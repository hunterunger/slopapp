import Foundation

/// An app bundle found in an Applications folder (or dropped on the window).
public struct InstalledApp: Sendable, Hashable, Identifiable {
    public var id: String { url.path }
    public var url: URL
    public var bundleID: String?
    /// What Finder shows: the display name, the bundle name, or the file name.
    public var name: String
    public var version: String?
    /// `CFBundleName`, `CFBundleDisplayName` and the file name, deduplicated.
    public var names: [String]
    public var executableName: String?
    /// Bundle ids of helpers, extensions and login items inside the app. Their data counts as
    /// the app's data too.
    public var embeddedBundleIDs: [String]

    public init(url: URL, bundleID: String?, name: String, version: String? = nil, names: [String] = [],
                executableName: String? = nil, embeddedBundleIDs: [String] = []) {
        self.url = url
        self.bundleID = bundleID
        self.name = name
        self.version = version
        self.names = names.isEmpty ? [name] : names
        self.executableName = executableName
        self.embeddedBundleIDs = embeddedBundleIDs
    }

    /// Main id first, then embedded ones.
    public var allBundleIDs: [String] {
        ([bundleID].compactMap { $0 } + embeddedBundleIDs).uniqued()
    }

    /// Apps that come with macOS (or from Apple). Tidy never removes these.
    public var isApple: Bool {
        guard let bundleID else { return url.path.hasPrefix("/System/") }
        return BundleID.isApple(bundleID) || url.path.hasPrefix("/System/")
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

/// Reading app bundles from disk.
public enum AppCatalog {
    /// Apps directly inside each folder, plus one level of subfolders (`Utilities`,
    /// `Setapp`...). Sorted by name. Apps nested inside other apps are not listed.
    public static func scan(_ directories: [URL]) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seen = Set<String>()
        let fm = FileManager.default
        for directory in directories {
            guard let children = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                             options: [.skipsHiddenFiles]) else { continue }
            for child in children {
                if Task.isCancelled { return [] }
                if child.pathExtension.lowercased() == "app" {
                    if let app = read(child), seen.insert(app.url.path).inserted { apps.append(app) }
                } else if isPlainDirectory(child),
                          let nested = try? fm.contentsOfDirectory(at: child, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for item in nested where item.pathExtension.lowercased() == "app" {
                        if let app = read(item), seen.insert(app.url.path).inserted { apps.append(app) }
                    }
                }
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func isPlainDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }

    /// Reads one `.app`. Returns nil if it isn't an app bundle.
    public static func read(_ url: URL) -> InstalledApp? {
        let url = url.standardizedFileURL
        guard url.pathExtension.lowercased() == "app" else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        let info = infoPlist(url.appendingPathComponent("Contents/Info.plist")) ?? [:]
        let stem = url.deletingPathExtension().lastPathComponent
        let bundleName = (info["CFBundleName"] as? String)?.trimmed
        let displayName = (info["CFBundleDisplayName"] as? String)?.trimmed
        let name = [displayName, bundleName].compactMap { $0 }.first { !$0.isEmpty } ?? stem
        let names = [stem, bundleName, displayName].compactMap { $0 }.filter { !$0.isEmpty }.uniqued()
        return InstalledApp(
            url: url,
            bundleID: (info["CFBundleIdentifier"] as? String)?.trimmed.nilIfEmpty,
            name: name,
            version: (info["CFBundleShortVersionString"] as? String)?.trimmed.nilIfEmpty,
            names: names,
            executableName: (info["CFBundleExecutable"] as? String)?.trimmed.nilIfEmpty,
            embeddedBundleIDs: embeddedIDs(in: url, mainID: info["CFBundleIdentifier"] as? String)
        )
    }

    /// Bundle ids of login items, helpers, extensions and XPC services inside an app. Only
    /// ids from the app's own vendor count: embedded third-party components (Sparkle's XPC
    /// services, say) are shared by many apps.
    static func embeddedIDs(in app: URL, mainID: String?) -> [String] {
        guard let mainID, !mainID.isEmpty else { return [] }
        let vendor = BundleID.vendor(mainID)
        let folders = ["Contents/Library/LoginItems", "Contents/PlugIns", "Contents/XPCServices",
                       "Contents/Helpers", "Contents/Frameworks", "Contents/MacOS", "Contents/Library/LaunchServices",
                       "Contents/Library/SystemExtensions"]
        let bundleExtensions: Set<String> = ["app", "appex", "xpc", "systemextension"]
        var ids: [String] = []
        let fm = FileManager.default
        for folder in folders {
            guard let items = try? fm.contentsOfDirectory(at: app.appendingPathComponent(folder), includingPropertiesForKeys: nil,
                                                         options: [.skipsHiddenFiles]) else { continue }
            for item in items where bundleExtensions.contains(item.pathExtension.lowercased()) {
                if let id = infoPlist(item.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String,
                   !id.isEmpty, BundleID.vendor(id) == vendor, id.caseInsensitiveCompare(mainID) != .orderedSame {
                    ids.append(id)
                }
            }
        }
        return ids.uniqued()
    }

    static func infoPlist(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
