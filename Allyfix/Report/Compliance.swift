import Foundation

/// The two documents the law and buyers ask for, drafted from what Allyfix found: the
/// accessibility information a service must publish under the German BFSG (§ 14 with Anlage
/// 3), and a conformance report in the shape of a VPAT 2.5 EU edition, against EN 301 549.
/// Drafts: what only the owner knows is marked to fill in, and nothing untested is claimed.
enum Compliance {
    /// A success criterion of WCAG 2.1 at level A or AA, as EN 301 549 takes them up.
    struct Criterion {
        let number: String
        let name: String
        let level: String
    }

    static let criteria: [Criterion] = [
        ("1.1.1", "Non-text Content", "A"), ("1.2.1", "Audio-only and Video-only (Prerecorded)", "A"), ("1.2.2", "Captions (Prerecorded)", "A"),
        ("1.2.3", "Audio Description or Media Alternative (Prerecorded)", "A"), ("1.2.4", "Captions (Live)", "AA"), ("1.2.5", "Audio Description (Prerecorded)", "AA"),
        ("1.3.1", "Info and Relationships", "A"), ("1.3.2", "Meaningful Sequence", "A"), ("1.3.3", "Sensory Characteristics", "A"),
        ("1.3.4", "Orientation", "AA"), ("1.3.5", "Identify Input Purpose", "AA"), ("1.4.1", "Use of Color", "A"),
        ("1.4.2", "Audio Control", "A"), ("1.4.3", "Contrast (Minimum)", "AA"), ("1.4.4", "Resize Text", "AA"),
        ("1.4.5", "Images of Text", "AA"), ("1.4.10", "Reflow", "AA"), ("1.4.11", "Non-text Contrast", "AA"),
        ("1.4.12", "Text Spacing", "AA"), ("1.4.13", "Content on Hover or Focus", "AA"), ("2.1.1", "Keyboard", "A"),
        ("2.1.2", "No Keyboard Trap", "A"), ("2.1.4", "Character Key Shortcuts", "A"), ("2.2.1", "Timing Adjustable", "A"),
        ("2.2.2", "Pause, Stop, Hide", "A"), ("2.3.1", "Three Flashes or Below Threshold", "A"), ("2.4.1", "Bypass Blocks", "A"),
        ("2.4.2", "Page Titled", "A"), ("2.4.3", "Focus Order", "A"), ("2.4.4", "Link Purpose (In Context)", "A"),
        ("2.4.5", "Multiple Ways", "AA"), ("2.4.6", "Headings and Labels", "AA"), ("2.4.7", "Focus Visible", "AA"),
        ("2.5.1", "Pointer Gestures", "A"), ("2.5.2", "Pointer Cancellation", "A"), ("2.5.3", "Label in Name", "A"),
        ("2.5.4", "Motion Actuation", "A"), ("3.1.1", "Language of Page", "A"), ("3.1.2", "Language of Parts", "AA"),
        ("3.2.1", "On Focus", "A"), ("3.2.2", "On Input", "A"), ("3.2.3", "Consistent Navigation", "AA"),
        ("3.2.4", "Consistent Identification", "AA"), ("3.3.1", "Error Identification", "A"), ("3.3.2", "Labels or Instructions", "A"),
        ("3.3.3", "Error Suggestion", "AA"), ("3.3.4", "Error Prevention (Legal, Financial, Data)", "AA"), ("4.1.1", "Parsing", "A"),
        ("4.1.2", "Name, Role, Value", "A"), ("4.1.3", "Status Messages", "AA"),
    ].map { Criterion(number: $0.0, name: $0.1, level: $0.2) }

    /// What Allyfix examines on every screen it checks; only these can be judged from its
    /// findings. 2.5.8 comes from WCAG 2.2 and is reported apart.
    static let examined: Set<String> = ["1.1.1", "1.3.1", "1.3.2", "2.4.3", "2.5.3", "3.1.2", "4.1.2"]

    /// The German market surveillance authority for the BFSG; its address is to be checked,
    /// as published sources disagree.
    static let authority = "Marktüberwachungsstelle der Länder für die Barrierefreiheit von Produkten und Dienstleistungen (MLBF AöR), Magdeburg, www.mlbf-barrierefrei.de"

