import AppKit
import SwiftUI

@main
struct QuickWinsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    static let statsWindowID = "quickwins.stats"

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                model: appDelegate.model,
                openPanel: { appDelegate.openPanel() },
                toggleHUD: { appDelegate.toggleHUD() },
                hudIsVisible: appDelegate.model.settings.miniHUDVisible,
                openStats: {
                    // An accessory app has to activate itself, or the window opens behind
                    // whatever the user is looking at.
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: Self.statsWindowID)
                }
            )
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }

        Window("QuickWins Statistics", id: Self.statsWindowID) {
            StatsView(model: appDelegate.model)
        }
        .defaultSize(width: 880, height: 620)
        .windowResizability(.contentMinSize)

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
