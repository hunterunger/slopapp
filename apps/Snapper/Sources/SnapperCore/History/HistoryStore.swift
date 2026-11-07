import CoreGraphics
import Foundation
import ImageIO

/// What a new history entry is made from.
public struct HistoryCapture: Sendable {
    public var id: UUID
    public var createdAt: Date
    public var kind: HistoryKind
    public var scale: Double
    /// The current version (edits burned in). For recordings, the poster.
    public var image: CGImage
    /// The unedited capture (images only).
    public var original: CGImage?
    public var document: AnnotationDocument?
    /// A recording's file, copied into history.
    public var media: URL?
    public var duration: Double?
    public var format: ImageFormat
    /// The file name without extension ("Screenshot 2026-11-07 at 10.42.03").
    public var baseName: String
    public var source: SourceApp?

    public init(id: UUID, createdAt: Date, kind: HistoryKind, scale: Double, image: CGImage, original: CGImage?,
                document: AnnotationDocument? = nil, media: URL? = nil, duration: Double? = nil, format: ImageFormat,
                baseName: String, source: SourceApp?) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.scale = scale
        self.image = image
        self.original = original
        self.document = document
        self.media = media
        self.duration = duration
        self.format = format
        self.baseName = baseName
        self.source = source
    }
}

/// Capture History on disk: one folder per capture under `root`, and `index.json`. All file
/// work happens on this actor, off the main thread.
///
///     root/index.json
///     root/<id>/Screenshot 2026-11-07 at 10.42.03.png   (current version, the file people drag)
///     root/<id>/original.png                            (as captured, for editable edits)
///     root/<id>/annotations.json                        (the edits, when edited)
///     root/<id>/poster.png                              (recordings)
///     root/.deleted/<id>/                               (deleted, until purged: undo)
public actor HistoryStore {
    public nonisolated let root: URL
    private var index: HistoryIndex?
    private let fileManager = FileManager.default

    public init(root: URL) {
        self.root = root
    }

    public nonisolated func folder(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    public nonisolated func fileURL(for entry: HistoryEntry) -> URL { folder(for: entry.id).appendingPathComponent(entry.fileName) }
    public nonisolated func originalURL(for entry: HistoryEntry) -> URL? {
        entry.originalFileName.map { folder(for: entry.id).appendingPathComponent($0) }
    }
    public nonisolated func posterURL(for entry: HistoryEntry) -> URL? {
        entry.posterFileName.map { folder(for: entry.id).appendingPathComponent($0) }
    }
    /// What the History window shows for an entry: the current image, or a recording's poster.
    public nonisolated func thumbnailSourceURL(for entry: HistoryEntry) -> URL {
        posterURL(for: entry) ?? fileURL(for: entry)
    }

    private var indexURL: URL { root.appendingPathComponent("index.json") }
    private var trash: URL { root.appendingPathComponent(".deleted", isDirectory: true) }

    // MARK: Reading

    /// The index (read once, then kept in memory). Entries whose folder is gone are dropped.
    public func load() -> HistoryIndex {
        if let index { return index }
        var loaded = (try? Data(contentsOf: indexURL)).map(HistoryIndex.decode) ?? HistoryIndex()
        let missing = Set(loaded.entries.filter { !fileManager.fileExists(atPath: fileURL(for: $0).path) }.map(\.id))
        if !missing.isEmpty { loaded.remove(missing) }
        index = loaded
        if !missing.isEmpty { save() }
        return loaded
    }

    public func entry(_ id: UUID) -> HistoryEntry? { load().entry(id) }

    public func document(for entry: HistoryEntry) -> AnnotationDocument? {
        guard let name = entry.documentFileName,
              let data = try? Data(contentsOf: folder(for: entry.id).appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(AnnotationDocument.self, from: data)
    }

    /// What restoring an entry needs: its current image (a recording's poster), the unedited
    /// original and the edits. Nil if its files are gone.
    public func restorable(_ entry: HistoryEntry) -> (current: CGImage, original: CGImage?, document: AnnotationDocument?)? {
        let currentURL = entry.kind.isMedia ? posterURL(for: entry) : fileURL(for: entry)
        guard let currentURL, let current = Self.image(at: currentURL) else { return nil }
        if entry.kind.isMedia { return (current, nil, nil) }
        return (current, originalURL(for: entry).flatMap(Self.image(at:)), document(for: entry))
    }

    static func image(at url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return ImageEncoder.image(from: data)
    }

    // MARK: Writing

    /// Writes a new capture's folder and adds it to the index.
    @discardableResult
    public func add(_ capture: HistoryCapture) throws -> HistoryEntry {
        var index = load()
        let folder = folder(for: capture.id)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        var entry = HistoryEntry(id: capture.id, createdAt: capture.createdAt, kind: capture.kind,
                                 pixelWidth: capture.image.width, pixelHeight: capture.image.height, scale: capture.scale,
                                 fileName: "", source: capture.source, duration: capture.duration)
        do {
            if let media = capture.media {
                let name = Self.safeName(capture.baseName) + "." + media.pathExtension.lowercased()
                try fileManager.copyItem(at: media, to: folder.appendingPathComponent(name))
                entry.fileName = name
                try ImageEncoder.data(for: capture.image, format: .png).write(to: folder.appendingPathComponent("poster.png"))
                entry.posterFileName = "poster.png"
            } else {
                entry.fileName = try writeCurrent(capture.image, format: capture.format, baseName: capture.baseName, in: folder)
                if let original = capture.original {
                    try ImageEncoder.data(for: original, format: .png).write(to: folder.appendingPathComponent("original.png"))
                    entry.originalFileName = "original.png"
                }
                entry.documentFileName = try writeDocument(capture.document, in: folder)
            }
        } catch {
            try? fileManager.removeItem(at: folder)
            throw error
        }
        entry.byteSize = Self.size(of: folder)
        index.insert(entry)
        self.index = index
        save()
        return entry
    }

    /// After an edit: the new current version and the edits.
    @discardableResult
    public func update(_ id: UUID, image: CGImage, document: AnnotationDocument?, format: ImageFormat, baseName: String) throws -> HistoryEntry? {
        var index = load()
        guard let old = index.entry(id) else { return nil }
        let folder = folder(for: id)
        let name = try writeCurrent(image, format: format, baseName: baseName, in: folder)
        if name != old.fileName { try? fileManager.removeItem(at: folder.appendingPathComponent(old.fileName)) }
        let documentName = try writeDocument(document, in: folder)
        if documentName == nil, let previous = old.documentFileName {
            try? fileManager.removeItem(at: folder.appendingPathComponent(previous))
        }
        index.update(id) { entry in
            entry.fileName = name
            entry.documentFileName = documentName
            entry.pixelWidth = image.width
            entry.pixelHeight = image.height
            entry.byteSize = Self.size(of: folder)
        }
        self.index = index
        save()
        return index.entry(id)
    }

    public func setSavedPath(_ id: UUID, _ path: String) {
        var index = load()
        index.update(id) { $0.savedPath = path }
        self.index = index
        save()
    }

    // MARK: Removing

    /// Moves entries out of the index into `.deleted` (undo can bring them back).
    @discardableResult
    public func delete(_ ids: Set<UUID>) -> [HistoryEntry] {
        var index = load()
        let removed = index.remove(ids)
        try? fileManager.createDirectory(at: trash, withIntermediateDirectories: true)
        for entry in removed {
            let target = trash.appendingPathComponent(entry.id.uuidString, isDirectory: true)
            try? fileManager.removeItem(at: target)
            try? fileManager.moveItem(at: folder(for: entry.id), to: target)
        }
        self.index = index
        save()
        return removed
    }

    /// Undo for `delete`.
    public func restoreDeleted(_ entries: [HistoryEntry]) {
        var index = load()
        for entry in entries {
            let source = trash.appendingPathComponent(entry.id.uuidString, isDirectory: true)
            guard (try? fileManager.moveItem(at: source, to: folder(for: entry.id))) != nil else { continue }
            index.insert(entry)
        }
        self.index = index
        save()
    }

    /// Erases deleted folders for good.
    public func purgeDeleted() {
        try? fileManager.removeItem(at: trash)
    }

    /// Erases what `retention` no longer keeps (never `protected` ones). Returns their ids.
    @discardableResult
    public func prune(retention: HistoryRetention, now: Date, protected: Set<UUID> = []) -> [UUID] {
        var index = load()
        let expired = index.expired(retention: retention, now: now, protected: protected)
        guard !expired.isEmpty else { return [] }
        for entry in expired { try? fileManager.removeItem(at: folder(for: entry.id)) }
        index.remove(Set(expired.map(\.id)))
        self.index = index
        save()
        return expired.map(\.id)
    }

    /// Clear History: erases every entry but `protected` ones, and the deleted ones.
    @discardableResult
    public func clear(protected: Set<UUID> = []) -> [UUID] {
        var index = load()
        let gone = index.entries.filter { !protected.contains($0.id) }
        for entry in gone { try? fileManager.removeItem(at: folder(for: entry.id)) }
        index.remove(Set(gone.map(\.id)))
        self.index = index
        save()
        purgeDeleted()
        // Stray folders that never made it into the index (a crash mid-write).
        let keep = Set(index.entries.map(\.id.uuidString))
        for url in (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        where url.hasDirectoryPath && !url.lastPathComponent.hasPrefix(".") && !keep.contains(url.lastPathComponent) {
            try? fileManager.removeItem(at: url)
        }
        return gone.map(\.id)
    }

    // MARK: Helpers

    private func save() {
        guard let index, let data = try? index.encoded() else { return }
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try? data.write(to: indexURL, options: .atomic)
    }

    private func writeCurrent(_ image: CGImage, format: ImageFormat, baseName: String, in folder: URL) throws -> String {
        let name = Self.safeName(baseName) + "." + format.fileExtension
        try ImageEncoder.data(for: image, format: format).write(to: folder.appendingPathComponent(name), options: .atomic)
        return name
    }

    private func writeDocument(_ document: AnnotationDocument?, in folder: URL) throws -> String? {
        guard let document, document.isEdited else { return nil }
        let url = folder.appendingPathComponent("annotations.json")
        try JSONEncoder().encode(document).write(to: url, options: .atomic)
        return url.lastPathComponent
    }

    /// A name safe for a file ("/" and ":" replaced), never empty or reserved.
    public static func safeName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let reserved: Set<String> = ["", "original", "poster", "annotations", "index"]
        return reserved.contains(cleaned.lowercased()) ? "Capture" : cleaned
    }

    static func size(of folder: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileSizeKey]
        var total: Int64 = 0
        for case let url as URL in FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys)) ?? .init() {
            let values = try? url.resourceValues(forKeys: keys)
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }
}

/// Small, fast thumbnails for the History window (ImageIO downsampling, never the full image).
public enum HistoryThumbnail {
    public static func make(from url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
