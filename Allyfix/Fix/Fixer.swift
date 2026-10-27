import Foundation

/// Fixes a screen's issues in the app's code: Muse Wonder reads the whole project at once,
/// with what VoiceOver reads and what is wrong, and answers with exact edits.
enum Fixer {
    static let model = "muse-wonder-1.0"

    struct Edit: Codable, Hashable {
        let path: String
        let find: String
        let replace: String
        /// The numbers of the issues, as listed to the model, that this edit fixes.
        let issues: [Int]
        let why: String
    }

    struct Answer: Decodable {
        let summary: String
        let edits: [Edit]
    }

    /// What one fix did.
    struct Run: Codable {
        let branch: String
        let base: String
        let summary: String
        let applied: [Edit]
        /// Edits that did not fit the code as it is, with why.
        let failed: [String]
        let usage: ModelClient.Usage
        let time: Double
        /// The same screen checked again once the app reloaded.
        var after: CheckedScreen.ID?
        /// The problems the edits say they fix, by `Checker.fixKey`.
        var fixed: [String]?
        /// The people's failed runs the fix was asked to fix; only they try again after it.
        var stuck: [UUID]?

        var files: Set<String> { Set(applied.map(\.path)) }
    }

    static func run(_ checked: CheckedScreen, project: Project, client: ModelClient) async throws -> Run {
        try await run([checked], project: project, client: client)
    }

    /// Fixes what was chosen on several screens at once: Muse Wonder sees each screen and the
    /// whole project, and answers with one set of edits, committed on one branch.
    static func run(_ screens: [CheckedScreen], project: Project, client: ModelClient) async throws -> Run {
        let start = Date()
        let sources = try project.sources()
        var input: [ModelClient.Part] = []
        for (number, checked) in screens.enumerated() {
            input.append(.text("Screen \(number + 1): \(checked.title)"))
            if let jpeg = checked.jpeg { input.append(.jpeg(jpeg)) }
        }
        input.append(.text(describe(screens)))
        input.append(.text(sources.map { "=== \($0.path)\n\($0.text)" }.joined(separator: "\n\n")))

        var wonder = client
        wonder.model = model
        wonder.reasoning = "medium"
        let (answer, usage) = try await wonder.answer(Answer.self, schemaName: "fixes", schema: schema, instructions: instructions, input: input, maxTokens: 48000)

        let name = screens.count == 1 ? slug(screens[0].title) : "\(screens.count)-screens"
        let branch = "allyfix/\(name)-\(Int(Date().timeIntervalSince1970) % 100_000)"
        let base = try project.startBranch(branch)
        var applied: [Edit] = [], failed: [String] = []
        for edit in answer.edits {
            do {
                try project.edit(edit.path, find: edit.find, replace: edit.replace)
                applied.append(edit)
            } catch {
                failed.append("\(edit.why): \(error.localizedDescription)")
            }
        }
        if applied.isEmpty {
            try? project.undo(branch: branch, base: base)
            throw Project.Problem.edit(failed.first ?? "No changes were proposed. \(answer.summary)")
        }
        // Problems are numbered across the screens in the order they were described.
        let numbered = screens.flatMap { checked in checked.issues.map { Checker.fixKey(checked.id, $0.id) } }
        let fixed = Set(applied.flatMap(\.issues)).compactMap { $0 >= 1 && $0 <= numbered.count ? numbered[$0 - 1] : nil }
        let titles = screens.map(\.title).joined(separator: ", ")
        try project.commit("Make \(titles) work with VoiceOver\n\n\(answer.summary)\n\n" + applied.map { "- \($0.why)" }.joined(separator: "\n"))
        var run = Run(branch: branch, base: base, summary: answer.summary, applied: applied, failed: failed, usage: usage, time: Date().timeIntervalSince(start))
        run.fixed = fixed
        run.stuck = screens.flatMap { ($0.personaRuns ?? []).filter { $0.achieved == false && $0.persona != .control }.map(\.id) }
        return run
    }

