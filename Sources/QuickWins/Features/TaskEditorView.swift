import QuickWinsCore
import SwiftUI

struct TaskEditorView: View {
    @ObservedObject var model: AppModel
    let task: DailyTask

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var notes: String
    @State private var estimateMinutes: Double
    @State private var hasEstimate: Bool
    @State private var idleDetectionEnabled: Bool
    @State private var color: TaskColor

    init(model: AppModel, task: DailyTask) {
        self.model = model
        self.task = task
        _title = State(initialValue: task.title)
        _notes = State(initialValue: task.notes ?? "")
        _hasEstimate = State(initialValue: task.estimatedDuration != nil)
        _estimateMinutes = State(initialValue: (task.estimatedDuration ?? 1_800) / 60)
        _idleDetectionEnabled = State(initialValue: task.idleDetectionEnabled)
        _color = State(initialValue: task.color)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit task")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 4) {
                Text("Title").font(.caption).foregroundStyle(.secondary)
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Task title")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Notes").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $notes)
                    .font(.callout)
                    .frame(height: 64)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.15))
                    )
                    .accessibilityLabel("Task notes")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Colour").font(.caption).foregroundStyle(.secondary)
                TaskColorPicker(selection: $color)
            }

            Toggle("Estimated duration", isOn: $hasEstimate)
            if hasEstimate {
                HStack {
                    Slider(value: $estimateMinutes, in: 5...240, step: 5)
                        .accessibilityLabel("Estimated minutes")
                        .accessibilityValue("\(Int(estimateMinutes)) minutes")
                    Text(FocusTimeFormatter.estimate(estimateMinutes * 60))
                        .font(.callout.monospacedDigit())
                        .frame(width: 56, alignment: .trailing)
                }
            }

            Toggle("Inactivity check-ins", isOn: $idleDetectionEnabled)
                .help("Turn this off for tasks like reading or watching, where low input is expected.")

            Divider()

            HStack {
                Button("Delete", role: .destructive) {
                    model.delete(task.id)
                    dismiss()
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedTitle.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 340)
        .onDisappear { model.editingTask = nil }
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        model.update(
            task.id,
            title: trimmedTitle,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            estimatedDuration: hasEstimate ? estimateMinutes * 60 : nil
        )
        if idleDetectionEnabled != task.idleDetectionEnabled {
            model.setIdleDetection(idleDetectionEnabled, for: task.id)
        }
        if color != task.color {
            model.setColor(color, for: task.id)
        }
        dismiss()
    }
}
