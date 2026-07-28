import Foundation
import UserNotifications

public enum NotificationAuthorization: String, Sendable {
    case notDetermined
    case authorized
    case provisional
    case denied
    /// The process has no bundle identifier, so the notification system is unusable.
    case unavailable

    public var allowsDelivery: Bool { self == .authorized || self == .provisional }
}

/// Actions offered on an accountability alert. Each one asks the user what is true rather than
/// letting the app decide on its own.
public enum NotificationAction: String, Sendable, CaseIterable {
    case stillWorking = "quickwins.action.stillWorking"
    case pauseTask = "quickwins.action.pause"
    case switchTask = "quickwins.action.switch"
    case completeTask = "quickwins.action.complete"
    case snooze = "quickwins.action.snooze"

    public var title: String {
        switch self {
        case .stillWorking: return "Still working"
        case .pauseTask: return "Pause task"
        case .switchTask: return "Switch task"
        case .completeTask: return "Complete task"
        case .snooze: return "Snooze 15 min"
        }
    }
}

public enum NotificationCategory {
    public static let accountability = "quickwins.category.accountability"
}

public protocol NotificationScheduling: AnyObject, Sendable {
    func registerCategories()
    func currentAuthorization() async -> NotificationAuthorization
    func requestAuthorization() async -> NotificationAuthorization
    func post(_ alert: AccountabilityAlert) async throws
    func removeDeliveredAlerts() async
}

public enum NotificationServiceError: Error, LocalizedError {
    case unavailable
    case notAuthorized

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Notifications are unavailable because the app is not running from an application bundle."
        case .notAuthorized:
            return "Notification permission has not been granted."
        }
    }
}

/// Local-only notifications. No content ever leaves the machine and no remote token is
/// registered.
public final class UserNotificationService: NotificationScheduling, @unchecked Sendable {
    private let logger: DiagnosticLogging

    /// `UNUserNotificationCenter.current()` traps when the process has no bundle identifier,
    /// which is the case when the executable is run directly instead of from QuickWins.app.
    private let isBundled: Bool

    public init(logger: DiagnosticLogging) {
        self.logger = logger
        self.isBundled = Bundle.main.bundleIdentifier != nil
        if !isBundled {
            logger.notice("notifications", "No bundle identifier; notification delivery disabled for this process.")
        }
    }

    private var center: UNUserNotificationCenter? {
        isBundled ? UNUserNotificationCenter.current() : nil
    }

    public func registerCategories() {
        guard let center else { return }
        let actions = [
            UNNotificationAction(identifier: NotificationAction.stillWorking.rawValue, title: NotificationAction.stillWorking.title, options: []),
            UNNotificationAction(identifier: NotificationAction.pauseTask.rawValue, title: NotificationAction.pauseTask.title, options: []),
            UNNotificationAction(identifier: NotificationAction.switchTask.rawValue, title: NotificationAction.switchTask.title, options: [.foreground]),
            UNNotificationAction(identifier: NotificationAction.completeTask.rawValue, title: NotificationAction.completeTask.title, options: []),
            UNNotificationAction(identifier: NotificationAction.snooze.rawValue, title: NotificationAction.snooze.title, options: []),
        ]
        let category = UNNotificationCategory(
            identifier: NotificationCategory.accountability,
            actions: actions,
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    public func currentAuthorization() async -> NotificationAuthorization {
        guard let center else { return .unavailable }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    public func requestAuthorization() async -> NotificationAuthorization {
        guard let center else { return .unavailable }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            logger.error("notifications", "Authorization request failed: \(error.localizedDescription)")
        }
        return await currentAuthorization()
    }

    public func post(_ alert: AccountabilityAlert) async throws {
        guard let center else { throw NotificationServiceError.unavailable }
        guard await currentAuthorization().allowsDelivery else { throw NotificationServiceError.notAuthorized }

        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.categoryIdentifier = NotificationCategory.accountability
        content.userInfo = ["taskID": alert.taskID.uuidString, "level": alert.level.rawValue]
        content.interruptionLevel = alert.level >= .strong ? .timeSensitive : .active
        if alert.playSound { content.sound = .default }
        // Collapsing on the task keeps escalating alerts from stacking up in Notification Center.
        content.threadIdentifier = alert.taskID.uuidString

        let request = UNNotificationRequest(
            identifier: "quickwins.alert.\(alert.taskID.uuidString)",
            content: content,
            trigger: nil
        )
        try await center.add(request)
        logger.info("notifications", "Posted level \(alert.level.rawValue) alert for task \(alert.taskID.uuidString).")
    }

    public func removeDeliveredAlerts() async {
        guard let center else { return }
        let delivered = await center.deliveredNotifications()
        let ids = delivered
            .filter { $0.request.content.categoryIdentifier == NotificationCategory.accountability }
            .map(\.request.identifier)
        guard !ids.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
}

/// Records what would have been delivered. Used to assert scheduling without a notification
/// daemon.
public final class RecordingNotificationService: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var _posted: [AccountabilityAlert] = []
    private var _authorization: NotificationAuthorization
    private var _registeredCategories = false
    private var _removeCallCount = 0

    public init(authorization: NotificationAuthorization = .authorized) {
        self._authorization = authorization
    }

    public var posted: [AccountabilityAlert] {
        lock.lock(); defer { lock.unlock() }
        return _posted
    }

    public var didRegisterCategories: Bool {
        lock.lock(); defer { lock.unlock() }
        return _registeredCategories
    }

    public var removeCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _removeCallCount
    }

    public func setAuthorization(_ value: NotificationAuthorization) {
        lock.lock(); _authorization = value; lock.unlock()
    }

    public func registerCategories() {
        lock.lock(); _registeredCategories = true; lock.unlock()
    }

    // The async members below delegate to these synchronous helpers: locking directly inside an
    // async function is diagnosed as unsafe because the compiler cannot prove no suspension
    // occurs while the lock is held.
    private func readAuthorization() -> NotificationAuthorization {
        lock.lock(); defer { lock.unlock() }
        return _authorization
    }

    private func grantIfUndetermined() -> NotificationAuthorization {
        lock.lock(); defer { lock.unlock() }
        if _authorization == .notDetermined { _authorization = .authorized }
        return _authorization
    }

    private func record(_ alert: AccountabilityAlert) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard _authorization.allowsDelivery else { return false }
        _posted.append(alert)
        return true
    }

    private func countRemoval() {
        lock.lock(); _removeCallCount += 1; lock.unlock()
    }

    public func currentAuthorization() async -> NotificationAuthorization {
        readAuthorization()
    }

    public func requestAuthorization() async -> NotificationAuthorization {
        grantIfUndetermined()
    }

    public func post(_ alert: AccountabilityAlert) async throws {
        guard record(alert) else { throw NotificationServiceError.notAuthorized }
    }

    public func removeDeliveredAlerts() async {
        countRemoval()
    }
}
