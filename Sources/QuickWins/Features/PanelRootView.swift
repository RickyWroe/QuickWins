import QuickWinsCore
import SwiftUI

struct PanelRootView: View {
    @ObservedObject var model: AppModel
    /// The exact height the window will be, computed by the controller. Pinned rather than
    /// proposed — see the note on `Theme.panelHeaderHeight`.
    let height: CGFloat
    let dismiss: () -> Void

    @FocusState private var quickAddFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ProgressHeader(model: model)

            Divider().opacity(0.5)

            if let session = model.session, let task = model.focusTask {
                ActiveTaskCard(model: model, task: task, session: session)
            } else {
                EmptyFocusView(hasTasks: !model.tasks.isEmpty) {
                    quickAddFocused = true
                }
            }

            TaskListView(model: model)

            // Any surplus from the height estimate lands here rather than stretching a section.
            Spacer(minLength: 0)

            QuickAddField(model: model, isFocused: $quickAddFocused)
        }
        .frame(width: Theme.panelWidth, height: height)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .overlay(alignment: .top) { banners }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: model.revision)
        .background(keyboardShortcuts)
        .onKeyPress(.upArrow) { handleArrow(-1) }
        .onKeyPress(.downArrow) { handleArrow(1) }
        .onKeyPress(.space) { handleSpace() }
        .onKeyPress(.delete) { handleDelete() }
        .onChange(of: quickAddFocused) { _, focused in
            model.isQuickAddFocused = focused
        }
        .onChange(of: model.isQuickAddFocused) { _, requested in
            if requested != quickAddFocused { quickAddFocused = requested }
        }
        .sheet(item: $model.editingTask) { task in
            TaskEditorView(model: model, task: task)
        }
        .onChange(of: model.editingTask?.id) { _, editing in
            model.isEditingModally = editing != nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("QuickWins task panel")
    }

    // MARK: - Banners

    @ViewBuilder
    private var banners: some View {
        VStack(spacing: 6) {
            if let error = model.lastError {
                PanelBanner(
                    symbol: "exclamationmark.triangle.fill",
                    title: error.message,
                    detail: error.recoverySuggestion,
                    actionTitle: "Dismiss",
                    action: model.clearError
                )
            }
            if model.showStorageWarning {
                PanelBanner(
                    symbol: "externaldrive.badge.exclamationmark",
                    title: model.environment.isUsingFallbackStorage
                        ? "Tasks are not being saved this session."
                        : "The task database was rebuilt after a read error.",
                    detail: model.environment.isUsingFallbackStorage
                        ? "QuickWins could not open its database. Your tasks will be lost when you quit."
                        : "Any previous tasks were kept aside for inspection.",
                    actionTitle: "OK",
                    action: { model.showStorageWarning = false }
                )
            }
            if model.notificationAuthorization == .denied {
                PanelBanner(
                    symbol: "bell.slash",
                    title: "Notifications are turned off.",
                    detail: "Accountability check-ins will appear in this panel only. Enable them in System Settings › Notifications.",
                    actionTitle: nil,
                    action: nil
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    // MARK: - Keyboard

    /// Command-key actions live on zero-size buttons because `keyboardShortcut` is the only
    /// mechanism that participates correctly in SwiftUI's responder chain.
    private var keyboardShortcuts: some View {
        Group {
            Button("Add task") { quickAddFocused = true }
                .keyboardShortcut("n", modifiers: .command)
            Button("Start selected task") { model.startSelected() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Complete active task") { model.completeActive() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
            Button("Undo delete") { model.undoDelete() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.canUndoDelete)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func handleArrow(_ offset: Int) -> KeyPress.Result {
        guard !quickAddFocused else { return .ignored }
        model.moveSelection(by: offset)
        return .handled
    }

    private func handleSpace() -> KeyPress.Result {
        // Space must keep working as space while the user is typing a task title.
        guard !quickAddFocused, model.editingTask == nil else { return .ignored }
        model.toggleActive()
        return .handled
    }

    private func handleDelete() -> KeyPress.Result {
        guard !quickAddFocused, model.selectionTarget != nil else { return .ignored }
        model.deleteSelected()
        return .handled
    }
}

private struct PanelBanner: View {
    let symbol: String
    let title: String
    let detail: String?
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(10)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        )
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyFocusView: View {
    let hasTasks: Bool
    let addTask: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: hasTasks ? "hand.tap" : "checklist")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(hasTasks ? "Nothing in focus" : "No tasks yet")
                .font(.headline)

            Text(hasTasks
                 ? "Pick a task below and press Return to start the timer."
                 : "Add the first thing you want to get done today.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !hasTasks {
                Button("Add a task", action: addTask)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, Theme.horizontalPadding)
        .accessibilityElement(children: .combine)
    }
}
