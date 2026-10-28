import SwiftUI

struct ContentView: View {
    @Bindable var checker: Checker

    var body: some View {
        if checker.permitted {
            NavigationSplitView {
                AppList(checker: checker)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            } detail: {
                VStack(spacing: 0) {
                BusyBar(checker: checker)
                switch checker.selection {
                case .app(let app)?:
                    AppOverview(checker: checker, app: app)
                case .screen?:
                    if let checked = checker.selected { ScreenDetail(checker: checker, checked: checked) }
                case .fix(let id)?:
                    if let fixed = checker.screens.first(where: { $0.id == id }) { FixPage(checker: checker, before: fixed) }
                case nil:
                    start
                }
                }
                .navigationTitle(checker.selection.map(checker.name) ?? "Allyfix")
                .navigationSubtitle(subtitle)
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: checker.goBack) { Label("Back", systemImage: "chevron.left") }
                        .keyboardShortcut("[", modifiers: .command)
                        .disabled(checker.previous == nil)
                        .help(checker.previous.map { "Back to \(checker.name(of: $0)) (⌘[)" } ?? "Back")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let exploring = checker.exploring {
                        ProgressView().controlSize(.small)
                        Text(exploring.step).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        Button("Stop", action: checker.stopExploring)
                    } else {
                        Button(action: checker.check) { Label("Check Screen", systemImage: "eye") }
                            .labelStyle(.titleAndIcon)
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

    /// Under the title: where it is, and how it stands, in a few words.
    private var subtitle: String {
        switch checker.selection {
        case .app(let app)?:
            let screens = checker.latestScreens(of: app).count, stuck = checker.blocked(in: app).count
            return "\(screens) screen\(screens == 1 ? "" : "s") · " + (stuck == 0 ? "nobody got stuck so far" : "\(stuck) task\(stuck == 1 ? "" : "s") someone could not do")
        case .screen?:
            guard let checked = checker.selected else { return "" }
            return "\(Checker.app(of: checked)) · \(checked.reviewing ? "checking…" : "\(checked.issues.count) problem\(checked.issues.count == 1 ? "" : "s")")"
        case .fix(let id)?:
            guard let fixed = checker.screens.first(where: { $0.id == id }) else { return "" }
            if checker.fixing?.screen == id { return "\(Checker.app(of: fixed)) · in progress" }
            return "\(Checker.app(of: fixed)) · " + (fixed.fix?.kept == true ? "kept" : fixed.fix == nil ? "not made" : "waiting for Keep or Undo")
        case nil:
            return ""
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
                    } label: {
                        AppRow(app: app, checker: checker).tag(Checker.Selection.app(app))
                    }
                }
            }
        }
        // The app being looked at stays open in the list, from the start: opening it at the
        // moment a screen is chosen from the overview changes the list mid-update, and SwiftUI
        // then drops the change of page.
        .onAppear {
            if let app = checker.selectedApp { open.insert(app) }
            checker.startWatching()
        }
        .onChange(of: checker.selection) { _, _ in
            if let app = checker.selectedApp { open.insert(app) }
        }
        // Someone may switch branches in the source by hand; look again when the app changes.
        .task(id: checker.selectedApp) { checker.refreshBranch(of: checker.selectedApp) }
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

/// Where a page sits, from the app down, at the top of the page: every step but the last
/// opens that place.
struct PathBar: View {
    @Bindable var checker: Checker
    let steps: [Checker.Selection]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 { Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary) }
                if index < steps.count - 1 {
                    Button(checker.name(of: step)) { checker.selection = step }.buttonStyle(.link)
                } else {
                    Text(checker.name(of: step)).foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Path")
    }
}

/// What Allyfix is busy with, on every page while it lasts, and what can be done meanwhile:
/// looking around, yes; anything else that needs the Simulator, once it is done.
private struct BusyBar: View {
    @Bindable var checker: Checker

    var body: some View {
        if let (id, step, stop) = busy, checker.selection != .fix(id), checker.selectedScreen != id {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text(step).lineLimit(2)
                    Text("Look around meanwhile. Checks, tests and fixes wait until this is done, as it uses the Simulator; keep it in view.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Show") { checker.selection = checker.fixing != nil ? .fix(id) : .screen(id) }
                if let stop { Button("Stop", action: stop) }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.1))
            Divider()
        }
    }

    private var busy: (CheckedScreen.ID, String, (() -> Void)?)? {
        if let fixing = checker.fixing { return (fixing.screen, fixing.step, nil) }
        if let testing = checker.testing { return (testing.screen, testing.step, checker.stopTesting) }
        return nil
    }
}
