import ApplicationServices
import CoreGraphics

/// One thing on the iOS screen as VoiceOver sees it: its role, what it is called, and
/// where it is.
struct Element: Identifiable {
    let id: Int
    /// The macOS accessibility role the Simulator gives it: `AXButton`, `AXStaticText`,
    /// `AXCheckBox`, `AXGenericElement`…
    let role: String
    let subrole: String
    /// What VoiceOver reads for it; empty when it has no label.
    let label: String
    let value: String
    /// On the Mac's screen, in points, origin at the top left.
    let frame: CGRect
    /// In the iPhone's own points.
    let pointFrame: CGRect
    let canPress: Bool
    let ax: AXUIElement

    /// Something a person can act on: what VoiceOver would offer to activate.
    var isControl: Bool {
        // The Simulator offers a press on plain text too; VoiceOver does not treat it as a control.
        if role == "AXStaticText" { return false }
        return canPress || ["AXButton", "AXCheckBox", "AXSlider", "AXTextField", "AXPopUpButton", "AXLink"].contains(role)
    }

    /// The label split the way VoiceOver pauses in it.
    var parts: [String] {
        label.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

/// What the Simulator shows right now.
struct Screen {
    /// The Simulator window's title, e.g. "iPhone 17 – iOS 27.0".
    let device: String
    /// Where the iPhone's screen is on the Mac's screen.
    let frame: CGRect
    /// Mac points per iPhone point.
    let scale: CGFloat
    /// In VoiceOver's reading order.
    let elements: [Element]
}
