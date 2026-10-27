import AVFoundation
import Observation

/// What the window shows: the screen last checked and what is wrong on it.
@Observable
final class Checker {
    enum State {
        case idle
        case checked
        case failed(String)
    }

    private(set) var state = State.idle
    private(set) var screen: Screen?
    private(set) var issues: [Issue] = []
    var permitted = Simulator.permitted()

    private let voice = AVSpeechSynthesizer()

    func check() {
        permitted = Simulator.permitted()
        do {
            let screen = try Simulator.screen()
            self.screen = screen
            issues = Audit.run(screen.elements)
            state = .checked
        } catch {
            screen = nil
            issues = []
            state = .failed(error.localizedDescription)
        }
    }

    func askPermission() {
        permitted = Simulator.permitted(ask: true)
    }

    /// Says an element the way VoiceOver would, so it can be heard as a blind person hears it.
    func speak(_ issue: Issue) {
        guard let id = issue.elements.first, let element = screen?.elements.first(where: { $0.id == id }) else { return }
        voice.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: Audit.spoken(element))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
        voice.speak(utterance)
    }
}
