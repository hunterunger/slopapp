import Darwin
import Foundation

/// The real file system. `trashDirectory` (SLOPAPP_TRASH_DIR) replaces the Trash in tests.
public struct LocalFiles: FileOperating {
    public var trashDirectory: URL?

    public init(trashDirectory: URL? = nil) {
        self.trashDirectory = trashDirectory
    }

    private var fm: FileManager { .default }

    public func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    public func contents(of directory: URL) -> [URL] {
        (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    }

    public func createDirectory(_ url: URL) throws {
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func scratchDirectory(near url: URL) throws -> URL {
        if let dir = try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true) {
            return dir
        }
        let dir = fm.temporaryDirectory.appendingPathComponent("slopapp-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func move(_ source: URL, to destination: URL) throws {
        try fm.moveItem(at: source, to: destination)
    }

    public func remove(_ url: URL) throws {
        try fm.removeItem(at: url)
    }

    public func trash(_ url: URL) throws -> URL {
        if let trashDirectory {
            try fm.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
            var target = trashDirectory.appendingPathComponent(url.lastPathComponent)
            var n = 2
            // Like the Finder: "name 2.ext" for files and bundles, "name 2" for plain folders
            // (whose dots, as in "app.slopapp.awake", aren't extensions).
            let isPlainFolder = url.hasDirectoryPath && !["app", "savedState", "bundle"].contains(url.pathExtension)
            while fm.fileExists(atPath: target.path) {
                let name = url.lastPathComponent
                let base = isPlainFolder ? name : url.deletingPathExtension().lastPathComponent
                let ext = isPlainFolder ? "" : url.pathExtension
                target = trashDirectory.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
                n += 1
            }
            try fm.moveItem(at: url, to: target)
            return target
        }
        var result: NSURL?
        try fm.trashItem(at: url, resultingItemURL: &result)
        return (result as URL?) ?? url
    }

    public func isWritable(_ url: URL) -> Bool {
        fm.fileExists(atPath: url.path) && fm.isWritableFile(atPath: url.path)
    }

    public func availableSpace(at url: URL) -> Int64? {
        var probe = url
        while !fm.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
            probe.deleteLastPathComponent()
        }
        let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    public func clearQuarantine(_ url: URL) {
        let name = "com.apple.quarantine"
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil) else { return }
        removexattr(url.path, name, XATTR_NOFOLLOW)
        for case let item as URL in enumerator {
            removexattr(item.path, name, XATTR_NOFOLLOW)
        }
    }
}
