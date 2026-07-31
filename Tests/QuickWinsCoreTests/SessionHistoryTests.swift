import CoreData
import Foundation
import Testing
@testable import QuickWinsCore

@Suite("Session records")
struct SessionRecordTests {
    private let taskID = UUID()

    @Test("A normal session becomes exactly one record")
    func singleSession() {
        let records = SessionRules.close(
            taskID: taskID,
            from: Fixture.epoch,
            to: Fixture.epoch.addingTimeInterval(1_800),
            calendar: Fixture.calendar
        )
        #expect(records.count == 1)
        #expect(records.first?.seconds == 1_800)
        #expect(records.first?.day == Fixture.day)
    }

    @Test("A session crossing midnight is split so each day gets its own share")
    func midnightSplit() throws {
        // 23:00 to 01:00 the next morning.
        let calendar = Fixture.calendar
        let start = try #require(calendar.date(bySettingHour: 23, minute: 0, second: 0, of: Fixture.epoch))
        let end = start.addingTimeInterval(2 * 3_600)

        let records = SessionRules.close(taskID: taskID, from: start, to: end, calendar: calendar)

        #expect(records.count == 2)
        #expect(records[0].seconds == 3_600)
        #expect(records[1].seconds == 3_600)
        #expect(records[1].day == records[0].day.adding(days: 1, in: calendar))
        // No time is invented or lost in the split.
        #expect(records.reduce(0) { $0 + $1.seconds } == end.timeIntervalSince(start))
    }

    @Test("A session spanning several days splits into one record per day")
    func multiDaySplit() {
        let start = Fixture.epoch
        let end = Fixture.epoch.addingTimeInterval(3 * 24 * 3_600)
        let records = SessionRules.close(taskID: taskID, from: start, to: end, calendar: Fixture.calendar)

        #expect(records.count >= 3)
        #expect(Set(records.map(\.day)).count == records.count)
        #expect(abs(records.reduce(0) { $0 + $1.seconds } - end.timeIntervalSince(start)) < 0.001)
    }

    @Test("A zero or backwards span records nothing, so a clock change cannot invent focus")
    func nonPositiveSpanIsDropped() {
        #expect(SessionRules.close(taskID: taskID, from: Fixture.epoch, to: Fixture.epoch, calendar: Fixture.calendar).isEmpty)
        #expect(SessionRules.close(
            taskID: taskID,
            from: Fixture.epoch,
            to: Fixture.epoch.addingTimeInterval(-3_600),
            calendar: Fixture.calendar
        ).isEmpty)
    }

    @Test("The interrupted and backfilled flags carry onto every split part")
    func flagsPropagate() throws {
        let calendar = Fixture.calendar
        let start = try #require(calendar.date(bySettingHour: 23, minute: 30, second: 0, of: Fixture.epoch))
        let records = SessionRules.close(
            taskID: taskID,
            from: start,
            to: start.addingTimeInterval(3_600),
            wasInterrupted: true,
            isBackfilled: true,
            calendar: calendar
        )
        let allInterrupted = records.allSatisfy { $0.wasInterrupted }
        let allBackfilled = records.allSatisfy { $0.isBackfilled }
        #expect(records.count == 2)
        #expect(allInterrupted)
        #expect(allBackfilled)
    }

    @Test("An implausibly long stretch is flagged rather than silently trusted")
    func implausibleSessionsAreFlagged() {
        let long = FocusSessionRecord(
            taskID: taskID,
            startedAt: Fixture.epoch,
            endedAt: Fixture.epoch.addingTimeInterval(10 * 3_600),
            seconds: 10 * 3_600,
            day: Fixture.day
        )
        #expect(SessionRules.isImplausible(long))

        let normal = FocusSessionRecord(
            taskID: taskID,
            startedAt: Fixture.epoch,
            endedAt: Fixture.epoch.addingTimeInterval(3_600),
            seconds: 3_600,
            day: Fixture.day
        )
        #expect(!SessionRules.isImplausible(normal))
    }

    @Test("Daily totals sum every session on the day")
    func focusByDay() {
        let other = Fixture.day.adding(days: 1, in: Fixture.calendar)
        let sessions = [
            FocusSessionRecord(taskID: taskID, startedAt: Fixture.epoch, endedAt: Fixture.epoch.addingTimeInterval(600), seconds: 600, day: Fixture.day),
            FocusSessionRecord(taskID: taskID, startedAt: Fixture.epoch, endedAt: Fixture.epoch.addingTimeInterval(900), seconds: 900, day: Fixture.day),
            FocusSessionRecord(taskID: taskID, startedAt: Fixture.epoch, endedAt: Fixture.epoch.addingTimeInterval(300), seconds: 300, day: other),
        ]
        let totals = SessionRules.focusByDay(sessions)
        #expect(totals[Fixture.day] == 1_500)
        #expect(totals[other] == 300)
    }
}

@Suite("History storage")
struct HistoryRepositoryTests {

