import QuickWinsCore
import SwiftUI

/// The contribution graph: weeks across, weekdays down, intensity by focus time.
///
/// A heat map encodes everything in colour, which is the one thing the rest of this app refuses
/// to rely on. Three things compensate: intensity varies within a *single* hue so it survives
/// colour blindness and increased contrast, a rest day is marked by its **shape** (a dashed
/// outline) rather than a shade, and every cell carries the same sentence for VoiceOver that it
/// shows on hover.
struct ContributionGraphView: View {
    let grid: ContributionGrid
    let summaries: [DayKey: DaySummary]
    let today: DayKey
    let tint: Color

    private let cell: CGFloat = 11
    private let gap: CGFloat = 3

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        return formatter.shortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            monthLabels
            HStack(alignment: .top, spacing: 6) {
                weekdayLabels
                gridBody
            }
            legend
        }
    }

    // MARK: - Pieces

    private var monthLabels: some View {
        let visible = ContributionGridRules.visibleMonthStarts(grid.monthStarts)
        return ZStack(alignment: .topLeading) {
            // A clear row of the full width keeps the labels aligned to their columns.
            Color.clear.frame(width: totalWidth, height: 12)
            ForEach(visible, id: \.column) { start in
                Text(monthName(start.month))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .offset(x: CGFloat(start.column) * (cell + gap))
            }
        }
        .padding(.leading, weekdayColumnWidth + 6)
        .frame(width: totalWidth + weekdayColumnWidth + 6, alignment: .leading)
    }

    private var weekdayLabels: some View {
        VStack(alignment: .trailing, spacing: gap) {
            ForEach(0..<7, id: \.self) { row in
                // Every other row, as GitHub does — all seven would crowd at this size.
                Text(row % 2 == 1 ? String(weekdaySymbols[row].prefix(3)) : "")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: weekdayColumnWidth, height: cell, alignment: .trailing)
            }
        }
        .accessibilityHidden(true)
    }

    private var gridBody: some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                VStack(spacing: gap) {
                    ForEach(week, id: \.self) { day in
                        DayCell(
                            day: day,
                            summary: summaries[day],
                            isToday: day == today,
                            isFuture: day > today,
                            tint: tint,
                            size: cell
                        )
                    }
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Spacer()
            Text("Less").font(.system(size: 9)).foregroundStyle(.secondary)
            ForEach(HeatmapLevel.allCases, id: \.rawValue) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(fill(for: level, tint: tint))
                    .frame(width: cell, height: cell)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08))
                    )
            }
            Text("More").font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scale from no focus to goal met")
    }

    // MARK: - Geometry

    private var weekdayColumnWidth: CGFloat { 26 }
    private var totalWidth: CGFloat {
        CGFloat(grid.weeks.count) * cell + CGFloat(max(0, grid.weeks.count - 1)) * gap
    }

    private func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        let symbols = formatter.shortMonthSymbols ?? []
        guard (1...symbols.count).contains(month) else { return "" }
        return symbols[month - 1]
    }
}

/// One day. Kept separate so the accessibility text and the tooltip cannot drift apart.
private struct DayCell: View {
    let day: DayKey
    let summary: DaySummary?
    let isToday: Bool
    let isFuture: Bool
    let tint: Color
    let size: CGFloat

    private var level: HeatmapLevel { summary?.level ?? .none }
    private var isDayOff: Bool { summary?.type == .off }

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(isFuture ? Color.clear : fill(for: level, tint: tint))
            .frame(width: size, height: size)
            .overlay(border)
            .opacity(isFuture ? 0.35 : 1)
            .help(description)
            .accessibilityLabel(description)
    }

    /// A rest day is drawn with a dashed outline rather than a different shade, so "I chose not
    /// to work" and "I worked nothing" are distinguishable with no colour perception at all.
    @ViewBuilder
    private var border: some View {
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        if isToday {
            shape.strokeBorder(Color.primary.opacity(0.85), lineWidth: 1.5)
        } else if isDayOff && level == .none {
            shape.strokeBorder(
                Color.secondary.opacity(0.7),
                style: StrokeStyle(lineWidth: 1, dash: [2, 2])
            )
        } else {
            shape.strokeBorder(Color.primary.opacity(0.08))
        }
    }

    private var description: String {
        guard !isFuture else { return "\(day), not yet" }
        guard let summary else { return "\(day), no focus recorded" }
        var text = summary.accessibilityDescription { FocusTimeFormatter.abbreviated($0) }
        if isToday { text += ", today" }
        return text
    }
}

/// One hue, five steps of intensity. Not five hues: a single-hue ramp is the version that still
/// reads correctly without colour vision and under increased contrast.
private func fill(for level: HeatmapLevel, tint: Color) -> Color {
    switch level {
    case .none: return Color.primary.opacity(0.06)
    case .light: return tint.opacity(0.28)
    case .medium: return tint.opacity(0.5)
    case .strong: return tint.opacity(0.74)
    case .full: return tint
    }
}
