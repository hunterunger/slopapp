import Darwin
import Foundation

/// Output names that never overwrite anything: "photos", "photos 2", "photos 3"…
public enum Naming {
    /// "name 2.ext" style candidate number `n` (1 → the name itself).
    public static func candidate(_ name: String, number: Int, isFolder: Bool) -> String {
        guard number > 1 else { return name }
        let ns = name as NSString
        let ext = ns.pathExtension
        // Folders and extension-less names get the number at the end. "x.tar.gz" keeps
        // its double extension together.
        if isFolder || ext.isEmpty || ns.deletingPathExtension.isEmpty {
            return "\(name) \(number)"
        }
        var stem = ns.deletingPathExtension
        var fullExt = ext
        let inner = (stem as NSString).pathExtension
        if ["tar", "cpio"].contains(inner.lowercased()) {
            stem = (stem as NSString).deletingPathExtension
            fullExt = inner + "." + ext
        }
        return "\(stem) \(number).\(fullExt)"
    }

    /// The first free name in `folder` (checked against the disk).
    public static func uniqueURL(for name: String, in folder: URL, isFolder: Bool) -> URL {
        var number = 1
        while true {
            let url = folder.appendingPathComponent(candidate(name, number: number, isFolder: isFolder), isDirectory: isFolder)
            if !exists(url) { return url }
            number += 1
        }
    }

    /// Moves `source` to a free name based on `name` in `folder`, atomically refusing to
    /// replace anything (`RENAME_EXCL`). Both must be on the same volume. Returns where it went.
    public static func moveIntoPlace(_ source: URL, named name: String, in folder: URL, isFolder: Bool) throws -> URL {
        var number = 1
        while number < 10_000 {
            let target = folder.appendingPathComponent(candidate(name, number: number, isFolder: isFolder), isDirectory: isFolder)
            let result = source.withUnsafeFileSystemRepresentation { from in
                target.withUnsafeFileSystemRepresentation { to in
                    renamex_np(from!, to!, UInt32(RENAME_EXCL))
                }
            }
            if result == 0 { return target }
            let code = errno
            guard code == EEXIST || code == ENOTEMPTY else {
                throw CrateError.writeFailed(name: name, detail: String(cString: strerror(code)))
            }
            number += 1
        }
        throw CrateError.writeFailed(name: name, detail: "Too many items with this name")
    }

    /// Like `FileManager.fileExists`, but also true for broken symlinks.
    public static func exists(_ url: URL) -> Bool {
        var info = stat()
        return url.withUnsafeFileSystemRepresentation { lstat($0!, &info) } == 0
    }

    /// A hidden working folder inside `folder`, on the same volume so the result can be
    /// moved into place instantly. Resolved through symlinks (libarchive's symlink check
    /// refuses paths through `/tmp` → `/private/tmp`).
    public static func makeWorkFolder(in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(".crate-\(UUID().uuidString.prefix(8))", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            throw CrateError.destinationNotWritable(folder: folder.lastPathComponent)
        }
        let real = realPath(url)
        WorkFolderLedger.shared.add(real)
        return real
    }

    /// The path with every symlink resolved (`/tmp/x` → `/private/tmp/x`). Foundation's
    /// `resolvingSymlinksInPath` maps `/private` back, which libarchive then refuses.
    public static func realPath(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: url.hasDirectoryPath)
    }

    public static func removeWorkFolder(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        WorkFolderLedger.shared.remove(url)
    }
}

/// Remembers working folders while they exist, so ones left behind by a crash can be
/// removed on the next launch. Only folders recorded by an earlier run are ever removed,
/// never ones in use now.
public final class WorkFolderLedger: @unchecked Sendable {
    public static let shared = WorkFolderLedger()
    private let lock = NSLock()
    private var file: URL?
    private var current: Set<String> = []
    private var leftovers: Set<String> = []

    /// Where the list lives. Takes over whatever an earlier run left in it as leftovers.
    /// Unset (tests, tools): nothing is recorded.
    public func configure(file: URL) {
        lock.withLock {
            self.file = file
            let previous = (try? String(contentsOf: file, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
            leftovers = Set(previous)
            current = []
            save()
        }
    }

    func add(_ url: URL) {
        lock.withLock {
            guard file != nil else { return }
            current.insert(url.standardizedFileURL.path)
            save()
        }
    }

    func remove(_ url: URL) {
        lock.withLock {
            guard file != nil else { return }
            current.remove(url.standardizedFileURL.path)
            save()
        }
    }

    /// Deletes the `.crate-` folders an earlier run left behind.
    public func cleanUpLeftovers() {
        let paths = lock.withLock { () -> Set<String> in
            defer { leftovers = [] }
            return leftovers
        }
        for path in paths where (path as NSString).lastPathComponent.hasPrefix(".crate-") {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private func save() {
        guard let file else { return }
        try? current.sorted().joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }
}
