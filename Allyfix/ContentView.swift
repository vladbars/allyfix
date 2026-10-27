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

/// The screens checked, under the app each belongs to.
private struct ScreenList: View {
    @Bindable var checker: Checker

    var body: some View {
        List(selection: $checker.selectedScreen) {
            ForEach(apps, id: \.self) { app in
                Section(app) {
                    ForEach(checker.screens.filter { ($0.app ?? "Screens") == app }) { checked in
                        ScreenRow(checked: checked).tag(checked.id)
                            .contextMenu { Button("Delete", role: .destructive) { checker.delete(checked.id) } }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let problem = checker.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        }
    }

    /// App names in the order they were first met.
    private var apps: [String] {
        var seen: [String] = []
        for app in checker.screens.map({ $0.app ?? "Screens" }) where !seen.contains(app) {
            seen.append(app)
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
                if let section = checked.section, section != checked.name {
                    Text(section).font(.caption).foregroundStyle(.secondary)
                }
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
    @State private var showing = Showing.findings

    enum Showing: String, CaseIterable {
        case findings = "Findings", personas = "Personas"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScreenshotView(checked: checked, selected: $checker.selectedIssue)
                .padding(16)
                .frame(width: 300)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                header
                FixPanel(checker: checker, checked: checked)
                Picker("Show", selection: $showing) {
                    ForEach(Showing.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12).padding(.bottom, 10)
                Divider()
                switch showing {
                case .findings: issues
                case .personas: PersonaPanel(checker: checker, checked: checked)
                }
            }
        }
        .onAppear { if checker.testing?.screen == checked.id || checked.personaRuns != nil { showing = .personas } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(checked.title).font(.title2.weight(.semibold))
                if let section = checked.section, section != checked.name {
                    Text(section).foregroundStyle(.secondary)
                }
                Spacer()
                if checked.fix == nil, checked.fixOf == nil, !checked.reviewing, !checked.issues.isEmpty, checked.id == checker.live {
                    Button(action: checker.fix) { Label("Fix", systemImage: "wand.and.stars") }
                        .buttonStyle(.borderedProminent)
                        .disabled(checker.fixing != nil)
                        .help(checker.project.map { "Fixes the code in \($0.name) on a new branch" } ?? "Choose the app's project folder, then fix its code on a new branch")
                }
            }
            HStack(spacing: 6) {
                if checked.reviewing {
                    ProgressView().controlSize(.small)
                    Text("Comparing the screen with what VoiceOver reads…")
                } else if let problem = checked.reviewProblem {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(problem)
                } else if checked.review != nil {
                    Image(systemName: "eye")
                    Text("\(checked.issues.filter(\.byModel).count) found by comparing the screen with what VoiceOver reads")
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
                // Only the issue picked in the list: every frame at once is noise.
                if let issue = checked.reviewing ? nil : checked.issues.first(where: { $0.id == selected }) {
                    let outline = checked.outline(of: issue)
                    ForEach(Array(outline.frames.enumerated()), id: \.offset) { _, frame in
                        let rect = checked.screen.unit(frame).scaled(to: geometry.size)
                        IssueFrame(blocker: issue.severity == .blocker, area: outline.area)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
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
        .overlay(alignment: .bottom) {
            if !checked.drawn(selected).isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Where VoiceOver's focus lands", systemImage: "rectangle").foregroundStyle(.red)
                    Label("What it should cover", systemImage: "rectangle.dashed").foregroundStyle(.blue)
                }
                .font(.caption)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .offset(y: 56)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Where an issue is: red when it blocks, orange when it hinders.
struct IssueFrame: View {
    let blocker: Bool
    /// An area where the problem is, rather than the thing itself.
    var area = false

    var body: some View {
        let color: Color = blocker ? .red : .orange
        RoundedRectangle(cornerRadius: area ? 10 : 3)
            .strokeBorder(color, style: StrokeStyle(lineWidth: 2.5, dash: area ? [8, 5] : []))
            .background(RoundedRectangle(cornerRadius: area ? 10 : 3).fill(color.opacity(area ? 0.08 : 0.18)))
            .allowsHitTesting(false)
    }
}

/// Six people with different disabilities trying the screen's tasks: who managed, who got
/// stuck, and why, in their own words.
private struct PersonaPanel: View {
    @Bindable var checker: Checker
    let checked: CheckedScreen

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                if let tasks = checked.tasks, !tasks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tasks, first tried without a disability").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(tasks, id: \.self) { task in
                            TaskResult(task: task, run: checked.run(.control, task), running: false)
                        }
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(Persona.people) { persona in
                        PersonaTile(persona: persona, checked: checked, running: checker.testing?.screen == checked.id)
                    }
                }
            }
            .padding(12)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let testing = checker.testing, testing.screen == checked.id {
                    ProgressView().controlSize(.small)
                    Text(testing.step).font(.callout).lineLimit(2)
                    Spacer()
                    Button("Stop", action: checker.stopTesting)
                } else {
                    Button(action: { checker.testPersonas() }) { Label(checked.personaRuns == nil ? "Test with Personas" : "Test Again", systemImage: "person.3") }
                        .buttonStyle(.borderedProminent)
                        .disabled(checker.testing != nil)
                    Spacer()
                }
            }
            Group {
                if let problem = checker.testProblem, checker.testing == nil {
                    Text(problem).foregroundStyle(.orange)
                } else if checked.id != checker.live {
                    Text("Checks what the Simulator shows now, then each person tries the screen's two main tasks.")
                } else {
                    Text("Each person tries the screen's two main tasks, starting each time from a fresh start of the app. Takes a few minutes.")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct PersonaTile: View {
    let persona: Persona
    let checked: CheckedScreen
    let running: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: persona.symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.tint)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(persona.title).font(.headline)
                        Text("\(persona.clause) · \(persona.perceives)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !persona.ready {
                    Text("Coming soon: needs the app's sound.").font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(checked.tasks ?? [], id: \.self) { task in
                        if checked.run(.control, task)?.achieved == false {
                            Label("\(task.goal): not tested, since it failed without a disability too", systemImage: "minus.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            TaskResult(task: task, run: checked.run(persona, task), running: running)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            seen
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background.secondary))
        .opacity(persona.ready ? 1 : 0.55)
    }

    /// The screen as this persona last perceived it, small, beside the results: VoiceOver's
    /// words on black, or the picture as they saw it.
    @ViewBuilder private var seen: some View {
        let step = (checked.personaRuns ?? []).last { $0.persona == persona }?.steps.last
        if persona == .screenReader, let target = step?.target {
            Text(target)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .padding(6)
                .frame(width: 76, height: 165, alignment: .bottomLeading)
                .background(RoundedRectangle(cornerRadius: 10).fill(.black))
        } else if let jpeg = step?.jpeg, let image = NSImage(data: jpeg) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 76).clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct TaskResult: View {
    let task: ScreenTask
    let run: PersonaRun?
    let running: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                switch run?.achieved {
                case nil where run?.problem != nil: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                case true?: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case false?: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                case nil where run != nil: ProgressView().controlSize(.mini)
                default: Image(systemName: "circle.dashed").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.goal).font(.callout.weight(.medium))
                if let problem = run?.problem {
                    Text("Couldn't finish: \(problem)").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                } else if let why = run?.why, run?.achieved != nil {
                    Text(why).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                } else if let run, let step = run.steps.last {
                    Text("Step \(run.steps.count): \(step.thought)").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
        }
    }
}

/// The fix of a screen: under way, or what it changed and what the check after it found.
private struct FixPanel: View {
    let checker: Checker
    let checked: CheckedScreen

    /// The screen that was fixed: this one, or the one this is the check after.
    private var fixed: CheckedScreen? {
        checked.fix != nil ? checked : checker.screens.first { $0.id == checked.fixOf }
    }

    var body: some View {
        if let fixing = checker.fixing, fixing.screen == checked.id {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(fixing.step)
            }
            .font(.callout)
            .padding(.horizontal, 12).padding(.bottom, 10)
        } else if let problem = checker.fixProblem, checked.id == checker.selectedScreen, checked.fix == nil {
            Label(problem, systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.orange)
                .padding(.horizontal, 12).padding(.bottom, 10)
        } else if let fixed, let run = fixed.fix {
            let after = checker.screens.first { $0.id == run.after }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "wand.and.stars").foregroundStyle(.tint)
                    Text("\(fixed.issues.count)").font(.title2.weight(.semibold)).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    if let after, !after.reviewing {
                        Text("\(after.issues.count)").font(.title2.weight(.semibold)).foregroundStyle(after.issues.count < fixed.issues.count ? .green : .orange)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text("problems").foregroundStyle(.secondary)
                    Spacer()
                    if let after, checked.id != after.id {
                        Button("Show After") { checker.selectedScreen = after.id }
                    } else if checked.fixOf != nil {
                        Button("Show Before") { checker.selectedScreen = fixed.id }
                    }
                    Button("Undo") { checker.undoFix(of: fixed.id) }
                }
                Text(run.summary).font(.callout)
                Text("\(run.applied.count) changes in \(run.files.count) files on \(run.branch)")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Changes") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(run.applied, id: \.self) { edit in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(edit.why).font(.callout)
                                Text(edit.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(run.failed, id: \.self) { failed in
                            Label(failed, systemImage: "xmark.circle").font(.caption).foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                .font(.callout)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.08)))
            .padding(.horizontal, 12).padding(.bottom, 10)
        }
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
                Text(issue.title.withIconsNamed).font(.body.weight(.medium))
                Text(issue.detail.withIconsNamed).font(.callout).foregroundStyle(.secondary)
                if let suggestion = issue.suggestion {
                    Text("Label it \"\(suggestion)\"").font(.callout)
                }

                HStack(spacing: 4) {
                    if issue.byModel {
                        Label("Seen on screen", systemImage: "eye").help("Found by comparing the screen with what VoiceOver reads")
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
