import SwiftUI

struct ContentView: View {
    @Bindable var checker: Checker

    var body: some View {
        if checker.permitted {
            NavigationSplitView {
                ScreenList(checker: checker)
                    .navigationSplitViewColumnWidth(min: 190, ideal: 220)
            } detail: {
                if let checked = checker.selected {
                    ScreenDetail(checker: checker, checked: checked)
                } else {
                    ContentUnavailableView {
                        Label("No screen checked yet", systemImage: "iphone")
                    } description: {
                        Text(checker.problem ?? "Open your app in the Simulator and check the screen it shows.")
                    } actions: {
                        Button("Check This Screen", action: checker.check).buttonStyle(.borderedProminent)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: checker.check) { Label("Check This Screen", systemImage: "eye") }
                        .labelStyle(.titleAndIcon)
                        .help("Check what the Simulator shows now (⌘R)")
                }
            }
        } else {
            permission
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
        .frame(maxWidth: 420, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
    }
}

/// The screens checked, under the tab each belongs to.
private struct ScreenList: View {
    @Bindable var checker: Checker

    var body: some View {
        List(selection: $checker.selectedScreen) {
            ForEach(sections, id: \.self) { section in
                Section(section) {
                    ForEach(checker.screens.filter { ($0.section ?? "") == section }) { checked in
                        ScreenRow(checked: checked).tag(checked.id)
                            .contextMenu { Button("Delete", role: .destructive) { checker.delete(checked.id) } }
                    }
                }
            }
            let unsorted = checker.screens.filter { $0.section == nil }
            if !unsorted.isEmpty {
                Section(sections.isEmpty ? "Screens" : "Other") {
                    ForEach(unsorted) { checked in
                        ScreenRow(checked: checked).tag(checked.id)
                            .contextMenu { Button("Delete", role: .destructive) { checker.delete(checked.id) } }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                if let problem = checker.problem {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                Text("Muse Spark · \(dollars(checker.spent)) for these screens").foregroundStyle(.secondary)
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
    }

    /// Tab names in the order they were first met.
    private var sections: [String] {
        var seen: [String] = []
        for case let section? in checker.screens.map(\.section) where !seen.contains(section) {
            seen.append(section)
        }
        return seen
    }
}

private struct ScreenRow: View {
    let checked: CheckedScreen

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let picture = checked.picture {
                    Image(nsImage: picture).resizable().aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 3).fill(.quaternary).aspectRatio(0.46, contentMode: .fit)
                }
            }
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 2) {
                Text(checked.title).lineLimit(1)
                HStack(spacing: 4) {
                    if checked.reviewing {
                        ProgressView().controlSize(.mini)
                        Text("Looking…").foregroundStyle(.secondary)
                    } else {
                        Text(count).foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    private var count: String {
        let blockers = checked.issues.filter { $0.severity == .blocker }.count
        return checked.issues.isEmpty ? "No problems" : "\(checked.issues.count) problems, \(blockers) blocking"
    }
}

/// One screen: its screenshot with every issue framed on it, and the issues by kind.
private struct ScreenDetail: View {
    @Bindable var checker: Checker
    let checked: CheckedScreen

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScreenshotView(checked: checked, selected: $checker.selectedIssue)
                .padding(16)
                .frame(width: 300)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                issues
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(checked.title).font(.title2.weight(.semibold))
                if let section = checked.section, section != checked.name {
                    Text(section).foregroundStyle(.secondary)
                }
                Spacer()
                Text(checked.screen.device).font(.caption).foregroundStyle(.tertiary)
            }
            HStack(spacing: 6) {
                if checked.reviewing {
                    ProgressView().controlSize(.small)
                    Text("Muse Spark is comparing the screenshot with what VoiceOver reads…")
                } else if let problem = checked.reviewProblem {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(problem)
                } else if let seen = checked.review {
                    Image(systemName: "eye")
                    Text("Muse Spark found \(checked.issues.filter(\.byModel).count) that the rules cannot see · \(Int(seen.time.rounded())) s · \(dollars(seen.usage.cost))")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var issues: some View {
        ScrollViewReader { scroller in
            List(selection: $checker.selectedIssue) {
                ForEach(groups, id: \.title) { group in
                    Section("\(group.title) · \(group.issues.count)") {
                        ForEach(group.issues) { issue in
                            IssueRow(issue: issue) { checker.speak(issue) }.tag(issue.id).id(issue.id)
                        }
                    }
                }
            }
            .onChange(of: checker.selectedIssue) { _, id in
                if let id { withAnimation { scroller.scrollTo(id) } }
            }
            .opacity(checked.reviewing ? 0 : 1)
            .overlay {
                if checked.reviewing {
                    ProgressView()
                } else if checked.issues.isEmpty {
                    ContentUnavailableView("All clear", systemImage: "checkmark.circle", description: Text("Nothing on this screen keeps someone from using it."))
                }
            }
        }
    }

    /// The worst kinds first, then the most common.
    private var groups: [(title: String, issues: [Issue])] {
        Dictionary(grouping: checked.issues, by: \.kind.group)
            .map { (title: $0.key, issues: $0.value) }
            .sorted {
                let a = $0.issues.map(\.severity).min()!, b = $1.issues.map(\.severity).min()!
                return a != b ? a < b : $0.issues.count > $1.issues.count
            }
    }
}

/// The screen as it looked when checked, with a frame on every issue; a click on a frame
/// picks its issue.
private struct ScreenshotView: View {
    let checked: CheckedScreen
    @Binding var selected: Issue.ID?

    var body: some View {
        let ratio = checked.screen.frame.width / max(checked.screen.frame.height, 1)
        ZStack {
            if let picture = checked.picture {
                Image(nsImage: picture).resizable()
            } else {
                Rectangle().fill(.quaternary)
                ProgressView()
            }
            GeometryReader { geometry in
                // What nobody sees is framed only when picked: its frames lie over what is shown.
                ForEach(checked.reviewing ? [] : checked.issues.filter { $0.kind != .hidden || $0.id == selected }) { issue in
                    ForEach(Array(checked.frames(of: issue).enumerated()), id: \.offset) { _, frame in
                        let rect = checked.screen.unit(frame).scaled(to: geometry.size)
                        IssueFrame(blocker: issue.severity == .blocker, selected: issue.id == selected)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .onTapGesture { selected = issue.id }
                    }
                }
                ForEach(Array(checked.drawn(selected).enumerated()), id: \.offset) { _, drawn in
                    let rect = checked.screen.unit(drawn).scaled(to: geometry.size)
                    DrawnFrame().frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .aspectRatio(ratio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Where an issue is: red when it blocks, orange when it hinders.
struct IssueFrame: View {
    let blocker: Bool
    let selected: Bool

    var body: some View {
        let color: Color = blocker ? .red : .orange
        RoundedRectangle(cornerRadius: 3)
            .strokeBorder(color.opacity(selected ? 1 : 0.3), lineWidth: selected ? 2.5 : 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(color.opacity(selected ? 0.18 : 0.001)))
    }
}

/// Where a thing whose frame misses it is really drawn.
struct DrawnFrame: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
            .allowsHitTesting(false)
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
                if let suggestion = issue.suggestion {
                    Text("Label it \"\(suggestion)\"").font(.callout)
                }
                if issue.kind == .wrongFrame, !issue.drawn.isEmpty {
                    Text("Red: the frame VoiceOver gets. Dashed blue: where it is drawn.").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    if issue.byModel {
                        Label("Muse Spark", systemImage: "eye").help("Seen by comparing the screenshot with what VoiceOver reads")
                        Text("·")
                    }
                    Text("WCAG \(issue.wcag)")
                }
                .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            // Something VoiceOver does not see has nothing to say.
            if !issue.elements.isEmpty {
                Button(action: hear) { Image(systemName: "speaker.wave.2") }
                    .buttonStyle(.borderless)
                    .help("Hear it as VoiceOver says it")
            }
        }
        .padding(.vertical, 4)
    }
}

func dollars(_ amount: Double) -> String {
    String(format: "$%.3f", amount)
}
