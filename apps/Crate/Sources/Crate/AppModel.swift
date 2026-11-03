import AppKit
import CrateCore
import Observation
import SlopKit
import UniformTypeIdentifiers

/// The window's state: which screen shows, the settings, and the batch extraction queue.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    enum Screen {
        case empty
        case browse(BrowseModel)
        case create(CreateModel)
        case queue
    }

    var screen: Screen = .empty
    var settings: CrateSettings {
        didSet { if settings != oldValue { save() } }
    }

    /// Batch extraction (several archives, ⌥-drop, the Finder service).
    let queue: FileQueue
    let processor: ExtractProcessor
    var queueSelection: Set<FileQueueItem.ID> = []
    /// What each finished queue row produced, by archive path.
    var queueResults: [String: String] = [:]
    /// Queue rows waiting for a password, oldest first.
    var passwordRequests: [PasswordRequest] = []
    /// Archives in File ▸ Open Recent.
    private(set) var recents: [URL] = []
    /// The window's undo manager (set by the main view), for putting trashed archives back.
    @ObservationIgnored weak var undoManager: UndoManager?

    private static let settingsKey = "settings"

    private init() {
        let loaded = UserDefaults.standard.data(forKey: Self.settingsKey)
            .flatMap { try? JSONDecoder().decode(CrateSettings.self, from: $0) } ?? CrateSettings()
        settings = loaded
        let processor = ExtractProcessor()
        self.processor = processor
        queue = FileQueue(processor: processor, acceptedTypes: [.item], maxConcurrent: 3)
        processor.settings = loaded
        processor.onNeedsPassword = { url, wrong in
            Task { @MainActor in AppModel.shared.requestPassword(for: url, wrong: wrong) }
        }
        processor.onFinished = { url, summary, moves in
            Task { @MainActor in
                AppModel.shared.queueResults[url.standardizedFileURL.path] = summary
                if !moves.isEmpty { AppModel.shared.registerPutBack(moves) }
            }
        }
        queue.onIdle = { [weak self] in self?.queueFinished() }
        refreshRecents()
    }

    private func save() {
        processor.settings = settings
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }

    // MARK: Opening

    var browse: BrowseModel? {
        if case .browse(let model) = screen { return model }
        return nil
    }

    var create: CreateModel? {
        if case .create(let model) = screen { return model }
        return nil
    }

    /// True while a browse or create job runs (new drops wait).
    var isBusy: Bool {
        (browse?.isWorking ?? false) || (create?.isWorking ?? false)
    }

    /// Opens dropped or chosen files, routed by what they are. `explicit`: Open With, the
    /// Dock icon or ⌘O (zip-based documents count as archives). ⌥ flips "extract right away".
    func open(_ urls: [URL], explicit: Bool = false, optionHeld: Bool = AppModel.optionAloneHeld) {
        let urls = urls.filter(\.isFileURL)
        guard !urls.isEmpty else { return }
        let rightAway = settings.extractsRightAway(optionHeld: optionHeld)
        guard let route = Router.route(urls, extractRightAway: rightAway, explicitOpen: explicit) else { return }
        switch route {
        case .browse(let url):
            guard !isBusy else { return refuseWhileBusy() }
            do {
                let source = try VolumeSet.resolve(url)
                noteRecent(source.displayURL)
                let model = BrowseModel(source: source, app: self)
                screen = .browse(model)
                model.load()
            } catch {
                let crateError = error as? CrateError ?? .unreadableSource(name: url.lastPathComponent)
                screen = .browse(BrowseModel(failed: url, error: crateError, app: self))
            }
        case .extract(let archives):
            if case .create = screen, isBusy { return refuseWhileBusy() }
            extractInQueue(archives)
        case .create(let items):
            if let create, !create.isWorking, !create.isDone {
                create.add(items)
                return
            }
            guard !isBusy else { return refuseWhileBusy() }
            screen = .create(CreateModel(sources: items, app: self))
        }
    }

    /// ⌥ and nothing else (so a stray Shift-Option or Command-Option doesn't count).
    static var optionAloneHeld: Bool {
        NSEvent.modifierFlags.intersection([.shift, .control, .option, .command]) == .option
    }

    func extractInQueue(_ urls: [URL]) {
        // A split set shows as its first part, whichever part was dropped.
        let archives = urls.map { (try? VolumeSet.resolve($0))?.displayURL ?? $0 }
        archives.forEach { noteRecent($0) }
        if case .ask = settings.destination {
            chooseFolder(message: "Choose where to put the extracted files.", prompt: "Extract Here", near: archives.first) { [weak self] folder in
                guard let self else { return }
                archives.forEach { self.processor.setFolder(folder, for: $0) }
                self.addToQueue(archives)
            }
        } else {
            addToQueue(archives)
        }
    }

    private func addToQueue(_ archives: [URL]) {
        screen = .queue
        Task {
            let added = await queue.add(archives)
            if added.isEmpty { HUD.show("Already in the list", systemImage: "doc.on.doc") }
        }
    }

    private func refuseWhileBusy() {
        NSSound.beep()
        HUD.show("Stop the current job first", systemImage: "hourglass")
    }

    /// ⌘O: archives or files to compress.
    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.message = "Choose an archive to open, or files and folders to compress."
        panel.prompt = "Open"
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            MainActor.assumeIsolated { self?.open(panel.urls, explicit: true, optionHeld: false) }
        }
    }

    /// ⌘N: always compresses, even archives.
    func newArchiveFromFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.message = "Choose the files and folders to put in a new archive."
        panel.prompt = "Choose"
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            MainActor.assumeIsolated {
                guard !self.isBusy else { return self.refuseWhileBusy() }
                self.screen = .create(CreateModel(sources: panel.urls, app: self))
            }
        }
    }

    /// Back to the queue if it has rows, otherwise the drop zone.
    func closeCurrent() {
        if let browse { browse.cancel() }
        if let create { create.cancel() }
        screen = queue.items.isEmpty ? .empty : .queue
    }

    var canClose: Bool {
        switch screen {
        case .browse, .create: true
        default: false
        }
    }

    // MARK: Queue

    func clearQueue() {
        queue.remove(queue.items)
        queueSelection = []
        queueResults = [:]
        passwordRequests = []
        if case .queue = screen { screen = .empty }
    }

    func revealQueueSelection() {
        let selected = queue.items.filter { queueSelection.contains($0.id) }
        FileQueueActions.reveal(selected.isEmpty ? queue.items : selected)
    }

    private func queueFinished() {
        if settings.revealAfterExtracting {
            let outputs = queue.items.compactMap(\.output)
            if !outputs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
        }
        if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
    }

    func requestPassword(for url: URL, wrong: Bool) {
        guard !passwordRequests.contains(where: { $0.url == url }) else { return }
        passwordRequests.append(PasswordRequest(url: url, wrong: wrong))
    }

    func answerPassword(_ password: String?, for request: PasswordRequest) {
        passwordRequests.removeAll { $0.url == request.url }
        guard let password, !password.isEmpty else { return }
        processor.setPassword(password, for: request.url)
        if let item = queue.items.first(where: { $0.input == request.url }) {
            queue.retry(item)
        }
    }

    // MARK: Helpers

    func noteRecent(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        refreshRecents()
    }

    /// Recent archives, minus ones that went to the Trash or are gone.
    func refreshRecents() {
        recents = NSDocumentController.shared.recentDocumentURLs.filter {
            !TrashLocation.contains($0) && FileManager.default.fileExists(atPath: $0.path)
        }
    }

    // MARK: Trash and Undo

    /// Moves an archive's parts to the Trash. Nil if any part couldn't be moved (the ones
    /// that were are put back).
    func trashParts(of source: ArchiveSource) -> [TrashMove]? {
        let fileSystem = SystemFileSystem()
        var moves: [TrashMove] = []
        for part in source.parts {
            guard let trashed = try? fileSystem.trash(part) else {
                moves.forEach { try? $0.putBack() }
                return nil
            }
            moves.append(TrashMove(original: part, trashed: trashed))
        }
        refreshRecents()
        return moves
    }

    /// Edit ▸ Undo Move to Trash.
    func registerPutBack(_ moves: [TrashMove], then: (@MainActor () -> Void)? = nil) {
        let window = NSApp.windows.first { $0.identifier?.rawValue == "main" } ?? NSApp.mainWindow
        guard let undoManager = window?.undoManager ?? self.undoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                var failed = false
                for move in moves {
                    do { try move.putBack() } catch { failed = true }
                }
                model.refreshRecents()
                then?()
                HUD.show(failed ? "Couldn't put the archive back" : (moves.count == 1 ? "Archive put back" : "Archive parts put back"),
                         systemImage: failed ? "exclamationmark.triangle" : "arrow.uturn.backward")
            }
        }
        undoManager.setActionName("Move to Trash")
    }

    func clearRecents() {
        NSDocumentController.shared.clearRecentDocuments(nil)
        refreshRecents()
    }

    func chooseFolder(message: String, prompt: String, near: URL?, then: @escaping @MainActor (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.prompt = prompt
        panel.directoryURL = near?.deletingLastPathComponent()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { then(url) }
        }
    }
}

