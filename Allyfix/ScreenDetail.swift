import SwiftUI

/// One screen: its screenshot, who could and could not do its tasks, the fix, and the
/// problems found on it.
struct ScreenDetail: View {
    @Bindable var checker: Checker
    let checked: CheckedScreen
    @State private var story: PersonaRun?
    /// The branch the app's source has checked out, to tell whether a fix is in the app now.
    @State private var currentBranch: String?

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
                        if checked.fix == nil, checked.fixOf == nil, let fixed = checker.versions(of: checked).first(where: { $0.fix != nil }), let branch = fixed.fix?.branch {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: "wand.and.stars").foregroundStyle(.tint)
                                Text(branch == currentBranch
                                     ? "Fixed on \(branch), which the app's source has checked out now."
                                     : "Not fixed in the app now. An earlier fix is on \(branch), which is not checked out.")
                                Button("Open") { checker.selectedScreen = fixed.id }.buttonStyle(.link)
                            }
                            .font(.callout)
                        }
                        people
                        issues
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: checker.selectedIssue) { _, id in
                    if let id { withAnimation { scroller.scrollTo(id, anchor: .center) } }
                }
            }
        }
        .sheet(item: $story) { run in Story(run: run) }
        .task(id: checked.id) { currentBranch = try? checker.project(for: checked.app)?.branch }
    }


    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(checked.title).font(.title2.weight(.semibold))
                    Text([checked.app, checked.section].compactMap { $0 }.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                let latest = checker.latest(of: checked)
                if latest.id != checked.id {
                    Button("Open Latest Check") { checker.selectedScreen = latest.id }
                        .help("This is an earlier check; fixes are made from how the screen is now")
                } else if checked.fix == nil, !checked.reviewing, !checked.issues.isEmpty || !stuck.isEmpty {
                    let chosen = checker.chosen(checked)
                    let count = chosen.issues.count + (chosen.personaRuns ?? []).filter { $0.achieved == false && $0.persona != .control }.count
                    Menu("Select") {
                        ForEach(Checker.Pick.allCases, id: \.self) { pick in
                            Button(pick.rawValue) { checker.pick(pick, on: [checked]) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Tick all, only what blocks, only what stopped people, or nothing")
                    Button(action: checker.fix) { Label("Fix \(count) Selected", systemImage: "wand.and.stars") }
                        .buttonStyle(.borderedProminent)
                        .disabled(count == 0 || checker.fixing != nil || checker.testing != nil)
                        .help(checker.project(for: checked.app).map { "Changes the code in \($0.name) on a new branch, then the same people try again" } ?? "Choose the app's source folder, then change its code on a new branch")
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

    private var stuck: [PersonaRun] {
        (checked.personaRuns ?? []).filter { $0.persona != .control && $0.achieved == false && checked.run($0.persona, $0.task)?.id == $0.id }
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
                        .help("Six people with different disabilities try this screen's two main tasks, each from a fresh start of the app. Takes a few minutes.")
                }
            }
            if let problem = checker.testProblem, checker.testing == nil, checker.selectedScreen == checked.id {
                Text(problem).font(.callout).foregroundStyle(.orange)
            }
            if let tasks = checked.tasks, !tasks.isEmpty {
                PeopleTable(checked: checked, tasks: tasks) { story = $0 }
                ForEach(stuck) { run in
                    HStack(alignment: .top, spacing: 6) {
                    Tick(checker: checker, key: Checker.fixKey(checked.id, run.id.uuidString))
                    Button { story = run } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                            Text("**\(run.persona.title)** could not \(run.task.goal.lowercasedFirst): \(run.why ?? "")")
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .font(.callout)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    }
                }
            } else if checker.testing?.screen != checked.id {
                Text("Not tested on this check. Each person tries what this screen is for, with only what they can perceive.")
                    .font(.callout).foregroundStyle(.secondary)
                if let earlier {
                    HStack(spacing: 6) {
                        Text("Last tested on \(earlier.date.formatted(date: .abbreviated, time: .shortened))\(earlier.fixOf != nil ? ", after a fix" : earlier.fix != nil ? ", before a fix" : "").")
                        Button("Open") { checker.selectedScreen = earlier.id }.buttonStyle(.link)
                    }
                    .font(.callout).foregroundStyle(.secondary)
                }
                // What the fix will take from the last test before any fix: the code is the
                // same until a fix changes it.
                if let tested = checker.lastTest(of: checked) {
                    let failed = (tested.personaRuns ?? []).filter { $0.persona != .control && $0.achieved == false && tested.run($0.persona, $0.task)?.id == $0.id }
                    if !failed.isEmpty {
                        Text("Still to fix, from the test on \(tested.date.formatted(date: .abbreviated, time: .shortened)):").font(.callout.weight(.medium))
                        ForEach(failed) { run in
                            HStack(alignment: .top, spacing: 6) {
                                Tick(checker: checker, key: Checker.fixKey(checked.id, run.id.uuidString))
                                Button { story = run } label: {
                                    Text("**\(run.persona.title)** could not \(run.task.goal.lowercasedFirst): \(run.why ?? "")").multilineTextAlignment(.leading)
                                }
                                .buttonStyle(.plain)
                            }
                            .font(.callout)
                        }
                    }
                }
            }
        }
    }

    // MARK: Problems

    private var issues: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Problems").font(.title3.weight(.semibold))
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

    var body: some View {
        Toggle("", isOn: Binding(
            get: { !checker.excluded.contains(key) },
            set: { if $0 { checker.excluded.remove(key) } else { checker.excluded.insert(key) } }
        ))
        .toggleStyle(.checkbox)
        .labelsHidden()
        .help("Include in the fix")
    }
}

/// Tasks down, people across: who managed each task, who got stuck, who was not tried.
private struct PeopleTable: View {
    let checked: CheckedScreen
    let tasks: [ScreenTask]
    let open: (PersonaRun) -> Void

    private var columns: [Persona] { [.control] + Persona.people.filter(\.ready) }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 8) {
            GridRow {
                Text("")
                ForEach(columns) { persona in
                    Image(systemName: persona.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(persona == .control ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                        .frame(width: 34)
                        .help(persona == .control ? "Without a disability: a task this fails is not a test of access" : "\(persona.title): \(persona.perceives)")
                }
            }
            ForEach(tasks, id: \.self) { task in
                GridRow {
                    Text(task.goal).font(.callout).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(columns) { persona in
                        Cell(run: checked.run(persona, task), skipped: persona != .control && checked.run(.control, task)?.achieved == false, open: open)
                            .frame(width: 34)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
        legend
    }

    /// What the symbols mean, once, under the table.
    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(columns) { persona in
                Label(persona == .control ? "Without a disability" : persona.title, systemImage: persona.symbol)
            }
            Label("did it", systemImage: "checkmark.circle.fill")
            Label("got stuck", systemImage: "xmark.octagon.fill")
            Label("not tried: failed without a disability too", systemImage: "minus")
            Label("not tried yet", systemImage: "circle.dashed")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private struct Cell: View {
        let run: PersonaRun?
        let skipped: Bool
        let open: (PersonaRun) -> Void

        var body: some View {
            Button { if let run { open(run) } } label: {
                Group {
                    if skipped {
                        Image(systemName: "minus").foregroundStyle(.tertiary)
                    } else if let run {
                        switch run.achieved {
                        case true?: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case false?: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                        case nil where run.problem != nil: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        case nil: ProgressView().controlSize(.mini)
                        }
                    } else {
                        Image(systemName: "circle.dashed").foregroundStyle(.quaternary)
                    }
                }
                .font(.system(size: 15))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(run == nil)
            .help(skipped ? "Not tried: it failed without a disability too" : run?.why ?? run?.problem ?? "")
        }
    }
}

/// How one person went about one task, step by step: what they perceived, what they did,
/// and where it ended.
private struct Story: View {
    let run: PersonaRun
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
                    if let why = run.why ?? run.problem { Text(why).font(.callout) }
                }
                Spacer()
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
        } else if let fixed, let run = fixed.fix {
            let verified = checker.verified(fixed)
            Button { checker.selection = .fix(fixed.id) } label: {
                HStack(spacing: 10) {
                    Image(systemName: verified == true ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(verified == true ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verified == true ? "Fixed and verified" : verified == false ? "Fixed in part" : "Fixed, not verified yet").font(.headline)
                        Text(FixPage.headline(run)).font(.callout).foregroundStyle(.secondary).lineLimit(2)
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
