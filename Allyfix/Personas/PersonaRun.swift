import Foundation

/// What a screen is for, in tasks a person comes to do there.
struct ScreenTask: Codable, Hashable {
    /// In the words a person would use: "Mark the word as known".
    let goal: String
    /// What a sighted judge would see once it is done; never shown to the persona.
    let success: String
}

/// A persona trying one task in the running app, step by step, and whether it got there.
struct PersonaRun: Codable, Identifiable {
    struct Step: Codable {
        /// What the persona was given: the words VoiceOver read, or a note on the picture.
        let perceived: String
        let thought: String
        let action: String
        /// The element or point acted on, in plain words.
        var target: String?
        /// What the persona saw, as the persona saw it, when it had a picture.
        var jpeg: Data?
        /// The same action again, without a model: the label of the element acted on, the
        /// point aimed at in iPhone points, and which of a tremor's misses it got.
        var label: String?
        var point: CGPoint?
        var miss: Int?
    }

    /// Something the accessibility tree shows once the task is done, or no longer shows.
    struct Expectation: Codable, Hashable {
        let label: String
        let present: Bool
    }

    var id = UUID()
    let persona: Persona
    let task: ScreenTask
    var steps: [Step] = []
    /// Whether the task got done, as the judge saw it.
    var achieved: Bool?
    /// The judge's reason, or the persona's own words when it gave up.
    var why: String?
    /// Why the run could not finish, when something other than the app stopped it.
    var problem: String?
    /// How the accessibility tree tells the task is done, taken when the judge first saw it
    /// done; a saved test checks this, with no model.
    var expect: [Expectation]?
    var usage = ModelClient.Usage()
}

/// Brings the app under test back to the screen a test starts from, whatever it is built
/// with, so every person starts the same way.
enum Restart {
    /// A React Native or Expo app in development reloads in seconds through its dev server;
    /// any other app is quit and launched again. Where it lands is up to the app; the
    /// navigator then finds the screen under test.
    static func app() async throws {
        let before = (try? Simulator.screen())?.elements.map(\.label) ?? []
        let ports = await devServers()
        // Expo Go shows its own tools button over the app after a reload; opened afresh with
        // the right address, it does not.
        if !ports.isEmpty, await foregroundApp() == "host.exp.Exponent" {
            simctl("terminate", "booted", "host.exp.Exponent")
            simctl("openurl", "booted", "exp://127.0.0.1:\(ports[0])?__expo_disable_fab=1&__expo_disable_onboarding=1")
            guard try await settle(changedFrom: before) else { throw Problem.notBack }
            return
        }
        if !ports.isEmpty {
            for port in ports { await reload(port) }
            // A reload that reached this app blanks the screen for a moment; one that did not
            // leaves it as it was, and the app is restarted the other way.
            if try await settle(changedFrom: before) { return }
        }
        guard let bundle = await foregroundApp() else { throw Problem.unknownApp }
        if bundle == "host.exp.Exponent", let port = ports.first {
            // Quitting Expo Go would lose the project; open it again from its dev server.
            simctl("openurl", "booted", "exp://127.0.0.1:\(port)?__expo_disable_fab=1&__expo_disable_onboarding=1")
        } else {
            simctl("terminate", "booted", bundle)
            simctl("launch", "booted", bundle)
        }
        guard try await settle(changedFrom: before) else { throw Problem.notBack }
    }

    enum Problem: LocalizedError {
        case unknownApp, notBack
        var errorDescription: String? {
            switch self {
            case .unknownApp: "Allyfix could not tell which app the Simulator shows."
            case .notBack: "The app did not start again. Open it in the Simulator and try again."
            }
        }
    }

