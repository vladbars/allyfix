import SwiftUI

@main
struct AllyfixApp: App {
    @State private var checker = Checker()
    @State private var overlay: Overlay?

    var body: some Scene {
        Window("Allyfix", id: "main") {
            ContentView(checker: checker)
                .frame(minWidth: 900, minHeight: 620)
                .onAppear { overlay = overlay ?? Overlay(checker: checker) }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Check This Screen") { checker.check() }
                    .keyboardShortcut("r")
            }
        }
    }
}
