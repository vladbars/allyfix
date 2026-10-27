import SwiftUI

struct ContentView: View {
    @Bindable var checker: Checker

    var body: some View {
        if checker.permitted {
            NavigationSplitView {
                AppList(checker: checker)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            } detail: {
                switch checker.selection {
                case .app(let app)?:
                    AppOverview(checker: checker, app: app)
                case .screen?:
                    if let checked = checker.selected { ScreenDetail(checker: checker, checked: checked) }
                case .fix(let id)?:
                    if let fixed = checker.screens.first(where: { $0.id == id && $0.fix != nil }) { FixPage(checker: checker, before: fixed) }
                case nil:
                    start
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if let exploring = checker.exploring {
                        ProgressView().controlSize(.small)
                        Text(exploring.step).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        Button("Stop", action: checker.stopExploring)
                    } else {
                        Button(action: checker.check) { Label("Check Screen", systemImage: "eye") }
                            .help("Check the screen the Simulator shows now (⌘R)")
                        Button(action: checker.exploreApp) { Label("Explore App", systemImage: "map") }
                            .labelStyle(.titleAndIcon)
                            .buttonStyle(.borderedProminent)
                            .disabled(checker.testing != nil || checker.fixing != nil)
                            .help("Walk the app shown in the Simulator, screen by screen, and check each one")
                    }
                }
            }
        } else {
            permission
        }
    }

    /// The first thing a new user sees: what to do, in order.
    private var start: some View {
        ContentUnavailableView {
            Label("Test an app", systemImage: "iphone")
        } description: {
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Run your app in the iOS Simulator, as you always do.")
                Text("2. Explore App: Allyfix walks its screens and checks each one.")
                Text("3. On a screen, Test People: six people with different disabilities try its tasks.")
                Text("4. Fix: the code is changed on a branch, and the same people try again.")
                if let problem = checker.problem ?? checker.exploreProblem {
                    Text(problem).foregroundStyle(.orange).padding(.top, 6)
                }
            }
            .multilineTextAlignment(.leading)
        } actions: {
            Button("Explore App", action: checker.exploreApp).buttonStyle(.borderedProminent)
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

/// The apps tested, each opening into its screens.
private struct AppList: View {
    @Bindable var checker: Checker
    @State private var open: Set<String> = []

    var body: some View {
        List(selection: $checker.selection) {
            Section("Apps") {
                ForEach(checker.apps, id: \.self) { app in
                    DisclosureGroup(isExpanded: Binding(get: { open.contains(app) }, set: { if $0 { open.insert(app) } else { open.remove(app) } })) {
                        ForEach(checker.latestScreens(of: app)) { checked in
                            ScreenRow(checked: checked)
                                .tag(Checker.Selection.screen(checked.id))
                                .contextMenu { Button("Delete", role: .destructive) { checker.delete(checked.id) } }
                        }
                        let fixes = checker.fixes(of: app)
                        if !fixes.isEmpty {
                            Text("Fixes").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 6)
                            ForEach(fixes) { fixed in
                                FixRow(fixed: fixed, verified: checker.verified(fixed)).tag(Checker.Selection.fix(fixed.id))
                            }
                        }
                    } label: {
                        AppRow(app: app, checker: checker).tag(Checker.Selection.app(app))
                    }
                }
            }
        }
        .onChange(of: checker.selection) { _, selection in
            // Opening a screen opens its app in the list too.
            if case .screen = selection, let app = checker.selectedApp { open.insert(app) }
        }
        .safeAreaInset(edge: .bottom) {
            if let problem = checker.problem ?? checker.exploreProblem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        }
    }
}

private struct AppRow: View {
    let app: String
    let checker: Checker

    var body: some View {
        let blocked = checker.blocked(in: app).count
        HStack {
            Label(app, systemImage: "iphone")
            Spacer()
            if checker.exploring != nil, checker.exploring?.app == app {
                ProgressView().controlSize(.mini)
            } else if blocked > 0 {
                Text("\(blocked)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(.red))
                    .help("\(blocked) tasks someone could not do")
            }
        }
    }
}

private struct FixRow: View {
    let fixed: CheckedScreen
    let verified: Bool?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: verified == true ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(verified == true ? .green : .orange)
            Text("\(fixed.title): \(FixPage.headline(fixed.fix!))").lineLimit(1)
        }
        .help(verified == true ? "Fixed and verified" : verified == false ? "Fixed in part" : "Fixed, not verified yet")
    }
}

private struct ScreenRow: View {
    let checked: CheckedScreen

    var body: some View {
        HStack(spacing: 8) {
            Text(checked.title).lineLimit(1)
            if checked.fixOf != nil {
                Text("after fix").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if checked.reviewing {
                ProgressView().controlSize(.mini)
            } else if !checked.issues.isEmpty {
                Text("\(checked.issues.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}