    /// Waits for the screen to change, then to hold still: the app has started again.
    private static func settle(changedFrom before: [String]) async throws -> Bool {
        var changed = false
        for _ in 0..<16 where !changed {
            try await Task.sleep(for: .milliseconds(250))
            changed = (try? Simulator.screen())?.elements.map(\.label) != before
        }
        guard changed else { return false }
        var last: [String]?
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(500))
            let now = (try? Simulator.screen())?.elements.map(\.label)
            if let now, !now.isEmpty, now == last {
                // Let entrance animations finish.
                try await Task.sleep(for: .seconds(1))
                return true
            }
            last = now
        }
        return false
    }

    /// Metro dev servers on the usual ports, the way React Native and Expo run them.
    static func devServers() async -> [Int] {
        var running: [Int] = []
        for port in 8081...8090 {
            var request = URLRequest(url: URL(string: "http://localhost:\(port)/status")!)
            request.timeoutInterval = 0.4
            if let (data, _) = try? await URLSession.shared.data(for: request), String(decoding: data, as: UTF8.self) == "packager-status:running" {
                running.append(port)
            }
        }
        return running
    }

    /// Asks a dev server to reload the apps connected to it, as pressing r in its terminal does.
    private static func reload(_ port: Int) async {
        let socket = URLSession.shared.webSocketTask(with: URL(string: "ws://localhost:\(port)/message")!)
        socket.resume()
        try? await socket.send(.string(#"{"version":2,"method":"reload"}"#))
        socket.cancel(with: .goingAway, reason: nil)
    }

    /// The app iOS last brought to the foreground, from SpringBoard's log.
    @concurrent nonisolated static func foregroundApp() async -> String? {
        await lookUpForegroundApp()
    }

    /// The app under test does not change during a check or a test; asking the log once is
    /// enough. A new check starts over, since the Simulator may show another app by then.
    private static var knownApp: String?

    static func forgetApp() {
        knownApp = nil
    }

    private static func lookUpForegroundApp() async -> String? {
        if let knownApp { return knownApp }
        knownApp = await readForegroundApp()
        return knownApp
    }

    @concurrent nonisolated private static func readForegroundApp() async -> String? {
        let log = simctl("spawn", "booted", "log", "show", "--last", "1d", "--style", "compact", "--predicate",
                         #"subsystem == "com.apple.FrontBoard" AND eventMessage CONTAINS "Scene lifecycle state did change: Foreground""#)
        return log.split(separator: "\n").reversed().lazy.compactMap { line -> String? in
            guard let range = line.range(of: "sceneID:"), let end = line[range.upperBound...].range(of: "-default]") else { return nil }
            let bundle = String(line[range.upperBound..<end.lowerBound])
            // The home screen and system sheets are not the app under test.
            return bundle.hasPrefix("com.apple.") ? nil : bundle
        }.first
    }

    /// The app's name as people know it; an Expo Go app by its project's name.
    static func appName(of bundle: String) async -> String {
        if bundle == "host.exp.Exponent" {
            for port in await devServers() {
                var request = URLRequest(url: URL(string: "http://localhost:\(port)/")!)
                request.setValue("ios", forHTTPHeaderField: "expo-platform")
                request.timeoutInterval = 1
                guard let (data, _) = try? await URLSession.shared.data(for: request),
                      let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let client = (manifest["extra"] as? [String: Any])?["expoClient"] as? [String: Any]
                if let name = client?["name"] as? String ?? manifest["name"] as? String { return name }
            }
        }
        let list = Data(simctl("listapps", "booted").utf8)
        let apps = (try? PropertyListSerialization.propertyList(from: list, format: nil)) as? [String: [String: Any]]
        return apps?[bundle]?["CFBundleDisplayName"] as? String ?? apps?[bundle]?["CFBundleName"] as? String ?? bundle
    }

    @discardableResult
    nonisolated private static func simctl(_ arguments: String...) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl"] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return "" }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Plays personas through a screen's tasks in the Simulator.
enum Personas {
    /// Every persona tries every task, each from a freshly opened app.
    static func test(_ personas: [Persona], tasks: [ScreenTask], start: Screen, picture: Picture, client: ModelClient, progress: (PersonaRun) -> Void = { _ in }) async throws -> [PersonaRun] {
        var runs: [PersonaRun] = []
        var route: [String] = []
        for persona in personas {
            for task in tasks {
                try await Restart.app()
                let way = try await Navigator.reach(start, picture: picture.jpeg, name: "the screen under test", route: &route, client: client)
                var run = try await run(persona, task: task, client: client, progress: progress)
                run.usage += way
                runs.append(run)
                progress(run)
            }
        }
        try await Restart.app()
        _ = try await Navigator.reach(start, picture: picture.jpeg, name: "the screen under test", route: &route, client: client)
        return runs
    }

    static let mostSteps = 6
    /// Time for the app to answer a press and finish animating.
    static let settle = Duration.milliseconds(1200)

    // MARK: Tasks

    struct TaskAnswer: Decodable { let tasks: [ScreenTask] }

    /// The two or three things a person comes to this screen to do, as a sighted person
    /// sees them.
    static func tasks(on screen: Screen, picture: Picture, client: ModelClient) async throws -> ([ScreenTask], ModelClient.Usage) {
        let elements = screen.elements.map { "\($0.id). \(Audit.spoken($0).withIconsNamed)" }.joined(separator: "\n")
        let (answer, usage) = try await client.answer(TaskAnswer.self, schemaName: "tasks", schema: taskSchema, instructions: """
            You look at one screen of an iOS app and say what people come to this screen to \
            do: two or three tasks, the most important first. Each goal is a short sentence a \
            person would say, naming the very thing on this screen it is about ("Mark der \
            Bahnhof as known", not "Mark this word as known"), so it stays clear after the screen \
            changes. success says what would be visibly \
            different on screen once the task is done, so someone looking can tell. Never a task \
            that deletes, pays, sends, signs out or changes settings for good.
            """, input: [.jpeg(picture.jpeg), .text("Elements VoiceOver reads:\n" + elements)], maxTokens: 6000)
        return (Array(answer.tasks.prefix(3)), usage)
    }

    static let taskSchema: [String: Any] = {
        let task: [String: Any] = ["type": "object", "properties": ["goal": ["type": "string"], "success": ["type": "string"]], "required": ["goal", "success"], "additionalProperties": false]
        return ["type": "object", "properties": ["tasks": ["type": "array", "items": task]], "required": ["tasks"], "additionalProperties": false]
    }()

    // MARK: A run

    struct Move: Decodable {
        let thought: String
        /// activate, touch, done or giveUp.
        let action: String
        let element: Int?
        let x: Double?
        let y: Double?
    }

    /// One persona tries one task from the screen the Simulator shows now.
    static func run(_ persona: Persona, task: ScreenTask, client: ModelClient, progress: (PersonaRun) -> Void = { _ in }) async throws -> PersonaRun {
        var run = PersonaRun(persona: persona, task: task)
        let first = try await look()
        var screen = first.screen, picture = first.picture
        var taps = 0

        for _ in 0..<mostSteps {
            let lines = persona.sees ? await Reading.lines(in: picture.jpeg) : []
            let seen = persona.perceive(screen, picture: picture, lines: lines)
            var input: [ModelClient.Part] = []
            if let jpeg = seen.jpeg { input.append(.jpeg(jpeg)) }
            input.append(.text(prompt(task, run: run, perceived: seen.text)))
            let (move, usage) = try await client.answer(Move.self, schemaName: "move", schema: moveSchema(for: persona), instructions: instructions(for: persona), input: input, maxTokens: 4000)
            run.usage += usage

            var step = PersonaRun.Step(perceived: seen.text, thought: move.thought, action: move.action, target: nil, jpeg: seen.jpeg)
            switch move.action {
            case "activate":
                guard let id = move.element, let element = screen.elements.first(where: { $0.id == id }) else { break }
                step = step.with(target: "#\(id) \"\(Audit.spoken(element).withIconsNamed)\"", label: element.label)
                _ = Simulator.press(element)
            case "touch":
                // A mark is an element, pressed without the mouse; a point is touched for real.
                // A hand with a tremor touches for real either way, off its aim by the next miss.
                let index = taps % persona.tremor.count
                taps += 1
                if let id = move.element, let spot = seen.spots[id] {
                    // Text with no element of its own: only a real touch reaches it.
                    step = step.with(target: "mark \(id)", point: spot, miss: index)
                    try await Simulator.touch(at: spot, miss: persona.tremor[index], on: screen)
                } else if let id = move.element, let element = screen.elements.first(where: { $0.id == id }) {
                    let aim = CGPoint(x: element.pointFrame.midX, y: element.pointFrame.midY)
                    step = step.with(target: "mark \(id)", label: persona == .dexterity ? nil : element.label, point: aim, miss: index)
                    if persona == .dexterity || !Simulator.press(element) {
                        try await Simulator.touch(at: aim, miss: persona.tremor[index], on: screen)
                    }
                } else if let x = move.x, let y = move.y {
                    let mac = Review.toScreen(CGRect(x: x, y: y, width: 0, height: 0), screen: screen, picture: picture).origin
                    let aim = CGPoint(x: (mac.x - screen.frame.minX) / screen.scale, y: (mac.y - screen.frame.minY) / screen.scale)
                    step = step.with(target: "(\(Int(x)), \(Int(y)))", point: aim, miss: index)
                    try await Simulator.touch(at: aim, miss: persona.tremor[index], on: screen)
                }
            default:
                break
            }
            run.steps.append(step)
            progress(run)

            if move.action == "giveUp" {
                run.achieved = false
                run.why = move.thought
                return run
            }
            try await Task.sleep(for: settle)
            (screen, picture) = try await look()
            // The judge looks after every step: a persona may not notice it is done, or
            // believe it is when it is not.
            let (verdict, judged) = try await judge(task, before: first.picture, after: picture, run: run, client: client)
            run.usage += judged
            run.why = verdict.why
            if verdict.achieved || move.action == "done" {
                run.achieved = verdict.achieved
                if verdict.achieved { run.expect = Self.change(from: first.screen, to: screen) }
                return run
            }
        }
        run.achieved = false
        return run
    }

    /// What the accessibility tree gained and lost between two screens, in its most stable
    /// words: short labels, not glyphs or blanks. "3 of 20" gone and "4 of 20" there.
    static func change(from before: Screen, to after: Screen) -> [PersonaRun.Expectation] {
        let usable = { (labels: [String]) in Set(labels.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.withIconsNamed.contains("<icon>") && $0.count <= 60 }) }
        let old = usable(before.elements.map(\.label)), new = usable(after.elements.map(\.label))
        let gained = new.subtracting(old).sorted { $0.count < $1.count }.prefix(3).map { PersonaRun.Expectation(label: $0, present: true) }
        let lost = old.subtracting(new).sorted { $0.count < $1.count }.prefix(3).map { PersonaRun.Expectation(label: $0, present: false) }
        return gained + lost
    }

    private static func look() async throws -> (screen: Screen, picture: Picture) {
        let screen = try Simulator.screen()
        return (screen, try await Picture.take(device: screen.device))
    }

    static func instructions(for persona: Persona) -> String {
        let acting = persona.sees
            ? "Each step, do one thing: touch something you see (by its mark in element, or by x and y), say done when you believe the task is complete, or giveUp when you cannot see how to do it."
            : "Each step, do one thing: activate an element by its number (you swipe to it and double-tap), say done when you believe the task is complete, or giveUp when what you hear does not let you do it."
        return """
        \(persona.role)

        You are testing an app to see whether people like you can use it. \(acting) After each \
        action, first check whether the task is already done; if it is, say done. In thought, \
        say in one or two plain sentences, as yourself, what you notice and why you do what \
        you do. When you give up, say exactly what you could not find or tell apart.
        """
    }

    static func prompt(_ task: ScreenTask, run: PersonaRun, perceived: String) -> String {
        var lines = ["Your task: \(task.goal)", ""]
        if !run.steps.isEmpty {
            lines.append("What you did so far:")
            for (n, step) in run.steps.enumerated() {
                lines.append("\(n + 1). \(step.action)\(step.target.map { " \($0)" } ?? "") — \(step.thought)")
            }
            lines.append("")
        }
        lines.append(perceived)
        return lines.joined(separator: "\n")
    }

    static func moveSchema(for persona: Persona) -> [String: Any] {
        let nullableInteger: [String: Any] = ["anyOf": [["type": "integer"], ["type": "null"]]]
        let nullableNumber: [String: Any] = ["anyOf": [["type": "number"], ["type": "null"]]]
        let actions = persona.sees ? ["touch", "done", "giveUp"] : ["activate", "done", "giveUp"]
        return [
            "type": "object",
            "properties": [
                "thought": ["type": "string"],
                "action": ["type": "string", "enum": actions],
                "element": nullableInteger,
                "x": nullableNumber,
                "y": nullableNumber,
            ],
            "required": ["thought", "action", "element", "x", "y"],
            "additionalProperties": false,
        ]
    }

    // MARK: Judge

    struct Verdict: Decodable {
        let achieved: Bool
        let why: String
    }

    /// A sighted judge compares the screen before and after with what success looks like.
    static func judge(_ task: ScreenTask, before: Picture, after: Picture, run: PersonaRun, client: ModelClient) async throws -> (Verdict, ModelClient.Usage) {
        let steps = run.steps.enumerated().map { "\($0.offset + 1). \($0.element.action)\($0.element.target.map { " \($0)" } ?? ""): \($0.element.thought)" }.joined(separator: "\n")
        let schema: [String: Any] = ["type": "object", "properties": ["achieved": ["type": "boolean"], "why": ["type": "string"]], "required": ["achieved", "why"], "additionalProperties": false]
        return try await client.answer(Verdict.self, schemaName: "verdict", schema: schema, instructions: """
            You judge an accessibility test. A person with a disability tried a task in an app. \
            You get the screen before and after, the task, what success looks like, and the \
            person's steps. Say whether the task was really done, judging by the screens, not by \
            what the person believed. why: one or two plain sentences; when it was not done, say \
            what in the app stopped them.
            """, input: [.text("Before:"), .jpeg(before.jpeg), .text("After:"), .jpeg(after.jpeg), .text("Task: \(task.goal)\nSuccess looks like: \(task.success)\nPersona: \(run.persona.title)\n\nSteps:\n\(steps)")], maxTokens: 4000)
    }
}

extension PersonaRun.Step {
    func with(target: String?, label: String? = nil, point: CGPoint? = nil, miss: Int? = nil) -> PersonaRun.Step {
        var step = self
        step.target = target
        step.label = label
        step.point = point
        step.miss = miss
        return step
    }
}
