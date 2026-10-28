import SwiftUI

extension Checker {
    /// Tasks someone could not do in an app, where the control could: each is a barrier.
    /// From each screen's last test before any fix, shown on the screen's latest check.
    func blocked(in app: String) -> [(screen: CheckedScreen, run: PersonaRun)] {
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

    private var screens: [CheckedScreen] { checker.latestScreens(of: app) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                fixCard
                people
                gallery
                reports
                Folded(title: "Details: \(screens.map(\.issues.count).reduce(0, +)) problems found by automatic checks, code and saved tests") {
                    VStack(alignment: .leading, spacing: 28) {
                        toFix
                        source
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $story) { run in Story(run: run) }
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

    // MARK: Who cannot use it

    private var people: some View {
        let blocked = checker.blocked(in: app)
        let tested = screens.filter { checker.lastTest(of: $0) != nil }
        return Section {
            VStack(spacing: 0) {
                ForEach(Persona.people) { persona in
                    PersonRow(persona: persona, outcome: outcome(for: persona))
                    // Where they got stuck, right here: the screen, the task, why, and the way there.
                    ForEach(blocked.filter { $0.run.persona == persona }, id: \.run.id) { item in
                        StuckRow(checker: checker, app: app, screen: item.screen, run: item.run, open: { story = item.run })
                    }
                    if persona != Persona.people.last { Divider() }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
            Text(tested.isEmpty
                 ? "Nobody has tried this app yet. Open a screen and press Test People: each person tries what the screen is for."
                 : "Tried on \(tested.map(\.title).sorted().joined(separator: ", ")) (\(tested.count) of \(screens.count) screens). To try more, open a screen and press Test People.")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.top, 6)
        } header: {
            SectionTitle("Who can't use it", detail: "Each person tries what a screen is for, with only what they can perceive")
        }
    }

    /// Tasks tried and tasks someone got stuck at, for one person across the app.
    private func outcome(for persona: Persona) -> (tried: Int, stuck: Int)? {
        let runs = screens.compactMap(checker.lastTest).flatMap { tested in
            (tested.personaRuns ?? []).filter { $0.persona == persona && $0.achieved != nil && tested.run(.control, $0.task)?.achieved == true && tested.run(persona, $0.task)?.id == $0.id }
        }
        guard !runs.isEmpty else { return nil }
        return (runs.count, runs.filter { $0.achieved == false }.count)
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

    // MARK: Screens

    private var gallery: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 16)], alignment: .leading, spacing: 18) {
                ForEach(screens) { checked in
                    Button { checker.selectedScreen = checked.id } label: { ScreenCard(checked: checked, blocked: checker.blocked(in: app).filter { $0.screen.id == checked.id }.count) }
                        .buttonStyle(.plain)
                }
            }
        } header: {
            SectionTitle("Screens", detail: "As last checked. Explore App checks them all again.")
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
                        Text("\(tests.count) saved tests run again with no model, in seconds.").foregroundStyle(.secondary)
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

private struct PersonRow: View {
    let persona: Persona
    let outcome: (tried: Int, stuck: Int)?

    var body: some View {
            HStack(spacing: 12) {
                Image(systemName: persona.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.accentColor.opacity(0.12)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(persona.title).font(.body.weight(.medium))
                    Text("\(persona.clause) · \(persona.perceives)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Group {
                    if !persona.ready {
                        Text("Coming soon").foregroundStyle(.tertiary)
                    } else if let outcome {
                        if outcome.stuck > 0 {
                            Label("Stuck at \(outcome.stuck) of \(outcome.tried) tasks", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                        } else {
                            Label("Did all \(outcome.tried) tasks", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    } else {
                        Text("Not tested yet").foregroundStyle(.tertiary)
                    }
                }
                .font(.callout)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        .opacity(persona.ready ? 1 : 0.6)
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
                    Text("**\(screen.title):** could not \(run.task.goal.lowercasedFirst)")
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
        .padding(.leading, 54).padding(.trailing, 12).padding(.bottom, 12)
    }
}

private struct ScreenCard: View {
    let checked: CheckedScreen
    let blocked: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let picture = checked.picture {
                    Image(nsImage: picture).resizable().aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 10).fill(.quaternary).aspectRatio(0.46, contentMode: .fit)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
            .overlay(alignment: .topTrailing) {
                if blocked > 0 {
                    Image(systemName: "person.fill.xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Circle().fill(.red))
                        .padding(6)
                        .help("\(blocked) tasks someone could not do here")
                }
            }
            Text(checked.title).font(.callout.weight(.medium)).lineLimit(1)
            Group {
                if checked.reviewing {
                    Text("Looking…")
                } else {
                    Text(checked.issues.isEmpty ? "No problems" : "\(checked.issues.count) problems")
                }
                Text(checked.date.formatted(.relative(presentation: .named)))
            }
            .font(.caption).foregroundStyle(.secondary)
        }
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
