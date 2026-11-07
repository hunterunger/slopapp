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
            FooterBar {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
                Spacer(minLength: Spacing.s)
                // One slot for both titles, so the button doesn't change width.
                ZStack(alignment: .trailing) {
                    Button("Stop All") { model.queue.cancelAll() }
                        .keyboardShortcut(.cancelAction)
                        .opacity(model.queue.isBusy ? 1 : 0)
                        .disabled(!model.queue.isBusy)
                        .accessibilityHidden(!model.queue.isBusy)
                    Button("Clear List") { model.clearQueue() }
                        .opacity(model.queue.isBusy ? 0 : 1)
                        .disabled(model.queue.isBusy)
                        .accessibilityHidden(model.queue.isBusy)
                }
                .controlSize(.small)
            }
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
