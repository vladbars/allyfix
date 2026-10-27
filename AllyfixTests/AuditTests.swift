import ApplicationServices
import Foundation
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
        #expect(issues.map(\.elements) == [[0], [1]])
    }

    @Test func smallTargetsAreOneIssue() {
        let issues = Audit.targets((0..<5).map { element($0, label: "\($0)", size: .init(width: 30, height: 30)) })
        #expect(issues.count == 1)
        #expect(issues.first?.title == "5 targets smaller than 44×44 pt")
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

    @Test func anIconFontGlyphIsNoLabelAndASwitchValueIsNoName() {
        let glyph = element(0, label: "\u{E8F4}")
        let toggle = Element(id: 1, role: "AXCheckBox", subrole: "AXSwitch", label: "", value: "0", frame: .init(x: 0, y: 0, width: 60, height: 60), pointFrame: .init(x: 0, y: 0, width: 60, height: 60), canPress: true, ax: AXUIElementCreateSystemWide())
        #expect(Audit.unlabeled([glyph, toggle, element(2, label: "Save")]).map(\.elements) == [[0], [1]])
    }

    @Test func aLabelWithAGapHidesAnIcon() {
        let gaps = Audit.gaps([
            element(0, role: "AXGenericElement", label: ", Sets from a photo"),
            element(1, role: "AXGenericElement", label: "\u{E5D4}, Sets from a photo"),
            element(2, label: "Sets, tab, 2 of 5"),
        ])
        #expect(gaps.map(\.id) == [0, 1])
    }

    @Test func theModelNamesWhatARuleFoundAndAddsWhatItCouldNot() {
        let rule = Audit.unlabeled([element(0)])
        let named = Issue(kind: .unlabeledIcon, severity: .blocker, title: "The ⋮ menu has no label", detail: "", wcag: "", elements: [0], frame: .zero, byModel: true)
        let missing = Issue(kind: .notExposed, severity: .blocker, title: "Missing", detail: "", wcag: "", elements: [], frame: .init(x: 10, y: 10, width: 20, height: 20), byModel: true)
        let again = Issue(kind: .notExposed, severity: .serious, title: "Missing again", detail: "", wcag: "", elements: [], frame: .init(x: 15, y: 15, width: 20, height: 20), byModel: true)
        let merged = Audit.merge(rule, [named, missing, again])
        #expect(merged.map(\.title) == ["The ⋮ menu has no label", "Missing"])
    }

    @Test func aBroaderModelIssueDoesNotSwallowARule() {
        let rule = Issue(kind: .missingTabRole, severity: .serious, title: "Progress is not a tab", detail: "", wcag: "", elements: [3], frame: .zero)
        let tabs = Issue(kind: .wrongRole, severity: .serious, title: "No tab says it is selected", detail: "", wcag: "", elements: [0, 1, 2, 3, 4], frame: .zero, byModel: true)
        #expect(Audit.merge([rule], [tabs]).map(\.title) == ["Progress is not a tab", "No tab says it is selected"])
    }

    @Test func whatIsHiddenIsNotAlsoTooSmall() {
        let elements = [element(0, label: "das Eisen", size: .init(width: 300, height: 20)), element(1, label: "Save", size: .init(width: 30, height: 30))]
        let hidden = Issue(kind: .hidden, severity: .serious, title: "Hidden", detail: "", wcag: "", elements: [0], frame: .zero, byModel: true)
        #expect(Audit.combine(elements, seen: [hidden]).map(\.elements) == [[1], [0]])
    }

    @Test func theAnswerSchemaIsStrict() {
        func check(_ node: Any) {
            if let object = node as? [String: Any] {
                if object["type"] as? String == "object", let properties = object["properties"] as? [String: Any] {
                    #expect(object["additionalProperties"] as? Bool == false)
                    #expect(Set(object["required"] as? [String] ?? []) == Set(properties.keys))
                }
                object.values.forEach(check)
            } else if let array = node as? [Any] {
                array.forEach(check)
            }
        }
        check(Review.schema)
        #expect(Review.schema["anyOf"] == nil)
    }

    @Test func modelFindingsLandOnTheElementOrTheBox() throws {
        let screen = Screen(device: "iPhone 17", frame: .init(x: 100, y: 50, width: 300, height: 600), scale: 0.75, elements: [element(0, label: "AddCard")])
        let picture = Picture(jpeg: Data(), size: .init(width: 600, height: 1200))
        let json = """
        {"screen": "Card", "section": "Cards", "hidden": [], "places": [], "findings": [
          {"kind": "unclearLabel", "elements": [0], "boxes": [], "title": "AddCard", "detail": "", "suggestedLabel": "Add card", "severity": "blocker", "confidence": 0.9},
          {"kind": "notExposed", "elements": [], "boxes": [{"x": 500, "y": 100, "width": 40, "height": 40}], "title": "⋮", "detail": "", "suggestedLabel": "", "severity": "blocker", "confidence": 0.8},
          {"kind": "decorative", "elements": [0], "boxes": [], "title": "unsure", "detail": "", "suggestedLabel": null, "severity": "serious", "confidence": 0.3}
        ]}
        """
        let answer = try JSONDecoder().decode(Review.Answer.self, from: Data(json.utf8))
        let issues = Review.issues(from: answer, screen: screen, picture: picture)
        #expect(issues.map(\.title) == ["AddCard", "⋮"])
        #expect(issues[0].suggestion == "Add card")
        #expect(issues[1].elements.isEmpty && issues[1].suggestion == nil)
        #expect(issues[1].frame == CGRect(x: 350, y: 100, width: 20, height: 20))
    }

    @Test func aCheckedScreenSurvivesARelaunch() throws {
        let screen = Screen(device: "iPhone 17", frame: .init(x: 0, y: 0, width: 300, height: 650), scale: 0.75, elements: [element(0)])
        var checked = CheckedScreen(screen: screen, issues: Audit.run(screen.elements))
        checked.name = "Sets"
        let kept = try JSONDecoder().decode(CheckedScreen.self, from: JSONEncoder().encode(checked))
        #expect(kept.id == checked.id && kept.name == "Sets" && kept.issues == checked.issues)
        #expect(kept.screen.elements.first?.ax == nil)

        // A screen kept by an earlier version, without the fields added since, still loads.
        var older = try JSONSerialization.jsonObject(with: JSONEncoder().encode(checked)) as! [String: Any]
        older["inked"] = nil
        older["fix"] = nil
        #expect(try JSONDecoder().decode(CheckedScreen.self, from: JSONSerialization.data(withJSONObject: older)).id == checked.id)
    }

    @Test func otherIssuesOnAMisplacedElementPointAtWhereItIsDrawn() {
        let tab = element(0, label: "AddCard, tab, 3 of 5", size: .init(width: 100, height: 10))
        let screen = Screen(device: "iPhone 17", frame: .init(x: 0, y: 0, width: 300, height: 650), scale: 1, elements: [tab])
        let icon = CGRect(x: 20, y: 600, width: 40, height: 40)
        let misplaced = Issue(kind: .wrongFrame, severity: .serious, title: "", detail: "", wcag: "", elements: [0], frame: tab.frame, byModel: true, drawn: [icon])
        let code = Issue(kind: .unclearLabel, severity: .serious, title: "", detail: "", wcag: "", elements: [0], frame: tab.frame, byModel: true)
        let checked = CheckedScreen(screen: screen, issues: [misplaced, code])
        #expect(checked.frames(of: code) == [icon])
        #expect(checked.frames(of: misplaced) == [tab.frame])
        #expect(checked.drawn(misplaced.id) == [icon])

        // Without a finding about the frame, the model's place for the thing still wins
        // when the frame misses it, and not when the frame is right.
        let alone = CheckedScreen(screen: screen, issues: [Issue(kind: .unclearLabel, severity: .serious, title: "", detail: "", wcag: "", elements: [0], frame: tab.frame, byModel: true, drawn: [icon])])
        #expect(alone.frames(of: alone.issues[0]) == [icon])
        let close = CGRect(x: tab.frame.minX + 2, y: tab.frame.minY, width: 96, height: 10)
        let right = CheckedScreen(screen: screen, issues: [Issue(kind: .unclearLabel, severity: .serious, title: "", detail: "", wcag: "", elements: [0], frame: tab.frame, byModel: true, drawn: [close])])
        #expect(right.frames(of: right.issues[0]) == [tab.frame])

        // A finding about the frame that only repeats the frame corrects nothing.
        let copied = Issue(kind: .wrongFrame, severity: .serious, title: "", detail: "", wcag: "", elements: [0], frame: tab.frame, byModel: true, drawn: [tab.frame])
        let both = CheckedScreen(screen: screen, issues: [copied, Issue(kind: .unclearLabel, severity: .serious, title: "", detail: "", wcag: "", elements: [0], frame: tab.frame, byModel: true, drawn: [icon])])
        #expect(both.frames(of: both.issues[1]) == [icon])
    }

    @Test func whatIsHiddenIsOneIssueAndPlacesFixOnlyMissedFrames() throws {
        let tab = element(1, label: "Progress", size: .init(width: 100, height: 10))
        let screen = Screen(device: "iPhone 17", frame: .init(x: 0, y: 0, width: 300, height: 600), scale: 1, elements: [element(0, label: "das Eisen"), tab, element(2, label: "Save")])
        let picture = Picture(jpeg: Data(), size: .init(width: 300, height: 600))
        let json = """
        {"screen": "Card", "section": null, "hidden": [0, 0, 9], "findings": [], "places": [
          {"element": 1, "box": {"x": 140, "y": 20, "width": 40, "height": 40}},
          {"element": 2, "box": {"x": 140, "y": 0, "width": 60, "height": 60}}
        ]}
        """
        let answer = try JSONDecoder().decode(Review.Answer.self, from: Data(json.utf8))
        #expect(Review.issues(from: answer, screen: screen, picture: picture).map(\.elements) == [[0]])
        #expect(Review.places(from: answer, screen: screen, picture: picture) == [1: CGRect(x: 140, y: 20, width: 40, height: 40)])
    }

    @Test func whatNobodySeesIsOneAreaNotManyFrames() {
        let elements = (0..<3).map { element($0, label: "\($0)") }
        let screen = Screen(device: "iPhone 17", frame: .init(x: 0, y: 0, width: 300, height: 600), scale: 1, elements: elements)
        let hidden = Issue(kind: .hidden, severity: .serious, title: "", detail: "", wcag: "", elements: [0, 1, 2], frame: .zero, byModel: true)
        let label = Issue(kind: .unlabeled, severity: .blocker, title: "", detail: "", wcag: "", elements: [0, 1], frame: .zero)
        let checked = CheckedScreen(screen: screen, issues: [hidden, label])
        #expect(checked.outline(of: hidden).frames == [CGRect(x: 0, y: 0, width: 200, height: 60)])
        #expect(checked.outline(of: hidden).area)
        #expect(checked.outline(of: label).frames.count == 2 && !checked.outline(of: label).area)
    }
}
