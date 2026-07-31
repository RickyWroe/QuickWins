import CoreData
import Foundation

/// Core Data implementation of `HistoryRepository`.
///
/// Follows the same rules as the task repository: every mutation runs inside one
/// `performAndWait` and rolls back on failure, and a row that cannot be decoded is skipped rather
/// than failing the whole read — one bad session must not make the dashboard unopenable.
public final class CoreDataHistoryRepository: HistoryRepository {
    private typealias SessionKey = MigrationPlan.SessionEntityKey
    private typealias DayKeyEntity = MigrationPlan.DayMarkEntityKey

    private let context: NSManagedObjectContext
    private let logger: DiagnosticLogging

    public init(stack: CoreDataStack, logger: DiagnosticLogging) {
        self.context = stack.container.viewContext
        self.logger = logger
    }

    // MARK: - Sessions

    public func allSessions() throws -> [FocusSessionRecord] {
        try fetchSessions(predicate: nil)
    }

    public func sessions(from start: DayKey, to end: DayKey) throws -> [FocusSessionRecord] {
        try fetchSessions(
            predicate: NSPredicate(
                format: "%K >= %d AND %K <= %d",
                SessionKey.dayPacked, start.packed,
                SessionKey.dayPacked, end.packed
            )
        )
    }

    private func fetchSessions(predicate: NSPredicate?) throws -> [FocusSessionRecord] {
        var result: [FocusSessionRecord] = []
        var thrown: Error?
        context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: SessionKey.entityName)
            request.predicate = predicate
            request.sortDescriptors = [NSSortDescriptor(key: SessionKey.startedAt, ascending: true)]
            do {
                result = try context.fetch(request).compactMap { Self.decode($0, logger: logger) }
            } catch {
                thrown = error
            }
        }
        if let thrown { throw PersistenceError.saveFailed(thrown.localizedDescription) }
        return result
    }

    public func record(_ sessions: [FocusSessionRecord]) throws {
        guard !sessions.isEmpty else { return }
        var thrown: Error?
        context.performAndWait {
            do {
                for session in sessions {
                    let object = NSEntityDescription.insertNewObject(
                        forEntityName: SessionKey.entityName,
                        into: context
                    )
                    Self.encode(session, into: object)
                }
                guard context.hasChanges else { return }
                try context.save()
            } catch {
                context.rollback()
                thrown = error
            }
        }
        if let thrown {
            logger.error("history", "Failed to record \(sessions.count) session(s): \(thrown.localizedDescription)")
            throw PersistenceError.saveFailed(thrown.localizedDescription)
        }
    }

    // MARK: - Day overrides

    public func dayOverrides() throws -> [DayKey: DayType] {
        var result: [DayKey: DayType] = [:]
        var thrown: Error?
        context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: DayKeyEntity.entityName)
            do {
                for object in try context.fetch(request) {
                    guard let packed = object.value(forKey: DayKeyEntity.dayPacked) as? Int,
                          let day = DayKey(packed: packed),
                          let raw = object.value(forKey: DayKeyEntity.typeRaw) as? String,
                          let type = DayType(rawValue: raw)
                    else { continue }
                    result[day] = type
                }
            } catch {
                thrown = error
            }
        }
        if let thrown { throw PersistenceError.saveFailed(thrown.localizedDescription) }
        return result
    }

    public func setDayOverride(_ type: DayType?, for day: DayKey) throws {
        var thrown: Error?
        context.performAndWait {
            do {
                let request = NSFetchRequest<NSManagedObject>(entityName: DayKeyEntity.entityName)
                request.predicate = NSPredicate(format: "%K == %d", DayKeyEntity.dayPacked, day.packed)
                let existing = try context.fetch(request)

                guard let type else {
                    // Removing the override returns the day to the weekly pattern.
                    for object in existing { context.delete(object) }
                    if context.hasChanges { try context.save() }
                    return
                }

                let object = existing.first ?? NSEntityDescription.insertNewObject(
                    forEntityName: DayKeyEntity.entityName,
                    into: context
                )
                object.setValue(day.packed, forKey: DayKeyEntity.dayPacked)
                object.setValue(type.rawValue, forKey: DayKeyEntity.typeRaw)
                if context.hasChanges { try context.save() }
            } catch {
                context.rollback()
                thrown = error
            }
        }
        if let thrown { throw PersistenceError.saveFailed(thrown.localizedDescription) }
    }

    public func deleteAllHistory() throws {
        var thrown: Error?
        context.performAndWait {
            do {
                for name in [SessionKey.entityName, DayKeyEntity.entityName] {
                    let request = NSFetchRequest<NSManagedObject>(entityName: name)
                    for object in try context.fetch(request) { context.delete(object) }
                }
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

    private static func encode(_ session: FocusSessionRecord, into object: NSManagedObject) {
        object.setValue(session.id, forKey: SessionKey.id)
        object.setValue(session.taskID, forKey: SessionKey.taskID)
        object.setValue(session.startedAt, forKey: SessionKey.startedAt)
        object.setValue(session.endedAt, forKey: SessionKey.endedAt)
        object.setValue(max(0, session.seconds), forKey: SessionKey.seconds)
        object.setValue(session.day.packed, forKey: SessionKey.dayPacked)
        object.setValue(session.wasInterrupted, forKey: SessionKey.wasInterrupted)
        object.setValue(session.isBackfilled, forKey: SessionKey.isBackfilled)
    }

    private static func decode(_ object: NSManagedObject, logger: DiagnosticLogging) -> FocusSessionRecord? {
        guard let id = object.value(forKey: SessionKey.id) as? UUID,
              let taskID = object.value(forKey: SessionKey.taskID) as? UUID,
              let startedAt = object.value(forKey: SessionKey.startedAt) as? Date,
              let endedAt = object.value(forKey: SessionKey.endedAt) as? Date
        else {
            logger.error("history", "Skipping session row with missing identity or timestamps.")
            return nil
        }

        let storedDay = object.value(forKey: SessionKey.dayPacked) as? Int ?? 0
        let day = DayKey(packed: storedDay) ?? DayKey(date: startedAt)
        let storedSeconds = object.value(forKey: SessionKey.seconds) as? Double ?? 0
        // A stored duration that disagrees with the timestamps is repaired from the timestamps,
        // which are the thing the rest of the app derives everything else from.
        let seconds = storedSeconds > 0 ? storedSeconds : max(0, endedAt.timeIntervalSince(startedAt))

        return FocusSessionRecord(
            id: id,
            taskID: taskID,
            startedAt: startedAt,
            endedAt: endedAt,
            seconds: seconds,
            day: day,
            wasInterrupted: object.value(forKey: SessionKey.wasInterrupted) as? Bool ?? false,
            isBackfilled: object.value(forKey: SessionKey.isBackfilled) as? Bool ?? false
        )
    }
}
