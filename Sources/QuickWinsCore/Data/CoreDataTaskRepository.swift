import CoreData
import Foundation

/// Core Data implementation of `TaskRepository`.
///
/// Every mutation runs inside a single `performAndWait` block and rolls the context back on
/// failure, so a partially applied multi-row change is never committed.
public final class CoreDataTaskRepository: TaskRepository {
    private typealias Key = MigrationPlan.TaskEntityKey

    private let context: NSManagedObjectContext
    private let logger: DiagnosticLogging

    public init(stack: CoreDataStack, logger: DiagnosticLogging) {
        self.context = stack.container.viewContext
        self.logger = logger
    }

    // MARK: - Reads

    public func loadAll() throws -> [DailyTask] {
        try fetch(predicate: nil)
    }

    public func tasks(on day: DayKey) throws -> [DailyTask] {
        try fetch(predicate: NSPredicate(format: "%K == %d", Key.dayPacked, day.packed))
    }

    public func task(id: UUID) throws -> DailyTask? {
        try fetch(predicate: NSPredicate(format: "%K == %@", Key.id, id as CVarArg)).first
    }

    private func fetch(predicate: NSPredicate?) throws -> [DailyTask] {
        var result: [DailyTask] = []
        var thrown: Error?
        context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: Key.entityName)
            request.predicate = predicate
            request.sortDescriptors = [
                NSSortDescriptor(key: Key.order, ascending: true),
                NSSortDescriptor(key: Key.createdAt, ascending: true),
            ]
            do {
                // A row that cannot be decoded at all is skipped rather than failing the whole
                // read; one bad record must not make the day's list unopenable.
                result = try context.fetch(request).compactMap { Self.decode($0, logger: logger) }
            } catch {
                thrown = error
            }
        }
        if let thrown { throw PersistenceError.saveFailed(thrown.localizedDescription) }
        return result
    }

    // MARK: - Writes

    public func save(_ tasks: [DailyTask]) throws {
        guard !tasks.isEmpty else { return }
        var thrown: Error?
        context.performAndWait {
            do {
                let ids = tasks.map { $0.id }
                let request = NSFetchRequest<NSManagedObject>(entityName: Key.entityName)
                request.predicate = NSPredicate(format: "%K IN %@", Key.id, ids)
                let existing = try context.fetch(request)
                var byID: [UUID: NSManagedObject] = [:]
                for object in existing {
                    if let id = object.value(forKey: Key.id) as? UUID { byID[id] = object }
                }

                for task in tasks {
                    let object = byID[task.id] ?? NSEntityDescription.insertNewObject(
                        forEntityName: Key.entityName,
                        into: context
                    )
                    Self.encode(task, into: object)
                }

                guard context.hasChanges else { return }
                try context.save()
            } catch {
                context.rollback()
                thrown = error
            }
        }
        if let thrown {
            logger.error("persistence", "Save of \(tasks.count) task(s) failed: \(thrown.localizedDescription)")
            throw PersistenceError.saveFailed(thrown.localizedDescription)
        }
    }

    public func delete(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        var thrown: Error?
        context.performAndWait {
            do {
                let request = NSFetchRequest<NSManagedObject>(entityName: Key.entityName)
                request.predicate = NSPredicate(format: "%K IN %@", Key.id, ids)
                for object in try context.fetch(request) { context.delete(object) }
                guard context.hasChanges else { return }
                try context.save()
            } catch {
                context.rollback()
                thrown = error
            }
        }
        if let thrown { throw PersistenceError.saveFailed(thrown.localizedDescription) }
    }

    public func deleteAll() throws {
        var thrown: Error?
        context.performAndWait {
            do {
                let request = NSFetchRequest<NSManagedObject>(entityName: Key.entityName)
                for object in try context.fetch(request) { context.delete(object) }
                guard context.hasChanges else { return }
                try context.save()
            } catch {
                context.rollback()
                thrown = error
            }
        }
        if let thrown { throw PersistenceError.saveFailed(thrown.localizedDescription) }
    }

    // MARK: - Mapping

    private static func encode(_ task: DailyTask, into object: NSManagedObject) {
        object.setValue(task.id, forKey: Key.id)
        object.setValue(task.title, forKey: Key.title)
        object.setValue(task.notes, forKey: Key.notes)
        object.setValue(task.createdAt, forKey: Key.createdAt)
        object.setValue(task.day.packed, forKey: Key.dayPacked)
        object.setValue(task.order, forKey: Key.order)
        object.setValue(task.estimatedDuration, forKey: Key.estimatedDuration)
        object.setValue(max(0, task.accumulatedFocus), forKey: Key.accumulatedFocus)
        object.setValue(task.sessionStartedAt, forKey: Key.sessionStartedAt)
        object.setValue(task.completedAt, forKey: Key.completedAt)
        object.setValue(task.status.rawValue, forKey: Key.statusRaw)
        object.setValue(task.remindersEnabled, forKey: Key.remindersEnabled)
        object.setValue(task.idleDetectionEnabled, forKey: Key.idleDetectionEnabled)
        object.setValue(max(0, task.alertCount), forKey: Key.alertCount)
        object.setValue(task.lastInteractionAt, forKey: Key.lastInteractionAt)
    }

    /// Rebuilds a `DailyTask`, substituting defaults for values that are missing or nonsensical.
    ///
    /// Returns `nil` only when the row lacks an identity, which is the one field that cannot be
    /// invented without risking duplicates.
    private static func decode(_ object: NSManagedObject, logger: DiagnosticLogging) -> DailyTask? {
        guard let id = object.value(forKey: Key.id) as? UUID else {
            logger.error("persistence", "Skipping task row with no identifier.")
            return nil
        }

        let createdAt = object.value(forKey: Key.createdAt) as? Date ?? Date()
        let storedDay = object.value(forKey: Key.dayPacked) as? Int ?? 0
        let day = DayKey(packed: storedDay) ?? DayKey(date: createdAt)
        let statusRaw = object.value(forKey: Key.statusRaw) as? String ?? ""
        let status = TaskStatus(rawValue: statusRaw) ?? .upcoming
        if TaskStatus(rawValue: statusRaw) == nil {
            logger.error("persistence", "Task \(id.uuidString) had unknown status '\(statusRaw)'; defaulting to upcoming.")
        }

        let task = DailyTask(
            id: id,
            title: object.value(forKey: Key.title) as? String ?? "",
            notes: object.value(forKey: Key.notes) as? String,
            createdAt: createdAt,
            day: day,
            order: object.value(forKey: Key.order) as? Int ?? 0,
            estimatedDuration: object.value(forKey: Key.estimatedDuration) as? Double,
            accumulatedFocus: object.value(forKey: Key.accumulatedFocus) as? Double ?? 0,
            sessionStartedAt: object.value(forKey: Key.sessionStartedAt) as? Date,
            completedAt: object.value(forKey: Key.completedAt) as? Date,
            status: status,
            remindersEnabled: object.value(forKey: Key.remindersEnabled) as? Bool ?? true,
            idleDetectionEnabled: object.value(forKey: Key.idleDetectionEnabled) as? Bool ?? true,
            alertCount: object.value(forKey: Key.alertCount) as? Int ?? 0,
            lastInteractionAt: object.value(forKey: Key.lastInteractionAt) as? Date ?? createdAt
        )
        return task.normalized()
    }
}
