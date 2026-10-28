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
        var places = review?.places.flatMap { $0 } ?? [:]
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

/// What the window shows: the apps tested, their screens, and what is wrong on them.
@Observable
final class Checker {
    /// What the sidebar has picked: an app's overview, or one of its screens.
    enum Selection: Hashable {
        case app(String)
        case screen(CheckedScreen.ID)
        /// A fix, by the check it was made from.
        case fix(CheckedScreen.ID)
    }

    /// Screens whose app Allyfix could not tell.
    static let unknownApp = "Other screens"

    private(set) var screens = History.load()
    var selection: Selection? {
        didSet {
            guard !goingBack, let oldValue, oldValue != selection, visited.last != oldValue else { return }
            visited = Array((visited + [oldValue]).suffix(50))
        }
    }
    var selectedIssue: Issue.ID?

    /// Where the person has been, the latest last: the Back button goes there.
    private(set) var visited: [Selection] = []
    private var goingBack = false

    /// Where Back leads: the last place visited that is still there.
    var previous: Selection? {
        visited.last { exists($0) }
    }

    func goBack() {
        while let last = visited.popLast() {
            guard exists(last) else { continue }
            goingBack = true
            selection = last
            goingBack = false
            return
        }
    }

    private func exists(_ place: Selection) -> Bool {
        switch place {
        case .app(let app): apps.contains(app)
        case .screen(let id): screens.contains { $0.id == id }
        case .fix(let id): screens.contains { $0.id == id && $0.fix != nil }
        }
    }

    /// A place in words, as the Back button and the path at the top of a page name it.
    func name(of place: Selection) -> String {
        switch place {
        case .app(let app): app
        case .screen(let id): screens.first { $0.id == id }?.title ?? "Screen"
        case .fix(let id): "Fix of " + (screens.first { $0.id == id }?.title ?? "a screen")
        }
    }

    var selectedScreen: CheckedScreen.ID? {
        get { if case .screen(let id) = selection { id } else { nil } }
        set { selection = newValue.map { .screen($0) } }
    }

    var selectedApp: String? {
        switch selection {
        case .app(let name): name
        case .screen(let id), .fix(let id): screens.first { $0.id == id }.map(Self.app)
        case nil: nil
        }
    }

    static func app(of checked: CheckedScreen) -> String { checked.app ?? unknownApp }

    /// Apps by the time they were last checked, latest first.
    var apps: [String] {
        var latest: [String: Date] = [:]
        for checked in screens { latest[Self.app(of: checked)] = max(latest[Self.app(of: checked)] ?? .distantPast, checked.date) }
        return latest.keys.sorted { latest[$0]! > latest[$1]! }
    }

    func screens(of app: String) -> [CheckedScreen] {
        screens.filter { Self.app(of: $0) == app }
    }

    /// An app's fixes, latest first, by the checks they were made from.
    /// The kept fix made for a task someone could not do: the barrier counts as gone, until
    /// people are tested again.
    func keptFix(for run: PersonaRun) -> CheckedScreen? {
        screens.first { $0.fix?.kept == true && $0.fix?.stuck?.contains(run.id) == true }
    }

    func fixes(of app: String) -> [CheckedScreen] {
        screens(of: app).filter { $0.fix != nil }.sorted { $0.date > $1.date }
    }

    /// How many of the problems a fix set out to close the check after it no longer finds:
    /// the same kind of problem on the same things, by what VoiceOver reads for them.
    static func gone(_ keys: [String], before: CheckedScreen, after: CheckedScreen) -> Int {
        keys.filter { key in
            guard let issue = before.issues.first(where: { fixKey(before.id, $0.id) == key }) else { return false }
            let labels = Set(issue.elements.compactMap { id in before.screen.elements.first { $0.id == id }?.readableLabel })
            return !after.issues.contains { other in
                other.kind.topic == issue.kind.topic
                    && !labels.isDisjoint(with: other.elements.compactMap { id in after.screen.elements.first { $0.id == id }?.readableLabel })
            }
        }.count
    }

    /// Whether the check after a fix confirms it: every problem it set out to close gone,
    /// and everyone who was stuck now through. Nil until checked.
    func verified(_ fixed: CheckedScreen) -> Bool? {
        guard let run = fixed.fix, let after = screens.first(where: { $0.id == run.after }), !after.reviewing else { return nil }
        let keys = run.fixed ?? []
        return Self.gone(keys, before: fixed, after: after) == keys.count
            && (after.personaRuns ?? []).filter { $0.persona != .control }.allSatisfy { $0.achieved == true }
    }

