import CoreAudio
import Foundation

/// Hears whether the Simulator played a sound: a tap on the audio of the Simulator's own
/// processes, measured, never kept. The app's audio engine stays running in silence once it
/// has played anything, so only the level tells a sound from none.
nonisolated final class Ear: @unchecked Sendable {
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    private let lock = NSLock()
    private var loudest: Float = 0

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
            for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)) {
                guard let data = buffer.mData else { continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                for index in 0..<Int(buffer.mDataByteSize) / MemoryLayout<Float>.size { peak = max(peak, abs(samples[index])) }
            }
            self.lock.lock()
            self.loudest = max(self.loudest, peak)
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
