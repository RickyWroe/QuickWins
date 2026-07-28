import Foundation

public enum TaskRuleError: Error, Equatable {
    case emptyTitle
    case taskNotFound(UUID)
    case invalidTransition(from: TaskStatus, to: TaskStatus)
    case indexOutOfRange
}

extension TaskRuleError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return "A task needs a title."
        case .taskNotFound:
            return "That task no longer exists."
        case .invalidTransition(let from, let to):
            return "A \(from.rawValue) task cannot become \(to.rawValue)."
        case .indexOutOfRange:
            return "That position is no longer valid."
        }
    }
}

/// The single source of truth for task state transitions.
///
/// Every function is pure: it takes the day's tasks, returns a new array, and never touches
/// persistence or the UI. The one-active-task invariant is enforced here rather than in views,
/// so it holds regardless of which surface (panel, menu bar, notification action) initiated
/// the change.
public enum TaskRules {

    // MARK: - Creation

    public static func normalizedTitle(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TaskRuleError.emptyTitle }
        return String(trimmed.prefix(DailyTask.maxTitleLength))
    }

    public static func makeTask(
        title: String,
        notes: String? = nil,
        day: DayKey,
        estimatedDuration: TimeInterval? = nil,
        in tasks: [DailyTask],
        at now: Date
    ) throws -> DailyTask {
        let cleanTitle = try normalizedTitle(title)
        let nextOrder = (tasks.map(\.order).max() ?? -1) + 1
        let estimate = estimatedDuration.flatMap { $0 > 0 ? $0 : nil }
        return DailyTask(
            title: cleanTitle,
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            createdAt: now,
            day: day,
            order: nextOrder,
            estimatedDuration: estimate,
            lastInteractionAt: now
        )
    }

    // MARK: - Invariant

    /// The single running task, if any.
    public static func activeTask(in tasks: [DailyTask]) -> DailyTask? {
        tasks.first { $0.status == .active }
    }

    /// True when at most one task is active and only an active task holds a session.
    public static func satisfiesSingleActiveInvariant(_ tasks: [DailyTask]) -> Bool {
        let actives = tasks.filter { $0.status == .active }
        guard actives.count <= 1 else { return false }
        return tasks.allSatisfy { $0.hasRunningSession == ($0.status == .active) }
    }

    /// Banks any running time and clears the session, leaving the task paused.
    private static func suspend(_ task: DailyTask, at now: Date) -> DailyTask {
        var updated = task
        if let start = updated.sessionStartedAt {
            updated.accumulatedFocus = max(0, updated.accumulatedFocus + max(0, now.timeIntervalSince(start)))
            updated.sessionStartedAt = nil
        }
        updated.status = .paused
        updated.lastInteractionAt = now
        return updated
    }

    // MARK: - Transitions

    public static func start(_ id: UUID, in tasks: [DailyTask], at now: Date) throws -> [DailyTask] {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            throw TaskRuleError.taskNotFound(id)
        }
        let target = tasks[index]
        guard target.status.isOpen else {
            throw TaskRuleError.invalidTransition(from: target.status, to: .active)
        }
        if target.status == .active { return tasks }

        var updated = tasks
        // Suspending every other running task is what makes the invariant hold; doing it in
        // the same pure step means callers cannot persist a half-applied switch.
        for other in updated.indices where updated[other].status == .active {
            updated[other] = suspend(updated[other], at: now)
        }

        var task = updated[index]
        task.status = .active
        task.sessionStartedAt = now
        task.completedAt = nil
        task.lastInteractionAt = now
        updated[index] = task
        return updated
    }

    public static func pause(_ id: UUID, in tasks: [DailyTask], at now: Date) throws -> [DailyTask] {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            throw TaskRuleError.taskNotFound(id)
        }
        let target = tasks[index]
        guard target.status == .active else {
            if target.status == .paused { return tasks }
            throw TaskRuleError.invalidTransition(from: target.status, to: .paused)
        }
        var updated = tasks
        updated[index] = suspend(target, at: now)
        return updated
    }

    /// Pauses a running task or starts a stopped one.
    public static func toggle(_ id: UUID, in tasks: [DailyTask], at now: Date) throws -> [DailyTask] {
        guard let target = tasks.first(where: { $0.id == id }) else {
            throw TaskRuleError.taskNotFound(id)
        }
        return target.status == .active
            ? try pause(id, in: tasks, at: now)
            : try start(id, in: tasks, at: now)
    }

    public static func complete(_ id: UUID, in tasks: [DailyTask], at now: Date) throws -> [DailyTask] {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            throw TaskRuleError.taskNotFound(id)
        }
        var task = tasks[index]
        guard task.status != .completed else { return tasks }

        if let start = task.sessionStartedAt {
            task.accumulatedFocus = max(0, task.accumulatedFocus + max(0, now.timeIntervalSince(start)))
            task.sessionStartedAt = nil
        }
        task.status = .completed
        task.completedAt = now
        task.lastInteractionAt = now

        var updated = tasks
        updated[index] = task
        return updated
    }

    public static func skip(_ id: UUID, in tasks: [DailyTask], at now: Date) throws -> [DailyTask] {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            throw TaskRuleError.taskNotFound(id)
        }
        var task = tasks[index]
        guard task.status != .skipped else { return tasks }

        if let start = task.sessionStartedAt {
            task.accumulatedFocus = max(0, task.accumulatedFocus + max(0, now.timeIntervalSince(start)))
            task.sessionStartedAt = nil
        }
        task.status = .skipped
        task.completedAt = nil
        task.lastInteractionAt = now

        var updated = tasks
        updated[index] = task
        return updated
    }

    /// Returns a completed or skipped task to the working set, preserving banked focus time.
    public static func restore(_ id: UUID, in tasks: [DailyTask], at now: Date) throws -> [DailyTask] {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            throw TaskRuleError.taskNotFound(id)
        }
        var task = tasks[index]
        guard task.status == .completed || task.status == .skipped else {
            throw TaskRuleError.invalidTransition(from: task.status, to: .upcoming)
        }
        task.status = task.accumulatedFocus > 0 ? .paused : .upcoming
        task.completedAt = nil
        task.sessionStartedAt = nil
        task.lastInteractionAt = now

        var updated = tasks
        updated[index] = task
        return updated
    }

    // MARK: - Ordering

    /// Moves a task to a new position and renumbers the whole day so `order` stays dense.
    public static func reorder(_ id: UUID, to destination: Int, in tasks: [DailyTask]) throws -> [DailyTask] {
        var sorted = tasks.sorted { $0.order < $1.order }
        guard let current = sorted.firstIndex(where: { $0.id == id }) else {
            throw TaskRuleError.taskNotFound(id)
        }
        guard sorted.indices.contains(destination) else {
            throw TaskRuleError.indexOutOfRange
        }
        let moved = sorted.remove(at: current)
        sorted.insert(moved, at: destination)
        return renumber(sorted)
    }

    /// Collapses gaps and duplicates in `order` while preserving the current visual sequence.
    public static func renumber(_ tasks: [DailyTask]) -> [DailyTask] {
        tasks.enumerated().map { index, task in
            var copy = task
            copy.order = index
            return copy
        }
    }

    public static func sortedForDisplay(_ tasks: [DailyTask]) -> [DailyTask] {
        tasks.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.createdAt < rhs.createdAt
        }
    }

    // MARK: - Day movement

    public static func move(_ id: UUID, to day: DayKey, in tasks: [DailyTask], at now: Date) throws -> [DailyTask] {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            throw TaskRuleError.taskNotFound(id)
        }
        var task = tasks[index]
        if task.status == .active {
            task = suspend(task, at: now)
        }
        task.day = day
        if task.status == .overdue { task.status = .upcoming }
        task.lastInteractionAt = now

        var updated = tasks
        updated[index] = task
        return updated
    }

    /// Flags still-open tasks left behind on earlier days and banks any session that was
    /// running when the date changed.
    public static func applyRollover(to tasks: [DailyTask], today: DayKey, at now: Date) -> [DailyTask] {
        tasks.map { task in
            guard task.day < today, task.status.isOpen else { return task }
            var updated = task
            if let start = updated.sessionStartedAt {
                updated.accumulatedFocus = max(0, updated.accumulatedFocus + max(0, now.timeIntervalSince(start)))
                updated.sessionStartedAt = nil
            }
            updated.status = .overdue
            return updated
        }
    }

    // MARK: - Selection & progress

    /// The task to promote after the current one finishes, in display order.
    public static func nextTask(after id: UUID?, in tasks: [DailyTask]) -> DailyTask? {
        let ordered = sortedForDisplay(tasks).filter { $0.status.isOpen && $0.status != .active }
        guard let id, let currentOrder = tasks.first(where: { $0.id == id })?.order else {
            return ordered.first
        }
        return ordered.first { $0.order > currentOrder } ?? ordered.first
    }

    public static func progress(in tasks: [DailyTask]) -> (completed: Int, total: Int) {
        let counted = tasks.filter { $0.status != .skipped }
        return (counted.filter { $0.status == .completed }.count, counted.count)
    }

    public static func totalFocus(in tasks: [DailyTask], at now: Date) -> TimeInterval {
        tasks.reduce(0) { $0 + $1.elapsedFocus(at: now) }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
