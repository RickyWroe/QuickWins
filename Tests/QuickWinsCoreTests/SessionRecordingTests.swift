import Foundation
import Testing
@testable import QuickWinsCore

@Suite("Session recording")
@MainActor
struct SessionRecordingTests {

    @Test("Pausing records exactly one session for the time worked")
    func pauseRecordsASession() throws {
        let task = Fixture.task("Focus")
        let env = Fixture.coordinator(tasks: [task])

        env.coordinator.start(task.id)
        env.time.advance(by: 1_800)
        env.coordinator.pause(task.id)

        let sessions = try env.history.allSessions()
        #expect(sessions.count == 1)
        #expect(sessions.first?.seconds == 1_800)
        #expect(sessions.first?.taskID == task.id)
        #expect(sessions.first?.wasInterrupted == false)
    }

    @Test("Starting a task records nothing until it stops")
    func startingAloneRecordsNothing() throws {
        let task = Fixture.task("Focus")
        let env = Fixture.coordinator(tasks: [task])

        env.coordinator.start(task.id)
        env.time.advance(by: 600)

        #expect(try env.history.allSessions().isEmpty)
    }

    @Test("Completing a running task records the final stretch")
    func completeRecordsASession() throws {
        let task = Fixture.task("Focus")
        let env = Fixture.coordinator(tasks: [task])

        env.coordinator.start(task.id)
        env.time.advance(by: 900)
        env.coordinator.complete(task.id)

        #expect(try env.history.allSessions().first?.seconds == 900)
    }

    @Test("Skipping a running task still records what was worked")
    func skipRecordsASession() throws {
        let task = Fixture.task("Focus")
        let env = Fixture.coordinator(tasks: [task])

        env.coordinator.start(task.id)
        env.time.advance(by: 450)
        env.coordinator.skip(task.id)

        #expect(try env.history.allSessions().first?.seconds == 450)
    }

    @Test("Switching tasks records the one that stopped, not the one that started")
    func switchingRecordsOnlyTheClosedSession() throws {
        let first = Fixture.task("First", order: 0)
        let second = Fixture.task("Second", order: 1)
        let env = Fixture.coordinator(tasks: [first, second])

        env.coordinator.start(first.id)
        env.time.advance(by: 1_200)
        env.coordinator.start(second.id)

        let sessions = try env.history.allSessions()
        #expect(sessions.count == 1)
        #expect(sessions.first?.taskID == first.id)
        #expect(sessions.first?.seconds == 1_200)
    }

    @Test("Repeated pause and resume produces one record per stretch")
    func repeatedCyclesRecordSeparately() throws {
        let task = Fixture.task("Focus")
        let env = Fixture.coordinator(tasks: [task])

        env.coordinator.start(task.id)
        env.time.advance(by: 300)
        env.coordinator.pause(task.id)

        env.time.advance(by: 600) // paused, not recorded
        env.coordinator.start(task.id)
        env.time.advance(by: 200)
        env.coordinator.pause(task.id)

        let sessions = try env.history.allSessions()
        let recorded: TimeInterval = sessions.reduce(0) { $0 + $1.seconds }
        #expect(sessions.count == 2)
        #expect(recorded == 500)
    }

    @Test("A stale session is recorded up to the heartbeat, not up to now")
    func staleSessionRecordsOnlyToTheHeartbeat() throws {
        let id = UUID()
        var task = Fixture.task("Focus", id: id, status: .active, sessionStartedAt: Fixture.epoch)
        task.lastInteractionAt = Fixture.epoch.addingTimeInterval(300)

        // Two hours of wall clock, but heartbeats stopped after 300 seconds.
        let env = Fixture.coordinator(tasks: [task], at: Fixture.epoch.addingTimeInterval(7_200))

        let sessions = try env.history.allSessions()
        #expect(sessions.count == 1)
        // Crediting the whole gap is exactly what the heartbeat exists to prevent.
        #expect(sessions.first?.seconds == 300)
        #expect(sessions.first?.wasInterrupted == true)
    }

    @Test("Day rollover records the session that was running at midnight")
    func rolloverRecordsTheRunningSession() throws {
        let task = Fixture.task("Overnight")
        let env = Fixture.coordinator(tasks: [task])
        env.coordinator.start(task.id)

        env.time.advance(by: 24 * 60 * 60)
        env.coordinator.applyDayRolloverIfNeeded()

        let sessions = try env.history.allSessions()
        // A stretch spanning midnight is split, so each day is credited separately.
        let distinctDays = Set(sessions.map { $0.day }).count
        let recorded: TimeInterval = sessions.reduce(0) { $0 + $1.seconds }
        let expected: TimeInterval = 24 * 60 * 60
        #expect(sessions.count >= 1)
        #expect(distinctDays == sessions.count)
        #expect(recorded == expected)
    }

    @Test("A failed history write never blocks the task change itself")
    func historyFailureDoesNotBlockTheTask() throws {
        let task = Fixture.task("Focus")
        let env = Fixture.coordinator(tasks: [task])

        env.coordinator.start(task.id)
        env.time.advance(by: 600)
        env.history.errorToThrowOnNextWrite = PersistenceError.saveFailed("disk full")
        env.coordinator.pause(task.id)

        // The pause still happened and the banked time is intact.
        #expect(env.coordinator.tasks.first?.status == .paused)
        #expect(env.coordinator.tasks.first?.accumulatedFocus == 600)
        #expect(try env.history.allSessions().isEmpty)
    }

