import SwiftUI

/// An app at a glance, however many screens it has: one row per screen, in the order the
/// walk found them and indented by how deep, and one column per person. A cell says how
/// that person fared on that screen; the Reach column says whether the way there still
/// works. Rows appear while the walk goes on, and cells light up while checks run.
struct ScreensTable: View {
    @Bindable var checker: Checker
    let app: String
    let open: (PersonaRun) -> Void
    /// The screens ticked to fix together, and whether only what blocks.
    @State private var ticked: Set<CheckedScreen.ID> = []
    @State private var blockingOnly = true
    /// Choosing screens: a click on a row ticks it instead of opening it.
    @State private var choosing = false

    private var people: [Persona] { Persona.people.filter(\.ready) }

    /// Screens as a tree: each after the screen its way starts from, the ones checked by
    /// hand last.
    private var rows: [CheckedScreen] {
        checker.latestScreens(of: app).sorted { a, b in
            switch (route(of: a), route(of: b)) {
            case let (x?, y?): return x.lexicographicallyPrecedes(y) || (x == y && a.date < b.date)
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return a.date < b.date
            }
        }
    }

    /// The way to a screen, from whichever of its checks knows it: a check made by hand does not.
    private func route(of checked: CheckedScreen) -> [String]? {
        checked.route ?? checker.versions(of: checked).lazy.compactMap(\.route).first
    }

