import SwiftUI

@main
struct AllyfixApp: App {
    @State private var checker = Checker()

    var body: some Scene {
        Window("Allyfix", id: "main") {
            ContentView(checker: checker)
                .frame(minWidth: 380, minHeight: 520)
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
