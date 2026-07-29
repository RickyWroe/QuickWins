import AppKit
import QuickWinsCore
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment: AppEnvironment
    let model: AppModel
    let panelController: FloatingPanelController
    let hudController: MiniHUDController
    private let shortcutService: GlobalShortcutService
    private let hudShortcutService: GlobalShortcutService

    /// Surfaced in Settings when macOS refused a configured hot key.
    @Published private(set) var shortcutError: String?
    @Published private(set) var hudShortcutError: String?

    override init() {
        let environment = AppEnvironment()
        self.environment = environment
        let model = AppModel(environment: environment)
        self.model = model
        let panelController = FloatingPanelController(model: model, logger: environment.logger)
        self.panelController = panelController
        self.hudController = MiniHUDController(
            model: model,
            logger: environment.logger,
            openPanel: { panelController.show() }
        )
        self.shortcutService = GlobalShortcutService(logger: environment.logger)
        self.hudShortcutService = GlobalShortcutService(logger: environment.logger)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar app: no Dock tile, no application menu.
        NSApp.setActivationPolicy(.accessory)

        environment.notifications.registerCategories()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }

        model.start()
        environment.coordinator.onSurfacePanel = { [weak self] in
            self?.panelController.surfaceForAlert()
        }

        shortcutService.onTrigger = { [weak self] in
            self?.panelController.toggle()
        }
        hudShortcutService.onTrigger = { [weak self] in
            self?.hudController.toggle()
        }
        applyShortcut()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        environment.logger.info("lifecycle", "QuickWins launched.")
    }

    /// Launching QuickWins again while it is already running — from Finder, Spotlight, or `open`
    /// — shows the panel. Without this the second launch would appear to do nothing at all.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        panelController.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        shortcutService.unregister()
        hudShortcutService.unregister()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        environment.logger.info("lifecycle", "QuickWins terminating.")
    }

    /// Re-registers both hot keys after the user edits them in Settings.
    func applyShortcut() {
        shortcutError = register(
            model.settings.shortcut,
            enabled: model.settings.shortcutEnabled,
            with: shortcutService,
            label: "panel"
        )
        hudShortcutError = register(
            model.settings.miniHUDShortcut,
            enabled: model.settings.miniHUDShortcutEnabled,
            with: hudShortcutService,
            label: "hud"
        )
    }

    /// Returns a message to show the user, or nil on success.
    ///
    /// A conflict must not be silent: without a working hot key the surface is only reachable
    /// from the menu bar, and the user needs to know to pick another key.
    private func register(
        _ binding: ShortcutBinding,
        enabled: Bool,
        with service: GlobalShortcutService,
        label: String
    ) -> String? {
        guard enabled else {
            service.unregister()
            return nil
        }
        do {
            try service.register(binding)
            return nil
        } catch {
            environment.logger.error("shortcut", "\(label) shortcut unavailable: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    var currentShortcutError: String? { shortcutError }
    var currentHUDShortcutError: String? { hudShortcutError }

    func toggleHUD() {
        hudController.toggle()
    }

    @objc private func systemDidWake() {
        environment.logger.info("lifecycle", "System woke from sleep.")
        model.systemDidWake()
    }

    func openPanel() {
        panelController.show()
    }

    func togglePanel() {
        panelController.toggle()
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Alerts are worth seeing even while QuickWins is the active app, since the panel may be
    /// hidden behind the app the user is actually working in.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionIdentifier = response.actionIdentifier
        let taskIDString = response.notification.request.content.userInfo["taskID"] as? String

        await MainActor.run {
            self.handle(actionIdentifier: actionIdentifier, taskIDString: taskIDString)
        }
    }

    private func handle(actionIdentifier: String, taskIDString: String?) {
        let taskID = taskIDString.flatMap(UUID.init(uuidString:))

        switch NotificationAction(rawValue: actionIdentifier) {
        case .stillWorking:
            model.acknowledgeStillWorking()
        case .pauseTask:
            if let taskID { model.pause(taskID) }
        case .completeTask:
            if let taskID { model.complete(taskID) }
        case .snooze:
            model.snooze(.fifteenMinutes)
        case .switchTask:
            panelController.show()
        case nil:
            // Tapping the banner body itself opens the panel.
            if actionIdentifier == UNNotificationDefaultActionIdentifier {
                panelController.show()
            }
        }
    }
}
