import CoreGraphics
import Foundation

/// The check that needs eyes: the model looks at the screenshot and at what VoiceOver
/// reads, and reports where the two disagree. A button that is drawn but not in the
/// accessibility tree, or a tab called "AddCard" in a Russian app, cannot be found from
/// the elements alone.
enum Review {
    /// Below this the model is guessing.
    static let minimumConfidence = 0.6

    /// What the model made of a screen.
    struct Seen: Codable {
        let issues: [Issue]
        /// What a person would call the screen: "Profile", "Card", "Sets".
        let name: String
        /// The tab it is under, as the selected tab is drawn; nil without a tab bar.
        let section: String?
        /// Where elements whose frames miss them are really drawn, on the Mac's screen;
        /// optional, so checks kept before it existed still load.
        let places: [Int: CGRect]?
        let usage: ModelClient.Usage
        /// In seconds.
        let time: Double
    }

    static func run(_ screen: Screen, picture: Picture, found: [Issue], client: ModelClient) async throws -> Seen {
        let start = Date()
        let (answer, usage) = try await client.answer(
            Answer.self,
            schemaName: "screen_review",
            schema: schema,
            instructions: instructions,
            input: [.jpeg(picture.jpeg), .text(describe(screen, picture: picture, found: found))]
        )
        let section = answer.section.flatMap { $0.isEmpty ? nil : $0 }
        return Seen(issues: issues(from: answer, screen: screen, picture: picture), name: answer.screen, section: section, places: places(from: answer, screen: screen, picture: picture), usage: usage, time: Date().timeIntervalSince(start))
    }

    static let instructions = """
    You check iOS app screens for people who use VoiceOver. You get a screenshot of one \
    screen and the accessibility elements VoiceOver reads on it, in reading order, with \
    frames in the screenshot's pixels. Find where what is drawn and what VoiceOver reads \
    disagree. Report only these kinds:

    - notExposed: something drawn that a person must read or can act on (a button, an icon \
    button, a menu "⋮" or "…", a link, a text field, text with information) that no element \
    covers, so VoiceOver skips it. Leave elements empty.
    - unlabeledIcon: an icon or image that acts or informs, whose element has no label or \
    only part of one (a label that starts or ends with ", " because the icon in it has none).
    - unclearLabel: a label that does not say what the thing is or does: a code name \
    ("AddCard", "btn_close", "ic_menu"), a file name, words run together, a symbol read \
    literally, a label that differs from the visible text so a Voice Control user cannot \
    say it.
    - wrongLanguage: a label in another language than the text on the screen.
    - wrongRole: something that looks and acts like a button, tab, filter chip, switch or \
    link but is read as plain text or a plain element, or whose selected or on/off state \
    is not read.
    - wrongFrame: an element whose frame clearly misses the thing drawn: much smaller, \
    shifted, or covering something else. VoiceOver's cursor and double tap land there.
    - merged: an element that reads several things as one while something inside it is \
    drawn as its own button, switch or link, so that can not be reached or activated on its \
    own. A list row or card read whole, with nothing to press inside, is fine.
    - decorative: a purely decorative image, divider or background that VoiceOver stops on.

    Always fill these two lists, checking every element against the screenshot:
    - hidden: the id of every element VoiceOver reads that cannot be seen: covered, behind \
    a card or sheet, scrolled away, transparent. When a card or page is stacked behind \
    the visible one, all of its elements count, its icons and empty ones too.
    - places: for every element under "Flat frames", and any other whose frame misses the \
    thing it stands for, the box where that thing is really drawn.

    Also name the screen: screen is what a person would call it ("Profile", "Card", \
    "Sets", "Add card"), from its title or what it shows; section is the name of the tab \
    that is drawn as selected, in plain words even when its label is wrong, or null when \
    there is no tab bar.

    Rules:
    - Report only what the screenshot shows. When you are not sure, leave it out or give a \
    low confidence.
    - Do not report target sizes, nothing in "Already found", and nothing hidden: the \
    hidden list says that.
    - "Labels with a gap" have an icon inside that has no label. Report one, as \
    unlabeledIcon, only when that icon does or means something the text does not say (a \
    "⋮" menu, a delete button, a status). An icon beside text that says the same, or a \
    chevron, is fine.
    - The status bar at the top (time, signal, battery) belongs to iOS; ignore it.
    - elements are ids from the list. boxes, in the screenshot's pixels, are where the \
    things are drawn: one per element in the same order, or for notExposed one per thing \
    VoiceOver skips.
    - When one problem repeats on elements of the same kind (every tab, every row of a \
    list), report it once with all their ids.
    - Write title and detail in English, whatever the language of the screen.
    - title: one short line naming the thing ("The ⋮ menu button is missing for VoiceOver").
    - detail: what VoiceOver says or skips now, quoting it, and what that means for someone \
    who cannot see the screen. One or two sentences, plain English.
    - suggestedLabel: a label in the language of the screen's text, or null.
    - severity: blocker when a VoiceOver user cannot find, understand or activate it; \
    serious when it is confusing but usable.
    """

