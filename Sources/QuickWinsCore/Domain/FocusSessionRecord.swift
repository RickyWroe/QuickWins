import Foundation

/// One completed stretch of focus on a task.
///
/// The task itself only carries a running total, which is enough to show a timer but says nothing
/// about *when* the work happened. Everything historical — the contribution graph, streaks, peak
/// hours — is derived from these records instead, and they survive the task being deleted.
public struct FocusSessionRecord: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var taskID: UUID
    public var startedAt: Date
    public var endedAt: Date
    /// Denormalised duration. Always positive; a record is never created without one.
    public var seconds: TimeInterval
    /// The day this stretch belongs to. A session crossing midnight is split, so this is exact.
    public var day: DayKey
    /// Ended by the idle ceiling or a stale heartbeat rather than by the user.
    public var wasInterrupted: Bool
    /// Reconstructed from a task's stored total when history began, so its clock times are a
    /// guess. Excluded from any analysis that depends on *when* work happened.
    public var isBackfilled: Bool

    public init(
        id: UUID = UUID(),
        taskID: UUID,
        startedAt: Date,
        endedAt: Date,
        seconds: TimeInterval,
        day: DayKey,
        wasInterrupted: Bool = false,
        isBackfilled: Bool = false
    ) {
        self.id = id
        self.taskID = taskID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.seconds = seconds
        self.day = day
        self.wasInterrupted = wasInterrupted
        self.isBackfilled = isBackfilled
    }
}

public enum SessionRules {
    /// A single stretch beyond this is almost certainly a bug rather than work. The heartbeat
    /// should already have capped it, so this is a second line of defence for reporting.
    public static let maximumPlausibleSession: TimeInterval = 8 * 3_600

    /// Turns a start and end instant into the records to store.
    ///
    /// Returns more than one when the stretch crosses midnight: a session run from 23:00 to 01:00
    /// belongs partly to each day, and attributing all of it to one would make the contribution
    /// graph say the work happened on a day it did not. Returns nothing for a zero or negative
    /// span, so a clock adjustment cannot invent focus time.
    public static func close(
        taskID: UUID,
        from start: Date,
        to end: Date,
        wasInterrupted: Bool = false,
        isBackfilled: Bool = false,
        calendar: Calendar = .current,
        makeID: () -> UUID = { UUID() }
    ) -> [FocusSessionRecord] {
        guard end > start else { return [] }

        var records: [FocusSessionRecord] = []
        var segmentStart = start

        while segmentStart < end {
            let dayStart = calendar.startOfDay(for: segmentStart)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? end
            let segmentEnd = min(nextDay, end)
            // A calendar that refuses to advance would otherwise spin here forever.
            guard segmentEnd > segmentStart else { break }

            records.append(
                FocusSessionRecord(
                    id: makeID(),
                    taskID: taskID,
                    startedAt: segmentStart,
                    endedAt: segmentEnd,
                    seconds: segmentEnd.timeIntervalSince(segmentStart),
                    day: DayKey(date: segmentStart, calendar: calendar),
                    wasInterrupted: wasInterrupted,
                    isBackfilled: isBackfilled
                )
            )
            segmentStart = segmentEnd
        }

        return records
    }

    public static func isImplausible(_ record: FocusSessionRecord) -> Bool {
        record.seconds > maximumPlausibleSession
    }

    /// Total focus per day, which is what the contribution graph draws.
    public static func focusByDay(_ sessions: [FocusSessionRecord]) -> [DayKey: TimeInterval] {
        sessions.reduce(into: [:]) { totals, session in
            totals[session.day, default: 0] += max(0, session.seconds)
        }
    }
}
