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
    /// The fix made for this screen's issues.
    var fix: Fixer.Run?
    /// The screen this one is the check after a fix of.
    var fixOf: ID?
    /// Where elements with flat frames are really drawn, found in the screenshot's pixels;
    /// optional, so screens kept before it existed still load.
    var inked: [Int: CGRect]?
    /// What people come to this screen to do, and how each persona fared at it.
    var tasks: [ScreenTask]?
    var personaRuns: [PersonaRun]?
    /// The app the screen belongs to, by name.
    var app: String?
    /// The labels pressed to get here from the app's first screen.
    var route: [String]?
    /// Tests kept from runs that succeeded after a fix, as files in the project.
    var savedTests: [String]?

    private enum CodingKeys: CodingKey {
        case id, date, screen, name, section, issues, reviewProblem, review, fix, fixOf, inked, tasks, personaRuns, app, route, savedTests
    }

    /// How a persona fared at a task, once it has tried.
    func run(_ persona: Persona, _ task: ScreenTask) -> PersonaRun? {
        personaRuns?.last { $0.persona == persona && $0.task == task }
    }

    var title: String { name ?? "Checking…" }

    /// Where elements whose frames miss them are really drawn, as the model saw them.
    var corrected: [Int: CGRect] {
        var places = review?.places ?? [:]
        for issue in issues where issue.kind == .wrongFrame && issue.drawn.count == issue.elements.count {
            for (id, place) in zip(issue.elements, issue.drawn) { places[id] = place }
        }
        // The pixels are exact where the model only estimates.
        return places.merging(inked ?? [:]) { _, ink in ink }
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

    /// More frames than this and an issue is shown as one outline around them all.
    static let mostFrames = 6

    /// What to draw for an issue: its frames, or, for what nobody sees or for many
    /// elements, one outline of the area, since frames over hidden things point at nothing.
    func outline(of issue: Issue) -> (frames: [CGRect], area: Bool) {
        let frames = frames(of: issue)
        guard issue.kind == .hidden || frames.count > Self.mostFrames, let first = frames.first else { return (frames, false) }
        return ([frames.dropFirst().reduce(first) { $0.union($1) }], true)
    }

    /// Where the selected issue's things are really drawn, shown dashed beside wrong frames.
    func drawn(_ id: Issue.ID?) -> [CGRect] {
        guard let issue = issues.first(where: { $0.id == id }), issue.kind == .wrongFrame else { return [] }
        let corrected = self.corrected
        let places = issue.elements.compactMap { corrected[$0] }
        return places.count == issue.elements.count ? places : issue.drawn
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
    /// The app's source, where fixes are made.
    private(set) var project = UserDefaults.standard.string(forKey: "project").map { Project(folder: URL(fileURLWithPath: $0)) }
    /// What the fix under way is doing, for the screen it is fixing.
    private(set) var fixing: (screen: CheckedScreen.ID, step: String)?
    private(set) var fixProblem: String?
    /// The persona test under way: which screen, and what it is doing.
    private(set) var testing: (screen: CheckedScreen.ID, step: String)?
    private(set) var testProblem: String?
    private var test: Task<Void, Never>?

    private let voice = AVSpeechSynthesizer()

    var selected: CheckedScreen? { screens.first { $0.id == selectedScreen } }

    init() {
        selectedScreen = screens.last?.id
    }

    /// The rules first, at once; then the model, which takes a few seconds, adds what only
    /// the picture shows.
    func check() {
        permitted = Simulator.permitted()
        problem = nil
        do {
            let checked = try capture()
            Task { await review(checked) }
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Reads the screen and lists it, before the model has looked.
    private func capture(fixOf before: CheckedScreen.ID? = nil) throws -> CheckedScreen {
        let screen = try Simulator.screen()
        if before == nil { Restart.forgetApp() }
        // The same screen again replaces the earlier check of it, unless that one was fixed.
        let labels = screen.elements.map(\.label)
        remove { $0.screen.elements.map(\.label) == labels && $0.fix == nil }
        var checked = CheckedScreen(screen: screen, issues: Audit.run(screen.elements))
        checked.fixOf = before
        screens.append(checked)
        selectedScreen = checked.id
        live = checked.id
        selectedIssue = nil
        return checked
    }

    private func review(_ checked: CheckedScreen) async {
        let id = checked.id
        do {
            let picture = try await Picture.take(device: checked.screen.device)
            let inked = checked.screen.elements.filter(\.isSliver).reduce(into: [Int: CGRect]()) { places, element in
                places[element.id] = Ink.below(element.frame, on: checked.screen, picture: picture.jpeg)
            }
            update(id) {
                $0.jpeg = picture.jpeg
                $0.picture = NSImage(data: picture.jpeg)
                $0.inked = inked
            }
            if let bundle = await Restart.foregroundApp() {
                let name = await Restart.appName(of: bundle)
                update(id) { $0.app = name }
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
            remove { $0.id != id && $0.name == name && $0.section == done.section && $0.app == done.app && !$0.reviewing && $0.fix == nil && $0.fixOf == nil }
        }
    }

    /// Has every persona Allyfix can play try the screen's main tasks, each from a fresh
    /// launch of the app, and keeps how each one fared.
    /// A screen kept from before is checked again first: personas need it open now.
    func testPersonas(tasks count: Int = 2, people: [Persona] = Persona.people) {
        guard testing == nil else { return }
        testProblem = nil
        var checked = selected
        if checked == nil || checked?.id != live {
            do {
                let old = selected
                var fresh = try capture()
                // The same screen tested again: one entry, not two.
                if let old {
                    update(fresh.id) {
                        $0.name = old.name
                        $0.section = old.section
                        $0.app = old.app
                    }
                    fresh.name = old.name
                    remove { $0.id == old.id && $0.fix == nil }
                }
                Task { await review(fresh) }
                checked = fresh
            } catch {
                testProblem = error.localizedDescription
                return
            }
        }
        guard let checked else { return }
        test = Task { await testPersonas(checked, count: count, people: people) }
    }

    func stopTesting() {
        test?.cancel()
    }

    private func testPersonas(_ checked: CheckedScreen, count: Int, people: [Persona]) async {
        let id = checked.id
        testing = (id, "Working out what this screen is for…")
        defer { testing = nil }
        do {
            let client = try ModelClient.fromEnvironment()
            let picture = try await Picture.take(device: checked.screen.device)
            let (tasks, usage) = try await Personas.tasks(on: checked.screen, picture: picture, client: client)
            let chosen = Array(tasks.prefix(count))
            update(id) {
                $0.tasks = chosen
                $0.personaRuns = []
            }
            // The way back to this screen after each restart, learned on the first one.
            var route: [String] = []
            var charged = false
            for task in chosen {
                // The control goes first: a task even it cannot do is not a test of access.
                for persona in [Persona.control] + people where persona.ready {
                    try Task.checkCancellation()
                    if persona != .control, screens.first(where: { $0.id == id })?.run(.control, task)?.achieved != true { break }
                    testing = (id, "\(persona.title): \(task.goal)…")
                    try await Restart.app()
                    let way = try await Navigator.reach(checked.screen, picture: picture.jpeg, name: checked.title, route: &route, client: client)
                    var run: PersonaRun
                    do {
                        run = try await Personas.run(persona, task: task, client: client) { [weak self] partial in
                            self?.keep(partial, in: id)
                        }
                        run.usage += way
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // One run that cannot finish does not stop the others.
                        run = PersonaRun(persona: persona, task: task)
                        run.problem = error.localizedDescription
                    }
                    // Working out the tasks is charged to the first run.
                    if !charged {
                        run.usage += usage
                        charged = true
                    }
                    keep(run, in: id)
                }
            }
            try await Restart.app()
            _ = try await Navigator.reach(checked.screen, picture: picture.jpeg, name: checked.title, route: &route, client: client)
            update(id) { $0.route = route }
        } catch is CancellationError {
            testProblem = "Stopped."
        } catch {
            testProblem = error.localizedDescription
        }
        if let done = screens.first(where: { $0.id == id }) { History.save(done) }
    }

    /// Puts a run, finished or under way, in the screen's list in place of its earlier self.
    private func keep(_ run: PersonaRun, in id: CheckedScreen.ID) {
        update(id) { checked in
            var runs = checked.personaRuns ?? []
            if let index = runs.firstIndex(where: { $0.id == run.id }) { runs[index] = run } else { runs.append(run) }
            checked.personaRuns = runs
        }
    }

    func chooseProject() {
        let panel = NSOpenPanel()
        panel.message = "Choose the folder of the app shown in the Simulator. Allyfix makes its fixes there on a new git branch."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        project = Project(folder: folder)
        UserDefaults.standard.set(folder.path, forKey: "project")
    }

    /// Has Muse Wonder fix the selected screen's issues, waits for the app to reload, and
    /// checks the screen again to prove it.
    func fix() {
        guard let checked = selected, fixing == nil else { return }
        if project == nil { chooseProject() }
        guard let project else { return }
        fixProblem = nil
        Task { await fix(checked, in: project) }
    }

    private func fix(_ checked: CheckedScreen, in project: Project) async {
        fixing = (checked.id, "Reading \(project.name) and writing fixes…")
        defer { fixing = nil }
        do {
            var run = try await Fixer.run(checked, project: project, client: ModelClient.fromEnvironment())
            update(checked.id) { $0.fix = run }
            fixing = (checked.id, "Waiting for \(project.name) to reload…")
            await waitForReload(from: checked.screen)
            fixing = (checked.id, "Checking the screen again…")
            let after = try capture(fixOf: checked.id)
            run.after = after.id
            update(checked.id) { $0.fix = run }
            if let fixed = screens.first(where: { $0.id == checked.id }) { History.save(fixed) }
            await review(after)
            try await proveFix(of: checked, after: after.id, in: project)
        } catch {
            fixProblem = error.localizedDescription
        }
    }

    /// The same people try the same tasks they could not do before, from the same start, and
    /// the control tries them too, since a fix must not break normal use. Each success is
    /// kept as a test in the project, on the fix's branch.
    private func proveFix(of before: CheckedScreen, after id: CheckedScreen.ID, in project: Project) async throws {
        let stuck = (before.personaRuns ?? []).filter { $0.achieved == false && $0.persona != .control }
        guard !stuck.isEmpty, let start = screens.first(where: { $0.id == id }) else { return }
        let client = try ModelClient.fromEnvironment()
        let picture = try await Picture.take(device: start.screen.device)
        var route = before.route ?? []
        update(id) {
            $0.tasks = before.tasks
            $0.personaRuns = []
        }
        var tests: [String] = []
        let tries = Set(stuck.map(\.task)).flatMap { task in [(Persona.control, task)] + stuck.filter { $0.task == task }.map { ($0.persona, task) } }
        for (persona, task) in tries {
            fixing = (before.id, "Checking the fix: \(persona.title), \(task.goal)…")
            try await Restart.app()
            let way = try await Navigator.reach(start.screen, picture: picture.jpeg, name: start.title, route: &route, client: client)
            var run = try await Personas.run(persona, task: task, client: client) { [weak self] partial in self?.keep(partial, in: id) }
            run.usage += way
            keep(run, in: id)
            if persona != .control, let test = SavedTest(run, screen: start.title, route: route) {
                tests.append(try test.save(in: project.folder).lastPathComponent)
            }
        }
        if !tests.isEmpty {
            try project.commit("Add accessibility tests for \(start.title)\n\n" + tests.map { "- allyfix/tests/\($0)" }.joined(separator: "\n"))
        }
        update(id) {
            $0.route = route
            $0.savedTests = tests
        }
        if let done = screens.first(where: { $0.id == id }) { History.save(done) }
    }

    /// Fast Refresh and hot reload show the change within seconds; a native app needs to
    /// be run again, and the check then shows the screen as it was.
    private func waitForReload(from before: Screen) async {
        let labels = before.elements.map(\.label)
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(500))
            if let now = try? Simulator.screen(), now.elements.map(\.label) != labels {
                // Let the reload settle before reading the screen for good.
                try? await Task.sleep(for: .milliseconds(800))
                return
            }
        }
    }

    /// Throws the fix away: back to the branch it started from, and the check after it gone.
    func undoFix(of id: CheckedScreen.ID) {
        guard let run = screens.first(where: { $0.id == id })?.fix, let project else { return }
        do {
            try project.undo(branch: run.branch, base: run.base)
            if let after = run.after { remove { $0.id == after } }
            update(id) { $0.fix = nil }
            if let before = screens.first(where: { $0.id == id }) { History.save(before) }
            selectedScreen = id
        } catch {
            fixProblem = error.localizedDescription
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