    struct Finding {
        let screen: String
        let issue: Issue
    }

    struct Facts {
        let app: String
        let screens: [CheckedScreen]
        let open: [Finding]
        /// Person by person: tasks tried and tasks stuck at, with why.
        let people: [(persona: Persona, tried: Int, stuck: [(screen: String, task: String, why: String)])]
        let firstChecked: Date?
        let lastChecked: Date?
    }

    static func facts(of app: String, checker: Checker) -> Facts {
        let screens = checker.latestScreens(of: app)
        let open = screens.flatMap { checked in checked.issues.map { Finding(screen: checked.title, issue: $0) } }
        let people = Persona.people.filter(\.ready).map { persona in
            var tried = 0
            var stuck: [(String, String, String)] = []
            for checked in screens {
                guard let tested = checker.lastTest(of: checked) else { continue }
                for run in tested.personaRuns ?? [] where run.persona == persona && run.achieved != nil
                    && tested.run(.control, run.task)?.achieved == true && tested.run(persona, run.task)?.id == run.id {
                    tried += 1
                    if run.achieved == false { stuck.append((checked.title, run.task.goal, run.why ?? "")) }
                }
            }
            return (persona, tried, stuck)
        }
        let dates = checker.screens(of: app).map(\.date)
        return Facts(app: app, screens: screens, open: open, people: people, firstChecked: dates.min(), lastChecked: dates.max())
    }

    /// The success criteria a finding fails, by number, read from its WCAG reference.
    static func numbers(_ issue: Issue) -> Set<String> {
        Set(issue.wcag.matches(of: /\d\.\d+\.\d+/).map { String($0.output) })
    }

    enum Level: String {
        case supports = "Supports"
        case partial = "Partially Supports"
        case fails = "Does Not Support"
        case notEvaluated = "Not Evaluated"
    }

    static func level(of criterion: Criterion, in facts: Facts) -> (Level, String) {
        let failing = facts.open.filter { numbers($0.issue).contains(criterion.number) }
        guard examined.contains(criterion.number) || !failing.isEmpty else {
            return (.notEvaluated, "Not covered by Allyfix's automated checks; needs a manual review.")
        }
        guard !failing.isEmpty else {
            return (.supports, "No problems found by Allyfix on the \(facts.screens.count) screens checked.")
        }
        let where_ = Array(Set(failing.map(\.screen))).sorted().joined(separator: ", ")
        let what = failing.prefix(3).map { $0.issue.title.withIconsNamed }.joined(separator: "; ")
        let level: Level = failing.contains { $0.issue.severity == .blocker } ? .fails : .partial
        return (level, "\(failing.count) problem\(failing.count == 1 ? "" : "s") on \(where_): \(what)\(failing.count > 3 ? "; …" : "").")
    }

    /// Writes both documents into `allyfix/` in the folder, each as Markdown and as PDF;
    /// returns the PDFs.
    static func write(_ facts: Facts, to folder: URL) throws -> [URL] {
        let dir = folder.appending(path: "allyfix")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try [("Barrierefreiheit", bfsg(facts)), ("Conformance Report", acr(facts))].map { name, markdown in
            try markdown.write(to: dir.appending(path: "\(name).md"), atomically: true, encoding: .utf8)
            let pdf = dir.appending(path: "\(name).pdf")
            try Paper.pdf(fromMarkdown: markdown, to: pdf)
            return pdf
        }
    }

    // MARK: BFSG information, in German

