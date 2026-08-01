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
    /// The exact size the window will be. Pinned rather than proposed: a view that asks for a
    /// different size than its window makes SwiftUI resize the window during layout, which
    /// re-enters layout and eventually trips AppKit's display-cycle limit.
    let compactSize: CGSize
    let expandedSize: CGSize
    let openPanel: () -> Void

    @State private var isHovering = false

    private var task: DailyTask? { model.focusTask }
    private var message: String? { model.hudMessage }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
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

            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    // Fixed width, never a flexible `maxWidth`. The hosting controller sizes the
                    // window from this content, so a view that asks for "up to N points of
                    // whatever is available" makes view layout and window resize depend on each
                    // other and recurse until the stack is exhausted. That crashed the app four
                    // times. A fixed width breaks the cycle and keeps a longer line to two rows
                    // rather than one very wide capsule beside the pointer.
                    .frame(width: expandedSize.width - 20, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(
            width: (message == nil ? compactSize : expandedSize).width,
            height: (message == nil ? compactSize : expandedSize).height,
            alignment: .leading
        )
        .background(hudBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(isHovering ? 0.22 : 0.1))
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { isHovering = isInteractive && $0 }
        .onTapGesture { if isInteractive { openPanel() } }
        .help(isInteractive ? "Open the QuickWins panel" : "")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isInteractive ? [.isButton] : [])
        .accessibilityHint(isInteractive ? "Opens the full task panel" : "")
    }

    /// A live material backdrop must be re-blurred against whatever is behind it every time the
    /// window moves, which is ruinous at pointer speed. While following, a flat translucent fill
    /// is used instead; when parked, the material returns.
    private var hudBackground: AnyShapeStyle {
        isInteractive ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color(nsColor: .windowBackgroundColor).opacity(0.92))
    }

    /// The task's colour, with the run state carried by a glyph rather than by the colour — the
    /// dot says *which* task, the glyph says *whether it is running*.
    @ViewBuilder
    private var indicator: some View {
        if model.settings.petEnabled {
            PetView(
                state: model.petState,
                color: task?.color.swatch ?? Color(nsColor: .systemGray),
                vitality: model.petVitality,
                size: 16
            )
        } else if let task {
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
        var parts = [
            task.title,
            task.color.displayName,
            task.status.accessibilityDescription,
            FocusTimeFormatter.spoken(task.elapsedFocus(at: model.now)) + " elapsed",
        ]
        // The pet is decorative to VoiceOver; its meaning is spoken here instead.
        if model.settings.petEnabled { parts.append(model.petState.accessibilityDescription) }
        if let message { parts.append(message) }
        return parts.joined(separator: ", ")
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
