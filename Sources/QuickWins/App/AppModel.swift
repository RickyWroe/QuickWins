import AppKit
import Combine
import QuickWinsCore
import SwiftUI

/// SwiftUI-facing wrapper around `TaskCoordinator`.
///
/// The coordinator holds the behaviour and stays free of SwiftUI; this object republishes its
/// changes, owns the once-a-second display tick, and carries the small amount of state that is
/// genuinely presentational — keyboard selection and which sheet is open.
@MainActor
final class AppModel: ObservableObject {
    let environment: AppEnvironment

    /// Bumped whenever the coordinator reports a change, invalidating dependent views.
    @Published private(set) var revision = 0
    /// Drives elapsed-time labels. Only updated while something is actually running.
    @Published private(set) var now: Date
    @Published var selectedTaskID: UUID?
    @Published var editingTask: DailyTask?
    @Published var isQuickAddFocused = false
    /// Suppresses click-outside dismissal while a sheet owns the interaction.
    @Published var isEditingModally = false
    @Published var showStorageWarning: Bool

    private var coordinator: TaskCoordinator { environment.coordinator }
    private let ticker: TickScheduling
    private var tickingReason: Set<TickReason> = []

    private enum TickReason: Hashable {
        case runningTask
        case panelVisible
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        self.ticker = environment.ticker
        self.now = environment.time.now
        self.showStorageWarning = environment.storeWasRecovered || environment.isUsingFallbackStorage

        coordinator.onChange = { [weak self] in
            guard let self else { return }
            self.revision &+= 1
            self.syncTicker()
        }
    }

    // MARK: - Pass-through state

    var tasks: [DailyTask] { coordinator.todaysTasks }
    var focusTask: DailyTask? { coordinator.focusTask }
    var activeTask: DailyTask? { coordinator.activeTask }
    var upcoming: [DailyTask] { coordinator.upcomingTasks }
    var completed: [DailyTask] { coordinator.completedTasks }
    var overdue: [DailyTask] { coordinator.overdueTasks }
    var progress: DayProgress { coordinator.progress }
    var session: FocusSession? { coordinator.currentSession }
    var settings: AppSettings { coordinator.settings }
    var accountabilityLevel: AccountabilityLevel { coordinator.accountability.level }
    var isSnoozed: Bool { coordinator.isSnoozed }
    var lastError: UserFacingError? { coordinator.lastError }
    var canUndoDelete: Bool { coordinator.canUndoDelete }
    var notificationAuthorization: NotificationAuthorization { coordinator.notificationAuthorization }
    var sessionWasInterrupted: Bool { coordinator.sessionWasInterrupted }

    /// The row the keyboard is on, defaulting to the focus task so arrow keys always have an anchor.
    var selectionTarget: DailyTask? {
        if let selectedTaskID, let match = tasks.first(where: { $0.id == selectedTaskID }) { return match }
        return focusTask ?? tasks.first
    }

    // MARK: - Lifecycle

    func start() {
        coordinator.load()
        selectedTaskID = focusTask?.id
        syncTicker()
        Task { await coordinator.refreshNotificationAuthorization() }
    }

    func panelDidAppear() {
        tickingReason.insert(.panelVisible)
        syncTicker()
    }

    func panelDidDisappear() {
        tickingReason.remove(.panelVisible)
        isQuickAddFocused = false
        syncTicker()
    }

    /// Called when the machine wakes; a long sleep may have invalidated the running session.
    func systemDidWake() {
        coordinator.restoreInterruptedSessionIfNeeded()
        coordinator.applyDayRolloverIfNeeded()
        now = environment.time.now
    }

    /// Runs the timer only when something on screen or on the clock depends on it, so an idle
    /// app costs nothing.
    private func syncTicker() {
        if activeTask != nil {
            tickingReason.insert(.runningTask)
        } else {
            tickingReason.remove(.runningTask)
        }

        if tickingReason.isEmpty {
            ticker.stop()
        } else if !ticker.isRunning {
            ticker.start(interval: 1) { [weak self] in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
    }

    private func tick() {
        now = environment.time.now
        coordinator.tick()
    }

    // MARK: - Commands

    func addTask(title: String, estimatedDuration: TimeInterval? = nil) {
        guard let created = coordinator.addTask(title: title, estimatedDuration: estimatedDuration) else { return }
        selectedTaskID = created.id
    }

    func start(_ id: UUID) { coordinator.start(id) }
    func pause(_ id: UUID) { coordinator.pause(id) }
    func toggleActive() { coordinator.toggleActive() }
    func skip(_ id: UUID) { coordinator.skip(id) }
    func restore(_ id: UUID) { coordinator.restore(id) }
    func moveToTomorrow(_ id: UUID) { coordinator.moveToTomorrow(id) }
    func moveToToday(_ id: UUID) { coordinator.moveToToday(id) }
    func clearCompleted() { coordinator.clearCompleted() }
    func undoDelete() { coordinator.undoDelete() }
    func acknowledgeStillWorking() { coordinator.acknowledgeStillWorking() }
    func snooze(_ duration: SnoozeDuration) { coordinator.snooze(duration) }
    func clearSnooze() { coordinator.clearSnooze() }
    func clearError() { coordinator.clearError() }
    func resetAllData() { coordinator.resetAllData() }
    func setIdleDetection(_ enabled: Bool, for id: UUID) { coordinator.setIdleDetection(enabled, for: id) }

    func complete(_ id: UUID) {
        let wasSelected = selectedTaskID == id
        coordinator.complete(id)
        if wasSelected { selectedTaskID = focusTask?.id ?? tasks.first?.id }
    }

    func delete(_ id: UUID) {
        if selectedTaskID == id {
            let ordered = tasks
            let index = ordered.firstIndex { $0.id == id }
            selectedTaskID = index.flatMap { ordered.indices.contains($0 + 1) ? ordered[$0 + 1].id : ordered.last(where: { $0.id != id })?.id }
        }
        coordinator.delete(ids: [id])
    }

    func update(_ id: UUID, title: String, notes: String?, estimatedDuration: TimeInterval?) {
        coordinator.updateTask(id: id, title: title, notes: .some(notes), estimatedDuration: .some(estimatedDuration))
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let ordered = tasks
        guard let first = source.first, ordered.indices.contains(first) else { return }
        let target = destination > first ? destination - 1 : destination
        coordinator.reorder(ordered[first].id, to: min(max(0, target), ordered.count - 1))
    }

    func updateSettings(_ transform: (inout AppSettings) -> Void) {
        coordinator.updateSettings(transform)
    }

    func requestNotificationAuthorization() {
        Task { await coordinator.requestNotificationAuthorization() }
    }

    // MARK: - Keyboard selection

    func moveSelection(by offset: Int) {
        let ordered = tasks
        guard !ordered.isEmpty else { return }
        let currentIndex = selectionTarget.flatMap { target in ordered.firstIndex { $0.id == target.id } } ?? 0
        let next = min(max(0, currentIndex + offset), ordered.count - 1)
        selectedTaskID = ordered[next].id
    }

    func startSelected() {
        guard let target = selectionTarget, target.status.isOpen else { return }
        start(target.id)
    }

    func completeActive() {
        guard let task = activeTask ?? focusTask else { return }
        complete(task.id)
    }

    func deleteSelected() {
        guard let target = selectionTarget else { return }
        delete(target.id)
    }

    // MARK: - Diagnostics

    func exportDiagnostics(to url: URL) throws {
        try environment.logger.exportText().write(to: url, atomically: true, encoding: .utf8)
    }
}
