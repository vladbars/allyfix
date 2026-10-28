import SwiftUI

/// One screen: its screenshot, who could and could not do its tasks, the fix, and the
/// problems found on it.
struct ScreenDetail: View {
    @Bindable var checker: Checker
    let checked: CheckedScreen
    @State private var story: PersonaRun?
    @State private var tab: Tab = .problems

    enum Tab: Hashable { case people, problems, history }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScreenshotView(checked: checked, selected: $checker.selectedIssue, fixed: fixedFrames)
                .padding(16)
                .frame(width: 300)
            Divider()
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        FixPanel(checker: checker, checked: checked)
                        if let problem = checker.testProblem, checker.testing == nil {
                            Label(problem, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
                        }
                        Picker("Show", selection: $tab) {
                            Text("People").tag(Tab.people)
                            Text(checked.reviewing ? "Problems · checking…" : "Problems · \(checked.issues.count)").tag(Tab.problems)
                            Text("History · \(checker.versions(of: checked).count)").tag(Tab.history)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.large)
                        switch tab {
                        case .people: people
                        case .problems: issues
                        case .history: ChecksHistory(checker: checker, checked: checked)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: checker.selectedIssue) { _, id in
                    // A frame clicked on the screenshot opens the list at its problem.
                    if id != nil { tab = .problems }
                    if let id { withAnimation { scroller.scrollTo(id, anchor: .center) } }
                }
            }
        }
        .sheet(item: $story) { run in Story(run: run, checker: checker) }
        // A screen just checked shows what was found; one people tried shows how they fared.
        .task(id: checked.id) {
            let tested = checked.tasks != nil || checker.testing?.screen == checked.id || (checked.id != checker.live && checker.lastTest(of: checked) != nil)
            tab = tested ? .people : .problems
        }
        .onChange(of: checked.tasks != nil) { _, tested in
            if tested { tab = .people }
        }
        // Testing people shows them at it.
        .onChange(of: checker.testing?.screen) { _, screen in
            if screen == checked.id { tab = .people }
        }
    }


    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            PathBar(checker: checker, steps: [.app(Checker.app(of: checked)), .screen(checked.id)])
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(checked.title).font(.title2.weight(.semibold))
                    Text(checked.date.formatted(date: .abbreviated, time: .shortened)).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                let latest = checker.latest(of: checked)
                if latest.id != checked.id {
                    Button("Open Latest Check") { checker.selectedScreen = latest.id }
                        .help("This is an earlier check; fixes are made from how the screen is now")
                }
            }
            HStack(spacing: 6) {
                if checked.reviewing {
                    ProgressView().controlSize(.small)
                    Text("Comparing the screen with what VoiceOver reads…")
                } else if let problem = checked.reviewProblem {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(problem)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    /// The last time people were tested on this screen, when it was not on this check.
    private var earlier: CheckedScreen? {
        checked.tasks != nil ? nil : checker.versions(of: checked).first { $0.tasks != nil && $0.id != checked.id }
    }

    /// Where the things a fix closed are on this screen: on the check it fixed, and on the
    /// check after it, where the same things now sound right.
    private var fixedFrames: [CGRect] {
        let before = checked.fix != nil ? checked : checker.screens.first { $0.id == checked.fixOf }
        guard let before, let keys = before.fix?.fixed else { return [] }
        let closed = before.issues.filter { keys.contains(Checker.fixKey(before.id, $0.id)) }
        if before.id == checked.id { return closed.flatMap { checked.frames(of: $0) } }
        return closed.flatMap { issue in
            issue.elements.compactMap { id in before.screen.elements.first { $0.id == id } }
                .compactMap { BeforeAfter.counterpart(of: $0, in: checked.screen)?.frame }
        }
    }

    // MARK: People

    private var people: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("People").font(.title3.weight(.semibold))
                Spacer()
                if let testing = checker.testing, testing.screen == checked.id {
                    ProgressView().controlSize(.small)
                    Text(testing.step).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    Button("Stop", action: checker.stopTesting)
                } else {
                    Button(action: { checker.testPersonas() }) { Label(checked.tasks == nil && earlier == nil ? "Test People" : "Test Again", systemImage: "person.3") }
                        .buttonStyle(.bordered)
                        .disabled(checker.testing != nil || checker.exploring != nil || checker.fixing != nil)
                        .help("Six people with different disabilities try this screen's two main tasks, each from a fresh start of the app.")
                }
            }
            PeopleGrid(checker: checker, checked: checked) { story = $0 }
            if let tested = checked.tasks != nil ? checked : checker.lastTest(of: checked), let tasks = tested.tasks, !tasks.isEmpty {
                if tested.id != checked.id {
                    Text("From the test on \(tested.date.formatted(date: .abbreviated, time: .shortened)).").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(tasks, id: \.self) { task in
                    TaskResult(checker: checker, checked: checked, tested: tested, task: task) { story = $0 }
                }
                let untried = Persona.people.filter { person in person.ready && !tasks.contains { tested.run(person, $0) != nil } }
                if !untried.isEmpty {
                    Text("Not tried yet: " + untried.map(\.title).joined(separator: ", ") + ". Test Again has everyone try.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else if checker.testing?.screen != checked.id {
                Text("Nobody has tried this screen yet. Test People: each person tries what this screen is for, with only what they can perceive.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Problems

    private var issues: some View {
        VStack(alignment: .leading, spacing: 10) {
            if checker.latest(of: checked).id == checked.id, checked.fix == nil, !checked.issues.isEmpty {
                let count = checker.chosen(checked).issues.count
                HStack {
                    Text(count == 0 ? "Fix everything found on this screen, or tick only some." : "Only what is ticked is fixed, on this screen.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Menu("Select") {
                        ForEach(Checker.Pick.allCases, id: \.self) { pick in
                            Button(pick.rawValue) { checker.pick(pick, on: [checked]) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Button {
                        if count == 0 { checker.pick(.all, on: [checked]) }
                        checker.fix()
                    } label: {
                        Label(count == 0 ? "Fix All \(checked.issues.count) on This Screen" : "Fix \(count) Ticked", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(checker.busy)
                    .help("Muse Wonder changes this screen's code on a new git branch; then the screen is checked again")
                }
            }
            if checked.reviewing {
                ProgressView()
            } else if checked.issues.isEmpty {
                Label("Nothing on this screen keeps someone from using it.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            }
            ForEach(groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(group.title) · \(group.issues.count)").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(group.issues) { issue in
                        HStack(alignment: .top, spacing: 6) {
                            Tick(checker: checker, key: Checker.fixKey(checked.id, issue.id)).padding(.top, 9)
                            IssueRow(issue: issue, selected: checker.selectedIssue == issue.id) { checker.speak(issue) }
                                .onTapGesture { checker.selectedIssue = issue.id }
                        }
                        .id(issue.id)
                    }
                }
            }
            if !fixedIssues.isEmpty, let run = checked.fix {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Fixed · \(fixedIssues.count)").font(.callout.weight(.semibold)).foregroundStyle(.green)
                        Button("Open Fix") { checker.selection = .fix(checked.id) }.buttonStyle(.link).font(.callout)
                    }
                    ForEach(fixedIssues) { issue in
                        IssueRow(issue: issue, selected: checker.selectedIssue == issue.id, fixed: fixedNote(run)) { checker.speak(issue) }
                            .onTapGesture { checker.selectedIssue = issue.id }
                            .id(issue.id)
                    }
                }
            }
        }
    }

    /// Problems a fix of this check closed, kept apart from the open ones.
    private var fixedIssues: [Issue] {
        guard let keys = checked.fix?.fixed else { return [] }
        return checked.issues.filter { keys.contains(Checker.fixKey(checked.id, $0.id)) }
    }

    private func fixedNote(_ run: Fixer.Run) -> String {
        let after = checker.screens.first { $0.id == run.after }
        let state = after == nil ? "not checked after the fix yet" : after!.reviewing ? "checking after the fix…" : "checked after the fix"
        return "Fixed on \(run.branch) · \(state)"
    }

    /// Open problems, the worst kinds first, then the most common.
    private var groups: [(title: String, issues: [Issue])] {
        let fixed = Set(fixedIssues.map(\.id))
        return Dictionary(grouping: checked.issues.filter { !fixed.contains($0.id) }, by: \.kind.group)
            .map { (title: $0.key, issues: $0.value) }
            .sorted {
                let a = $0.issues.map(\.severity).min()!, b = $1.issues.map(\.severity).min()!
                return a != b ? a < b : $0.issues.count > $1.issues.count
            }
    }
}

/// What a fix changed for a VoiceOver user: for each problem it closed, the things that now
/// sound different, before and after, to hear, with what changed in plain words.
struct BeforeAfter: View {
    let checker: Checker
    let before: CheckedScreen
    let after: CheckedScreen?
    let keys: [String]

    var body: some View {
        let closed = before.issues.filter { keys.contains(Checker.fixKey(before.id, $0.id)) && !$0.elements.isEmpty }
        if !closed.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("What a VoiceOver user hears now").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(closed) { issue in
                    ClosedIssue(checker: checker, issue: issue, before: before, after: after)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(.background.opacity(0.6)))
        }
    }

    /// The same thing on the screen after the fix: the same words, or what sits where it sat.
    static func counterpart(of element: Element, in screen: Screen) -> Element? {
        if !element.readableLabel.isEmpty, let same = screen.elements.first(where: { $0.readableLabel == element.readableLabel }) { return same }
        return screen.elements.filter { $0.frame.overlap(element.frame) > 0.6 }.max { $0.frame.overlap(element.frame) < $1.frame.overlap(element.frame) }
    }

    /// What changed for the listener, in plain words: the role, the state, the name.
    static func explain(was: Element, now: Element?) -> String {
        guard let now else { return "No longer read: it was not meant for VoiceOver." }
        var said: [String] = []
        let isButton = { (element: Element) in Audit.spoken(element).components(separatedBy: ", ").contains { $0 == "button" || $0 == "switch button" } }
        if isButton(now), !isButton(was) { said.append("now announced as a button, so it can be found and pressed") }
        if now.selected == true, was.selected != true { said.append("now says it is selected") }
        if now.readableLabel != was.readableLabel {
            said.append(was.readableLabel.isEmpty
                        ? "now has a name: \u{201C}\(now.readableLabel)\u{201D}"
                        : "now called \u{201C}\(now.readableLabel)\u{201D} instead of \u{201C}\(was.readableLabel.withIconsNamed)\u{201D}")
        }
        guard let first = said.first else { return "Sounds the same as before." }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + said.dropFirst()).joined(separator: "; ") + "."
    }
}

/// One problem a fix closed: only the things that sound different now.
private struct ClosedIssue: View {
    let checker: Checker
    let issue: Issue
    let before: CheckedScreen
    let after: CheckedScreen?

    private var pairs: [(was: Element, now: Element?)] {
        issue.elements.compactMap { id in before.screen.elements.first { $0.id == id } }
            .map { element in (element, after.flatMap { BeforeAfter.counterpart(of: element, in: $0.screen) }) }
    }

    var body: some View {
        let all = pairs
        // The rest was right already.
        let changed = all.filter { after == nil || $0.now.map(Audit.spoken) != Audit.spoken($0.was) }
        VStack(alignment: .leading, spacing: 6) {
            Text(issue.title.withIconsNamed).font(.callout.weight(.medium))
            if after != nil, changed.isEmpty {
                Text("Nothing a VoiceOver user hears changed here.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(changed.prefix(4).enumerated()), id: \.offset) { _, pair in
                Change(checker: checker, was: pair.was, now: pair.now, checked: after != nil)
            }
            if after != nil, changed.count < all.count {
                let same = all.count - changed.count
                Text("\(same) more \(same == 1 ? "was" : "were") right already.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// One thing before and after, to hear, with the new words marked and what they mean.
private struct Change: View {
    let checker: Checker
    let was: Element
    let now: Element?
    /// Whether the screen has been checked after the fix.
    let checked: Bool

    var body: some View {
        let heardBefore = Audit.spoken(was).withIconsNamed
        let heardAfter = now.map { Audit.spoken($0).withIconsNamed }
        VStack(alignment: .leading, spacing: 3) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
                GridRow {
                    Text("Before").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("\u{201C}\(heardBefore)\u{201D}").font(.callout.monospaced())
                    hear(heardBefore)
                }
                GridRow {
                    Text("After").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if !checked {
                        Text("after Check Again").font(.callout).foregroundStyle(.tertiary)
                    } else if let heardAfter {
                        Self.marked(heardAfter, against: heardBefore).font(.callout.monospaced())
                        hear(heardAfter)
                    } else {
                        Text("not read any more").font(.callout).foregroundStyle(.green)
                    }
                }
            }
            if checked {
                Label(BeforeAfter.explain(was: was, now: now), systemImage: "arrow.turn.down.right")
                    .font(.callout).foregroundStyle(.green)
            }
        }
    }

    private func hear(_ text: String) -> some View {
        Button { checker.say(text) } label: { Image(systemName: "speaker.wave.2") }
            .buttonStyle(.borderless)
            .help("Hear it as VoiceOver says it")
    }

    /// What VoiceOver says now, with the words it did not say before in green.
    static func marked(_ now: String, against before: String) -> Text {
        let old = Set(before.components(separatedBy: ", "))
        let parts = now.components(separatedBy: ", ")
        var text = Text("\u{201C}")
        for (index, part) in parts.enumerated() {
            let piece = (index == 0 ? "" : ", ") + part
            text = text + (old.contains(part) ? Text(piece) : Text(piece).foregroundColor(.green).bold())
        }
        return text + Text("\u{201D}")
    }
}

/// Whether something goes into the next fix; ticked unless the person unticks it.
private struct Tick: View {
    @Bindable var checker: Checker
    let key: String
    /// Whether it is a task someone got stuck at, ticked unless unticked.
    var stuck = false

    var body: some View {
        Toggle("", isOn: Binding(
            get: { checker.isTicked(key, stuck: stuck) },
            set: { checker.choices[key] = $0 }
        ))
        .toggleStyle(.checkbox)
        .labelsHidden()
        .help("Include in the fix")
    }
}

/// How one person went about one task, step by step: what they perceived, what they did,
/// and where it ended.
struct Story: View {
    let run: PersonaRun
    var checker: Checker?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: run.persona.symbol).font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(run.persona.title): \(run.task.goal)").font(.title3.weight(.semibold))
                    Text(run.persona.perceives).foregroundStyle(.secondary)
                    Label(run.achieved == true ? "Done" : "Stuck", systemImage: run.achieved == true ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(run.achieved == true ? .green : .red)
                    if let why = run.reason { Text(why).font(.callout) }
                    if let boundary = run.boundary { SizeScale(boundary: boundary) }
                }
                Spacer()
                if let checker, run.achieved == true, run.persona != .control,
                   let checked = checker.screens.first(where: { $0.personaRuns?.contains { $0.id == run.id } == true }) {
                    if checker.isKept(run, on: checked) {
                        Label("Kept as a test", systemImage: "checklist.checked").foregroundStyle(.green)
                    } else {
                        Button { checker.keepAsTest(run, on: checked) } label: { Label("Keep as Test", systemImage: "checklist") }
                            .help("Saves these steps in allyfix/tests and commits that file alone: they run again with no AI and fail if this stops working")
                    }
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(run.steps.enumerated()), id: \.offset) { number, step in
                        HStack(alignment: .top, spacing: 14) {
                            perceived(step)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Step \(number + 1)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(step.thought).font(.callout)
                                Text(action(step)).font(.callout.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 640, height: 560)
    }

    /// The screen as the person got it at that step: a picture, or what VoiceOver read.
    @ViewBuilder private func perceived(_ step: PersonaRun.Step) -> some View {
        if let jpeg = step.jpeg, let image = NSImage(data: jpeg) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 110).clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Text(step.perceived.split(separator: "\n").dropFirst().prefix(14).joined(separator: "\n"))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .padding(6)
                .frame(width: 110, height: 200, alignment: .topLeading)
                .clipped()
                .background(RoundedRectangle(cornerRadius: 8).fill(.black))
        }
    }

    private func action(_ step: PersonaRun.Step) -> String {
        switch step.action {
        case "activate": "→ double-tap \(step.target?.withIconsNamed ?? "")"
        case "touch": "→ touch \(step.target ?? "")"
        case "giveUp": "→ gives up"
        case "done": "→ says it is done"
        default: "→ \(step.action)"
        }
    }
}

/// The screen as it looked when checked, with the picked problem framed on it.
struct ScreenshotView: View {
    let checked: CheckedScreen
    @Binding var selected: Issue.ID?
    /// What a fix closed, framed in green.
    var fixed: [CGRect] = []

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
                ForEach(Array(fixed.enumerated()), id: \.offset) { _, frame in
                    let rect = checked.screen.unit(frame).scaled(to: geometry.size)
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.green, lineWidth: 2.5)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.green.opacity(0.15)))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
                // Only the problem picked: every frame at once is noise.
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

/// Where a problem is: red when it blocks, orange when it hinders.
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

/// Where a thing whose frame misses it is really drawn.
struct DrawnFrame: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
            .allowsHitTesting(false)
    }
}

/// A fix of this screen in one line, leading to its page; or the fix under way.
private struct FixPanel: View {
    let checker: Checker
    let checked: CheckedScreen

    /// The check the fix was made from: this one, or the one this is the check after.
    private var fixed: CheckedScreen? {
        checked.fix != nil ? checked : checker.screens.first { $0.id == checked.fixOf }
    }

    var body: some View {
        if let fixing = checker.fixing, fixing.screen == checked.id || fixing.screen == fixed?.id {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(fixing.step)
            }
            .font(.callout)
        } else if let problem = checker.fixProblem, checked.id == checker.selectedScreen, fixed == nil {
            Label(problem, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
        } else if let fixed, fixed.fix != nil {
            let verified = checker.verified(fixed)
            Button { checker.selection = .fix(fixed.id) } label: {
                HStack(spacing: 10) {
                    Image(systemName: verified == true ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(verified == true ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verified == true ? "Fixed and verified" : verified == false ? "Fixed in part" : "Fixed, not verified yet").font(.headline)
                        Text(checker.fixTitle(of: fixed)).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    Text("Open Fix").foregroundStyle(.tint)
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill((verified == true ? Color.green : Color.orange).opacity(0.1)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct IssueRow: View {
    let issue: Issue
    let selected: Bool
    /// How it was fixed, for a problem a fix closed; nil while it is open.
    var fixed: String?
    let hear: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if fixed != nil {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Image(systemName: issue.severity == .blocker ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(issue.severity == .blocker ? .red : .orange)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.title.withIconsNamed).font(.body.weight(.medium)).foregroundStyle(fixed == nil ? .primary : .secondary)
                if let fixed { Text(fixed).font(.callout).foregroundStyle(.green) }
                Text(issue.detail.withIconsNamed).font(.callout).foregroundStyle(.secondary)
                if let suggestion = issue.suggestion {
                    Text("Label it \"\(suggestion)\"").font(.callout)
                }
            }
            Spacer()
            // Something VoiceOver does not see has nothing to say.
            if !issue.elements.isEmpty {
                Button(action: hear) { Image(systemName: "speaker.wave.2") }
                    .buttonStyle(.borderless)
                    .help("Hear it as VoiceOver says it")
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.12) : .clear))
        .contentShape(Rectangle())
    }
}

/// Where a task stopped working as text grew: each size iOS offers, up to the one a person
/// with low vision uses, green while it worked and red from where it broke.
struct SizeScale: View {
    let boundary: PersonaRun.Boundary

    private var sizes: [TextSize] {
        TextSize.allCases.filter { $0 <= max(Persona.lowVision.textSize ?? .large, boundary.breaks ?? boundary.holds) }
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 5) {
            ForEach(sizes, id: \.self) { size in
                Text("A")
                    .font(.system(size: 8 + CGFloat(size.percent) / 25, weight: .semibold))
                    .foregroundStyle(boundary.breaks.map { size >= $0 } == true ? .red : .green)
                    .help(size.title)
            }
            Text(boundary.breaks.map { "works up to \(boundary.holds.percent)%, breaks at \($0.percent)%" } ?? "layout holds at \(boundary.holds.percent)%")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(boundary.breaks.map { "Works up to \(boundary.holds.title), breaks at \($0.title)" } ?? "Layout holds at \(boundary.holds.title)")
    }
}

/// One task and how the people fared at it: who got stuck, with Fix, and who got through.
private struct TaskResult: View {
    @Bindable var checker: Checker
    let checked: CheckedScreen
    let tested: CheckedScreen
    let task: ScreenTask
    let open: (PersonaRun) -> Void

    var body: some View {
        let runs = Persona.people.compactMap { tested.run($0, task) }.filter { $0.achieved != nil }
        let control = tested.run(.control, task)
        let stuck = runs.filter { $0.achieved == false }
        let through = runs.filter { $0.achieved == true }
        VStack(alignment: .leading, spacing: 8) {
            Text(task.goal).font(.body.weight(.semibold))
            if control?.achieved == false {
                Label("Not a test of access: it did not work without a disability either.", systemImage: "minus.circle").foregroundStyle(.secondary)
            } else if control == nil || (runs.isEmpty && checker.testing?.screen == checked.id) {
                Label("Being tried…", systemImage: "hourglass").foregroundStyle(.secondary)
            }
            ForEach(stuck) { run in
                let kept = checker.keptFix(for: run) != nil
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text(kept ? "**\(run.persona.title)** got stuck here; a fix for it is kept since. Test Again to confirm." : "**\(run.persona.title)** got stuck. \(run.why ?? "")").lineLimit(3)
                    } icon: {
                        Image(systemName: kept ? "checkmark.seal.fill" : "xmark.octagon.fill").foregroundStyle(kept ? .green : .red)
                    }
                    if let boundary = run.boundary { SizeScale(boundary: boundary).padding(.leading, 28) }
                    HStack(spacing: 14) {
                        if let fixed = checker.fix(for: run, in: Checker.app(of: checked)) {
                            Button { checker.selection = .fix(fixed.id) } label: { Label("Open Fix", systemImage: "wand.and.stars") }
                        } else if checker.latest(of: checked).id == checked.id {
                            Button { checker.fix(stuck: run, on: checked) } label: { Label("Fix", systemImage: "wand.and.stars") }
                                .buttonStyle(.borderedProminent)
                                .disabled(checker.fixing != nil || checker.testing != nil || checker.exploring != nil)
                        }
                        Button("See What Happened") { open(run) }
                    }
                    .padding(.leading, 28)
                }
            }
            if !through.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(stuck.isEmpty ? "Everyone who tried got through:" : "Got through:")
                    ForEach(through) { run in
                        Button(run.persona.title) { open(run) }.buttonStyle(.link)
                    }
                }
            }
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
    }
}

/// Every check of this screen, latest first: what each was, what it found, and how people
/// fared, to open any of them.
private struct ChecksHistory: View {
    @Bindable var checker: Checker
    let checked: CheckedScreen

    var body: some View {
        let versions = checker.versions(of: checked)
        if !versions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(versions) { version in
                        Button { checker.selectedScreen = version.id } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: symbol(version)).foregroundStyle(.secondary).frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(what(version)).font(.callout.weight(version.id == checked.id ? .semibold : .regular))
                                    Text(version.date.formatted(date: .abbreviated, time: .shortened) + " · \(version.issues.count) problems").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if version.id == checked.id { Text("shown").font(.caption).foregroundStyle(.secondary) }
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(version.id == checked.id)
                    }
                }
            }
        }
    }

    private func what(_ version: CheckedScreen) -> String {
        let people = (version.personaRuns ?? []).filter { $0.persona != .control && $0.achieved != nil }
        let stuck = people.filter { $0.achieved == false }.count
        var parts: [String] = []
        if version.fixOf != nil { parts.append("Checked after a fix") }
        else if version.tasks != nil { parts.append(people.isEmpty ? "Tested with people" : "Tested with people: \(stuck == 0 ? "everyone got through" : "\(stuck) stuck")") }
        else { parts.append("Checked") }
        if let fix = version.fix { parts.append(fix.kept == true ? "fix kept" : "fixed") }
        return parts.joined(separator: " · ")
    }

    private func symbol(_ version: CheckedScreen) -> String {
        version.fix != nil ? "wand.and.stars" : version.fixOf != nil ? "checkmark.seal" : version.tasks != nil ? "person.3" : "eye"
    }
}