    /// One entry per screen of an app: its latest check, the check after a fix included,
    /// since that is how the screen is now; in the order screens were found.
    func latestScreens(of app: String) -> [CheckedScreen] {
        let all = screens(of: app)
        return all.filter { checked in !all.contains { $0.id != checked.id && Self.same($0, checked) && $0.date > checked.date } }
    }

    /// The latest check of the same screen.
    func latest(of checked: CheckedScreen) -> CheckedScreen {
        versions(of: checked).first ?? checked
    }

    /// Every check of the same screen, latest first, the checks after fixes included.
    func versions(of checked: CheckedScreen) -> [CheckedScreen] {
        screens.filter { $0.id == checked.id || Self.same($0, checked) }.sorted { $0.date > $1.date }
    }

    /// The last time people were tested on this screen: what they could not do there holds
    /// until a fix changes the code, and a fix tests them again.
    func lastTest(of checked: CheckedScreen) -> CheckedScreen? {
        versions(of: checked).first { $0.tasks != nil }
    }

    /// Writes what was found in an app for coding agents into its source, or wherever the
    /// person chooses when the source is not set; shows the file in the Finder.
    func writeAgentReport(for app: String) {
        guard let folder = reportFolder(for: app, what: "the report") else { return }
        do {
            let file = try AgentReport.write(AgentReport.findings(of: app, checker: self), to: folder)
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } catch {
            problem = "Could not write the report: \(error.localizedDescription)"
        }
    }

    /// Writes the BFSG accessibility information and the conformance report, as Markdown to
    /// edit and as PDF to send, next to the report for agents; shows the PDFs in the Finder.
    func writeComplianceReports(for app: String) {
        guard let folder = reportFolder(for: app, what: "the compliance reports") else { return }
        do {
            let files = try Compliance.write(Compliance.facts(of: app, checker: self), to: folder)
            NSWorkspace.shared.activateFileViewerSelecting(files)
        } catch {
            problem = "Could not write the reports: \(error.localizedDescription)"
        }
    }

