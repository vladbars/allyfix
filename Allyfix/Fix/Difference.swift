import AppKit

/// Where two screenshots of the same screen differ, so a change can be pointed at: the
/// pictures are shrunk, compared pixel by pixel, and the changed pixels grouped into boxes.
enum Difference {
    /// The shrunk width; small enough to skip JPEG noise, big enough for a button.
    static let width = 90
    /// How much a pixel's brightness must change, out of 255.
    static let threshold = 22

    /// The places that changed, biggest first, at most `limit`, in unit coordinates (0 to 1,
    /// from the top left). The status bar is left out: its clock always changes.
    static func regions(_ before: Data, _ after: Data, limit: Int = 3) -> [CGRect] {
        guard let a = gray(before), let b = gray(after, size: a.size) else { return [] }
        let (w, h) = a.size
        let top = Int(Double(h) * 0.06)
        var changed = [Bool](repeating: false, count: w * h)
        for y in top..<h {
            for x in 0..<w where abs(Int(a.pixels[y * w + x]) - Int(b.pixels[y * w + x])) > threshold {
                changed[y * w + x] = true
            }
        }
        // Group touching changed pixels into boxes.
        var seen = [Bool](repeating: false, count: w * h)
        var boxes: [(minX: Int, minY: Int, maxX: Int, maxY: Int, count: Int)] = []
        for start in 0..<(w * h) where changed[start] && !seen[start] {
            var stack = [start], box = (minX: w, minY: h, maxX: 0, maxY: 0, count: 0)
            seen[start] = true
            while let index = stack.popLast() {
                let x = index % w, y = index / w
                box = (min(box.minX, x), min(box.minY, y), max(box.maxX, x), max(box.maxY, y), box.count + 1)
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                        let next = ny * w + nx
                        if changed[next] && !seen[next] {
                            seen[next] = true
                            stack.append(next)
                        }
                    }
                }
            }
            if box.count >= 3 { boxes.append(box) }
        }
        // Boxes close together are one change.
        var merged: [CGRect] = boxes.map { CGRect(x: $0.minX, y: $0.minY, width: $0.maxX - $0.minX + 1, height: $0.maxY - $0.minY + 1) }
        var joined = true
        while joined {
            joined = false
            outer: for i in merged.indices {
                for j in merged.indices where j > i && merged[i].insetBy(dx: -3, dy: -3).intersects(merged[j]) {
                    merged[i] = merged[i].union(merged[j])
                    merged.remove(at: j)
                    joined = true
                    break outer
                }
            }
        }
        return merged.sorted { $0.width * $0.height > $1.width * $1.height }.prefix(limit).map {
            CGRect(x: $0.minX / CGFloat(w), y: $0.minY / CGFloat(h), width: $0.width / CGFloat(w), height: $0.height / CGFloat(h))
        }
    }

    /// A part of a picture, around a place given in unit coordinates, with room around it.
    static func closeUp(_ jpeg: Data, around place: CGRect) -> NSImage? {
        guard let image = NSImage(data: jpeg)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        var crop = CGRect(x: place.minX * w, y: place.minY * h, width: place.width * w, height: place.height * h)
        let margin = max(crop.width, crop.height) * 0.35 + 0.04 * w
        crop = crop.insetBy(dx: -margin, dy: -margin).intersection(CGRect(x: 0, y: 0, width: w, height: h)).integral
        guard let part = image.cropping(to: crop) else { return nil }
        return NSImage(cgImage: part, size: crop.size)
    }

    private static func gray(_ jpeg: Data, size: (Int, Int)? = nil) -> (pixels: [UInt8], size: (Int, Int))? {
        guard let image = NSImage(data: jpeg)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = size?.0 ?? width
        let h = size?.1 ?? max(1, Int((Double(image.height) / Double(image.width) * Double(w)).rounded()))
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // A bitmap context keeps the picture's top row first.
        return (pixels, (w, h))
    }
}
