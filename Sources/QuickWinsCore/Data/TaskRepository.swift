import Foundation

/// Storage boundary for tasks.
///
/// Deliberately narrow and synchronous. `save` takes an array because every domain operation
/// in `TaskRules` produces a whole-day result, and applying it as one transaction is what keeps
/// multi-step changes — such as switching the active task, which pauses one row and starts
/// another — from being persisted half-applied.
public protocol TaskRepository: AnyObject {
    func loadAll() throws -> [DailyTask]
    func tasks(on day: DayKey) throws -> [DailyTask]
    func task(id: UUID) throws -> DailyTask?
    func save(_ tasks: [DailyTask]) throws
    func delete(ids: [UUID]) throws
    func deleteAll() throws
}

public extension TaskRepository {
    func save(_ task: DailyTask) throws { try save([task]) }
    func delete(id: UUID) throws { try delete(ids: [id]) }
}

/// In-memory repository for tests and for keeping the app usable if the database fails to open.
public final class InMemoryTaskRepository: TaskRepository {
    private var storage: [UUID: DailyTask] = [:]
    private let lock = NSLock()

    /// When set, the next mutating call throws it. Used to exercise save-failure recovery.
    public var errorToThrowOnNextWrite: Error?

    public init(seed: [DailyTask] = []) {
        for task in seed { storage[task.id] = task }
    }

    public func loadAll() throws -> [DailyTask] {
        lock.lock(); defer { lock.unlock() }
        return TaskRules.sortedForDisplay(storage.values.map { $0.normalized() })
    }

    public func tasks(on day: DayKey) throws -> [DailyTask] {
        try loadAll().filter { $0.day == day }
    }

    public func task(id: UUID) throws -> DailyTask? {
        lock.lock(); defer { lock.unlock() }
        return storage[id]?.normalized()
    }

    public func save(_ tasks: [DailyTask]) throws {
        if let error = errorToThrowOnNextWrite {
            errorToThrowOnNextWrite = nil
            throw error
        }
        lock.lock(); defer { lock.unlock() }
        for task in tasks { storage[task.id] = task }
    }

    public func delete(ids: [UUID]) throws {
        if let error = errorToThrowOnNextWrite {
            errorToThrowOnNextWrite = nil
            throw error
        }
        lock.lock(); defer { lock.unlock() }
        for id in ids { storage.removeValue(forKey: id) }
    }

    public func deleteAll() throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll()
    }
}
