import Foundation

/// The Simulator's text size, the Dynamic Type setting people change in Settings → Display &
/// Text Size → Larger Text. Default and up; the five accessibility sizes come last.
enum TextSize: String, Codable, CaseIterable, Comparable {
    case large
    case extraLarge = "extra-large"
    case extraExtraLarge = "extra-extra-large"
    case extraExtraExtraLarge = "extra-extra-extra-large"
    case accessibilityMedium = "accessibility-medium"
    case accessibilityLarge = "accessibility-large"
    case accessibilityExtraLarge = "accessibility-extra-large"
    case accessibilityExtraExtraLarge = "accessibility-extra-extra-large"
    case accessibilityExtraExtraExtraLarge = "accessibility-extra-extra-extra-large"

    /// Body text at this size against the default, 17 points: what people can picture.
    var percent: Int {
        let points: [TextSize: Double] = [.large: 17, .extraLarge: 19, .extraExtraLarge: 21, .extraExtraExtraLarge: 23, .accessibilityMedium: 28,
                                          .accessibilityLarge: 33, .accessibilityExtraLarge: 40, .accessibilityExtraExtraLarge: 47, .accessibilityExtraExtraExtraLarge: 53]
        return Int((points[self]! / 17 * 100).rounded())
    }

    var title: String { self == .large ? "default text size" : "text at \(percent)%" }

    static func < (a: TextSize, b: TextSize) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }

    /// What the Simulator is set to now; nil when it is smaller than the default or unknown.
    @concurrent nonisolated static func current() async -> TextSize? {
        TextSize(rawValue: simctl("content_size").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @concurrent nonisolated static func set(_ size: TextSize) async {
        simctl("content_size", size.rawValue)
    }

    /// Does the work with the Simulator at this size, then puts back what was set before,
    /// whether the work finished, failed or was stopped. Apps follow the change on their own;
    /// time is left for them to lay out again.
    static func with<T>(_ size: TextSize?, _ work: () async throws -> T) async throws -> T {
        guard let size else { return try await work() }
        let before = await current() ?? .large
        await set(size)
        try? await Task.sleep(for: .milliseconds(800))
        do {
            let result = try await work()
            await set(before)
            return result
        } catch {
            await set(before)
            throw error
        }
    }

    @discardableResult
    nonisolated private static func simctl(_ arguments: String...) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "ui", "booted"] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return "" }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
