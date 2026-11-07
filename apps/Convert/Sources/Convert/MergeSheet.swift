import ConvertCore
import SlopKit
import SwiftUI

/// Merge videos (or sound files) into one: put them in order, then Merge. The new file goes
/// where converted files go (next to the first file, or the Save To folder).
struct MergeSheet: View {
    @Bindable var model: AppModel
    @State private var order: [URL]
    @State private var phase: Phase = .ready
    @State private var task: Task<Void, Never>?
    @State private var selection: URL?
    @Environment(\.dismiss) private var dismiss

    enum Phase: Equatable {
        case ready
        case running(Double)
        case done(ConversionReport)
        case failed(String)
    }

    init(model: AppModel, files: [URL]) {
        self.model = model
        _order = State(initialValue: files)
    }

    private var isSound: Bool { order.allSatisfy { model.kind(of: $0) == .audio } }

    private var targetTitle: String {
        if isSound { return model.settings.audio.title }
        let video = model.settings.video
        return video == .gif ? VideoTarget.mp4H264.title : video.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Merge \(order.count) Files").font(.title3.weight(.semibold))
            Text("They play one after another, in this order. Drag to reorder.")
                .font(.callout)
                .foregroundStyle(.secondary)
            List(selection: $selection) {
                ForEach(order, id: \.self) { url in
                    HStack {
                        Image(systemName: model.kind(of: url) == .audio ? "waveform" : "film")
                            .foregroundStyle(.secondary)
                            // One column for both symbols, so the names line up.
                            .frame(width: Spacing.l + Spacing.xs / 2)
                            .accessibilityHidden(true)
                        Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if let duration = model.facts(for: url).info?.duration {
                            Text(Durations.string(duration)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .tag(url)
                }
                .onMove { order.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 160)
            .disabled(phase != .ready)
            HStack(spacing: Spacing.s) {
                Button { move(-1) } label: { Image(systemName: "arrow.up") }
                    .help("Move the selected file earlier")
                    .accessibilityLabel("Move Up")
                    .disabled(selection == nil || selection == order.first || phase != .ready)
                Button { move(1) } label: { Image(systemName: "arrow.down") }
                    .help("Move the selected file later")
                    .accessibilityLabel("Move Down")
                    .disabled(selection == nil || selection == order.last || phase != .ready)
                Spacer()
            }
            .controlSize(.small)
            Text("Becomes one \(targetTitle) file named “\(Converter.mergedName(first: order[0]))”, \(DestinationText.short(model.settings.destination).lowercased() == "next to originals" ? "next to the first file" : "in \(DestinationText.short(model.settings.destination))"). Clips of another shape get black bars.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            status
            HStack {
                Spacer()
                switch phase {
                case .ready, .failed:
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Merge") { run() }
                        .keyboardShortcut(.defaultAction)
                case .running:
                    Button("Stop") { task?.cancel() }
                        .keyboardShortcut(.cancelAction)
                case .done(let report):
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([report.output]) }
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(Spacing.xl)
        .frame(width: 480)
        .interactiveDismissDisabled(phase != .ready && !isFinished)
    }

    private var isFinished: Bool {
        if case .done = phase { return true }
        if case .failed = phase { return true }
        return false
    }

    @ViewBuilder private var status: some View {
        switch phase {
        case .ready:
            EmptyView()
        case .running(let fraction):
            ProgressView(value: fraction) { Text("Merging…") }
                .accessibilityLabel("Merging")
        case .done(let report):
            Label("\(report.output.lastPathComponent) · \(report.summary) · \(FileQueueText.bytes(report.bytes))",
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.textOrange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func move(_ step: Int) {
        guard let selection, let index = order.firstIndex(of: selection) else { return }
        let target = index + step
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
    }

    private func run() {
        phase = .running(0)
        let converter = Converter(settings: model.settings, capabilities: model.capabilities)
        let files = order
        model.mergeRunning = true
        task = Task {
            do {
                let report = try await converter.merge(files) { fraction in
                    Task { @MainActor in if case .running = phase { phase = .running(fraction) } }
                }
                phase = .done(report)
                HUD.show("Merged", systemImage: "checkmark.circle")
            } catch is CancellationError {
                phase = .ready
            } catch {
                let e = error as? ConvertError
                phase = .failed([e?.errorDescription, e?.recoverySuggestion].compactMap { $0 }.joined(separator: " ")
                                .ifEmpty(error.localizedDescription))
            }
            model.mergeRunning = false
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
