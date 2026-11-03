import AppKit
import CrateCore
import Observation
import SlopKit

/// One open archive: its listing, the filter, the selection, and the job running on it.
@MainActor
@Observable
final class BrowseModel {
    enum Phase {
        case loading(Double?)
        case loaded
        case failed(CrateError)
    }

    enum Job {
        case idle
        case working(title: String, progress: Double?)
        case extracted(ExtractionResult, trashed: Bool?)
        case converted(CreateResult)
        case failed(String)
    }

    /// Something to run once the password is known.
    enum PendingAction {
        case extractAll
        case extractSelected
        case extractTo
        case quickLook
        case open(ArchiveNode)
        case convert(CreateFormat)
    }

    let source: ArchiveSource
    unowned let app: AppModel
    private(set) var phase: Phase = .loading(nil)
    private(set) var listing: ArchiveListing?
    private(set) var tree: ArchiveTree = .empty
    private(set) var visibleTree: ArchiveTree = .empty
    var query = "" {
        didSet { if query != oldValue { visibleTree = tree.filtered(query) } }
    }
    /// Set by the outline. Changing it clears a finished job's message and moves Quick Look.
    var selection: [ArchiveNode] = [] {
        didSet {
            switch job {
            case .extracted, .converted, .failed: job = .idle
            default: break
            }
            if quickLook.isVisible, let node = previewNode { preparePreview(node) }
        }
    }
    private(set) var job: Job = .idle
    /// The checked password, kept only while the archive is open.
    @ObservationIgnored private var password: String?
    var askingPassword = false
    var passwordWasWrong = false
    var checkingPassword = false
    @ObservationIgnored private var pending: PendingAction?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Space bar Quick Look (a real QLPreviewPanel that follows the selection).
    @ObservationIgnored let quickLook = QuickLookController()
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    /// The archive (or its parts) went to the Trash after extracting.
    private(set) var archiveGone = false
    /// Why "Move to Trash after extracting" didn't happen this time.
    private(set) var keptNote: String?

    init(source: ArchiveSource, app: AppModel) {
        self.source = source
        self.app = app
    }

    /// An archive that couldn't even be opened (e.g. a missing part).
    init(failed url: URL, error: CrateError, app: AppModel) {
        source = ArchiveSource(file: url)
        self.app = app
        phase = .failed(error)
    }

    // MARK: State

    var isWorking: Bool {
        if case .working = job { return true }
        if case .loading = phase { return true }
        return false
    }

    var isLoaded: Bool {
        if case .loaded = phase { return true }
        return false
    }

    var canExtract: Bool {
        isLoaded && !isWorking && !archiveGone && listing?.encryptionUnsupported == false && !tree.roots.isEmpty
    }

    var hasSelection: Bool { !selection.isEmpty }

    /// "212 items, 1.4 GB" for the window subtitle.
    var summary: String {
        guard let listing, isLoaded else { return "" }
        let count = tree.itemCount
        var text = count == 1 ? "1 item" : "\(count.formatted()) items"
        text += tree.sizesKnown ? ", " + ByteCountFormatter.string(fromByteCount: tree.totalBytes, countStyle: .file) : ", size unknown"
        text += " · " + listing.formatName
        return text
    }

    // MARK: Loading

