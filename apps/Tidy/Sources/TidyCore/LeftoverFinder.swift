import Foundation

/// Something Tidy proposes to move to the Trash.
public struct Leftover: Sendable, Hashable, Identifiable {
    public var id: String { url.path }
    public var url: URL
    public var kind: LeftoverKind
    public var reason: MatchReason
    /// Can't be moved without an administrator password (in `/Library`, or owned by root).
    public var needsAdmin: Bool
    /// In a folder macOS protects; needs Full Disk Access to measure or move.
    public var needsFullDiskAccess: Bool

    public init(url: URL, kind: LeftoverKind, reason: MatchReason, needsAdmin: Bool = false, needsFullDiskAccess: Bool = false) {
        self.url = url
        self.kind = kind
        self.reason = reason
        self.needsAdmin = needsAdmin
        self.needsFullDiskAccess = needsFullDiskAccess
    }

    /// Whether Tidy can move it right now.
    public func isRemovable(hasFullDiskAccess: Bool) -> Bool {
        !needsAdmin && (hasFullDiskAccess || !needsFullDiskAccess)
    }
}

/// Matches the index against installed apps. Conservative on purpose: an item belongs to an
/// app only by its bundle id (or one of its helpers' ids), an exact distinctive name in the
/// folders apps name after themselves, a launch agent that runs a program inside the app, or
/// a crash report named after its executable. When two installed apps could claim an item,
/// neither gets it (except bundle ids, where the most specific id wins).
public struct LeftoverFinder: Sendable {
    public let apps: [InstalledApp]
    public let index: LibraryIndex
    private let idOwners: [String: Set<String>]      // lowercased id → app paths
    private let nameOwners: [String: Set<String>]    // lowercased name → app paths
    private let anyNameOwners: [String: Set<String>] // same, including common names

    public init(apps: [InstalledApp], index: LibraryIndex) {
        self.apps = apps
        self.index = index
        var ids: [String: Set<String>] = [:]
        var names: [String: Set<String>] = [:]
        var anyNames: [String: Set<String>] = [:]
        for app in apps {
            for id in app.allBundleIDs { ids[id.lowercased(), default: []].insert(app.url.path) }
            for name in Self.matchNames(app) { names[name.lowercased(), default: []].insert(app.url.path) }
            for name in Self.allNames(app) { anyNames[name.lowercased(), default: []].insert(app.url.path) }
        }
        idOwners = ids
        nameOwners = names
        anyNameOwners = anyNames
    }

    /// Names used for exact folder-name matches: the bundle and display names, the file name
    /// and the executable, when distinctive; each also without spaces ("Photo Sorter" →
    /// "PhotoSorter").
    static func matchNames(_ app: InstalledApp) -> [String] {
        let names = (app.names + [app.executableName].compactMap { $0 }).filter(NameRules.isDistinctive)
        return (names + names.map { $0.replacingOccurrences(of: " ", with: "") }).uniqued()
    }

    /// Every name of the app, distinctive or not (for possible matches).
    static func allNames(_ app: InstalledApp) -> [String] {
        let names = (app.names + [app.executableName].compactMap { $0 }).map(\.trimmed).filter { $0.count >= 2 }
        return (names + names.map { $0.replacingOccurrences(of: " ", with: "") }).uniqued()
    }

    /// The installed app paths owning `candidate` by bundle id: the apps with the longest
    /// installed id that `candidate` equals or is namespaced under.
    public func owners(ofBundleID candidate: String) -> Set<String> {
        var parts = candidate.lowercased().split(separator: ".").map(String.init)
        while parts.count >= 2 {
            if let owners = idOwners[parts.joined(separator: ".")] { return owners }
            parts.removeLast()
        }
        return []
    }

    /// Everything that belongs to `app`, the app itself first, then by kind and name.
    /// `app` may be one that isn't in `apps` (dropped from elsewhere); it's matched the same way.
    public func leftovers(for app: InstalledApp) -> [Leftover] {
        guard !app.isApple else { return [] }
        let isKnown = apps.contains { $0.url.path == app.url.path }
        let finder = isKnown ? self : LeftoverFinder(apps: apps + [app], index: index)
        var result = [Leftover(url: app.url, kind: .application, reason: .appBundle, needsAdmin: Self.needsAdmin(app.url))]
        var seen = Set([app.url.path])
        for entry in index.entries {
            guard let reason = finder.reason(entry, belongsTo: app), seen.insert(entry.url.path).inserted else { continue }
            result.append(Leftover(
                url: entry.url, kind: entry.location.kind, reason: reason,
                needsAdmin: entry.location.isSystem || Self.needsAdmin(entry.url),
                needsFullDiskAccess: entry.location.needsFullDiskAccess
            ))
        }
        return result.sorted {
            ($0.kind, $0.url.lastPathComponent.lowercased()) < ($1.kind, $1.url.lastPathComponent.lowercased())
        }
    }