    private func makeRepository() throws -> (CoreDataHistoryRepository, CoreDataStack) {
        let logger = NullDiagnosticLogger()
        let stack = try CoreDataStack(storage: .temporaryOnDisk, logger: logger)
        return (CoreDataHistoryRepository(stack: stack, logger: logger), stack)
    }

    private func session(_ day: DayKey = Fixture.day, seconds: TimeInterval = 600) -> FocusSessionRecord {
        FocusSessionRecord(
            taskID: UUID(),
            startedAt: Fixture.epoch,
            endedAt: Fixture.epoch.addingTimeInterval(seconds),
            seconds: seconds,
            day: day
        )
    }

    @Test("A session survives a round trip with every field intact")
    func roundTrip() throws {
        let (repository, _) = try makeRepository()
        let original = FocusSessionRecord(
            taskID: UUID(),
            startedAt: Fixture.epoch,
            endedAt: Fixture.epoch.addingTimeInterval(2_058),
            seconds: 2_058,
            day: Fixture.day,
            wasInterrupted: true,
            isBackfilled: true
        )
        try repository.record([original])

        let loaded = try #require(try repository.allSessions().first)
        #expect(loaded.id == original.id)
        #expect(loaded.taskID == original.taskID)
        #expect(loaded.seconds == 2_058)
        #expect(loaded.day == Fixture.day)
        #expect(loaded.wasInterrupted)
        #expect(loaded.isBackfilled)
    }

    @Test("Sessions can be fetched for a date range")
    func rangeQuery() throws {
        let (repository, _) = try makeRepository()
        let calendar = Fixture.calendar
        try repository.record([
            session(Fixture.day.adding(days: -5, in: calendar)),
            session(Fixture.day),
            session(Fixture.day.adding(days: 5, in: calendar)),
        ])

        let window = try repository.sessions(
            from: Fixture.day.adding(days: -1, in: calendar),
            to: Fixture.day.adding(days: 1, in: calendar)
        )
        #expect(window.count == 1)
    }

    @Test("History outlives the tasks that produced it")
    func historyOutlivesTasks() throws {
        let logger = NullDiagnosticLogger()
        let stack = try CoreDataStack(storage: .temporaryOnDisk, logger: logger)
        let tasks = CoreDataTaskRepository(stack: stack, logger: logger)
        let history = CoreDataHistoryRepository(stack: stack, logger: logger)

        let task = Fixture.task("Gone tomorrow")
        try tasks.save([task])
        try history.record([
            FocusSessionRecord(
                taskID: task.id,
                startedAt: Fixture.epoch,
                endedAt: Fixture.epoch.addingTimeInterval(1_200),
                seconds: 1_200,
                day: Fixture.day
            )
        ])

        // "Clear completed" deletes task rows. The contribution graph must not go with them.
        try tasks.delete(ids: [task.id])

        #expect(try tasks.loadAll().isEmpty)
        #expect(try history.allSessions().count == 1)
    }

    @Test("A day override can be set, changed, and removed")
    func dayOverrides() throws {
        let (repository, _) = try makeRepository()

        try repository.setDayOverride(.off, for: Fixture.day)
        var overrides = try repository.dayOverrides()
        #expect(overrides[Fixture.day] == .off)

        try repository.setDayOverride(.working, for: Fixture.day)
        overrides = try repository.dayOverrides()
        #expect(overrides[Fixture.day] == .working)

        try repository.setDayOverride(nil, for: Fixture.day)
        #expect(try repository.dayOverrides().isEmpty)
    }

    @Test("Setting the same day twice does not create a second row")
    func overridesAreUnique() throws {
        let (repository, _) = try makeRepository()
        try repository.setDayOverride(.off, for: Fixture.day)
        try repository.setDayOverride(.off, for: Fixture.day)
        #expect(try repository.dayOverrides().count == 1)
    }

    @Test("A stored duration that disagrees with its timestamps is repaired on read")
    func repairsInconsistentDuration() throws {
        let (repository, stack) = try makeRepository()
        try repository.record([session(seconds: 600)])

        let context = stack.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: MigrationPlan.SessionEntityKey.entityName)
        let object = try #require(try context.fetch(request).first)
        object.setValue(0.0, forKey: MigrationPlan.SessionEntityKey.seconds)
        try context.save()

        #expect(try repository.allSessions().first?.seconds == 600)
    }

    @Test("Resetting all data clears history as well as tasks")
    func resetClearsHistory() throws {
        let logger = NullDiagnosticLogger()
        let stack = try CoreDataStack(storage: .temporaryOnDisk, logger: logger)
        let tasks = CoreDataTaskRepository(stack: stack, logger: logger)
        let history = CoreDataHistoryRepository(stack: stack, logger: logger)

        try tasks.save([Fixture.task("A")])
        try history.record([session()])
        try history.setDayOverride(.off, for: Fixture.day)

        try stack.destroyAllData()

        #expect(try tasks.loadAll().isEmpty)
        #expect(try history.allSessions().isEmpty)
        #expect(try history.dayOverrides().isEmpty)
    }
}
