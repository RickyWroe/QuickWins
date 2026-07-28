import Foundation
import QuickWinsCore

/// Composition root.
///
/// Every system integration is resolved here and injected downward, so no view or controller
/// reaches for a singleton. Tests in QuickWinsCoreTests build the same object graph with test
/// doubles instead.
@MainActor
final class AppEnvironment {
    let logger: DiagnosticLogging
    let time: TimeSource
    let idleProvider: IdleTimeProviding
    let notifications: NotificationScheduling
    let launchAtLogin: LaunchAtLoginManaging
    let settingsStore: SettingsStoring
    let repository: TaskRepository
    let coordinator: TaskCoordinator
    let ticker: TickScheduling

    /// Set when the database had to be rebuilt, so the UI can tell the user once.
    let storeWasRecovered: Bool

    init() {
        let logger = DiagnosticLogger()
        self.logger = logger
        self.time = SystemTimeSource()
        self.idleProvider = SystemIdleTimeProvider()
        self.notifications = UserNotificationService(logger: logger)
        self.launchAtLogin = LaunchAtLoginService(logger: logger)
        self.settingsStore = UserDefaultsSettingsStore(logger: logger)
        self.ticker = TimerService()

        var recovered = false
        let repository: TaskRepository
        do {
            let stack = try CoreDataStack(logger: logger)
            recovered = stack.recoveredFromCorruptStore
            repository = CoreDataTaskRepository(stack: stack, logger: logger)
        } catch {
            // Falling back to memory keeps the app usable for the current session instead of
            // refusing to launch. The UI reports that nothing will be saved.
            logger.error("bootstrap", "Persistent store unavailable: \(error.localizedDescription)")
            repository = InMemoryTaskRepository()
            recovered = false
        }
        self.repository = repository
        self.storeWasRecovered = recovered

        self.coordinator = TaskCoordinator(
            repository: repository,
            settingsStore: settingsStore,
            time: time,
            idleProvider: idleProvider,
            notifications: notifications,
            logger: logger
        )
    }

    var isUsingFallbackStorage: Bool { repository is InMemoryTaskRepository }
}
