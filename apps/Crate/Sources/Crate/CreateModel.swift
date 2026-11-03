import AppKit
import CrateCore
import Observation

/// The items to compress and the options for the new archive.
@MainActor
@Observable
final class CreateModel {
    enum Job {
        case idle
        case working(Double?)
        case done(CreateResult)
        case failed(String)
    }

    unowned let app: AppModel
    private(set) var items: [URL]
    var name: String
    /// The name the user typed, or nil while it follows the items.
    private var nameEdited = false
    var format: CreateFormat {
        didSet {
            app.settings.createFormat = format
            if !format.supportsPassword { password = nil }
        }
    }
    var level: CompressionLevel {
        didSet { app.settings.compression = level }
    }
    var encryption: ZipEncryption {
        didSet { app.settings.zipEncryption = encryption }
    }
    /// Never stored anywhere but here.
    var password: String?
    var split: SplitSize = .off
    var customSplitMB = 50
    var usesCustomSplit = false
    /// Nil: next to the first item.
    var folder: URL?
    var editingPassword = false
    private(set) var job: Job = .idle
    /// How the last archive made here was protected, for the result line.
    private(set) var lastProtection: ZipEncryption?
    var itemSelection: Set<URL> = []
    @ObservationIgnored private var task: Task<Void, Never>?

    init(sources: [URL], app: AppModel) {
        self.app = app
        items = []
        name = "Archive"
        format = app.settings.createFormat
        level = app.settings.compression
        encryption = app.settings.zipEncryption
        add(sources)
    }

    var isWorking: Bool {
        if case .working = job { return true }
        return false
    }

    var isDone: Bool {
        if case .done = job { return true }
        return false
    }

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

    var canCreate: Bool { !items.isEmpty && !isWorking && splitProblem == nil }

    /// The one-line hint under Format, which depends on the password too.
    var formatHint: String {
        if format == .zip, password != nil {
            return encryption == .aes256
                ? "Needs 7-Zip, Keka or The Unarchiver to open (AES-256 password)"
                : "Opens almost anywhere; the password is easy to crack"
        }
        return format.summary
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
        let request = CreateRequest(
            sources: items, folder: folder, name: cleanName, format: format, level: level,
            password: format.supportsPassword ? password : nil, encryption: encryption,
            leaveOutMacFiles: app.settings.leaveOutMacFiles, partSize: partSize
        )
        job = .working(nil)
        let sink: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in
                if case .working = self?.job { self?.job = .working(fraction) }
            }
        }
        task = Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<CreateResult, any Error> in
                Result {
                    try ArchiveCreator().create(request, progress: sink)
                }
            }.value
            guard !Task.isCancelled else { return }
            switch outcome {
            case .success(let result):
                lastProtection = request.password == nil ? nil : request.encryption
                job = .done(result)
                password = nil
            case .failure(is CancellationError):
                job = .idle
            case .failure(let error):
                job = .failed((error as? CrateError)?.message ?? error.localizedDescription)
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

    func reveal() {
        if case .done(let result) = job {
            NSWorkspace.shared.activateFileViewerSelecting(result.outputs)
        }
    }

    func chooseFolder() {
        app.chooseFolder(message: "Choose where to save the archive.", prompt: "Choose", near: items.first) { url in
            self.folder = url
        }
    }
}
