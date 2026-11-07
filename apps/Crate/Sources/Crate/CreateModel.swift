import AppKit
import CrateCore
import Observation
import SlopKit

/// Making a new archive (or converting an open one): the items, the format page's options,
/// the job, and its finished screen.
@MainActor
@Observable
final class CreateModel {
    enum Page {
        /// The dropped items, to add to or trim (skipped with "Go Straight to Options").
        case review
        /// Format cards, name, compression, encryption, split, destination.
        case options
    }

    enum Job {
        case idle
        case working(Double?)
        case done(CreateResult)
        case split([URL])
        case failed(String)
    }

    unowned let app: AppModel
    /// Set when converting: the open archive, to go back to.
    let origin: BrowseModel?
    private(set) var items: [URL]
    var page: Page
    var name: String
    /// The name the user typed, or nil while it follows the items.
    private var nameEdited = false
    var format: CreateFormat {
        didSet {
            app.settings.createFormat = format
            if !format.supportsPassword { encrypt = false }
        }
    }
    var level: CompressionLevel {
        didSet { app.settings.compression = level }
    }
    var encryption: ZipEncryption {
        didSet { app.settings.zipEncryption = encryption }
    }
    var hideNames: Bool {
        didSet { app.settings.hideNames = hideNames }
    }
    /// The Encrypt checkbox and its fields. Never stored anywhere but here.
    var encrypt = false
    var passwordText = ""
    var repeatText = ""
    var showPassword = false
    var split: SplitSize = .off
    var customSplitMB = 50
    var usesCustomSplit = false
    /// Nil: next to the first item.
    var folder: URL?
    var splittingFile = false
    /// The running job is a split (for the progress line).
    private(set) var splittingFileJob = false
    private(set) var job: Job = .idle
    /// How the last archive made here was protected, for the result line.
    private(set) var lastProtection: String?
    var itemSelection: Set<URL> = []
    @ObservationIgnored private var task: Task<Void, Never>?

    init(sources: [URL], app: AppModel) {
        self.app = app
        origin = nil
        items = []
        name = "Archive"
        format = app.settings.createFormat
        level = app.settings.compression
        encryption = app.settings.zipEncryption
        hideNames = app.settings.hideNames
        page = app.settings.reviewFilesFirst ? .review : .options
        add(sources)
    }

    /// The format page for repacking an open archive.
    init(converting archive: BrowseModel, app: AppModel) {
        self.app = app
        origin = archive
        items = [archive.source.displayURL]
        name = archive.source.baseName
        nameEdited = true
        let formats = archive.conversionFormats
        format = formats.contains(app.settings.createFormat) ? app.settings.createFormat : formats.first ?? .zip
        level = app.settings.compression
        encryption = app.settings.zipEncryption
        hideNames = app.settings.hideNames
        page = .options
    }

    var isConverting: Bool { origin != nil }

    var isWorking: Bool {
        if case .working = job { return true }
        return false
    }

    var isDone: Bool {
        switch job {
        case .done, .split: true
        default: false
        }
    }

    /// The formats offered (converting leaves out the archive's own).
    var formats: [CreateFormat] { origin?.conversionFormats ?? CreateFormat.allCases }

    func add(_ urls: [URL]) {
        let known = Set(items.map(\.standardizedFileURL))
        items += urls.filter { !known.contains($0.standardizedFileURL) }
        followName()
    }

    func remove(_ urls: Set<URL>) {
        items.removeAll { urls.contains($0) }
        itemSelection.subtract(urls)
        followName()
    }

    func nameChanged() {
        guard !isConverting else { return }
        nameEdited = !name.trimmingCharacters(in: .whitespaces).isEmpty && name != CreateRequest.defaultName(for: items)
    }

    private func followName() {
        if !nameEdited { name = CreateRequest.defaultName(for: items) }
    }

    /// The chosen folder, else next to the first item (never a Trash: then ~/Downloads).
    var targetFolder: URL? {
        if let folder { return folder }
        guard let next = items.first?.deletingLastPathComponent() else { return nil }
        return TrashLocation.contains(next) ? TrashLocation.fallbackFolder : next
    }

    var partSize: Int64? {
        usesCustomSplit ? Int64(customSplitMB) * 1_000_000 : split.bytes
    }

    var fileName: String {
        cleanName + "." + format.fileExtension
    }

