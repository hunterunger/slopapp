import Foundation

/// Store-screenshot runs (`SLOP_SHOWCASE`, docs/screenshots.md). The launcher then reads and
/// writes only inside the scene's data folder (`SLOP_SHOWCASE_DATA`): its install folder,
/// Trash, Library, caches and the feed. A path the environment gives outside that folder is
/// replaced by the folder's own, so a showcase copy can never see or change the owner's apps.
public enum ShowcaseSandbox {
    /// Where each launcher path goes inside the data folder.
    public static let folders: [(key: String, folder: String)] = [
        ("SLOPAPP_INSTALL_DIR", "Applications"),
        ("SLOPAPP_TRASH_DIR", "Trash"),
        ("SLOPAPP_LIBRARY_DIR", "Library"),
        ("SLOPAPP_STATE_DIR", "State"),
    ]
    public static let feedKey = "SLOPAPP_FEED_URL"
    /// The feed when the environment names none: `<data>/feed/feed.json`.
    public static let defaultFeed = "feed/feed.json"

    /// A showcase run: `SLOP_SHOWCASE` names a scene (SlopKit's `ShowcaseRequest` rule).
    public static func isActive(_ env: [String: String]) -> Bool {
        guard let scene = env["SLOP_SHOWCASE"]?.trimmingCharacters(in: .whitespaces) else { return false }
        return !scene.isEmpty && scene != "0"
    }

    /// The scene's data folder: `SLOP_SHOWCASE_DATA`, else `<temporary>/slopapp-showcase`.
    public static func dataDirectory(_ env: [String: String], temporary: URL) -> URL {
        if let path = env["SLOP_SHOWCASE_DATA"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return temporary.appendingPathComponent("slopapp-showcase", isDirectory: true)
    }

    /// `env` for the launcher. Outside a showcase run, unchanged. In one, every launcher path
    /// is inside `data`: values already inside are kept, anything else (missing, relative,
    /// outside, or a feed that isn't a local file) becomes the data folder's default.
    public static func environment(_ env: [String: String], data: URL) -> [String: String] {
        guard isActive(env) else { return env }
        var result = env
        for (key, folder) in folders {
            if let value = env[key], isInside(value, data) { continue }
            result[key] = data.appendingPathComponent(folder, isDirectory: true).path
        }
        if let feed = env[feedKey], let path = localPath(feed), isInside(path, data) {
            result[feedKey] = path
        } else {
            result[feedKey] = data.appendingPathComponent(defaultFeed).path
        }
        return result
    }

    /// A file path from "/path" or "file:///path"; nil for anything else (https, localhost).
    static func localPath(_ value: String) -> String? {
        if value.hasPrefix("/") { return value }
        guard let url = URL(string: value), url.isFileURL, !url.path.isEmpty else { return nil }
        return url.path
    }

    /// `path` is `folder` or inside it, after resolving `..` and symlinks (/tmp is /private/tmp).
    static func isInside(_ path: String, _ folder: URL) -> Bool {
        guard path.hasPrefix("/") else { return false }
        let resolve = { (url: URL) in url.standardizedFileURL.resolvingSymlinksInPath().path }
        let child = resolve(URL(fileURLWithPath: path))
        let parent = resolve(folder)
        return child == parent || child.hasPrefix(parent.hasSuffix("/") ? parent : parent + "/")
    }

    /// Apps whose icon should be drawn but hasn't loaded yet (a scene waits for none).
    public static func missingIcons(_ items: [CatalogItem], allows: (URL) -> Bool, isLoaded: (CatalogItem) -> Bool) -> [String] {
        items.filter { IconSource.of($0, allows: allows) != nil && !isLoaded($0) }.map(\.id)
    }
}
