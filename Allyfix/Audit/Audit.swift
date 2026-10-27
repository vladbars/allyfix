import CoreGraphics
import Foundation

/// Something on the screen that keeps a person who cannot see it, or who cannot tap
/// precisely, from using the app.
struct Issue: Identifiable, Hashable, Codable {
    enum Kind: String, Codable {
        // Found by the rules.
        case unlabeled, smallTarget, tinyTarget, merged, missingTabRole
        // Found by the model, comparing the screenshot with what VoiceOver reads.
        case notExposed, hidden, unlabeledIcon, unclearLabel, wrongLanguage, wrongRole, wrongFrame, decorative

        /// What the issue is about; two issues on one element with the same topic say the
        /// same thing.
        var topic: String {
            switch self {
            case .unlabeled, .unlabeledIcon, .unclearLabel: "label"
            case .missingTabRole, .wrongRole: "role"
            case .smallTarget, .tinyTarget: "size"
            default: rawValue
            }
        }

        /// The heading issues with this topic are listed under.
        var group: String {
            switch topic {
            case "label": "No label, or one that says nothing"
            case "role": "Wrong role or state"
            case "size": "Too small to tap"
            case "merged": "Read as one"
            case "notExposed": "Visible but not read"
            case "hidden": "Read but not visible"
            case "wrongLanguage": "Wrong language"
            case "wrongFrame": "Frame misses what is drawn"
            default: "Decoration read aloud"
            }
        }
    }

    enum Severity: Int, Comparable, Codable {
        /// Blocks a VoiceOver user, or fails WCAG at level A or AA.
        case blocker = 0
        /// Makes the app hard to use, or falls short of Apple's guidelines.
        case serious = 1

        static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    let kind: Kind
    var severity: Severity
    /// What is wrong, in a line.
    let title: String
    /// Why it matters and what VoiceOver says now.
    let detail: String
    /// The WCAG 2.2 success criterion it fails, e.g. "4.1.2 Name, Role, Value".
    let wcag: String
    /// The elements it is about.
    let elements: [Int]
    /// Where to draw it, on the Mac's screen.
    let frame: CGRect
    /// A label that would say what it is, in the app's language.
    var suggestion: String?
    /// Seen by the model in the screenshot rather than found by a rule.
    var byModel = false
    /// Where the things are really drawn, on the Mac's screen: what VoiceOver does not
    /// see, or, when frames miss, one place for each element in order.
    var drawn: [CGRect] = []

    var id: String {
        // Something VoiceOver does not see has no element, only a place.
        let place = elements.isEmpty ? "\(Int(frame.minX)),\(Int(frame.minY))" : elements.map(String.init).joined(separator: "-")
        return "\(kind.rawValue)-\(place)"
    }

    /// Whether `other` says what this one already says.
    func repeats(_ other: Issue) -> Bool {
        guard kind.topic == other.kind.topic else { return false }
        if elements.isEmpty || other.elements.isEmpty {
            return elements.isEmpty && other.elements.isEmpty && frame.intersects(other.frame)
        }
        return !Set(elements).isDisjoint(with: other.elements)
    }
}

/// The checks that need no model: they read the accessibility elements alone, so they
/// run in a moment on every screen.
enum Audit {
    /// Apple's minimum for something to tap.
    static let comfortableTarget: CGFloat = 44
    /// WCAG 2.2's minimum (2.5.8, level AA), 24 CSS pixels, taken as 24 points.
    static let minimumTarget: CGFloat = 24
    /// More parts than this in one label, and it is several things read as one.
    static let mergedParts = 6

    static func run(_ elements: [Element]) -> [Issue] {
        // Things read as one are left to the model: a list row read whole is right, a card
        // with its own buttons inside is not, and only the picture tells which.
        (unlabeled(elements) + targets(elements) + tabs(elements)).sorted { $0.severity < $1.severity }
    }

    /// The rules run again once the model has seen the screen, and its issues added,
    /// without saying anything twice.
    static func combine(_ elements: [Element], seen model: [Issue]) -> [Issue] {
        // What VoiceOver reads but nobody sees is one problem, not also a small or unlabeled target.
        let hidden = Set(model.filter { $0.kind == .hidden }.flatMap(\.elements))
        return merge(run(elements.filter { !hidden.contains($0.id) }), model)
    }

    /// The model's issues added to the rules', without saying anything twice.
    static func merge(_ rules: [Issue], _ model: [Issue]) -> [Issue] {
        var all = rules
        for var issue in model {
            // Only about the very same elements is it the same problem: "the tabs do not say
            // which is selected" does not replace "Progress is not a tab".
            guard let same = all.firstIndex(where: { $0.repeats(issue) && (Set($0.elements) == Set(issue.elements) || $0.byModel) }) else {
                all.append(issue)
                continue
            }
            // The model has seen the screen and names the thing ("the ⋮ menu"), where a
            // rule can only say what the label lacks.
            guard !all[same].byModel else { continue }
            issue.severity = min(issue.severity, all[same].severity)
            all[same] = issue
        }
        return all.sorted { $0.severity < $1.severity }
    }

