import Darwin
import Foundation

/// Why a file couldn't be converted. Every message says what happened and what to do next.
public enum ConvertError: LocalizedError, Equatable {
    /// A container macOS has no reader for (MKV, WebM…).
    case unreadableFormat(name: String, format: String)
    /// Not a video, audio file or image.
    case unsupported(name: String)
    /// Looked like media but couldn't be decoded.
    case damaged(name: String)
    case protected(name: String)
    case noSound(name: String)
    case empty(name: String)
    case encodeFailed(name: String)
    case diskFull(name: String)
    case cantWrite(folder: String)
    case noFolder(folder: String)
    case tooManyNames(name: String)
    case cantWriteFormat(format: String, kind: MediaKind)

    /// Trying the same file again can't work (only another file or another app can help).
    public var isFinal: Bool {
        switch self {
        case .unreadableFormat, .unsupported, .damaged, .protected, .empty: true
        default: false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .unreadableFormat(_, let format): "Convert can't read \(format) files. macOS has no reader for them."
        case .unsupported(let name): "\(name) isn't a video, audio file or image."
        case .damaged(let name): "Couldn't read \(name)."
        case .protected(let name): "\(name) is copy-protected, so it can't be converted."
        case .noSound(let name): "\(name) has no sound to extract."
        case .empty(let name): "\(name) has no picture or sound in it."
        case .encodeFailed(let name): "Couldn't convert \(name)."
        case .diskFull(let name): "There isn't enough disk space to save \(name)."
        case .cantWrite(let folder): "Couldn't save in “\(folder)”."
        case .noFolder(let folder): "The folder “\(folder)” isn't there anymore."
        case .tooManyNames(let name): "Couldn't find a free name for \(name)."
        case .cantWriteFormat(let format, _): "This Mac can't save \(format) files."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .unreadableFormat: "A free tool like HandBrake can convert it."
        case .unsupported: "Convert works with videos, audio files and images."
        case .damaged: "It may be damaged or use a codec macOS can't play. Try opening it in QuickTime Player or Preview."
        case .protected: "Files bought with copy protection can only be played in the app they came from."
        case .noSound: "To convert the picture, choose a video format under Video."
        case .empty: "Try another copy of the file."
        case .encodeFailed: "Try another format or quality."
        case .diskFull: "Free up some space, or choose another folder under Save To, then try again."
        case .cantWrite: "Check that you can write to it, or choose another folder under Save To."
        case .noFolder: "Choose another folder under Save To."
        case .tooManyNames: "Rename or move some files, then try again."
        case .cantWriteFormat(_, let kind): "Choose another format under \(kind.title)."
        }
    }
}

/// File system access Convert needs, behind a protocol so tests can fake failures.
public protocol FileStore: Sendable {
    func size(of url: URL) -> Int64?
    func fileExists(_ url: URL) -> Bool
    func isDirectory(_ url: URL) -> Bool
    func isWritableDirectory(_ url: URL) -> Bool
    /// A fresh scratch location for writing `fileName`, on the same volume as `folder` and
    /// out of the user's sight. `cleanup` removes it (and anything left in it).
    func scratch(for fileName: String, near folder: URL) throws -> (url: URL, cleanup: @Sendable () -> Void)
    /// Moves `source` to `target` only if `target` is free (atomic, never clobbers).
    /// Throws `OutputClash` when the name is taken.
    func moveExclusive(_ source: URL, to target: URL) throws
    /// Atomically puts `source` in the place of `target` (an earlier output of ours).
    func replace(_ target: URL, with source: URL) throws
    /// Copies creation and modification dates.
    func copyDates(from source: URL, to target: URL)
}

/// The target name is taken; try the next one.
public struct OutputClash: Error {}

/// Where a converted file goes and what it's called. Pure.
public enum OutputPlanner {
    /// The folder the output goes in.
    public static func folder(for input: URL, destination: Destination) -> URL {
        switch destination {
        case .alongside: input.deletingLastPathComponent()
        case .folder(let folder): folder
        }
    }

    /// "clip.mov" → "clip.mp4" in the destination folder.
    public static func preferredURL(for input: URL, ext: String, destination: Destination) -> URL {
        folder(for: input, destination: destination)
            .appendingPathComponent(input.deletingPathExtension().lastPathComponent)
            .appendingPathExtension(ext)
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

    /// Moves a finished scratch file to the first free name. Never overwrites anything.
    public static func claim(_ scratch: URL, as preferred: URL, files: any FileStore) throws -> URL {
        for candidate in candidates(for: preferred) {
            do {
                try files.moveExclusive(scratch, to: candidate)
                return candidate
            } catch is OutputClash {
                continue
            }
        }
        throw ConvertError.tooManyNames(name: preferred.lastPathComponent)
    }
}

/// The real file system.
public struct SystemFileStore: FileStore {
    public init() {}

    public func size(of url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    public func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    public func isWritableDirectory(_ url: URL) -> Bool {
        isDirectory(url) && FileManager.default.isWritableFile(atPath: url.path)
    }

    public func scratch(for fileName: String, near folder: URL) throws -> (url: URL, cleanup: @Sendable () -> Void) {
        // A private folder on the same volume (so the final move is a rename), which macOS
        // also cleans up if we're killed mid-write.
        if let dir = try? FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                  appropriateFor: folder, create: true) {
            return (dir.appendingPathComponent(fileName), { try? FileManager.default.removeItem(at: dir) })
        }
        // Some volumes have no such folder: a hidden file next to the output instead.
        let url = folder.appendingPathComponent(".\(UUID().uuidString)-\(fileName)")
        return (url, { try? FileManager.default.removeItem(at: url) })
    }

    public func moveExclusive(_ source: URL, to target: URL) throws {
        if renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) == 0 { return }
        let code = errno
        if code == EEXIST { throw OutputClash() }
        if code == EXDEV {
            // Different volume: copy (which refuses to overwrite), then delete the source.
            if fileExists(target) { throw OutputClash() }
            do {
                try FileManager.default.copyItem(at: source, to: target)
                try? FileManager.default.removeItem(at: source)
                return
            } catch CocoaError.fileWriteFileExists {
                throw OutputClash()
            } catch {
                try? FileManager.default.removeItem(at: target)
            }
        }
        if code == ENOSPC { throw ConvertError.diskFull(name: target.lastPathComponent) }
        throw ConvertError.cantWrite(folder: target.deletingLastPathComponent().lastPathComponent)
    }

    public func replace(_ target: URL, with source: URL) throws {
        if rename(source.path, target.path) == 0 { return }
        let code = errno
        if code == EXDEV, (try? FileManager.default.replaceItemAt(target, withItemAt: source)) != nil { return }
        if code == ENOSPC { throw ConvertError.diskFull(name: target.lastPathComponent) }
        throw ConvertError.cantWrite(folder: target.deletingLastPathComponent().lastPathComponent)
    }

    public func copyDates(from source: URL, to target: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: source.path) else { return }
        var dates: [FileAttributeKey: Any] = [:]
        dates[.creationDate] = attributes[.creationDate]
        dates[.modificationDate] = attributes[.modificationDate]
        try? FileManager.default.setAttributes(dates, ofItemAtPath: target.path)
    }
}
