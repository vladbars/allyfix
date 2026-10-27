import CoreGraphics
import Foundation

/// Something on the screen that keeps a person who cannot see it, or who cannot tap
/// precisely, from using the app.
struct Issue: Identifiable, Hashable {
    enum Kind: String {
        case unlabeled, smallTarget, tinyTarget, merged, missingTabRole
    }

    enum Severity: Int, Comparable {
        /// Blocks a VoiceOver user, or fails WCAG at level A or AA.
        case blocker = 0
        /// Makes the app hard to use, or falls short of Apple's guidelines.
        case serious = 1

        static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    let kind: Kind
    let severity: Severity
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

    var id: String { "\(kind.rawValue)-\(elements.map(String.init).joined(separator: "-"))" }
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
        (unlabeled(elements) + targets(elements) + merged(elements) + tabs(elements)).sorted { $0.severity < $1.severity }
    }

    /// Controls VoiceOver can only call "button", or nothing at all.
    static func unlabeled(_ elements: [Element]) -> [Issue] {
        elements.filter { $0.isControl && $0.label.isEmpty && $0.value.isEmpty }.map { element in
            let what = element.subrole == "AXSwitch" ? "A switch" : element.role == "AXButton" || element.canPress ? "A button" : "A control"
            return Issue(
                kind: .unlabeled,
                severity: .blocker,
                title: "\(what) has no label",
                detail: "VoiceOver says only \"\(spoken(element))\". Someone who cannot see the screen does not know what it does.",
                wcag: "4.1.2 Name, Role, Value",
                elements: [element.id],
                frame: element.frame
            )
        }
    }

    /// Controls too small to hit reliably.
    static func targets(_ elements: [Element]) -> [Issue] {
        elements.compactMap { element in
            guard element.isControl else { return nil }
            let size = element.pointFrame.size
            let side = min(size.width, size.height)
            // Hidden or clipped: nothing to tap.
            guard side >= 4 else { return nil }
            // A sliver much longer than it is high is usually a frame the app reports
            // wrongly, as custom tab bars do; the picture decides those, not the numbers.
            if side < 12 && max(size.width, size.height) >= 3 * side { return nil }
            let shown = "\(Int(size.width.rounded()))×\(Int(size.height.rounded())) pt"
            if side < minimumTarget {
                return Issue(
                    kind: .tinyTarget,
                    severity: .blocker,
                    title: "Target too small: \(shown)",
                    detail: "Smaller than 24×24 points. People with tremor or limited dexterity miss it.",
                    wcag: "2.5.8 Target Size (Minimum)",
                    elements: [element.id],
                    frame: element.frame
                )
            }
            if side < comfortableTarget {
                return Issue(
                    kind: .smallTarget,
                    severity: .serious,
                    title: "Small target: \(shown)",
                    detail: "Apple recommends at least 44×44 points for anything to tap.",
                    wcag: "2.5.8 Target Size (Minimum), Apple HIG",
                    elements: [element.id],
                    frame: element.frame
                )
            }
            return nil
        }
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
        return [element.label, element.value, role].filter { !$0.isEmpty }.joined(separator: ", ").ifEmpty("…")
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
