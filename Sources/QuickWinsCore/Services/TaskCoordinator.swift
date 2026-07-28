import Foundation

public struct DayProgress: Equatable, Sendable {
    public let completed: Int
    public let total: Int
    public let focusedSeconds: TimeInterval

    public var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }
}

public struct UserFacingError: Equatable, Identifiable, Sendable {
    public let id = UUID()
    public let message: String
    /// A concrete next step, or `nil` when the user can only be informed.
    public let recoverySuggestion: String?

    public init(message: String, recoverySuggestion: String? = nil) {
        self.message = message
        self.recoverySuggestion = recoverySuggestion
    }

    public static func == (lhs: UserFacingError, rhs: UserFacingError) -> Bool {
        lhs.message == rhs.message && lhs.recoverySuggestion == rhs.recoverySuggestion
    }
}

/// Orchestrates tasks, the focus timer, and the accountability loop.
///
/// This holds all behaviour that the panel, the menu bar, and notification actions share.
/// It owns no views and no AppKit types, so the full lifecycle — including relaunch recovery,
/// day rollover, and idle escalation — is exercised in tests with injected time and idle values.
@MainActor
public final class TaskCoordinator {
    /// How often a running session writes a heartbeat. Deliberately coarse: elapsed time is
    /// derived from timestamps, so the heartbeat exists only to bound how much focus time an
    /// unclean termination can over-count.
    public static let heartbeatInterval: TimeInterval = 60
    /// A session whose heartbeat is older than this is treated as having ended when the
    /// heartbeat stopped, rather than having run through sleep or a crash.
    public static let staleSessionThreshold: TimeInterval = 150

    // MARK: - Dependencies

    private let repository: TaskRepository
    private let settingsStore: SettingsStoring
    private let time: TimeSource
    private let idleProvider: IdleTimeProviding
    private let notifications: NotificationScheduling
    private let logger: DiagnosticLogging
    private let calendar: Calendar

    // MARK: - Observable state

    public private(set) var tasks: [DailyTask] = []
    public private(set) var settings: AppSettings
    public private(set) var accountability: AccountabilityState = .idle
    public private(set) var today: DayKey
    public private(set) var lastError: UserFacingError?
    public private(set) var notificationAuthorization: NotificationAuthorization = .notDetermined
    /// Set when a session was cut short by an unclean shutdown, sleep, or the idle ceiling.
    public private(set) var sessionWasInterrupted = false

    /// Fired whenever `tasks`, `settings`, or `accountability` change.
    public var onChange: (() -> Void)?
    /// Fired when an escalated alert asks for the panel to be shown.
    public var onSurfacePanel: (() -> Void)?

    private var lastHeartbeatAt: Date?
    private var deletionUndoStack: [[DailyTask]] = []

    public init(
        repository: TaskRepository,
        settingsStore: SettingsStoring,
        time: TimeSource,
        idleProvider: IdleTimeProviding,
        notifications: NotificationScheduling,
        logger: DiagnosticLogging,
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.settingsStore = settingsStore
        self.time = time
        self.idleProvider = idleProvider
        self.notifications = notifications
        self.logger = logger
        self.calendar = calendar
        self.settings = settingsStore.load()
        self.today = DayKey(date: time.now, calendar: calendar)
    }

    // MARK: - Derived state

    public var activeTask: DailyTask? { TaskRules.activeTask(in: tasks) }

    /// The task the panel highlights: the running one, else the most recently paused one.
    public var focusTask: DailyTask? {
        activeTask ?? TaskRules.sortedForDisplay(tasks).first { $0.status == .paused }
    }

    public var todaysTasks: [DailyTask] {
        TaskRules.sortedForDisplay(tasks.filter { $0.day == today })
    }

    public var upcomingTasks: [DailyTask] {
        todaysTasks.filter { $0.status.isOpen && $0.id != focusTask?.id }
    }

    public var completedTasks: [DailyTask] {
        todaysTasks.filter { !$0.status.isOpen }
    }

    public var overdueTasks: [DailyTask] {
        TaskRules.sortedForDisplay(tasks.filter { $0.status == .overdue })
    }

    public var progress: DayProgress {
        let counts = TaskRules.progress(in: todaysTasks)
        return DayProgress(
            completed: counts.completed,
            total: counts.total,
            focusedSeconds: TaskRules.totalFocus(in: todaysTasks, at: time.now)
        )
    }

    public var currentSession: FocusSession? {
        focusTask.map { FocusSession(task: $0, wasInterrupted: sessionWasInterrupted) }
    }

