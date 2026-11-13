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
        /// The transcript with word timings, for subtitles.
        var timed: TimedTranscript?

        var text: String? {
            if case .done(let text) = status { return text }
            return nil
        }

        var isFinished: Bool {
            switch status {
            case .done, .failed: true
            case .waiting, .working: false
            }
        }
    }

    private(set) var jobs: [Job] = []
    var selection = Set<UUID>()
    @ObservationIgnored private let models: ModelHost
    @ObservationIgnored private var running = false

    static let types: [UTType] = [.audio, .movie, .audiovisualContent]

    init(models: ModelHost) {
        self.models = models
    }

    /// The one selected file, when exactly one is.
    var selectedJob: Job? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return jobs.first { $0.id == id }
    }

    func add(_ urls: [URL]) {
        let fresh = urls.filter { url in !jobs.contains { $0.url == url && $0.text == nil && $0.status != .working } }
        guard !fresh.isEmpty else { return }
        jobs.append(contentsOf: fresh.map { Job(url: $0) })
        if selection.isEmpty, let first = jobs.first(where: { $0.url == fresh[0] }) { selection = [first.id] }
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

    /// Takes files off the list (never the one being transcribed). The files stay where they are.
    func remove(_ ids: Set<UUID>) {
        let removable = Set(jobs.filter { ids.contains($0.id) && $0.status != .working }.map(\.id))
        guard !removable.isEmpty else { return }
        let firstIndex = jobs.firstIndex { removable.contains($0.id) } ?? 0
        jobs.removeAll { removable.contains($0.id) }
        selection.subtract(removable)
        if selection.isEmpty, !jobs.isEmpty { selection = [jobs[min(firstIndex, jobs.count - 1)].id] }
    }

    /// Takes every finished (done or failed) file off the list.
    func clearFinished() {
        remove(Set(jobs.filter(\.isFinished).map(\.id)))
    }

    var hasFinished: Bool { jobs.contains(where: \.isFinished) }

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
                    let seconds = Double(samples.count) / AudioDecoder.sampleRate
                    let timed = try await models.transcribeTimed(samples).cleaned(duration: seconds)
                    let text = timed?.text ?? ""
                    update(id) {
                        $0.timed = timed
                        $0.status = .done(text)
                    }
                    Diagnostics.record("file \(url.lastPathComponent) samples=\(samples.count) words=\(timed?.words.count ?? 0) ms=\(Diagnostics.milliseconds(since: start)) text=\(text)")
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

/// What File › Save Transcript… acts on, from the Transcribe window in front.
struct TranscriptActions {
    var canSave: Bool
    var save: () -> Void
}

extension FocusedValues {
    @Entry var transcriptActions: TranscriptActions?
}

/// Drop or choose files; each gets a transcript to copy, or save as text or subtitles.
struct FileTranscriptionWindow: View {
    let model: AppModel
    @Bindable var files: FileTranscriber
    @State private var isTargeted = false

    private var selectedJob: FileTranscriber.Job? { files.selectedJob }

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
                        JobRow(job: job, isSelected: files.selection.contains(job.id))
                    }
                    .listStyle(.inset)
                    .contextMenu(forSelectionType: UUID.self) { ids in
                        contextMenu(for: ids)
                    }
                    .onDeleteCommand { files.remove(files.selection) }
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
            }
            ToolbarItem {
                Button("Remove from List", systemImage: "minus") { files.remove(files.selection) }
                    .disabled(!canRemove(files.selection))
                    .help("Remove from the list (Delete). The files stay where they are.")
            }
            ToolbarItem {
                Button("Copy", systemImage: "doc.on.doc") { copy() }
                    .disabled(selectedJob?.text?.isEmpty ?? true)
                    .help("Copy transcript (⌘C)")
            }
            ToolbarItem {
                Button("Save…", systemImage: "square.and.arrow.down") { save() }
                    .disabled(selectedJob?.text?.isEmpty ?? true)
                    .help("Save transcript as text or subtitles (⌘S)")
            }
        }
        .focusedSceneValue(\.transcriptActions,
                           TranscriptActions(canSave: !(selectedJob?.text?.isEmpty ?? true), save: save))
        .onCopyCommand {
            guard let text = selectedJob?.text, !text.isEmpty else { return [] }
            return [NSItemProvider(object: text as NSString)]
        }
    }

    @ViewBuilder private func contextMenu(for ids: Set<UUID>) -> some View {
        let jobs = files.jobs.filter { ids.contains($0.id) }
        if !jobs.isEmpty {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(jobs.map(\.url)) }
            if jobs.count == 1, let job = jobs.first, let text = job.text, !text.isEmpty {
                Button("Copy Transcript") {
                    model.inserter.copy(text)
                    HUD.show("Copied", systemImage: "doc.on.doc")
                }
                Button("Save Transcript…") { save(job) }
            }
            Divider()
            Button(jobs.count == 1 ? "Remove from List" : "Remove \(jobs.count) Files from List") { files.remove(ids) }
                .disabled(!canRemove(ids))
        }
        if files.hasFinished {
            Button("Clear Finished") { files.clearFinished() }
        }
    }

    private func canRemove(_ ids: Set<UUID>) -> Bool {
        files.jobs.contains { ids.contains($0.id) && $0.status != .working }
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
                Text(files.selection.count > 1 ? "\(files.selection.count) files selected." : "Select a file to see its transcript.")
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
        guard let job = selectedJob else { return }
        save(job)
    }

    /// Plain text, or subtitles (SRT, WebVTT) timed from the words.
    private func save(_ job: FileTranscriber.Job) {
        guard let text = job.text, !text.isEmpty else { return }
        let timed = job.timed ?? TimedTranscript(text: text)
        let stored = Diagnostics.defaults.string(forKey: "transcriptFormat").flatMap(TranscriptFormat.init(rawValue:))
        let picker = SavePanelFormatPicker(
            formats: TranscriptFormat.allCases.map { .init(name: $0.displayName, type: $0.contentType, tag: $0.rawValue) },
            selected: (stored ?? .plainText).rawValue)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = job.url.deletingPathExtension().lastPathComponent
        // Test runs save next to their data, never into someone's Documents.
        if let folder = Diagnostics.dataDirectory { panel.directoryURL = folder }
        picker.attach(to: panel)
        panel.begin { response in
            MainActor.assumeIsolated {
                guard response == .OK, let url = panel.url,
                      let format = TranscriptFormat(rawValue: picker.selectedTag) else { return }
                Diagnostics.defaults.set(format.rawValue, forKey: "transcriptFormat")
                do {
                    try format.render(timed).write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    HUD.show("Couldn't save \(url.lastPathComponent). Try another folder.",
                             systemImage: "exclamationmark.triangle", duration: .seconds(3))
                }
            }
        }
    }
}

extension TranscriptFormat {
    var contentType: UTType {
        switch self {
        case .plainText: .plainText
        case .subRip: UTType(filenameExtension: "srt", conformingTo: .text) ?? .plainText
        case .webVTT: UTType(filenameExtension: "vtt", conformingTo: .text) ?? .plainText
        }
    }
}

struct JobRow: View {
    let job: FileTranscriber.Job
    /// Selected rows have an accent background: status colours give way to the row's text
    /// colour there (orange on blue is hard to read).
    var isSelected = false

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: job.url.path))
                .resizable()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(job.url.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
                // Row separators start under the name, not under the last label in the row.
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
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

    private var onAccent: Bool { isSelected }

    @ViewBuilder private var status: some View {
        switch job.status {
        case .waiting: Text("Waiting").foregroundStyle(.secondary)
        case .working: ProgressView().controlSize(.small).accessibilityLabel("Transcribing")
        case .done:
            Label("Done", systemImage: "checkmark.circle.fill")
                .foregroundStyle(onAccent ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(Color.textGreen))
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(onAccent ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(Color.textOrange))
        }
    }
}
