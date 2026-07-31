import Foundation
import Testing
@testable import QuickWinsCore

@Suite("Contribution grid")
struct ContributionGridTests {
    private let calendar = Fixture.calendar

    private func grid(weeks: Int = 53, endingOn end: DayKey = Fixture.day) -> ContributionGrid {
        ContributionGridRules.build(endingOn: end, weeks: weeks, firstWeekday: 1, calendar: calendar)
    }

    @Test("A year is 53 columns of 7 days")
    func shape() {
        let built = grid()
        #expect(built.weeks.count == 53)
        #expect(built.weeks.allSatisfy { $0.count == 7 })
        #expect(built.dayCount == 53 * 7)
    }

    @Test("Every row is the same weekday, which is what keeps the grid straight")
    func rowsAreAlignedByWeekday() {
        let built = grid()
        for row in 0..<7 {
            let weekdays = built.weeks.map { week in
                calendar.component(.weekday, from: week[row].startOfDay(in: calendar))
            }
            #expect(Set(weekdays).count == 1, "Row \(row) mixes weekdays")
        }
    }

    @Test("The first column starts on the configured first weekday")
    func startsOnTheWeekBoundary() {
        let built = grid()
        let firstWeekday = calendar.component(.weekday, from: built.firstDay.startOfDay(in: calendar))
        #expect(firstWeekday == 1)
    }

    @Test("Days run continuously with no gaps or repeats")
    func daysAreContiguous() {
        let built = grid(weeks: 8)
        let flattened = built.weeks.flatMap { $0 }

        #expect(Set(flattened).count == flattened.count)
        for index in 1..<flattened.count {
            #expect(flattened[index] == flattened[index - 1].adding(days: 1, in: calendar))
        }
    }

    @Test("The requested end day is inside the final week")
    func endDayIsCovered() {
        let built = grid()
        #expect(built.weeks.last?.contains(Fixture.day) == true)
    }

    @Test("The grid runs to the end of the final week rather than stopping at today")
    func finalWeekIsComplete() {
        // A ragged last column reads as a rendering bug; the view dims future days instead.
        let built = grid()
        #expect(built.lastDay >= Fixture.day)
        #expect(built.weeks.last?.count == 7)
    }

    @Test("Each month is labelled at the first column it appears in")
    func monthStartsAreFound() {
        let built = grid()
        #expect(built.monthStarts.count >= 12)

        // Columns only ever move forward.
        let columns = built.monthStarts.map(\.column)
        #expect(columns == columns.sorted())

        // Each labelled month really does occur in the column claimed for it.
        for start in built.monthStarts {
            let months = built.weeks[start.column].map(\.month)
            #expect(months.contains(start.month))
        }
    }

    @Test("Labels too close together are dropped rather than overlapping")
    func crowdedLabelsAreThinned() {
        let crowded = [
            ContributionGrid.MonthStart(column: 0, month: 1, year: 2026),
            ContributionGrid.MonthStart(column: 1, month: 2, year: 2026),
            ContributionGrid.MonthStart(column: 6, month: 3, year: 2026),
        ]
        let visible = ContributionGridRules.visibleMonthStarts(crowded, minimumColumnGap: 3)
        #expect(visible.map(\.month) == [1, 3])
    }

    @Test("A single-week grid is still well formed")
    func singleWeek() {
        let built = grid(weeks: 1)
        #expect(built.weeks.count == 1)
        #expect(built.weeks[0].count == 7)
        #expect(built.weeks[0].contains(Fixture.day))
    }

    @Test("A nonsensical week count is repaired rather than producing an empty grid")
    func zeroWeeksIsRepaired() {
        let built = grid(weeks: 0)
        #expect(built.weeks.count == 1)
    }

    @Test("The grid spans the right amount of time")
    func spansAYear() {
        let built = grid()
        let days = built.dayCount
        #expect(days == 371)
        // Roughly a year, allowing for the week alignment at each end.
        #expect(built.firstDay < Fixture.day)
    }
}
