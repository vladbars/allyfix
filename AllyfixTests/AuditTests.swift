import ApplicationServices
import Testing
@testable import Allyfix

@MainActor
struct AuditTests {
    private func element(_ id: Int, role: String = "AXButton", subrole: String = "", label: String = "", size: CGSize = .init(width: 60, height: 60), y: CGFloat = 0, press: Bool = true) -> Element {
        let frame = CGRect(origin: .init(x: CGFloat(id) * 70, y: y), size: size)
        return Element(id: id, role: role, subrole: subrole, label: label, value: "", frame: frame, pointFrame: frame, canPress: press, ax: AXUIElementCreateSystemWide())
    }

    @Test func aButtonWithoutALabelBlocks() {
        let issues = Audit.unlabeled([element(0), element(1, label: "Add card"), element(2, role: "AXStaticText", press: false)])
        #expect(issues.map(\.elements) == [[0]])
        #expect(issues.first?.severity == .blocker)
    }

    @Test func targetsBelowWCAGBlockAndBelowAppleWarn() {
        let issues = Audit.targets([
            element(0, label: "a", size: .init(width: 20, height: 20)),
            element(1, label: "b", size: .init(width: 30, height: 30)),
            element(2, label: "c", size: .init(width: 44, height: 44)),
            element(3, label: "d", size: .init(width: 58, height: 2)),
            // A tab bar that reports 74×10 for icons 40 points high.
            element(4, label: "e", size: .init(width: 74, height: 10)),
        ])
        #expect(issues.map(\.kind) == [.tinyTarget, .smallTarget])
    }

    @Test func aCardReadAsOneBreathIsFound() {
        let card = element(0, role: "AXGenericElement", label: "lang, long, Der Flur ist lang., Sie hat langes Haar., A1, Know it!, Learn again", press: false)
        #expect(Audit.merged([card, element(1, label: "Cards, tab, 1 of 5")]).map(\.elements) == [[0]])
    }

    @Test func aTabThatIsNotAnnouncedAsOne() {
        let bar = [
            element(0, label: "Cards, tab, 1 of 5", y: 900),
            element(1, label: "Sets, tab, 2 of 5", y: 900),
            element(2, label: "Progress", y: 900),
            element(3, label: "Save", y: 100),
        ]
        #expect(Audit.tabs(bar).map(\.elements) == [[2]])
    }
}
