import Foundation

/// A calendar day identified independently of time zone drift within a session.
///
/// Stored as a packed `yyyymmdd` integer so day-scoped queries are simple integer
/// comparisons and remain stable across daylight-saving transitions.
public struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = parts.year ?? 1970
        self.month = parts.month ?? 1
        self.day = parts.day ?? 1
    }

    /// Reconstructs a day from its packed `yyyymmdd` representation.
    ///
    /// Returns `nil` for values that cannot represent a calendar day, so callers reading
    /// persisted data can detect corruption instead of silently producing a wrong day.
    public init?(packed: Int) {
        guard packed > 0 else { return nil }
        let day = packed % 100
        let month = (packed / 100) % 100
        let year = packed / 10_000
        guard year > 0, (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public var packed: Int { year * 10_000 + month * 100 + day }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// Midnight at the start of this day in the supplied calendar.
    public func startOfDay(in calendar: Calendar = .current) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    public func adding(days: Int, in calendar: Calendar = .current) -> DayKey {
        let shifted = calendar.date(byAdding: .day, value: days, to: startOfDay(in: calendar))
        return DayKey(date: shifted ?? startOfDay(in: calendar), calendar: calendar)
    }

    public static func today(_ time: TimeSource, calendar: Calendar = .current) -> DayKey {
        DayKey(date: time.now, calendar: calendar)
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.packed < rhs.packed }
}
