import AppKit

/// Facts about the running app, read from its Info.plist (generated from app.json).
public struct AppInfo: Sendable, Equatable {
    public var name: String
    public var version: String
    public var build: String
    public var tagline: String

    public init(name: String, version: String, build: String, tagline: String) {
        self.name = name
        self.version = version
        self.build = build
        self.tagline = tagline
    }

    /// Reads from an Info.plist dictionary, falling back to `fallbackName` when run
    /// outside a bundle (e.g. `swift run`).
    public init(infoDictionary info: [String: Any], fallbackName: String) {
        self.init(
            name: info["CFBundleName"] as? String ?? fallbackName,
            version: info["CFBundleShortVersionString"] as? String ?? "dev",
            build: info["CFBundleVersion"] as? String ?? "0",
            tagline: info["SlopappTagline"] as? String ?? ""
        )
    }

    public static func current(fallbackName: String) -> AppInfo {
        AppInfo(infoDictionary: Bundle.main.infoDictionary ?? [:], fallbackName: fallbackName)
    }

    public var versionString: String { "Version \(version) (\(build))" }
}
