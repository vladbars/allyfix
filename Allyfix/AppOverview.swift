import SwiftUI

extension Checker {
    /// Tasks someone could not do in an app, where the control could: each is a barrier.
    /// From each screen's last test before any fix, shown on the screen's latest check.
    func blocked(in app: String) -> [(screen: CheckedScreen, run: PersonaRun)] {
        failed(in: app).filter { keptFix(for: $0.run) == nil }
    }

    /// Tasks someone could not do that a kept fix was made for, and nobody tried since.
    func fixedSinceTest(in app: String) -> [(screen: CheckedScreen, run: PersonaRun, fix: CheckedScreen)] {
        failed(in: app).compactMap { item in keptFix(for: item.run).map { (item.screen, item.run, $0) } }
    }

    /// Every task someone could not do in the last test of each screen.
    private func failed(in app: String) -> [(screen: CheckedScreen, run: PersonaRun)] {
        latestScreens(of: app).flatMap { checked -> [(screen: CheckedScreen, run: PersonaRun)] in
            guard let tested = lastTest(of: checked) else { return [] }
            return (tested.personaRuns ?? []).filter { run in
                run.persona != .control && run.achieved == false && tested.run(.control, run.task)?.achieved == true
                    // Only the latest try of each person at each task.
                    && tested.run(run.persona, run.task)?.id == run.id
            }.map { (checked, $0) }
        }
    }

    /// How much is ticked to fix across an app.
    func ticked(in app: String) -> Int {
        let issues = latestScreens(of: app).map { chosen($0).issues.count }.reduce(0, +)
        return issues + blocked(in: app).filter { isTicked(Checker.fixKey($0.screen.id, $0.run.id.uuidString), stuck: true) }.count
    }
}

/// One app at a glance: who cannot use it for what, what to fix and where, its screens, and
/// where its code and tests are.
struct AppOverview: View {
    @Bindable var checker: Checker
    let app: String
    @State private var story: PersonaRun?
    @State private var allStuck = false
    @State private var tab: Tab = .screens

    enum Tab: Hashable { case screens, problems, fixes, reports }

    private var screens: [CheckedScreen] { checker.latestScreens(of: app) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                stats
                fixCard
                Picker("Show", selection: $tab) {
                    Text("Screens · \(screens.count)").tag(Tab.screens)
                    Text("Problems · \(screens.map(\.issues.count).reduce(0, +))").tag(Tab.problems)
                    Text("Fixes & Tests · \(checker.fixes(of: app).count)").tag(Tab.fixes)
                    Text("Reports").tag(Tab.reports)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.large)
                switch tab {
                case .screens:
                    table
                    stuckList
                case .problems:
                    toFix
                case .fixes:
                    fixList
                    source
                case .reports:
                    reports
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $story) { run in Story(run: run, checker: checker) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(app).font(.largeTitle.weight(.bold))
            HStack(spacing: 6) {
                Text("\(screens.count) screens")
                if let last = screens.map(\.date).max() {
                    Text("·")
                    Text("checked \(last.formatted(.relative(presentation: .named)))")
                }
            }
            .foregroundStyle(.secondary)
            if let exploring = checker.exploring, exploring.app == app {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(exploring.step)
                }
                .foregroundStyle(.secondary)
            } else if let problem = checker.exploreProblem {
                Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        }
    }

    // MARK: The app in numbers

    private var stats: some View {
        let issues = screens.flatMap(\.issues)
        let blocking = issues.filter { $0.severity == .blocker }.count
        let tested = screens.filter { checker.lastTest(of: $0) != nil }.count
        let stuck = checker.blocked(in: app).count
        let fixes = checker.fixes(of: app)
        let kept = fixes.filter { $0.fix?.kept == true }.count
        let tests = checker.project(for: app).map { SavedTest.load(from: $0.folder).count } ?? 0
        return HStack(spacing: 10) {
            stat("\(screens.count)", "screens", detail: "found by the walk", opens: .screens)
            stat("\(issues.count)", "problems", detail: "\(blocking) blocking", color: blocking > 0 ? .red : nil, opens: .problems)
            stat("\(tested) of \(screens.count)", "screens tried", detail: "by people", opens: .screens)
            stat("\(stuck)", "tasks stuck", detail: stuck == 0 ? "nobody stuck now" : "people could not do", color: stuck > 0 ? .red : .green, opens: .screens)
            stat("\(fixes.count)", "fixes", detail: "\(kept) kept", opens: .fixes)
            stat("\(tests)", "saved tests", detail: "replay with no AI", opens: .fixes)
        }
    }