    /// What is on the screen, in the screenshot's coordinates.
    static func describe(_ screen: Screen, picture: Picture, found: [Issue]) -> String {
        var lines = [
            "Screenshot: \(Int(picture.size.width))×\(Int(picture.size.height)) px.",
            "",
            "Elements VoiceOver reads (id | role | label | value | frame x,y,w,h):",
        ]
        for element in screen.elements {
            let frame = toPicture(element.frame, screen: screen, picture: picture)
            let box = [frame.minX, frame.minY, frame.width, frame.height].map { String(Int($0.rounded())) }.joined(separator: ",")
            lines.append("\(element.id) | \(role(element)) | \(element.label) | \(element.value) | \(box)")
        }
        let flat = screen.elements.filter(\.isSliver).map { "#\($0.id)" }
        lines += ["", "Flat frames:", flat.isEmpty ? "none" : flat.joined(separator: " ")]
        let long = Audit.merged(screen.elements).flatMap(\.elements)
        lines += ["", "Long labels read as one:", long.isEmpty ? "none" : long.map { "#\($0)" }.joined(separator: " ")]
        let gaps = Audit.gaps(screen.elements)
        lines += ["", "Labels with a gap:", gaps.isEmpty ? "none" : gaps.map { "#\($0.id)" }.joined(separator: " ")]
        lines += ["", "Already found:"]
        lines += found.isEmpty ? ["nothing"] : found.map { "- \($0.elements.map { "#\($0)" }.joined(separator: " ")) \($0.title)" }
        return lines.joined(separator: "\n")
    }

    static func issues(from answer: Answer, screen: Screen, picture: Picture) -> [Issue] {
        let found: [Issue] = answer.findings.compactMap { finding in
            guard finding.confidence >= minimumConfidence, let kind = Issue.Kind(rawValue: finding.kind) else { return nil }
            let elements = kind == .notExposed ? [] : finding.elements.compactMap { id in screen.elements.first { $0.id == id } }
            let boxes = finding.boxes.map { toScreen(CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height), screen: screen, picture: picture) }
            let union = { (rects: [CGRect]) in rects.reduce(nil) { $0?.union($1) ?? $1 } }
            guard let frame = union(elements.map(\.frame)) ?? union(boxes) else { return nil }
            return Issue(
                kind: kind,
                severity: finding.severity == "blocker" ? .blocker : .serious,
                title: finding.title,
                detail: finding.detail,
                wcag: wcag(kind),
                elements: elements.map(\.id),
                frame: frame,
                suggestion: finding.suggestedLabel.flatMap { $0.isEmpty ? nil : $0 },
                byModel: true,
                drawn: boxes
            )
        }
        return found + [hidden(answer.hidden, screen: screen)].compactMap { $0 }
    }

    /// Everything VoiceOver reads that nobody sees, as one issue.
    static func hidden(_ ids: [Int], screen: Screen) -> Issue? {
        let elements = Set(ids).sorted().compactMap { id in screen.elements.first { $0.id == id } }
        guard let first = elements.first else { return nil }
        let heard = elements.map(\.readableLabel).filter { !$0.isEmpty }.prefix(3).map { "\"\($0)\"" }.joined(separator: ", ")
        return Issue(
            kind: .hidden,
            severity: .serious,
            title: elements.count == 1 ? "VoiceOver reads something that is not on screen" : "VoiceOver reads \(elements.count) things that are not on screen",
            detail: heard.isEmpty
                ? "Swiping stops on buttons that nobody can see, behind or outside what is shown."
                : "It reads \(heard)… which nobody can see: content behind or outside what is shown. Swiping reaches it as if it were there.",
            wcag: wcag(.hidden),
            elements: elements.map(\.id),
            frame: elements.dropFirst().reduce(first.frame) { $0.union($1.frame) },
            byModel: true
        )
    }

