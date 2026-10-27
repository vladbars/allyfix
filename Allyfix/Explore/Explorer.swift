import Foundation

/// Walks an app the way a curious person would: every tab, then what each tab's screen leads
/// to, one level down. Each new screen is checked and kept with the way to it, so personas
/// can be sent there later. Nothing that deletes, pays, sends, signs out or changes settings
/// is ever pressed.
extension Checker {
    /// At most this many screens, so a walk takes minutes, not an afternoon.
    static let mostScreens = 12
    /// Controls tried on each tab's screen to find the screens beyond it.
    static let mostTries = 8

    func exploreApp() {
        guard exploring == nil, testing == nil, fixing == nil else { return }
        exploreProblem = nil
        explore = Task { await walk() }
    }

    func stopExploring() {
        explore?.cancel()
    }

    private func walk() async {
        exploring = (nil, "Starting the app…")
        defer { exploring = nil }
        var visited: [Screen] = []
        var walked: [CheckedScreen.ID] = []
        var thinking: [Task<Void, Never>] = []

        /// Checks the screen shown now, unless it was seen already; keeps the way to it.
        func record(route: [String]) async throws -> Bool {
            let screen = try Simulator.screen()
            guard !visited.contains(where: { Explorer.same($0, screen) }) else { return false }
            visited.append(screen)
            let checked = try capture(select: false)
            walked.append(checked.id)
            update(checked.id) {
                $0.route = route
                $0.name = route.last.map(Explorer.words)
            }
            exploring = (exploring?.app, "Checking screen \(visited.count)…")
            if let picture = await snap(checked) {
                if exploring?.app == nil, let app = screens.first(where: { $0.id == checked.id })?.app, app != "Expo Go" {
                    exploring = (app, exploring?.step ?? "")
                    selection = .app(app)
                }
                // The model looks while the walk goes on.
                thinking.append(Task { await think(checked, picture: picture) })
            }
            return true
        }

        do {
            Restart.forgetApp()
            try await Restart.app()
            try await Explorer.waitForApp()
            let home = try Simulator.screen()
            _ = try await record(route: [])

            // Every tab first: they lead to the app's main screens and stay put.
            let tabs = Explorer.tabs(on: home)
            var roots: [[String]] = [[]]
            for tab in tabs where visited.count < Self.mostScreens {
                try Task.checkCancellation()
                guard let element = Navigator.find(tab, in: try Simulator.screen()) else { continue }
                exploring = (exploring?.app, "Opening \(Explorer.words(tab))…")
                _ = Simulator.press(element)
                try await Explorer.settle()
                if try await record(route: [tab]) { roots.append([tab]) }
            }

            // Then what each main screen leads to, one level down.
            for root in roots where visited.count < Self.mostScreens {
                try await Explorer.go(to: root, tabs: tabs)
                guard let start = try? Simulator.screen() else { continue }
                for label in Explorer.tries(on: start, tabs: tabs).prefix(Self.mostTries) where visited.count < Self.mostScreens {
                    try Task.checkCancellation()
                    if !Explorer.same(try Simulator.screen(), start) { try await Explorer.go(to: root, tabs: tabs) }
                    guard let element = Navigator.find(label, in: try Simulator.screen()) else { continue }
                    exploring = (exploring?.app, "Trying \(Explorer.words(label))…")
                    _ = Simulator.press(element)
                    try await Explorer.settle()
                    try await Explorer.dismissAlert(over: start)
                    let now = try Simulator.screen()
                    if !Explorer.same(now, start) { _ = try await record(route: root + [label]) }
                }
            }
            exploring = (exploring?.app, "Finishing the last checks…")
            for task in thinking { await task.value }
            // One walk is one app, whatever a screen said while the app was still loading.
            if let app = exploring?.app {
                for checked in screens where walked.contains(checked.id) { update(checked.id) { $0.app = app } }
                for id in walked { if let checked = screens.first(where: { $0.id == id }) { History.save(checked) } }
            }
            try await Restart.app()
        } catch is CancellationError {
            exploreProblem = "Stopped."
        } catch {
            exploreProblem = error.localizedDescription
        }
    }
}

enum Explorer {
    /// Never pressed while exploring, in English and German, the languages tested so far.
    static let unsafe = ["delete", "remove", "löschen", "entfernen", "sign out", "log out", "logout", "abmelden",
                         "buy", "purchase", "pay", "kaufen", "bezahlen", "subscribe", "abonnieren", "send", "senden",
                         "share", "teilen", "reset", "erase", "zurücksetzen", "report", "melden", "call", "anrufen"]

