import SwiftUI

@main
struct QuickWinsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                model: appDelegate.model,
                openPanel: { appDelegate.openPanel() },
                toggleHUD: { appDelegate.toggleHUD() },
                hudIsVisible: appDelegate.model.settings.miniHUDVisible
            )
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }

        Settings {
            SettingsView(
                model: appDelegate.model,
                shortcutError: appDelegate.currentShortcutError,
                hudShortcutError: appDelegate.currentHUDShortcutError,
                applyShortcut: { appDelegate.applyShortcut() },
                applyHUDSettings: { appDelegate.applyHUDSettings() }
            )
        }
    }
}