    /// Where the model saw elements whose frames miss them; a place that is the frame
    /// again corrects nothing.
    static func places(from answer: Answer, screen: Screen, picture: Picture) -> [Int: CGRect] {
        var places: [Int: CGRect] = [:]
        for place in answer.places {
            guard let element = screen.elements.first(where: { $0.id == place.element }) else { continue }
            let box = toScreen(CGRect(x: place.box.x, y: place.box.y, width: place.box.width, height: place.box.height), screen: screen, picture: picture)
            if element.frame.overlap(box) < 0.5 { places[element.id] = box }
        }
        return places
    }

    static func wcag(_ kind: Issue.Kind) -> String {
        switch kind {
        case .unlabeledIcon, .decorative: "1.1.1 Non-text Content"
        case .merged: "1.3.1 Info and Relationships"
        case .unclearLabel: "2.5.3 Label in Name, 4.1.2 Name, Role, Value"
        case .wrongLanguage: "3.1.2 Language of Parts"
        case .wrongFrame: "1.3.2 Meaningful Sequence, 2.5.8 Target Size"
        case .hidden: "1.3.2 Meaningful Sequence, 2.4.3 Focus Order"
        default: "4.1.2 Name, Role, Value"
        }
    }

    private static func role(_ element: Element) -> String {
        if element.subrole == "AXSwitch" { return "switch" }
        if element.role == "AXStaticText" { return "text" }
        if element.role == "AXGenericElement" { return element.isControl ? "element, pressable" : "element" }
        return element.role.replacingOccurrences(of: "AX", with: "").lowercased()
    }

    /// From the Mac's screen to the screenshot's pixels.
    static func toPicture(_ rect: CGRect, screen: Screen, picture: Picture) -> CGRect {
        let k = picture.size.width / screen.frame.width
        return CGRect(x: (rect.minX - screen.frame.minX) * k, y: (rect.minY - screen.frame.minY) * k, width: rect.width * k, height: rect.height * k)
    }

    /// From the screenshot's pixels to the Mac's screen.
    static func toScreen(_ rect: CGRect, screen: Screen, picture: Picture) -> CGRect {
        let k = screen.frame.width / picture.size.width
        return CGRect(x: screen.frame.minX + rect.minX * k, y: screen.frame.minY + rect.minY * k, width: rect.width * k, height: rect.height * k)
    }

    struct Answer: Decodable {
        struct Finding: Decodable {
            struct Box: Decodable {
                let x, y, width, height: Double
            }

            let kind: String
            let elements: [Int]
            let boxes: [Box]
            let title: String
            let detail: String
            let suggestedLabel: String?
            let severity: String
            let confidence: Double
        }

        struct Place: Decodable {
            let element: Int
            let box: Finding.Box
        }

        let screen: String
        let section: String?
        let hidden: [Int]
        let places: [Place]
        let findings: [Finding]
    }

    static let schema: [String: Any] = {
        func object(_ properties: [String: Any]) -> [String: Any] {
            ["type": "object", "properties": properties, "required": Array(properties.keys).sorted(), "additionalProperties": false]
        }
        func nullable(_ type: [String: Any]) -> [String: Any] {
            ["anyOf": [type, ["type": "null"]]]
        }
        let number = ["type": "number"]
        let box = object(["x": number, "y": number, "width": number, "height": number])
        let finding = object([
            "kind": ["type": "string", "enum": ["notExposed", "unlabeledIcon", "unclearLabel", "wrongLanguage", "wrongRole", "wrongFrame", "merged", "decorative"]],
            "elements": ["type": "array", "items": ["type": "integer"]],
            "boxes": ["type": "array", "items": box],
            "title": ["type": "string"],
            "detail": ["type": "string"],
            "suggestedLabel": nullable(["type": "string"]),
            "severity": ["type": "string", "enum": ["blocker", "serious"]],
            "confidence": ["type": "number", "description": "0 to 1"],
        ])
        return object([
            "screen": ["type": "string"],
            "section": nullable(["type": "string"]),
            "hidden": ["type": "array", "items": ["type": "integer"]],
            "places": ["type": "array", "items": object(["element": ["type": "integer"], "box": box])],
            "findings": ["type": "array", "items": finding],
        ])
    }()
}
