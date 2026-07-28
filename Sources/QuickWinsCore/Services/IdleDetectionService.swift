import CoreGraphics
import Foundation

public protocol IdleTimeProviding: AnyObject, Sendable {
    /// Seconds since the last hardware input event anywhere in the system.
    func idleSeconds() -> TimeInterval
    /// False when the platform refused to report idle time, so callers can degrade instead of
    /// treating an unavailable reading as "the user is away".
    var isAvailable: Bool { get }
}

/// System-wide idle time from Quartz Event Services.
///
/// `CGEventSource.secondsSinceLastEventType` needs no Accessibility permission and exposes
/// only a duration — never what was typed, clicked, or displayed. `.hidSystemState` counts
/// hardware input only, so synthetic events posted by scripts are not mistaken for presence.
public final class SystemIdleTimeProvider: IdleTimeProviding, @unchecked Sendable {
    private static let anyInputEventType = CGEventType(rawValue: ~0)

    public init() {}

    public var isAvailable: Bool { Self.anyInputEventType != nil }

    public func idleSeconds() -> TimeInterval {
        guard let eventType = Self.anyInputEventType else { return 0 }
        let seconds = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: eventType)
        guard seconds.isFinite, seconds >= 0 else { return 0 }
        return seconds
    }
}

/// Test double: idle time is whatever the test says it is.
public final class StubIdleTimeProvider: IdleTimeProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval
    public var isAvailable: Bool

    public init(seconds: TimeInterval = 0, isAvailable: Bool = true) {
        self.value = seconds
        self.isAvailable = isAvailable
    }

    public func idleSeconds() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    public func set(_ seconds: TimeInterval) {
        lock.lock()
        value = seconds
        lock.unlock()
    }
}
