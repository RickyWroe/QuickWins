import CoreData
import Foundation
import Testing
@testable import QuickWinsCore

@Suite("Schema migration")
struct MigrationTests {

    /// Writes a store using the v1 model, exactly as a build before colours existed would have.
    private func makeV1Store(at url: URL, taskID: UUID, title: String) throws {
        let container = NSPersistentContainer(name: "QuickWins", managedObjectModel: MigrationPlan.model(for: .v1))
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        let context = container.viewContext
        let key = MigrationPlan.TaskEntityKey.self
        let object = NSEntityDescription.insertNewObject(forEntityName: key.entityName, into: context)
        object.setValue(taskID, forKey: key.id)
        object.setValue(title, forKey: key.title)
        object.setValue(Fixture.epoch, forKey: key.createdAt)
        object.setValue(Fixture.day.packed, forKey: key.dayPacked)
        object.setValue(2, forKey: key.order)
        object.setValue(1_234.0, forKey: key.accumulatedFocus)
        object.setValue(TaskStatus.paused.rawValue, forKey: key.statusRaw)
        object.setValue(true, forKey: key.remindersEnabled)
        object.setValue(true, forKey: key.idleDetectionEnabled)
        object.setValue(0, forKey: key.alertCount)
        object.setValue(Fixture.epoch, forKey: key.lastInteractionAt)
        try context.save()

        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }

    @Test("A v1 store opens under v2 with its tasks intact and no data loss")
    func migratesV1StoreInPlace() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickWinsMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("QuickWins.sqlite")
        let id = UUID()
        try makeV1Store(at: url, taskID: id, title: "Written before colours existed")

        // Opening with the current model must migrate rather than quarantine.
        let logger = NullDiagnosticLogger()
        let stack = try CoreDataStack(storage: .onDisk(url), logger: logger)
        #expect(!stack.recoveredFromCorruptStore, "Migration fell back to quarantine — existing tasks would be lost")

        let repository = CoreDataTaskRepository(stack: stack, logger: logger)
        let task = try #require(try repository.task(id: id))

        #expect(task.title == "Written before colours existed")
        #expect(task.accumulatedFocus == 1_234)
        #expect(task.order == 2)
        #expect(task.status == .paused)
        #expect(task.color == .fallback)
    }

    @Test("The migrated store is restamped to the current schema version, and it sticks")
    func migrationUpdatesTheVersionStamp() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickWinsMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("QuickWins.sqlite")
        try makeV1Store(at: url, taskID: UUID(), title: "A")

        let logger = NullDiagnosticLogger()
        let stack = try CoreDataStack(storage: .onDisk(url), logger: logger)
        let store = try #require(stack.container.persistentStoreCoordinator.persistentStores.first)
        #expect(store.metadata?[MigrationPlan.versionMetadataKey] as? Int == SchemaVersion.current.rawValue)

        // Core Data flushes store metadata with the next save, so the stamp lands as soon as
        // anything is written — which on a real launch is the first task change.
        try CoreDataTaskRepository(stack: stack, logger: logger).save([Fixture.task("Anything")])

        for open in stack.container.persistentStoreCoordinator.persistentStores {
            try stack.container.persistentStoreCoordinator.remove(open)
        }

        // Reading the file back is the only thing that proves the stamp was written rather than
        // just held in memory until the process exited.
        let onDisk = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            type: .sqlite,
            at: url
        )
        #expect(onDisk[MigrationPlan.versionMetadataKey] as? Int == SchemaVersion.current.rawValue)
    }

    @Test("A colour written after migration survives reopening")
    func colorPersistsAfterMigration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickWinsMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("QuickWins.sqlite")
        let id = UUID()
        try makeV1Store(at: url, taskID: id, title: "A")

        let logger = NullDiagnosticLogger()
        let firstStack = try CoreDataStack(storage: .onDisk(url), logger: logger)
        let firstRepository = CoreDataTaskRepository(stack: firstStack, logger: logger)
        var task = try #require(try firstRepository.task(id: id))
        task.color = .orange
        try firstRepository.save([task])
        for store in firstStack.container.persistentStoreCoordinator.persistentStores {
            try firstStack.container.persistentStoreCoordinator.remove(store)
        }

        let secondStack = try CoreDataStack(storage: .onDisk(url), logger: logger)
        let secondRepository = CoreDataTaskRepository(stack: secondStack, logger: logger)
        #expect(try secondRepository.task(id: id)?.color == .orange)
    }
}
