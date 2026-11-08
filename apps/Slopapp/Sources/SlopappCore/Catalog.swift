import Foundation

/// One app as the launcher shows it: the feed entry joined with what's on disk.
public struct CatalogItem: Sendable, Equatable, Identifiable {
    public var app: FeedApp
    /// Every copy found, best first. `copies.first` is the one Open/Update/Uninstall act on.
    public var copies: [InstalledCopy]

    public init(app: FeedApp, copies: [InstalledCopy] = []) {
        self.app = app
        self.copies = copies
    }

    public var id: String { app.slug }
    public var primary: InstalledCopy? { copies.first }
    public var isInstalled: Bool { primary != nil }

    public enum State: Sendable, Equatable {
        case comingSoon
        case notInstalled
        case installed
        case updateAvailable
    }

    public var state: State {
        guard let primary else { return app.isInstallable ? .notInstalled : .comingSoon }
        return hasUpdate(for: primary) ? .updateAvailable : .installed
    }

    /// The feed has a newer version than this copy, and the launcher may replace it.
    public func hasUpdate(for copy: InstalledCopy) -> Bool {
        guard app.isInstallable, copy.location.canModify, let version = app.version else { return false }
        return AppVersion(version, build: app.build ?? 0) > copy.info.appVersion
    }

    /// Only copies outside the Applications folders exist (e.g. a development build).
    /// Install then puts a managed copy next to it; the other copy is left alone.
    public var isOnlyElsewhere: Bool {
        guard let primary else { return false }
        return primary.location == .elsewhere
    }

    /// A newer version exists but the copy found can't be updated in place.
    public var newerVersionForElsewhereCopy: Bool {
        guard isOnlyElsewhere, app.isInstallable, let version = app.version, let primary else { return false }
        return AppVersion(version, build: app.build ?? 0) > primary.info.appVersion
    }

    public func matches(_ query: String) -> Bool {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return true }
        let haystack = ([app.name, app.tagline, app.category ?? ""] + app.replaces).joined(separator: " ").lowercased()
        return terms.allSatisfy { haystack.contains($0) }
    }
}

public enum CatalogBuilder {
    /// Joins the feed with the copies on disk. The launcher itself (`hub`) is left out of
    /// the lists; it updates separately.
    ///
    /// Apps with no release yet have no bundle id in the feed. With `bundleIDNamespace`
    /// ("app.slopapp"), they get "<namespace>.<slug>", the id every Slopapp app has, so a
    /// copy already on this Mac (a build installed by hand) is found, shown and opened.
    public static func items(feed: Feed, bundleIDNamespace: String? = nil, copies: (FeedApp) -> [InstalledCopy]) -> [CatalogItem] {
        feed.apps.filter { !$0.isHub }.map { feedApp in
            var app = feedApp
            if app.bundleId?.isEmpty ?? true { app.bundleId = expectedBundleID(slug: app.slug, namespace: bundleIDNamespace) }
            return CatalogItem(app: app, copies: app.bundleId == nil ? [] : copies(app))
        }
    }

    /// "<namespace>.<slug>", or nil when either part can't be part of a bundle id.
    public static func expectedBundleID(slug: String, namespace: String?) -> String? {
        guard let namespace, !namespace.isEmpty, !slug.isEmpty else { return nil }
        let allowed = { (c: Character) in c.isASCII && (c.isLetter || c.isNumber || c == "-") }
        guard slug.allSatisfy(allowed),
              namespace.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0.allSatisfy(allowed) })
        else { return nil }
        return "\(namespace).\(slug)"
    }

    /// "app.slopapp" from the launcher's own "app.slopapp.slopapp".
    public static func namespace(ofBundleID id: String?) -> String? {
        guard let id, let dot = id.lastIndex(of: "."), dot > id.startIndex else { return nil }
        return String(id[..<dot])
    }

    public static func updates(in items: [CatalogItem]) -> [CatalogItem] {
        items.filter { $0.state == .updateAvailable }
    }

    public static func installed(in items: [CatalogItem]) -> [CatalogItem] {
        items.filter(\.isInstalled).sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
    }
}

/// Byte counts as Finder shows them ("4.2 MB").
public enum SizeFormat {
    public static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
