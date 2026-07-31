import Foundation

/// Aggregate numbers for the dashboard.
///
/// Every field measures *time with a timer running*, not productivity. The UI says so, and so does
/// this type, because the difference is the whole reason the rest of the app refuses to tell the
/// user how their work is going.
public struct FocusStatistics: Equatable, Sendable {
    public let totalSeconds: TimeInterval
    public let sessionCount: Int
    public let averageSessionSeconds: TimeInterval
    public let longestSessionSeconds: TimeInterval
    public let interruptedCount: Int
    /// Focus per hour of day, 0–23. Backfilled sessions are excluded.
    public let secondsByHour: [Int: TimeInterval]
    /// Focus per task, for the closest thing to a per-repository breakdown.
    public let secondsByTask: [UUID: TimeInterval]
    /// Number of sessions whose clock times were reconstructed rather than observed.
    public let backfilledCount: Int

    public var interruptionRate: Double {
        sessionCount == 0 ? 0 : Double(interruptedCount) / Double(sessionCount)
    }

    /// The hour with the most recorded focus, or nil when there is nothing trustworthy to judge by.
    public var peakHour: Int? {
        secondsByHour.max { $0.value < $1.value }?.key
    }

    /// Peak-hour analysis needs a reasonable sample before it means anything. Below this the
    /// dashboard should say it does not know yet rather than name an hour on thin evidence.
    public static let minimumSessionsForPeakHour = 10

    public var hasEnoughDataForPeakHour: Bool {
        secondsByHour.values.reduce(0, +) > 0
            && (sessionCount - backfilledCount) >= Self.minimumSessionsForPeakHour
    }

    public static let empty = FocusStatistics(
        totalSeconds: 0,
        sessionCount: 0,
        averageSessionSeconds: 0,
        longestSessionSeconds: 0,
        interruptedCount: 0,
        secondsByHour: [:],
        secondsByTask: [:],
        backfilledCount: 0
    )

    public init(
        totalSeconds: TimeInterval,
        sessionCount: Int,
        averageSessionSeconds: TimeInterval,
        longestSessionSeconds: TimeInterval,
        interruptedCount: Int,
        secondsByHour: [Int: TimeInterval],
        secondsByTask: [UUID: TimeInterval],
        backfilledCount: Int
    ) {
        self.totalSeconds = totalSeconds
        self.sessionCount = sessionCount
        self.averageSessionSeconds = averageSessionSeconds
        self.longestSessionSeconds = longestSessionSeconds
        self.interruptedCount = interruptedCount
        self.secondsByHour = secondsByHour
        self.secondsByTask = secondsByTask
        self.backfilledCount = backfilledCount
    }
}

public enum StatisticsRules {

    public static func compute(
        sessions: [FocusSessionRecord],
        calendar: Calendar = .current
    ) -> FocusStatistics {
        guard !sessions.isEmpty else { return .empty }

        var total: TimeInterval = 0
        var longest: TimeInterval = 0
        var interrupted = 0
        var backfilled = 0
        var byHour: [Int: TimeInterval] = [:]
        var byTask: [UUID: TimeInterval] = [:]

        for session in sessions {
            let seconds = max(0, session.seconds)
            total += seconds
            longest = max(longest, seconds)
            if session.wasInterrupted { interrupted += 1 }
            byTask[session.taskID, default: 0] += seconds

            if session.isBackfilled {
                // Its clock times were invented when history began. Counting them toward peak
                // hours would report a guess back to the user as their best working time.
                backfilled += 1
                continue
            }
            distribute(session: session, seconds: seconds, into: &byHour, calendar: calendar)
        }

        return FocusStatistics(
            totalSeconds: total,
            sessionCount: sessions.count,
            averageSessionSeconds: total / Double(sessions.count),
            longestSessionSeconds: longest,
            interruptedCount: interrupted,
            secondsByHour: byHour,
            secondsByTask: byTask,
            backfilledCount: backfilled
        )
    }

    /// Spreads a session across the hours it actually spanned.
    ///
    /// Crediting the whole of a 90-minute session to its starting hour would make long sessions
    /// distort the peak-hour histogram in favour of whenever the user tends to begin work.
    private static func distribute(
        session: FocusSessionRecord,
        seconds: TimeInterval,
        into byHour: inout [Int: TimeInterval],
        calendar: Calendar
    ) {
        guard seconds > 0 else { return }
        var cursor = session.startedAt
        let end = session.endedAt

        while cursor < end {
            let hour = calendar.component(.hour, from: cursor)
            let hourStart = calendar.dateInterval(of: .hour, for: cursor)?.start ?? cursor
            let nextHour = calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? end
            let sliceEnd = min(nextHour, end)
            guard sliceEnd > cursor else { break }

            byHour[hour, default: 0] += sliceEnd.timeIntervalSince(cursor)
            cursor = sliceEnd
        }
    }
}
