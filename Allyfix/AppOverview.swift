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
        latestScreens(of: app).map(chosen).map { $0.issues.count + ($0.personaRuns ?? []).filter { $0.achieved == false && $0.persona != .control }.count }.reduce(0, +)
    }
}

/// One app at a glance: who cannot use it for what, what to fix and where, its screens, and
/// where its code and tests are.
struct AppOverview: View {
    @Bindable var checker: Checker
    let app: String

    private var screens: [CheckedScreen] { checker.latestScreens(of: app) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                people
                toFix
                gallery
                source
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
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

    // MARK: Who cannot use it

    private var people: some View {
        Section {
            VStack(spacing: 0) {
                ForEach(Persona.people) { persona in
                    PersonRow(persona: persona, outcome: outcome(for: persona)) {
                        if let first = checker.blocked(in: app).first(where: { $0.run.persona == persona }) {
                            checker.selectedScreen = first.screen.id
                        }
                    }
                    if persona != Persona.people.last { Divider() }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
        } header: {
            SectionTitle("Who can't use it", detail: "Tasks each person tried on the screens tested so far")
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
        return Section {
            if groups.isEmpty {
                Text(screens.contains(where: \.reviewing) ? "Still looking…" : "Nothing found on the screens checked.").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(groups, id: \.title) { group in
                        let names = Array(Set(group.items.map(\.0.title))).sorted()
                        let keys = group.items.map { Checker.fixKey($0.0.id, $0.1.id) }
                        HStack(spacing: 0) {
                        Toggle("", isOn: Binding(
                            get: { !keys.allSatisfy(checker.excluded.contains) },
                            set: { on in if on { checker.excluded.subtract(keys) } else { checker.excluded.formUnion(keys) } }
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
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("What to fix", detail: "Problems by cause, across every screen")
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
            SectionTitle("Screens", detail: nil)
        }
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
                Divider()
                HStack {
                    Text("A report coding agents and people can work from: what is wrong, where, and how to check it.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Write Report for Agents") { checker.writeAgentReport(for: app) }
                        .help("Writes allyfix/ACCESSIBILITY.md and allyfix/findings.json into the app's source")
                }
                Divider()
                HStack {
                    Text("Drafts of what the law and buyers ask for: the accessibility information the German BFSG requires, and a conformance report in the VPAT EU format.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Write Compliance Reports") { checker.writeComplianceReports(for: app) }
                        .help("Writes Barrierefreiheit and Conformance Report into allyfix/, as Markdown to edit and PDF to send")
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
    let open: () -> Void

    var body: some View {
        Button(action: open) {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(persona.ready ? 1 : 0.6)
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
