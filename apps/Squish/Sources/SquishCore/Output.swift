import CryptoKit
import Darwin
import Foundation

/// File system access Squish needs, behind a protocol so tests can fake it.
public protocol FileStore: Sendable {
    func size(of url: URL) throws -> Int64
    func fileExists(_ url: URL) -> Bool
    func isDirectory(_ url: URL) -> Bool
    /// Writes `data` to `url` only if nothing is there yet (atomic, no clobbering).
    /// Throws `OutputError.exists` when the name is taken.
    func create(_ data: Data, at url: URL) throws
    /// Atomically replaces the file at `url` (which this app wrote earlier) with `data`.
    func overwrite(_ data: Data, at url: URL) throws
    /// Renames a file only if the target name is free. Throws `OutputError.exists` if not.
    func move(_ source: URL, to target: URL) throws
    func remove(_ url: URL)
    /// Moves a file to the Trash and returns where it went.
    @discardableResult
    func trash(_ url: URL) throws -> URL
    /// Copies creation and modification dates.
    func copyDates(from source: URL, to target: URL)
    /// SHA-256 of a file's bytes, hex.
    func sha256(of url: URL) throws -> String
    /// Tags a file Squish wrote (an extended attribute), so it's never compressed twice.
    func markAsOutput(_ url: URL)
    func isMarkedAsOutput(_ url: URL) -> Bool
}

/// The extended attribute on files Squish wrote.
public let squishOutputAttribute = "app.slopapp.squish.output"


public enum OutputError: LocalizedError, Equatable {
    case exists
    case cantWrite(folder: String)
    case noFolder(String)
    case tooManyNames(String)
    case cantTrash(String)
    case cantPutBack(String)
    case originalChanged(String)
    case outputEdited(String)
    case cantReachTrash(String)

    public var errorDescription: String? {
        switch self {
        case .exists: "A file with that name already exists."
        case .cantWrite(let folder): "Couldn't save in “\(folder)”."
        case .noFolder(let folder): "The folder “\(folder)” isn't there anymore."
        case .tooManyNames(let name): "Couldn't find a free name for \(name)."
        case .cantTrash(let name): "Couldn't move \(name) to the Trash, so it was left as it was."
        case .cantPutBack(let name): "Couldn't put back \(name)."
        case .originalChanged(let name): "The copy of \(name) in the Trash isn't the original anymore, so it wasn't put back."
        case .outputEdited(let name): "\(name) was changed after Squish compressed it."
        case .cantReachTrash(let name): "macOS didn't let Squish read the original of \(name) in the Trash."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .exists, .tooManyNames: "Rename or move some files, then try again."
        case .cantWrite: "Check that you can write to it, or choose another folder under Save To."
        case .noFolder: "Choose another folder under Save To."
        case .cantTrash: "Save copies instead of replacing originals, or check the file's permissions."
        case .cantPutBack: "It's no longer in the Trash, or something else now has its name. Look for it in the Trash."
        case .originalChanged: "Look for the original in the Trash and put it back from Finder."
        case .outputEdited: "Putting the original back would move your changed file to the Trash."
        case .cantReachTrash: "Put it back from the Trash in Finder (right-click › Put Back)."
        }
    }
}

/// Where a compressed file goes and what it's called. Pure.
public enum OutputPlanner {
    /// The preferred output URL for `input`, written as `ext`.
    /// - alongside: same folder, name + suffix ("photo-small.jpg").
    /// - folder: that folder, same name; adds the suffix if it's the input's own folder.
    /// - replace: the input's own path (with the new extension if the format changed).
    public static func preferredURL(for input: URL, ext: String, settings: SquishSettings) -> URL {
        let base = input.deletingPathExtension().lastPathComponent
        let inputFolder = input.deletingLastPathComponent()
        switch settings.destination {
        case .alongside:
            return inputFolder.appendingPathComponent(base + settings.effectiveSuffix).appendingPathExtension(ext)
        case .folder(let folder):
            let sameFolder = folder.standardizedFileURL.resolvingSymlinksInPath().path
                == inputFolder.standardizedFileURL.resolvingSymlinksInPath().path
            let name = sameFolder ? base + settings.effectiveSuffix : base
            return folder.appendingPathComponent(name).appendingPathExtension(ext)
        case .replaceOriginal:
            return inputFolder.appendingPathComponent(base).appendingPathExtension(ext)
        }
    }

