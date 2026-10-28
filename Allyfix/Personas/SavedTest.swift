import Foundation

/// A task a persona managed, kept as a test that runs again with no model: the way to the
/// screen, the same actions, and what the accessibility tree must show at the end. Kept in
/// the app's repository, so it travels with the code and catches the barrier coming back.
struct SavedTest: Codable {
    struct Step: Codable {
        /// Activate the element with this label, as VoiceOver's double tap or a press does.
        var activate: String?
        /// Or touch this point, in iPhone points, off by this miss of the persona's tremor.
        var touch: CGPoint?
        var miss: Int?
    }

    enum Result {
        case passed
        case failed(String)
    }

    var task: String
    var persona: Persona
    var screen: String
    /// Labels pressed, in order, to get from the app's first screen to this one.
    var route: [String]
    var steps: [Step]
    var expect: [PersonaRun.Expectation]
    /// The text size the steps were taken at, when not the default.
    var textSize: TextSize?

    /// The test a successful run makes; none when the run did not succeed or nothing in the
    /// accessibility tree tells that it did.
    init?(_ run: PersonaRun, screen: String, route: [String]) {
        guard run.achieved == true, let expect = run.expect, !expect.isEmpty else { return nil }
        task = run.task.goal
        persona = run.persona
        self.screen = screen
        self.route = route
        self.expect = expect
        textSize = run.textSize
        steps = run.steps.compactMap { step in
            if let label = step.label, run.persona != .dexterity { return Step(activate: label) }
            if let point = step.point { return Step(touch: point, miss: step.miss) }
            return nil
        }
    }

    var fileName: String {
        let words = task.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: "-")
        return "\(words).\(persona.rawValue).json"
    }

    /// Writes the test to `allyfix/tests` in the project, or wherever `folder` says.
    @discardableResult
    func save(in folder: URL) throws -> URL {
        let tests = folder.appending(path: "allyfix/tests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let file = tests.appending(path: fileName)
        try encoder.encode(self).write(to: file, options: .atomic)
        return file
    }

    static func load(from folder: URL) -> [SavedTest] {
        let tests = folder.appending(path: "allyfix/tests")
        let files = (try? FileManager.default.contentsOfDirectory(at: tests, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }.compactMap {
            try? JSONDecoder().decode(SavedTest.self, from: Data(contentsOf: $0))
        }
    }

    /// Runs the test again from a fresh start of the app. No model is asked anything.
    func replay() async throws -> Result {
        try await TextSize.with(textSize) { try await replaySteps() }
    }

    private func replaySteps() async throws -> Result {
        try await Restart.app()
        for label in route {
            guard let element = Navigator.find(label, in: try Simulator.screen()) else {
                return .failed("The way to \(screen) changed: \"\(label)\" is gone.")
            }
            _ = Simulator.press(element)
            try await Task.sleep(for: Personas.settle)
        }
        for step in steps {
            let screen = try Simulator.screen()
            if let label = step.activate {
                guard let element = screen.elements.first(where: { $0.label == label }) else {
                    return .failed("\(persona.title) cannot reach \"\(label.withIconsNamed)\": it is not there any more.")
                }
                _ = Simulator.press(element)
            } else if let point = step.touch {
                let miss = persona.tremor[(step.miss ?? 0) % persona.tremor.count]
                try await Simulator.touch(at: point, miss: miss, on: screen)
            }
            try await Task.sleep(for: Personas.settle)
        }
        let labels = Set(try Simulator.screen().elements.map { $0.label.trimmingCharacters(in: .whitespaces) })
        let unmet = expect.filter { labels.contains($0.label) != $0.present }
        guard unmet.isEmpty else {
            let what = unmet.map { $0.present ? "\"\($0.label)\" did not appear" : "\"\($0.label)\" did not go away" }
            return .failed("\(task) did not happen: " + what.joined(separator: ", ") + ".")
        }
        return .passed
    }
}
