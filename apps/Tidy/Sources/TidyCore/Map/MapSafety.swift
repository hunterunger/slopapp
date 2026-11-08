import Foundation

/// Why something in the map can't be checked and moved. Shown as a lock with this reason.
public enum MapLock: Sendable, Equatable {
    /// "N smaller items", "Not mapped", "macOS": groups, not things.
    case virtualItem
    case belongsToMacOS
    /// Inside an app or library: removing part of it can break it.
    case insidePackage
    /// iCloud Drive, Dropbox and the like: deleting here deletes on every device.
    case synced(String)
    /// Mail's or Messages' own storage.
    case appData(String)
    /// Apps go through the Uninstaller, so their leftovers go too.
    case app
    /// Outside the home folder on the startup disk, or outside home in a folder map.
    case outsideHome
    case readOnlyDisk
    /// A system folder or a disk's own folder Tidy never moves.
    case systemFolder
    /// Skipped without Full Disk Access.
    case needsFullDiskAccess
    /// The disk was disconnected.
    case disconnected

    public var reason: String {
        switch self {
        case .virtualItem: "It's a group of items, not one thing."
        case .belongsToMacOS: "Belongs to macOS."
        case .insidePackage: "Inside an app or library: removing part of it can break it. Move the whole thing instead."
        case .synced(let service): "Synced with \(service): remove it in Finder, so it's removed everywhere on purpose."
        case .appData(let app): "\(app) keeps this. Remove it in \(app)."
        case .app: "An app: use Uninstall… so its leftovers go too."
        case .outsideHome: "Outside your home folder: Tidy only shows it."
        case .readOnlyDisk: "This disk is read-only."
        case .systemFolder: "A folder Tidy never moves."
        case .needsFullDiskAccess: "Needs Full Disk Access: macOS protects it."
        case .disconnected: "The disk was disconnected."
        }
    }

    /// One or two words for the details strip.
    public var shortLabel: String {
        switch self {
        case .virtualItem: "Group"
        case .belongsToMacOS: "macOS"
        case .insidePackage: "Inside a package"
        case .synced: "Synced"
        case .appData(let app): app
        case .app: "App"
        case .outsideHome: "Outside home"
        case .readOnlyDisk: "Read-only disk"
        case .systemFolder: "System folder"
        case .needsFullDiskAccess: "Protected"
        case .disconnected: "Disconnected"
        }
    }
}

/// Why a move was refused at the last moment.
public enum MapMoveRefusal: Error, Sendable, Equatable, CustomStringConvertible {
    case locked(MapLock)
    case gone
    case changedSinceScan

    public var description: String {
        switch self {
        case .locked(let lock): lock.reason
        case .gone: "It's no longer there."
        case .changedSinceScan: "It changed since the scan. Rescan and try again."
        }
    }
}

/// What the map is showing, for the safety rules.
public enum MapScopeKind: Sendable, Equatable {
    case home
    case folder
    case startupDisk
    case volume(isReadOnly: Bool)
}

/// The map's safety rules on top of `TrashPolicy` (which every move still passes):
/// read-only zones (package insides, synced folders, Mail and Messages), apps routed to the
/// Uninstaller, virtual items, read-only disks, and a last check that the item is still the
/// one that was scanned.
public struct MapSafety: Sendable {
    public let policy: TrashPolicy
    public let scope: MapScopeKind
    let home: String
    /// Synced folders: (path, service name).
    let synced: [(path: String, service: String)]
    let appData: [(path: String, app: String)]

    /// `syncedFolders` are extra synced roots found on this Mac (iCloud Desktop and Documents,
    /// a classic Dropbox folder); the standard ones are always included.
    public init(policy: TrashPolicy, scope: MapScopeKind, syncedFolders: [(URL, String)] = []) {
        self.policy = policy
        self.scope = scope
        let home = policy.environment.home.standardizedFileURL.path
        self.home = home
        synced = ([("Library/Mobile Documents", "iCloud Drive"), ("Library/CloudStorage", "a cloud storage service")]
            .map { (home + "/" + $0.0, $0.1) }) + syncedFolders.map { ($0.0.standardizedFileURL.path, $0.1) }
        appData = [("Library/Mail", "Mail"), ("Library/Messages", "Messages")].map { (home + "/" + $0.0, $0.1) }
    }

    /// Classic sync folders at the top of the home folder (their File Provider versions live
    /// in ~/Library/CloudStorage, which is always synced).
    public static let classicSyncFolders = ["Dropbox": "Dropbox", "Google Drive": "Google Drive", "OneDrive": "OneDrive",
                                            "Box": "Box", "pCloud Drive": "pCloud"]

    static func isInside(_ path: String, _ folder: String) -> Bool {
        path == folder || path.hasPrefix(folder + "/")
    }

    /// The lock for an item at `path` (full, firmlinked path), or nil if it can be checked.
    public func lock(path: String, kind: MapItem.Kind, flags: MapFlags) -> MapLock? {
        switch kind {
        case .smaller, .system, .notMapped: return .virtualItem
        default: break
        }
        if case .volume(true) = scope { return .readOnlyDisk }
        if flags.contains(.excluded) { return .needsFullDiskAccess }
        if flags.contains(.insidePackage) { return .insidePackage }
        if let sync = synced.first(where: { Self.isInside(path, $0.path) }) { return .synced(sync.service) }
        if flags.contains(.dataless) { return .synced("iCloud") }
        if let data = appData.first(where: { Self.isInside(path, $0.path) }) { return .appData(data.app) }
        if kind == .package, path.lowercased().hasSuffix(".app") { return .app }
        let url = URL(fileURLWithPath: path)
        do {
            try policy.check(url)
        } catch let refusal as TrashRefusal {
            switch refusal {
            case .appleItem: return .belongsToMacOS
            case .protectedFolder: return Self.isSystemPath(path) ? .belongsToMacOS : .systemFolder
            case .notAbsolute, .outsideAllowedFolders, .notAnApp:
                return Self.isSystemPath(path) ? .belongsToMacOS : .outsideHome
            }
        } catch {
            return .outsideHome
        }
        return nil
    }

    /// macOS's own folders on the startup disk.
    static func isSystemPath(_ path: String) -> Bool {
        ["/System", "/usr", "/bin", "/sbin", "/private", "/Library", "/cores", "/opt"].contains { isInside(path, $0) }
            || path == "/" || path == "/Applications" || path == "/Users"
    }

    /// The last check before a move: still allowed, still there, and still the same item (same
    /// device and file id, and no folder above it replaced by a symlink).
    public func verify(_ item: CheckedItem, kind: MapItem.Kind, flags: MapFlags,
                       info: (String) -> ItemInfo?, resolveParent: (String) -> String) -> MapMoveRefusal? {
        if let lock = lock(path: item.path, kind: kind, flags: flags) { return .locked(lock) }
        guard let now = info(item.path) else { return .gone }
        if now.device != item.device || now.fileID != item.fileID { return .changedSinceScan }
        if !item.resolvedParent.isEmpty, resolveParent((item.path as NSString).deletingLastPathComponent) != item.resolvedParent {
            return .changedSinceScan
        }
        return nil
    }
}

/// The real parent resolution: symlinks in the folders above.
public enum PathResolution {
    public static func resolvedParent(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}
