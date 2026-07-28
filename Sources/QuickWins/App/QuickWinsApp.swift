import SwiftUI

@main
struct QuickWinsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                model: appDelegate.model,
                openPanel: { appDelegate.openPanel() },
                applyShortcut: { appDelegate.applyShortcut() }
            )
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }

        Settings {
            SettingsView(
                model: appDelegate.model,
                shortcutError: appDelegate.currentShortcutError,
                applyShortcut: { appDelegate.applyShortcut() }
            )
        }
    }
}
