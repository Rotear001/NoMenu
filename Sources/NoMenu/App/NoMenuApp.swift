import SwiftUI

@main
struct NoMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n.text("Settings…")) {
                    appDelegate.showSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
