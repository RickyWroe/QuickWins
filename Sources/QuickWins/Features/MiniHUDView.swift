import QuickWinsCore
import SwiftUI

/// The compact cursor HUD: a task's colour and its elapsed time, and nothing else.
///
/// Deliberately the smallest useful surface — it answers "what am I on, and for how long?"
/// without the user leaving what they are doing. Anything more belongs in the full panel, which
/// a click opens.
struct MiniHUDView: View {
    @ObservedObject var model: AppModel
    /// False while the HUD follows the pointer, when it is click-through and can never be
    /// hovered or tapped — showing hover affordances then would promise something that cannot
    /// happen.
    let isInteractive: Bool
    let openPanel: () -> Void

    @State private var isHovering = false

    private var task: DailyTask? { model.focusTask }

    var body: some View {
        HStack(spacing: 7) {
            indicator

            if let task {
                Text(FocusTimeFormatter.clock(task.elapsedFocus(at: model.now)))
                    .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                    .foregroundStyle(task.status == .active ? .primary : .secondary)
            } else {
                Text("No task")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.primary.opacity(isHovering ? 0.22 : 0.1))
        )
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        .contentShape(Capsule())
        .onHover { isHovering = isInteractive && $0 }
        .onTapGesture { if isInteractive { openPanel() } }
        .help(isInteractive ? "Open the QuickWins panel" : "")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isInteractive ? [.isButton] : [])
        .accessibilityHint(isInteractive ? "Opens the full task panel" : "")
    }

    /// The task's colour, with the run state carried by a glyph rather than by the colour — the
    /// dot says *which* task, the glyph says *whether it is running*.
    @ViewBuilder
    private var indicator: some View {
        if let task {
            ZStack {
                Circle()
                    .fill(task.color.swatch)
                    .frame(width: 12, height: 12)

                if task.status != .active {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
        } else {
            Circle()
                .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                .frame(width: 12, height: 12)
        }
    }

    private var accessibilityLabel: String {
        guard let task else { return "QuickWins, no task in focus" }
        return [
            task.title,
            task.color.displayName,
            task.status.accessibilityDescription,
            FocusTimeFormatter.spoken(task.elapsedFocus(at: model.now)) + " elapsed",
        ].joined(separator: ", ")
    }
}

extension TaskColor {
    /// Palette resolved at render time so it follows light and dark mode and increased contrast.
    var swatch: Color {
        switch self {
        case .graphite: return Color(nsColor: .systemGray)
        case .red: return Color(nsColor: .systemRed)
        case .orange: return Color(nsColor: .systemOrange)
        case .yellow: return Color(nsColor: .systemYellow)
        case .green: return Color(nsColor: .systemGreen)
        case .teal: return Color(nsColor: .systemTeal)
        case .blue: return Color(nsColor: .systemBlue)
        case .purple: return Color(nsColor: .systemPurple)
        }
    }
}

/// Eight swatches with the selected one marked by a ring and a checkmark, so the choice is not
/// signalled by colour alone.
struct TaskColorPicker: View {
    @Binding var selection: TaskColor

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(TaskColor.allCases) { color in
                Button {
                    selection = color
                } label: {
                    ZStack {
                        Circle()
                            .fill(color.swatch)
                            .frame(width: 20, height: 20)
                        if selection == color {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .overlay(
                        Circle()
                            .strokeBorder(
                                selection == color ? Color.primary.opacity(0.7) : Color.primary.opacity(0.12),
                                lineWidth: selection == color ? 2 : 1
                            )
                            .frame(width: 25, height: 25)
                    )
                    .frame(width: 27, height: 27)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.displayName)
                .accessibilityAddTraits(selection == color ? [.isSelected] : [])
            }
        }
    }
}
