import Foundation
import Testing
@testable import QuickWinsCore

@Suite("Focus statistics")
struct FocusStatisticsTests {
    private let calendar = Fixture.calendar
    private let taskA = UUID()
    private let taskB = UUID()

    private func session(
        task: UUID? = nil,
        atHour hour: Int,
        minutes: Double,
        interrupted: Bool = false,
        backfilled: Bool = false
    ) -> FocusSessionRecord {
        let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Fixture.epoch) ?? Fixture.epoch
        let seconds = minutes * 60
        return FocusSessionRecord(
            taskID: task ?? taskA,
            startedAt: start,
            endedAt: start.addingTimeInterval(seconds),
            seconds: seconds,
            day: DayKey(date: start, calendar: calendar),
            wasInterrupted: interrupted,
            isBackfilled: backfilled
        )
    }

    @Test("Nothing recorded produces empty statistics rather than a divide by zero")
    func emptyInput() {
        #expect(StatisticsRules.compute(sessions: [], calendar: calendar) == .empty)
        #expect(FocusStatistics.empty.interruptionRate == 0)
    }

    @Test("Totals, averages and the longest session are reported")
    func basicAggregates() {
        let stats = StatisticsRules.compute(
            sessions: [session(atHour: 9, minutes: 30), session(atHour: 14, minutes: 90)],
            calendar: calendar
        )
        #expect(stats.totalSeconds == 120 * 60)
        #expect(stats.sessionCount == 2)
        #expect(stats.averageSessionSeconds == 60 * 60)
        #expect(stats.longestSessionSeconds == 90 * 60)
    }

    @Test("The interruption rate counts sessions cut short")
    func interruptionRate() {
        let stats = StatisticsRules.compute(
            sessions: [
                session(atHour: 9, minutes: 30, interrupted: true),
                session(atHour: 11, minutes: 30),
                session(atHour: 13, minutes: 30),
                session(atHour: 15, minutes: 30),
            ],
            calendar: calendar
        )
        #expect(stats.interruptedCount == 1)
        #expect(stats.interruptionRate == 0.25)
    }

    @Test("A long session is spread across the hours it spanned, not credited to its start")
    func longSessionsAreSpreadAcrossHours() {
        // 09:00 to 12:00 is one hour in each of 9, 10 and 11 — not three hours at 09:00.
        let stats = StatisticsRules.compute(sessions: [session(atHour: 9, minutes: 180)], calendar: calendar)

        #expect(stats.secondsByHour[9] == 3_600)
        #expect(stats.secondsByHour[10] == 3_600)
        #expect(stats.secondsByHour[11] == 3_600)
        #expect(stats.secondsByHour[12] == nil)
    }

    @Test("Peak hour is the hour with the most focus")
    func peakHour() {
        let stats = StatisticsRules.compute(
            sessions: [
                session(atHour: 9, minutes: 20),
                session(atHour: 14, minutes: 100),
                session(atHour: 16, minutes: 15),
            ],
            calendar: calendar
        )
        #expect(stats.peakHour == 14)
    }

    @Test("Backfilled sessions never influence peak hours, because their clock times were invented")
    func backfilledSessionsExcludedFromPeakHours() {
        let stats = StatisticsRules.compute(
            sessions: [
                session(atHour: 3, minutes: 600, backfilled: true),
                session(atHour: 10, minutes: 30),
            ],
            calendar: calendar
        )
        // The backfilled block is ten hours at 3am and would dominate if it were counted.
        #expect(stats.secondsByHour[3] == nil)
        #expect(stats.peakHour == 10)
        #expect(stats.backfilledCount == 1)
        // It still counts toward totals, where only the duration matters.
        let expectedTotal: TimeInterval = (600 + 30) * 60
        #expect(stats.totalSeconds == expectedTotal)
    }

    @Test("Peak hour is withheld until there is a real sample to judge from")
    func peakHourNeedsEnoughData() {
        let thin = StatisticsRules.compute(sessions: [session(atHour: 10, minutes: 30)], calendar: calendar)
        #expect(!thin.hasEnoughDataForPeakHour)

        let plenty = StatisticsRules.compute(
            sessions: (0..<12).map { session(atHour: 10, minutes: 30 + Double($0)) },
            calendar: calendar
        )
        #expect(plenty.hasEnoughDataForPeakHour)
    }

    @Test("A history made only of backfilled sessions never claims to know a peak hour")
    func allBackfilledMeansNoPeakHour() {
        let stats = StatisticsRules.compute(
            sessions: (0..<20).map { _ in session(atHour: 9, minutes: 60, backfilled: true) },
            calendar: calendar
        )
        #expect(!stats.hasEnoughDataForPeakHour)
        #expect(stats.secondsByHour.isEmpty)
    }

    @Test("Focus is broken down per task, the nearest thing to a per-repository split")
    func perTaskBreakdown() {
        let stats = StatisticsRules.compute(
            sessions: [
                session(task: taskA, atHour: 9, minutes: 30),
                session(task: taskA, atHour: 11, minutes: 30),
                session(task: taskB, atHour: 13, minutes: 15),
            ],
            calendar: calendar
        )
        let expectedA: TimeInterval = 60 * 60
        let expectedB: TimeInterval = 15 * 60
        #expect(stats.secondsByTask[taskA] == expectedA)
        #expect(stats.secondsByTask[taskB] == expectedB)
    }
}
