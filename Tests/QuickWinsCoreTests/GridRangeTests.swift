import Foundation
import Testing
@testable import QuickWinsCore

@Suite("Grid over a date range")
struct GridRangeTests {
    private let calendar = Fixture.calendar

    @Test("A range grid covers both ends, expanded to whole weeks")
    func coversTheRange() {
        let start = Fixture.day.adding(months: -3, in: calendar)
        let end = Fixture.day.adding(months: 3, in: calendar)
        let grid = ContributionGridRules.build(from: start, to: end, firstWeekday: 1, calendar: calendar)

        #expect(grid.firstDay <= start)
        #expect(grid.lastDay >= end)
        #expect(grid.weeks.allSatisfy { $0.count == 7 })
    }

    @Test("Six months is roughly twenty-six to twenty-eight columns")
    func plausibleWidth() {
        let grid = ContributionGridRules.build(
            from: Fixture.day.adding(months: -3, in: calendar),
            to: Fixture.day.adding(months: 3, in: calendar),
            firstWeekday: 1,
            calendar: calendar
        )
        #expect(grid.weeks.count >= 26)
        #expect(grid.weeks.count <= 29)
    }

    @Test("Today sits inside the range grid")
    func todayIsCovered() {
        let grid = ContributionGridRules.build(
            from: Fixture.day.adding(months: -3, in: calendar),
            to: Fixture.day.adding(months: 3, in: calendar),
            firstWeekday: 1,
            calendar: calendar
        )
        #expect(grid.weeks.contains { $0.contains(Fixture.day) })
    }

    @Test("Rows stay aligned by weekday across a range grid")
    func rowsAligned() {
        let grid = ContributionGridRules.build(
            from: Fixture.day.adding(months: -3, in: calendar),
            to: Fixture.day.adding(months: 3, in: calendar),
            firstWeekday: 1,
            calendar: calendar
        )
        for row in 0..<7 {
            let weekdays = grid.weeks.map { calendar.component(.weekday, from: $0[row].startOfDay(in: calendar)) }
            #expect(Set(weekdays).count == 1)
        }
    }

    @Test("A backwards range still yields a usable grid rather than looping")
    func backwardsRangeIsSafe() {
        let grid = ContributionGridRules.build(
            from: Fixture.day,
            to: Fixture.day.adding(months: -3, in: calendar),
            firstWeekday: 1,
            calendar: calendar
        )
        #expect(grid.weeks.count == 1)
    }

    @Test("Month arithmetic lands on the same day number where the month allows")
    func monthArithmetic() {
        let march31 = DayKey(year: 2026, month: 3, day: 31)
        #expect(march31.adding(months: 1, in: calendar).month == 4)
        #expect(march31.adding(months: -1, in: calendar).month == 2)
    }
}
