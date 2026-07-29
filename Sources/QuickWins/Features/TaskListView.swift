import QuickWinsCore
import SwiftUI

struct TaskListView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let upcoming = model.upcoming
        let completed = model.completed
        let overdue = model.overdue

        if upcoming.isEmpty && completed.isEmpty && overdue.isEmpty {
            EmptyView()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if !overdue.isEmpty {
                        SectionHeader(title: "Unfinished", systemImage: "clock.arrow.circlepath")
                        ForEach(overdue) { task in
                            TaskRow(model: model, task: task, showsCarryOver: true)
                        }
                    }

                    if !upcoming.isEmpty {
                        SectionHeader(title: "Upcoming", systemImage: nil)
                        ForEach(upcoming) { task in
                            TaskRow(model: model, task: task, showsCarryOver: false)
                        }
                    }

                    if !completed.isEmpty {
                        SectionHeader(
                            title: "Done",
                            systemImage: nil,
                            trailing: AnyView(
                                Button("Clear") { model.clearCompleted() }
                                    .buttonStyle(.link)
                                    .font(.caption)
                                    .accessibilityHint("Removes completed tasks. This can be undone with Command Z.")
                            )
                        )
                        ForEach(completed) { task in
                            TaskRow(model: model, task: task, showsCarryOver: false)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            .frame(maxHeight: Theme.maximumListHeight)
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let systemImage: String?
    var trailing: AnyView?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .tracking(0.5)
            Spacer(minLength: 4)
            trailing
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, Theme.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

struct TaskRow: View {
    @ObservedObject var model: AppModel
    let task: DailyTask
    let showsCarryOver: Bool

    @State private var isHovering = false

    private var isSelected: Bool { model.selectionTarget?.id == task.id }
    private var isFinished: Bool { !task.status.isOpen }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isFinished ? model.restore(task.id) : model.complete(task.id)
            } label: {
                Image(systemName: task.status.symbolName)
                    .font(.body)
                    .foregroundStyle(task.status == .completed ? Theme.accent : .secondary)
                    .frame(width: Theme.minimumHitTarget, height: Theme.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFinished ? "Restore \(task.title)" : "Complete \(task.title)")

            Circle()
                .fill(task.color.swatch)
                .frame(width: 7, height: 7)
                .opacity(isFinished ? 0.4 : 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.callout)
                    .strikethrough(task.status == .completed, color: .secondary)
                    .foregroundStyle(isFinished ? .secondary : .primary)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            if isHovering || isSelected {
                rowActions
            } else if task.accumulatedFocus > 0 {
                Text(FocusTimeFormatter.abbreviated(task.accumulatedFocus))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Theme.horizontalPadding - 4)
        .padding(.vertical, 3)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture { model.selectedTaskID = task.id }
        .onHover { isHovering = $0 }
        .contextMenu { contextMenu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(task.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var subtitle: String? {
        if showsCarryOver { return "From an earlier day" }
        if let estimate = task.estimatedDuration {
            return "Est. \(FocusTimeFormatter.estimate(estimate))"
        }
        if task.status == .skipped { return "Skipped" }
        return nil
    }

    @ViewBuilder
    private var rowActions: some View {
        if task.status.isOpen {
            Button {
                model.start(task.id)
            } label: {
                Image(systemName: "play.fill")
                    .font(.caption)
                    .frame(width: Theme.minimumHitTarget, height: Theme.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .accessibilityLabel("Start \(task.title)")
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if task.status.isOpen {
            Button("Start") { model.start(task.id) }
            Button("Complete") { model.complete(task.id) }
            Button("Skip") { model.skip(task.id) }
        } else {
            Button("Restore") { model.restore(task.id) }
        }
        Button("Edit…") { model.editingTask = task }
        Divider()
        if showsCarryOver {
            Button("Move to today") { model.moveToToday(task.id) }
        } else {
            Button("Move to tomorrow") { model.moveToTomorrow(task.id) }
        }
        Divider()
        Button("Delete", role: .destructive) { model.delete(task.id) }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isSelected ? Theme.accent.opacity(0.16) : (isHovering ? Color.primary.opacity(0.05) : .clear))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent.opacity(0.5) : .clear)
            )
            .padding(.horizontal, 6)
    }

    private var accessibilityValue: String {
        var parts = [task.color.displayName, task.status.accessibilityDescription]
        if task.accumulatedFocus > 0 {
            parts.append("focused \(FocusTimeFormatter.spoken(task.accumulatedFocus))")
        }
        if let estimate = task.estimatedDuration {
            parts.append("estimated \(FocusTimeFormatter.estimate(estimate))")
        }
        if showsCarryOver { parts.append("carried over from an earlier day") }
        return parts.joined(separator: ", ")
    }
}
