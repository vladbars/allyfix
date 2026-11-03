import CoreAudio
import Foundation

/// Hears whether the Simulator played a sound, and what: a tap on the audio of the
/// Simulator's own processes. The level tells a sound from none, as the app's audio engine
/// stays running in silence once it has played anything; what was said is kept only while
/// the ear listens, to be written out as words.
nonisolated final class Ear: @unchecked Sendable {
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    private let lock = NSLock()
    private var loudest: Float = 0
    /// What was heard, as one channel, at the tap's rate; a minute at most.
    private var heard: [Float] = []
    private var rate: Double = 48000

    /// Above this peak a sound counts as played; JPEG-like noise in silence stays far below.
    static let threshold: Float = 0.01

    /// Starts listening to every process of the Simulator that has audio; nil when there is
    /// none yet, or macOS does not allow it.
    static func start() -> Ear? {
        let processes = simulatorProcesses()
        guard !processes.isEmpty else { return nil }
        let ear = Ear()
        return ear.listen(to: processes) ? ear : nil
    }

    /// Whether a sound played since the last time this was asked.
    func heardSomething() -> Bool {
        lock.lock()
        defer { loudest = 0; lock.unlock() }
        return loudest > Self.threshold
    }

    /// What was heard since listening began, as 16-bit mono WAV at 16 kHz, the form speech
    /// recognition takes; nil when it was silence.
    func recording() -> Data? {
        lock.lock()
        let samples = heard, rate = self.rate, loud = loudest
        lock.unlock()
        guard !samples.isEmpty, samples.contains(where: { abs($0) > Self.threshold }) || loud > Self.threshold else { return nil }
        let target = 16000.0
        let step = rate / target
        let count = Int(Double(samples.count) / step)
        var pcm = Data(capacity: count * 2)
        for index in 0..<count {
            let value = max(-1, min(1, samples[min(samples.count - 1, Int(Double(index) * step))]))
            var sample = Int16(value * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
        }
        var wav = Data("RIFF".utf8)
        func append<T>(_ value: T) { var v = value; withUnsafeBytes(of: &v) { wav.append(contentsOf: $0) } }
        append(UInt32(36 + pcm.count).littleEndian)
        wav += Data("WAVEfmt ".utf8)
        append(UInt32(16).littleEndian); append(UInt16(1).littleEndian); append(UInt16(1).littleEndian)
        append(UInt32(16000).littleEndian); append(UInt32(32000).littleEndian)
        append(UInt16(2).littleEndian); append(UInt16(16).littleEndian)
        wav += Data("data".utf8)
        append(UInt32(pcm.count).littleEndian)
        return wav + pcm
    }

    func stop() {
        if let proc { AudioDeviceStop(device, proc); AudioDeviceDestroyIOProcID(device, proc) }
        if device != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(device) }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        proc = nil
        device = AudioObjectID(kAudioObjectUnknown)
        tap = AudioObjectID(kAudioObjectUnknown)
    }

    deinit { stop() }

    private func listen(to processes: [AudioObjectID]) -> Bool {
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.isPrivate = true
        description.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr else { return false }
        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var formatAddress = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(tap, &formatAddress, 0, nil, &formatSize, &format) == noErr, format.mSampleRate > 0 { rate = format.mSampleRate }
        let settings: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Allyfix Ear",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        guard AudioHardwareCreateAggregateDevice(settings as CFDictionary, &device) == noErr else { stop(); return false }
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, device, DispatchQueue(label: "ear")) { [weak self] _, input, _, _, _ in
            guard let self else { return }
            var peak: Float = 0
            var mono: [Float] = []
            for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)) {
                guard let data = buffer.mData else { continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let channels = max(1, Int(buffer.mNumberChannels))
                for index in 0..<count { peak = max(peak, abs(samples[index])) }
                // Channels side by side: their mean is the one channel kept.
                for frame in 0..<(count / channels) {
                    var sum: Float = 0
                    for channel in 0..<channels { sum += samples[frame * channels + channel] }
                    mono.append(sum / Float(channels))
                }
            }
            self.lock.lock()
            self.loudest = max(self.loudest, peak)
            if self.heard.count < Int(self.rate * 60) { self.heard += mono }
            self.lock.unlock()
        }
        guard status == noErr, let proc, AudioDeviceStart(device, proc) == noErr else { stop(); return false }
        return true
    }

    /// Audio objects of processes that run inside the Simulator.
    static func simulatorProcesses() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects)
        return objects.filter { object in
            var pidAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(object, &pidAddress, 0, nil, &pidSize, &pid) == noErr else { return false }
            var path = [CChar](repeating: 0, count: 4096)
            proc_pidpath(pid, &path, 4096)
            return String(cString: path).contains("/CoreSimulator/")
        }
    }
}
