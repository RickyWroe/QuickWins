import Foundation
import Testing
@testable import QuickWinsCore

@Suite("Task coordinator")
@MainActor
struct CoordinatorTests {

    @Test("Adding a task puts it in today's list and on disk")
    func addPersists() throws {
        let env = Fixture.coordinator()
        let created = try #require(env.coordinator.addTask(title: "  Ship it  "))

        #expect(created.title == "Ship it")
        #expect(env.coordinator.todaysTasks.count == 1)
        #expect(try env.repository.loadAll().count == 1)
    }

    @Test("An empty title surfaces an actionable error and creates nothing")
    func addRejectsEmptyTitle() {
        let env = Fixture.coordinator()
        #expect(env.coordinator.addTask(title: "   ") == nil)
        #expect(env.coordinator.todaysTasks.isEmpty)
        #expect(env.coordinator.lastError != nil)
    }

    @Test("Starting a second task moves the running one aside")
    func onlyOneTaskRunsAtATime() {
        let first = Fixture.task("First", order: 0)
        let second = Fixture.task("Second", order: 1)
        let env = Fixture.coordinator(tasks: [first, second])

        env.coordinator.start(first.id)
        env.time.advance(by: 120)
        env.coordinator.start(second.id)

        #expect(env.coordinator.activeTask?.id == second.id)
        #expect(env.coordinator.tasks.first { $0.id == first.id }?.accumulatedFocus == 120)
        #expect(TaskRules.satisfiesSingleActiveInvariant(env.coordinator.tasks))
    }

    @Test("Completing promotes the next task when that setting is on")
    func autoAdvancesToNextTask() {
        let first = Fixture.task("First", order: 0)
        let second = Fixture.task("Second", order: 1)
        let env = Fixture.coordinator(tasks: [first, second])

        env.coordinator.start(first.id)
        env.time.advance(by: 60)
        env.coordinator.complete(first.id)

        #expect(env.coordinator.activeTask?.id == second.id)
    }

    @Test("Completing leaves nothing running when auto-advance is off")
    func autoAdvanceCanBeDisabled() {
        var settings = AppSettings.default
        settings.automaticallySelectNextTask = false
        let first = Fixture.task("First", order: 0)
        let second = Fixture.task("Second", order: 1)
        let env = Fixture.coordinator(tasks: [first, second], settings: settings)

        env.coordinator.start(first.id)
        env.coordinator.complete(first.id)

        #expect(env.coordinator.activeTask == nil)
        #expect(env.coordinator.tasks.first { $0.id == second.id }?.status == .upcoming)
    }

    @Test("Progress counts completed tasks against the day's total")
    func progressReflectsTheDay() {
        let tasks = (0..<5).map { Fixture.task("T\($0)", order: $0) }
        let env = Fixture.coordinator(tasks: tasks)

        env.coordinator.complete(tasks[0].id)
        env.coordinator.complete(tasks[1].id)

        #expect(env.coordinator.progress.completed == 2)
        #expect(env.coordinator.progress.total == 5)
    }

    // MARK: - Deletion and undo

    @Test("A deleted task can be restored, so deletion needs no confirmation dialog")
    func deleteIsUndoable() {
        let task = Fixture.task("Delete me")
        let env = Fixture.coordinator(tasks: [task])

        env.coordinator.delete(ids: [task.id])
        #expect(env.coordinator.tasks.isEmpty)
        #expect(env.coordinator.canUndoDelete)

        env.coordinator.undoDelete()
        #expect(env.coordinator.tasks.map(\.title) == ["Delete me"])
        #expect(!env.coordinator.canUndoDelete)
    }

    @Test("Clearing completed tasks leaves open ones alone and is still undoable")
    func clearCompletedIsScoped() {
        let done = Fixture.task("Done", order: 0, status: .completed)
        let open = Fixture.task("Open", order: 1)
        let env = Fixture.coordinator(tasks: [done, open])

        env.coordinator.clearCompleted()
        #expect(env.coordinator.tasks.map(\.title) == ["Open"])

        env.coordinator.undoDelete()
        #expect(env.coordinator.tasks.count == 2)
    }