    public var canUndoDelete: Bool { !deletionUndoStack.isEmpty }

    // MARK: - Lifecycle

    public func load() {
        do {
            tasks = try repository.loadAll()
        } catch {
            // The app stays usable with an empty list rather than refusing to open.
            logger.error("coordinator", "Initial load failed: \(error.localizedDescription)")
            report(error, suggestion: "Your tasks could not be read. Existing data has been left untouched.")
            tasks = []
        }
        settings = settingsStore.load()
        // Per-row normalization in the repository cannot see across rows, so a store holding two
        // active tasks — from an interrupted write or an older build — is reconciled here.
        repairSingleActiveInvariant()
        applyDayRolloverIfNeeded()
        restoreInterruptedSessionIfNeeded()
        accountability = AccountabilityEngine.reset(for: activeTask?.id)
        notifyChange()
    }

    public func refreshNotificationAuthorization() async {
        notificationAuthorization = await notifications.currentAuthorization()
        notifyChange()
    }

    public func requestNotificationAuthorization() async {
        notificationAuthorization = await notifications.requestAuthorization()
        if notificationAuthorization == .denied {
            logger.notice("notifications", "Authorization denied; accountability alerts will be panel-only.")
        }
        notifyChange()
    }

    /// Re-evaluates a session that may have spanned a crash, a force quit, or system sleep.
    ///
    /// Wall-clock arithmetic alone would credit that whole gap as focus time. The heartbeat
    /// bounds it: anything past the last heartbeat is discarded and the session is flagged.
    public func restoreInterruptedSessionIfNeeded() {
        guard let active = activeTask, let startedAt = active.sessionStartedAt else { return }
        let now = time.now
        let heartbeat = max(active.lastInteractionAt, startedAt)
        let gap = now.timeIntervalSince(heartbeat)
        guard gap > Self.staleSessionThreshold else { return }

        var updated = active
        updated.accumulatedFocus = max(0, updated.accumulatedFocus + max(0, heartbeat.timeIntervalSince(startedAt)))
        updated.sessionStartedAt = nil
        updated.status = .paused
        updated.lastInteractionAt = now
        sessionWasInterrupted = true

        logger.notice(
            "timer",
            "Session for task \(updated.id.uuidString) had a \(Int(gap))s heartbeat gap; banked \(Int(updated.accumulatedFocus))s and paused."
        )
        apply(replacing: [updated])
    }

    // MARK: - Task commands

    @discardableResult
    public func addTask(title: String, notes: String? = nil, estimatedDuration: TimeInterval? = nil) -> DailyTask? {
        do {
            let task = try TaskRules.makeTask(
                title: title,
                notes: notes,
                day: today,
                estimatedDuration: estimatedDuration,
                in: todaysTasks,
                at: time.now
            )
            apply(replacing: [task])
            return task
        } catch {
            report(error, suggestion: nil)
            return nil
        }
    }

