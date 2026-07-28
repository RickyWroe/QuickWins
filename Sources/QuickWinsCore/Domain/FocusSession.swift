import Foundation

/// A read-only snapshot of the focus timer for the active task.
///
/// The panel and the menu bar both render from this rather than reading the task directly,
/// so elapsed time is computed the same way everywhere.
public struct FocusSession: Equatable, Sendable {
    public let taskID: UUID
    public let title: String
    public let startedAt: Date?
    public let accumulated: TimeInterval
    public let estimate: TimeInterval?
    public let isRunning: Bool
    public let wasInterrupted: Bool

    public init(task: DailyTask, wasInterrupted: Bool = false) {
        self.taskID = task.id
        self.title = task.title
        self.startedAt = task.sessionStartedAt
        self.accumulated = max(0, task.accumulatedFocus)
        self.estimate = task.estimatedDuration
        self.isRunning = task.status == .active
        self.wasInterrupted = wasInterrupted
    }

    public func elapsed(at now: Date) -> TimeInterval {
        guard let startedAt else { return accumulated }
        return accumulated + max(0, now.timeIntervalSince(startedAt))
    }

    public func remaining(at now: Date) -> TimeInterval? {
        guard let estimate, estimate > 0 else { return nil }
        return max(0, estimate - elapsed(at: now))
    }

    public func overtime(at now: Date) -> TimeInterval? {
        guard let estimate, estimate > 0 else { return nil }
        let over = elapsed(at: now) - estimate
        return over > 0 ? over : nil
    }
}

public enum FocusTimeFormatter {
    /// Compact stopwatch form: `34:18`, or `1:02:33` once an hour has passed.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Menu-bar form, which must stay narrow: `34m`, `1h 02m`.
    public static func abbreviated(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }

    /// Spoken form for VoiceOver, where `34:18` would be read as a time of day.
    public static func spoken(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hour\(hours == 1 ? "" : "s")") }
        if minutes > 0 { parts.append("\(minutes) minute\(minutes == 1 ? "" : "s")") }
        if hours == 0 && (secs > 0 || parts.isEmpty) { parts.append("\(secs) second\(secs == 1 ? "" : "s")") }
        return parts.joined(separator: " ")
    }

    public static func estimate(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded())
        if minutes >= 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
        }
        return "\(minutes)m"
    }
}
