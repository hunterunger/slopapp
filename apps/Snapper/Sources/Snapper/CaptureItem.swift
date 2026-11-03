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
        sourceName == "Image" || sourceName == "Clipboard Image" ? FileNaming.baseName(for: createdAt) : sourceName
    }

    var nsImage: NSImage { NSImage(cgImage: image, size: size) }

    /// Applies edits from the editor.
    func apply(_ document: AnnotationDocument, rendered: CGImage) {
        self.document = document.isEdited ? document : nil
        image = rendered
        savedURL = nil
        invalidateTemporaryFile()
    }

    // MARK: Temporary file

    /// Starts writing the temporary file (for drag-out) in the background.
    func prepareTemporaryFile(format: ImageFormat) {
        guard writeTask == nil else { return }
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

    /// The temporary file, written now if the background write hasn't finished.
    func temporaryFile(format: ImageFormat) -> URL? {
        if let temporaryURL, FileManager.default.fileExists(atPath: temporaryURL.path) { return temporaryURL }
        let url = Self.writeTemporary(image, name: fileBaseName, format: format)
        temporaryURL = url
        return url
    }

    private func invalidateTemporaryFile() {
        writeTask?.cancel()
        writeTask = nil
        if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL.deletingLastPathComponent()) }
        temporaryURL = nil
    }

    func discardTemporaryFile() {
        invalidateTemporaryFile()
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

/// A closed capture parked on disk for "Reopen Last Capture".
struct ClosedCapture {
    let url: URL
    let scale: CGFloat
    let displayID: CGDirectDisplayID?
    let createdAt: Date

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
