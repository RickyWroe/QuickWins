import Foundation

/// Storage for everything historical: completed focus sessions and day-type overrides.
///
/// Kept separate from `TaskRepository` on purpose. History has to outlive the tasks that produced
/// it — "Clear completed" deletes task rows, and if the only record of past focus lived there,
/// tidying up your day would erase your contribution graph.
public protocol HistoryRepository: AnyObject {
    func allSessions() throws -> [FocusSessionRecord]
    func sessions(from start: DayKey, to end: DayKey) throws -> [FocusSessionRecord]
    func record(_ sessions: [FocusSessionRecord]) throws

    /// Only days whose type differs from the weekly pattern are stored.
    func dayOverrides() throws -> [DayKey: DayType]
    /// Passing `nil` removes the override and returns the day to the weekly pattern.
    func setDayOverride(_ type: DayType?, for day: DayKey) throws

    func deleteAllHistory() throws
}

public final class InMemoryHistoryRepository: HistoryRepository {
    private var sessions: [UUID: FocusSessionRecord] = [:]
    private var overrides: [DayKey: DayType] = [:]
    private let lock = NSLock()

    /// When set, the next mutating call throws it. Used to exercise write-failure handling.
    public var errorToThrowOnNextWrite: Error?

    public init(sessions: [FocusSessionRecord] = [], overrides: [DayKey: DayType] = [:]) {
        for session in sessions { self.sessions[session.id] = session }
        self.overrides = overrides
    }

    public func allSessions() throws -> [FocusSessionRecord] {
        lock.lock(); defer { lock.unlock() }
        return sessions.values.sorted { $0.startedAt < $1.startedAt }
    }

    public func sessions(from start: DayKey, to end: DayKey) throws -> [FocusSessionRecord] {
        try allSessions().filter { $0.day >= start && $0.day <= end }
    }

    public func record(_ newSessions: [FocusSessionRecord]) throws {
        if let error = errorToThrowOnNextWrite {
            errorToThrowOnNextWrite = nil
            throw error
        }
        lock.lock(); defer { lock.unlock() }
        for session in newSessions { sessions[session.id] = session }
    }

    public func dayOverrides() throws -> [DayKey: DayType] {
        lock.lock(); defer { lock.unlock() }
        return overrides
    }

    public func setDayOverride(_ type: DayType?, for day: DayKey) throws {
        if let error = errorToThrowOnNextWrite {
            errorToThrowOnNextWrite = nil
            throw error
        }
        lock.lock(); defer { lock.unlock() }
        if let type { overrides[day] = type } else { overrides.removeValue(forKey: day) }
    }

    public func deleteAllHistory() throws {
        lock.lock(); defer { lock.unlock() }
        sessions.removeAll()
        overrides.removeAll()
    }
}
