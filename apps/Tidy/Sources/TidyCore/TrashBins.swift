import Foundation

/// One thing sitting in a Trash folder.
public struct TrashBinItem: Sendable, Hashable, Identifiable {
    public var id: String { url.path }
    public var url: URL
    /// The Trash folder it's in.
    public var bin: URL
    public var isDirectory: Bool
    /// When it was put in the Trash (the item's change date), if known.
    public var dateTrashed: Date?

    public var name: String { url.lastPathComponent }

    public init(url: URL, bin: URL, isDirectory: Bool, dateTrashed: Date? = nil) {
        self.url = url
        self.bin = bin
        self.isDirectory = isDirectory
        self.dateTrashed = dateTrashed
    }
}

public struct TrashBinScan: Sendable {
    public var items: [TrashBinItem] = []
    /// Trash folders that couldn't be read (on a real Mac: no Full Disk Access).
    public var unreadable: [URL] = []

    public init(items: [TrashBinItem] = [], unreadable: [URL] = []) {
        self.items = items
        self.unreadable = unreadable
    }
}

/// Lists what's in the Trash. Read-only.
public struct TrashBinScanner: Sendable {
    public var bins: [URL]

    public init(bins: [URL]) {
        self.bins = bins.map(\.standardizedFileURL)
    }

    public init(environment: TidyEnvironment) {
        self.init(bins: environment.trashBins)
    }

    public func scan() -> TrashBinScan {
        var result = TrashBinScan()
        let fm = FileManager.default
        for bin in bins {
            guard fm.fileExists(atPath: bin.path) else { continue }
            guard let names = try? fm.contentsOfDirectory(atPath: bin.path) else {
                result.unreadable.append(bin)
                continue
            }
            // .DS_Store and friends aren't something people put in the Trash.
            for name in names.sorted() where name != ".DS_Store" && name != ".localized" {
                let url = bin.appendingPathComponent(name)
                var info = stat()
                guard lstat(url.path, &info) == 0 else { continue }
                let isDirectory = (info.st_mode & S_IFMT) == S_IFDIR
                let changed = Date(timeIntervalSince1970: TimeInterval(info.st_ctimespec.tv_sec))
                result.items.append(TrashBinItem(url: url, bin: bin, isDirectory: isDirectory, dateTrashed: changed))
            }
        }
        return result
    }
}

/// Why Tidy won't erase something.
public enum EraseRefusal: Error, Equatable, Sendable, CustomStringConvertible {
    case notInTrash

    public var description: String {
        switch self {
        case .notInTrash: "It isn't in the Trash."
        }
    }
}

/// Erasing files for good. The only permanent delete in Tidy, and only for things already in
/// the Trash (emptying it).
public protocol Eraser: Sendable {
    func erase(_ url: URL) throws
}

public struct FileEraser: Eraser {
    public init() {}

    public func erase(_ url: URL) throws {
        let fm = FileManager.default
        do {
            try fm.removeItem(at: url)
        } catch {
            // Read-only folders inside (Finder asks about locked items; Tidy just makes the
            // folders it's erasing writable, inside the Trash only) and try once more.
            guard let walker = fm.enumerator(atPath: url.path) else { throw error }
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            for case let relative as String in walker {
                let path = url.appendingPathComponent(relative).path
                var isDirectory: ObjCBool = false
                if fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
                }
            }
            try fm.removeItem(at: url)
        }
    }
}

public struct EraseResult: Sendable {
    public var erased: [URL] = []
    public var bytes: Int64 = 0
    public var failures: [TrashFailure] = []
}

/// Empties the Trash: erases exactly the items it's given, each only if it sits directly
/// inside one of the Trash folders.
public struct TrashBinService: Sendable {
    public let bins: [URL]
    public let eraser: Eraser

    public init(bins: [URL], eraser: Eraser = FileEraser()) {
        self.bins = bins.map(\.standardizedFileURL)
        self.eraser = eraser
    }

    public init(environment: TidyEnvironment, eraser: Eraser = FileEraser()) {
        self.init(bins: environment.trashBins, eraser: eraser)
    }

    /// Throws unless `url` is directly inside a Trash folder (never the folder itself, never
    /// something deeper, never through a symlinked parent).
    public func check(_ url: URL) throws {
        let item = url.standardizedFileURL
        let parent = item.deletingLastPathComponent().resolvingSymlinksInPath().path
        let name = item.lastPathComponent
        guard url.isFileURL, !name.isEmpty, name != ".", name != "..",
              bins.contains(where: { $0.resolvingSymlinksInPath().path == parent }) else {
            throw EraseRefusal.notInTrash
        }
    }

    public func erase(_ items: [(url: URL, bytes: Int64)]) -> EraseResult {
        var result = EraseResult()
        for item in items {
            do {
                try check(item.url)
                try eraser.erase(item.url)
                result.erased.append(item.url)
                result.bytes += item.bytes
            } catch {
                let message = (error as? EraseRefusal)?.description ?? TrashService.message(for: error)
                result.failures.append(TrashFailure(url: item.url, message: message))
            }
        }
        return result
    }
}
