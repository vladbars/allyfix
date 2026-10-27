import ApplicationServices
import CoreGraphics

/// One thing on the iOS screen as VoiceOver sees it: its role, what it is called, and
/// where it is.
struct Element: Identifiable, Codable {
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
    /// The live element in the Simulator; none for a screen kept from an earlier launch.
    var ax: AXUIElement?
    /// Whether VoiceOver announces it as selected: the current tab, the chosen filter.
    /// Optional, so screens kept before it was read still load.
    var selected: Bool?

    private enum CodingKeys: CodingKey {
        case id, role, subrole, label, value, frame, pointFrame, canPress, selected
    }

    /// Something a person can act on: what VoiceOver would offer to activate.
    var isControl: Bool {
        // The Simulator offers a press on plain text too; VoiceOver does not treat it as a control.
        if role == "AXStaticText" { return false }
        return canPress || ["AXButton", "AXCheckBox", "AXSlider", "AXTextField", "AXPopUpButton", "AXLink"].contains(role)
    }

    /// Much longer than it is high, like the 74×10 point frames custom tab bars report for
    /// icons 40 points high: usually a frame the app gets wrong.
    var isSliver: Bool {
        let side = min(pointFrame.width, pointFrame.height)
        return side < 12 && max(pointFrame.width, pointFrame.height) >= 3 * side
    }

    /// The label without what VoiceOver cannot say: icon-font glyphs, which live in the
    /// Unicode private use area, and spaces.
    var readableLabel: String {
        String(String.UnicodeScalarView(label.unicodeScalars.filter { $0.properties.generalCategory != .privateUse })).trimmingCharacters(in: .whitespaces)
    }

    /// The label split the way VoiceOver pauses in it.
    var parts: [String] {
        label.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

/// What the Simulator shows right now.
struct Screen: Codable {
    /// The Simulator window's title, e.g. "iPhone 17 – iOS 27.0".
    let device: String
    /// Where the iPhone's screen is on the Mac's screen.
    let frame: CGRect
    /// Mac points per iPhone point.
    let scale: CGFloat
    /// In VoiceOver's reading order.
    let elements: [Element]

    /// A place on the Mac's screen as parts of this iPhone screen, 0 to 1, to draw it
    /// over a screenshot of any size.
    func unit(_ rect: CGRect) -> CGRect {
        CGRect(x: (rect.minX - frame.minX) / frame.width, y: (rect.minY - frame.minY) / frame.height, width: rect.width / frame.width, height: rect.height / frame.height)
    }
}

extension CGRect {
    /// How much of the smaller of the two the other covers, 0 to 1.
    func overlap(_ other: CGRect) -> CGFloat {
        let shared = intersection(other)
        guard !shared.isNull else { return 0 }
        return shared.width * shared.height / max(min(width * height, other.width * other.height), 1)
    }

    /// From parts of a whole, 0 to 1, to points in `size`.
    func scaled(to size: CGSize) -> CGRect {
        CGRect(x: minX * size.width, y: minY * size.height, width: width * size.width, height: height * size.height)
    }
}
