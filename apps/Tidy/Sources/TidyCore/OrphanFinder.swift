import Foundation

/// Data left behind by an app that's no longer installed, grouped by the app's bundle id.
public struct OrphanGroup: Sendable, Hashable, Identifiable {
    public var id: String { bundleID }
    /// `com.acme.Widget`.
    public var bundleID: String
    public var items: [Leftover]
    /// The newest modification date among the items.
    public var lastModified: Date?
    /// Set when the app itself is in the Trash: its name, read from the bundle there.
    public var appName: String?

    /// The app's name if known, else the last part of its id (`Widget`).
    public var displayName: String {
        appName ?? String(bundleID.split(separator: ".").last ?? Substring(bundleID))
    }
}

/// Finds leftovers whose app is gone. Deliberately cautious, because a false positive here
/// means deleting data of something that is still in use:
/// - only items named by a bundle id with 3+ parts, in folders keyed by bundle id;
/// - never Apple's, never a known tool namespace (Homebrew, Python...);
/// - not if any installed app (or its helpers) has that id, an id under it, or an id it's under;
/// - not if any installed app comes from the same vendor (`com.acme.*`): vendors share ids
///   between apps and helpers in ways we can't see;
/// - not if it's running, or (real Macs) LaunchServices knows an app with that id anywhere;
/// - not if anything in the group changed in the last 7 days (something still writes to it);
/// - not if an installed app claims it by any rule (a launch agent running a program inside
///   it), or it's a launch agent whose program still exists.
///
/// Apps that are in the Trash are the exception that makes this useful right after an
/// uninstall: their bundle is still readable, so their leftovers are found with the same
/// rules as installed apps (ids, distinctive names, `/Library` items) and grouped under
/// the app's name, whatever the vendor or age.
public struct OrphanFinder: Sendable {
    static let ignoredPrefixes = [
        "com.apple.", "group.com.apple.", "systemgroup.", "homebrew.", "org.homebrew.", "org.python.",
        "org.macports.", "org.openssh.", "com.openssh.", "org.cups.", "org.nixos.", "org.pqrs.karabiner",
        "org.swift.", "org.llvm.", "org.carthage.", "org.nodejs.", "org.rust-lang.", "com.github.cli.",
    ]

    public var finder: LeftoverFinder
    /// Asks LaunchServices (or a fake) whether an app with this id exists anywhere.
    public var isInstalledElsewhere: @Sendable (String) -> Bool
    public var runningBundleIDs: Set<String>
    public var now: Date
    public var recentWindow: TimeInterval = 7 * 86_400
    /// App bundles sitting in the Trash.
    public var trashedApps: [InstalledApp]

    public init(finder: LeftoverFinder, runningBundleIDs: Set<String> = [], now: Date = Date(), trashedApps: [InstalledApp] = [],
                isInstalledElsewhere: @escaping @Sendable (String) -> Bool = { _ in false }) {
        self.finder = finder
        self.trashedApps = trashedApps
        self.now = now
        self.runningBundleIDs = Set(runningBundleIDs.map { $0.lowercased() })
        self.isInstalledElsewhere = isInstalledElsewhere
    }

    public func find() -> [OrphanGroup] {
        let installedIDs = finder.apps.flatMap(\.allBundleIDs).map { $0.lowercased() }
        let vendors = Set(finder.apps.compactMap(\.bundleID).filter { !BundleID.isApple($0) }.map(BundleID.vendor))
        var groups: [String: [Leftover]] = [:]
        var groupNames: [String: String] = [:]
        var lookups: [String: Bool] = [:]
        let claimed = Set(finder.apps.flatMap { finder.leftovers(for: $0) }.map(\.url.path))

        for entry in finder.index.entries where entry.location.findsOrphans {
            guard let candidate = entry.candidateID, BundleID.looksLikeBundleID(candidate) else { continue }
            let lower = candidate.lowercased()
            if Self.ignoredPrefixes.contains(where: { lower.hasPrefix($0) }) || BundleID.isApple(lower) { continue }
            if !finder.owners(ofBundleID: candidate).isEmpty { continue }
            if installedIDs.contains(where: { BundleID.matches($0, lower) }) { continue }
            if vendors.contains(BundleID.vendor(lower)) { continue }
            if claimed.contains(entry.url.path) { continue }
            if entry.launchPrograms.contains(where: { $0.hasPrefix("/") && FileManager.default.fileExists(atPath: $0) }) { continue }
            let key = BundleID.appKey(candidate)
            let keyLower = key.lowercased()
            if runningBundleIDs.contains(where: { BundleID.matches($0, keyLower) || BundleID.matches(keyLower, $0) }) { continue }
            let elsewhere = lookups[keyLower] ?? {
                let found = isInstalledElsewhere(key) || (lower != keyLower && isInstalledElsewhere(candidate))
                lookups[keyLower] = found
                return found
            }()
            if elsewhere { continue }
            groupNames[keyLower] = groupNames[keyLower] ?? key
            groups[keyLower, default: []].append(Leftover(
                url: entry.url, kind: entry.location.kind, reason: .bundleID(key),
                needsAdmin: entry.location.isSystem || LeftoverFinder.needsAdmin(entry.url),
                needsFullDiskAccess: entry.location.needsFullDiskAccess
            ))
        }

        // Apps in the Trash: matched like installed apps, unless an installed copy shares the id.
        var trashed: [String: (name: String, items: [Leftover])] = [:]
        for app in trashedApps where !app.isApple {
            guard let id = app.bundleID, finder.owners(ofBundleID: id).isEmpty,
                  !runningBundleIDs.contains(id.lowercased()), !isInstalledElsewhere(id) else { continue }
            let items = finder.leftovers(for: app).filter { $0.kind != .application && !$0.reason.isPossibleMatch }
                .filter { !claimed.contains($0.url.path) }
            guard !items.isEmpty else { continue }
            let key = id.lowercased()
            var merged = trashed[key]?.items ?? []
            merged += items.filter { item in !merged.contains { $0.url == item.url } }
            trashed[key] = (app.name, merged)
            groupNames[key] = id
        }

        let recent = now.addingTimeInterval(-recentWindow)
        var result: [OrphanGroup] = []
        for (key, entry) in trashed {
            // Fold in id-named items found above (`com.acme.Widget.helper` etc.).
            var items = entry.items
            for (otherKey, others) in groups where BundleID.matches(otherKey, key) {
                items += others.filter { other in !items.contains { $0.url == other.url } }
                groups[otherKey] = nil
            }
            result.append(OrphanGroup(bundleID: groupNames[key] ?? key, items: Self.sorted(items),
                                      lastModified: items.compactMap { Self.modificationDate($0.url) }.max(), appName: entry.name))
        }
        for (key, items) in groups {
            let newest = items.compactMap { Self.modificationDate($0.url) }.max()
            if let newest, newest > recent { continue }
            result.append(OrphanGroup(bundleID: groupNames[key] ?? key, items: Self.sorted(items), lastModified: newest))
        }
        return result.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    static func sorted(_ items: [Leftover]) -> [Leftover] {
        items.sorted { ($0.kind, $0.url.lastPathComponent.lowercased()) < ($1.kind, $1.url.lastPathComponent.lowercased()) }
    }

    static func modificationDate(_ url: URL) -> Date? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
    }
}
