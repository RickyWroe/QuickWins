import Foundation

/// Whether a day was one you meant to work.
///
/// The distinction exists because a contribution graph cannot otherwise tell "I did not work"
/// from "I chose not to work" — every blank square reads as a failure, which is the most
/// demoralising thing about using one as a personal tracker.
public enum DayType: String, Codable, Sendable, CaseIterable {
    case working
    case off

    public var accessibilityDescription: String {
        switch self {
        case .working: return "Working day"
        case .off: return "Day off"
        }
    }
}

public enum DayTypeRules {
    /// `Calendar` numbers weekdays from 1 for Sunday. Monday to Friday is the default working week.
    public static let defaultWorkingWeekdays: Set<Int> = [2, 3, 4, 5, 6]

    /// Resolves a day's type from the weekly pattern, letting an explicit mark win.
    ///
    /// Only overrides are stored. A normal week writes nothing at all, so marking every weekend
    /// would otherwise mean thousands of rows that say exactly what the pattern already says.
    public static func type(
        for day: DayKey,
        workingWeekdays: Set<Int>,
        overrides: [DayKey: DayType],
        calendar: Calendar = .current
    ) -> DayType {
        if let override = overrides[day] { return override }
        let weekday = calendar.component(.weekday, from: day.startOfDay(in: calendar))
        return workingWeekdays.contains(weekday) ? .working : .off
    }

    /// True when an explicit mark would say the same thing the pattern already says, and so is
    /// not worth storing.
    public static func isRedundantOverride(
        _ type: DayType,
        for day: DayKey,
        workingWeekdays: Set<Int>,
        calendar: Calendar = .current
    ) -> Bool {
        let weekday = calendar.component(.weekday, from: day.startOfDay(in: calendar))
        let implied: DayType = workingWeekdays.contains(weekday) ? .working : .off
        return implied == type
    }

    public static func sanitized(workingWeekdays: Set<Int>) -> Set<Int> {
        let valid = workingWeekdays.filter { (1...7).contains($0) }
        // An empty working week would make every day a rest day and every streak meaningless.
        return valid.isEmpty ? defaultWorkingWeekdays : valid
    }
}

/// How full a contribution-graph cell is drawn.
public enum HeatmapLevel: Int, Comparable, Sendable, CaseIterable {
    case none = 0
    case light = 1
    case medium = 2
    case strong = 3
    case full = 4

    public static func < (lhs: HeatmapLevel, rhs: HeatmapLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var accessibilityDescription: String {
        switch self {
        case .none: return "no focus"
        case .light: return "a little focus"
        case .medium: return "moderate focus"
        case .strong: return "strong focus"
        case .full: return "goal met"
        }
    }
}

public enum HeatmapRules {
    /// Buckets a day's focus against the daily goal, so the scale means something personal rather
    /// than being pinned to an arbitrary number of minutes.
    public static func level(seconds: TimeInterval, goalSeconds: TimeInterval) -> HeatmapLevel {
        guard seconds > 0 else { return .none }
        guard goalSeconds > 0 else { return .full }

        let fraction = seconds / goalSeconds
        switch fraction {
        case ..<0.25: return .light
        case ..<0.5: return .medium
        case ..<1.0: return .strong
        default: return .full
        }
    }
}

/// A day as the contribution graph sees it.
public struct DaySummary: Equatable, Sendable {
    public let day: DayKey
    public let type: DayType
    public let focusedSeconds: TimeInterval
    public let level: HeatmapLevel

    public init(day: DayKey, type: DayType, focusedSeconds: TimeInterval, level: HeatmapLevel) {
        self.day = day
        self.type = type
        self.focusedSeconds = focusedSeconds
        self.level = level
    }

    public var metGoal: Bool { level == .full }

    /// Spoken by VoiceOver, because a heat map otherwise conveys everything through colour alone.
    public func accessibilityDescription(formatter: (TimeInterval) -> String) -> String {
        switch (type, focusedSeconds > 0) {
        case (.off, false): return "\(day), day off"
        case (.off, true): return "\(day), day off, \(formatter(focusedSeconds)) focused"
        case (.working, false): return "\(day), no focus recorded"
        case (.working, true): return "\(day), \(formatter(focusedSeconds)) focused"
        }
    }
}

public enum StreakRules {
    /// Counts consecutive goal-meeting days ending today.
    ///
    /// Days off are skipped: they neither break a streak nor extend it, which is the whole point
    /// of marking them. Today is treated as pending rather than failed — the day is not over, so
    /// falling short of the goal so far does not end a streak that yesterday earned.
    public static func currentStreak(
        endingOn today: DayKey,
        summaries: [DayKey: DaySummary],
        maximumLookback: Int = 800,
        calendar: Calendar = .current
    ) -> Int {
        var streak = 0
        var cursor = today

        for step in 0..<maximumLookback {
            let summary = summaries[cursor]
            let type = summary?.type ?? .working

            if type == .off {
                cursor = cursor.adding(days: -1, in: calendar)
                continue
            }

            if summary?.metGoal == true {
                streak += 1
            } else if step == 0 {
                // Today is still in progress.
            } else {
                break
            }

            cursor = cursor.adding(days: -1, in: calendar)
        }

        return streak
    }

    /// The longest run of goal-meeting working days anywhere in the supplied range.
    public static func longestStreak(summaries: [DaySummary]) -> Int {
        let ordered = summaries.sorted { $0.day < $1.day }
        var longest = 0
        var running = 0

        for summary in ordered {
            switch (summary.type, summary.metGoal) {
            case (.off, _):
                continue // Skipped, exactly as in the current streak.
            case (.working, true):
                running += 1
                longest = max(longest, running)
            case (.working, false):
                running = 0
            }
        }

        return longest
    }
}