    func load() {
        phase = .loading(nil)
        let source = self.source
        let loadProgress: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in
                if case .loading = self?.phase { self?.phase = .loading(fraction) }
            }
        }
        task = Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<(ArchiveListing, ArchiveTree), CrateError> in
                do {
                    let listing = try ArchiveReader.list(source, progress: loadProgress)
                    return .success((listing, ArchiveTree(entries: listing.entries)))
                } catch let error as CrateError {
                    return .failure(error)
                } catch {
                    return .failure(.damaged(name: source.fileName, detail: error.localizedDescription))
                }
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let (listing, tree)):
                self.listing = listing
                self.tree = tree
                self.visibleTree = tree.filtered(query)
                phase = .loaded
                if listing.hasEncryptedEntries, !listing.encryptionUnsupported {
                    askingPassword = true
                }
            case .failure(let error):
                phase = .failed(error)
            }
        }
    }

    // MARK: Password

    func submitPassword(_ text: String) {
        guard !text.isEmpty else { return }
        checkingPassword = true
        let source = self.source
        Task {
            let ok = await Task.detached { (try? ArchiveReader.checkPassword(text, for: source)) ?? false }.value
            checkingPassword = false
            if ok {
                password = text
                askingPassword = false
                passwordWasWrong = false
                if let pending {
                    self.pending = nil
                    run(pending)
                }
            } else {
                passwordWasWrong = true
            }
        }
    }

    func cancelPassword() {
        askingPassword = false
        passwordWasWrong = false
        pending = nil
    }

    private var needsPassword: Bool {
        listing?.hasEncryptedEntries == true && listing?.encryptionUnsupported == false && password == nil
    }

    /// Runs `action`, asking for the password first if the archive needs one.
    private func withPassword(_ action: PendingAction) {
        if needsPassword {
            pending = action
            askingPassword = true
        } else {
            run(action)
        }
    }

    private func run(_ action: PendingAction) {
        switch action {
        case .extractAll: extractAll()
        case .extractSelected: extractSelection()
        case .extractTo: extractSelectionTo()
        case .quickLook: toggleQuickLook()
        case .open(let node): open(node)
        case .convert(let format): convert(to: format)
        }
    }

    // MARK: Extracting

    /// Return / ⌘E / the main button: the selection if there is one, else everything.
    func extractPrimary() {
        hasSelection ? extractSelection() : extractAll()
    }

    func extractAll() {
        guard canExtract else { return }
        if needsPassword { return withPassword(.extractAll) }
        destination { folder in self.extract(selection: nil, to: folder, layout: .smart, fullArchive: true) }
    }

    /// The selected items, wrapped like Extract All (one item lands as is).
    func extractSelection() {
        guard canExtract, hasSelection else { return }
        if needsPassword { return withPassword(.extractSelected) }
        let paths = selection.map(\.archivePath)
        destination { folder in self.extract(selection: paths, to: folder, layout: .smart, fullArchive: false) }
    }

    /// ⇧⌘E: the selected items straight into a folder the user picks.
    func extractSelectionTo() {
        guard canExtract else { return }
        if needsPassword { return withPassword(.extractTo) }
        let paths = hasSelection ? selection.map(\.archivePath) : nil
        app.chooseFolder(message: hasSelection ? "Choose where to put the selected items." : "Choose where to extract the archive.",
                         prompt: "Extract Here", near: source.displayURL) { folder in
            self.extract(selection: paths, to: folder, layout: paths == nil ? .smart : .loose, fullArchive: paths == nil)
        }
    }

    /// The folder from Settings, asking when needed (or when it can't be written to).
    private func destination(_ then: @escaping @MainActor (URL) -> Void) {
        if let folder = app.settings.extractionFolder(for: source), FileManager.default.isWritableFile(atPath: folder.path) {
            then(folder)
            return
        }
        let message: String
        if case .ask = app.settings.destination {
            message = "Choose where to put the extracted files."
        } else {
            message = "Crate can't save next to the archive. Choose where to put the extracted files."
        }
        app.chooseFolder(message: message, prompt: "Extract Here", near: source.displayURL, then: then)
    }

    private func extract(selection: [String]?, to folder: URL, layout: ExtractionOptions.Layout, fullArchive: Bool) {
        let source = self.source
        let declared = selection == nil ? listing?.unpackedBytes
            : self.selection.filter { selection!.contains($0.archivePath) }.reduce(0) { $0 + $1.size }
        let options = ExtractionOptions(password: password, selection: selection, layout: layout, declaredBytes: declared)
        let settings = app.settings
        job = .working(title: "Extracting…", progress: nil)
        let sink = progressSink()
        task = Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<ExtractionResult, any Error> in
                Result {
                    try Extractor().extract(source, to: folder, options: options, progress: sink)
                }
            }.value
            guard !Task.isCancelled else { return }
            switch outcome {
            case .success(let result):
                var trashed: Bool?
                // Only a complete, clean extraction may send the archive to the Trash.
                keptNote = nil
                if fullArchive, settings.afterExtracting == .trash, !(result.skipped.isEmpty && listing?.problem == nil) {
                    keptNote = "The archive was kept because some items were skipped."
                }
                if fullArchive, settings.afterExtracting == .trash, result.skipped.isEmpty, listing?.problem == nil {
                    let moves = app.trashParts(of: source)
                    trashed = moves != nil
                    archiveGone = moves != nil
                    if let moves { app.registerPutBack(moves) { self.archiveGone = false } }
                }
                job = .extracted(result, trashed: trashed)
                if settings.revealAfterExtracting, !result.outputs.isEmpty {
                    NSWorkspace.shared.activateFileViewerSelecting(result.outputs)
                }
            case .failure(let error as CrateError) where error.needsPassword:
                password = nil
                passwordWasWrong = true
                job = .idle
                pending = fullArchive ? .extractAll : .extractSelected
                askingPassword = true
            case .failure(is CancellationError):
                job = .idle
            case .failure(let error as CrateError) where error == listing?.problem:
                // The banner already explains; don't repeat it.
                job = .failed(error.isTruncated ? "Extraction stopped where the archive ends. Nothing was kept."
                                                : "Extraction stopped at the damaged part. Nothing was kept.")
            case .failure(let error):
                job = .failed((error as? CrateError)?.message ?? error.localizedDescription)
            }
        }
    }

    private func progressSink() -> @Sendable (Double) -> Void {
        { [weak self] fraction in Task { @MainActor in self?.progress(fraction) } }
    }

    private func progress(_ fraction: Double) {
        if case .working(let title, _) = job { job = .working(title: title, progress: fraction) }
    }

    func cancel() {
        previewTask?.cancel()
        task?.cancel()
        task = nil
        if case .working = job { job = .idle }
    }

    func dismissResult() {
        if case .working = job { return }
        job = .idle
    }

    func revealResult() {
        switch job {
        case .extracted(let result, _) where !result.outputs.isEmpty:
            NSWorkspace.shared.activateFileViewerSelecting(result.outputs)
        case .converted(let result):
            NSWorkspace.shared.activateFileViewerSelecting(result.outputs)
        default:
            if !archiveGone { NSWorkspace.shared.activateFileViewerSelecting([source.displayURL]) }
        }
    }

    // MARK: Previews

    /// Space / ⌘Y: Quick Look the selected file (unpacked to a temporary folder). The panel
    /// follows the selection as it moves.
    func toggleQuickLook() {
        if quickLook.isVisible { quickLook.close(); return }
        guard let node = previewNode, canExtract else { return }
        if needsPassword { return withPassword(.quickLook) }
        preparePreview(node)
    }

    private var previewNode: ArchiveNode? { selection.first(where: { !$0.isFolder }) }

    private func preparePreview(_ node: ArchiveNode) {
        previewTask?.cancel()
        let source = self.source
        let password = self.password
        previewTask = Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<URL, any Error> in
                Result {
                    let folder = try TemporaryFiles.newFolder()
                    let result = try Extractor().extract(source, to: folder,
                                                         options: ExtractionOptions(password: password, selection: [node.archivePath], layout: .loose))
                    guard let url = result.primary else { throw CrateError.damaged(name: source.fileName, detail: "") }
                    return url
                }
            }.value
            guard !Task.isCancelled else { return }
            switch outcome {
            case .success(let url): quickLook.show(url)
            case .failure(is CancellationError): break
            case .failure(let error): job = .failed((error as? CrateError)?.message ?? error.localizedDescription)
            }
        }
    }

    /// ⌘↓: open the first selected file.
    func openSelected() {
        if let node = selection.first(where: { !$0.isFolder }) { open(node) }
    }

    /// Double-click: open a file with its default app (from a temporary copy).
    func open(_ node: ArchiveNode) {
        guard canExtract else { return }
        if needsPassword { return withPassword(.open(node)) }
        temporaryCopy(of: node) { url in NSWorkspace.shared.open(url) }
    }

    private func temporaryCopy(of node: ArchiveNode, then: @escaping @MainActor (URL) -> Void) {
        let source = self.source
        let password = self.password
        job = .working(title: "Preparing “\(node.name)”…", progress: nil)
        task = Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<URL, any Error> in
                Result {
                    let folder = try TemporaryFiles.newFolder()
                    let result = try Extractor().extract(source, to: folder,
                                                         options: ExtractionOptions(password: password, selection: [node.archivePath], layout: .loose))
                    guard let url = result.primary else { throw CrateError.damaged(name: source.fileName, detail: "") }
                    return url
                }
            }.value
            guard !Task.isCancelled else { return }
            switch outcome {
            case .success(let url):
                job = .idle
                then(url)
            case .failure(is CancellationError):
                job = .idle
            case .failure(let error):
                job = .failed((error as? CrateError)?.message ?? error.localizedDescription)
            }
        }
    }

    /// What dragging rows out (file promises) needs, captured when the drag starts.
    var promiseContext: PromiseContext? {
        canExtract && !needsPassword ? PromiseContext(source: source, password: password) : nil
    }

    // MARK: Converting

    func convert(to format: CreateFormat) {
        guard canExtract else { return }
        if needsPassword { return withPassword(.convert(format)) }
        let source = self.source
        let password = self.password
        let settings = app.settings
        let folder = TrashLocation.contains(source.folder) ? TrashLocation.fallbackFolder
            : FileManager.default.isWritableFile(atPath: source.folder.path) ? source.folder : nil
        let start: @MainActor (URL) -> Void = { folder in
            let template = CreateRequest(sources: [], folder: folder, name: source.baseName, format: format,
                                         level: settings.compression, leaveOutMacFiles: settings.leaveOutMacFiles)
            self.job = .working(title: "Converting to \(format.title)…", progress: nil)
            let sink = self.progressSink()
            self.task = Task {
                let outcome = await Task.detached(priority: .userInitiated) { () -> Result<CreateResult, any Error> in
                    Result {
                        try Converter().convert(source, password: password, to: template, progress: sink)
                    }
                }.value
                guard !Task.isCancelled else { return }
                switch outcome {
                case .success(let result): self.job = .converted(result)
                case .failure(is CancellationError): self.job = .idle
                case .failure(let error): self.job = .failed((error as? CrateError)?.message ?? error.localizedDescription)
                }
            }
        }
        if let folder {
            start(folder)
        } else {
            app.chooseFolder(message: "Crate can't save next to the archive. Choose where to put the converted archive.",
                             prompt: "Save Here", near: source.displayURL, then: start)
        }
    }

    /// The formats it can be converted to (not its own).
    var conversionFormats: [CreateFormat] {
        let name = listing?.formatName.lowercased() ?? ""
        return CreateFormat.allCases.filter { format in
            switch format {
            case .zip: name != "zip"
            case .tarGz: name != "tar.gz"
            case .tarXz: name != "tar.xz"
            case .sevenZip: name != "7z"
            }
        }
    }
}

/// What a drag-out needs, captured on the main actor.
struct PromiseContext: Sendable {
    let source: ArchiveSource
    let password: String?
}

/// Temporary copies for Quick Look and Open, removed on launch and quit.
enum TemporaryFiles {
    static var root: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("app.slopapp.crate", isDirectory: true)
    }

    static func newFolder() throws -> URL {
        let url = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }
}