struct PasswordRequest: Identifiable, Equatable {
    let url: URL
    let wrong: Bool
    var id: URL { url }
}

/// Extracts one archive for the batch queue. Passwords live in memory only, until used.
final class ExtractProcessor: FileProcessor, @unchecked Sendable {
    private let lock = NSLock()
    private var passwords: [String: String] = [:]
    private var folders: [String: URL] = [:]
    private var _settings = CrateSettings()
    private let fileSystem = SystemFileSystem()
    var onNeedsPassword: (@Sendable (URL, Bool) -> Void)?
    var onFinished: (@Sendable (URL, String, [TrashMove]) -> Void)?

    var settings: CrateSettings {
        get { lock.withLock { _settings } }
        set { lock.withLock { _settings = newValue } }
    }

    func setPassword(_ password: String, for url: URL) {
        lock.withLock { passwords[url.standardizedFileURL.path] = password }
    }

    func setFolder(_ folder: URL, for url: URL) {
        lock.withLock { folders[url.standardizedFileURL.path] = folder }
    }

    func process(_ job: FileJob, progress: FileProgress) async throws -> FileOutcome {
        let key = job.input.standardizedFileURL.path
        let (password, chosenFolder, settings) = lock.withLock { (passwords[key], folders[key], _settings) }
        let source = try VolumeSet.resolve(job.input)
        let folder = chosenFolder ?? settings.extractionFolder(for: source) ?? source.folder
        let result: ExtractionResult
        do {
            result = try Extractor(fileSystem: fileSystem).extract(
                source, to: folder, options: ExtractionOptions(password: password)
            ) { progress($0) }
        } catch let error as CrateError where error.needsPassword {
            // Wrong passwords are forgotten; the prompt asks again.
            lock.withLock { passwords[key] = nil }
            onNeedsPassword?(job.input, password != nil)
            throw error
        }
        lock.withLock { passwords[key] = nil }
        var summary = Self.summary(result)
        var moves: [TrashMove] = []
        // Only a complete, clean extraction may send the archive to the Trash.
        if settings.afterExtracting == .trash, result.skipped.isEmpty {
            do {
                for part in source.parts {
                    moves.append(TrashMove(original: part, trashed: try fileSystem.trash(part)))
                }
                summary += " · Archive moved to the Trash"
            } catch {
                moves.forEach { try? $0.putBack() }
                moves = []
                summary += " · Couldn't move the archive to the Trash"
            }
        } else if settings.afterExtracting == .trash {
            summary += " · Archive kept because items were skipped"
        }
        onFinished?(job.input, summary, moves)
        return .produced(output: result.primary ?? folder, bytes: result.bytes)
    }

    static func summary(_ result: ExtractionResult) -> String {
        var parts = [result.fileCount == 1 ? "1 file" : "\(result.fileCount) files"]
        if let output = result.primary { parts.insert("into “\(output.lastPathComponent)”", at: 0) }
        if !result.skipped.isEmpty {
            parts.append(result.skipped.count == 1 ? "1 unsafe item skipped" : "\(result.skipped.count) unsafe items skipped")
        }
        return parts.joined(separator: " · ")
    }
}
