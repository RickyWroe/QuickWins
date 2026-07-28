import Foundation
import Testing
@testable import QuickWinsCore

@Suite("Task rules")
struct TaskRulesTests {

    // MARK: - Creation

    @Test("A blank title is rejected rather than creating an unnamed task")
    func rejectsBlankTitle() {
        #expect(throws: TaskRuleError.emptyTitle) {
            _ = try TaskRules.normalizedTitle("   \n ")
        }
    }

    @Test("Titles are trimmed and length-capped")
    func normalizesTitle() throws {
        #expect(try TaskRules.normalizedTitle("  Ship the thing  ") == "Ship the thing")
        let long = String(repeating: "a", count: 500)
        #expect(try TaskRules.normalizedTitle(long).count == DailyTask.maxTitleLength)
    }

    @Test("New tasks are appended after the highest existing order")
    func appendsInOrder() throws {
        let existing = [Fixture.task("A", order: 0), Fixture.task("B", order: 4)]
        let created = try TaskRules.makeTask(title: "C", day: Fixture.day, in: existing, at: Fixture.epoch)
        #expect(created.order == 5)
        #expect(created.status == .upcoming)
    }

    @Test("A non-positive estimate is discarded instead of stored as zero")
    func dropsNonPositiveEstimate() throws {
        let created = try TaskRules.makeTask(
            title: "C", day: Fixture.day, estimatedDuration: 0, in: [], at: Fixture.epoch
        )
        #expect(created.estimatedDuration == nil)
    }

    // MARK: - The one-active-task invariant

    @Test("Starting a task pauses whichever task was already running")
    func startingPausesPrevious() throws {
        let first = Fixture.task("First", order: 0)
        let second = Fixture.task("Second", order: 1)
        var tasks = try TaskRules.start(first.id, in: [first, second], at: Fixture.epoch)

        let later = Fixture.epoch.addingTimeInterval(600)
        tasks = try TaskRules.start(second.id, in: tasks, at: later)

        let reloadedFirst = try #require(tasks.first { $0.id == first.id })
        let reloadedSecond = try #require(tasks.first { $0.id == second.id })

        #expect(reloadedFirst.status == .paused)
        #expect(reloadedFirst.sessionStartedAt == nil)
        // The 600 seconds it was running are banked, not lost.
        #expect(reloadedFirst.accumulatedFocus == 600)
        #expect(reloadedSecond.status == .active)
        #expect(reloadedSecond.sessionStartedAt == later)
        #expect(TaskRules.satisfiesSingleActiveInvariant(tasks))
    }

    @Test("Only one task can be active no matter how many starts are issued")
    func neverMoreThanOneActive() throws {
        var tasks = (0..<5).map { Fixture.task("T\($0)", order: $0) }
        for task in tasks {
            tasks = try TaskRules.start(task.id, in: tasks, at: Fixture.epoch)
            #expect(tasks.filter { $0.status == .active }.count == 1)
        }
        #expect(TaskRules.satisfiesSingleActiveInvariant(tasks))
    }

    @Test("A completed task cannot be started")
    func cannotStartCompletedTask() throws {
        let task = Fixture.task("Done", status: .completed)
        #expect(throws: TaskRuleError.invalidTransition(from: .completed, to: .active)) {
            _ = try TaskRules.start(task.id, in: [task], at: Fixture.epoch)
        }
    }

    @Test("Starting an already-active task is a no-op, not a timer reset")
    func startingActiveTaskIsIdempotent() throws {
        let task = Fixture.task("A")
        let started = try TaskRules.start(task.id, in: [task], at: Fixture.epoch)
        let again = try TaskRules.start(task.id, in: started, at: Fixture.epoch.addingTimeInterval(300))
        #expect(again.first?.sessionStartedAt == Fixture.epoch)
    }

    @Test("Acting on a deleted task reports not-found instead of silently succeeding")
    func unknownTaskThrows() {
        let missing = UUID()
        #expect(throws: TaskRuleError.taskNotFound(missing)) {
            _ = try TaskRules.start(missing, in: [], at: Fixture.epoch)
        }
    }

    // MARK: - Pause, complete, skip, restore

    @Test("Pausing banks the running interval and clears the session")
    func pauseBanksTime() throws {
        let task = Fixture.task("A")
        let started = try TaskRules.start(task.id, in: [task], at: Fixture.epoch)
        let paused = try TaskRules.pause(task.id, in: started, at: Fixture.epoch.addingTimeInterval(125))
        let result = try #require(paused.first)
        #expect(result.status == .paused)
        #expect(result.accumulatedFocus == 125)
        #expect(result.sessionStartedAt == nil)
    }

    @Test("Pause and resume cycles accumulate without double counting")
    func pauseResumeAccumulates() throws {
        let task = Fixture.task("A")
        var tasks = try TaskRules.start(task.id, in: [task], at: Fixture.epoch)
        tasks = try TaskRules.pause(task.id, in: tasks, at: Fixture.epoch.addingTimeInterval(100))
        tasks = try TaskRules.start(task.id, in: tasks, at: Fixture.epoch.addingTimeInterval(500))
        tasks = try TaskRules.pause(task.id, in: tasks, at: Fixture.epoch.addingTimeInterval(560))

        let result = try #require(tasks.first)
        // 100 seconds, then 60 seconds. The 400-second gap while paused is excluded.
        #expect(result.accumulatedFocus == 160)
    }

    @Test("Completing a running task banks its final interval")
    func completeBanksTime() throws {
        let task = Fixture.task("A")
        let started = try TaskRules.start(task.id, in: [task], at: Fixture.epoch)
        let done = try TaskRules.complete(task.id, in: started, at: Fixture.epoch.addingTimeInterval(90))
        let result = try #require(done.first)
        #expect(result.status == .completed)
        #expect(result.accumulatedFocus == 90)
        #expect(result.completedAt == Fixture.epoch.addingTimeInterval(90))
        #expect(result.sessionStartedAt == nil)
    }

    @Test("Skipping preserves focus time already spent but sets no completion date")
    func skipPreservesFocus() throws {
        let task = Fixture.task("A")
        let started = try TaskRules.start(task.id, in: [task], at: Fixture.epoch)
        let skipped = try TaskRules.skip(task.id, in: started, at: Fixture.epoch.addingTimeInterval(45))
        let result = try #require(skipped.first)
        #expect(result.status == .skipped)
        #expect(result.accumulatedFocus == 45)
        #expect(result.completedAt == nil)
    }

    @Test("Restoring a completed task with banked time returns it as paused, not upcoming")
    func restoreKeepsProgress() throws {
        let task = Fixture.task("A", status: .completed, accumulated: 300)
        let restored = try TaskRules.restore(task.id, in: [task], at: Fixture.epoch)
        let result = try #require(restored.first)
        #expect(result.status == .paused)
        #expect(result.accumulatedFocus == 300)
        #expect(result.completedAt == nil)
    }

    @Test("Restoring an untouched skipped task returns it as upcoming")
    func restoreUntouchedTask() throws {
        let task = Fixture.task("A", status: .skipped)
        let restored = try TaskRules.restore(task.id, in: [task], at: Fixture.epoch)
        #expect(restored.first?.status == .upcoming)
    }

    // MARK: - Ordering

    @Test("Reordering renumbers the day so order stays dense")
    func reorderRenumbers() throws {
        let tasks = (0..<4).map { Fixture.task("T\($0)", order: $0 * 10) }
        let moved = try TaskRules.reorder(tasks[3].id, to: 0, in: tasks)
        #expect(moved.map(\.title) == ["T3", "T0", "T1", "T2"])
        #expect(moved.map(\.order) == [0, 1, 2, 3])
    }

    @Test("Reordering past the end is refused rather than clamped silently")
    func reorderOutOfRange() {
        let tasks = [Fixture.task("A", order: 0)]
        #expect(throws: TaskRuleError.indexOutOfRange) {
            _ = try TaskRules.reorder(tasks[0].id, to: 7, in: tasks)
        }
    }

    @Test("Display order breaks ties on creation date so it is never ambiguous")
    func displayOrderIsStable() {
        let older = Fixture.task("older", order: 0, createdAt: Fixture.epoch)
        let newer = Fixture.task("newer", order: 0, createdAt: Fixture.epoch.addingTimeInterval(60))
        #expect(TaskRules.sortedForDisplay([newer, older]).map(\.title) == ["older", "newer"])
    }

    // MARK: - Rollover

    @Test("Open tasks left on an earlier day become overdue and bank any running session")
    func rolloverFlagsStaleTasks() throws {
        let yesterday = Fixture.day.adding(days: -1, in: Fixture.calendar)
        let running = Fixture.task(
            "Yesterday", status: .active, day: yesterday, sessionStartedAt: Fixture.epoch.addingTimeInterval(-600)
        )
        let finished = Fixture.task("Finished", status: .completed, day: yesterday)

        let rolled = TaskRules.applyRollover(to: [running, finished], today: Fixture.day, at: Fixture.epoch)
        let rolledRunning = try #require(rolled.first { $0.id == running.id })

        #expect(rolledRunning.status == .overdue)
        #expect(rolledRunning.sessionStartedAt == nil)
        #expect(rolledRunning.accumulatedFocus == 600)
        // A finished task is history; rollover leaves it alone.
        #expect(rolled.first { $0.id == finished.id }?.status == .completed)
    }

    @Test("Today's tasks are untouched by rollover")
    func rolloverIgnoresToday() {
        let task = Fixture.task("Today", status: .upcoming)
        let rolled = TaskRules.applyRollover(to: [task], today: Fixture.day, at: Fixture.epoch)
        #expect(rolled == [task])
    }

    @Test("Moving a running task to another day pauses it first")
    func moveSuspendsRunningTask() throws {
        let task = Fixture.task("A")
        let started = try TaskRules.start(task.id, in: [task], at: Fixture.epoch)
        let tomorrow = Fixture.day.adding(days: 1, in: Fixture.calendar)
        let moved = try TaskRules.move(task.id, to: tomorrow, in: started, at: Fixture.epoch.addingTimeInterval(30))

        let result = try #require(moved.first)
        #expect(result.day == tomorrow)
        #expect(result.status == .paused)
        #expect(result.accumulatedFocus == 30)
    }

    // MARK: - Selection and progress

    @Test("The next task is the following open one in display order")
    func nextTaskFollowsOrder() throws {
        let tasks = [
            Fixture.task("A", order: 0, status: .completed),
            Fixture.task("B", order: 1),
            Fixture.task("C", order: 2),
        ]
        #expect(TaskRules.nextTask(after: tasks[0].id, in: tasks)?.title == "B")
        #expect(TaskRules.nextTask(after: tasks[1].id, in: tasks)?.title == "C")
    }

    @Test("Selection wraps to the first open task once the end is reached")
    func nextTaskWraps() {
        let tasks = [Fixture.task("A", order: 0), Fixture.task("B", order: 1)]
        #expect(TaskRules.nextTask(after: tasks[1].id, in: tasks)?.title == "A")
    }

    @Test("There is no next task when everything is finished")
    func nextTaskEmptyWhenAllDone() {
        let tasks = [Fixture.task("A", order: 0, status: .completed)]
        #expect(TaskRules.nextTask(after: tasks[0].id, in: tasks) == nil)
    }

    @Test("Skipped tasks are excluded from the day's denominator")
    func progressIgnoresSkipped() {
        let tasks = [
            Fixture.task("A", status: .completed),
            Fixture.task("B", status: .skipped),
            Fixture.task("C", status: .upcoming),
        ]
        let progress = TaskRules.progress(in: tasks)
        #expect(progress.completed == 1)
        #expect(progress.total == 2)
    }
}
