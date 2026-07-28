import CoreData
import Foundation
import Testing
@testable import QuickWinsCore

@Suite("Core Data repository")
struct RepositoryTests {

    /// A real SQLite store in a temp directory: uniqueness constraints and type coercion behave
    /// differently in the in-memory store, and those are exactly what these tests cover.
    private func makeRepository() throws -> (CoreDataTaskRepository, CoreDataStack) {
        let logger = NullDiagnosticLogger()
        let stack = try CoreDataStack(storage: .temporaryOnDisk, logger: logger)
        return (CoreDataTaskRepository(stack: stack, logger: logger), stack)
    }

    @Test("A task survives a round trip with every field intact")
    func roundTripsAllFields() throws {
        let (repository, _) = try makeRepository()
        let id = UUID()
        let original = DailyTask(
            id: id,
            title: "Build landing page",
            notes: "Hero section first",
            createdAt: Fixture.epoch,
            day: Fixture.day,
            order: 3,
            estimatedDuration: 5_400,
            accumulatedFocus: 2_058,
            sessionStartedAt: Fixture.epoch.addingTimeInterval(60),
            completedAt: nil,
            status: .active,
            remindersEnabled: false,
            idleDetectionEnabled: false,
            alertCount: 2,
            lastInteractionAt: Fixture.epoch.addingTimeInterval(120)
        )
        try repository.save([original])

        let loaded = try #require(try repository.task(id: id))
        #expect(loaded.title == original.title)
        #expect(loaded.notes == original.notes)
        #expect(loaded.day == original.day)
        #expect(loaded.order == 3)
        #expect(loaded.estimatedDuration == 5_400)
        #expect(loaded.accumulatedFocus == 2_058)
        #expect(loaded.sessionStartedAt == original.sessionStartedAt)
        #expect(loaded.status == .active)
        #expect(loaded.remindersEnabled == false)
        #expect(loaded.idleDetectionEnabled == false)
        #expect(loaded.alertCount == 2)
    }

    @Test("Saving the same identifier twice updates the row instead of duplicating it")
    func saveIsAnUpsert() throws {
        let (repository, _) = try makeRepository()
        let id = UUID()
        try repository.save([Fixture.task("First", id: id)])

        var updated = Fixture.task("Second", id: id)
        updated.order = 9
        try repository.save([updated])

        let all = try repository.loadAll()
        #expect(all.count == 1)
        #expect(all.first?.title == "Second")
        #expect(all.first?.order == 9)
    }

    @Test("A whole-day switch of the active task is stored as one consistent set")
    func multiRowWriteIsAtomicallyConsistent() throws {
        let (repository, _) = try makeRepository()
        let first = Fixture.task("First", order: 0)
        let second = Fixture.task("Second", order: 1)
        try repository.save([first, second])

        var tasks = try TaskRules.start(first.id, in: [first, second], at: Fixture.epoch)
        tasks = try TaskRules.start(second.id, in: tasks, at: Fixture.epoch.addingTimeInterval(300))
        try repository.save(tasks)

        let reloaded = try repository.loadAll()
        #expect(reloaded.filter { $0.status == .active }.count == 1)
        #expect(TaskRules.satisfiesSingleActiveInvariant(reloaded))
    }

    @Test("Tasks can be fetched for one day without loading the rest")
    func filtersByDay() throws {
        let (repository, _) = try makeRepository()
        let tomorrow = Fixture.day.adding(days: 1, in: Fixture.calendar)
        try repository.save([
            Fixture.task("Today", day: Fixture.day),
            Fixture.task("Tomorrow", day: tomorrow),
        ])

        #expect(try repository.tasks(on: Fixture.day).map(\.title) == ["Today"])
        #expect(try repository.tasks(on: tomorrow).map(\.title) == ["Tomorrow"])
    }

    @Test("Results come back in manual order, and that order is preserved across reloads")
    func preservesManualOrder() throws {
        let (repository, _) = try makeRepository()
        let tasks = (0..<5).map { Fixture.task("T\($0)", order: $0) }
        try repository.save(tasks)

        let reordered = try TaskRules.reorder(tasks[4].id, to: 0, in: tasks)
        try repository.save(reordered)

        #expect(try repository.loadAll().map(\.title) == ["T4", "T0", "T1", "T2", "T3"])
    }

    @Test("Deleting removes only the requested rows")
    func deletesSelectively() throws {
        let (repository, _) = try makeRepository()
        let keep = Fixture.task("Keep", order: 0)
        let drop = Fixture.task("Drop", order: 1)
        try repository.save([keep, drop])

        try repository.delete(ids: [drop.id])
        #expect(try repository.loadAll().map(\.title) == ["Keep"])
    }