    var cleanName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return trimmed.isEmpty || trimmed.hasPrefix(".") ? "Archive" : trimmed
    }

    /// Set when the custom split size can't be used.
    var splitProblem: String? {
        guard usesCustomSplit else { return nil }
        return customSplitMB < 1 ? "Enter a part size of at least 1 MB." : nil
    }

    /// Set when the password fields aren't ready.
    var passwordProblem: String? {
        guard encrypt, format.supportsPassword else { return nil }
        if passwordText.isEmpty { return "Enter a password, or turn off Encrypt." }
        if repeatText != passwordText { return repeatText.isEmpty ? "Repeat the password to confirm it." : "The passwords don't match." }
        return nil
    }

    /// A problem the user has to fix (shown as a warning), not just a step still to do.
    var hasInputProblem: Bool {
        splitProblem != nil || (encrypt && format.supportsPassword && !repeatText.isEmpty && repeatText != passwordText && !passwordText.isEmpty)
    }

    var password: String? {
        encrypt && format.supportsPassword && passwordProblem == nil ? passwordText : nil
    }

    var canCreate: Bool { !items.isEmpty && !isWorking && splitProblem == nil && passwordProblem == nil }

    /// One regular file: Split can cut it into parts without making an archive.
    var canSplitFile: Bool {
        guard !isConverting, items.count == 1, let only = items.first, !isWorking else { return false }
        let values = try? only.resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile == true
    }

    /// The one-line description under the format cards, which depends on the password too.
    var formatHint: String {
        // Short enough for one line at the window's minimum width.
        if encrypt, format == .zip {
            return encryption == .aes256
                ? "AES-256 password. Opens in 7‑Zip, Keka or The Unarchiver"
                : "Opens almost anywhere; the password is easy to crack"
        }
        if encrypt, format == .sevenZip {
            return hideNames ? "AES-256 password, names hidden too. Opens in 7‑Zip, Keka or Crate"
                             : "AES-256 password. Opens in 7‑Zip, Keka or Crate"
        }
        return format.summary
    }

    // MARK: Pages

    func next() {
        guard page == .review, !items.isEmpty else { return }
        page = .options
    }

    /// Back: from the options to the items, or (converting) to the archive.
    func back() {
        if case .working = job { return }
        if isDone {
            job = .idle
            return
        }
        if let origin {
            app.screen = .browse(origin)
            return
        }
        if page == .options { page = .review }
    }

    /// Done on the finished screen.
    func finish() {
        if let origin { origin.cancel() }
        app.closeCurrent()
    }

    // MARK: Running

    func create() {
        guard canCreate else { return }
        guard let folder = targetFolder else { return }
        if !FileManager.default.isWritableFile(atPath: folder.path) {
            app.chooseFolder(message: "Crate can't save in “\(folder.lastPathComponent)”. Choose where to save the archive.",
                             prompt: "Save Here", near: items.first) { chosen in
                self.folder = chosen
                self.start(in: chosen)
            }
            return
        }
        start(in: folder)
    }

    private func start(in folder: URL) {
        splittingFileJob = false
        let request = CreateRequest(
            sources: items, folder: folder, name: cleanName, format: format, level: level,
            password: password, encryption: encryption, hideNames: hideNames,
            leaveOutMacFiles: app.settings.leaveOutMacFiles, partSize: partSize
        )
        let protection: String? = request.password == nil ? nil
            : format == .sevenZip ? (hideNames ? "password (AES-256, names hidden)" : "password (AES-256)")
            : encryption == .aes256 ? "password (AES-256)" : "password (ZipCrypto)"
        let converting = origin.map { ($0.source, $0.checkedPassword) }
        job = .working(nil)
        let sink = progressSink()
        task = Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<CreateResult, any Error> in
                Result {
                    if let (source, archivePassword) = converting {
                        return try Converter().convert(source, password: archivePassword, to: request, progress: sink)
                    }
                    return try ArchiveCreator().create(request, progress: sink)
                }
            }.value
            guard !Task.isCancelled else { return }
            switch outcome {
            case .success(let result):
                lastProtection = protection
                job = .done(result)
                passwordText = ""
                repeatText = ""
                encrypt = false
            case .failure(is CancellationError):
                job = .idle
            case .failure(let error):
                job = .failed((error as? CrateError)?.message ?? error.localizedDescription)
            }
        }
    }

    /// Cuts the one dropped file into `.001`, `.002`… parts next to it.
    func splitFile(partSize: Int64) {
        guard canSplitFile, let file = items.first else { return }
        splittingFileJob = true
        let folder = TrashLocation.contains(file.deletingLastPathComponent()) ? TrashLocation.fallbackFolder : nil
        job = .working(nil)
        let sink = progressSink()
        task = Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Result { try FileSplitter.split(file, partSize: partSize, in: folder, progress: sink) }
            }.value
            guard !Task.isCancelled else { return }
            switch outcome {
            case .success(let parts): job = .split(parts)
            case .failure(is CancellationError): job = .idle
            case .failure(let error): job = .failed((error as? CrateError)?.message ?? error.localizedDescription)
            }
        }
    }

    private func progressSink() -> @Sendable (Double) -> Void {
        { [weak self] fraction in
            Task { @MainActor in
                if case .working = self?.job { self?.job = .working(fraction) }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if case .working = job { job = .idle }
    }

    func dismissError() {
        if case .failed = job { job = .idle }
    }

    /// What the finished screen lists.
    var resultItems: [URL] {
        switch job {
        case .done(let result): result.outputs
        case .split(let parts): parts
        default: []
        }
    }

    func reveal() {
        let items = resultItems
        if !items.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(items) }
    }

    func chooseFolder() {
        app.chooseFolder(message: "Choose where to save the archive.", prompt: "Choose", near: items.first) { url in
            self.folder = url
        }
    }
}