    /// Controls VoiceOver can only call "button", or nothing at all.
    static func unlabeled(_ elements: [Element]) -> [Issue] {
        // A switch's value is whether it is on, not what it is.
        elements.filter { $0.isControl && $0.readableLabel.isEmpty && ($0.value.isEmpty || $0.role == "AXCheckBox") }.map { element in
            let what = element.subrole == "AXSwitch" ? "A switch" : element.role == "AXButton" || element.canPress ? "A button" : "A control"
            let glyph = element.label.trimmingCharacters(in: .whitespaces).isEmpty ? "" : " Its label is an icon-font character, which VoiceOver cannot read."
            return Issue(
                kind: .unlabeled,
                severity: .blocker,
                title: "\(what) has no label",
                detail: "VoiceOver says only \"\(spoken(element))\".\(glyph) Someone who cannot see the screen does not know what it does.",
                wcag: "4.1.2 Name, Role, Value",
                elements: [element.id],
                frame: element.frame
            )
        }
    }

    /// Controls whose label has a gap, like ", Sets from a photo": an icon inside has no
    /// label of its own. Often it only decorates the text beside it, so the model, which
    /// sees the icon, decides which of these matter.
    static func gaps(_ elements: [Element]) -> [Element] {
        elements.filter { element in
            guard element.isControl, !element.readableLabel.isEmpty, element.parts.count <= mergedParts else { return false }
            let pieces = element.label.split(separator: ",", omittingEmptySubsequences: false)
            return pieces.count > 1 && pieces.contains { $0.unicodeScalars.allSatisfy { $0.properties.generalCategory == .privateUse || $0.properties.isWhitespace } }
        }
    }

    /// Controls too small to hit reliably, one issue for all below WCAG's minimum and one
    /// for all below Apple's.
    static func targets(_ elements: [Element]) -> [Issue] {
        var tiny: [Element] = [], small: [Element] = []
        for element in elements where element.isControl {
            let size = element.pointFrame.size
            let side = min(size.width, size.height)
            // Hidden or clipped: nothing to tap.
            guard side >= 4 else { continue }
            // The picture decides those, not the numbers.
            if element.isSliver { continue }
            if side < minimumTarget {
                tiny.append(element)
            } else if side < comfortableTarget {
                small.append(element)
            }
        }
        func issue(_ kind: Issue.Kind, _ found: [Element], severity: Issue.Severity, below: String, why: String, wcag: String) -> Issue? {
            guard let first = found.first else { return nil }
            let sizes = found.prefix(4).map { "\(Int($0.pointFrame.width.rounded()))×\(Int($0.pointFrame.height.rounded()))" }.joined(separator: ", ")
            return Issue(
                kind: kind,
                severity: severity,
                title: found.count == 1 ? "A target smaller than \(below)" : "\(found.count) targets smaller than \(below)",
                detail: "\(why) Sizes: \(sizes)\(found.count > 4 ? "…" : "") pt.",
                wcag: wcag,
                elements: found.map(\.id),
                frame: found.dropFirst().reduce(first.frame) { $0.union($1.frame) }
            )
        }
        return [
            issue(.tinyTarget, tiny, severity: .blocker, below: "24×24 pt", why: "People with tremor or limited dexterity miss them.", wcag: "2.5.8 Target Size (Minimum)"),
            issue(.smallTarget, small, severity: .serious, below: "44×44 pt", why: "Apple recommends at least 44×44 points for anything to tap.", wcag: "2.5.8 Target Size (Minimum), Apple HIG"),
        ].compactMap { $0 }
    }

    /// Many things read out as one: VoiceOver says it all in one breath, and the buttons
    /// inside cannot be reached on their own.
    static func merged(_ elements: [Element]) -> [Issue] {
        elements.filter { $0.parts.count > mergedParts }.map { element in
            Issue(
                kind: .merged,
                severity: .blocker,
                title: "\(element.parts.count) items read as one",
                detail: "VoiceOver reads \"\(element.parts.prefix(3).joined(separator: ", "))…\" in one go. What is inside cannot be reached or activated on its own.",
                wcag: "1.3.1 Info and Relationships",
                elements: [element.id],
                frame: element.frame
            )
        }
    }

    /// Tabs in one bar where some say they are tabs and some do not.
    static func tabs(_ elements: [Element]) -> [Issue] {
        let isTab = { (element: Element) in element.parts.contains("tab") || element.subrole == "AXTabButton" }
        guard let tab = elements.first(where: isTab) else { return [] }
        let bar = elements.filter { $0.isControl && abs($0.frame.midY - tab.frame.midY) < 4 }
        return bar.filter { !isTab($0) }.map { element in
            Issue(
                kind: .missingTabRole,
                severity: .serious,
                title: "\"\(element.label)\" is not announced as a tab",
                detail: "The other items in this bar are read as \"tab, 1 of 5\"; this one is read as a plain button, so the bar sounds broken.",
                wcag: "4.1.2 Name, Role, Value",
                elements: [element.id],
                frame: element.frame
            )
        }
    }

    /// Roughly what VoiceOver says for an element.
    static func spoken(_ element: Element) -> String {
        let role = element.subrole == "AXSwitch" ? "switch button" : element.isControl ? "button" : ""
        return [element.readableLabel, element.value, role].filter { !$0.isEmpty }.joined(separator: ", ").ifEmpty("…")
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
