import SlopKit
import AppKit
import SnapperCore

/// One capture moving through the app: card → editor → pin → saved.
@MainActor
final class CaptureItem: Identifiable {
    let id = UUID()
    /// The pixels as captured. The editor always starts from these, so edits stay editable.
    let original: CGImage
    /// What Copy/Save/Pin use: the original with any edits burned in.
    private(set) var image: CGImage
    /// The edits, so reopening the editor shows them as objects again.
    private(set) var document: AnnotationDocument?
    /// The editor's full state (with undo history) from the last time it was open.
    var editorState: AnnotationEditor?
    /// Pixels per point (2 for Retina).
    let scale: CGFloat
    let createdAt: Date
    /// The display it came from (cards show there).
    let displayID: CGDirectDisplayID?
    /// Where Save last wrote this version (cleared by new edits).
    var savedURL: URL?
    /// Where Save last wrote any version, so saving again after edits updates that file.
    var lastSavedURL: URL?
    /// What it is, for window titles: "Screenshot … at …", "Clipboard Image", a file name.
    var sourceName = "Image"
    /// A screen recording (MP4 or GIF). `image` is then its first frame (the poster).
    var media: MediaFile?
    var isMedia: Bool { media != nil }
    /// QR codes found in `image` (filled in after the card appears).
    var codes: [ScannedCode] = []
    /// The image `codes` were read from, so a scan of an older version is dropped.
    var codesScanned: CGImage?
    /// Its Capture History entry, once recorded.
    var historyID: UUID?
    /// The entry's current file in history: what drags hand over when history is on (a
    /// persistent file, so a receiver that copies it after the drag ends always finds it).
    var historyFile: URL?
    /// A temporary file for drag-out, written in the background.
    private(set) var temporaryURL: URL?
    private var writeTask: Task<URL?, Never>?

    init(image: CGImage, scale: CGFloat, displayID: CGDirectDisplayID?, createdAt: Date = Date()) {
        original = image
        self.image = image
        self.scale = max(scale, 1)
        self.displayID = displayID
        self.createdAt = createdAt
    }

    /// Size in points.
    var size: CGSize {
        CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    }

    var pixelSizeDescription: String { "\(image.width) × \(image.height)" }

    var fileBaseName: String {
        guard sourceName == "Image" || sourceName == "Clipboard Image" else { return sourceName }
        return FileNaming.baseName(template: AppModel.shared.fileNameTemplate, type: isMedia ? "Recording" : "Screenshot", date: createdAt)
    }

    var nsImage: NSImage { NSImage(cgImage: image, size: size) }

    /// Applies edits from the editor.
    func apply(_ document: AnnotationDocument, rendered: CGImage) {
        self.document = document.isEdited ? document : nil
        image = rendered
        savedURL = nil
        // Edits can cover or blur a code: read the new version again.
        codes = []
        codesScanned = nil
        invalidateTemporaryFile()
    }

    // MARK: Temporary file

    /// Starts writing the temporary file (for drag-out) in the background.
    func prepareTemporaryFile(format: ImageFormat) {
        guard writeTask == nil, media == nil else { return }
        let image = self.image
        let name = fileBaseName
        writeTask = Task.detached(priority: .utility) {
            Self.writeTemporary(image, name: name, format: format)
        }
        Task { [weak self] in
            let url = await self?.writeTask?.value
            self?.temporaryURL = url
        }
    }

    /// The file a drag hands over: the history file when history keeps this capture, else a
    /// temporary file (written now if the background write hasn't finished).
    func temporaryFile(format: ImageFormat) -> URL? {
        if let media { return media.url }
        if let historyFile, FileManager.default.fileExists(atPath: historyFile.path) { return historyFile }
        if let url = writeHistoryFileNow(format: format) { return url }
        if let temporaryURL, FileManager.default.fileExists(atPath: temporaryURL.path) { return temporaryURL }
        let url = Self.writeTemporary(image, name: fileBaseName, format: format)
        temporaryURL = url
        return url
    }

    /// How long a superseded drag file stays on disk. A drop hands Finder (or any app) only
    /// the file's URL, and the receiver copies it after the drag has ended, so deleting it
    /// right away fails the copy ("one or more required items can't be found"). Every file
    /// has its own folder, so a late delete never touches a newer one; whatever is left goes
    /// when Snapper quits or next launches (`TemporaryFiles.clear()`).
    nonisolated static let temporaryFileGrace: TimeInterval = 300

    private func invalidateTemporaryFile() {
        writeTask?.cancel()
        writeTask = nil
        if let folder = temporaryURL?.deletingLastPathComponent() {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.temporaryFileGrace) {
                try? FileManager.default.removeItem(at: folder)
            }
        }
        temporaryURL = nil
    }

    func discardTemporaryFile() {
        invalidateTemporaryFile()
    }

    /// A drag right after an edit, before the history update has landed: write the current
    /// version straight into the entry's folder, under the name the update will give it too.
    private func writeHistoryFileNow(format: ImageFormat) -> URL? {
        guard let historyID else { return nil }
        let folder = AppModel.shared.history.store.folder(for: historyID)
        guard FileManager.default.fileExists(atPath: folder.path) else { return nil }
        let url = folder.appendingPathComponent(HistoryStore.safeName(fileBaseName) + "." + format.fileExtension)
        do {
            try ImageEncoder.data(for: image, format: format).write(to: url, options: .atomic)
        } catch {
            return nil
        }
        historyFile = url
        return url
    }

    nonisolated private static func writeTemporary(_ image: CGImage, name: String, format: ImageFormat) -> URL? {
        // Each capture gets its own folder so the dragged file keeps the plain name.
        let folder = TemporaryFiles.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("\(name).\(format.fileExtension)")
            try ImageEncoder.data(for: image, format: format).write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

/// Snapper's temporary folder. Emptied at launch and quit; captures never outlive the session.
enum TemporaryFiles {
    nonisolated static let root: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("app.slopapp.snapper", isDirectory: true)

    static func clear() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// A recording's file. It lives in Snapper's temporary folder until it's saved or copied.
struct MediaFile {
    let url: URL
    let duration: TimeInterval
    var isGIF: Bool { url.pathExtension.lowercased() == "gif" }
}

/// A closed capture parked on disk for "Reopen Last Capture".
struct ClosedCapture {
    let url: URL
    let scale: CGFloat
    let displayID: CGDirectDisplayID?
    let createdAt: Date
    var media: MediaFile?

    nonisolated static func write(_ image: CGImage) -> URL? {
        let folder = TemporaryFiles.root.appendingPathComponent("closed", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("\(UUID().uuidString).png")
            try ImageEncoder.data(for: image, format: .png).write(to: url)
            return url
        } catch {
            return nil
        }
    }

    func load() -> CGImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return ImageEncoder.image(from: data)
    }
}

/// Gives freed image memory back to the system a moment after big buffers go away
/// (frozen screens, closed captures), so idle memory returns to baseline.
@MainActor
enum Memory {
    private static var task: Task<Void, Never>?

    static func relieveSoon() {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            malloc_zone_pressure_relief(nil, 0)
        }
    }
}
