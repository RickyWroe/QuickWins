import Foundation
import Testing
@testable import QuickWinsCore

@Suite("Day types and streaks")
struct DayRulesTests {
    private let calendar = Fixture.calendar

    /// Fixture.epoch is a Tuesday. These are the surrounding days, by name, so the tests read
    /// as statements about weekdays rather than about arithmetic.
    private var tuesday: DayKey { Fixture.day }
    private var saturday: DayKey { Fixture.day.adding(days: 4, in: calendar) }
    private var sunday: DayKey { Fixture.day.adding(days: 5, in: calendar) }

    @Test("The weekday of the fixture day is what these tests assume")
    func fixtureIsTuesday() {
        #expect(calendar.component(.weekday, from: tuesday.startOfDay(in: calendar)) == 3)
        #expect(calendar.component(.weekday, from: saturday.startOfDay(in: calendar)) == 7)
        #expect(calendar.component(.weekday, from: sunday.startOfDay(in: calendar)) == 1)
    }

    // MARK: - Resolution

    @Test("Weekends are days off under the default Monday-to-Friday pattern")
    func weeklyPattern() {
        let working = DayTypeRules.defaultWorkingWeekdays
        #expect(DayTypeRules.type(for: tuesday, workingWeekdays: working, overrides: [:], calendar: calendar) == .working)
        #expect(DayTypeRules.type(for: saturday, workingWeekdays: working, overrides: [:], calendar: calendar) == .off)
        #expect(DayTypeRules.type(for: sunday, workingWeekdays: working, overrides: [:], calendar: calendar) == .off)
    }

    @Test("An explicit mark beats the weekly pattern in both directions")
    func overrideWins() {
        let working = DayTypeRules.defaultWorkingWeekdays
        #expect(DayTypeRules.type(for: saturday, workingWeekdays: working, overrides: [saturday: .working], calendar: calendar) == .working)
        #expect(DayTypeRules.type(for: tuesday, workingWeekdays: working, overrides: [tuesday: .off], calendar: calendar) == .off)
    }

    @Test("A mark that merely restates the pattern is not worth storing")
    func redundantOverridesAreDetected() {
        let working = DayTypeRules.defaultWorkingWeekdays
        #expect(DayTypeRules.isRedundantOverride(.working, for: tuesday, workingWeekdays: working, calendar: calendar))
        #expect(DayTypeRules.isRedundantOverride(.off, for: saturday, workingWeekdays: working, calendar: calendar))
        #expect(!DayTypeRules.isRedundantOverride(.off, for: tuesday, workingWeekdays: working, calendar: calendar))
    }

    @Test("An empty working week falls back to the default rather than making every day a rest day")
    func emptyWorkingWeekIsRepaired() {
        #expect(DayTypeRules.sanitized(workingWeekdays: []) == DayTypeRules.defaultWorkingWeekdays)
        #expect(DayTypeRules.sanitized(workingWeekdays: [0, 9, 3]) == [3])
    }

    // MARK: - Heatmap buckets

    @Test("Levels bucket against the personal goal, not an arbitrary number of minutes")
    func heatmapLevels() {
        let goal: TimeInterval = 7_200 // two hours
        #expect(HeatmapRules.level(seconds: 0, goalSeconds: goal) == .none)
        #expect(HeatmapRules.level(seconds: 600, goalSeconds: goal) == .light)
        #expect(HeatmapRules.level(seconds: 2_400, goalSeconds: goal) == .medium)
        #expect(HeatmapRules.level(seconds: 5_400, goalSeconds: goal) == .strong)
        #expect(HeatmapRules.level(seconds: 7_200, goalSeconds: goal) == .full)
        #expect(HeatmapRules.level(seconds: 20_000, goalSeconds: goal) == .full)
    }

    @Test("Any focus at all outranks none, even against a huge goal")
    func anyFocusIsNeverNone() {
        #expect(HeatmapRules.level(seconds: 1, goalSeconds: 100_000) == .light)
    }

    // MARK: - Streaks

    private func summary(_ day: DayKey, _ type: DayType, seconds: TimeInterval, goal: TimeInterval = 3_600) -> DaySummary {
        DaySummary(
            day: day,
            type: type,
            focusedSeconds: seconds,
            level: HeatmapRules.level(seconds: seconds, goalSeconds: goal)
        )
    }

    @Test("Consecutive goal-meeting days build a streak")
    func consecutiveDaysCount() {
        var summaries: [DayKey: DaySummary] = [:]
        for offset in 0..<5 {
            let day = tuesday.adding(days: -offset, in: calendar)
            summaries[day] = summary(day, .working, seconds: 3_600)
        }
        #expect(StreakRules.currentStreak(endingOn: tuesday, summaries: summaries, calendar: calendar) == 5)
    }

