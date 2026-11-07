import AppKit
import ConvertCore
import Observation
import SlopKit

/// Facts about one row, observed per file so a probe finishing redraws only its own row.
@MainActor
@Observable
final class RowFacts {
    var info: MediaInfo?
    /// Why it can't be read (shown on cards still waiting for Start).
    var readError: String?
    /// The target it's being converted to, set when its conversion starts.
    var runningTarget: String?
    /// What it is (once read) and the settings its last run used.
    var kind: MediaKind?
    var signature: String?
    var report: ConversionReport?
    /// The file's own format, trim, turn and sound (mirrors the processor's book).
    var options = FileOptions()
    /// Its original went to the Trash after converting (Settings ▸ When Done).
    var trashedOriginal = false
}

/// A file added while "Start converting as soon as files are added" is off: it waits as a
/// card until Start, so its format, trim or turn can be set first.
@MainActor
@Observable
final class StagedFile: Identifiable {
    nonisolated let id = UUID()
    let input: URL
    let bytes: Int64?

    init(input: URL, bytes: Int64?) {
        self.input = input
        self.bytes = bytes
    }
}

/// One card: a file waiting for Start, or one in the queue.
@MainActor
enum CardEntry: Identifiable {
    case staged(StagedFile)
    case item(FileQueueItem)

    nonisolated var id: UUID {
        switch self {
        case .staged(let file): file.id
        case .item(let item): item.id
        }
    }

    var input: URL {
        switch self {
        case .staged(let file): file.input
        case .item(let item): item.input
        }
    }

    var item: FileQueueItem? {
        if case .item(let item) = self { return item }
        return nil
    }
}

/// The cards of one kind under their header (Video, Audio, Images; files Convert can't
/// take are under "Other").
struct CardGroup: Identifiable {
    var kind: MediaKind?
    var entries: [CardEntry]
    var id: String { kind?.rawValue ?? "other" }

    var title: String {
        switch kind {
        case .video: "Video"
        case .audio: "Audio"
        case .image: "Images"
        case nil: "Other"
        }
    }
}

