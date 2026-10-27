import ApplicationServices
import Foundation
import Testing
@testable import Allyfix

@MainActor
struct ExplorerTests {
    private func element(_ id: Int, _ label: String, x: CGFloat, y: CGFloat, role: String = "AXButton") -> Element {
        let frame = CGRect(x: x, y: y, width: 60, height: 10)
        return Element(id: id, role: role, subrole: "", label: label, value: "", frame: frame, pointFrame: frame, canPress: true)
    }

    @Test func aTabThatDoesNotSayItIsATabIsStillInTheRow() {
        let screen = Screen(device: "iPhone", frame: .init(x: 0, y: 0, width: 300, height: 650), scale: 1, elements: [
            element(0, "Save", x: 10, y: 100),
            element(1, "Cards, tab, 1 of 3", x: 0, y: 620),
            element(2, "Progress", x: 100, y: 620),
            element(3, "Profile, tab, 3 of 3", x: 200, y: 620),
        ])
        #expect(Explorer.tabs(on: screen) == ["Cards, tab, 1 of 3", "Progress", "Profile, tab, 3 of 3"])
        #expect(Explorer.tries(on: screen, tabs: Explorer.tabs(on: screen)) == ["Save"])
    }

    @Test func nothingUnsafeIsTried() {
        let screen = Screen(device: "iPhone", frame: .init(x: 0, y: 0, width: 300, height: 650), scale: 1, elements: [
            element(0, "Delete account", x: 10, y: 100),
            element(1, "Sign out", x: 10, y: 200),
            element(2, "Open set", x: 10, y: 300),
        ])
        #expect(Explorer.tries(on: screen, tabs: []) == ["Open set"])
    }

    @Test func controlsAreCalledWhatAPersonWouldCallThem() {
        #expect(Explorer.words("Sets, tab, 2 of 5") == "Sets")
        #expect(Explorer.words(", From a photo") == "From a photo")
        #expect(Explorer.words("\u{E8F4}, Search") == "Search")
    }
}

@MainActor
struct AgentReportTests {
    @Test func theReportSaysWhereEachProblemIsAndWhoGotStuck() {
        let findings = AgentReport.Findings(app: "Vokabeln", written: Date(), screens: [
            .init(name: "Sets", section: "Sets", route: ["Sets, tab, 2 of 5"], checked: Date(),
                  problems: [.init(severity: "blocker", kind: "unclearLabel", title: "The add tab reads AddCard", detail: "VoiceOver reads \"AddCard\".", wcag: "4.1.2", suggestedLabel: "Add card",
                                   elements: [.init(role: "Button", label: "AddCard, tab, 3 of 5", value: "", frame: CGRect(x: 1, y: 2, width: 3, height: 4))])],
                  stuck: [.init(persona: "Screen reader user", clause: "EN 301 549 §4.2.1", task: "Open the Weather set", why: "No button to open it.", tested: Date(), steps: ["giveUp: no button"])]),
        ], savedTests: [])
        let text = AgentReport.markdown(findings)
        #expect(text.contains("1 screen, 1 problem (1 blocking), 1 task people could not do"))
        #expect(text.contains("From launch: tap \"Sets\"."))
        #expect(text.contains("### Screen reader user could not open the Weather set — Sets"))
        #expect(text.contains("Suggested label: \"Add card\""))
    }
}

@MainActor
struct ChoosingTests {
    @Test func whatIsUntickedStaysOutOfTheFix() {
        let checker = Checker()
        let frame = CGRect(x: 0, y: 0, width: 60, height: 60)
        let element = Element(id: 0, role: "AXButton", subrole: "", label: "", value: "", frame: frame, pointFrame: frame, canPress: true)
        let screen = Screen(device: "iPhone", frame: .init(x: 0, y: 0, width: 300, height: 650), scale: 1, elements: [element])
        let checked = CheckedScreen(screen: screen, issues: Audit.run(screen.elements) + Audit.targets([element]))
        #expect(checker.chosen(checked).issues.count == checked.issues.count)
        checker.excluded.insert(Checker.fixKey(checked.id, checked.issues[0].id))
        #expect(checker.chosen(checked).issues.map(\.id) == checked.issues.dropFirst().map(\.id))
        #expect(Checker.hasWork(checker.chosen(checked)) == (checked.issues.count > 1))
    }

    @Test func picksTickWhatTheyCover() {
        let checker = Checker()
        let frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        let unlabeled = Element(id: 0, role: "AXButton", subrole: "", label: "", value: "", frame: frame, pointFrame: frame, canPress: true)
        let screen = Screen(device: "iPhone", frame: .init(x: 0, y: 0, width: 300, height: 650), scale: 1, elements: [unlabeled])
        let checked = CheckedScreen(screen: screen, issues: Audit.run(screen.elements))
        let blocking = checked.issues.filter { $0.severity == .blocker }.count
        checker.pick(.blocking, on: [checked])
        #expect(checker.chosen(checked).issues.count == blocking)
        checker.pick(.none, on: [checked])
        #expect(checker.chosen(checked).issues.isEmpty)
        checker.pick(.all, on: [checked])
        #expect(checker.chosen(checked).issues.count == checked.issues.count)
    }
}
