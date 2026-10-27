import CoreGraphics
import Foundation
import ImageIO

/// Finds what is drawn in a screenshot, where a model would only guess the coordinates.
enum Ink {
    /// How far below a flat frame to look for what it stands for, in iPhone points.
    static let depth: CGFloat = 64
    /// How different from the background a pixel must be to count as drawn, 0 to 255.
    static let contrast = 48

    /// What is drawn under a flat frame, like the icon under a tab's 10-point strip: the
    /// bounds of everything that stands out from the background in the frame's columns,
    /// from its top down. On the Mac's screen, or nil when nothing is drawn there.
    static func below(_ frame: CGRect, on screen: Screen, picture jpeg: Data) -> CGRect? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        let unit = screen.unit(frame)
        let down = depth * screen.scale / screen.frame.height
        let left = max(0, Int(unit.minX * CGFloat(width))), right = min(width, Int(unit.maxX * CGFloat(width)))
        let top = max(0, Int(unit.minY * CGFloat(height))), bottom = min(height, Int((unit.minY + down) * CGFloat(height)))
        guard right - left > 2, bottom - top > 2 else { return nil }

        func color(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * width + x) * 4
            return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
        }
        // The background is the commonest color, a little rounded so JPEG noise agrees.
        var counts: [Int: Int] = [:]
        for y in top..<bottom { for x in left..<right {
            let (r, g, b) = color(x, y)
            counts[(r >> 4) << 8 | (g >> 4) << 4 | b >> 4, default: 0] += 1
        } }
        guard let common = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        let background = ((common >> 8 & 15) * 16 + 8, (common >> 4 & 15) * 16 + 8, (common & 15) * 16 + 8)

        var minX = right, minY = bottom, maxX = left, maxY = top, found = 0
        for y in top..<bottom { for x in left..<right {
            let (r, g, b) = color(x, y)
            guard max(abs(r - background.0), abs(g - background.1), abs(b - background.2)) > contrast else { continue }
            found += 1
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        // A few stray pixels are noise, not a drawn thing.
        guard found >= 12 else { return nil }
        let k = screen.frame.width / CGFloat(width)
        return CGRect(x: screen.frame.minX + CGFloat(minX) * k, y: screen.frame.minY + CGFloat(minY) * k,
                      width: CGFloat(maxX - minX + 1) * k, height: CGFloat(maxY - minY + 1) * k)
    }
}
