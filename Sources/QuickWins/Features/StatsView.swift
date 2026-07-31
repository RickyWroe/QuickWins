import QuickWinsCore
import SwiftUI

/// The dashboard: a year of focus at a glance, then the numbers behind it.
///
/// A separate window on purpose. The floating panel has to stay a glance you can dismiss without
/// thinking, and a year-wide graph plus a stack of statistics is the opposite of that.
struct StatsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                graphSection
                Divider()
                streakSection
                Divider()
                sessionSection
                peakHourSection
                footnote
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Data

    private var grid: ContributionGrid {
        ContributionGridRules.build(endingOn: model.today)
    }

    private var summaries: [DayKey: DaySummary] {
        let built = grid
        return model.daySummaries(from: built.firstDay, to: built.lastDay)
    }

    private var statistics: FocusStatistics {
        let built = grid
        return model.statistics(from: built.firstDay, to: built.lastDay)
    }

    private var hasAnyHistory: Bool { statistics.totalSeconds > 0 }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hasAnyHistory
                 ? "\(FocusTimeFormatter.abbreviated(statistics.totalSeconds)) focused in the last year"
                 : "No focus recorded yet")
                .font(.title2.weight(.semibold))
            Text("Time with a timer running. Not a measure of how the work went.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var graphSection: some View {
        let built = grid
        VStack(alignment: .leading, spacing: 10) {
            ContributionGraphView(
                grid: built,
                summaries: summaries,
                today: model.today,
                tint: Theme.accent
            )

            if !hasAnyHistory {
                // An empty graph looks broken unless it says why.
                Text("Your graph fills in as you use the timer. History began when this version was installed, so it will look sparse for a while.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var streakSection: some View {
        let daily = summaries
        let current = StreakRules.currentStreak(endingOn: model.today, summaries: daily)
        let longest = StreakRules.longestStreak(summaries: Array(daily.values))
        let goal = model.settings.dailyFocusGoalMinutes

        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Streaks")
            HStack(spacing: 12) {
                StatCard(title: "Current", value: "\(current)", unit: current == 1 ? "day" : "days")
                StatCard(title: "Longest", value: "\(longest)", unit: longest == 1 ? "day" : "days")
                StatCard(title: "Daily goal", value: "\(goal)", unit: "min")
            }
            Text("A day counts once it reaches the goal. Days off are skipped — they never break a streak.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sessionSection: some View {
        let stats = statistics
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Sessions")
            HStack(spacing: 12) {
                StatCard(title: "Recorded", value: "\(stats.sessionCount)", unit: stats.sessionCount == 1 ? "session" : "sessions")
                StatCard(
                    title: "Average",
                    value: stats.sessionCount == 0 ? "—" : FocusTimeFormatter.abbreviated(stats.averageSessionSeconds),
                    unit: ""
                )
                StatCard(
                    title: "Longest",
                    value: stats.sessionCount == 0 ? "—" : FocusTimeFormatter.abbreviated(stats.longestSessionSeconds),
                    unit: ""
                )
                StatCard(
                    title: "Interrupted",
                    value: stats.sessionCount == 0 ? "—" : "\(Int((stats.interruptionRate * 100).rounded()))%",
                    unit: ""
                )
            }
            if stats.backfilledCount > 0 {
                Text("\(stats.backfilledCount) session\(stats.backfilledCount == 1 ? " was" : "s were") reconstructed from totals recorded before history existed. They count toward time, but their clock times are unknown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var peakHourSection: some View {
        let stats = statistics
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("When you focus")

            if stats.hasEnoughDataForPeakHour {
                HourHistogram(secondsByHour: stats.secondsByHour, tint: Theme.accent)
                if let peak = stats.peakHour {
                    Text("Most focus around \(hourLabel(peak)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                // Naming an hour from three sessions would be a guess dressed as a finding.
                Text("Not enough recorded sessions yet to say. This needs at least \(FocusStatistics.minimumSessionsForPeakHour) sessions with known times.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footnote: some View {
        Text("Everything here is stored on this Mac and never leaves it.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private func hourLabel(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date).lowercased()
    }
}

// MARK: - Small pieces

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(minWidth: 96, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value) \(unit)")
    }
}

/// Focus by hour of day. Bars are labelled for VoiceOver, so the shape is not the only signal.
private struct HourHistogram: View {
    let secondsByHour: [Int: TimeInterval]
    let tint: Color

    private var peak: TimeInterval {
        max(1, secondsByHour.values.max() ?? 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<24, id: \.self) { hour in
                let seconds = secondsByHour[hour] ?? 0
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(seconds > 0 ? tint.opacity(0.3 + 0.7 * (seconds / peak)) : Color.primary.opacity(0.06))
                        .frame(height: max(3, 54 * (seconds / peak)))
                    if hour % 6 == 0 {
                        Text("\(hour)").font(.system(size: 8)).foregroundStyle(.secondary)
                    } else {
                        Text(" ").font(.system(size: 8))
                    }
                }
                .frame(width: 18)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(hour):00, \(FocusTimeFormatter.abbreviated(seconds))")
            }
        }
        .frame(height: 72, alignment: .bottom)
    }
}