    /// The app's source, or wherever the person chooses when it is not set.
    private func reportFolder(for app: String, what: String) -> URL? {
        if let folder = project(for: app)?.folder { return folder }
        let panel = NSOpenPanel()
        panel.message = "Choose where to write \(what) for \(app)."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Two checks are of the same screen when one is the check after a fix of the other, or
    /// the model named them alike in the same app.
    static func same(_ a: CheckedScreen, _ b: CheckedScreen) -> Bool {
        if a.fixOf == b.id || b.fixOf == a.id { return true }
        return a.name != nil && a.name == b.name && a.section == b.section && app(of: a) == app(of: b)
    }

    /// Each app's source, where its fixes are made, by app name.
    private(set) var projects = UserDefaults.standard.dictionary(forKey: "projects") as? [String: String] ?? [:]

    func project(for app: String?) -> Project? {
        app.flatMap { projects[$0] }.map { Project(folder: URL(fileURLWithPath: $0)) }
    }

    /// The app being explored, and what the explorer is doing.
    var exploring: (app: String?, step: String)?
    var exploreProblem: String?
    var explore: Task<Void, Never>?
    /// Saved tests run again, by file name: nil while running, then the result.
    var savedResults: [String: SavedTest.Result?] = [:]
    /// The latest run of the checks that need no model, per app: under way or done.
    var checkRuns: [String: CheckRun] = [:]
    var checkTask: Task<Void, Never>?
    /// Apps whose code is watched: a change runs the checks again.
    var watching: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "watching") ?? [])
    /// What the code looked like at the last look, per app, to tell when it changed.
    var codeStamps: [String: String] = [:]
    var watchTimer: Timer?
    private(set) var problem: String?
    var permitted = Simulator.permitted()
    /// The screen checked last in this launch, which the Simulator most likely still shows.
    private(set) var live: CheckedScreen.ID?
    /// What the fix under way is doing, for the screen it is fixing.
    private(set) var fixing: (screen: CheckedScreen.ID, step: String)?
    /// How far the fix under way has got: 1 writing it, 2 waiting for the app to reload,
    /// 3 checking the screen again, 4 the people who were stuck trying again.
    private(set) var fixStage = 0
    /// What the fix under way was asked to fix, as the screens went to the fixer.
    private(set) var fixRequest: [CheckedScreen] = []
    private(set) var fixProblem: String?
    /// The persona test under way: which screen, and what it is doing.
    private(set) var testing: (screen: CheckedScreen.ID, step: String)?
    private(set) var testProblem: String?
    private var test: Task<Void, Never>?

    private let voice = AVSpeechSynthesizer()

    var selected: CheckedScreen? { screens.first { $0.id == selectedScreen } }

    init() {
        selection = apps.first.map { .app($0) }
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
    func capture(fixOf before: CheckedScreen.ID? = nil, select: Bool = true) throws -> CheckedScreen {
        let screen = try Simulator.screen()
        if before == nil, select { Restart.forgetApp() }
        // The same screen again replaces a plain earlier check of it; a check people were
        // tested on, or that a fix was made from or checked after, stays as history.
        let labels = screen.elements.map(\.label)
        let replaced = screens.filter { $0.screen.elements.map(\.label) == labels && Self.plain($0) }
        remove { $0.screen.elements.map(\.label) == labels && Self.plain($0) }
        var checked = CheckedScreen(screen: screen, issues: Audit.run(screen.elements))
        checked.fixOf = before
        // What the walk learned about the screen stays: the way to it.
        checked.route = replaced.lazy.compactMap(\.route).first
        // Listed under the app being looked at, or the last one checked, until the Simulator's
        // log says which app it is; that takes a few seconds.
        checked.app = before.flatMap { id in screens.first { $0.id == id }?.app } ?? selectedApp.flatMap { $0 != Self.unknownApp ? $0 : nil }
            ?? screens.filter { $0.app != nil && $0.app != Self.unknownApp }.max { $0.date < $1.date }?.app
        screens.append(checked)
        live = checked.id
        if select {
            selectedScreen = checked.id
            selectedIssue = nil
        }
        return checked
    }

    func review(_ checked: CheckedScreen) async {
        guard let picture = await snap(checked) else { return }
        await think(checked, picture: picture)
    }

    /// The part of a check that needs the screen still shown: its picture and its app.
    func snap(_ checked: CheckedScreen) async -> Picture? {
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
            return picture
        } catch {
            update(id) {
                $0.reviewProblem = error.localizedDescription
                $0.reviewing = false
            }
            return nil
        }
    }

    /// The part of a check that can run while the Simulator moves on: the model's look.
    func think(_ checked: CheckedScreen, picture: Picture) async {
        let id = checked.id
        do {
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
            remove { $0.id != id && $0.name == name && $0.section == done.section && $0.app == done.app && !$0.reviewing && Self.plain($0) }
        }
    }

    /// Has every persona Allyfix can play try the screen's main tasks, each from a fresh
    /// launch of the app, and keeps how each one fared.
    /// A screen kept from before is checked again first: personas need it open now.
    func testPersonas(tasks count: Int = 2, people: [Persona] = Persona.people) {
        guard testing == nil else { return }
        testProblem = nil
        let old = selected
        test = Task { await test(old, count: count, people: people, select: true) }
    }

    /// Several screens tested one after another, each opened in the Simulator in turn.
    private(set) var testQueue: (done: Int, total: Int)?

    func testPeople(on ids: [CheckedScreen.ID]) {
        guard !busy else { return }
        testProblem = nil
        let targets = ids.compactMap { id in screens.first { $0.id == id } }
        testQueue = (0, targets.count)
        test = Task {
            defer { testQueue = nil }
            for (index, old) in targets.enumerated() {
                if Task.isCancelled { break }
                testQueue = (index, targets.count)
                await test(old, count: 2, people: Persona.people, select: false)
            }
        }
    }

    /// Tests people on a screen; one checked before is opened again from a fresh start and
    /// checked anew first, since people need it on the Simulator.
    private func test(_ old: CheckedScreen?, count: Int, people: [Persona], select: Bool) async {
        var checked: CheckedScreen
        if let old, old.id == live {
            checked = old
        } else {
            do {
                if let old {
                    testing = (old.id, "Opening \(old.title) in the Simulator…")
                    try await Restart.app()
                    var route = old.route ?? versions(of: old).lazy.compactMap(\.route).first ?? []
                    if let jpeg = old.jpeg {
                        _ = try await Navigator.reach(old.screen, picture: jpeg, name: old.title, route: &route, client: ModelClient.fromEnvironment())
                    }
                    testing = nil
                }
                var fresh = try capture(select: select)
                if let old {
                    let route = old.route ?? versions(of: old).lazy.compactMap(\.route).first
                    update(fresh.id) {
                        $0.name = old.name
                        $0.section = old.section
                        $0.app = old.app
                        $0.route = $0.route ?? route
                    }
                    fresh.name = old.name
                    fresh.section = old.section
                    fresh.app = old.app
                    if Self.plain(old) { remove { $0.id == old.id } }
                }
                Task { await review(fresh) }
                checked = fresh
            } catch {
                testing = nil
                testProblem = error.localizedDescription
                return
            }
        }
        await testPersonas(checked, count: count, people: people)
    }

    /// A check with nothing but what it found: no people tested on it, no fix made from it,
    /// not the check after a fix. Another check of the same screen can take its place.
    static func plain(_ checked: CheckedScreen) -> Bool {
        checked.tasks == nil && checked.fix == nil && checked.fixOf == nil
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
                    if persona != .control, let control = screens.first(where: { $0.id == id })?.run(.control, task), control.achieved != true {
                        // Said plainly: nobody else tries what even the control could not do.
                        if let problem = control.problem { testProblem = "Stopped: \(problem) Nobody else tried \(task.goal.lowercasedFirst)." }
                        break
                    }
                    testing = (id, "\(persona.title): \(task.goal)…")
                    var run: PersonaRun
                    do {
                        run = try await Personas.attempt(persona, task: task, at: persona.textSize, start: checked.screen, picture: picture.jpeg, name: checked.title, route: &route, client: client) { [weak self] partial in
                            self?.keep(partial, in: id)
                        }
                        if run.achieved == false, let size = run.textSize {
                            keep(run, in: id)
                            testing = (id, "\(persona.title): finding the text size where \(task.goal.lowercasedFirst) stops working…")
                            // The search only adds to the failure: when it cannot finish, the failure stands without it.
                            do {
                                let (boundary, usage) = try await Personas.boundary(of: task, upTo: size) { size in
                                    try await Personas.attempt(.control, task: task, at: size, start: checked.screen, picture: picture.jpeg, name: checked.title, route: &route, client: client)
                                }
                                run.boundary = boundary
                                run.usage += usage
                            } catch is CancellationError {
                                throw CancellationError()
                            } catch {}
                        }
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
                    // Someone who got through what a kept fix was made for: that becomes a test.
                    if run.achieved == true, persona != .control, versions(of: checked).contains(where: { version in
                        (version.personaRuns ?? []).contains { $0.persona == persona && $0.task.goal == task.goal && $0.achieved == false && keptFix(for: $0) != nil }
                    }), let now = screens.first(where: { $0.id == id }) {
                        keepAsTest(run, on: now, route: route)
                    }
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

    /// Keeps a task someone managed as a test in the app's source, committed on its own:
    /// nothing else changed in the source goes with it.
    @discardableResult
    func keepAsTest(_ run: PersonaRun, on checked: CheckedScreen, route: [String]? = nil) -> Bool {
        guard let project = project(for: Self.app(of: checked)) else {
            testProblem = "Choose the app's source folder first: tests are kept there."
            return false
        }
        let way = route ?? checked.route ?? versions(of: checked).lazy.compactMap(\.route).first ?? []
        guard let test = SavedTest(run, screen: checked.title, route: way) else {
            testProblem = "Nothing VoiceOver reads tells that this task is done, so it cannot be checked without a model."
            return false
        }
        do {
            let file = try test.save(in: project.folder)
            try project.commit("Add accessibility test: \(run.persona.title) can \(run.task.goal.lowercasedFirst)", only: ["allyfix/tests/" + file.lastPathComponent])
            update(checked.id) { $0.savedTests = Array(Set(($0.savedTests ?? []) + [file.lastPathComponent])).sorted() }
            if let done = screens.first(where: { $0.id == checked.id }) { History.save(done) }
            return true
        } catch {
            testProblem = "Could not keep the test: \(error.localizedDescription)"
            return false
        }
    }

    /// Whether a run is already kept as a test in the app's source.
    func isKept(_ run: PersonaRun, on checked: CheckedScreen) -> Bool {
        guard let project = project(for: Self.app(of: checked)), let test = SavedTest(run, screen: checked.title, route: []) else { return false }
        return FileManager.default.fileExists(atPath: project.folder.appending(path: "allyfix/tests/" + test.fileName).path)
    }

    /// Puts a run, finished or under way, in the screen's list in place of its earlier self.
    private func keep(_ run: PersonaRun, in id: CheckedScreen.ID) {
        update(id) { checked in
            var runs = checked.personaRuns ?? []
            if let index = runs.firstIndex(where: { $0.id == run.id }) { runs[index] = run } else { runs.append(run) }
            checked.personaRuns = runs
        }
    }

    /// Asks where an app's source is; fixes for it are made there, on a new git branch.
    func chooseProject(for app: String) {
        let panel = NSOpenPanel()
        panel.message = "Choose the folder with \(app)'s source. Allyfix makes its fixes there, on a new git branch."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        projects[app] = folder.path
        UserDefaults.standard.set(projects, forKey: "projects")
    }

    /// What the person ticked or unticked for the next fix, by `fixKey`. Untouched, only the
    /// tasks people got stuck at are ticked: a fix of everything found at once is too big to
    /// review, and what stopped people matters most.
    var choices: [String: Bool] = [:]

    func isTicked(_ key: String, stuck: Bool) -> Bool {
        choices[key] ?? stuck
    }

    static func fixKey(_ screen: CheckedScreen.ID, _ thing: String) -> String { "\(screen)/\(thing)" }

    /// A screen with the people's results from the last test before any fix, when this check
    /// has none: the code is the same until a fix changes it.
    func withEarlierTest(_ checked: CheckedScreen) -> CheckedScreen {
        var with = checked
        if with.personaRuns == nil, let tested = lastTest(of: checked) {
            with.tasks = tested.tasks
            with.personaRuns = tested.personaRuns
            with.route = with.route ?? tested.route
        }
        return with
    }

    /// A screen as it goes to the fixer: the problems and failed tasks still ticked.
    func chosen(_ checked: CheckedScreen) -> CheckedScreen {
        var chosen = withEarlierTest(checked)
        chosen.issues = checked.issues.filter { isTicked(Self.fixKey(checked.id, $0.id), stuck: false) }
        chosen.personaRuns = chosen.personaRuns?.filter { $0.achieved != false || $0.persona == .control || isTicked(Self.fixKey(checked.id, $0.id.uuidString), stuck: true) }
        return chosen
    }

    /// Ready-made choices of what to fix; single ticks fine-tune them.
    enum Pick: String, CaseIterable {
        case all = "Select All"
        case blocking = "Blocking Only"
        case people = "What Stopped People"
        case none = "Select None"
    }

    /// Ticks what a pick covers on the given screens and unticks the rest. What stopped
    /// people always blocks them, so it counts as blocking too.
    func pick(_ pick: Pick, on screens: [CheckedScreen]) {
        for checked in screens {
            let all = Self.fixKeys(withEarlierTest(checked))
            for (key, blocker) in all.issues {
                choices[key] = pick == .all || (pick == .blocking && blocker)
            }
            for key in all.stuck { choices[key] = pick != .none }
        }
    }

    /// The keys of everything on a chosen screen that a fix can take: its problems, with
    /// whether each blocks, and the tasks people got stuck at.
    static func fixKeys(_ checked: CheckedScreen) -> (issues: [(key: String, blocker: Bool)], stuck: [String]) {
        let issues = checked.issues.map { (fixKey(checked.id, $0.id), $0.severity == .blocker) }
        let stuck = (checked.personaRuns ?? []).filter { $0.achieved == false && $0.persona != .control }.map { fixKey(checked.id, $0.id.uuidString) }
        return (issues, stuck)
    }

    /// Whether a chosen screen has anything left to fix.
    static func hasWork(_ checked: CheckedScreen) -> Bool {
        !checked.issues.isEmpty || (checked.personaRuns ?? []).contains { $0.achieved == false && $0.persona != .control }
    }

    /// Fixes what is ticked on the selected screen.
    func fix() {
        guard let checked = selected, Self.hasWork(chosen(checked)) else { return }
        fix([chosen(checked)])
    }

    /// Fixes one task someone could not do, and nothing else.
    func fix(stuck run: PersonaRun, on checked: CheckedScreen) {
        var only = withEarlierTest(checked)
        only.issues = []
        only.personaRuns = only.personaRuns?.filter { $0.id == run.id || $0.persona == .control }
        fix([only])
    }

    /// The fix made for a task someone could not do, if there is one and it is not undone.
    func fix(for run: PersonaRun, in app: String) -> CheckedScreen? {
        fixes(of: app).first { $0.fix?.stuck?.contains(run.id) == true }
    }

    /// Fixes what is ticked on every screen of an app, in one go.
    /// What a fix of these screens would take: everything found and the tasks people could
    /// not do, or only what blocks someone.
    func work(on ids: Set<CheckedScreen.ID>, blockingOnly: Bool) -> [CheckedScreen] {
        screens.filter { ids.contains($0.id) }.map { checked in
            var with = withEarlierTest(checked)
            if blockingOnly { with.issues = with.issues.filter { $0.severity == .blocker } }
            with.personaRuns = with.personaRuns?.filter { $0.persona == .control || $0.achieved != false || keptFix(for: $0) == nil }
            return with
        }.filter(Self.hasWork)
    }

    /// Fixes the chosen screens in one go, on one branch.
    func fix(screens ids: Set<CheckedScreen.ID>, blockingOnly: Bool) {
        fix(work(on: ids, blockingOnly: blockingOnly))
    }

    func fixSelected(in app: String) {
        fix(latestScreens(of: app).map(chosen).filter(Self.hasWork))
    }

    /// Has Muse Wonder fix the chosen problems on the given screens, waits for the app to
    /// reload, checks each screen again, and has the people who got stuck try again.
    private func fix(_ screens: [CheckedScreen]) {
        guard let first = screens.first, fixing == nil, testing == nil, exploring == nil else { return }
        let app = Self.app(of: first)
        if project(for: app) == nil { chooseProject(for: app) }
        guard let project = project(for: app) else { return }
        fixProblem = nil
        fixRequest = screens
        fixing = (first.id, "Starting…")
        fixStage = 1
        // The fix's own page follows it from the start: its steps, then the result.
        selection = .fix(first.id)
        Task { await fix(screens, in: project) }
    }

    private func fix(_ screens: [CheckedScreen], in project: Project) async {
        let lead = screens[0].id
        defer {
            fixing = nil
            fixStage = 0
        }
        do {
            let app = Self.app(of: screens[0])
            fixing = (lead, "Muse Wonder is reading \(app)'s code and writing a fix for \(screens.count == 1 ? screens[0].title : "\(screens.count) screens")…")
            let shown = try? Simulator.screen()
            let run = try await Fixer.run(screens, project: project, client: ModelClient.fromEnvironment())
            for checked in screens {
                update(checked.id) { $0.fix = run }
                // Kept at once: the commit is made, whatever happens to the check after it.
                if let fixed = self.screens.first(where: { $0.id == checked.id }) { History.save(fixed) }
            }
            refreshBranch(of: app)
            fixStage = 2
            fixing = (lead, "Waiting for \(app) to reload in the Simulator…")
            if let shown { await waitForReload(from: shown) }
            let client = try ModelClient.fromEnvironment()
            for checked in screens {
                try await afterFix(checked, run: run, in: project, client: client, lead: lead, fresh: screens.count > 1 || checked.id != live, select: false)
            }
            refreshBranch(of: Self.app(of: screens[0]))
        } catch {
            fixProblem = error.localizedDescription
        }
    }

    /// The check after a fix, for one screen: it is opened from a fresh start when it may not
    /// be shown, checked again, and the people who got stuck there try again.
    private func afterFix(_ checked: CheckedScreen, run: Fixer.Run, in project: Project, client: ModelClient, lead: CheckedScreen.ID, fresh: Bool, select: Bool) async throws {
        fixStage = 3
        fixing = (lead, "Checking \(checked.title) again…")
        if fresh {
            var route = checked.route ?? []
            try await Restart.app()
            if let jpeg = checked.jpeg {
                _ = try await Navigator.reach(checked.screen, picture: jpeg, name: checked.title, route: &route, client: client)
            }
        }
        let after = try capture(fixOf: checked.id, select: select)
        var mine = run
        mine.after = after.id
        update(checked.id) { $0.fix = mine }
        if let fixed = screens.first(where: { $0.id == checked.id }) { History.save(fixed) }
        await review(after)
        try await proveFix(of: checked, after: after.id, in: project)
    }

    /// Does the check after a fix again, when it could not be done then: the app was not
    /// running, or the screen could not be reached.
    func checkAfterFix(of id: CheckedScreen.ID) {
        guard let checked = screens.first(where: { $0.id == id }), let run = checked.fix, fixing == nil,
              let project = project(for: Self.app(of: checked)) else { return }
        fixProblem = nil
        Task {
            defer { fixing = nil }
            do {
                try await afterFix(withEarlierTest(checked), run: run, in: project, client: ModelClient.fromEnvironment(), lead: id, fresh: true, select: false)
            } catch {
                fixProblem = error.localizedDescription
            }
        }
    }

    /// The people who were stuck try again after a fix, when that could not be done then.
    func tryAgainAfterFix(of id: CheckedScreen.ID) {
        guard let checked = screens.first(where: { $0.id == id }), let after = checked.fix?.after, fixing == nil, testing == nil,
              let project = project(for: Self.app(of: checked)) else { return }
        fixProblem = nil
        fixing = (id, "Starting…")
        fixStage = 4
        Task {
            defer {
                fixing = nil
                fixStage = 0
            }
            do {
                try await proveFix(of: withEarlierTest(checked), after: after, in: project)
            } catch {
                fixProblem = error.localizedDescription
            }
        }
    }

    /// A fix whose saved tests are being run before and after it, and what is being done.
    private(set) var proving: (screen: CheckedScreen.ID, step: String)?

    /// Shows the saved tests guard the fix: the code goes back to before the fix, where each
    /// test must fail, then forward to the fix, where it must pass. No model is asked; the
    /// source is left on the fix's branch, as it was.
    func proveTests(of id: CheckedScreen.ID) {
        guard let checked = screens.first(where: { $0.id == id }), let run = checked.fix, let after = run.after,
              let names = screens.first(where: { $0.id == after })?.savedTests, !names.isEmpty,
              proving == nil, fixing == nil, testing == nil, exploring == nil,
              let project = project(for: Self.app(of: checked)) else { return }
        fixProblem = nil
        Task {
            defer { proving = nil }
            do {
                guard try project.branch == run.branch else { throw Project.Problem.edit("The source is not on \(run.branch) now.") }
                let tests = SavedTest.load(from: project.folder).filter { names.contains($0.fileName) }
                var without: [String: String?] = [:]
                proving = (id, "Going back to the code before the fix…")
                _ = try project.git("switch", "-q", run.base)
                do {
                    for test in tests {
                        proving = (id, "Without the fix: \(test.persona.title) tries \(test.task.lowercasedFirst)…")
                        without[test.fileName] = Self.failure(try await test.replay())
                    }
                } catch {
                    _ = try? project.git("switch", "-q", run.branch)
                    throw error
                }
                proving = (id, "Bringing the fix back…")
                _ = try project.git("switch", "-q", run.branch)
                var proof: [Fixer.Run.Proof] = []
                for test in tests {
                    proving = (id, "With the fix: \(test.persona.title) tries \(test.task.lowercasedFirst)…")
                    proof.append(.init(test: test.fileName, without: without[test.fileName] ?? nil, with: Self.failure(try await test.replay())))
                }
                update(id) { $0.fix?.proof = proof }
                if let done = screens.first(where: { $0.id == id }) { History.save(done) }
            } catch {
                fixProblem = error.localizedDescription
            }
        }
    }

    private static func failure(_ result: SavedTest.Result) -> String? {
        if case .failed(let why) = result { return why }
        return nil
    }

    /// Says a line as VoiceOver would, for hearing a screen before and after a fix.
    func say(_ text: String) {
        voice.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
        voice.speak(utterance)
    }

    /// The same people try the same tasks they could not do before, from the same start, and
    /// the control tries them too, since a fix must not break normal use. Each success is
    /// kept as a test in the project, on the fix's branch.
    private func proveFix(of before: CheckedScreen, after id: CheckedScreen.ID, in project: Project) async throws {
        // Only the people whose failures the fix was asked to fix.
        let asked = Set(screens.first { $0.id == before.id }?.fix?.stuck ?? [])
        let stuck = (before.personaRuns ?? []).filter { $0.achieved == false && $0.persona != .control && asked.contains($0.id) }
        guard !stuck.isEmpty, let start = screens.first(where: { $0.id == id }) else { return }
        // Whatever was tried is kept, also when a try cannot finish.
        defer { if let done = screens.first(where: { $0.id == id }) { History.save(done) } }
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
            fixStage = 4
            fixing = (before.id, persona == .control ? "Someone without a disability tries \(task.goal.lowercasedFirst)…" : "\(persona.title) tries \(task.goal.lowercasedFirst) again…")
            let run = try await Personas.attempt(persona, task: task, at: persona.textSize, start: start.screen, picture: picture.jpeg, name: start.title, route: &route, client: client) { [weak self] partial in
                self?.keep(partial, in: id)
            }
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

    /// The fix whose branch an app's source has checked out now, still to keep or undo.
    func openFix(of app: String) -> CheckedScreen? {
        guard let branch = branches[app], branch.hasPrefix("allyfix/") else { return nil }
        return fixes(of: app).first { $0.fix?.branch == branch && $0.fix?.kept != true }
    }

    /// The branch each app's source has checked out, as last looked up. Views read this and
    /// never run git themselves: git waits for its process, and a view that waits while
    /// SwiftUI draws loses the update it was part of.
    private(set) var branches: [String: String] = [:]

    /// Looks up the branch the app's source has checked out now.
    func refreshBranch(of app: String?) {
        guard let app else { return }
        branches[app] = try? project(for: app)?.branch
    }

    /// Keeps a fix: brings it into the branch it started from, goes back there, and drops its
    /// branch, on every screen the fix touched.
    func keepFix(of id: CheckedScreen.ID) {
        guard let checked = screens.first(where: { $0.id == id }), let run = checked.fix, let project = project(for: Self.app(of: checked)) else { return }
        do {
            try project.keep(branch: run.branch, base: run.base)
            refreshBranch(of: Self.app(of: checked))
            for fixed in screens where fixed.fix?.branch == run.branch {
                update(fixed.id) { $0.fix?.kept = true }
                if let kept = screens.first(where: { $0.id == fixed.id }) { History.save(kept) }
            }
        } catch {
            fixProblem = error.localizedDescription
        }
    }

    /// Throws a fix away: back to the branch it started from, and the checks after it gone,
    /// on every screen the fix touched.
    func undoFix(of id: CheckedScreen.ID) {
        guard let checked = screens.first(where: { $0.id == id }), let run = checked.fix, let project = project(for: Self.app(of: checked)) else { return }
        do {
            try project.undo(branch: run.branch, base: run.base)
            refreshBranch(of: Self.app(of: checked))
            for fixed in screens where fixed.fix?.branch == run.branch {
                if let after = fixed.fix?.after { remove { $0.id == after } }
                update(fixed.id) { $0.fix = nil }
                if let kept = screens.first(where: { $0.id == fixed.id }) { History.save(kept) }
            }
            selectedScreen = id
        } catch {
            fixProblem = error.localizedDescription
        }
    }

    func delete(_ id: CheckedScreen.ID) {
        let app = screens.first { $0.id == id }.map(Self.app)
        remove { $0.id == id }
        if selectedScreen == id { selection = app.map { .app($0) } }
    }

    /// Runs an app's saved tests again, with no model, one after another.
    func runSavedTests(of app: String) {
        guard let project = project(for: app), testing == nil, exploring == nil else { return }
        let tests = SavedTest.load(from: project.folder)
        for test in tests { savedResults[test.fileName] = .some(nil) }
        Task {
            for test in tests {
                savedResults[test.fileName] = .some((try? await test.replay()) ?? .failed("Could not run."))
            }
        }
    }

    func remove(where matches: (CheckedScreen) -> Bool) {
        for checked in screens where matches(checked) {
            History.delete(checked.id)
        }
        screens.removeAll(where: matches)
    }

    func update(_ id: CheckedScreen.ID, _ change: (inout CheckedScreen) -> Void) {
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