    @Test("Resetting data clears history along with tasks")
    func resetClearsHistory() throws {
        let task = Fixture.task("Focus")
        let env = Fixture.coordinator(tasks: [task])
        env.coordinator.start(task.id)
        env.time.advance(by: 600)
        env.coordinator.pause(task.id)
        #expect(try env.history.allSessions().count == 1)

        env.coordinator.resetAllData()
        #expect(try env.history.allSessions().isEmpty)
    }

    // MARK: - Backfill

    @Test("Existing focus time is reconstructed once, and flagged as reconstructed")
    func backfillsExistingTasks() throws {
        var task = Fixture.task("Had time before history existed", accumulated: 3_600)
        task.lastInteractionAt = Fixture.epoch
        let env = Fixture.coordinator(tasks: [task])

        let sessions = try env.history.allSessions()
        #expect(sessions.count == 1)
        #expect(sessions.first?.seconds == 3_600)
        #expect(sessions.first?.isBackfilled == true)
        #expect(env.coordinator.settings.historyBackfilledAt != nil)
    }

    @Test("Backfill runs once, not on every launch")
    func backfillIsIdempotent() throws {
        var task = Fixture.task("Existing", accumulated: 1_800)
        task.lastInteractionAt = Fixture.epoch
        let env = Fixture.coordinator(tasks: [task])
        #expect(try env.history.allSessions().count == 1)

        env.coordinator.backfillHistoryIfNeeded()
        env.coordinator.load()

        #expect(try env.history.allSessions().count == 1)
    }

    @Test("Tasks with no recorded focus are not backfilled")
    func backfillSkipsUntouchedTasks() throws {
        let env = Fixture.coordinator(tasks: [Fixture.task("Never started")])
        #expect(try env.history.allSessions().isEmpty)
        #expect(env.coordinator.settings.historyBackfilledAt != nil)
    }

    @Test("Backfilled sessions never claim to know when the work happened")
    func backfilledSessionsExcludedFromPeakHours() throws {
        var task = Fixture.task("Existing", accumulated: 7_200)
        task.lastInteractionAt = Fixture.epoch
        let env = Fixture.coordinator(tasks: [task])

        let stats = StatisticsRules.compute(sessions: try env.history.allSessions(), calendar: Fixture.calendar)
        #expect(stats.totalSeconds == 7_200)
        #expect(stats.secondsByHour.isEmpty)
        #expect(!stats.hasEnoughDataForPeakHour)
    }
}

@Suite("Day marking")
@MainActor
struct DayMarkingTests {

    @Test("A weekend is a day off without anything being stored")
    func weekendNeedsNoStorage() throws {
        let env = Fixture.coordinator()
        let saturday = Fixture.day.adding(days: 4, in: Fixture.calendar)

        #expect(env.coordinator.dayType(for: saturday) == .off)
        #expect(try env.history.dayOverrides().isEmpty)
    }

    @Test("Marking a weekday off stores an override")
    func markingAWeekdayOff() throws {
        let env = Fixture.coordinator()
        env.coordinator.setDayType(.off, for: Fixture.day)

        #expect(env.coordinator.dayType(for: Fixture.day) == .off)
        #expect(try env.history.dayOverrides().count == 1)
    }

    @Test("Marking a day the way the pattern already has it stores nothing")
    func redundantMarksAreNotStored() throws {
        let env = Fixture.coordinator()
        let saturday = Fixture.day.adding(days: 4, in: Fixture.calendar)

        env.coordinator.setDayType(.off, for: saturday)
        #expect(try env.history.dayOverrides().isEmpty)

        env.coordinator.setDayType(.working, for: Fixture.day)
        #expect(try env.history.dayOverrides().isEmpty)
    }

    @Test("Marking a day back to its pattern value removes the override")
    func revertingClearsTheOverride() throws {
        let env = Fixture.coordinator()

        env.coordinator.setDayType(.off, for: Fixture.day)
        #expect(try env.history.dayOverrides().count == 1)

        env.coordinator.setDayType(.working, for: Fixture.day)
        #expect(try env.history.dayOverrides().isEmpty)
        #expect(env.coordinator.dayType(for: Fixture.day) == .working)
    }

    @Test("Day summaries combine recorded focus with the day's type")
    func daySummariesForTheGraph() throws {
        let task = Fixture.task("Focus")
        let env = Fixture.coordinator(tasks: [task])
        env.coordinator.start(task.id)
        env.time.advance(by: 3_600)
        env.coordinator.pause(task.id)

        let saturday = Fixture.day.adding(days: 4, in: Fixture.calendar)
        let summaries = env.coordinator.daySummaries(from: Fixture.day, to: saturday)

        #expect(summaries.count == 5)
        #expect(summaries[Fixture.day]?.focusedSeconds == 3_600)
        #expect(summaries[Fixture.day]?.type == .working)
        #expect(summaries[saturday]?.type == .off)
        #expect(summaries[saturday]?.focusedSeconds == 0)
    }
}
