import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A screenshot of the iPhone's screen, small enough to send to the model.
nonisolated struct Picture: Sendable {
    enum Problem: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let why): "Could not take a screenshot of the Simulator: \(why)"
            }
        }
    }

    let jpeg: Data
    /// In pixels.
    let size: CGSize

    /// Takes a screenshot of the booted device named in the Simulator window's title,
    /// scaled so its longer side is `longSide` pixels.
    @concurrent static func take(device: String, longSide: Int = 1280) async throws -> Picture {
        let file = FileManager.default.temporaryDirectory.appending(path: "allyfix-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        _ = try simctl(["io", bootedDevice(named: device), "screenshot", "--type=png", file.path])

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: longSide,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { throw Problem.failed("unreadable image") }

        let jpeg = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil) else { throw Problem.failed("no JPEG encoder") }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Problem.failed("could not encode JPEG") }
        return Picture(jpeg: jpeg as Data, size: CGSize(width: image.width, height: image.height))
    }

    /// The booted device's UDID, so the screenshot is of the device in the window even when
    /// several are booted.
    private static func bootedDevice(named title: String) throws -> String {
        let name = title.components(separatedBy: " – ").first ?? title
        let list = try JSONSerialization.jsonObject(with: simctl(["list", "devices", "booted", "--json"])) as? [String: Any]
        let devices = (list?["devices"] as? [String: [[String: Any]]] ?? [:]).values.joined()
        let match = devices.first { $0["name"] as? String == name } ?? devices.first
        return match?["udid"] as? String ?? "booted"
    }

    private static func simctl(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl"] + arguments
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Problem.failed(String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return data
    }
}
