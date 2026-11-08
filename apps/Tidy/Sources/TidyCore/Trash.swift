import Foundation

/// Moves things to the Trash and back. The real one uses the user's Trash; test mode uses a
/// plain folder.
public protocol Trasher: Sendable {
    /// Moves `url` to the Trash and returns where it ended up.
    func moveToTrash(_ url: URL) throws -> URL
}

/// The user's Trash, via `FileManager.trashItem` (the same Trash Finder uses).
public struct SystemTrasher: Trasher {
    public init() {}

    public func moveToTrash(_ url: URL) throws -> URL {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return (result as URL?) ?? url
    }
}

/// Test mode: "the Trash" is a folder. Name clashes get " 2", " 3"... like Finder.
public struct FolderTrasher: Trasher {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public func moveToTrash(_ url: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var isDirectory: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let keepsExtension = !isDirectory.boolValue || url.pathExtension.lowercased() == "app"
        let destination = Self.uniqueDestination(for: url.lastPathComponent, in: folder, keepsExtension: keepsExtension)
        try fm.moveItem(at: url, to: destination)
        return destination
    }

    /// Folders (other than apps) are numbered at the end: `com.acme.Widget 2`.
    static func uniqueDestination(for name: String, in folder: URL, keepsExtension: Bool = true) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(name)
        let ext = keepsExtension ? (name as NSString).pathExtension : ""
        let base = keepsExtension ? (name as NSString).deletingPathExtension : name
        var number = 2
        while fm.fileExists(atPath: candidate.path) || (try? candidate.checkResourceIsReachable()) == true {
            let numbered = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            candidate = folder.appendingPathComponent(numbered)
            number += 1
        }
        return candidate
    }
}

/// One thing that was moved, so it can be put back.
public struct TrashedItem: Sendable, Hashable, Codable {
    public var original: URL
    public var trashed: URL
    public var bytes: Int64

    public init(original: URL, trashed: URL, bytes: Int64) {
        self.original = original
        self.trashed = trashed
        self.bytes = bytes
    }
}

public struct TrashFailure: Sendable, Hashable {
    public var url: URL
    public var message: String

    public init(url: URL, message: String) {
        self.url = url
        self.message = message
    }
}

public struct TrashResult: Sendable {
    public var moved: [TrashedItem] = []
    public var failures: [TrashFailure] = []
    /// The first item failed and `stopIfFirstFails` was set, so nothing else was tried.
    public var stoppedEarly = false

    public var bytes: Int64 { moved.reduce(0) { $0 + $1.bytes } }
}

/// Every move to the Trash goes through here: policy check, move, record.
public struct TrashService: Sendable {
    public let policy: TrashPolicy
    public let trasher: Trasher

    public init(environment: TidyEnvironment, trasher: Trasher? = nil, allowedVolumeRoots: [URL] = []) {
        policy = TrashPolicy(environment: environment, allowedVolumeRoots: allowedVolumeRoots)
        self.trasher = trasher ?? environment.trashDirectory.map { FolderTrasher(folder: $0) as Trasher } ?? SystemTrasher()
    }

    /// Moves `items` (url and size) in order. With `stopIfFirstFails`, a failure on the first
    /// item (the app itself, when uninstalling) leaves everything else in place.
    public func moveToTrash(_ items: [(url: URL, bytes: Int64)], stopIfFirstFails: Bool = false) -> TrashResult {
        var result = TrashResult()
        for (index, item) in items.enumerated() {
            do {
                try policy.check(item.url)
                let trashed = try trasher.moveToTrash(item.url)
                result.moved.append(TrashedItem(original: item.url, trashed: trashed, bytes: item.bytes))
            } catch {
                result.failures.append(TrashFailure(url: item.url, message: Self.message(for: error)))
                if index == 0 && stopIfFirstFails {
                    result.stoppedEarly = true
                    return result
                }
            }
        }
        return result
    }

    /// Moves items back to where they were. Skips (and reports) ones whose original place is
    /// taken again or that are no longer in the Trash.
    ///
    /// With `keepBoth`, an item whose place is taken goes back next to it as
    /// "Name (restored).ext" instead (`restored` then holds the name it got).
    public func putBack(_ items: [TrashedItem], keepBoth: Bool = false) -> (restored: [TrashedItem], failures: [TrashFailure]) {
        let fm = FileManager.default
        var restored: [TrashedItem] = []
        var failures: [TrashFailure] = []
        // Parents before children (an app's folder before files that were inside it).
        for var item in items.sorted(by: { $0.original.path.count < $1.original.path.count }) {
            do {
                if fm.fileExists(atPath: item.original.path) {
                    guard keepBoth else { throw CocoaError(.fileWriteFileExists) }
                    item.original = Self.restoredName(for: item.original)
                }
                guard fm.fileExists(atPath: item.trashed.path) || (try? item.trashed.checkResourceIsReachable()) == true else {
                    throw CocoaError(.fileNoSuchFile)
                }
                try fm.createDirectory(at: item.original.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: item.trashed, to: item.original)
                restored.append(item)
            } catch {
                failures.append(TrashFailure(url: item.original, message: Self.message(for: error)))
            }
        }
        return (restored, failures)
    }

    /// `report.pdf` → `report (restored).pdf`, then `report (restored 2).pdf`...
    static func restoredName(for url: URL) -> URL {
        let folder = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var number = 1
        while true {
            let suffix = number == 1 ? " (restored)" : " (restored \(number))"
            let candidate = folder.appendingPathComponent(base + suffix + (ext.isEmpty ? "" : "." + ext))
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }

    static func message(for error: Error) -> String {
        if let refusal = error as? TrashRefusal { return refusal.description }
        let ns = error as NSError
        switch (ns.domain, ns.code) {
        case (NSCocoaErrorDomain, CocoaError.fileWriteNoPermission.rawValue),
             (NSCocoaErrorDomain, CocoaError.fileReadNoPermission.rawValue),
             (NSPOSIXErrorDomain, Int(EACCES)), (NSPOSIXErrorDomain, Int(EPERM)):
            return "You don't have permission to move it. Use Show in Finder and move it to the Trash there."
        case (NSCocoaErrorDomain, CocoaError.fileNoSuchFile.rawValue),
             (NSCocoaErrorDomain, CocoaError.fileReadNoSuchFile.rawValue):
            return "It's no longer there."
        case (NSCocoaErrorDomain, CocoaError.fileWriteFileExists.rawValue):
            return "Something with the same name is already there."
        default:
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
               underlying.domain == NSPOSIXErrorDomain, [Int(EACCES), Int(EPERM)].contains(underlying.code) {
                return "You don't have permission to move it. Use Show in Finder and move it to the Trash there."
            }
            return ns.localizedDescription
        }
    }
}