    public func updateTask(id: UUID, title: String? = nil, notes: String?? = nil, estimatedDuration: TimeInterval?? = nil) {
        guard var task = tasks.first(where: { $0.id == id }) else { return }
        do {
            if let title { task.title = try TaskRules.normalizedTitle(title) }
            if let notes { task.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            if let estimatedDuration { task.estimatedDuration = estimatedDuration.flatMap { $0 > 0 ? $0 : nil } }
            task.lastInteractionAt = time.now
            apply(replacing: [task])
        } catch {
            report(error, suggestion: nil)
        }
    }

    public func setIdleDetection(_ enabled: Bool, for id: UUID) {
        guard var task = tasks.first(where: { $0.id == id }) else { return }
        task.idleDetectionEnabled = enabled
        task.lastInteractionAt = time.now
        apply(replacing: [task])
    }

    public func start(_ id: UUID) {
        mutateDay { try TaskRules.start(id, in: $0, at: self.time.now) }
        sessionWasInterrupted = false
        accountability = AccountabilityEngine.reset(for: id, preservingSnoozeFrom: accountability)
        lastHeartbeatAt = time.now
    }

    public func pause(_ id: UUID) {
        mutateDay { try TaskRules.pause(id, in: $0, at: self.time.now) }
        accountability = AccountabilityEngine.reset(for: id, preservingSnoozeFrom: accountability)
    }

    public func toggleActive() {
        guard let task = focusTask else { return }
        if task.status == .active { pause(task.id) } else { start(task.id) }
    }

    public func complete(_ id: UUID) {
        mutateDay { try TaskRules.complete(id, in: $0, at: self.time.now) }
        sessionWasInterrupted = false
        accountability = AccountabilityEngine.reset(for: nil, preservingSnoozeFrom: accountability)
        Task { await notifications.removeDeliveredAlerts() }

        if settings.automaticallySelectNextTask, let next = TaskRules.nextTask(after: id, in: todaysTasks) {
            start(next.id)
        }
    }

    public func skip(_ id: UUID) {
        mutateDay { try TaskRules.skip(id, in: $0, at: self.time.now) }
        accountability = AccountabilityEngine.reset(for: nil, preservingSnoozeFrom: accountability)
    }

    public func restore(_ id: UUID) {
        mutateDay { try TaskRules.restore(id, in: $0, at: self.time.now) }
    }

    public func reorder(_ id: UUID, to destination: Int) {
        guard let dayOfTask = tasks.first(where: { $0.id == id })?.day else { return }
        let scoped = TaskRules.sortedForDisplay(tasks.filter { $0.day == dayOfTask })
        do {
            let reordered = try TaskRules.reorder(id, to: destination, in: scoped)
            apply(replacing: reordered)
        } catch {
            report(error, suggestion: nil)
        }
    }

    public func moveToTomorrow(_ id: UUID) {
        let tomorrow = today.adding(days: 1, in: calendar)
        mutateDay { try TaskRules.move(id, to: tomorrow, in: $0, at: self.time.now) }
    }

    public func moveToToday(_ id: UUID) {
        mutateDay { try TaskRules.move(id, to: self.today, in: $0, at: self.time.now) }
    }

    /// Deletes tasks and keeps them for `undoDelete`, so no confirmation dialog is needed.
    public func delete(ids: [UUID]) {
        let removed = tasks.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        do {
            try repository.delete(ids: ids)
            tasks.removeAll { ids.contains($0.id) }
            deletionUndoStack.append(removed)
            if deletionUndoStack.count > 10 { deletionUndoStack.removeFirst() }
            notifyChange()
        } catch {
            report(error, suggestion: "The task was not deleted. Try again.")
        }
    }

    public func undoDelete() {
        guard let restored = deletionUndoStack.popLast() else { return }
        apply(replacing: restored)
    }

    public func clearCompleted() {
        let ids = todaysTasks.filter { $0.status == .completed }.map(\.id)
        delete(ids: ids)
    }

    // MARK: - Accountability commands

    public func acknowledgeStillWorking() {
        accountability = AccountabilityEngine.acknowledge(
            state: accountability,
            config: settings.accountability,
            at: time.now
        )
        sessionWasInterrupted = false
        touchActiveTask()
        Task { await notifications.removeDeliveredAlerts() }
        logger.info("accountability", "User acknowledged; grace period started.")
        notifyChange()
    }

    public func snooze(_ duration: SnoozeDuration) {
        accountability = AccountabilityEngine.snooze(state: accountability, duration: duration, at: time.now)
        Task { await notifications.removeDeliveredAlerts() }
        logger.info("accountability", "Alerts snoozed for \(duration.label).")
        notifyChange()
    }

    public func clearSnooze() {
        accountability = AccountabilityEngine.clearSnooze(state: accountability)
        notifyChange()
    }

    public var isSnoozed: Bool { accountability.isSnoozed(at: time.now) }

    // MARK: - Settings

    public func updateSettings(_ transform: (inout AppSettings) -> Void) {
        var updated = settings
        transform(&updated)
        settings = updated.sanitized()
        settingsStore.save(settings)
        notifyChange()
    }

    public func resetAllData() {
        do {
            try repository.deleteAll()
            settingsStore.reset()
            tasks = []
            settings = settingsStore.load()
            accountability = .idle
            deletionUndoStack.removeAll()
            logger.notice("coordinator", "All local data reset by user request.")
            notifyChange()
        } catch {
            report(error, suggestion: "Some data could not be removed.")
        }
    }

    // MARK: - Tick

    /// Called once per second by the UI ticker while the panel or menu bar needs updating.
    ///
    /// Cheap by construction: it only writes on a day change, on the once-a-minute heartbeat,
    /// or when accountability state actually moves.
    public func tick() {
        applyDayRolloverIfNeeded()
        writeHeartbeatIfDue()
        evaluateAccountability()
    }

    private func writeHeartbeatIfDue() {
        guard var active = activeTask else {
            lastHeartbeatAt = nil
            return
        }
        let now = time.now
        if let last = lastHeartbeatAt, now.timeIntervalSince(last) < Self.heartbeatInterval { return }
        lastHeartbeatAt = now
        active.lastInteractionAt = now
        persist([active])
        // Kept out of `tasks` reload to avoid a full-list churn every minute.
        if let index = tasks.firstIndex(where: { $0.id == active.id }) {
            tasks[index] = active
        }
    }

    private func evaluateAccountability() {
        guard idleProvider.isAvailable else { return }
        let context: AccountabilityContext
        if let active = activeTask {
            context = AccountabilityContext(
                activeTaskID: active.id,
                activeTaskTitle: active.title,
                isRunning: true,
                idleDetectionEnabled: active.idleDetectionEnabled && active.remindersEnabled
            )
        } else {
            context = .inactive
        }

        let (newState, effects) = AccountabilityEngine.evaluate(
            state: accountability,
            context: context,
            idleSeconds: idleProvider.idleSeconds(),
            config: settings.accountability,
            now: time.now,
            calendar: calendar
        )

        let stateChanged = newState != accountability
        accountability = newState
        for effect in effects { perform(effect) }
        if stateChanged || !effects.isEmpty { notifyChange() }
    }

    private func perform(_ effect: AccountabilityEffect) {
        switch effect {
        case .updateIndicator:
            break // The indicator reads `accountability.level` directly.
        case .notify(let alert):
            Task { [notifications, logger] in
                do {
                    try await notifications.post(alert)
                } catch {
                    logger.error("notifications", "Alert delivery failed: \(error.localizedDescription)")
                }
            }
        case .surfacePanel:
            onSurfacePanel?()
        case .markSessionInterrupted(let taskID):
            sessionWasInterrupted = true
            logger.notice("accountability", "Session for task \(taskID.uuidString) marked interrupted.")
        }
    }

    /// Detects a date change and flags anything left open on an earlier day.
    public func applyDayRolloverIfNeeded() {
        let current = DayKey(date: time.now, calendar: calendar)
        guard current != today else { return }
        logger.info("coordinator", "Day changed from \(today) to \(current).")
        today = current
        let rolled = TaskRules.applyRollover(to: tasks, today: current, at: time.now)
        let changed = zip(tasks, rolled).filter { $0 != $1 }.map(\.1)
        if !changed.isEmpty {
            apply(replacing: changed)
        } else {
            notifyChange()
        }
    }

    // MARK: - Plumbing

    /// Applies a `TaskRules` transformation to the whole working set as one transaction.
    private func mutateDay(_ transform: ([DailyTask]) throws -> [DailyTask]) {
        do {
            let updated = try transform(tasks)
            let changed = updated.filter { candidate in
                guard let original = tasks.first(where: { $0.id == candidate.id }) else { return true }
                return original != candidate
            }
            guard !changed.isEmpty else { return }
            apply(replacing: changed)
        } catch {
            report(error, suggestion: nil)
        }
    }

    private func apply(replacing changed: [DailyTask]) {
        persist(changed)
        for task in changed {
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = task
            } else {
                tasks.append(task)
            }
        }
        repairSingleActiveInvariant()
        notifyChange()
    }

