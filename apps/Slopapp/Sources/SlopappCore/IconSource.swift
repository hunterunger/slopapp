import Foundation

/// Where an app's icon comes from. The installed copy wins (it's what the person has, and an
/// app with no release yet has nothing else); otherwise the feed's icon URL; otherwise none
/// (the view draws a placeholder).
public enum IconSource: Sendable, Equatable {
    /// The copy on disk. Rendered once off the main thread, then cached on disk.
    case installed(URL)
    /// The feed's PNG, cached on disk per version.
    case remote(URL, cacheName: String)

    /// What `Icons` keys its memory cache by: changes when the copy or the release changes.
    public static func memoryKey(for item: CatalogItem) -> String {
        if let primary = item.primary { return "\(item.id)@\(primary.url.path)#\(primary.info.version)" }
        return "\(item.id)#\(item.app.version ?? "")"
    }

    public static func of(_ item: CatalogItem, allows: (URL) -> Bool) -> IconSource? {
        if let primary = item.primary { return .installed(primary.url) }
        guard let url = item.app.iconUrl, allows(url) else { return nil }
        return .remote(url, cacheName: "\(item.id)-\(item.app.version ?? "0").png")
    }

    /// The disk cache file for an installed copy's rendered icon. Keyed by the bundle's path,
    /// version and modification date, so a rebuilt or replaced copy (even at the same
    /// version) renders afresh. Starts with `installedCachePrefix(slug)`, so older renders of
    /// the same app can be swept.
    public static func installedCacheName(slug: String, url: URL, version: String, build: String, modified: Date?) -> String {
        let stamp = modified.map { String(Int64(($0.timeIntervalSince1970 * 1000).rounded())) } ?? "0"
        return installedCachePrefix(slug) + stableHash("\(url.standardizedFileURL.path)|\(version)|\(build)|\(stamp)") + ".png"
    }

    public static func installedCachePrefix(_ slug: String) -> String { "installed.\(slug)." }  // slugs have no dots

    /// FNV-1a, so file names stay the same across launches (Swift's `Hasher` is seeded per process).
    static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return String(hash, radix: 16)
    }
}