    /// `url`, then "name 2.ext", "name 3.ext"… like Finder does for duplicates.
    public static func candidates(for url: URL, limit: Int = 500) -> [URL] {
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        return [url] + (2...limit).map { n in
            let name = "\(base) \(n)"
            return ext.isEmpty ? folder.appendingPathComponent(name)
                : folder.appendingPathComponent(name).appendingPathExtension(ext)
        }
    }
}

/// The real file system.
public struct SystemFileStore: FileStore {
    /// When set, "trash" moves files into this folder instead of the user's Trash.
    /// Tests use it, and so does `SQUISH_TRASH_DIR` for scripted runs.
    public var trashFolder: URL?

    public init(trashFolder: URL? = nil) {
        self.trashFolder = trashFolder
    }

    /// The store the app uses: the real Trash unless `SQUISH_TRASH_DIR` points elsewhere.
    public static var app: SystemFileStore {
        let override = ProcessInfo.processInfo.environment["SQUISH_TRASH_DIR"].map { URL(fileURLWithPath: $0) }
        return SystemFileStore(trashFolder: override)
    }

    public func size(of url: URL) throws -> Int64 {
        // Not resourceValues: those are cached per URL object, and files get rewritten in place.
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    public func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    public func create(_ data: Data, at url: URL) throws {
        let temp = try writeTemporary(data, beside: url)
        // RENAME_EXCL makes "take this name only if it's free" a single atomic step, so two
        // files finishing at once can't both claim "photo-small.jpg".
        if renamex_np(temp.path, url.path, UInt32(RENAME_EXCL)) != 0 {
            let code = errno
            try? FileManager.default.removeItem(at: temp)
            if code == EEXIST { throw OutputError.exists }
            throw OutputError.cantWrite(folder: url.deletingLastPathComponent().lastPathComponent)
        }
    }

    public func overwrite(_ data: Data, at url: URL) throws {
        let temp = try writeTemporary(data, beside: url)
        if rename(temp.path, url.path) != 0 {
            try? FileManager.default.removeItem(at: temp)
            throw OutputError.cantWrite(folder: url.deletingLastPathComponent().lastPathComponent)
        }
    }

    public func move(_ source: URL, to target: URL) throws {
        if renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) != 0 {
            let code = errno
            if code == EEXIST { throw OutputError.exists }
            // Another volume (e.g. the Trash of the boot disk): copy-and-delete instead.
            if code == EXDEV, !fileExists(target), (try? FileManager.default.moveItem(at: source, to: target)) != nil {
                return
            }
            throw OutputError.cantWrite(folder: target.deletingLastPathComponent().lastPathComponent)
        }
    }

    public func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    public func trash(_ url: URL) throws -> URL {
        do {
            if let trashFolder {
                try FileManager.default.createDirectory(at: trashFolder, withIntermediateDirectories: true)
                let target = OutputPlanner.candidates(for: trashFolder.appendingPathComponent(url.lastPathComponent))
                    .first { !FileManager.default.fileExists(atPath: $0.path) } ?? trashFolder.appendingPathComponent(UUID().uuidString)
                try FileManager.default.moveItem(at: url, to: target)
                return target
            }
            var result: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &result)
            return (result as URL?) ?? url
        } catch {
            throw OutputError.cantTrash(url.lastPathComponent)
        }
    }

    public func copyDates(from source: URL, to target: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: source.path) else { return }
        var dates: [FileAttributeKey: Any] = [:]
        dates[.creationDate] = attributes[.creationDate]
        dates[.modificationDate] = attributes[.modificationDate]
        try? FileManager.default.setAttributes(dates, ofItemAtPath: target.path)
    }

    public func sha256(of url: URL) throws -> String {
        try FileHash.sha256(of: url)
    }

    public func markAsOutput(_ url: URL) {
        let value: UInt8 = 1
        _ = withUnsafePointer(to: value) { setxattr(url.path, squishOutputAttribute, $0, 1, 0, 0) }
    }

    public func isMarkedAsOutput(_ url: URL) -> Bool {
        getxattr(url.path, squishOutputAttribute, nil, 0, 0, 0) >= 0
    }

    private func writeTemporary(_ data: Data, beside url: URL) throws -> URL {
        let folder = url.deletingLastPathComponent()
        guard isDirectory(folder) else { throw OutputError.noFolder(folder.lastPathComponent) }
        let temp = folder.appendingPathComponent(".squish-\(UUID().uuidString).tmp")
        do {
            try data.write(to: temp)
        } catch {
            throw OutputError.cantWrite(folder: folder.lastPathComponent)
        }
        return temp
    }
}

