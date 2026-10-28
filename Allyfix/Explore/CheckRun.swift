import Foundation

/// The checks that need no model, run again on an app: the way to every screen walked as
/// it was found, then every saved test. Free and quick, so they can run whenever the code
/// changes and say at once when a screen can no longer be reached or a barrier is back.
struct CheckRun {
    enum Outcome: Equatable {
        case reached
        case lost(String)
    }

    let app: String
    /// What started it: a person, or a change in the code.
    let reason: String
    var date = Date()
    /// How long it took, once finished.
    var took: TimeInterval?
    var screens: [CheckedScreen.ID: Outcome] = [:]
    var current: CheckedScreen.ID?
    /// By test file: nil when it passed, why when it failed.
    var tests: [String: String?] = [:]
    var testing: String?
    var finished = false
    var problem: String?

    var lost: Int { screens.values.filter { $0 != .reached }.count }
    var failed: Int { tests.values.filter { $0 != nil }.count }
    var passed: Bool { finished && problem == nil && lost == 0 && failed == 0 }
}

extension Checker {
    var busy: Bool { exploring != nil || testing != nil || testQueue != nil || fixing != nil || proving != nil || checkRuns.values.contains { !$0.finished } }

    /// Walks the way to every screen of the app found so far, then runs its saved tests.
    func runChecks(of app: String, reason: String = "Run by hand") {
        guard !busy else { return }
        // The way to each screen, from whichever of its checks knows it.
        let screens = latestScreens(of: app).compactMap { checked -> CheckedScreen? in
            var with = checked
            with.route = checked.route ?? versions(of: checked).lazy.compactMap(\.route).first
            return with.route == nil ? nil : with
        }.sorted { ($0.route?.count ?? 0, $0.date) < ($1.route?.count ?? 0, $1.date) }
        checkRuns[app] = CheckRun(app: app, reason: reason)
        checkTask = Task {
            do {
                try await Restart.app()
                try await Explorer.waitForApp()
                let home = try Simulator.screen()
                let tabs = Explorer.tabs(on: home)
                for checked in screens {
                    try Task.checkCancellation()
                    checkRuns[app]?.current = checked.id
                    checkRuns[app]?.screens[checked.id] = try await reach(checked, tabs: tabs)
                }
                checkRuns[app]?.current = nil
                if let project = project(for: app) {
                    for test in SavedTest.load(from: project.folder) {
                        try Task.checkCancellation()
                        checkRuns[app]?.testing = test.fileName
                        let result = try await test.replay()
                        if case .failed(let why) = result { checkRuns[app]?.tests[test.fileName] = .some(why) } else { checkRuns[app]?.tests[test.fileName] = .some(nil) }
                    }
                }
            } catch is CancellationError {
                checkRuns[app]?.problem = "Stopped."
            } catch {
                checkRuns[app]?.problem = error.localizedDescription
            }
            checkRuns[app]?.current = nil
            checkRuns[app]?.testing = nil
            checkRuns[app]?.finished = true
            checkRuns[app]?.took = Date().timeIntervalSince(checkRuns[app]?.date ?? Date())
            codeStamps[app] = codeStamp(of: app)
        }
    }

    func stopChecks() {
        checkTask?.cancel()
    }

    /// Goes the way the walk found to a screen and tells whether it is there.
    private func reach(_ checked: CheckedScreen, tabs: [String]) async throws -> CheckRun.Outcome {
        let route = checked.route ?? []
        if route.isEmpty {
            try await Restart.app()
            try await Explorer.waitForApp()
        } else {
            try await Explorer.go(to: [route[0]], tabs: tabs)
            for label in route.dropFirst() {
                guard let element = Navigator.find(label, in: try Simulator.screen()) else {
                    return .lost("\"\(Explorer.words(label))\" is gone from the way there.")
                }
                _ = Simulator.press(element)
                try await Explorer.settle()
            }
            // A tab that is not on the screen any more.
            if Navigator.find(route[0], in: try Simulator.screen()) == nil, !tabs.contains(route[0]) {
                return .lost("\"\(Explorer.words(route[0]))\" is gone.")
            }
        }
        let now = try Simulator.screen()
        return Explorer.same(now, checked.screen) ? .reached : .lost("The way there now leads somewhere else.")
    }

    // MARK: Watching the code

    func setWatching(_ app: String, _ on: Bool) {
        if on { watching.insert(app) } else { watching.remove(app) }
        UserDefaults.standard.set(Array(watching), forKey: "watching")
        if on { codeStamps[app] = codeStamp(of: app) }
        startWatching()
    }

    /// Looks at the watched apps' code every few seconds; a change, once the app has had time
    /// to reload, runs the checks.
    func startWatching() {
        watchTimer?.invalidate()
        guard !watching.isEmpty else { return }
        for app in watching where codeStamps[app] == nil { codeStamps[app] = codeStamp(of: app) }
        watchTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.lookAtCode() }
        }
    }

    private func lookAtCode() {
        // Allyfix's own switches of branch are not changes to check.
        guard !busy else { return }
        for app in watching {
            let stamp = codeStamp(of: app)
            guard let stamp, stamp != codeStamps[app] else { continue }
            codeStamps[app] = stamp
            Task {
                try? await Task.sleep(for: .seconds(3))
                runChecks(of: app, reason: "The code changed")
            }
            return
        }
    }

    /// What the app's code is now, in one string: the commit and what is changed beyond it.
    func codeStamp(of app: String) -> String? {
        guard let project = project(for: app),
              let head = try? project.git("rev-parse", "HEAD"),
              let changes = try? project.git("diff", "HEAD", "--", ".") else { return nil }
        return head + String(changes.hashValue)
    }
}
