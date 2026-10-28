import ApplicationServices
import Foundation
import Testing
@testable import Allyfix

@MainActor
struct PersonaTests {
    private func strict(_ node: Any) -> Bool {
        if let object = node as? [String: Any] {
            if object["type"] as? String == "object", let properties = object["properties"] as? [String: Any] {
                guard object["additionalProperties"] as? Bool == false, Set(object["required"] as? [String] ?? []) == Set(properties.keys) else { return false }
            }
            return object.values.allSatisfy(strict)
        }
        if let array = node as? [Any] { return array.allSatisfy(strict) }
        return true
    }

    @Test func everyPersonaSchemaIsStrict() {
        #expect(strict(Personas.taskSchema))
        #expect(Persona.allCases.allSatisfy { strict(Personas.moveSchema(for: $0)) })
    }

    @Test func aScreenReaderUserGetsWordsOnlyAndNoIconGlyphs() {
        let frame = CGRect(x: 0, y: 0, width: 60, height: 60)
        let screen = Screen(device: "iPhone 17", frame: .init(x: 0, y: 0, width: 300, height: 650), scale: 1, elements: [
            Element(id: 0, role: "AXButton", subrole: "", label: "\u{E8F4}", value: "", frame: frame, pointFrame: frame, canPress: true),
            Element(id: 1, role: "AXButton", subrole: "", label: "Save word", value: "", frame: frame, pointFrame: frame, canPress: true),
        ])
        let seen = Persona.screenReader.perceive(screen, picture: Picture(jpeg: Data(), size: .init(width: 300, height: 650)))
        #expect(seen.jpeg == nil)
        #expect(seen.text.contains("0. button"))
        #expect(seen.text.contains("1. Save word, button"))
        #expect(!seen.text.contains("\u{E8F4}") && !seen.text.contains("<icon>"))
    }

    @Test func seeingPersonasTouchAndScreenReaderUsersActivate() {
        let actions = { (persona: Persona) in ((Personas.moveSchema(for: persona)["properties"] as? [String: Any])?["action"] as? [String: Any])?["enum"] as? [String] }
        #expect(actions(.screenReader) == ["activate", "done", "giveUp"])
        #expect(actions(.colorVision) == ["touch", "done", "giveUp"])
    }

    @Test func theSameHandMissesTheSameWayEveryRunAndTheControlIsApart() {
        #expect(Persona.dexterity.tremor == Persona.dexterity.tremor)
        #expect(Persona.dexterity.tremor.count > 3 && Persona.dexterity.tremor.allSatisfy { $0 != .zero })
        #expect(Persona.colorVision.tremor == [.zero])
        #expect(!Persona.people.contains(.control) && Persona.people.count == 6)
    }

    @Test func textInsideACardGetsItsOwnMarkAndTextOnItsOwnButtonDoesNot() {
        let card = CGRect(x: 0, y: 100, width: 300, height: 400)
        let save = CGRect(x: 20, y: 520, width: 120, height: 44)
        let screen = Screen(device: "iPhone 17", frame: .init(x: 0, y: 0, width: 300, height: 650), scale: 1, elements: [
            Element(id: 0, role: "AXGenericElement", subrole: "", label: "der Bahnhof, Learn again, I know it", value: "", frame: card, pointFrame: card, canPress: true),
            Element(id: 1, role: "AXButton", subrole: "", label: "Save", value: "", frame: save, pointFrame: save, canPress: true),
        ])
        let picture = Picture(jpeg: Data(), size: .init(width: 300, height: 650))
        let lines = [
            Reading.Line(text: "I know it", box: CGRect(x: 180, y: 440, width: 80, height: 20)),
            Reading.Line(text: "Save", box: CGRect(x: 60, y: 532, width: 40, height: 20)),
        ]
        let seen = Persona.colorVision.perceive(screen, picture: picture, lines: lines)
        #expect(seen.spots == [Persona.firstSpot: CGPoint(x: 220, y: 450)])
        #expect(Persona.screenReader.perceive(screen, picture: picture, lines: lines).spots.isEmpty)
    }
}

@MainActor
struct TextSizeTests {
    let task = ScreenTask(goal: "Open the Weather set", success: "The Weather set is open")

    func search(breaksFrom first: TextSize?) async throws -> (PersonaRun.Boundary, [TextSize]) {
        var tried: [TextSize] = []
        let (boundary, _) = try await Personas.boundary(of: task, upTo: .accessibilityExtraLarge) { size in
            tried.append(size)
            var run = PersonaRun(persona: .control, task: task)
            run.achieved = first.map { size < $0 } ?? true
            run.why = "The set row is cut off at \(size.percent)%"
            return run
        }
        return (boundary, tried)
    }

    @Test func findsTheFirstSizeThatBreaksInAFewTries() async throws {
        let (boundary, tried) = try await search(breaksFrom: .extraExtraExtraLarge)
        #expect(boundary.holds == .extraExtraLarge)
        #expect(boundary.breaks == .extraExtraExtraLarge)
        #expect(boundary.why == "The set row is cut off at 135%")
        #expect(tried.count <= 4)
    }

    @Test func aLayoutThatHoldsIsTriedOnce() async throws {
        let (boundary, tried) = try await search(breaksFrom: nil)
        #expect(boundary.holds == .accessibilityExtraLarge && boundary.breaks == nil)
        #expect(tried == [.accessibilityExtraLarge])
    }

    @Test func sizesReadAsPercent() {
        #expect(TextSize.large.title == "default text size")
        #expect(TextSize.accessibilityLarge.title == "text at 194%")
        #expect(Persona.lowVision.textSize! > .extraExtraExtraLarge)
    }
}
