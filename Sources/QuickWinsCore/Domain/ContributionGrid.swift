import Foundation

/// The day grid behind a GitHub-style contribution graph.
///
/// Columns are weeks running left to right, rows are weekdays running top to bottom. Kept as pure
/// geometry — no view, no colour — so the awkward parts (week alignment, month boundaries, the
/// ragged current week) are testable without rendering anything.
public struct ContributionGrid: Equatable, Sendable {
    /// One entry per week. Each holds exactly seven days, oldest week first.
    public let weeks: [[DayKey]]
    /// Column index where each month first appears, for the labels across the top.
    public let monthStarts: [MonthStart]
    public let firstDay: DayKey
    public let lastDay: DayKey

    public struct MonthStart: Equatable, Sendable {
        public let column: Int
        public let month: Int
        public let year: Int
    }

    public var dayCount: Int { weeks.reduce(0) { $0 + $1.count } }
}

public enum ContributionGridRules {
    /// A full year, the way GitHub draws it.
    public static let defaultWeeks = 53

    /// Builds a grid ending on `endingOn`, aligned so every row is the same weekday.
    ///
    /// The grid is extended forward to the end of the final week rather than stopping at today,
    /// which is what keeps the rows straight. Days after `endingOn` are still returned — the view
    /// dims them — because a ragged final column reads as a rendering bug.
    public static func build(
        endingOn end: DayKey,
        weeks weekCount: Int = defaultWeeks,
        firstWeekday: Int? = nil,
        calendar: Calendar = .current
    ) -> ContributionGrid {
        let weekCount = max(1, weekCount)
        let startOfWeek = firstWeekday ?? calendar.firstWeekday

        // Walk back to the start of the week containing `end`, then back the remaining weeks.
        let endWeekday = calendar.component(.weekday, from: end.startOfDay(in: calendar))
        let offsetIntoWeek = ((endWeekday - startOfWeek) + 7) % 7
        let lastWeekStart = end.adding(days: -offsetIntoWeek, in: calendar)
        let firstWeekStart = lastWeekStart.adding(days: -7 * (weekCount - 1), in: calendar)

        var weeks: [[DayKey]] = []
        var monthStarts: [ContributionGrid.MonthStart] = []
        var seenMonths: Set<Int> = []

        var cursor = firstWeekStart
        for column in 0..<weekCount {
            var week: [DayKey] = []
            for _ in 0..<7 {
                week.append(cursor)
                cursor = cursor.adding(days: 1, in: calendar)
            }
            weeks.append(week)

            // A month is labelled at the first column that contains any of its days, so the
            // label sits above the week the month actually begins in.
            for day in week {
                let key = day.year * 100 + day.month
                if !seenMonths.contains(key) {
                    seenMonths.insert(key)
                    monthStarts.append(
                        ContributionGrid.MonthStart(column: column, month: day.month, year: day.year)
                    )
                }
            }
        }

        return ContributionGrid(
            weeks: weeks,
            monthStarts: monthStarts,
            firstDay: firstWeekStart,
            lastDay: weeks.last?.last ?? end
        )
    }

    /// Labels are dropped when a month would only occupy a sliver at the very start, which is
    /// where GitHub's own graph leaves a gap rather than crowding two labels together.
    public static func visibleMonthStarts(
        _ starts: [ContributionGrid.MonthStart],
        minimumColumnGap: Int = 3
    ) -> [ContributionGrid.MonthStart] {
        var result: [ContributionGrid.MonthStart] = []
        for start in starts {
            guard let previous = result.last else {
                result.append(start)
                continue
            }
            if start.column - previous.column >= minimumColumnGap {
                result.append(start)
            }
        }
        return result
    }
}
