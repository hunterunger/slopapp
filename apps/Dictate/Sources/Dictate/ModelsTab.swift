import AppKit
import DictateCore
import SlopKit
import SwiftUI

/// Choose, download and remove speech models; choose how long one stays in memory.
struct ModelsTab: View {
    let model: AppModel
    let models: ModelHost
    @State private var pendingRemoval: ModelOption?

    var body: some View {
        @Bindable var settings = model.settings
        ScrollingSettingsForm(height: 560) {
            ForEach(EngineKind.allCases) { engine in
                Section {
                    ForEach(ModelCatalog.options(for: engine)) { option in
                        ModelRow(option: option, models: models,
                                 isSelected: models.selected.key == option.key,
                                 select: { settings.select(option) },
                                 download: { Task { await models.download(option) } },
                                 remove: { pendingRemoval = option })
                    }
                } header: {
                    Text(engine == .parakeet ? "Parakeet" : "Whisper")
                } footer: {
                    Text(engine == .parakeet
                         ? "Fastest and most accurate for everyday dictation. Runs on the Neural Engine of Apple silicon Macs."
                         : "Works on every Mac and in many languages. Larger models are more accurate and slower.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Picker(selection: $settings.modelRetention) {
                    ForEach(ModelRetention.allCases) { Text($0.displayName).tag($0) }
                } label: {
                    Text("Keep the model in memory")
                    Text("Always means dictation starts instantly, for a few hundred MB of memory. Otherwise, the first dictation after a break can take up to 30 seconds while the model reloads.")
                }
                LabeledContent("Now") {
                    Text(stateText)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } footer: {
                HStack(alignment: .top) {
                    Text("Models download from Hugging Face the first time, then work offline. Dictate doesn't use the internet for anything else.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: model.modelsDirectory, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([model.modelsDirectory])
                    }
                }
            }
        }
        .confirmationDialog("Move \(pendingRemoval?.name ?? "") to the Trash?",
                            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let option = pendingRemoval { try? models.remove(option) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("You can download it again any time.")
        }
    }

    private var stateText: String {
        switch models.state {
        case .notInstalled: "\(models.selected.name) isn't downloaded"
        case .downloading(let fraction): "Downloading \(models.selected.name)" + (fraction.map { " \(Int($0 * 100))%" } ?? "…")
        case .unloaded: "\(models.selected.name) loads when you dictate"
        case .loading: "Loading \(models.selected.name)…"
        case .ready: "\(models.selected.name) is loaded"
        case .failed(let message): message
        }
    }
}

struct ModelRow: View {
    let option: ModelOption
    let models: ModelHost
    let isSelected: Bool
    let select: () -> Void
    let download: () -> Void
    let remove: () -> Void

    var body: some View {
        let installed = models.isInstalled(option)
        let progress = models.downloads[option.key]
        LabeledContent {
            HStack(spacing: Spacing.s) {
                if let progress {
                    ProgressView(value: progress ?? 0, total: 1)
                        .progressViewStyle(.linear)
                        .frame(width: 80)
                        .opacity(progress == nil ? 0.4 : 1)
                        .accessibilityLabel("Downloading \(option.name)")
                } else if !models.isSupported(option) {
                    Text("Needs Apple silicon").foregroundStyle(.secondary)
                } else if installed {
                    if isSelected {
                        Label("In Use", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.textGreen)
                    } else {
                        Button("Use", action: select)
                    }
                    Button(action: remove) {
                        Label("Move to Trash", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Move \(option.name) to the Trash")
                    .accessibilityLabel("Move \(option.name) to the Trash")
                } else {
                    Button("Download") {
                        if !isSelected { select() }
                        download()
                    }
                    .help("Download \(option.sizeText) from Hugging Face")
                }
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(option.name)
                if isSelected && !installed && progress == nil {
                    Text("Selected").foregroundStyle(.secondary)
                }
            }
            Text(option.summary)
            Text("\(option.tags.joined(separator: ", ")) · \(option.sizeText)")
            if let error = models.downloadErrors[option.key] {
                Text(error).foregroundStyle(.textRed)
            }
        }
    }
}
