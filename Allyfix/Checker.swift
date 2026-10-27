import AppKit
import AVFoundation
import Observation

/// One screen checked: what it looked like, what VoiceOver read on it, and what is wrong.
struct CheckedScreen: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    let screen: Screen
    /// The screenshot, as sent to the model and kept on disk.
    var jpeg: Data?
    var picture: NSImage?
    /// What the model calls the screen, once it has seen it.
    var name: String?
    /// The tab the screen is under.
    var section: String?
    var issues: [Issue]
    /// Whether the model is still looking at it.
    var reviewing = true
    /// Why the model's check did not happen; the rules' issues still stand.
    var reviewProblem: String?
    /// What the model found, cost and took, once it is done.
    var review: Review.Seen?

    private enum CodingKeys: CodingKey {
        case id, date, screen, name, section, issues, reviewProblem, review
    }

    var title: String { name ?? "Checking…" }

    /// Where elements whose frames miss them are really drawn, as the model saw them.
    var corrected: [Int: CGRect] {
        var places = review?.places ?? [:]
        for issue in issues where issue.kind == .wrongFrame && issue.drawn.count == issue.elements.count {
            for (id, place) in zip(issue.elements, issue.drawn) { places[id] = place }
        }
        return places
    }

    /// Where to frame an issue, on the Mac's screen: each element it is about where it is
    /// drawn, or the places of what VoiceOver does not see.
    func frames(of issue: Issue) -> [CGRect] {
        if issue.elements.isEmpty { return issue.drawn.isEmpty ? [issue.frame] : issue.drawn }
        // An issue about wrong frames shows the frames themselves; any other, the things.
        if issue.kind == .wrongFrame { return issue.elements.compactMap { id in screen.elements.first { $0.id == id }?.frame } }
        let corrected = self.corrected
        let seen = issue.drawn.count == issue.elements.count ? issue.drawn : []
        return issue.elements.enumerated().compactMap { index, id in
            let places = [corrected[id], index < seen.count ? seen[index] : nil].compactMap { $0 }
            guard let frame = screen.elements.first(where: { $0.id == id })?.frame else { return places.first }
            // The model's place is rougher than the element's frame; it wins only when the
            // frame plainly misses the thing. A place that is the frame again corrects nothing.
            return places.first { frame.overlap($0) < 0.5 } ?? frame
        }
    }

    /// Where the selected issue's things are really drawn, shown dashed beside wrong frames.
    func drawn(_ id: Issue.ID?) -> [CGRect] {
        guard let issue = issues.first(where: { $0.id == id }), issue.kind == .wrongFrame else { return [] }
        return issue.drawn
    }
}

/// What the window shows: the screens checked so far and what is wrong on them.
@Observable
final class Checker {
    private(set) var screens = History.load()
    var selectedScreen: CheckedScreen.ID?
    var selectedIssue: Issue.ID?
    private(set) var problem: String?
    var permitted = Simulator.permitted()
    /// The screen checked last in this launch, which the Simulator most likely still shows.
    private(set) var live: CheckedScreen.ID?

    private let voice = AVSpeechSynthesizer()

    var selected: CheckedScreen? { screens.first { $0.id == selectedScreen } }
    /// What the model has cost for the screens kept.
    var spent: Double { screens.compactMap { $0.review?.usage.cost }.reduce(0, +) }

    init() {
        selectedScreen = screens.last?.id
    }

    /// The rules first, at once; then the model, which takes a few seconds, adds what only
    /// the picture shows.
    func check() {
        permitted = Simulator.permitted()
        problem = nil
        let screen: Screen
        do {
            screen = try Simulator.screen()
        } catch {
            problem = error.localizedDescription
            return
        }
        // The same screen again replaces the earlier check of it.
        let labels = screen.elements.map(\.label)
        remove { $0.screen.elements.map(\.label) == labels }
        let checked = CheckedScreen(screen: screen, issues: Audit.run(screen.elements))
        screens.append(checked)
        selectedScreen = checked.id
        live = checked.id
        selectedIssue = nil
        Task { await review(checked) }
    }

    private func review(_ checked: CheckedScreen) async {
        let id = checked.id
        do {
            let picture = try await Picture.take(device: checked.screen.device)
            update(id) {
                $0.jpeg = picture.jpeg
                $0.picture = NSImage(data: picture.jpeg)
            }
            let client = try ModelClient.fromEnvironment()
            let seen = try await Review.run(checked.screen, picture: picture, found: checked.issues, client: client)
            update(id) {
                $0.issues = Audit.combine(checked.screen.elements, seen: seen.issues)
                $0.name = seen.name
                $0.section = seen.section
                $0.review = seen
            }
        } catch {
            update(id) { $0.reviewProblem = error.localizedDescription }
        }
        update(id) { $0.reviewing = false }
        // Point at the worst problem first, on the Simulator too.
        if selectedScreen == id, selectedIssue == nil {
            selectedIssue = screens.first { $0.id == id }?.issues.first?.id
        }
        guard let done = screens.first(where: { $0.id == id }) else { return }
        History.save(done)
        // A screen checked twice under different element lists is still one screen.
        if let name = done.name {
            remove { $0.id != id && $0.name == name && $0.section == done.section && !$0.reviewing }
        }
    }

    func delete(_ id: CheckedScreen.ID) {
        remove { $0.id == id }
        if selectedScreen == id { selectedScreen = screens.last?.id }
    }

    private func remove(where matches: (CheckedScreen) -> Bool) {
        for checked in screens where matches(checked) {
            History.delete(checked.id)
        }
        screens.removeAll(where: matches)
    }

    private func update(_ id: CheckedScreen.ID, _ change: (inout CheckedScreen) -> Void) {
        guard let index = screens.firstIndex(where: { $0.id == id }) else { return }
        change(&screens[index])
    }

    func askPermission() {
        permitted = Simulator.permitted(ask: true)
    }

    /// Says an element the way VoiceOver would, so it can be heard as a blind person hears it.
    func speak(_ issue: Issue) {
        guard let id = issue.elements.first, let element = selected?.screen.elements.first(where: { $0.id == id }) else { return }
        voice.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: Audit.spoken(element))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
        voice.speak(utterance)
    }
}