    static func bfsg(_ facts: Facts) -> String {
        let date = (facts.lastChecked ?? Date()).formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "de_DE")))
        var lines = [
            "# Informationen zur Barrierefreiheit: \(facts.app)",
            "",
            "> **Entwurf**, von Allyfix aus automatischen Prüfungen erstellt. Vor der Veröffentlichung rechtlich prüfen lassen und die Stellen in [eckigen Klammern] ausfüllen. Pflichtangaben nach § 14 Absatz 1 Nummer 2 und Anlage 3 BFSG; zu veröffentlichen in den AGB oder auf andere deutlich wahrnehmbare Weise, selbst barrierefrei.",
            "",
            "## a) Allgemeine Beschreibung der Dienstleistung",
            "",
            "[Beschreiben Sie in zwei, drei Sätzen, was \(facts.app) ist und wofür man die App nutzt.]",
            "",
            "## b) Erläuterungen zur Durchführung der Dienstleistung",
            "",
            "[Beschreiben Sie, wie die Dienstleistung genutzt wird: Registrierung, Kauf oder Abonnement, wichtigste Abläufe.]",
            "",
            "Die App umfasst unter anderem folgende Bereiche: " + facts.screens.map(\.title).joined(separator: ", ") + ".",
            "",
            "## c) Wie die Dienstleistung die Barrierefreiheitsanforderungen erfüllt",
            "",
            "Grundlage ist die harmonisierte Norm EN 301 549, die für Software die Erfolgskriterien der WCAG 2.1 auf den Stufen A und AA übernimmt.",
            "",
            "Geprüft am \(date): \(facts.screens.count) Bildschirme der iOS-App, automatisch mit Allyfix (Bedienung mit VoiceOver, Beschriftungen, Rollen und Zustände, Lesereihenfolge, Größe der Bedienelemente, Sprache) sowie Testläufe, in denen Nutzer mit verschiedenen Einschränkungen die wichtigsten Aufgaben ausführen:",
            "",
        ]
        for person in facts.people where person.tried > 0 {
            lines.append("- \(german(person.persona)): \(person.tried - person.stuck.count) von \(person.tried) Aufgaben erfolgreich.")
        }
        if facts.people.allSatisfy({ $0.tried == 0 }) {
            lines.append("- [Noch keine Testläufe mit Nutzern durchgeführt.]")
        }
        lines += ["", "### Bekannte Einschränkungen", ""]
        if facts.open.isEmpty {
            lines.append("Bei der Prüfung wurden keine Barrieren festgestellt.")
        } else {
            lines.append("Folgende Barrieren sind bekannt; die Behebung ist geplant bis [Datum]:")
            lines.append("")
            // By screen and criterion, in plain German: the findings themselves are in English.
            var groups: [(screen: String, number: String, count: Int)] = []
            for finding in facts.open {
                let number = finding.issue.wcag.firstMatch(of: /\d\.\d+\.\d+/).map { String($0.output) } ?? ""
                if let index = groups.firstIndex(where: { $0.screen == finding.screen && $0.number == number }) {
                    groups[index].count += 1
                } else {
                    groups.append((finding.screen, number, 1))
                }
            }
            for group in groups {
                let what = germanBarrier[group.number] ?? "Barriere"
                lines.append("- \(group.screen): \(what)\(group.number.isEmpty ? "" : " (WCAG \(group.number))")\(group.count > 1 ? ", \(group.count) Stellen" : "")")
            }
        }
        lines += [
            "",
            "### Feedback und Kontakt",
            "",
            "Wenn Sie auf Barrieren stoßen, schreiben Sie uns: [E-Mail-Adresse], [Telefon]. Wir antworten innerhalb von [Frist].",
            "",
            "## d) Zuständige Marktüberwachungsbehörde",
            "",
            authority + " [Anschrift auf der Website prüfen].",
            "",
        ]
        return lines.joined(separator: "\n")
    }

    /// What failing each criterion Allyfix can find means, in plain German.
    private static let germanBarrier = [
        "1.1.1": "Bilder und Symbole ohne Textalternative",
        "1.3.1": "Struktur und Zusammenhänge für Screenreader nicht erkennbar",
        "1.3.2": "Lesereihenfolge nicht sinnvoll",
        "1.4.1": "Informationen nur über Farbe vermittelt",
        "1.4.3": "Zu geringer Textkontrast",
        "1.4.4": "Text lässt sich nicht vergrößern",
        "1.4.11": "Zu geringer Kontrast von Bedienelementen",
        "2.4.3": "Fokus-Reihenfolge nicht sinnvoll",
        "2.4.6": "Unklare Überschriften oder Beschriftungen",
        "2.5.3": "Sichtbare Beschriftung fehlt im zugänglichen Namen",
        "2.5.8": "Zu kleine Bedienelemente",
        "3.1.2": "Sprache von Textteilen nicht ausgezeichnet",
        "3.3.2": "Fehlende Beschriftungen oder Anweisungen",
        "4.1.2": "Name, Rolle oder Zustand von Bedienelementen fehlt",
    ]

    private static func german(_ persona: Persona) -> String {
        switch persona {
        case .screenReader: "Nutzung ohne Sehvermögen (Screenreader VoiceOver, EN 301 549 §4.2.1)"
        case .lowVision: "Nutzung mit eingeschränktem Sehvermögen (§4.2.2)"
        case .colorVision: "Nutzung ohne Farbwahrnehmung (§4.2.3)"
        case .deaf: "Nutzung ohne Hörvermögen (§4.2.4)"
        case .dexterity: "Nutzung mit eingeschränkter Feinmotorik (§4.2.7)"
        case .cognitive: "Nutzung mit eingeschränkten kognitiven Fähigkeiten (§4.2.10)"
        case .control: "Nutzung ohne Einschränkung"
        }
    }

    // MARK: Conformance report, VPAT 2.5 EU shape

    static func acr(_ facts: Facts) -> String {
        let date = (facts.lastChecked ?? Date()).formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "en_GB")))
        var lines = [
            "# Accessibility Conformance Report: \(facts.app)",
            "",
            "Based on the VPAT® 2.5 EU edition, reporting against EN 301 549 V3.2.1. **Draft** written by Allyfix from automated checks and simulated user tests; a self-assessment, not a certification. Review it, and add the criteria marked Not Evaluated after a manual review.",
            "",
            "| | |",
            "|---|---|",
            "| Product | \(facts.app) (iOS app) |",
            "| Report date | \(date) |",
            "| Evaluation methods | Allyfix: accessibility tree and screenshots of \(facts.screens.count) screens in the iOS Simulator; tasks tried by simulated users with disabilities |",
            "| Applicable standards | EN 301 549 V3.2.1, chapters 4 and 11 (software); WCAG 2.1 A and AA |",
            "",
            "## Chapter 4: Functional performance statements",
            "",
            "| Statement | Conformance | Remarks |",
            "|---|---|---|",
        ]
        let statements: [(Persona, String)] = [(.screenReader, "4.2.1 Usage without vision"), (.lowVision, "4.2.2 Usage with limited vision"), (.colorVision, "4.2.3 Usage without perception of colour"), (.dexterity, "4.2.7 Usage with limited manipulation or strength"), (.cognitive, "4.2.10 Usage with limited cognition, language or learning")]
        for (persona, statement) in statements {
            let person = facts.people.first { $0.persona == persona }
            if let person, person.tried > 0 {
                let level: Level = person.stuck.isEmpty ? .supports : person.stuck.count == person.tried ? .fails : .partial
                let remark = person.stuck.isEmpty
                    ? "Did all \(person.tried) tasks tried."
                    : "Stuck at \(person.stuck.count) of \(person.tried) tasks: " + person.stuck.prefix(2).map { "\($0.task) (\($0.screen)): \($0.why)" }.joined(separator: " ")
                lines.append("| \(statement) | \(level.rawValue) | \(remark.replacingOccurrences(of: "|", with: "/")) |")
            } else {
                lines.append("| \(statement) | \(Level.notEvaluated.rawValue) | Not tested with this kind of user yet. |")
            }
        }
        lines += [
            "| 4.2.4 / 4.2.5 Usage without or with limited hearing | \(Level.notEvaluated.rawValue) | Not tested yet. |",
            "",
            "## Chapter 11: Software (WCAG 2.1 success criteria)",
            "",
            "| Criterion | Conformance | Remarks |",
            "|---|---|---|",
        ]
        for criterion in criteria {
            let (level, remark) = level(of: criterion, in: facts)
            let clause = "11." + criterion.number
            lines.append("| \(clause) \(criterion.name) (Level \(criterion.level)) | \(level.rawValue) | \(remark.replacingOccurrences(of: "|", with: "/")) |")
        }
        let targets = facts.open.filter { numbers($0.issue).contains("2.5.8") }
        lines += [
            "",
            "## Beyond EN 301 549 V3.2.1",
            "",
            "WCAG 2.2 2.5.8 Target Size (Minimum): " + (targets.isEmpty ? "no targets below 24×24 points found." : "\(targets.count) findings of small targets on " + Array(Set(targets.map(\.screen))).sorted().joined(separator: ", ") + "."),
            "",
        ]
        return lines.joined(separator: "\n")
    }
}
