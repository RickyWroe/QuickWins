import Foundation

/// How far the current inactivity has escalated.
///
/// The app never asserts the user is slacking; each level only describes how long the system
/// has reported no input, and every alert asks for confirmation rather than acting alone.
public enum AccountabilityLevel: Int, Comparable, Codable, Sendable, CaseIterable {
    case calm = 0
    case subtle = 1
    case gentle = 2
    case strong = 3
    case interrupted = 4

    public static func < (lhs: AccountabilityLevel, rhs: AccountabilityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A window of the day during which notifications are suppressed.
public struct QuietHours: Codable, Equatable, Sendable {
    /// Minutes from midnight, 0..<1440.
    public var startMinute: Int
    public var endMinute: Int

    public init(startMinute: Int, endMinute: Int) {
        self.startMinute = min(max(0, startMinute), 1_439)
        self.endMinute = min(max(0, endMinute), 1_439)
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if startMinute == endMinute { return false }
        if startMinute < endMinute {
            return minute >= startMinute && minute < endMinute
        }
        // Window wraps past midnight, e.g. 22:00 to 07:00.
        return minute >= startMinute || minute < endMinute
    }
}

public struct AccountabilityConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var subtleThreshold: TimeInterval
    public var gentleThreshold: TimeInterval
    public var strongThreshold: TimeInterval
    public var interruptThreshold: TimeInterval
    /// How long "Still working" suppresses further alerts.
    public var gracePeriod: TimeInterval
    /// Minimum spacing between repeated alerts at the same level.
    public var repeatCooldown: TimeInterval
    public var repeatRemindersEnabled: Bool
    public var surfacePanelOnStrongAlert: Bool
    public var soundEnabled: Bool
    public var quietHours: QuietHours?

    public static let `default` = AccountabilityConfig(
        enabled: true,
        subtleThreshold: 180,
        gentleThreshold: 300,
        strongThreshold: 600,
        interruptThreshold: 900,
        gracePeriod: 300,
        repeatCooldown: 300,
        repeatRemindersEnabled: true,
        surfacePanelOnStrongAlert: true,
        soundEnabled: false,
        quietHours: nil
    )

    public init(
        enabled: Bool,
        subtleThreshold: TimeInterval,
        gentleThreshold: TimeInterval,
        strongThreshold: TimeInterval,
        interruptThreshold: TimeInterval,
        gracePeriod: TimeInterval,
        repeatCooldown: TimeInterval,
        repeatRemindersEnabled: Bool,
        surfacePanelOnStrongAlert: Bool,
        soundEnabled: Bool,
        quietHours: QuietHours?
    ) {
        self.enabled = enabled
        self.subtleThreshold = subtleThreshold
        self.gentleThreshold = gentleThreshold
        self.strongThreshold = strongThreshold
        self.interruptThreshold = interruptThreshold
        self.gracePeriod = gracePeriod
        self.repeatCooldown = repeatCooldown
        self.repeatRemindersEnabled = repeatRemindersEnabled
        self.surfacePanelOnStrongAlert = surfacePanelOnStrongAlert
        self.soundEnabled = soundEnabled
        self.quietHours = quietHours
    }

    /// Thresholds must stay strictly increasing or escalation would skip or thrash.
    public func sanitized() -> AccountabilityConfig {
        var config = self
        config.subtleThreshold = max(30, config.subtleThreshold)
        config.gentleThreshold = max(config.subtleThreshold + 30, config.gentleThreshold)
        config.strongThreshold = max(config.gentleThreshold + 30, config.strongThreshold)
        config.interruptThreshold = max(config.strongThreshold + 30, config.interruptThreshold)
        config.gracePeriod = max(60, config.gracePeriod)
        config.repeatCooldown = max(60, config.repeatCooldown)
        return config
    }

    public func level(forIdle idleSeconds: TimeInterval) -> AccountabilityLevel {
        if idleSeconds >= interruptThreshold { return .interrupted }
        if idleSeconds >= strongThreshold { return .strong }
        if idleSeconds >= gentleThreshold { return .gentle }
        if idleSeconds >= subtleThreshold { return .subtle }
        return .calm
    }
}

/// Snooze windows for activities where low input is legitimate.
public enum SnoozeDuration: Equatable, Sendable, Hashable, CaseIterable {
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case untilResumed

    public var seconds: TimeInterval? {
        switch self {
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        case .thirtyMinutes: return 1_800
        case .untilResumed: return nil
        }
    }

    public var label: String {
        switch self {
        case .fiveMinutes: return "5 minutes"
        case .fifteenMinutes: return "15 minutes"
        case .thirtyMinutes: return "30 minutes"
        case .untilResumed: return "Until I resume"
        }
    }
}

public struct AccountabilityState: Equatable, Sendable {
    public var level: AccountabilityLevel
    public var lastAlertAt: Date?
    /// Alerts are suppressed until this instant after an acknowledgment.
    public var acknowledgedUntil: Date?
    /// Non-nil while snoozed. `Date.distantFuture` means "until manually resumed".
    public var snoozedUntil: Date?
    public var alertsSent: Int
    public var sessionInterrupted: Bool
    /// Task the state refers to; switching tasks resets escalation.
    public var taskID: UUID?

    public static let idle = AccountabilityState(
        level: .calm,
        lastAlertAt: nil,
        acknowledgedUntil: nil,
        snoozedUntil: nil,
        alertsSent: 0,
        sessionInterrupted: false,
        taskID: nil
    )

    public init(
        level: AccountabilityLevel,
        lastAlertAt: Date?,
        acknowledgedUntil: Date?,
        snoozedUntil: Date?,
        alertsSent: Int,
        sessionInterrupted: Bool,
        taskID: UUID?
    ) {
        self.level = level
        self.lastAlertAt = lastAlertAt
        self.acknowledgedUntil = acknowledgedUntil
        self.snoozedUntil = snoozedUntil
        self.alertsSent = alertsSent
        self.sessionInterrupted = sessionInterrupted
        self.taskID = taskID
    }

    public func isSnoozed(at now: Date) -> Bool {
        guard let snoozedUntil else { return false }
        return snoozedUntil > now
    }

    public func isInGracePeriod(at now: Date) -> Bool {
        guard let acknowledgedUntil else { return false }
        return acknowledgedUntil > now
    }
}

/// What the engine asks the app to do. Kept as data so the state machine stays pure.
public enum AccountabilityEffect: Equatable, Sendable {
    case updateIndicator(AccountabilityLevel)
    case notify(AccountabilityAlert)
    case surfacePanel
    case markSessionInterrupted(UUID)
}

public struct AccountabilityAlert: Equatable, Sendable {
    public let level: AccountabilityLevel
    public let taskID: UUID
    public let taskTitle: String
    public let idleSeconds: TimeInterval
    public let playSound: Bool

    public init(level: AccountabilityLevel, taskID: UUID, taskTitle: String, idleSeconds: TimeInterval, playSound: Bool) {
        self.level = level
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.idleSeconds = idleSeconds
        self.playSound = playSound
    }

    public var title: String {
        switch level {
        case .strong, .interrupted: return "Still on \(taskTitle)?"
        default: return "Checking in"
        }
    }

    /// Deliberately phrased as a question. The app cannot know whether the user is working.
    public var body: String {
        let minutes = Int(idleSeconds / 60)
        switch level {
        case .interrupted:
            return "No input for \(minutes) minutes. This focus session is marked interrupted — the task is untouched."
        case .strong:
            return "No input for \(minutes) minutes. Are you still working on this?"
        default:
            return "No input for \(minutes) minutes on \"\(taskTitle)\"."
        }
    }
}
