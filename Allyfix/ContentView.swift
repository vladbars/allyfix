import SwiftUI

struct ContentView: View {
    let checker: Checker

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !checker.permitted {
                permission
            } else {
                results
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(checker.screen?.device ?? "iOS Simulator").font(.headline)
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Check This Screen", action: checker.check)
                .buttonStyle(.borderedProminent)
                .disabled(!checker.permitted)
        }
        .padding(12)
    }

    private var summary: String {
        switch checker.state {
        case .idle: return "Open your app in the Simulator, then check."
        case .failed(let problem): return problem
        case .checked:
            let blockers = checker.issues.filter { $0.severity == .blocker }.count
            return checker.issues.isEmpty ? "No problems found on this screen." : "\(checker.issues.count) problems, \(blockers) blocking"
        }
    }

    private var permission: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.raised").font(.largeTitle).foregroundStyle(.secondary)
            Text("Allow Accessibility access").font(.title3)
            Text("Allyfix reads and presses your app in the Simulator through the Mac's accessibility interface. It does not see anything else.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open System Settings", action: checker.askPermission)
            Button("I've Allowed It") { checker.check() }.buttonStyle(.link)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var results: some View {
        List(checker.issues) { issue in
            IssueRow(issue: issue) { checker.speak(issue) }
        }
        .overlay {
            if case .checked = checker.state, checker.issues.isEmpty {
                ContentUnavailableView("All clear", systemImage: "checkmark.circle", description: Text("Nothing on this screen keeps someone from using it."))
            }
        }
    }
}

private struct IssueRow: View {
    let issue: Issue
    let hear: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.severity == .blocker ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(issue.severity == .blocker ? .red : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.title).font(.body.weight(.medium))
                Text(issue.detail).font(.callout).foregroundStyle(.secondary)
                Text("WCAG \(issue.wcag)").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: hear) { Image(systemName: "speaker.wave.2") }
                .buttonStyle(.borderless)
                .help("Hear it as VoiceOver says it")
        }
        .padding(.vertical, 4)
    }
}
