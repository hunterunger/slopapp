import AppKit
import UniformTypeIdentifiers

/// Facts about an item we might give an icon.
public struct TargetInfo: Equatable, Sendable {
    public var exists = true
    public var isApplication = false
    public var isLocked = false
    public var isWritable = true
    public var isVolume = false
    public var isReadOnlyVolume = false

    public init(exists: Bool = true, isApplication: Bool = false, isLocked: Bool = false, isWritable: Bool = true,
                isVolume: Bool = false, isReadOnlyVolume: Bool = false) {
        self.exists = exists
        self.isApplication = isApplication
        self.isLocked = isLocked
        self.isWritable = isWritable
        self.isVolume = isVolume
        self.isReadOnlyVolume = isReadOnlyVolume
    }
}

/// Custom Finder icons: NSWorkspace in the app, a fake in tests.
@MainActor
public protocol FileIconSystem: AnyObject {
    func info(_ url: URL) -> TargetInfo
    func hasCustomIcon(_ url: URL) -> Bool
    /// The item's current custom icon (nil when it has none).
    func customIcon(_ url: URL) -> NSImage?
    /// Sets (or with nil, removes) the custom icon. Returns false when macOS refused.
    func setIcon(_ image: NSImage?, for url: URL) -> Bool
}

public enum TargetOutcome: Equatable, Sendable {
    case applied
    case removed
    case restored
    /// Nothing to do (e.g. no custom icon to remove).
    case unchanged(String)
    case failed(String)

    public var isSuccess: Bool {
        switch self {
        case .applied, .removed, .restored: true
        case .unchanged, .failed: false
        }
    }

    public var message: String {
        switch self {
        case .applied: "Icon applied"
        case .removed: "Custom icon removed"
        case .restored: "Restored"
        case .unchanged(let reason), .failed(let reason): reason
        }
    }
}

public struct TargetResult: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let url: URL
    public let outcome: TargetOutcome

    public init(url: URL, outcome: TargetOutcome) {
        self.url = url
        self.outcome = outcome
    }

    public var name: String { FileManager.default.displayName(atPath: url.path) }
}

/// What one apply or remove changed, so it can be undone and redone.
public struct IconChange: @unchecked Sendable {
    public struct Snapshot {
        public let url: URL
        public let before: NSImage?
        public let after: NSImage?
    }

    public enum Kind: Sendable { case apply, remove }

    public let kind: Kind
    public let results: [TargetResult]
    public let snapshots: [Snapshot]

    public var changedCount: Int { snapshots.count }
    public var failures: [TargetResult] { results.filter { if case .failed = $0.outcome { true } else { false } } }

    /// "Applied to 3 items", "Removed 1 custom icon", "Nothing changed".
    public var summary: String {
        let n = changedCount
        let things = n == 1 ? "item" : "items"
        var text: String
        switch kind {
        case .apply: text = n == 0 ? "No icons changed" : "Applied to \(n) \(things)"
        case .remove: text = n == 0 ? "No custom icons removed" : "Removed \(n) custom icon\(n == 1 ? "" : "s")"
        }
        let failed = failures.count
        if failed > 0 { text += ", \(failed) failed" }
        return text
    }
}

/// Applies, removes and restores custom icons on files, folders and volumes.
@MainActor
public final class IconApplier {
    public let system: FileIconSystem
    /// When set, only items inside this folder may change (`ICONSMITH_ALLOWED_ROOT`, for
    /// tests and scripted runs).
    public let allowedRoot: URL?

    public init(system: FileIconSystem, allowedRoot: URL? = nil) {
        self.system = system
        self.allowedRoot = allowedRoot?.standardizedFileURL
    }

