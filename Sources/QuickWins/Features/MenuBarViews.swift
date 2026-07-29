import QuickWinsCore
import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbolName)
            if let text = trailingText {
                Text(text)
                    .font(.system(size: 12).monospacedDigit())
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var symbolName: String {
        guard let task = model.focusTask else { return "circle.dashed" }
        if model.isSnoozed { return "moon.zzz.fill" }
        switch task.status {
        case .active:
            return model.accountabilityLevel >= .gentle ? "bell.badge.fill" : "record.circle.fill"
        case .paused:
            return "pause.circle.fill"
        default:
            return "circle.dashed"
        }
    }

    /// Kept short on purpose — a wide menu-bar item crowds out everything else.
    private var trailingText: String? {
        guard let task = model.focusTask else { return nil }
        switch model.settings.menuBarDisplay {
        case .iconOnly:
            return nil
        case .iconAndTime:
            return FocusTimeFormatter.abbreviated(task.elapsedFocus(at: model.now))
        case .iconAndTitle:
            let limit = 14
            return task.title.count > limit ? String(task.title.prefix(limit - 1)) + "…" : task.title
        }
    }

    private var accessibilityLabel: String {
        guard let task = model.focusTask else { return "QuickWins, no task in focus" }
        let elapsed = FocusTimeFormatter.spoken(task.elapsedFocus(at: model.now))
        return "QuickWins, \(task.title), \(task.status.accessibilityDescription), \(elapsed) elapsed"
    }
}

struct MenuBarContent: View {
    @ObservedObject var model: AppModel
    let openPanel: () -> Void
    let toggleHUD: () -> Void
    let hudIsVisible: Bool

    var body: some View {
        if let task = model.focusTask {
            Text(task.title)
            Text("\(FocusTimeFormatter.abbreviated(task.elapsedFocus(at: model.now))) elapsed · \(task.status.accessibilityDescription)")
            Divider()

            Button(task.status == .active ? "Pause" : "Start") {
                model.toggleActive()
            }
            Button("Complete task") {
                model.complete(task.id)
            }
        } else {
            Text("No task in focus")
            Divider()
        }

        Button("Open task panel") { openPanel() }
            .keyboardShortcut("o", modifiers: [.command, .shift])

        Button(hudIsVisible ? "Hide mini HUD" : "Show mini HUD") { toggleHUD() }

        if !model.tasks.isEmpty {
            Menu("Today's tasks") {
                ForEach(model.tasks) { task in
                    Button {
                        model.start(task.id)
                    } label: {
                        Text("\(task.status == .completed ? "✓ " : "")\(task.title)")
                    }
                    .disabled(!task.status.isOpen)
                }
            }
        }

        Menu("Snooze alerts") {
            ForEach(SnoozeDuration.allCases, id: \.self) { duration in
                Button(duration.label) { model.snooze(duration) }
            }
            if model.isSnoozed {
                Divider()
                Button("End snooze") { model.clearSnooze() }
            }
        }

        Divider()

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Quit QuickWins") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