    @Test("A day off between two worked days keeps the streak intact")
    func dayOffDoesNotBreakTheStreak() {
        let yesterday = tuesday.adding(days: -1, in: calendar)
        let dayBefore = tuesday.adding(days: -2, in: calendar)

        let summaries: [DayKey: DaySummary] = [
            tuesday: summary(tuesday, .working, seconds: 3_600),
            yesterday: summary(yesterday, .off, seconds: 0),
            dayBefore: summary(dayBefore, .working, seconds: 3_600),
        ]
        // The rest day is skipped, not counted — two worked days, not three.
        #expect(StreakRules.currentStreak(endingOn: tuesday, summaries: summaries, calendar: calendar) == 2)
    }

    @Test("A working day with nothing on it does break the streak")
    func emptyWorkingDayBreaksTheStreak() {
        let yesterday = tuesday.adding(days: -1, in: calendar)
        let dayBefore = tuesday.adding(days: -2, in: calendar)

        let summaries: [DayKey: DaySummary] = [
            tuesday: summary(tuesday, .working, seconds: 3_600),
            yesterday: summary(yesterday, .working, seconds: 0),
            dayBefore: summary(dayBefore, .working, seconds: 3_600),
        ]
        #expect(StreakRules.currentStreak(endingOn: tuesday, summaries: summaries, calendar: calendar) == 1)
    }

    @Test("Today falling short does not end a streak yesterday earned — the day is not over")
    func todayIsPendingNotFailed() {
        let yesterday = tuesday.adding(days: -1, in: calendar)
        let dayBefore = tuesday.adding(days: -2, in: calendar)

        let summaries: [DayKey: DaySummary] = [
            tuesday: summary(tuesday, .working, seconds: 60),
            yesterday: summary(yesterday, .working, seconds: 3_600),
            dayBefore: summary(dayBefore, .working, seconds: 3_600),
        ]
        #expect(StreakRules.currentStreak(endingOn: tuesday, summaries: summaries, calendar: calendar) == 2)
    }

    @Test("A day with no record at all is treated as a working day and breaks the streak")
    func missingDaysBreakTheStreak() {
        let dayBefore = tuesday.adding(days: -2, in: calendar)
        let summaries: [DayKey: DaySummary] = [
            tuesday: summary(tuesday, .working, seconds: 3_600),
            dayBefore: summary(dayBefore, .working, seconds: 3_600),
        ]
        #expect(StreakRules.currentStreak(endingOn: tuesday, summaries: summaries, calendar: calendar) == 1)
    }

    @Test("An unbroken run of rest days does not manufacture a streak")
    func restDaysAloneAreNotAStreak() {
        var summaries: [DayKey: DaySummary] = [:]
        for offset in 0..<10 {
            let day = tuesday.adding(days: -offset, in: calendar)
            summaries[day] = summary(day, .off, seconds: 0)
        }
        #expect(StreakRules.currentStreak(endingOn: tuesday, summaries: summaries, calendar: calendar) == 0)
    }

    @Test("The longest streak is found anywhere in the range, skipping rest days")
    func longestStreak() {
        var summaries: [DaySummary] = []
        for offset in 0..<10 {
            let day = tuesday.adding(days: -offset, in: calendar)
            switch offset {
            case 3:
                summaries.append(summary(day, .working, seconds: 0)) // the break
            case 7:
                summaries.append(summary(day, .off, seconds: 0)) // rest day, skipped
            default:
                summaries.append(summary(day, .working, seconds: 3_600))
            }
        }
        // Oldest first: five worked days (with a rest day skipped in the middle), then a break,
        // then three worked days. Were the rest day counted as a break instead of skipped, the
        // longest run would be three.
        #expect(StreakRules.longestStreak(summaries: summaries) == 5)
    }

    @Test("Day summaries describe themselves without relying on colour")
    func summariesAreSpoken() {
        let worked = summary(tuesday, .working, seconds: 2_820)
        let rested = summary(saturday, .off, seconds: 0)
        let format: (TimeInterval) -> String = { FocusTimeFormatter.abbreviated($0) }

        #expect(worked.accessibilityDescription(formatter: format).contains("47m"))
        #expect(rested.accessibilityDescription(formatter: format).contains("day off"))
        #expect(summary(tuesday, .working, seconds: 0).accessibilityDescription(formatter: format).contains("no focus"))
    }
}