    private func persist(_ changed: [DailyTask]) {
        do {
            try repository.save(changed)
        } catch {
            // The in-memory state stays correct so the user does not lose their place; the next
            // successful write reconciles it.
            report(error, suggestion: "Your change is applied but was not written to disk.")
        }
    }

    private func touchActiveTask() {
        guard var active = activeTask else { return }
        active.lastInteractionAt = time.now
        active.alertCount += 1
        apply(replacing: [active])
    }

    private func repairSingleActiveInvariant() {
        guard !TaskRules.satisfiesSingleActiveInvariant(tasks) else { return }
        // Reaching here means a transition produced an impossible state. Repair rather than
        // trap, and leave a trail: a stuck timer is recoverable, a crash loop is not.
        logger.error("coordinator", "Single-active invariant violated; repairing.")
        var seenActive = false
        let repaired: [DailyTask] = tasks.map { task in
            var copy = task
            if copy.status == .active {
                if seenActive {
                    copy.status = .paused
                    if let start = copy.sessionStartedAt {
                        copy.accumulatedFocus += max(0, time.now.timeIntervalSince(start))
                        copy.sessionStartedAt = nil
                    }
                } else {
                    seenActive = true
                }
            }
            return copy.normalized()
        }
        tasks = repaired
        persist(repaired)
    }

    private func report(_ error: Error, suggestion: String?) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        logger.error("coordinator", message)
        lastError = UserFacingError(message: message, recoverySuggestion: suggestion)
        notifyChange()
    }

    public func clearError() {
        lastError = nil
        notifyChange()
    }

    private func notifyChange() {
        onChange?()
    }
}