    func reason(_ entry: IndexEntry, belongsTo app: InstalledApp) -> MatchReason? {
        let path = app.url.path
        // 1. Bundle id (most specific installed id wins).
        if let candidate = entry.candidateID, !BundleID.isApple(candidate),
           let id = app.allBundleIDs.first(where: { BundleID.matches(candidate, $0) }),
           owners(ofBundleID: candidate) == [path] {
            return .bundleID(id)
        }
        // 2. Launch agents/daemons that start a program inside the app.
        if entry.location.isLaunchd {
            let appPath = app.url.resolvingSymlinksInPath().path + "/"
            if entry.launchPrograms.contains(where: {
                $0.hasPrefix("/") && URL(fileURLWithPath: $0).resolvingSymlinksInPath().path.hasPrefix(appPath)
            }) {
                return .launchProgram
            }
            if let id = app.bundleID, entry.launchBundleIDs.contains(where: { $0.caseInsensitiveCompare(id) == .orderedSame }) {
                return .launchProgram
            }
        }
        // 3. Exact, distinctive app name, claimed by no other installed app.
        if entry.location.matchesNames {
            let itemName = entry.isDirectory ? entry.name : (entry.name as NSString).deletingPathExtension
            if let name = Self.matchNames(app).first(where: { $0.caseInsensitiveCompare(itemName) == .orderedSame }),
               nameOwners[name.lowercased()] == [path], owners(ofBundleID: itemName).isEmpty {
                return .name(name)
            }
            // 3b. Named like the app, but the name is common or shared: a possible match only.
            if let name = Self.allNames(app).first(where: { $0.caseInsensitiveCompare(itemName) == .orderedSame }),
               owners(ofBundleID: itemName).isEmpty {
                let others = (anyNameOwners[name.lowercased()] ?? []).subtracting([path]).sorted()
                if !others.isEmpty {
                    let labels = others.map { other in
                        let url = URL(fileURLWithPath: other)
                        let app = apps.first { $0.url.path == other }
                        return "\(app?.name ?? url.deletingPathExtension().lastPathComponent) in \(url.deletingLastPathComponent().lastPathComponent)"
                    }
                    return .possibleName(name, .sharedWith(labels))
                }
                return .possibleName(name, .commonName)
            }
        }
        // 4. Crash reports: `<Executable>-YYYY-MM-DD-HHMMSS.ips` and similar.
        if entry.location.matching == .crashReport, !entry.isDirectory {
            for name in ([app.executableName].compactMap { $0 } + app.names).uniqued()
            where NameRules.isDistinctive(name) && nameOwnersAllow(name, path) && Self.isCrashReport(entry.name, of: name) {
                return .crashReport
            }
        }
        return nil
    }

    private func nameOwnersAllow(_ name: String, _ path: String) -> Bool {
        let owners = nameOwners[name.lowercased()] ?? []
        return owners.isEmpty || owners == [path]
    }

    static func isCrashReport(_ file: String, of name: String) -> Bool {
        let lower = file.lowercased()
        let extensions = [".ips", ".crash", ".diag", ".spin", ".hang", ".cpu_resource.diag"]
        guard extensions.contains(where: lower.hasSuffix) else { return false }
        let prefix = name.lowercased()
        guard lower.hasPrefix(prefix) else { return false }
        let rest = lower.dropFirst(prefix.count)
        guard let separator = rest.first, separator == "-" || separator == "_" else { return false }
        // A date must follow: `-2026-01-02...`.
        let digits = rest.dropFirst().prefix(4)
        return digits.count == 4 && digits.allSatisfy(\.isNumber)
    }

    static func needsAdmin(_ url: URL) -> Bool {
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent().path
        if !fm.isWritableFile(atPath: parent) { return true }
        var isDirectory: ObjCBool = false
        // Moving a folder to another folder rewrites its "..", which needs write access to it.
        if fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
           !fm.isWritableFile(atPath: url.path) {
            return true
        }
        return false
    }
}
