import Darwin
import Foundation

/// The file-system calls Crate makes besides plain reads and writes, behind a protocol so
/// tests can fake disk space, quarantine and the Trash.
public protocol FileSystem: Sendable {
    /// Free bytes on the volume holding `url` (for important use), or nil if unknown.
    func availableCapacity(at url: URL) -> Int64?
    /// The `com.apple.quarantine` attribute of a file, if it has one.
    func quarantine(of url: URL) -> Data?
    /// Sets `com.apple.quarantine` on a file, folder or link (not following links).
    func setQuarantine(_ value: Data, on url: URL)
    /// Moves an item to the Trash and returns where it went (for Undo).
    func trash(_ url: URL) throws -> URL
    /// Whether the folder can be written to.
    func isWritableFolder(_ url: URL) -> Bool
}

public struct SystemFileSystem: FileSystem {
    public static let quarantineKey = "com.apple.quarantine"
    /// When set (tests, blind testers: `CRATE_TRASH_DIR=/tmp/crate-test/trash`), "Move to
    /// Trash" moves items into this folder instead of the real Trash.
    public let trashOverride: URL?

    public init(trashOverride: URL? = ProcessInfo.processInfo.environment["CRATE_TRASH_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }) {
        self.trashOverride = trashOverride
    }

    public func availableCapacity(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let important = values?.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        return values?.volumeAvailableCapacity.map(Int64.init)
    }

    public func quarantine(of url: URL) -> Data? {
        url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { return nil }
            let size = getxattr(path, Self.quarantineKey, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { getxattr(path, Self.quarantineKey, $0.baseAddress, size, 0, 0) }
            return read > 0 ? data.prefix(read) : nil
        }
    }

    public func setQuarantine(_ value: Data, on url: URL) {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = value.withUnsafeBytes { setxattr(path, Self.quarantineKey, $0.baseAddress, value.count, 0, XATTR_NOFOLLOW) }
        }
    }

    public func trash(_ url: URL) throws -> URL {
        if let trashOverride {
            try FileManager.default.createDirectory(at: trashOverride, withIntermediateDirectories: true)
            return try Naming.moveIntoPlace(url, named: url.lastPathComponent, in: trashOverride, isFolder: false)
        }
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return (result as URL?) ?? url
    }

    public func isWritableFolder(_ url: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: url.path)
    }
}

/// Items Crate moved to the Trash, so Undo can put them back.
public struct TrashMove: Sendable, Equatable {
    public let original: URL
    public let trashed: URL

    public init(original: URL, trashed: URL) {
        self.original = original
        self.trashed = trashed
    }

    /// Moves it back. If something new took its name meanwhile, it comes back as "name 2".
    public func putBack() throws {
        let folder = original.deletingLastPathComponent()
        let target = Naming.exists(original) ? Naming.uniqueURL(for: original.lastPathComponent, in: folder, isFolder: false) : original
        try FileManager.default.moveItem(at: trashed, to: target)
    }
}

/// Whether a path is in a Trash, where nothing should be extracted to.
public enum TrashLocation {
    public static func contains(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if url.pathComponents.contains(where: { $0 == ".Trash" || $0 == ".Trashes" }) { return true }
        if let override = ProcessInfo.processInfo.environment["CRATE_TRASH_DIR"], !override.isEmpty,
           path.hasPrefix(URL(fileURLWithPath: override).standardizedFileURL.path) {
            return true
        }
        if let trash = try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false),
           path.hasPrefix(trash.standardizedFileURL.path + "/") {
            return true
        }
        return false
    }

    /// Where to put things when the natural place is a Trash: ~/Downloads
    /// (`CRATE_DOWNLOADS_DIR` overrides it for tests).
    public static var fallbackFolder: URL {
        if let override = ProcessInfo.processInfo.environment["CRATE_DOWNLOADS_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }
}