    /// Two readings of the tree are the same screen when they start alike or mostly agree.
    static func same(_ a: Screen, _ b: Screen) -> Bool {
        if Array(a.elements.map(\.label).prefix(4)) == Array(b.elements.map(\.label).prefix(4)) { return true }
        let words = { (screen: Screen) in Set(screen.elements.map(\.label).filter { !$0.isEmpty }) }
        let x = words(a), y = words(b)
        return !x.isEmpty && Double(x.intersection(y).count) / Double(x.union(y).count) >= 0.6
    }

    /// The app's tab bar: controls that say they are tabs, or a row of controls along the
    /// bottom of the screen.
    static func tabs(on screen: Screen) -> [String] {
        let said = screen.elements.filter { $0.isControl && ($0.parts.contains("tab") || $0.subrole == "AXTabButton") }
        if said.count >= 2 {
            // A tab that does not say so is still in the same row as those that do.
            let row = said[0].frame.midY
            return screen.elements.filter { $0.isControl && !$0.label.isEmpty && abs($0.frame.midY - row) < 4 }
                .sorted { $0.frame.minX < $1.frame.minX }.map(\.label)
        }
        let bottom = screen.frame.maxY - screen.frame.height * 0.14
        let row = screen.elements.filter { $0.isControl && !$0.readableLabel.isEmpty && $0.frame.midY > bottom }
        return row.count >= 3 ? row.sorted { $0.frame.minX < $1.frame.minX }.map(\.label) : []
    }

    /// What is worth pressing on a screen to find screens beyond it: labelled controls that
    /// are not tabs, not switches or text fields, and nothing unsafe.
    static func tries(on screen: Screen, tabs: [String]) -> [String] {
        screen.elements.filter { element in
            let label = element.readableLabel.lowercased()
            return element.isControl && !label.isEmpty && !tabs.contains(element.label)
                && element.subrole != "AXSwitch" && element.role != "AXTextField" && element.role != "AXCheckBox"
                && !unsafe.contains { label.contains($0) }
        }.map(\.label)
    }

    /// The words a person would use for a control: "Sets, tab, 2 of 5" is "Sets", and
    /// ", From a photo" is "From a photo".
    static func words(_ label: String) -> String {
        label.withIconsNamed.replacingOccurrences(of: "<icon>", with: "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? label
    }

    /// Back to a main screen: its tab, or a fresh start of the app when that does not do it.
    static func go(to route: [String], tabs: [String]) async throws {
        if let tab = route.first, let element = Navigator.find(tab, in: try Simulator.screen()) {
            _ = Simulator.press(element)
            try await settle()
            return
        }
        try await Restart.app()
        try await waitForApp()
        for label in route {
            guard let element = Navigator.find(label, in: try Simulator.screen()) else { return }
            _ = Simulator.press(element)
            try await settle()
        }
    }

    /// Closes an alert that a press opened, so the walk goes on from the screen behind it: a
    /// button to close it that the screen did not have before.
    static func dismissAlert(over start: Screen) async throws {
        let screen = try Simulator.screen()
        let close = ["ok", "cancel", "close", "abbrechen", "schließen", "not now", "später"]
        let before = Set(start.elements.map(\.label))
        if let button = screen.elements.first(where: { close.contains($0.readableLabel.lowercased()) && !before.contains($0.label) }) {
            _ = Simulator.press(button)
            try await settle()
        }
    }

    /// Waits for a restarted app to be past its splash screen: something to press is there,
    /// and the screen has held still for a moment.
    static func waitForApp() async throws {
        var last: [String] = [], still = 0
        for _ in 0..<90 {
            try await Task.sleep(for: .milliseconds(500))
            let screen = try? Simulator.screen()
            let now = screen?.elements.map(\.label) ?? []
            still = now == last && (screen?.elements.filter(\.isControl).count ?? 0) >= 2 ? still + 1 : 0
            if still >= 3 { return }
            last = now
        }
    }

    /// Waits for the screen to hold still after a press: its tree reads the same twice.
    static func settle() async throws {
        var last: [String] = []
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(400))
            let now = (try? Simulator.screen())?.elements.map(\.label) ?? []
            if !now.isEmpty, now == last { return }
            last = now
        }
    }
}
