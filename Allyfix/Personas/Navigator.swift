import Foundation

/// Gets from wherever the app opens to the screen under test. The model finds the way once,
/// looking at a picture of that screen; after that the same presses are replayed, at no cost.
enum Navigator {
    static let mostSteps = 5

    enum Problem: LocalizedError {
        case lost(String, saw: String)
        var errorDescription: String? {
            switch self {
            case .lost(let name, let saw): "Allyfix restarted the app but could not get back to \(name); it saw \(saw). Open \(name) in the Simulator and try again."
            }
        }
    }

    struct Move: Decodable {
        let thought: String
        let arrived: Bool
        let element: Int?
    }

    /// Whether the screen shown is the one under test: it starts the same way, or most of
    /// what it says is the same, as after a fix that changed some of its labels.
    static func arrived(at target: Screen) -> Bool {
        guard let now = try? Simulator.screen() else { return false }
        if Array(now.elements.map(\.label).prefix(4)) == Array(target.elements.map(\.label).prefix(4)) { return true }
        let words = { (screen: Screen) in Set(screen.elements.map(\.label).filter { !$0.isEmpty }) }
        let a = words(now), b = words(target)
        return !a.isEmpty && Double(a.intersection(b).count) / Double(a.union(b).count) >= 0.6
    }

    /// The element a remembered label points to: the same label, or one that starts with the
    /// same words, so "Sets, tab, 2 of 5" still finds "Sets, tab" after a fix.
    static func find(_ label: String, in screen: Screen) -> Element? {
        let head = { (label: String) in label.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? label }
        return screen.elements.first { $0.label == label && $0.isControl }
            ?? screen.elements.first { $0.isControl && !head(label).isEmpty && head($0.label) == head(label) }
    }

    /// Brings the app to `target`. `route` holds the labels pressed to get there; it is
    /// replayed when known and learned when not.
    static func reach(_ target: Screen, picture: Data, name: String, route: inout [String], client: ModelClient) async throws -> ModelClient.Usage {
        var usage = ModelClient.Usage()
        // A restarted app may still be loading behind a splash screen; Expo Go takes 20
        // seconds and more. Wait until there is something to press and it holds still.
        if arrived(at: target) { return usage }
        try await Explorer.waitForApp()
        // A screen still settling, an animation, a late reload: give it a moment more.
        for _ in 0..<40 {
            if arrived(at: target) { return usage }
            try await Task.sleep(for: .milliseconds(500))
        }

        if !route.isEmpty {
            for label in route {
                guard let element = find(label, in: try Simulator.screen()) else { break }
                _ = Simulator.press(element)
                try await Task.sleep(for: Personas.settle)
            }
            if arrived(at: target) { return usage }
        }

        // The way has changed or was never found: the model looks for it.
        route = []
        for _ in 0..<mostSteps {
            let screen = try Simulator.screen()
            let now = try await Picture.take(device: screen.device)
            let (move, spent) = try await client.answer(Move.self, schemaName: "navigate", schema: schema, instructions: """
                You move through an iOS app to reach one screen. You get a picture of the screen \
                to reach, then the screen shown now with numbered marks on what can be pressed. \
                If the screen shown now is the one to reach, set arrived. Otherwise give the mark \
                that leads there, the way a person would go: a tab, a back button, a list row. \
                Never anything that deletes, buys, sends or signs out.
                """, input: [.text("The screen to reach, \(name):"), .jpeg(picture), .text("The screen shown now:"), .jpeg(Persona.marked(now.jpeg, screen: screen, picture: now))], maxTokens: 3000)
            usage += spent
            if move.arrived && arrived(at: target) { return usage }
            guard let id = move.element, let element = screen.elements.first(where: { $0.id == id }) else { break }
            _ = Simulator.press(element)
            route.append(element.label)
            try await Task.sleep(for: Personas.settle)
            if arrived(at: target) { return usage }
        }
        route = []
        let saw = (try? Simulator.screen())?.elements.prefix(3).map { "\u{201C}\($0.label.withIconsNamed)\u{201D}" }.joined(separator: ", ")
        throw Problem.lost(name, saw: saw.map { "a screen starting with \($0)" } ?? "no app screen")
    }

    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "thought": ["type": "string"],
            "arrived": ["type": "boolean"],
            "element": ["anyOf": [["type": "integer"], ["type": "null"]]],
        ],
        "required": ["thought", "arrived", "element"],
        "additionalProperties": false,
    ]
}
