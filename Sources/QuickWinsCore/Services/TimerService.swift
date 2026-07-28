import Foundation

public protocol TickScheduling: AnyObject {
    var isRunning: Bool { get }
    func start(interval: TimeInterval, handler: @escaping () -> Void)
    func stop()
}

/// A single coalesced repeating timer used to refresh the elapsed-time display.
///
/// Only one timer ever exists; `start` replaces any previous schedule so repeated calls from
/// panel show/hide cannot leak parallel tickers. Generous leeway lets the system batch these
/// wakeups with others, which matters for battery on an app that may tick all day.
public final class TimerService: TickScheduling {
    private var source: DispatchSourceTimer?
    private let queue: DispatchQueue

    public init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    public var isRunning: Bool { source != nil }

    public func start(interval: TimeInterval, handler: @escaping () -> Void) {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(200)
        )
        timer.setEventHandler(handler: handler)
        source = timer
        timer.resume()
    }

    public func stop() {
        source?.setEventHandler(handler: nil)
        source?.cancel()
        source = nil
    }

    deinit { stop() }
}

/// Fires only when a test tells it to.
public final class ManualTickScheduler: TickScheduling {
    private var handler: (() -> Void)?
    public private(set) var startCount = 0
    public private(set) var stopCount = 0
    public private(set) var lastInterval: TimeInterval?

    public init() {}

    public var isRunning: Bool { handler != nil }

    public func start(interval: TimeInterval, handler: @escaping () -> Void) {
        // Mirrors TimerService: starting replaces any existing schedule.
        stop()
        startCount += 1
        lastInterval = interval
        self.handler = handler
    }

    public func stop() {
        if handler != nil { stopCount += 1 }
        handler = nil
    }

    public func fire(times: Int = 1) {
        for _ in 0..<times { handler?() }
    }
}
