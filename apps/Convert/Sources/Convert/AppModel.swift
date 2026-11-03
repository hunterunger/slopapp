import AppKit
import ConvertCore
import Observation
import SlopKit

/// Facts about one row, observed per file so a probe finishing redraws only its own row.
@MainActor
@Observable
final class RowFacts {
    var info: MediaInfo?
    /// The target it's being converted to, set when its conversion starts.
    var runningTarget: String?
    /// What it is (once read) and the settings its last run used.
    var kind: MediaKind?
    var signature: String?
    var report: ConversionReport?
}

/// App state: the settings (persisted), the queue that uses them, and per-file facts.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let queue: FileQueue
    var selection: Set<FileQueueItem.ID> = []
    /// Space bar Quick Look.
    var previewURL: URL?
    let capabilities = Capabilities.system

    var settings: ConvertSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
            queue.processor = makeProcessor()
        }
    }
    private(set) var recentFolders: [URL]

    @ObservationIgnored private var facts: [String: RowFacts] = [:]
    @ObservationIgnored private let restoreBook = RestoreBook()
    /// The window's undo manager, set by the main view.
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private let keepAwake = KeepAwake(reason: "Convert is converting files")
    @ObservationIgnored private var batchStart: Date?

    private static let settingsKey = "settings"
    private static let recentFoldersKey = "recentFolders"
    static let playSoundKey = "playSoundWhenDone"

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Self.playSoundKey: true])
        var loaded = defaults.data(forKey: Self.settingsKey)
            .flatMap { try? JSONDecoder().decode(ConvertSettings.self, from: $0) } ?? ConvertSettings()
        // A format this Mac can't write (settings copied from a newer Mac) falls back.
        if !capabilities.canWrite(loaded.image) { loaded.image = .jpeg }
        if !capabilities.canWrite(loaded.video) { loaded.video = .mp4H264 }
        settings = loaded
        recentFolders = (defaults.stringArray(forKey: Self.recentFoldersKey) ?? []).map { URL(fileURLWithPath: $0) }
        queue = FileQueue(processor: ConvertProcessor(converter: Converter(settings: loaded), events: .ignored),
                          acceptedTypes: MediaTypes.accepted)
        queue.processor = makeProcessor()
        queue.unsupportedReason = { url in
            let error = ConvertError.unsupported(name: url.lastPathComponent)
            return [error.errorDescription, error.recoverySuggestion].compactMap { $0 }.joined(separator: " ")
        }
        // Videos share the Mac's media engines: one or two at a time. Images run wide.
        queue.lane = { MediaTypes.kind(of: $0)?.rawValue }
        queue.laneLimits = [
            MediaKind.video.rawValue: ProcessInfo.processInfo.activeProcessorCount >= 10 ? 2 : 1,
            MediaKind.audio.rawValue: 4,
        ]
        queue.onBusy = { [weak self] in self?.batchStarted() }
        queue.onIdle = { [weak self] in self?.batchFinished() }
    }

    private func makeProcessor() -> ConvertProcessor {
        let events = ConvertEvents(
            started: { url, kind, target, signature in
                Task { @MainActor in AppModel.shared.started(url, kind: kind, target: target, signature: signature) }
            },
            finished: { url, report in Task { @MainActor in AppModel.shared.finished(url, report: report) } }
        )
        return ConvertProcessor(converter: Converter(settings: settings, capabilities: capabilities), events: events,
                                restore: restoreBook)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }

    // MARK: Row facts

    private static func key(_ url: URL) -> String { url.standardizedFileURL.path }

    func facts(for item: FileQueueItem) -> RowFacts {
        let key = Self.key(item.input)
        if let existing = facts[key] { return existing }
        let new = RowFacts()
        facts[key] = new
        return new
    }

    private func started(_ url: URL, kind: MediaKind, target: String, signature: String) {
        guard let row = facts[Self.key(url)] else { return }
        row.runningTarget = target
        row.kind = kind
        row.signature = signature
        row.report = nil
    }

    /// Finished rows made with settings that have changed since (another format, quality,
    /// size or destination for their kind).
    var outdatedItems: [FileQueueItem] {
        queue.items.filter { item in
            guard case .finished = item.state, let row = facts[Self.key(item.input)],
                  let kind = row.kind, let used = row.signature else { return false }
            return used != settings.signature(for: kind)
        }
    }

    private func finished(_ url: URL, report: ConversionReport?) {
        facts[Self.key(url)]?.report = report
    }

    /// Reads media facts for new rows in the background, one at a time.
    private func probe(_ items: [FileQueueItem]) {
        let jobs = items.filter { !$0.state.isFailure }.map { (facts(for: $0), $0.input) }
        guard !jobs.isEmpty else { return }
        Task.detached(priority: .utility) {
            for (row, url) in jobs {
                let info = try? await MediaProbe.probe(url)
                await MainActor.run { row.info = info }
            }
        }
    }

    /// The extra facts on a row: what it is and what it becomes, then what it became.
    func detail(for item: FileQueueItem) -> String? {
        let row = facts(for: item)
        switch item.state {
        case .waiting, .working:
            let kind = row.info?.kind ?? MediaTypes.kind(of: item.input)
            let target: String? = {
                if case .working = item.state, let running = row.runningTarget { return running }
                return kind.map(settings.targetTitle(for:))
            }()
            var text = [row.info?.summary, target.map { "→ \($0)" }].compactMap { $0 }.filter { !$0.isEmpty }
                .joined(separator: " ")
            if kind == .video, settings.video == .gif, let duration = row.info?.duration,
               duration > QualityTable.longGIFSeconds {
                text += " · \(GIFText.longClip)"
            }
            return text.isEmpty ? nil : text
        case .finished(.produced(_, let bytes)):
            guard let report = row.report else { return nil }
            var parts = [report.summary]
            if report.repackaged { parts.append("No quality loss") }
            parts += report.notes
            if let before = item.originalBytes, before > 0, Double(bytes) > Double(before) * 1.05 {
                parts.append("Bigger than the original: " + biggerReason(row: row))
            }
            return parts.joined(separator: " · ")
        default:
            return nil
        }
    }

    // MARK: Window

    @ObservationIgnored private var openMainWindow: (() -> Void)?

    /// Called by the menu commands, which have SwiftUI's `openWindow`.
    func registerOpenWindow(_ open: @escaping () -> Void) {
        openMainWindow = open
    }

    /// Brings the main window forward, reopening it if it was closed.
    func showMainWindow() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true && $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
        NSApp.activate()
    }

    /// Why a converted file came out bigger, in a few words.
    private func biggerReason(row: RowFacts) -> String {
        let target = row.runningTarget ?? ""
        if ["WAV", "AIFF", "Apple Lossless (M4A)", "PNG", "TIFF", "MOV (ProRes 422)", "Audio Only (WAV)"].contains(target) {
            return "\(target) keeps every detail, so it needs more space"
        }
        if target == "GIF" { return "GIF stores each frame as a picture" }
        if target == "MP4 (H.264)", let codec = row.info?.videoCodec, ["hvc1", "hev1", "av01"].contains(codec) {
            return "H.264 needs more space than \(Codecs.videoName(codec)). Choose MP4 (HEVC) to stay small"
        }
        if row.signature?.contains(Quality.best.rawValue) == true {
            return "Best keeps more detail. Choose Balanced or Smaller to shrink it"
        }
        return "choose Smaller under Quality to shrink it"
    }

    // MARK: Files

    func add(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            let added = await queue.add(urls)
            if added.isEmpty {
                HUD.show("Already in the list", systemImage: "doc.on.doc")
            } else {
                probe(added)
            }
        }
    }

    func chooseFiles() {
        FileQueueActions.chooseFiles(types: MediaTypes.accepted + [.folder]) { [weak self] in self?.add($0) }
    }

    /// The clipboard. Scripted tests set CONVERT_PASTEBOARD to a private pasteboard name so
    /// they never touch the real one.
    private var pasteboard: NSPasteboard {
        ProcessInfo.processInfo.environment["CONVERT_PASTEBOARD"].map { NSPasteboard(name: .init($0)) } ?? .general
    }

    /// ⌘V: adds files copied in Finder.
    func paste() {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                                    options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if urls.isEmpty {
            HUD.show("No files to paste", systemImage: "doc.on.clipboard")
        } else {
            add(urls)
        }
    }

    /// ⌘C: copies the converted files (to paste into Finder, Mail, chats).
    func copyOutputs() {
        let urls = targetItems.compactMap(\.output)
        guard !urls.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        HUD.show(urls.count == 1 ? "Copied" : "Copied \(urls.count) files", systemImage: "doc.on.doc")
    }

    var canCopy: Bool { targetItems.contains { $0.output != nil } }

    var selectedItems: [FileQueueItem] {
        queue.items.filter { selection.contains($0.id) }
    }

    /// The selection, or everything when nothing is selected.
    var targetItems: [FileQueueItem] {
        selectedItems.isEmpty ? queue.items : selectedItems
    }

    func revealTargets() {
        let items = targetItems.filter { $0.output != nil }
        FileQueueActions.reveal(items.isEmpty ? targetItems : items)
    }

    /// With a selection: exactly the selected rows. Without: rows whose settings changed,
    /// plus failed and stopped ones. Each replaces its own earlier output, so nothing piles up.
    func convertAgain() {
        let items = selectedItems.isEmpty
            ? outdatedItems + queue.items.filter { $0.canRetry && ($0.state.isFailure || $0.state == .cancelled) }
            : selectedItems.filter(\.canRetry)
        items.forEach(queue.retry)
    }

    var convertAgainTitle: String {
        selectedItems.isEmpty ? "Convert Again" : (selectedItems.count == 1 ? "Convert Selected File Again" : "Convert Selected Again")
    }

    var canConvertAgain: Bool {
        selectedItems.isEmpty
            ? !outdatedItems.isEmpty || queue.items.contains { $0.canRetry && ($0.state.isFailure || $0.state == .cancelled) }
            : selectedItems.contains(where: \.canRetry)
    }

    func selectAll() {
        selection = Set(queue.items.map(\.id))
    }

    /// Asks first while files are still converting (clearing stops them).
    func clearList() {
        let unfinished = queue.items.filter(\.isActive).count
        if unfinished > 0 {
            let alert = NSAlert()
            alert.messageText = unfinished == 1 ? "Stop converting and clear the list?" : "Stop \(unfinished) conversions and clear the list?"
            alert.informativeText = "Files that haven't finished won't be saved. Finished files and your originals aren't affected."
            alert.addButton(withTitle: "Clear List")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        removeFromList(queue.items, actionName: "Clear List")
    }

    /// Takes rows off the list (stopping any still converting). Undo puts them back as they
    /// were, without converting anything again; files on disk are never touched.
    func removeFromList(_ items: [FileQueueItem], actionName: String = "Remove from List") {
        guard !items.isEmpty else { return }
        pendingRemoval = (snapshot(items), actionName)
        queue.remove(items)
        selection.subtract(items.map(\.id))
        rowsChanged()
    }

    @ObservationIgnored private var known: [FileQueueItem.ID: FileQueueItem] = [:]
    @ObservationIgnored private var knownOrder: [FileQueueItem.ID] = []
    @ObservationIgnored private var pendingRemoval: ([(URL, RestoreBook.Entry?)], String)?

    /// Called whenever the rows change, by any route (the File menu, the Delete key, the
    /// right-click menu): rows that disappeared get an Undo.
    func rowsChanged() {
        let current = queue.items
        let ids = Set(current.map(\.id))
        let removed = knownOrder.filter { !ids.contains($0) }.compactMap { known[$0] }
        known = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        knownOrder = current.map(\.id)
        guard !removed.isEmpty else { return }
        let (entries, actionName) = pendingRemoval ?? (snapshot(removed), "Remove from List")
        pendingRemoval = nil
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.restore(entries, actionName: actionName) }
        }
        undoManager?.setActionName(actionName)
    }

    private func snapshot(_ items: [FileQueueItem]) -> [(URL, RestoreBook.Entry?)] {
        items.map { item in
            switch item.state {
            case .finished(let outcome): (item.input, .outcome(outcome))
            case .failed(let message): (item.input, .failed(message, final: !item.canRetry))
            case .cancelled: (item.input, .cancelled)
            case .waiting, .working: (item.input, nil) // put back to convert again
            }
        }
    }

    private func restore(_ snapshot: [(URL, RestoreBook.Entry?)], actionName: String) {
        for (url, entry) in snapshot {
            if let entry { restoreBook.store(entry, for: url) } else { restoreBook.forget(url) }
        }
        let urls = snapshot.map(\.0)
        // Registered now (while undoing) so it lands on the redo stack: Redo takes them off again.
        let paths = Set(urls.map { $0.standardizedFileURL.path })
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.removeFromList(model.queue.items.filter { paths.contains($0.input.standardizedFileURL.path) },
                                     actionName: actionName)
            }
        }
        undoManager?.setActionName(actionName)
        Task {
            await queue.add(urls)
            await queue.waitUntilIdle()
            urls.forEach(restoreBook.forget)
        }
    }

    func toggleQuickLook() {
        if previewURL != nil {
            previewURL = nil
        } else if let item = selectedItems.first ?? queue.items.first {
            previewURL = item.revealURL
        }
    }

    // MARK: Batches

    private func batchStarted() {
        batchStart = Date()
        keepAwake.update(busy: true)
    }

    private func batchFinished() {
        keepAwake.update(busy: false)
        // Hand big decode buffers back to the system now rather than whenever.
        malloc_zone_pressure_relief(nil, 0)
        let took = batchStart.map { Date().timeIntervalSince($0) } ?? 0
        batchStart = nil
        let anyDone = queue.items.contains { $0.output != nil }
        // Instant jobs stay quiet; a long one (or one finished while you were elsewhere)
        // gets the system sound and a single Dock bounce.
        if anyDone, took >= 3 || !NSApp.isActive, UserDefaults.standard.bool(forKey: Self.playSoundKey) {
            NSSound(named: "Glass")?.play()
        }
        if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
    }

    var isKeepingAwake: Bool { keepAwake.isHolding }

    // MARK: Destination

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Save Here"
        panel.message = "Choose where converted files go."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.useFolder(url) }
        }
    }

    func useFolder(_ url: URL) {
        settings.destination = .folder(url)
        recentFolders.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        recentFolders.insert(url, at: 0)
        recentFolders = Array(recentFolders.prefix(4))
        UserDefaults.standard.set(recentFolders.map(\.path), forKey: Self.recentFoldersKey)
    }

    // MARK: Labels

    var summaryText: String {
        let s = queue.summary
        guard s.total > 0 else { return "" }
        if s.remaining > 0 {
            return "Converting… \(s.done) of \(s.total) done"
        }
        var parts = [s.total == 1 ? "1 file" : "\(s.total) files"]
        if s.produced > 0, s.produced < s.total { parts.append("\(s.produced) converted") }
        if s.failed > 0 { parts.append("\(s.failed) failed") }
        return parts.joined(separator: " · ")
    }
}

extension FileQueueItem.State {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
