import AppKit
import CoreImage
import Foundation
import ImageIO

/// Someone with a disability who tries the app, played by the model with only what that
/// person can perceive. Named by the access need and the tool, never by a name, gender, age
/// or origin. Chosen after EN 301 549 §4.2, the standard the EAA points to.
enum Persona: String, Codable, CaseIterable, Identifiable {
    case screenReader, lowVision, colorVision, deaf, dexterity, cognitive
    /// No limitation: the control. A task it cannot do says nothing about accessibility.
    case control

    /// The people the test is about; the control runs first and apart.
    static let people: [Persona] = [.screenReader, .lowVision, .colorVision, .deaf, .dexterity, .cognitive]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenReader: "Screen reader user"
        case .lowVision: "Low vision"
        case .colorVision: "Color vision deficiency"
        case .deaf: "Deaf or hard of hearing"
        case .dexterity: "Limited dexterity"
        case .cognitive: "Cognitive and learning"
        case .control: "Without a disability"
        }
    }

    /// The clause of EN 301 549 the persona stands for.
    var clause: String {
        switch self {
        case .screenReader: "§4.2.1"
        case .lowVision: "§4.2.2"
        case .colorVision: "§4.2.3"
        case .deaf: "§4.2.4–5"
        case .dexterity: "§4.2.7"
        case .cognitive: "§4.2.10"
        case .control: "Control"
        }
    }

    var symbol: String {
        switch self {
        case .screenReader: "headphones"
        case .lowVision: "magnifyingglass"
        case .colorVision: "circle.lefthalf.filled"
        case .deaf: "speaker.slash"
        case .dexterity: "hand.tap"
        case .cognitive: "questionmark.bubble"
        case .control: "person"
        }
    }

    /// What the persona gets, in a line.
    var perceives: String {
        switch self {
        case .screenReader: "Hears VoiceOver, sees nothing"
        case .lowVision: "Text at 235%, still blurred"
        case .colorVision: "Can't tell red from green"
        case .deaf: "Knows a sound played, not what"
        case .dexterity: "Taps land a few points off"
        case .cognitive: "No habits from other apps"
        case .control: "Sees, hears and taps as designed"
        }
    }

    /// Whether Allyfix can play this persona yet. A deaf persona needs the app's sound,
    /// which the Simulator does not hand over yet.
    var ready: Bool { self != .deaf }

    /// Who the model is to be, in its own words.
    var role: String {
        switch self {
        case .screenReader:
            """
            You are blind and use VoiceOver on your iPhone every day. You cannot see the screen \
            at all. You know only what VoiceOver says, in the order you reach it by swiping. You \
            act like an experienced VoiceOver user: you swipe through what is read and \
            double-tap the element you want. You never guess at anything you could not have \
            heard.
            """
        case .lowVision:
            """
            You have low vision. Your iPhone's text is set far larger than usual, and even \
            with your glasses the screen looks as blurred as the screenshot you get. You can \
            make out large shapes and big, high-contrast text; small or faint text and thin \
            icons you cannot read. You never guess at what you cannot make out.
            """
        case .colorVision:
            """
            You have deuteranopia: you cannot tell red from green, and colors that differ only \
            in those look the same to you. The screenshot you get is what you see. You use the \
            app by touching what you see, and you notice when something seems to be told only \
            by color.
            """
        case .deaf:
            """
            You are deaf. You see the screen normally but hear nothing the app plays. You notice \
            when something seems to happen only as sound.
            """
        case .dexterity:
            """
            You have a tremor in your hands. You see the screen normally, but your taps land a \
            few points away from where you aim, so small controls are hard to hit. You notice \
            when a tap missed and try again, and you give up when a target is too small to hit.
            """
        case .control:
            """
            You use iPhone apps every day and have no disability. You see the screen clearly and \
            tap exactly where you aim.
            """
        case .cognitive:
            """
            You find new apps hard to figure out and have no habits from other apps: an icon \
            means nothing to you unless words or the context make it clear, and you do not \
            know hidden gestures. You read what is on the screen and act only on what it says. \
            When you cannot tell what something does, you say so.
            """
        }
    }

    /// The text size the persona has set on the phone: someone with low vision makes text
    /// larger, past the 200% WCAG asks text to work at. The others keep the default.
    var textSize: TextSize? { self == .lowVision ? .accessibilityExtraLarge : nil }

    /// Whether the persona gets a picture of the screen at all.
    var sees: Bool { self != .screenReader }

    /// Where each tap lands from its aim, in iPhone points, in order: the same misses on every
    /// run, so a test before a fix and after it face the same hand.
    var tremor: [CGPoint] {
        guard self == .dexterity else { return [.zero] }
        return [CGPoint(x: 7, y: -6), CGPoint(x: -8, y: 5), CGPoint(x: 4, y: 9), CGPoint(x: -9, y: -4), CGPoint(x: 6, y: 7), CGPoint(x: -5, y: -8)]
    }

    /// What a persona gets of a screen, and where marks that are not elements point.
    struct Perceived {
        let text: String
        let jpeg: Data?
        /// Marks on text the app gives no element of its own, by mark number: where to touch,
        /// in iPhone points.
        var spots: [Int: CGPoint] = [:]
    }

    /// The first number of marks put on text read off the screen, apart from element ids.
    static let firstSpot = 1000

    /// The screen as this persona perceives it: words for one, a picture for the others.
    /// `lines` is the text read off the screenshot; a line that sits inside a big element
    /// rather than its own, like a button merged into a card, gets a mark of its own, since a
    /// seeing person can touch it all the same.
    func perceive(_ screen: Screen, picture: Picture, lines: [Reading.Line] = []) -> Perceived {
        guard sees else {
            let heard = screen.elements.map { "\($0.id). \(Audit.spoken($0).withIconsNamed.replacingOccurrences(of: "<icon>", with: ""))" }
            return Perceived(text: "What VoiceOver reads, in swipe order (number. what you hear):\n" + heard.joined(separator: "\n"), jpeg: nil)
        }
        var spots: [Int: CGPoint] = [:], extra: [(Int, CGRect)] = []
        for (index, line) in lines.enumerated() where line.box.minY > picture.size.height * 0.06 {
            let box = Review.toScreen(line.box, screen: screen, picture: picture)
            let center = CGPoint(x: box.midX, y: box.midY)
            let own = screen.elements.filter { $0.frame.contains(center) }.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
            // Its own element says it, or is not much bigger than it: not hidden in something else.
            if let own, (own.readableLabel.localizedCaseInsensitiveContains(line.text) && line.text.count * 2 >= own.readableLabel.count)
                || own.frame.width * own.frame.height < box.width * box.height * 20 { continue }
            let id = Self.firstSpot + index
            spots[id] = CGPoint(x: (center.x - screen.frame.minX) / screen.scale, y: (center.y - screen.frame.minY) / screen.scale)
            extra.append((id, line.box))
        }
        let seen: Data
        switch self {
        case .lowVision: seen = Self.blurred(picture.jpeg)
        case .colorVision: seen = Self.deuteranopia(picture.jpeg)
        default: seen = picture.jpeg
        }
        return Perceived(text: """
            Numbered marks sit on things on the screen, whether they can be touched or not, each at \
            the top left of its thing; touch a thing by its mark. To touch something without a mark, give x and y in the \(Int(picture.size.width))×\(Int(picture.size.height)) pixel screenshot.
            """, jpeg: Self.marked(seen, screen: screen, picture: picture, extra: extra), spots: spots)
    }

    /// Marks numbered by element id on what is on the screen, so a seeing persona points at a
    /// mark instead of guessing pixels, which models do badly. On text as well as controls, so
    /// a mark does not tell what can be pressed; a mark that would cover another is left out.
    /// Neutral black and white, drawn after any filter, so they tell nothing by color.
    static func marked(_ jpeg: Data, screen: Screen, picture: Picture, extra: [(Int, CGRect)] = []) -> Data {
        guard let image = NSImage(data: jpeg), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return jpeg }
        let width = cgImage.width, height = cgImage.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return jpeg }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold)
        var placed: [CGRect] = []
        let elements = screen.elements.filter { $0.frame.width > 2 && $0.frame.height > 2 && screen.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
        // Text without an element of its own first, so its mark is not crowded out.
        let marks = extra + elements.map { ($0.id, Review.toPicture($0.frame, screen: screen, picture: picture)) }
        for (id, box) in marks {
            // CoreGraphics counts from the bottom.
            let label = NSAttributedString(string: "\(id)", attributes: [.font: font, .foregroundColor: NSColor.white])
            let size = label.size()
            // Just above the thing, so the mark does not hide its words; inside it at the top edge.
            let above = box.minY - size.height - 4 >= 0 ? box.minY : box.minY + size.height + 4
            let tag = CGRect(x: box.minX, y: CGFloat(height) - above, width: size.width + 8, height: size.height + 4)
            guard !placed.contains(where: { $0.intersects(tag) }) else { continue }
            placed.append(tag)
            context.setFillColor(NSColor.black.withAlphaComponent(0.85).cgColor)
            context.fill(tag)
            label.draw(at: CGPoint(x: tag.minX + 4, y: tag.minY + 2))
        }
        NSGraphicsContext.current = nil
        guard let marked = context.makeImage() else { return jpeg }
        return NSBitmapImageRep(cgImage: marked).representation(using: .jpeg, properties: [.compressionFactor: 0.8]) ?? jpeg
    }

    /// The picture as someone with deuteranopia sees it (Machado et al. 2009, full severity).
    static func deuteranopia(_ jpeg: Data) -> Data {
        filtered(jpeg) { image in
            let filter = CIFilter(name: "CIColorMatrix")!
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(CIVector(x: 0.367, y: 0.861, z: -0.228, w: 0), forKey: "inputRVector")
            filter.setValue(CIVector(x: 0.280, y: 0.673, z: 0.047, w: 0), forKey: "inputGVector")
            filter.setValue(CIVector(x: -0.012, y: 0.043, z: 0.969, w: 0), forKey: "inputBVector")
            return filter.outputImage
        }
    }

    /// The picture as someone with low vision sees it: small text is gone, large shapes stay.
    static func blurred(_ jpeg: Data) -> Data {
        filtered(jpeg) { image in
            image.clampedToExtent().applyingGaussianBlur(sigma: 3.5).cropped(to: image.extent)
        }
    }

    private static func filtered(_ jpeg: Data, _ apply: (CIImage) -> CIImage?) -> Data {
        guard let image = CIImage(data: jpeg), let output = apply(image),
              let data = CIContext().jpegRepresentation(of: output, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.8]) else { return jpeg }
        return data
    }
}
