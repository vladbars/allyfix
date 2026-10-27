import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Text read off a screenshot, the way a sighted person reads it, whether or not the app
/// tells VoiceOver about it. Done on the Mac, with no model.
nonisolated enum Reading {
    struct Line: Sendable {
        let text: String
        /// In the screenshot's pixels, from the top left.
        let box: CGRect
    }

    @concurrent static func lines(in jpeg: Data) async -> [Line] {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US", "de-DE"]
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let width = CGFloat(image.width), height = CGFloat(image.height)
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            // Vision counts from the bottom left, in parts of the image.
            let b = observation.boundingBox
            return Line(text: text, box: CGRect(x: b.minX * width, y: (1 - b.maxY) * height, width: b.width * width, height: b.height * height))
        }
    }
}
