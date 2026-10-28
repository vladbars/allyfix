import Foundation

/// What Allyfix found in an app, written for a coding agent (Claude Code, Codex, Cursor or a
/// person) to act on: a Markdown file to read and a JSON file to parse, both in the app's
/// repository. Each problem says where it is, how to get there, what VoiceOver reads, what
/// is wrong, and how to tell it is fixed.
enum AgentReport {
    struct Findings: Codable {
        struct Screen: Codable {
            let name: String
            let section: String?
            /// Labels pressed from the app's first screen to get here.
            let route: [String]
            let checked: Date
            let problems: [Problem]
            let stuck: [Stuck]
        }

        struct Problem: Codable {
            let severity: String
            let kind: String
            let title: String
            let detail: String
            let wcag: String
            let suggestedLabel: String?
            let elements: [Element]
        }

        struct Element: Codable {
            let role: String
            /// What VoiceOver reads for it; "<icon>" stands for an icon-font glyph.
            let label: String
            let value: String
            /// In the iPhone's points, from the top left.
            let frame: CGRect
        }

        struct Stuck: Codable {
            let persona: String
            let clause: String
            let task: String
            let why: String
            let tested: Date
            let steps: [String]
        }

        let app: String
        let written: Date
        let screens: [Screen]
        let savedTests: [String]
    }

    static func findings(of app: String, checker: Checker) -> Findings {
        let tests = checker.project(for: app).map { SavedTest.load(from: $0.folder).map(\.fileName) } ?? []
        let screens = checker.latestScreens(of: app).map { checked -> Findings.Screen in
            let problems = checked.issues.sorted { $0.severity < $1.severity }.map { issue in
                Findings.Problem(
                    severity: issue.severity == .blocker ? "blocker" : "serious",
                    kind: issue.kind.rawValue,
                    title: issue.title.withIconsNamed,
                    detail: issue.detail.withIconsNamed,
                    wcag: issue.wcag,
                    suggestedLabel: issue.suggestion,
                    elements: issue.elements.compactMap { id in checked.screen.elements.first { $0.id == id } }.map {
                        Findings.Element(role: $0.role.replacingOccurrences(of: "AX", with: ""), label: $0.label.withIconsNamed, value: $0.value, frame: $0.pointFrame.integral)
                    }
                )
            }
            let tested = checker.lastTest(of: checked)
            let stuck = (tested?.personaRuns ?? []).filter { run in
                run.persona != .control && run.achieved == false && tested?.run(run.persona, run.task)?.id == run.id
            }.map { run in
                Findings.Stuck(
                    persona: run.persona.title, clause: "EN 301 549 \(run.persona.clause)", task: run.task.goal,
                    why: run.reason ?? "", tested: tested?.date ?? checked.date,
                    steps: run.steps.map { "\($0.action)\($0.target.map { " \($0.withIconsNamed)" } ?? ""): \($0.thought)" }
                )
            }
            return Findings.Screen(name: checked.title, section: checked.section, route: checked.route ?? [], checked: checked.date, problems: problems, stuck: stuck)
        }
        return Findings(app: app, written: Date(), screens: screens, savedTests: tests)
    }

    static func markdown(_ findings: Findings) -> String {
        let problems = findings.screens.flatMap(\.problems)
        let stuck = findings.screens.flatMap(\.stuck)
        var lines = [
            "# Accessibility: \(findings.app)",
            "",
            "Found by Allyfix on \(findings.written.formatted(date: .long, time: .shortened)): \(count(findings.screens.count, "screen")), \(count(problems.count, "problem")) (\(problems.filter { $0.severity == "blocker" }.count) blocking), \(count(stuck.count, "task")) people could not do. The same findings, for tools, are in `findings.json` next to this file.",
            "",
            "## How to work on this",
            "",
            "- Start with **Tasks people could not do**: each is a real barrier, found by someone with that disability trying the task in the running app. Fix what stopped them.",
            "- Each problem names the screen, how to get there from launch, and the element as VoiceOver reads it (`<icon>` is an icon-font glyph VoiceOver cannot read). Find that element in the code that draws the screen.",
            "- Keep the look for everyone else, unless the problem is itself visual (a target too small, a state told only by color, text that does not fit at large sizes).",
            "- Labels are short, say what the thing is or does, and are in the language of the app's own buttons, not of its content.",
            "- To check a fix: in Allyfix, check the screen again, or test it with people; saved tests in `allyfix/tests` run again with no model (Allyfix → app → Run Saved Tests).",
            "",
        ]
        if !stuck.isEmpty {
            lines += ["## Tasks people could not do", ""]
            for screen in findings.screens {
                for item in screen.stuck {
                    lines += [
                        "### \(item.persona) could not \(item.task.lowercasedFirst) — \(screen.name)",
                        "",
                        "\(item.clause). Tested \(item.tested.formatted(date: .abbreviated, time: .shortened)). \(where_(screen))",
                        "",
                        "Why: \(item.why)",
                        "",
                        "What they did:",
                    ]
                    lines += item.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }
                    lines.append("")
                }
            }
        }
        lines += ["## Problems by screen", ""]
        for screen in findings.screens {
            lines += ["### \(screen.name)\(screen.section.map { " (\($0))" } ?? "")", "", where_(screen), ""]
            if screen.problems.isEmpty {
                lines += ["Nothing found.", ""]
                continue
            }
            for (number, problem) in screen.problems.enumerated() {
                lines.append("\(number + 1). **\(problem.title)** — \(problem.severity), WCAG \(problem.wcag)")
                lines.append("   \(problem.detail)")
                for element in problem.elements.prefix(4) {
                    lines.append("   - \(element.role) reading \"\(element.label)\"\(element.value.isEmpty ? "" : ", value \(element.value)") at \(Int(element.frame.minX)),\(Int(element.frame.minY)) \(Int(element.frame.width))×\(Int(element.frame.height)) pt")
                }
                if let label = problem.suggestedLabel { lines.append("   - Suggested label: \"\(label)\"") }
            }
            lines.append("")
        }
        if !findings.savedTests.isEmpty {
            lines += ["## Saved tests", "", "These pass today and must keep passing; each is a task a person with a disability can do since a fix.", ""]
            lines += findings.savedTests.map { "- `allyfix/tests/\($0)`" }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func count(_ number: Int, _ thing: String) -> String {
        "\(number) \(thing)\(number == 1 ? "" : "s")"
    }

    private static func where_(_ screen: Findings.Screen) -> String {
        screen.route.isEmpty ? "The app's first screen." : "From launch: " + screen.route.map { "tap \"\(Explorer.words($0))\"" }.joined(separator: ", then ") + "."
    }

    /// Writes `allyfix/ACCESSIBILITY.md` and `allyfix/findings.json` into the folder; returns
    /// the Markdown file.
    @discardableResult
    static func write(_ findings: Findings, to folder: URL) throws -> URL {
        let dir = folder.appending(path: "allyfix")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(findings).write(to: dir.appending(path: "findings.json"), options: .atomic)
        let file = dir.appending(path: "ACCESSIBILITY.md")
        try markdown(findings).write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
