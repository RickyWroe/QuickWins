import Foundation

/// Injected wall-clock reader.
///
/// Named `TimeSource` rather than `Clock` to avoid colliding with the standard library's
/// `Clock` protocol. Every elapsed-time calculation goes through this so tests can advance
/// time deterministically instead of sleeping.
public protocol TimeSource: AnyObject, Sendable {
    var now: Date { get }
}

public final class SystemTimeSource: TimeSource, @unchecked Sendable {
    public init() {}
    public var now: Date { Date() }
}

/// Test double whose time only moves when a test moves it.
public final class MutableTimeSource: TimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    public init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.current = start
    }

    public var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func advance(by interval: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(interval)
        lock.unlock()
    }

    public func set(_ date: Date) {
        lock.lock()
        current = date
        lock.unlock()
    }
}