/// App state: the settings (persisted), the queue that uses them, and per-file facts.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let queue: FileQueue
    var selection: Set<FileQueueItem.ID> = []
    /// The card the arrow keys last moved to (kept in view).
    var selectionLead: FileQueueItem.ID?
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
    @ObservationIgnored let optionsBook = OptionsBook()
    /// Files waiting for Start (only when "Start converting as soon as files are added" is off).
    var staged: [StagedFile] = []
    /// Groups the user folded away.
    var collapsedGroups: Set<String> = []
    /// Saved presets.
    var presets: PresetLibrary {
        didSet {
            if let data = try? JSONEncoder().encode(presets) { UserDefaults.standard.set(data, forKey: Self.presetsKey) }
        }
    }
    /// A merge is running (it keeps the Mac awake like a batch does).
    var mergeRunning = false {
        didSet { keepAwake.update(busy: queue.isBusy || mergeRunning) }
    }
    /// Sheets.
    var trimming: CardEntry?
    var merging: [URL]?
    /// Bumped when files are added, with the cards to scroll to.
    private(set) var addedBatch = 0
    private(set) var lastAddedIDs: [UUID] = []
    /// The window's undo manager, set by the main view.
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private let keepAwake = KeepAwake(reason: "Convert is converting files")
    @ObservationIgnored private var batchStart: Date?

    private static let settingsKey = "settings"
    private static let recentFoldersKey = "recentFolders"
    static let playSoundKey = "playSoundWhenDone"
    static let autoStartKey = "startWhenAdded"
    static let removeFinishedKey = "removeFinishedWhenDone"
    static let trashOriginalsKey = "trashOriginalsWhenDone"
    static let quitWhenDoneKey = "quitWhenDone"
    private static let presetsKey = "presets"

    var autoStart: Bool { UserDefaults.standard.bool(forKey: Self.autoStartKey) }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Self.playSoundKey: true, Self.autoStartKey: true])
        presets = defaults.data(forKey: Self.presetsKey).flatMap { try? JSONDecoder().decode(PresetLibrary.self, from: $0) }
            ?? PresetLibrary()
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
                                restore: restoreBook, options: optionsBook)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }

    // MARK: Row facts

    private static func key(_ url: URL) -> String { url.standardizedFileURL.path }

    func facts(for item: FileQueueItem) -> RowFacts {
        facts(for: item.input)
    }

    func facts(for url: URL) -> RowFacts {
        let key = Self.key(url)
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
        queue.items.filter(isOutdated)
    }

    /// Finished, but made with settings that have changed since. Reads only this item.
    func isOutdated(_ item: FileQueueItem) -> Bool {
        guard case .finished = item.state, let row = facts[Self.key(item.input)],
              let kind = row.kind, let used = row.signature else { return false }
        return used != settings.signature(for: kind, options: row.options)
    }

    private func finished(_ url: URL, report: ConversionReport?) {
        let row = facts[Self.key(url)]
        row?.report = report
        // When Done: move the original to the Trash, once the new file is safely there.
        if let report, UserDefaults.standard.bool(forKey: Self.trashOriginalsKey),
           AfterConversion.trashOriginal(url, output: report.output) {
            row?.trashedOriginal = true
        }
    }

    /// Reads media facts for new rows in the background, one at a time.
    private func probe(_ items: [FileQueueItem]) {
        probe(urls: items.filter { !$0.state.isFailure }.map(\.input))
    }

    private func probe(urls: [URL]) {
        let jobs = urls.map { (facts(for: $0), $0) }
        guard !jobs.isEmpty else { return }
        Task.detached(priority: .utility) {
            for (row, url) in jobs {
                do {
                    let info = try await MediaProbe.probe(url)
                    await MainActor.run { row.info = info }
                } catch {
                    let e = error as? ConvertError
                    let message = [e?.errorDescription, e?.recoverySuggestion].compactMap { $0 }.joined(separator: " ")
                    await MainActor.run { row.readError = message.isEmpty ? nil : message }
                }
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
        if !autoStart {
            stage(urls)
            return
        }
        Task {
            let added = await queue.add(urls)
            if added.isEmpty {
                HUD.show("Already in the list", systemImage: "doc.on.doc")
            } else {
                probe(added)
                announce(added.map(\.id))
            }
        }
    }

    private func announce(_ ids: [UUID]) {
        lastAddedIDs = ids
        addedBatch += 1
    }

    /// Adds files as cards that wait for Start. Files Convert can't take still go straight
    /// to the list, where they say why.
    private func stage(_ urls: [URL]) {
        let types = MediaTypes.accepted
        Task {
            let (found, rejected) = await Task.detached(priority: .userInitiated) {
                (FileIntake.expand(urls, types: types),
                 FileIntake.unaccepted(urls, types: types) { _ in "" }.map(\.url))
            }.value
            var known = Set(staged.map { Self.key($0.input) })
            var refreshed: [FileQueueItem] = []
            for item in queue.items { known.insert(Self.key(item.input)) }
            var added: [StagedFile] = []
            for file in found {
                let key = Self.key(file.url)
                if let item = queue.items.first(where: { Self.key($0.input) == key }) {
                    // Already converted: dropping it again makes it ready to convert again.
                    if item.canRetry, !refreshed.contains(where: { $0 === item }) { refreshed.append(item) }
                    continue
                }
                guard known.insert(key).inserted else { continue }
                added.append(StagedFile(input: file.url, bytes: file.bytes))
            }
            staged.append(contentsOf: added)
            if !rejected.isEmpty { await queue.add(rejected) }
            if added.isEmpty && rejected.isEmpty && refreshed.isEmpty {
                HUD.show("Already in the list", systemImage: "doc.on.doc")
                return
            }
            probe(urls: added.map(\.input))
            refreshed.forEach(queue.retry)
            announce(added.map(\.id) + refreshed.map(\.id))
        }
    }

    /// Starts files waiting for Start (all of them, or these).
    func start(_ entries: [CardEntry]? = nil) {
        let chosen: [StagedFile]
        if let entries {
            let ids = Set(entries.map(\.id))
            chosen = staged.filter { ids.contains($0.id) }
        } else {
            chosen = staged
        }
        // Finished files whose settings changed since are started again too.
        let again = (entries?.compactMap(\.item) ?? queue.items).filter(isOutdated)
        guard !chosen.isEmpty || !again.isEmpty else { return }
        let ids = Set(chosen.map(\.id))
        staged.removeAll { ids.contains($0.id) }
        again.forEach(queue.retry)
        guard !chosen.isEmpty else { return }
        Task {
            let added = await queue.add(chosen.map(\.input))
            // Selection follows the files into the queue.
            if !selection.isDisjoint(with: ids) {
                selection.subtract(ids)
                selection.formUnion(added.map(\.id))
            }
        }
    }

    /// Something to start: files waiting for Start, or files converted with other settings.
    var canStart: Bool { !staged.isEmpty || (!queue.isBusy && !outdatedItems.isEmpty) }

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
        // Only waiting cards selected (or nothing converted yet): show their originals.
        let chosen = selectedEntries.isEmpty ? entries : selectedEntries
        if chosen.allSatisfy({ $0.item == nil }) {
            NSWorkspace.shared.activateFileViewerSelecting(chosen.map(\.input))
            return
        }
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
        selection = Set(queue.items.map(\.id) + staged.map(\.id))
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
        removeStagedForClear()
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
        } else if let entry = selectedEntries.first ?? entries.first {
            previewURL = entry.item?.revealURL ?? entry.input
        }
    }

    /// The files Quick Look pages through.
    var previewURLs: [URL] {
        entries.map { $0.item?.revealURL ?? $0.input }
    }

    // MARK: Batches

    private func batchStarted() {
        batchStart = Date()
        keepAwake.update(busy: true)
    }

    private func batchFinished() {
        keepAwake.update(busy: mergeRunning)
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
        guard anyDone else { return }
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Self.removeFinishedKey) {
            let done = queue.items.filter { if case .finished = $0.state { return true } else { return false } }
            if !done.isEmpty { removeFromList(done, actionName: "Remove Finished") }
        }
        if defaults.bool(forKey: Self.quitWhenDoneKey), staged.isEmpty {
            // A moment to hear the sound; anything added meanwhile cancels it.
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if !queue.isBusy, staged.isEmpty { NSApp.terminate(nil) }
            }
        }
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
}

extension FileQueueItem.State {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
