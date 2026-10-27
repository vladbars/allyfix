import AppKit
import SwiftUI

/// Frames drawn over the Simulator itself, around the issues of the screen it shows, so a
/// problem is pointed out where the developer is looking. The window lets clicks through,
/// follows the Simulator as it moves, and stays just above it, so whatever covers the
/// Simulator covers the frames too.
final class Overlay {
    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private let host = NSHostingView(rootView: OverlayFrames(boxes: [], drawn: []))

    init(checker: Checker) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = host
        Task {
            while true {
                follow(checker)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func follow(_ checker: Checker) {
        // Only while the Simulator likely still shows the screen selected.
        guard let checked = checker.selected, checked.id == checker.live,
              let now = Simulator.contentFrame(), let window = simulatorWindow(around: now) else {
            panel.orderOut(nil)
            return
        }
        // Only the issue picked in the list: every frame at once over a live app is noise.
        let issue = checked.issues.first { $0.id == checker.selectedIssue }
        let boxes: [OverlayFrames.Box] = issue.map { issue in
            let outline = checked.outline(of: issue)
            return outline.frames.map { OverlayFrames.Box(rect: checked.screen.unit($0), blocker: issue.severity == .blocker, area: outline.area) }
        } ?? []
        let drawn = checked.drawn(checker.selectedIssue).map { checked.screen.unit($0) }
        let frames = OverlayFrames(boxes: boxes, drawn: drawn)
        if frames != host.rootView { host.rootView = frames }
        // Accessibility frames start at the top left of the main display; windows at its bottom left.
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let frame = NSRect(x: now.minX, y: top - now.maxY, width: now.width, height: now.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        panel.order(.above, relativeTo: window)
    }

    /// The window server's number for the Simulator window showing the iPhone at `frame`.
    private func simulatorWindow(around frame: CGRect) -> Int? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Simulator.bundleID).first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return windows.first { window in
            guard window[kCGWindowOwnerPID as String] as? pid_t == app.processIdentifier,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
            return rect.contains(center)
        }?[kCGWindowNumber as String] as? Int
    }
}

struct OverlayFrames: View, Equatable {
    struct Box: Equatable {
        /// In parts of the screen, 0 to 1.
        let rect: CGRect
        let blocker: Bool
        let area: Bool
    }

    let boxes: [Box]
    /// Where the selected issue's things are really drawn, in parts of the screen.
    let drawn: [CGRect]

    var body: some View {
        GeometryReader { geometry in
            ForEach(Array(boxes.enumerated()), id: \.offset) { _, box in
                let rect = box.rect.scaled(to: geometry.size)
                IssueFrame(blocker: box.blocker, area: box.area)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
            ForEach(Array(drawn.enumerated()), id: \.offset) { _, drawn in
                let rect = drawn.scaled(to: geometry.size)
                DrawnFrame().frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
            }
        }
    }
}
