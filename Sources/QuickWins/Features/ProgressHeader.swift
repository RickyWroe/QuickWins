import QuickWinsCore
import SwiftUI

struct ProgressHeader: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let progress = model.progress

        HStack(alignment: .firstTextBaseline) {
            Text("TODAY")
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            Text("\(progress.completed)/\(progress.total)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(progress.total > 0 && progress.completed == progress.total ? Theme.accent : .secondary)

            Spacer(minLength: 8)

            if model.isSnoozed {
                Label("Snoozed", systemImage: "moon.zzz.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .accessibilityLabel("Accountability alerts are snoozed")
            } else if progress.focusedSeconds > 0 {
                Text(FocusTimeFormatter.abbreviated(progress.focusedSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Focused \(FocusTimeFormatter.spoken(progress.focusedSeconds)) today")
            }
        }
        .padding(.horizontal, Theme.horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's progress: \(progress.completed) of \(progress.total) tasks complete")
    }
}