/// An original that Replace Originals moved to the Trash, and the file that took its place.
public struct Replacement: Sendable, Equatable, Hashable, Codable {
    /// Where the original was (and goes back to).
    public let original: URL
    /// Where it is now.
    public let trashed: URL
    /// The compressed file.
    public let output: URL
    /// SHA-256 of the original's bytes, taken before it was trashed. Put Back checks it,
    /// so it can only ever restore the exact original.
    public let originalSHA256: String
    /// SHA-256 of the compressed file as Squish wrote it, to notice later edits.
    public let outputSHA256: String?

    public init(original: URL, trashed: URL, output: URL, originalSHA256: String, outputSHA256: String? = nil) {
        self.original = original
        self.trashed = trashed
        self.output = output
        self.originalSHA256 = originalSHA256
        self.outputSHA256 = outputSHA256
    }

    func withOutput(_ output: URL, sha256: String?) -> Replacement {
        Replacement(original: original, trashed: trashed, output: output, originalSHA256: originalSHA256, outputSHA256: sha256)
    }

    /// Whether the compressed file was changed after Squish wrote it.
    public func outputWasEdited(files: any FileStore) -> Bool {
        guard let outputSHA256, files.fileExists(output) else { return false }
        return (try? files.sha256(of: output)) != outputSHA256
    }

    /// Moves the compressed file to the Trash and the original back to where it was.
    /// Refuses (and changes nothing) unless the file in the Trash is byte-identical to the
    /// original, and, unless `evenIfEdited`, if the compressed file was edited since.
    public func putBack(files: any FileStore, evenIfEdited: Bool = false) throws {
        let name = original.lastPathComponent
        guard files.fileExists(trashed) else { throw OutputError.cantPutBack(name) }
        let hash: String
        do { hash = try files.sha256(of: trashed) } catch { throw OutputError.cantReachTrash(name) }
        guard hash == originalSHA256 else { throw OutputError.originalChanged(name) }
        if output != original, files.fileExists(original) { throw OutputError.cantPutBack(name) }
        if !evenIfEdited, outputWasEdited(files: files) { throw OutputError.outputEdited(output.lastPathComponent) }
        if files.fileExists(output) {
            // Label the compressed copy so it can't be mistaken for the original in the Trash.
            let label = output.deletingLastPathComponent()
                .appendingPathComponent(output.deletingPathExtension().lastPathComponent + " (compressed copy)")
                .appendingPathExtension(output.pathExtension)
            let renamed = (try? files.move(output, to: label)) != nil
            try files.trash(renamed ? label : output)
        }
        do {
            try files.move(trashed, to: original)
        } catch {
            throw OutputError.cantPutBack(name)
        }
    }
}

/// Every original Replace Originals moved to the Trash, by the compressed file that now
/// stands in its place. Compressing that file again starts from the original. Saved to
/// disk (when given a file) so Put Back works after a relaunch, as long as the originals
/// are still in the Trash.
public final class ReplacementRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var byOutput: [String: Replacement] = [:]
    private let storage: URL?

    public init(storage: URL? = nil) {
        self.storage = storage
        guard let storage, let data = try? Data(contentsOf: storage),
              let saved = try? JSONDecoder().decode([Replacement].self, from: data) else { return }
        // Originals emptied from the Trash can't come back; forget them.
        for replacement in saved where FileManager.default.fileExists(atPath: replacement.trashed.path) {
            byOutput[Self.key(replacement.output)] = replacement
        }
    }

    private static func key(_ url: URL) -> String { url.standardizedFileURL.path }

    private func save() {
        guard let storage else { return }
        let all = Array(byOutput.values).sorted { $0.original.path < $1.original.path }
        try? FileManager.default.createDirectory(at: storage.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(all).write(to: storage, options: .atomic)
    }

    public func record(_ replacement: Replacement) {
        lock.withLock { byOutput[Self.key(replacement.output)] = replacement; save() }
    }

    /// Moves a record to a new output (the compressed file was rewritten).
    public func update(_ old: Replacement, to new: Replacement) {
        lock.withLock {
            byOutput[Self.key(old.output)] = nil
            byOutput[Self.key(new.output)] = new
            save()
        }
    }

    public func remove(_ replacement: Replacement) {
        lock.withLock { _ = byOutput.removeValue(forKey: Self.key(replacement.output)); save() }
    }

    /// The replacement whose compressed file is at `url`, if any.
    public func replacement(outputAt url: URL) -> Replacement? {
        lock.withLock { byOutput[Self.key(url)] }
    }

    public var all: [Replacement] { lock.withLock { Array(byOutput.values) } }
}

enum FileHash {
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
