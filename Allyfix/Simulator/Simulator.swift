import AppKit
import ApplicationServices

/// The iOS Simulator, seen and worked through the Mac's accessibility interface: the
/// Simulator hands the iPhone's own accessibility elements to it, so the app running
/// there can be read and pressed without building or changing anything.
enum Simulator {
    static let bundleID = "com.apple.iphonesimulator"

    enum Problem: LocalizedError {
        case notPermitted
        case notRunning
        case noDevice
        case covered

        var errorDescription: String? {
            switch self {
            case .notPermitted: "Allyfix needs Accessibility access to read the Simulator."
            case .notRunning: "Open your app in the iOS Simulator."
            case .noDevice: "No iPhone is shown in the Simulator."
            case .covered: "Another window covers the Simulator, so Allyfix did not click."
            }
        }
    }

    /// Whether macOS lets Allyfix read other apps; with `ask`, shows the system prompt.
    static func permitted(ask: Bool = false) -> Bool {
        // The value of `kAXTrustedCheckOptionPrompt`, which Swift 6 will not read as a global.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": ask] as CFDictionary)
    }

    /// Everything on the iPhone's screen now.
    static func screen() throws -> Screen {
        guard permitted() else { throw Problem.notPermitted }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { throw Problem.notRunning }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        let windows: [AXUIElement] = root.attribute(kAXWindowsAttribute) ?? []
        for window in windows {
            guard let content = window.firstDescendant(where: { $0.attribute(kAXSubroleAttribute) == "iOSContentGroup" }) else { continue }
            let frame = content.frame ?? .zero
            let scale = frame.width / deviceWidth(forWindowTitle: window.attribute(kAXTitleAttribute) ?? "")
            var elements: [Element] = []
            collect(content, into: &elements, screen: frame, scale: scale)
            return Screen(device: window.attribute(kAXTitleAttribute) ?? "iPhone", frame: frame, scale: scale, elements: elements)
        }
        throw Problem.noDevice
    }

    /// Where the iPhone's screen is on the Mac's screen now, read cheaply enough to follow
    /// the Simulator window as it moves.
    static func contentFrame() -> CGRect? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        let windows: [AXUIElement] = AXUIElementCreateApplication(app.processIdentifier).attribute(kAXWindowsAttribute) ?? []
        return windows.lazy.compactMap { $0.firstDescendant(where: { $0.attribute(kAXSubroleAttribute) == "iOSContentGroup" })?.frame }.first
    }

    /// Activates an element the way a VoiceOver double tap does.
    static func press(_ element: Element) -> Bool {
        guard let ax = element.ax else { return false }
        return AXUIElementPerformAction(ax, kAXPressAction as CFString) == .success
    }

    /// Touches a point on the iPhone's screen with a real click, as a finger would: not a
    /// press of the element there, which for a card holding its own buttons would press the
    /// card. The click happens only once the Simulator's window is the one on top at that
    /// point, so it can never land in another app.
    static func touch(_ point: CGPoint) async throws {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { throw Problem.notRunning }
        // Not in the middle of someone's typing or clicking elsewhere: wait for a pause.
        for _ in 0..<40 where idleSeconds < 1.2 {
            try await Task.sleep(for: .milliseconds(250))
        }
        let before = NSWorkspace.shared.frontmostApplication
        // Since macOS 14 the app in front has to give way, or the Simulator stays behind it.
        NSApplication.shared.yieldActivation(to: app)
        app.activate()
        // Whoever was working in another app gets it back right after the tap.
        defer {
            if let before, before.bundleIdentifier != bundleID {
                NSApplication.shared.yieldActivation(to: before)
                before.activate()
            }
        }
        var onTop = false
        for _ in 0..<20 {
            if owner(at: point) == app.processIdentifier { onTop = true; break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard onTop else { throw Problem.covered }
        let back = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            try await Task.sleep(for: .milliseconds(60))
        }
        if let back { CGWarpMouseCursorPosition(back) }
    }

    /// How long since the last key press, click or mouse move on this Mac.
    private static var idleSeconds: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// Touches a point given in the iPhone's own points, off by a miss, as a tremor would.
    static func touch(at point: CGPoint, miss: CGPoint, on screen: Screen) async throws {
        try await touch(CGPoint(x: screen.frame.minX + (point.x + miss.x) * screen.scale, y: screen.frame.minY + (point.y + miss.y) * screen.scale))
    }

    /// The app whose window is on top at a point on the Mac's screen.
    private static func owner(at point: CGPoint) -> pid_t? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        // Allyfix's own highlight lies over the Simulator but lets clicks through.
        let passThrough = Set(NSApp.windows.filter(\.ignoresMouseEvents).map(\.windowNumber))
        for window in windows where window[kCGWindowLayer as String] as? Int == 0 {
            if let number = window[kCGWindowNumber as String] as? Int, passThrough.contains(number) { continue }
            guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.contains(point) else { continue }
            return window[kCGWindowOwnerPID as String] as? pid_t
        }
        return nil
    }

    private static func collect(_ node: AXUIElement, into elements: inout [Element], screen: CGRect, scale: CGFloat) {
        for child in node.children {
            let frame = child.frame ?? .zero
            var actions: CFArray?
            AXUIElementCopyActionNames(child, &actions)
            elements.append(Element(
                id: elements.count,
                role: child.attribute(kAXRoleAttribute) ?? "",
                subrole: child.attribute(kAXSubroleAttribute) ?? "",
                label: child.attribute(kAXDescriptionAttribute) ?? "",
                value: child.attributeText(kAXValueAttribute),
                frame: frame,
                pointFrame: CGRect(
                    x: (frame.minX - screen.minX) / scale,
                    y: (frame.minY - screen.minY) / scale,
                    width: frame.width / scale,
                    height: frame.height / scale
                ),
                canPress: (actions as? [String] ?? []).contains(kAXPressAction),
                ax: child,
                selected: child.attribute(kAXSelectedAttribute) as Bool?
            ))
            collect(child, into: &elements, screen: screen, scale: scale)
        }
    }

    /// The iPhone's width in points, from the device named in the window title. Most
    /// current iPhones are 402 or 393 points wide; the Plus and Pro Max sizes wider.
    static func deviceWidth(forWindowTitle title: String) -> CGFloat {
        let name = title.components(separatedBy: " – ").first ?? title
        if name.contains("SE") || name.hasSuffix("iPhone 8") { return 375 }
        if name.contains("Pro Max") || name.contains("Plus") || name.contains("Air") { return 440 }
        if name.contains("iPhone 16") || name.contains("iPhone 17") { return 402 }
        if name.contains("iPhone 15") || name.contains("iPhone 14 Pro") { return 393 }
        return 390
    }
}

extension AXUIElement {
    func attribute<T>(_ name: String) -> T? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    func attributeText(_ name: String) -> String {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success, let value else { return "" }
        return "\(value)"
    }

    var children: [AXUIElement] { attribute(kAXChildrenAttribute) ?? [] }

    var frame: CGRect? {
        var position = CGPoint.zero, size = CGSize.zero
        guard let p: AXValue = attribute(kAXPositionAttribute), let s: AXValue = attribute(kAXSizeAttribute),
              AXValueGetValue(p, .cgPoint, &position), AXValueGetValue(s, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    func firstDescendant(where matches: (AXUIElement) -> Bool) -> AXUIElement? {
        for child in children {
            if matches(child) { return child }
            if let found = child.firstDescendant(where: matches) { return found }
        }
        return nil
    }
}