    @Test("Resetting data empties the store")
    func deleteAllEmptiesStore() throws {
        let (repository, _) = try makeRepository()
        try repository.save((0..<3).map { Fixture.task("T\($0)", order: $0) })
        try repository.deleteAll()
        #expect(try repository.loadAll().isEmpty)
    }

    // MARK: - Defensive reads

    @Test("A negative stored duration is repaired on read rather than shown as negative time")
    func repairsNegativeDuration() throws {
        let (repository, stack) = try makeRepository()
        let id = UUID()
        try repository.save([Fixture.task("A", id: id)])

        // Simulate a bad write reaching the store.
        let context = stack.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: MigrationPlan.TaskEntityKey.entityName)
        let object = try #require(try context.fetch(request).first)
        object.setValue(-500.0, forKey: MigrationPlan.TaskEntityKey.accumulatedFocus)
        try context.save()

        let loaded = try #require(try repository.task(id: id))
        #expect(loaded.accumulatedFocus == 0)
    }

    @Test("An unrecognised status falls back to upcoming instead of failing the load")
    func repairsUnknownStatus() throws {
        let (repository, stack) = try makeRepository()
        let id = UUID()
        try repository.save([Fixture.task("A", id: id)])

        let context = stack.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: MigrationPlan.TaskEntityKey.entityName)
        let object = try #require(try context.fetch(request).first)
        object.setValue("teleported", forKey: MigrationPlan.TaskEntityKey.statusRaw)
        try context.save()

        #expect(try repository.task(id: id)?.status == .upcoming)
    }

    @Test("A nonsense day value falls back to the creation date's day")
    func repairsCorruptDayKey() throws {
        let (repository, stack) = try makeRepository()
        let id = UUID()
        try repository.save([Fixture.task("A", id: id)])

        let context = stack.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: MigrationPlan.TaskEntityKey.entityName)
        let object = try #require(try context.fetch(request).first)
        object.setValue(99_999_999, forKey: MigrationPlan.TaskEntityKey.dayPacked)
        try context.save()

        let loaded = try #require(try repository.task(id: id))
        #expect(loaded.day == DayKey(date: Fixture.epoch))
    }

    @Test("A stored session on a non-active task is banked rather than left dangling")
    func banksOrphanedSession() throws {
        let (repository, _) = try makeRepository()
        let id = UUID()
        var task = Fixture.task("A", id: id, status: .paused)
        task.sessionStartedAt = Fixture.epoch
        task.lastInteractionAt = Fixture.epoch.addingTimeInterval(240)
        try repository.save([task])

        let loaded = try #require(try repository.task(id: id))
        #expect(loaded.sessionStartedAt == nil)
        #expect(loaded.accumulatedFocus == 240)
    }

    @Test("An empty title is replaced so the row is still renderable")
    func repairsEmptyTitle() throws {
        let (repository, _) = try makeRepository()
        let id = UUID()
        try repository.save([Fixture.task("   ", id: id)])
        #expect(try repository.task(id: id)?.title == "Untitled task")
    }

    // MARK: - Stack

    @Test("A fresh store is stamped with the current schema version")
    func stampsSchemaVersion() throws {
        let (_, stack) = try makeRepository()
        let store = try #require(stack.container.persistentStoreCoordinator.persistentStores.first)
        #expect(store.metadata?[MigrationPlan.versionMetadataKey] as? Int == SchemaVersion.current.rawValue)
    }

    @Test("An unreadable store file is quarantined and the app still opens")
    func recoversFromCorruptStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickWinsCorrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("QuickWins.sqlite")
        try Data("this is not a database".utf8).write(to: url)

        let stack = try CoreDataStack(storage: .onDisk(url), logger: NullDiagnosticLogger())
        #expect(stack.recoveredFromCorruptStore)
        #expect(stack.quarantinedStoreURL != nil)

        // The recreated store is usable.
        let repository = CoreDataTaskRepository(stack: stack, logger: NullDiagnosticLogger())
        try repository.save([Fixture.task("After recovery")])
        #expect(try repository.loadAll().count == 1)

        // The bad file is kept for inspection rather than deleted.
        let quarantined = try #require(stack.quarantinedStoreURL)
        #expect(FileManager.default.fileExists(atPath: quarantined.path))

        try? FileManager.default.removeItem(at: directory)
    }
}