    // MARK: - Failure handling

    @Test("A failed write keeps the change on screen and reports it rather than failing silently")
    func saveFailureIsSurfaced() {
        let env = Fixture.coordinator()
        env.repository.errorToThrowOnNextWrite = PersistenceError.saveFailed("disk full")

        _ = env.coordinator.addTask(title: "Survives in memory")

        #expect(env.coordinator.todaysTasks.count == 1)
        let error = env.coordinator.lastError
        #expect(error != nil)
        #expect(error?.recoverySuggestion != nil)
    }

    @Test("Two tasks stored as active are repaired to one on load")
    func repairsDuplicateActiveTasks() {
        let first = Fixture.task("First", order: 0, status: .active, sessionStartedAt: Fixture.epoch)
        let second = Fixture.task("Second", order: 1, status: .active, sessionStartedAt: Fixture.epoch)
        // The fixture calls load(), which is where the reconciliation happens.
        let env = Fixture.coordinator(tasks: [first, second], at: Fixture.epoch.addingTimeInterval(30))

        #expect(env.coordinator.tasks.filter { $0.status == .active }.count == 1)
        // The demoted task keeps the time it had run rather than losing it.
        #expect(env.coordinator.tasks.contains { $0.status == .paused && $0.accumulatedFocus == 30 })
        #expect(TaskRules.satisfiesSingleActiveInvariant(env.coordinator.tasks))
    }

    // MARK: - Day rollover

    @Test("Crossing midnight flags yesterday's unfinished work as overdue")
    func rolloverAtMidnight() throws {
        let task = Fixture.task("Yesterday", status: .upcoming)
        let env = Fixture.coordinator(tasks: [task])
        #expect(env.coordinator.todaysTasks.count == 1)

        // Move the clock into the next day and tick.
        env.time.advance(by: 24 * 60 * 60)
        env.coordinator.tick()

        #expect(env.coordinator.today == Fixture.day.adding(days: 1, in: Fixture.calendar))
        #expect(env.coordinator.todaysTasks.isEmpty)
        #expect(env.coordinator.overdueTasks.map(\.title) == ["Yesterday"])
    }

    @Test("An overdue task can be pulled into today")
    func overdueTaskCanBeReclaimed() throws {
        let task = Fixture.task("Yesterday")
        let env = Fixture.coordinator(tasks: [task])
        env.time.advance(by: 24 * 60 * 60)
        env.coordinator.tick()

        env.coordinator.moveToToday(task.id)

        #expect(env.coordinator.overdueTasks.isEmpty)
        #expect(env.coordinator.todaysTasks.map(\.title) == ["Yesterday"])
    }

    @Test("A session running across midnight is banked rather than left open")
    func rolloverBanksRunningSession() throws {
        let task = Fixture.task("Overnight")
        let env = Fixture.coordinator(tasks: [task])
        env.coordinator.start(task.id)

        env.time.advance(by: 24 * 60 * 60)
        env.coordinator.applyDayRolloverIfNeeded()

        let rolled = try #require(env.coordinator.tasks.first { $0.id == task.id })
        #expect(rolled.status == .overdue)
        #expect(rolled.sessionStartedAt == nil)
    }

    @Test("Moving a task to tomorrow takes it out of today's list")
    func moveToTomorrow() {
        let task = Fixture.task("Later")
        let env = Fixture.coordinator(tasks: [task])

        env.coordinator.moveToTomorrow(task.id)

        #expect(env.coordinator.todaysTasks.isEmpty)
        #expect(env.coordinator.tasks.first?.day == Fixture.day.adding(days: 1, in: Fixture.calendar))
    }

    // MARK: - Accountability wiring