    private func stat(_ value: String, _ label: String, detail: String, color: Color? = nil, opens: Tab) -> some View {
        Button { withAnimation(.easeOut(duration: 0.2)) { tab = opens } } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title.weight(.semibold).monospacedDigit()).foregroundStyle(color ?? .primary)
                Text(label).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(tab == opens ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tab == opens ? Color.accentColor.opacity(0.5) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value) \(label), \(detail)")
    }

    // MARK: Fixes made

    @ViewBuilder private var fixList: some View {
        let fixes = checker.fixes(of: app)
        Section {
            if fixes.isEmpty {
                Text("No fixes yet. Tick screens under Screens and press Fix, or Fix a task someone could not do.").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(fixes) { fixed in
                        Button { checker.selection = .fix(fixed.id) } label: {
                            HStack(spacing: 10) {
                                let kept = fixed.fix?.kept == true
                                let open = checker.openFix(of: app)?.id == fixed.id
                                Image(systemName: kept ? "checkmark.seal.fill" : open ? "arrow.triangle.branch" : "arrow.uturn.backward.circle")
                                    .foregroundStyle(kept ? .green : open ? .orange : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(checker.fixTitle(of: fixed)).font(.body.weight(.medium)).lineLimit(1)
                                    Text("\(fixed.title) · \(fixed.date.formatted(date: .abbreviated, time: .shortened)) · " + (kept ? "kept in \(fixed.fix?.base ?? "main")" : open ? "in the app now, waiting for Keep or Undo" : "not in the app"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
            }
        } header: {
            SectionTitle("Fixes", detail: nil)
        }
    }

    // MARK: A fix under way, or waiting for a decision

    @ViewBuilder private var fixCard: some View {
        if let fixing = checker.fixing, let fixed = checker.screens.first(where: { $0.id == fixing.screen }), Checker.app(of: fixed) == app {
            card(symbol: nil, color: .accentColor, title: "Fixing: " + checker.fixTitle(of: fixed).lowercasedFirst, detail: fixing.step) {
                Button("Show") { checker.selection = .fix(fixed.id) }
            }
        } else if let open = checker.openFix(of: app) {
            card(symbol: "arrow.triangle.branch", color: .orange, title: checker.fixTitle(of: open), detail: "This fix is in the app now, on its own branch. Keep it, or undo it.") {
                Button("Open Fix") { checker.selection = .fix(open.id) }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func card(symbol: String?, color: Color, title: String, detail: String, @ViewBuilder actions: () -> some View) -> some View {
        HStack(spacing: 12) {
            if let symbol { Image(systemName: symbol).font(.title2).foregroundStyle(color) } else { ProgressView().controlSize(.small) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            actions()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.1)))
    }

    // MARK: Screens and people

    private var table: some View {
        Section {
            ScreensTable(checker: checker, app: app) { story = $0 }
        } header: {
            SectionTitle("Screens and people", detail: "Who gets through where, screen by screen")
        }
    }

    /// The tasks people could not do, each with Fix; the first few, and the rest on request.
    @ViewBuilder private var stuckList: some View {
        let blocked = checker.blocked(in: app)
        let fixed = checker.fixedSinceTest(in: app)
        if !blocked.isEmpty || !fixed.isEmpty {
            Section {
                VStack(spacing: 0) {
                    ForEach(Array(blocked.prefix(allStuck ? blocked.count : 5)), id: \.run.id) { item in
                        StuckRow(checker: checker, app: app, screen: item.screen, run: item.run, open: { story = item.run })
                            .padding(.top, 12)
                        Divider()
                    }
                    ForEach(fixed, id: \.run.id) { item in
                        FixedRow(checker: checker, screen: item.screen, run: item.run, fix: item.fix).padding(.top, 12)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
                if blocked.count > 5 {
                    Button(allStuck ? "Show Fewer" : "Show All \(blocked.count)") { allStuck.toggle() }.buttonStyle(.link)
                }
            } header: {
                SectionTitle("Could not do", detail: blocked.isEmpty ? "Nothing left; fixed since the test" : "\(blocked.count) task\(blocked.count == 1 ? "" : "s"), the worst barriers: fix these first")
            }
        }
    }

    // MARK: What to fix

    private var toFix: some View {
        let groups = Dictionary(grouping: screens.flatMap { checked in checked.issues.map { (checked, $0) } }, by: { $0.1.kind.group })
            .map { (title: $0.key, items: $0.value) }
            .sorted {
                let a = $0.items.map(\.1.severity).min()!, b = $1.items.map(\.1.severity).min()!
                return a != b ? a < b : $0.items.count > $1.items.count
            }
        let blocked = checker.blocked(in: app)
        let stuckKeys = blocked.map { Checker.fixKey($0.screen.id, $0.run.id.uuidString) }
        return Section {
            if groups.isEmpty && blocked.isEmpty {
                Text(screens.contains(where: \.reviewing) ? "Still looking…" : "Nothing found on the screens checked.").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    // What stopped people first: real barriers, and ticked from the start.
                    if !blocked.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Toggle("", isOn: Binding(
                                get: { stuckKeys.contains { checker.isTicked($0, stuck: true) } },
                                set: { on in for key in stuckKeys { checker.choices[key] = on } }
                            ))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .help("Fix what stopped them")
                            Image(systemName: "person.fill.xmark").foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tasks people could not do").font(.body.weight(.medium))
                                Text(blocked.map { "\($0.run.persona.title): \($0.run.task.goal.lowercasedFirst) (\($0.screen.title))" }.joined(separator: "; "))
                                    .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Text("\(blocked.count)").font(.title3.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        if !groups.isEmpty { Divider() }
                    }
                    ForEach(groups, id: \.title) { group in
                        let names = Array(Set(group.items.map(\.0.title))).sorted()
                        let keys = group.items.map { Checker.fixKey($0.0.id, $0.1.id) }
                        HStack(spacing: 0) {
                        Toggle("", isOn: Binding(
                            get: { keys.contains { checker.isTicked($0, stuck: false) } },
                            set: { on in for key in keys { checker.choices[key] = on } }
                        ))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .padding(.leading, 12)
                        .help("Fix this everywhere it was found")
                        Button {
                            checker.selectedScreen = group.items[0].0.id
                            checker.selectedIssue = group.items[0].1.id
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: group.items.contains { $0.1.severity == .blocker } ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(group.items.contains { $0.1.severity == .blocker } ? .red : .orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.title).font(.body.weight(.medium))
                                    Text(names.joined(separator: ", ")).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                Text("\(group.items.count)").font(.title3.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        }
                        if group.title != groups.last?.title { Divider() }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
                Text(checker.ticked(in: app) == 0
                     ? "Tick what to fix, or use Select. A small fix is easier to check and to review."
                     : "Ticked to start with: what stopped people. Tick more to fix more in the same go; a small fix is easier to review.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("Problems", detail: "By cause, across every screen")
                Spacer()
                let count = checker.ticked(in: app)
                Menu("Select") {
                    ForEach(Checker.Pick.allCases, id: \.self) { pick in
                        Button(pick.rawValue) { checker.pick(pick, on: checker.latestScreens(of: app)) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Tick all, only what blocks, only what stopped people, or nothing, on every screen")
                Button(action: { checker.fixSelected(in: app) }) { Label("Fix \(count) Selected", systemImage: "wand.and.stars") }
                    .buttonStyle(.borderedProminent)
                    .disabled(count == 0 || checker.fixing != nil || checker.testing != nil || checker.exploring != nil)
                    .help("Changes the code for everything ticked, on one branch; then every screen it touched is checked again and the people who got stuck try again")
            }
        }
    }

    // MARK: Reports

    private var reports: some View {
        Section {
            HStack(alignment: .top, spacing: 16) {
                report("For coding agents", "What is wrong, where, and how to check it, for Claude Code, Codex or a person.", button: "Write Report for Agents") { checker.writeAgentReport(for: app) }
                report("For the law and buyers", "Drafts of the BFSG accessibility information and a VPAT EU conformance report, as PDF.", button: "Write Compliance Reports") { checker.writeComplianceReports(for: app) }
            }
        } header: {
            SectionTitle("Reports", detail: nil)
        }
    }

    private func report(_ title: String, _ detail: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(button, action: action)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
    }

    // MARK: Code and tests

    private var source: some View {
        let project = checker.project(for: app)
        let tests = project.map { SavedTest.load(from: $0.folder) } ?? []
        return Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if let project {
                        Label(project.folder.path(percentEncoded: false), systemImage: "folder").lineLimit(1).truncationMode(.middle)
                    } else {
                        Text("Fixes need the app's source. Without it Allyfix still tests, but does not change code.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(project == nil ? "Choose Folder…" : "Change…") { checker.chooseProject(for: app) }
                }
                if !tests.isEmpty {
                    Divider()
                    HStack {
                        Text("\(tests.count) saved tests run again with no model.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Run Saved Tests") { checker.runSavedTests(of: app) }
                            .disabled(checker.exploring != nil || checker.testing != nil)
                    }
                    ForEach(tests, id: \.fileName) { test in
                        SavedTestRow(test: test, result: checker.savedResults[test.fileName])
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
        } header: {
            SectionTitle("Code and tests", detail: nil)
        }
    }
}

private struct SectionTitle: View {
    let title: String
    let detail: String?

    init(_ title: String, detail: String?) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.semibold))
            if let detail { Text(detail).font(.callout).foregroundStyle(.secondary) }
        }
        .padding(.bottom, 4)
    }
}

/// A task someone could not do: where, why, and buttons to see how it went and the screen.
private struct StuckRow: View {
    @Bindable var checker: Checker
    let app: String
    let screen: CheckedScreen
    let run: PersonaRun
    let open: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let jpeg = run.steps.last?.jpeg ?? run.steps.first?.jpeg, let image = NSImage(data: jpeg) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary).aspectRatio(0.46, contentMode: .fit)
                }
            }
            .frame(width: 54)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            .help("What they saw")
            VStack(alignment: .leading, spacing: 5) {
                Label {
                    Text("**\(run.persona.title)** could not \(run.task.goal.lowercasedFirst) on **\(screen.title)**")
                } icon: {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                }
                if let why = run.reason { Text(why).font(.callout).foregroundStyle(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true) }
                if let boundary = run.boundary { SizeScale(boundary: boundary) }
                HStack(spacing: 14) {
                    if let fixed = checker.fix(for: run, in: app) {
                        Button { checker.selection = .fix(fixed.id) } label: { Label("Open Fix", systemImage: "wand.and.stars") }
                            .help("See what the fix changed and whether they get through now; keep it or undo it there")
                    } else {
                        Button { checker.fix(stuck: run, on: screen) } label: { Label("Fix", systemImage: "wand.and.stars") }
                            .buttonStyle(.borderedProminent)
                            .disabled(checker.fixing != nil || checker.testing != nil || checker.exploring != nil)
                            .help("Muse Wonder changes the app's code for this on a new git branch; then \(run.persona.title.lowercased()) tries the task again")
                    }
                    Button("See What Happened", action: open)
                    Button("Open \(screen.title)") { checker.selectedScreen = screen.id }.buttonStyle(.link)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.bottom, 12)
    }
}


private struct SavedTestRow: View {
    let test: SavedTest
    let result: SavedTest.Result??

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                switch result {
                case .some(.none): ProgressView().controlSize(.mini)
                case .some(.some(.passed)): Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .some(.some(.failed)): Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                case .none: Image(systemName: "circle.dashed").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(test.persona.title): \(test.task)").font(.callout)
                if case .some(.some(.failed(let why))) = result {
                    Text(why).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(test.screen) · allyfix/tests/\(test.fileName)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A task someone could not do that a kept fix was made for: fixed, and to be tried again.
private struct FixedRow: View {
    @Bindable var checker: Checker
    let screen: CheckedScreen
    let run: PersonaRun
    let fix: CheckedScreen

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label {
                Text("**\(run.persona.title)** could not \(run.task.goal.lowercasedFirst) on **\(screen.title)**. Fixed and kept in \(fix.fix?.base ?? "main"); not tried again since.")
            } icon: {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            }
            HStack(spacing: 14) {
                Button("Test Again") {
                    checker.selectedScreen = checker.latest(of: screen).id
                    checker.testPersonas()
                }
                .buttonStyle(.borderedProminent)
                .disabled(checker.testing != nil || checker.fixing != nil || checker.exploring != nil)
                .help("Opens \(screen.title) in the Simulator and has the people try its tasks again, on the code as it is now")
                Button("Open Fix") { checker.selection = .fix(fix.id) }
            }
            .padding(.leading, 28)
        }
        .padding(.horizontal, 12).padding(.bottom, 12)
    }
}
