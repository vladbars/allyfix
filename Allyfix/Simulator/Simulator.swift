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

        var errorDescription: String? {
            switch self {
            case .notPermitted: "Allyfix needs Accessibility access to read the Simulator."
            case .notRunning: "Open your app in the iOS Simulator."
            case .noDevice: "No iPhone is shown in the Simulator."
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
                ax: child
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