    @Test("Sustained idle time on a running task produces exactly one notification")
    func idleEscalationNotifiesOnce() async throws {
        let task = Fixture.task("Focus")
        let env = Fixture.coordinator(tasks: [task])
        env.coordinator.start(task.id)

        env.idle.set(320)
        env.time.advance(by: 320)
        env.coordinator.tick()
        // A second tick one second later must not double-post.
        env.time.advance(by: 1)
        env.idle.set(321)
        env.coordinator.tick()

        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(env.notifications.posted.count == 1)
        #expect(env.coordinator.accountability.level == .gentle)
    }

    @Test("No alerts are produced while nothing is running")
    func noAlertsWithoutActiveTask() async throws {
        let env = Fixture.coordinator(tasks: [Fixture.task("Idle")])
        env.idle.set(3_600)
        env.coordinator.tick()

        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(env.notifications.posted.isEmpty)
    }

    @Test("Still working resets escalation and records the acknowledgment")
    func acknowledgementResetsEscalation() {
        let task = Fixture.task("Focus")
        let env = Fixture.coordinator(tasks: [task])
        env.coordinator.start(task.id)

        env.idle.set(1_000)
        env.time.advance(by: 1_000)
        env.coordinator.tick()
        #expect(env.coordinator.accountability.level == .interrupted)

        env.coordinator.acknowledgeStillWorking()

        #expect(env.coordinator.accountability.level == .calm)
        #expect(!env.coordinator.sessionWasInterrupted)
        #expect(env.coordinator.tasks.first?.alertCount == 1)

        // The very next evaluation stays quiet.
        env.time.advance(by: 1)
        env.idle.set(1_001)
        env.coordinator.tick()
        #expect(env.coordinator.accountability.level == .calm)
    }

    @Test("Snoozing keeps the panel calm through a long quiet stretch")
    func snoozeKeepsThingsCalm() {
        let task = Fixture.task("Reading")
        let env = Fixture.coordinator(tasks: [task])
        env.coordinator.start(task.id)
        env.coordinator.snooze(.thirtyMinutes)

        env.idle.set(1_500)
        env.time.advance(by: 1_500)
        env.coordinator.tick()

        #expect(env.coordinator.accountability.level == .calm)
        #expect(env.coordinator.isSnoozed)
    }

    @Test("An unavailable idle source disables escalation instead of assuming absence")
    func unavailableIdleSourceIsSafe() {
        let task = Fixture.task("Focus")
        let env = Fixture.coordinator(tasks: [task])
        env.idle.isAvailable = false
        env.coordinator.start(task.id)

        env.idle.set(9_999)
        env.coordinator.tick()

        #expect(env.coordinator.accountability.level == .calm)
    }

    // MARK: - Settings

    @Test("Settings changes are written through immediately")
    func settingsPersist() {
        let env = Fixture.coordinator()
        env.coordinator.updateSettings { $0.menuBarDisplay = .iconAndTitle }

        #expect(env.settingsStore.load().menuBarDisplay == .iconAndTitle)
        #expect(env.coordinator.settings.menuBarDisplay == .iconAndTitle)
    }

    @Test("Invalid threshold settings are repaired on the way in")
    func settingsAreSanitizedOnWrite() {
        let env = Fixture.coordinator()
        env.coordinator.updateSettings {
            $0.accountability.gentleThreshold = 10
            $0.accountability.subtleThreshold = 600
        }
        let config = env.coordinator.settings.accountability
        #expect(config.subtleThreshold < config.gentleThreshold)
    }

    @Test("Resetting data clears tasks and returns settings to defaults")
    func resetClearsEverything() throws {
        let env = Fixture.coordinator(tasks: [Fixture.task("A")])
        env.coordinator.updateSettings { $0.menuBarDisplay = .iconOnly }

        env.coordinator.resetAllData()

        #expect(env.coordinator.tasks.isEmpty)
        #expect(try env.repository.loadAll().isEmpty)
        #expect(env.coordinator.settings == AppSettings.default)
    }
}