    static let instructions = """
    You fix problems that keep VoiceOver users from using an iOS app, in the app's source \
    code. You get the problems found on one screen, with what VoiceOver reads there, a \
    screenshot of the screen, and the app's source files.

    Most important are the tasks people with disabilities tried and could not do: fix what \
    stopped them, so the same person can do the same task. Make the smallest changes that \
    do it, in the code that draws this screen. Keep the look for everyone else, unless the \
    problem is itself visual (a target too small to hit, a state told only by color, text \
    that does not fit at large sizes); then change as little as needed.
    - React Native: accessibilityLabel, accessibilityRole, accessibilityState; \
    accessible={false} on a container that should not swallow the controls inside it; \
    accessibilityElementsHidden and importantForAccessibility="no-hide-descendants" for \
    content that is not visible (cards stacked behind, a side not shown); \
    accessibilityElementsHidden on icons that only decorate text beside them. A control \
    whose frame misses what is drawn: make the pressable view itself cover the drawn thing, \
    keeping the same look.
    - SwiftUI and UIKit: accessibilityLabel, accessibilityAddTraits, accessibilityHidden, \
    accessibilityElement(children:), isAccessibilityElement, accessibilityFrame.
    - Labels are short, in the language of the app's own buttons and headings, and say what \
    the thing is or does ("Listen", "Save word"); never a code name. An app that teaches or \
    shows another language keeps its interface language for labels: a German vocabulary app \
    with English buttons gets English labels. Tabs say they are tabs and which is \
    selected; switches and filters say whether they are on.

    Each edit: path is the file's path as given; find is text copied exactly from that \
    file, long enough to occur in it once; replace is what that text becomes. Edits in one \
    file must not overlap. issues are the numbers of the problems the edit fixes; why is \
    one short line. Leave out a problem you cannot fix safely. summary: two or three \
    sentences for the pull request, saying what changed for VoiceOver users.
    """

    /// For each screen: the tasks people could not do and how they got stuck, then the
    /// problems found, each with what VoiceOver reads for the elements it is about. Problems
    /// are numbered across all screens, so an edit can say which it fixes.
    static func describe(_ screens: [CheckedScreen]) -> String {
        var lines: [String] = []
        var number = 0
        for (index, checked) in screens.enumerated() {
            lines.append("## Screen \(index + 1): \(checked.title)" + (checked.section.map { " (tab \($0))" } ?? ""))
            if let route = checked.route, !route.isEmpty { lines.append("Reached from launch by tapping: " + route.joined(separator: " → ")) }
            lines.append("")
            let stuck = (checked.personaRuns ?? []).filter { $0.achieved == false && $0.persona != .control }
            if !stuck.isEmpty {
                lines.append("Tasks people could not do:")
                for run in stuck {
                    lines.append("- \(run.persona.title) (\(run.persona.perceives.lowercased())) tried \"\(run.task.goal)\" and got stuck: \(run.why ?? "")")
                    for step in run.steps {
                        lines.append("    \(step.action)\(step.target.map { " \($0.withIconsNamed)" } ?? ""): \(step.thought)")
                    }
                }
                lines.append("")
            }
            // The interface's own words, so labels match its language and not the content's.
            let own = checked.screen.elements.filter { $0.isControl && !$0.readableLabel.isEmpty && $0.readableLabel.count < 30 }.map(\.readableLabel).prefix(12)
            if !own.isEmpty { lines += ["The app's own button labels, in its interface language: " + own.joined(separator: " · "), ""] }
            if !checked.issues.isEmpty { lines.append("Problems:") }
            for issue in checked.issues {
                number += 1
                lines.append("\(number). [\(issue.severity == .blocker ? "blocker" : "serious")] \(issue.title)")
                lines.append("   \(issue.detail)")
                if let suggestion = issue.suggestion { lines.append("   Suggested label: \(suggestion)") }
                for id in issue.elements.prefix(6) {
                    guard let element = checked.screen.elements.first(where: { $0.id == id }) else { continue }
                    lines.append("   Element: \(element.role.replacingOccurrences(of: "AX", with: "")) reading \"\(element.label.withIconsNamed)\"")
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static let schema: [String: Any] = {
        func object(_ properties: [String: Any]) -> [String: Any] {
            ["type": "object", "properties": properties, "required": Array(properties.keys).sorted(), "additionalProperties": false]
        }
        let edit = object([
            "path": ["type": "string"],
            "find": ["type": "string", "description": "Exact text from the file, occurring in it once"],
            "replace": ["type": "string"],
            "issues": ["type": "array", "items": ["type": "integer"]],
            "why": ["type": "string"],
        ])
        return object(["summary": ["type": "string"], "edits": ["type": "array", "items": edit]])
    }()

    private static func slug(_ title: String) -> String {
        let words = title.lowercased().split { !$0.isLetter && !$0.isNumber }
        return words.isEmpty ? "screen" : words.joined(separator: "-")
    }
}

extension String {
    /// "Save der Bahnhof" as it reads mid-sentence: "save der Bahnhof".
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }

    /// Icon-font glyphs, which show as boxes and are read as nothing, written as "<icon>".
    var withIconsNamed: String {
        unicodeScalars.reduce(into: "") { text, scalar in
            text += scalar.properties.generalCategory == .privateUse ? "<icon>" : String(scalar)
        }
    }
}