    var body: some View {
        let rows = self.rows
        let run = checker.checkRuns[app]
        VStack(alignment: .leading, spacing: 10) {
            actionBar
            controls(run)
            VStack(spacing: 0) {
                header(rows)
                Divider()
                ForEach(rows) { checked in
                    row(checked, run: run)
                    Divider().opacity(0.5)
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
            Text(legend).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var legend: String {
        "✓ got through · ✗ got stuck · ○ not tried yet. Click a cell to see how it went; open a screen and press Test People to try it."
    }

    // MARK: Running the checks

    private func controls(_ run: CheckRun?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if let run, !run.finished {
                ProgressView().controlSize(.small)
                Text(run.testing.map { "Running saved test \($0)…" } ?? "Walking to every screen, no model…").font(.callout)
                Spacer()
                Button("Stop", action: checker.stopChecks)
            } else {
                if let run {
                    Image(systemName: run.passed ? "checkmark.seal.fill" : "exclamationmark.octagon.fill")
                        .font(.title3).foregroundStyle(run.passed ? .green : .red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(summary(run)).font(.callout.weight(.semibold))
                        Text("\(run.reason) · \(run.date.formatted(.relative(presentation: .named)))" + (run.took.map { " · took \(Duration.seconds($0).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))) for \(run.screens.count) screens" } ?? ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Quick re-test").font(.callout.weight(.semibold))
                        Text("No AI, free: walks to every screen and replays the saved tests.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle("Every Time the Code Changes", isOn: Binding(get: { checker.watching.contains(app) }, set: { checker.setWatching(app, $0) }))
                    .toggleStyle(.checkbox)
                    .disabled(checker.project(for: app) == nil)
                    .help("Allyfix looks at the app's code every few seconds; when it changes, the checks run again on their own")
                Button { checker.runChecks(of: app) } label: { Label("Re-test Now", systemImage: "arrow.clockwise") }
                    .disabled(checker.busy)
                    .help("Walks the way to every screen, as the walk found it, and replays the saved tests: no AI, free")
            }
        }
    }

    private func summary(_ run: CheckRun) -> String {
        if let problem = run.problem { return problem }
        var parts = ["\(run.screens.count - run.lost) of \(run.screens.count) screens reachable"]
        if !run.tests.isEmpty { parts.append("\(run.tests.count - run.failed) of \(run.tests.count) saved tests pass") }
        return parts.joined(separator: " · ")
    }

    // MARK: Header

    // MARK: Fixing several screens

    /// What can be done to the screens ticked in the table: people try them, or they are
    /// fixed together. Always shown, so it is clear the ticks are for this.
    private var actionBar: some View {
        // Nothing ticked is every screen: the buttons always do something.
        let all = ticked.isEmpty
        let chosen = all ? Set(rows.map(\.id)) : ticked
        let work = checker.work(on: chosen, blockingOnly: blockingOnly)
        let problems = work.map(\.issues.count).reduce(0, +)
        let tasks = work.map { ($0.personaRuns ?? []).filter { $0.achieved == false && $0.persona != .control }.count }.reduce(0, +)
        let ids = rows.map(\.id).filter(chosen.contains)
        let which = all ? "All \(chosen.count)" : "\(chosen.count)"
        return VStack(alignment: .leading, spacing: 10) {
            if let queue = checker.testQueue {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("Testing people: screen \(queue.done + 1) of \(queue.total)…").font(.callout)
                    Spacer()
                    Button("Stop", action: checker.stopTesting)
                }
            } else {
                // Which screens, and how to choose others.
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(choosing ? (ticked.isEmpty ? "Click screens in the table to choose them" : "\(ticked.count) chosen") : all ? "All \(chosen.count) screens" : "\(chosen.count) chosen screen\(chosen.count == 1 ? "" : "s")")
                            .font(.callout.weight(.semibold))
                        Text("To fix: \(problems) \(blockingOnly ? "blocking " : "")problem\(problems == 1 ? "" : "s")\(tasks > 0 ? ", \(tasks) task\(tasks == 1 ? "" : "s") people could not do" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if choosing {
                        Button(ticked.count == rows.count ? "Select None" : "Select All") { ticked = ticked.count == rows.count ? [] : Set(rows.map(\.id)) }
                        Button("Done") { choosing = false }.keyboardShortcut(.defaultAction)
                    } else {
                        Button(ticked.isEmpty ? "Choose Screens…" : "Change…") { choosing = true }
                            .help("Then click screens in the table to choose which to test or fix")
                        if !ticked.isEmpty { Button("All Screens") { ticked = [] }.help("Back to every screen") }
                    }
                }
                // What to do with them.
                HStack(spacing: 12) {
                    Spacer()
                    Button { checker.testPeople(on: ids) } label: { Label("Test People on \(which)", systemImage: "person.3") }
                        .disabled(checker.busy)
                        .help("Each screen in turn: opened in the Simulator, and six people try its two main tasks.")
                    Picker("Fix", selection: $blockingOnly) {
                        Text("Blocking only").tag(true)
                        Text("All problems").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Button {
                        checker.fix(screens: chosen, blockingOnly: blockingOnly)
                        ticked = []
                        choosing = false
                    } label: {
                        Label("Fix \(which)", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(work.isEmpty || checker.busy)
                    .help("Muse Wonder changes the code for all of it on one git branch; then every screen is checked again and the people who got stuck try again")
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.08)))
    }

    @ViewBuilder private func tick(_ id: CheckedScreen.ID) -> some View {
        if choosing || !ticked.isEmpty {
            Image(systemName: ticked.contains(id) ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(ticked.contains(id) ? Color.accentColor : .secondary)
                .frame(width: 36)
        }
    }

    private func toggle(_ id: CheckedScreen.ID) {
        if ticked.contains(id) { ticked.remove(id) } else { ticked.insert(id) }
    }

    private func header(_ rows: [CheckedScreen]) -> some View {
        HStack(spacing: 0) {
            if choosing || !ticked.isEmpty { Color.clear.frame(width: 36, height: 1) }
            Text("\(rows.count) screens").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Reach").font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 52)
            ForEach(people) { person in
                let stuck = rows.flatMap { stuckRuns(person, on: $0) }.count
                VStack(spacing: 2) {
                    Image(systemName: person.symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(.tint)
                    Text(stuck > 0 ? "\(stuck) stuck" : " ").font(.caption2.weight(.semibold)).foregroundStyle(.red)
                }
                .frame(width: 58)
                .help("\(person.title): \(person.perceives)")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // MARK: Rows

    private func row(_ checked: CheckedScreen, run: CheckRun?) -> some View {
        let depth = route(of: checked)?.count ?? 0
        return HStack(spacing: 0) {
            tick(checked.id)
            Button { checker.selectedScreen = checked.id } label: {
                HStack(spacing: 10) {
                    if depth > 0 {
                        Image(systemName: "arrow.turn.down.right").font(.caption).foregroundStyle(.tertiary)
                            .padding(.leading, CGFloat(depth - 1) * 22)
                    }
                    thumbnail(checked)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(checked.title).font(.body.weight(.medium)).lineLimit(1)
                        Text(how(checked)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            reach(checked, run: run).frame(width: 52)
            ForEach(people) { person in
                cell(person, on: checked).frame(width: 58)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(ticked.contains(checked.id) ? Color.accentColor.opacity(0.14) : isNow(checked, run: run) ? Color.accentColor.opacity(0.12) : .clear)
        .overlay {
            // While choosing, the whole row is one big tick.
            if choosing {
                Color.white.opacity(0.001).contentShape(Rectangle()).onTapGesture { toggle(checked.id) }
                    .accessibilityElement()
                    .accessibilityLabel("\(checked.title), \(ticked.contains(checked.id) ? "chosen" : "not chosen")")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { toggle(checked.id) }
            }
        }
        .animation(.easeOut(duration: 0.3), value: run?.screens[checked.id])
    }

    /// The screen being worked on right now: walked to, explored or tested.
    private func isNow(_ checked: CheckedScreen, run: CheckRun?) -> Bool {
        if run?.current == checked.id { return true }
        if checker.testing?.screen == checked.id { return true }
        if checker.exploring?.app == app, checker.latestScreens(of: app).max(by: { $0.date < $1.date })?.id == checked.id { return true }
        return false
    }

    private func how(_ checked: CheckedScreen) -> String {
        let way: String
        if let route = route(of: checked) {
            way = route.last.map { "via \u{201C}\(Explorer.words($0))\u{201D}" } ?? "first screen"
        } else {
            way = "checked by hand"
        }
        return "\(way) · \(checked.reviewing ? "checking…" : "\(checked.issues.count) problems")"
    }

    private func thumbnail(_ checked: CheckedScreen) -> some View {
        Group {
            if let picture = checked.picture {
                Image(nsImage: picture).resizable().aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
            }
        }
        .frame(width: 26, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
    }

    @ViewBuilder private func reach(_ checked: CheckedScreen, run: CheckRun?) -> some View {
        if run?.current == checked.id {
            ProgressView().controlSize(.small)
        } else if let outcome = run?.screens[checked.id] {
            switch outcome {
            case .reached:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Reached the way the walk found")
            case .lost(let why):
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red).help(why)
            }
        } else {
            Text("–").foregroundStyle(.quaternary)
        }
    }

    // MARK: People

    /// This person's latest tries on this screen's tasks, from its last test.
    private func runs(_ person: Persona, on checked: CheckedScreen) -> [PersonaRun] {
        guard let tested = checker.lastTest(of: checked) else { return [] }
        return (tested.tasks ?? []).compactMap { tested.run(person, $0) }
    }

    private func stuckRuns(_ person: Persona, on checked: CheckedScreen) -> [PersonaRun] {
        runs(person, on: checked).filter { $0.achieved == false && checker.keptFix(for: $0) == nil }
    }

    @ViewBuilder private func cell(_ person: Persona, on checked: CheckedScreen) -> some View {
        let runs = self.runs(person, on: checked)
        let stuck = stuckRuns(person, on: checked)
        let fixed = runs.filter { $0.achieved == false && checker.keptFix(for: $0) != nil }
        Button {
            if let run = stuck.first ?? fixed.first ?? runs.first { open(run) } else { checker.selectedScreen = checked.id }
        } label: {
            Group {
                if runs.contains(where: { $0.achieved == nil && $0.problem == nil }) {
                    ProgressView().controlSize(.small)
                } else if !stuck.isEmpty {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                } else if !fixed.isEmpty {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                } else if runs.contains(where: { $0.achieved == true }) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Image(systemName: "circle").foregroundStyle(.quaternary)
                }
            }
            .font(.system(size: 16))
            .frame(maxWidth: .infinity, minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(cellHelp(person, runs: runs, stuck: stuck, fixed: fixed))
    }

    private func cellHelp(_ person: Persona, runs: [PersonaRun], stuck: [PersonaRun], fixed: [PersonaRun]) -> String {
        if let run = stuck.first { return "\(person.title) could not \(run.task.goal.lowercasedFirst)" }
        if let run = fixed.first { return "\(person.title) could not \(run.task.goal.lowercasedFirst); fixed since, not tried again" }
        if runs.isEmpty { return "\(person.title): not tried yet" }
        return "\(person.title) got through"
    }
}
