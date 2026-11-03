import Foundation

/// What is drawn on a screen to be pressed, found in the picture by SAM 3.1, set against
/// what VoiceOver can reach there: each thing reachable by its own name, buried inside
/// something bigger or nameless, or nothing VoiceOver can press at all.
struct XRay: Codable {
    enum State: String, Codable {
        case reachable, buried, missing
    }

    struct Spot: Codable {
        /// Where it is drawn, in parts of the picture, from the top left.
        let box: CGRect
        let state: State
    }

    var spots: [Spot]

    func count(_ state: State) -> Int { spots.filter { $0.state == state }.count }

    /// What SAM 3.1 is asked to find; each a separate look at the picture.
    static let concepts = ["button", "icon"]
    /// SAM 3.1 at Standard prices, per picture.
    static let pricePerImage = 0.0025

    /// Everything SAM 3.1 finds drawn to be pressed, in parts of the picture.
    static func look(at picture: Picture, client: ModelClient) async throws -> ([CGRect], ModelClient.Usage) {
        var boxes: [CGRect] = []
        var usage = ModelClient.Usage()
        for concept in concepts {
            for box in try await client.segment(concept, in: picture.jpeg) where !boxes.contains(where: { $0.overlap(box) > 0.5 }) {
                boxes.append(box)
            }
            usage.cost += pricePerImage
        }
        return (boxes, usage)
    }

    /// Sets each thing drawn against the element VoiceOver has there. Plain words that only
    /// look like a button, a badge say, are left out, unless a check found a problem with them.
    static func judge(_ boxes: [CGRect], on screen: Screen, picture: Picture, flagged: Set<Int> = []) -> XRay {
        let size = picture.size
        let elements = screen.elements.map { element -> (Element, CGRect) in
            let frame = Review.toPicture(element.frame, screen: screen, picture: picture)
            return (element, CGRect(x: frame.minX / size.width, y: frame.minY / size.height, width: frame.width / size.width, height: frame.height / size.height))
        }
        let spots = boxes
            // Not the status bar, and not whole panels taken for one big button.
            .filter { $0.minY > 0.06 && $0.width * $0.height < 0.25 }
            .compactMap { box -> Spot? in
                let center = CGPoint(x: box.midX, y: box.midY)
                let around = elements.filter { $0.1.contains(center) }
                    .min { $0.1.width * $0.1.height < $1.1.width * $1.1.height }
                guard let (element, frame) = around else { return Spot(box: box, state: .missing) }
                let own = frame.width * frame.height <= box.width * box.height * 6
                let named = !element.readableLabel.isEmpty && !element.label.withIconsNamed.contains("<icon>")
                // Drawn as a button, but what VoiceOver has there is not one: nothing to press.
                // Words VoiceOver reads well may just be a label; only a known problem counts.
                if own && !element.isControl {
                    return !named || flagged.contains(element.id) ? Spot(box: box, state: .missing) : nil
                }
                return Spot(box: box, state: element.isControl && own && named ? .reachable : .buried)
            }
        return XRay(spots: spots)
    }
}

extension ModelClient {
    /// Everything in a picture that fits a short phrase, found by SAM 3.1: boxes in parts of
    /// the picture, from the top left.
    func segment(_ concept: String, in jpeg: Data) async throws -> [CGRect] {
        var request = URLRequest(url: Self.base.appending(path: "responses"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        let body: [String: Any] = [
            "model": "sam-3.1",
            "input": [["role": "user", "content": [
                ["type": "input_text", "text": concept],
                ["type": "input_image", "image_url": "data:image/jpeg;base64," + jpeg.base64EncodedString()],
            ]]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Problem.failed(status: status, message: String(decoding: data.prefix(300), as: UTF8.self)) }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let text = ((json?["output"] as? [[String: Any]]) ?? []).flatMap { ($0["content"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["text"] as? String }.joined()
        return Self.boxes(in: text)
    }

    /// The boxes in SAM's answer: `<|box;x1=…;y1=…;x2=…;y2=…;w=…;h=…|>`, in source pixels.
    static func boxes(in text: String) -> [CGRect] {
        text.matches(of: /<\|box;x1=(\d+);y1=(\d+);x2=(\d+);y2=(\d+);w=(\d+);h=(\d+)/).compactMap { match in
            guard let x1 = Double(match.1), let y1 = Double(match.2), let x2 = Double(match.3), let y2 = Double(match.4),
                  let w = Double(match.5), let h = Double(match.6), w > 0, h > 0 else { return nil }
            return CGRect(x: x1 / w, y: y1 / h, width: (x2 - x1) / w, height: (y2 - y1) / h)
        }
    }
}
