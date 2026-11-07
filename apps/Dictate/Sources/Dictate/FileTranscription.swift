import AppKit
import DictateCore
import Observation
import SlopKit
import SwiftUI
import UniformTypeIdentifiers

/// Audio and video files waiting for, or done with, transcription. One at a time, through
/// the same model as dictation (so a dictation started meanwhile waits its turn).
@Observable
final class FileTranscriber {
    struct Job: Identifiable {
        enum Status: Equatable {
            case waiting
            case working
            case done(String)
            case failed(String)
        }

        let id = UUID()
        let url: URL
        var status: Status = .waiting
        var duration: String?

        var text: String? {
            if case .done(let text) = status { return text }
            return nil
        }
    }

    private(set) var jobs: [Job] = []
    var selection: UUID?
    @ObservationIgnored private let models: ModelHost
    @ObservationIgnored private var running = false

    static let types: [UTType] = [.audio, .movie, .audiovisualContent]

    init(models: ModelHost) {
        self.models = models
    }

    func add(_ urls: [URL]) {
        let fresh = urls.filter { url in !jobs.contains { $0.url == url && $0.text == nil && $0.status != .working } }
        guard !fresh.isEmpty else { return }
        jobs.append(contentsOf: fresh.map { Job(url: $0) })
        if selection == nil { selection = jobs.first { $0.url == fresh[0] }?.id }
        run()
    }

    /// Shows the open panel.
    func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.types
        panel.allowsMultipleSelection = true
        panel.message = "Choose audio or video files to transcribe."
        panel.prompt = "Transcribe"
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            MainActor.assumeIsolated { self?.add(panel.urls) }
        }
    }

    func remove(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }), job.status != .working else { return }
        jobs.removeAll { $0.id == id }
        if selection == id { selection = jobs.first?.id }
    }

    private func run() {
        guard !running else { return }
        running = true
        Task {
            while let index = jobs.firstIndex(where: { $0.status == .waiting }) {
                let id = jobs[index].id
                update(id) { $0.status = .working }
                let url = jobs[index].url
                let start = Diagnostics.now()
                do {
                    let samples = try await AudioDecoder.decode(url: url)
                    update(id) { $0.duration = AudioDecoder.durationText(sampleCount: samples.count) }
                    guard samples.count >= DictationController.minimumSamples else {
                        update(id) { $0.status = .done("") }
                        continue
                    }
                    let raw = try await models.transcribe(samples)
                    let text = TextCleanup.meaningfulText(raw) ?? ""
                    update(id) { $0.status = .done(text) }
                    Diagnostics.record("file \(url.lastPathComponent) samples=\(samples.count) ms=\(Diagnostics.milliseconds(since: start)) text=\(text)")
                } catch {
                    update(id) { $0.status = .failed(ModelHost.describe(error)) }
                    Diagnostics.record("file failed \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            running = false
        }
    }

    private func update(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }
}

/// Drop or choose files; each gets a plain transcript to copy or save.
struct FileTranscriptionWindow: View {
    let model: AppModel
    @Bindable var files: FileTranscriber
    @State private var isTargeted = false

    private var selectedJob: FileTranscriber.Job? {
        files.jobs.first { $0.id == files.selection }
    }

    var body: some View {
        Group {
            if files.jobs.isEmpty {
                DropZone("Drop audio or video files here", systemImage: "waveform", types: FileTranscriber.types) { urls in
                    files.add(urls)
                }
                .padding(Spacing.xl)
            } else {
                VStack(spacing: 0) {
                    List(files.jobs, selection: $files.selection) { job in
                        JobRow(job: job)
                            .contextMenu {
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([job.url]) }
                                Button("Remove from List") { files.remove(job.id) }
                                    .disabled(job.status == .working)
                            }
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 120, idealHeight: 160)
                    Hairline()
                    transcript
                }
                .dropDestination(for: URL.self) { urls, _ in
                    files.add(urls)
                    return true
                } isTargeted: { isTargeted = $0 }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .toolbar {
            ToolbarItem {
                Button("Add Files…", systemImage: "plus") { files.choose() }
                    .help("Add files (⌘O)")
                    .keyboardShortcut("o")
            }
            ToolbarItem {
                Button("Copy", systemImage: "doc.on.doc") { copy() }
                    .disabled(selectedJob?.text?.isEmpty ?? true)
                    .help("Copy transcript")
            }
            ToolbarItem {
                Button("Save…", systemImage: "square.and.arrow.down") { save() }
                    .disabled(selectedJob?.text?.isEmpty ?? true)
                    .help("Save transcript as text (⌘S)")
                    .keyboardShortcut("s")
            }
        }
        .onCopyCommand {
            guard let text = selectedJob?.text, !text.isEmpty else { return [] }
            return [NSItemProvider(object: text as NSString)]
        }
    }

    @ViewBuilder private var transcript: some View {
        Group {
            switch selectedJob?.status {
            case .done(let text) where text.isEmpty:
                ContentUnavailableView("No Speech Found", systemImage: "waveform.slash",
                                       description: Text("This file seems to be silent or music only."))
            case .done(let text):
                ScrollView {
                    Text(text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.l)
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't Transcribe", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    if model.models.state == .notInstalled {
                        Button("Open Models Settings") { SettingsNavigation.open(.models) }
                    }
                }
            case .working, .waiting:
                VStack(spacing: Spacing.s) {
                    ProgressView().controlSize(.small)
                    Text(selectedJob?.status == .working ? "Transcribing…" : "Waiting…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case nil:
                Text("Select a file to see its transcript.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minHeight: 160)
    }

    private func copy() {
        guard let text = selectedJob?.text, !text.isEmpty else { return }
        model.inserter.copy(text)
        HUD.show("Copied", systemImage: "doc.on.doc")
    }

    private func save() {
        guard let job = selectedJob, let text = job.text else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = job.url.deletingPathExtension().lastPathComponent + ".txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

struct JobRow: View {
    let job: FileTranscriber.Job

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: job.url.path))
                .resizable()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(job.url.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let duration = job.duration {
                Text(duration)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            status
                .frame(minWidth: 70, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var status: some View {
        switch job.status {
        case .waiting: Text("Waiting").foregroundStyle(.secondary)
        case .working: ProgressView().controlSize(.small).accessibilityLabel("Transcribing")
        case .done: Label("Done", systemImage: "checkmark.circle.fill").foregroundStyle(.textGreen)
        case .failed: Label("Failed", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.textOrange)
        }
    }
}
