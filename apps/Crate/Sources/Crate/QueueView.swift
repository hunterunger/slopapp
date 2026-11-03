import CrateCore
import SlopKit
import SwiftUI

/// Several archives extracting at once, one row each.
struct QueueView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            FileQueueView(
                queue: model.queue,
                selection: $model.queueSelection,
                dropTitle: "Drop archives here",
                dropSymbol: "archivebox",
                onFiles: { model.open($0) }
            )
            .fileQueueSizeStyle(.neutral)
            .fileQueueDetail { item in
                guard case .finished = item.state else { return nil }
                return AppModel.shared.queueResults[item.input.standardizedFileURL.path]
            }
            .fileQueueRetryTitle("Extract Again")
            Divider()
            HStack {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                if model.queue.isBusy {
                    Button("Stop All") { model.queue.cancelAll() }
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button("Clear List") { model.clearQueue() }
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m)
        }
        .navigationTitle("Crate")
        .navigationSubtitle(model.queue.isBusy ? "Extracting" : "")
    }

    private var summary: String {
        let s = model.queue.summary
        if s.remaining > 0 {
            return "Extracting \(min(s.done + 1, s.total)) of \(s.total)…"
        }
        var parts = [s.total == 1 ? "1 archive" : "\(s.total) archives"]
        if s.produced > 0 { parts.append("\(s.produced) extracted") }
        if s.failed > 0 { parts.append("\(s.failed) failed") }
        if s.cancelled > 0 { parts.append("\(s.cancelled) stopped") }
        return parts.joined(separator: " · ")
    }
}
