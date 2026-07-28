import QuickWinsCore
import SwiftUI

struct QuickAddField: View {
    @ObservedObject var model: AppModel
    @FocusState.Binding var isFocused: Bool

    @State private var draft = ""

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isFocused ? Theme.accent : .secondary)
                .accessibilityHidden(true)

            TextField("Add task", text: $draft)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($isFocused)
                .onSubmit(commit)
                .accessibilityLabel("New task title")
                .accessibilityHint("Press Return to add the task")

            if !draft.isEmpty {
                Button {
                    draft = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, Theme.horizontalPadding)
        .padding(.vertical, 10)
        .background(alignment: .top) { Divider().opacity(0.5) }
        .background(isFocused ? Theme.accent.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }

    private func commit() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        model.addTask(title: title)
        draft = ""
        // Staying focused lets the user list the whole day without reaching for the mouse.
        isFocused = true
    }
}
