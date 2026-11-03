import Foundation

/// A folder where apps leave per-app data, and how items in it are matched.
public struct LeftoverLocation: Sendable, Hashable {
    public enum Matching: Sendable, Hashable {
        /// The item's name (minus `.plist` etc.) is a bundle id.
        case bundleID
        /// Group Containers: `TEAMID.com.acme.Widget`, `group.com.acme.Widget`.
        case groupContainer
        /// `Widget-2026-01-02-030405.ips`, keyed by the executable name.
        case crashReport
    }

    public var relativePath: String
    public var kind: LeftoverKind
    public var matching: Matching
    /// Folders named exactly after the app (`Application Support/Widget`) also count.
    public var matchesNames: Bool
    /// Launch agent/daemon plists: also matched by the program they start.
    public var isLaunchd: Bool
    /// macOS protects other apps' containers: reading or moving them needs Full Disk Access
    /// (otherwise macOS asks the user, item by item).
    public var needsFullDiskAccess: Bool
    /// In `/Library` rather than the home folder.
    public var isSystem: Bool
    /// Scanned for leftovers of apps that are no longer installed.
    public var findsOrphans: Bool

    init(_ relativePath: String, _ kind: LeftoverKind, _ matching: Matching = .bundleID, names: Bool = false,
         launchd: Bool = false, fda: Bool = false, system: Bool = false, orphans: Bool = true) {
        self.relativePath = relativePath
        self.kind = kind
        self.matching = matching
        self.matchesNames = names
        self.isLaunchd = launchd
        self.needsFullDiskAccess = fda
        self.isSystem = system
        // In /Library only launchd items and helper tools, which are always named by bundle id.
        self.findsOrphans = orphans && (!system || launchd || kind == .launchItems)
    }

    public static let all: [LeftoverLocation] = [
        .init("Application Support", .supportFiles, names: true),
        .init("Caches", .caches, names: true),
        .init("Preferences", .preferences),
        .init("Preferences/ByHost", .preferences),
        .init("Containers", .containers, fda: true),
        .init("Group Containers", .containers, .groupContainer, fda: true),
        .init("Application Scripts", .other),
        .init("LaunchAgents", .launchItems, launchd: true),
        .init("Saved Application State", .savedState),
        .init("HTTPStorages", .webData),
        .init("WebKit", .webData),
        .init("Cookies", .webData),
        .init("Logs", .logs, names: true),
        .init("Logs/DiagnosticReports", .logs, .crashReport, orphans: false),
        // /Library: removing these needs an administrator, so Tidy shows them for Finder.
        .init("Application Support", .supportFiles, names: true, system: true),
        .init("Caches", .caches, system: true),
        .init("Preferences", .preferences, system: true),
        .init("LaunchAgents", .launchItems, launchd: true, system: true),
        .init("LaunchDaemons", .launchItems, launchd: true, system: true),
        .init("PrivilegedHelperTools", .launchItems, system: true),
        .init("Logs", .logs, names: true, system: true),
    ]
}

/// One item in a leftover location.
public struct IndexEntry: Sendable, Hashable {
    public var url: URL
    public var name: String
    public var isDirectory: Bool
    public var location: LeftoverLocation
    /// Launchd plists: the program paths and associated bundle ids they declare.
    public var launchPrograms: [String] = []
    public var launchBundleIDs: [String] = []

    /// The bundle id this item is keyed by, if its location is keyed by bundle id.
    public var candidateID: String? {
        switch location.matching {
        case .bundleID: BundleID.stem(name)
        case .groupContainer: BundleID.groupContainerID(name)
        case .crashReport: nil
        }
    }
}

/// A listing of every leftover location, built once per scan (a few thousand names; fast).
/// Matching apps against it never touches the disk again.
public struct LibraryIndex: Sendable {
    public var entries: [IndexEntry]

    public init(entries: [IndexEntry]) {
        self.entries = entries
    }

    public static func build(_ environment: TidyEnvironment) -> LibraryIndex {
        var entries: [IndexEntry] = []
        let fm = FileManager.default
        for location in LeftoverLocation.all {
            let base: URL
            if location.isSystem {
                guard let system = environment.systemLibrary else { continue }
                base = system
            } else {
                base = environment.library
            }
            let folder = base.appendingPathComponent(location.relativePath, isDirectory: true)
            // Listing names is allowed even for protected folders; only their contents aren't.
            guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { continue }
            for name in names where !name.hasPrefix(".") {
                // Nested locations are listed separately (Preferences/ByHost, Logs/DiagnosticReports).
                if !location.isSystem, LeftoverLocation.all.contains(where: {
                    !$0.isSystem && $0.relativePath == location.relativePath + "/" + name
                }) { continue }
                let url = folder.appendingPathComponent(name)
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) || isSymlink(url) else { continue }
                var entry = IndexEntry(url: url, name: name, isDirectory: isDirectory.boolValue, location: location)
                if location.isLaunchd, name.lowercased().hasSuffix(".plist") {
                    (entry.launchPrograms, entry.launchBundleIDs) = launchdInfo(url)
                }
                entries.append(entry)
            }
        }
        return LibraryIndex(entries: entries)
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    static func launchdInfo(_ url: URL) -> ([String], [String]) {
        guard let plist = AppCatalog.infoPlist(url) else { return ([], []) }
        var programs: [String] = []
        if let program = plist["Program"] as? String { programs.append(program) }
        if let args = plist["ProgramArguments"] as? [String], let first = args.first { programs.append(first) }
        if let bundleProgram = plist["BundleProgram"] as? String { programs.append(bundleProgram) }
        var ids: [String] = []
        if let one = plist["AssociatedBundleIdentifiers"] as? String { ids.append(one) }
        if let many = plist["AssociatedBundleIdentifiers"] as? [String] { ids += many }
        return (programs, ids)
    }
}
