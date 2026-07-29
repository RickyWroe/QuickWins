import Foundation

/// A single task assigned to one calendar day.
///
/// This is a value type on purpose: all state transitions are pure functions in `TaskRules`,
/// which makes the one-active-task invariant and the timer arithmetic testable without a
/// database or a view.
public struct DailyTask: Identifiable, Equatable, Sendable {
    public static let maxTitleLength = 200
    public static let maxNotesLength = 2_000

    public let id: UUID
    public var title: String
    public var notes: String?
    public var createdAt: Date
    public var day: DayKey
    public var order: Int
    public var estimatedDuration: TimeInterval?
    /// Focus time banked from completed sessions. Never negative.
    public var accumulatedFocus: TimeInterval
    /// Start of the currently running session. Non-nil if and only if `status == .active`.
    public var sessionStartedAt: Date?
    public var completedAt: Date?
    public var status: TaskStatus
    /// User-assigned colour label. Identity only; it never conveys state on its own.
    public var color: TaskColor
    public var remindersEnabled: Bool
    public var idleDetectionEnabled: Bool
    public var alertCount: Int
    public var lastInteractionAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        createdAt: Date,
        day: DayKey,
        order: Int,
        estimatedDuration: TimeInterval? = nil,
        accumulatedFocus: TimeInterval = 0,
        sessionStartedAt: Date? = nil,
        completedAt: Date? = nil,
        status: TaskStatus = .upcoming,
        color: TaskColor = .fallback,
        remindersEnabled: Bool = true,
        idleDetectionEnabled: Bool = true,
        alertCount: Int = 0,
        lastInteractionAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.createdAt = createdAt
        self.day = day
        self.order = order
        self.estimatedDuration = estimatedDuration
        self.accumulatedFocus = accumulatedFocus
        self.sessionStartedAt = sessionStartedAt
        self.completedAt = completedAt
        self.status = status
        self.color = color
        self.remindersEnabled = remindersEnabled
        self.idleDetectionEnabled = idleDetectionEnabled
        self.alertCount = alertCount
        self.lastInteractionAt = lastInteractionAt ?? createdAt
    }

    // MARK: - Focus time

    /// Total focus time including any session currently running.
    ///
    /// Derived from wall-clock timestamps rather than tick counting, so the value stays
    /// correct across panel closure, app relaunch, and system sleep.
    public func elapsedFocus(at now: Date) -> TimeInterval {
        guard let start = sessionStartedAt else { return max(0, accumulatedFocus) }
        // A backwards clock adjustment must never subtract banked time.
        let running = max(0, now.timeIntervalSince(start))
        return max(0, accumulatedFocus) + running
    }

    /// Seconds left against the estimate, or `nil` when no estimate is set.
    /// Clamped at zero; use `overtime(at:)` for the excess.
    public func remaining(at now: Date) -> TimeInterval? {
        guard let estimate = estimatedDuration, estimate > 0 else { return nil }
        return max(0, estimate - elapsedFocus(at: now))
    }

    /// Seconds beyond the estimate, or `nil` when no estimate is set or the estimate holds.
    public func overtime(at now: Date) -> TimeInterval? {
        guard let estimate = estimatedDuration, estimate > 0 else { return nil }
        let over = elapsedFocus(at: now) - estimate
        return over > 0 ? over : nil
    }

    public var hasRunningSession: Bool { sessionStartedAt != nil }

    // MARK: - Defensive normalization

    /// Repairs values that are impossible in the domain but reachable in stored data.
    ///
    /// Applied on every read from persistence so a partially written record, a hand-edited
    /// store, or a schema change cannot put the app into an unrenderable state.
    public func normalized() -> DailyTask {
        var task = self

        task.title = String(task.title.prefix(Self.maxTitleLength))
        if task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            task.title = "Untitled task"
        }

        if let notes = task.notes {
            let trimmed = String(notes.prefix(Self.maxNotesLength))
            task.notes = trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : trimmed
        }

        if !task.accumulatedFocus.isFinite || task.accumulatedFocus < 0 {
            task.accumulatedFocus = 0
        }

        if let estimate = task.estimatedDuration, !estimate.isFinite || estimate <= 0 {
            task.estimatedDuration = nil
        }

        task.alertCount = max(0, task.alertCount)

        // A running session is only meaningful while active. Any other status banks the
        // orphaned session rather than discarding the user's focus time.
        if task.status != .active, let start = task.sessionStartedAt {
            let orphaned = max(0, task.lastInteractionAt.timeIntervalSince(start))
            task.accumulatedFocus += orphaned
            task.sessionStartedAt = nil
        }

        // An active task without a start timestamp cannot compute elapsed time; demote it
        // to paused so the user can explicitly resume rather than silently losing time.
        if task.status == .active && task.sessionStartedAt == nil {
            task.status = .paused
        }

        if task.status == .completed && task.completedAt == nil {
            task.completedAt = task.lastInteractionAt
        }
        if task.status != .completed {
            task.completedAt = nil
        }

        return task
    }
}