    public static func allowedRoot(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        guard let path = environment["ICONSMITH_ALLOWED_ROOT"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath()
    }

    /// Why an item can't change, or nil when it can.
    func refusal(_ url: URL) -> String? {
        if let root = allowedRoot {
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            if path != root.path && !path.hasPrefix(root.path + "/") {
                return "Outside the allowed folder (\(root.path))."
            }
        }
        let info = system.info(url)
        if !info.exists { return "It was moved or deleted." }
        if info.isApplication { return "Changing app icons isn’t supported yet." }
        if info.isLocked { return "It’s locked. Unlock it in Finder’s Get Info window, then try again." }
        if info.isReadOnlyVolume { return "This disk is read-only, so its icon can’t change." }
        if !info.isWritable { return "You don’t have permission to change it. Check its sharing & permissions in Get Info." }
        return nil
    }

    func failureAfterSet(_ url: URL, removing: Bool) -> String {
        if system.info(url).isVolume {
            return "This disk’s format doesn’t keep custom icons."
        }
        return removing ? "macOS didn’t allow removing the icon. Try Get Info in Finder." : "macOS didn’t allow the change. Try Get Info in Finder."
    }

    static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    public func apply(_ image: NSImage, to urls: [URL]) -> IconChange {
        var results: [TargetResult] = []
        var snapshots: [IconChange.Snapshot] = []
        for url in Self.unique(urls) {
            if let reason = refusal(url) {
                results.append(TargetResult(url: url, outcome: .failed(reason)))
                continue
            }
            let before = system.customIcon(url)
            if system.setIcon(image, for: url), system.hasCustomIcon(url) {
                results.append(TargetResult(url: url, outcome: .applied))
                snapshots.append(.init(url: url, before: before, after: image))
            } else {
                results.append(TargetResult(url: url, outcome: .failed(failureAfterSet(url, removing: false))))
            }
        }
        return IconChange(kind: .apply, results: results, snapshots: snapshots)
    }

    public func remove(from urls: [URL]) -> IconChange {
        var results: [TargetResult] = []
        var snapshots: [IconChange.Snapshot] = []
        for url in Self.unique(urls) {
            if let reason = refusal(url) {
                results.append(TargetResult(url: url, outcome: .failed(reason)))
                continue
            }
            guard system.hasCustomIcon(url) else {
                results.append(TargetResult(url: url, outcome: .unchanged("No custom icon")))
                continue
            }
            let before = system.customIcon(url)
            if system.setIcon(nil, for: url), !system.hasCustomIcon(url) {
                results.append(TargetResult(url: url, outcome: .removed))
                snapshots.append(.init(url: url, before: before, after: nil))
            } else {
                results.append(TargetResult(url: url, outcome: .failed(failureAfterSet(url, removing: true))))
            }
        }
        return IconChange(kind: .remove, results: results, snapshots: snapshots)
    }

    /// Puts each item back the way it was before (`toBefore`) or after the change.
    /// Returns per-item results.
    public func restore(_ change: IconChange, toBefore: Bool) -> [TargetResult] {
        change.snapshots.map { snapshot in
            let image = toBefore ? snapshot.before : snapshot.after
            if refusal(snapshot.url) == nil, system.setIcon(image, for: snapshot.url),
               system.hasCustomIcon(snapshot.url) == (image != nil) {
                return TargetResult(url: snapshot.url, outcome: .restored)
            }
            return TargetResult(url: snapshot.url, outcome: .failed("Couldn’t put its icon back."))
        }
    }
}

/// The real thing: NSWorkspace plus the Finder "has custom icon" flag.
@MainActor
public final class WorkspaceFileIcons: FileIconSystem {
    public init() {}

    public func info(_ url: URL) -> TargetInfo {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return TargetInfo(exists: false) }
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isUserImmutableKey, .isVolumeKey, .volumeIsReadOnlyKey])
        let isVolume = values?.isVolume ?? false
        return TargetInfo(
            exists: true,
            isApplication: values?.contentType?.conforms(to: .application) ?? false,
            isLocked: values?.isUserImmutable ?? false,
            isWritable: access(url.path, W_OK) == 0,
            isVolume: isVolume,
            isReadOnlyVolume: isVolume && (values?.volumeIsReadOnly ?? false)
        )
    }

    public func hasCustomIcon(_ url: URL) -> Bool {
        FinderInfo.hasCustomIcon(path: url.path)
    }

    public func customIcon(_ url: URL) -> NSImage? {
        guard hasCustomIcon(url) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        // Keep a detached copy: NSWorkspace's image can follow later changes to the file.
        let copy = NSImage(size: icon.size)
        for rep in icon.representations {
            if let bitmap = rep as? NSBitmapImageRep, let cloned = bitmap.copy() as? NSImageRep { copy.addRepresentation(cloned) }
        }
        if copy.representations.isEmpty, let data = icon.tiffRepresentation, let image = NSImage(data: data) { return image }
        return copy
    }

    public func setIcon(_ image: NSImage?, for url: URL) -> Bool {
        let ok = NSWorkspace.shared.setIcon(image, forFile: url.path, options: [])
        NSWorkspace.shared.noteFileSystemChanged(url.path)
        return ok
    }
}

/// Reads the Finder "has custom icon" flag from the FinderInfo extended attribute.
public enum FinderInfo {
    static let hasCustomIconFlag: UInt16 = 0x0400

    public static func hasCustomIcon(path: String) -> Bool {
        var buffer = [UInt8](repeating: 0, count: 32)
        let size = getxattr(path, "com.apple.FinderInfo", &buffer, 32, 0, 0)
        guard size >= 10 else { return false }
        return flags(buffer) & hasCustomIconFlag != 0
    }

    /// Finder flags are a big-endian UInt16 at offset 8 for files and folders alike.
    static func flags(_ finderInfo: [UInt8]) -> UInt16 {
        guard finderInfo.count >= 10 else { return 0 }
        return UInt16(finderInfo[8]) << 8 | UInt16(finderInfo[9])
    }
}
