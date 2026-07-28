import QuickWinsCore
import SwiftUI

/// The panel's focal point: what to work on right now, how long it has taken, and the two
/// actions that matter.
struct ActiveTaskCard: View {
    @ObservedObject var model: AppModel
    let task: DailyTask
    let session: FocusSession

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var elapsed: TimeInterval { session.elapsed(at: model.now) }
    private var isRunning: Bool { task.status == .active }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(task.title)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            timing
            statusLine
            actions
        }
        .padding(Theme.horizontalPadding)
        .background(cardBackground)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Current focus: \(task.title)")
        .accessibilityValue(accessibilitySummary)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Current focus")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            attentionIndicator
        }
    }

    /// Escalation is shown as an icon plus words, never colour alone.
    @ViewBuilder
    private var attentionIndicator: some View {
        let level = model.accountabilityLevel
        if isRunning, let label = level.indicatorLabel {
            Label(label, systemImage: level.indicatorSymbol)
                .font(.caption2)
                .foregroundStyle(level.indicatorColor)
                .labelStyle(.titleAndIcon)
                .transition(reduceMotion ? .identity : .opacity)
                .accessibilityLabel("Attention: \(label)")
        }
    }

    private var timing: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(FocusTimeFormatter.clock(elapsed))
                .font(.system(size: 30, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(isRunning ? Color.primary : .secondary)
                .contentTransition(.numericText())
                .accessibilityLabel("Elapsed \(FocusTimeFormatter.spoken(elapsed))")

            Text("elapsed")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: 6) {
            Image(systemName: task.status.symbolName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if session.wasInterrupted {
                Label("Interrupted", systemImage: "exclamationmark.arrow.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("This session stopped tracking after a long gap. The task itself is untouched.")
            }
        }
    }

    private var statusText: String {
        if let overtime = session.overtime(at: model.now) {
            return "\(FocusTimeFormatter.estimate(session.estimate ?? 0)) estimate · \(FocusTimeFormatter.clock(overtime)) over"
        }
        if let remaining = session.remaining(at: model.now) {
            return "\(FocusTimeFormatter.clock(remaining)) left of \(FocusTimeFormatter.estimate(session.estimate ?? 0))"
        }
        return isRunning ? "Timer running" : "Paused"
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                isRunning ? model.pause(task.id) : model.start(task.id)
            } label: {
                Label(isRunning ? "Pause" : "Start", systemImage: isRunning ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .accessibilityHint(isRunning ? "Pauses the focus timer" : "Starts the focus timer")

            Button {
                model.complete(task.id)
            } label: {
                Label("Finish", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .accessibilityHint("Marks this task complete")

            Menu {
                Button("Edit…") { model.editingTask = task }
                Button("Skip") { model.skip(task.id) }
                Button("Move to tomorrow") { model.moveToTomorrow(task.id) }
                Divider()
                Toggle("Inactivity check-ins", isOn: Binding(
                    get: { task.idleDetectionEnabled },
                    set: { model.setIdleDetection($0, for: task.id) }
                ))
                Menu("Snooze alerts") {
                    ForEach(SnoozeDuration.allCases, id: \.self) { duration in
                        Button(duration.label) { model.snooze(duration) }
                    }
                }
                if model.isSnoozed {
                    Button("End snooze") { model.clearSnooze() }
                }
                Divider()
                Button("Delete", role: .destructive) { model.delete(task.id) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28)
            .accessibilityLabel("More actions for \(task.title)")
        }
        .frame(minHeight: Theme.minimumHitTarget)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
            .fill(.thickMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(isRunning ? Theme.accent.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    private var accessibilitySummary: String {
        var parts = [task.status.accessibilityDescription, "elapsed \(FocusTimeFormatter.spoken(elapsed))"]
        if let remaining = session.remaining(at: model.now), remaining > 0 {
            parts.append("\(FocusTimeFormatter.spoken(remaining)) remaining")
        }
        if let overtime = session.overtime(at: model.now) {
            parts.append("\(FocusTimeFormatter.spoken(overtime)) over estimate")
        }
        return parts.joined(separator: ", ")
    }
}
