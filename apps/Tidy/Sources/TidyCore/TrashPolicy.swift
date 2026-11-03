import Foundation

/// Why Tidy refuses to move something. Every move goes through `TrashPolicy.check` first,
/// so a bug in a scanner can never turn into deleting the wrong thing.
public enum TrashRefusal: Error, Equatable, Sendable, CustomStringConvertible {
    case notAbsolute
    case outsideAllowedFolders
    case protectedFolder
    case appleItem
    case notAnApp

    public var description: String {
        switch self {
        case .notAbsolute: "The path isn't a full path."
        case .outsideAllowedFolders: "It's outside the folders Tidy cleans."
        case .protectedFolder: "It's a system folder Tidy never removes."
        case .appleItem: "It belongs to macOS."
        case .notAnApp: "Only apps are removed from Applications folders."
        }
    }
}

/// The last line of defence before anything is moved to the Trash.
public struct TrashPolicy: Sendable {
    public let environment: TidyEnvironment
    private let home: [String]
    private let appDirectories: [[String]]
    private let systemLibrary: [String]?
    private let trash: [String]?

    public init(environment: TidyEnvironment) {
        self.environment = environment
        home = Self.components(environment.home)
        appDirectories = environment.applicationDirectories.map(Self.components)
        systemLibrary = environment.systemLibrary.map(Self.components)
        trash = environment.trashDirectory.map(Self.components)
    }

    /// Folders inside the home folder that are never removed themselves (their contents can be).
    static let protectedHomePaths: Set<String> = [
        "Library/Preferences/ByHost",
        "Library/Logs/DiagnosticReports",
        "Library/Developer",
        "Library/Developer/Xcode",
        "Library/Developer/Xcode/DerivedData",
        "Library/Developer/Xcode/Archives",
        "Library/Developer/Xcode/UserData",
        "Library/Developer/Xcode/iOS DeviceSupport",
        "Library/Developer/Xcode/watchOS DeviceSupport",
        "Library/Developer/Xcode/tvOS DeviceSupport",
        "Library/Developer/Xcode/visionOS DeviceSupport",
        "Library/Developer/Xcode/macOS DeviceSupport",
        "Library/Developer/CoreSimulator",
        "Library/Developer/CoreSimulator/Caches",
        "Library/Developer/CoreSimulator/Devices",
        "Library/Mobile Documents",
        "Library/CloudStorage",
        "Library/Mail",
        "Library/Messages",
        "Library/Keychains",
        "Library/Accounts",
        "Library/Calendars",
        "Library/Photos",
        "Library/Safari",
        ".npm", ".gradle", ".cache", ".Trash",
    ]

    /// Throws if `url` must not be moved to the Trash.
    public func check(_ url: URL) throws {
        guard url.isFileURL, url.path.hasPrefix("/") else { throw TrashRefusal.notAbsolute }
        let parts = Self.components(url)
        guard !parts.isEmpty else { throw TrashRefusal.protectedFolder }
        if let trash, parts.starts(with: trash) { throw TrashRefusal.protectedFolder }

        // Apps in an Applications folder: only .app bundles, never Apple's.
        for dir in appDirectories where parts.count > dir.count && parts.starts(with: dir) {
            guard parts.last!.lowercased().hasSuffix(".app") else { throw TrashRefusal.notAnApp }
            try Self.rejectApple(parts.dropFirst(dir.count))
            return
        }
        if parts.count > home.count, parts.starts(with: home) {
            let relative = Array(parts.dropFirst(home.count))
            try checkInHome(relative)
            return
        }
        if let systemLibrary, parts.count > systemLibrary.count + 1, parts.starts(with: systemLibrary) {
            try Self.rejectApple(parts.dropFirst(systemLibrary.count))
            return
        }
        throw TrashRefusal.outsideAllowedFolders
    }

    public func allows(_ url: URL) -> Bool { (try? check(url)) != nil }

    private func checkInHome(_ relative: [String]) throws {
        let joined = relative.joined(separator: "/")
        if Self.protectedHomePaths.contains(joined) { throw TrashRefusal.protectedFolder }
        if relative[0] == "Library" {
            // Library itself and its standard folders (Caches, Preferences...) stay.
            guard relative.count >= 3 else { throw TrashRefusal.protectedFolder }
        } else if relative.count == 1 {
            // Top-level folders (Desktop, Documents...) stay; top-level files may go.
            var isDirectory: ObjCBool = false
            let path = (home + relative).joined(separator: "/")
            if FileManager.default.fileExists(atPath: "/" + path, isDirectory: &isDirectory), isDirectory.boolValue,
               !relative[0].lowercased().hasSuffix(".app") {
                throw TrashRefusal.protectedFolder
            }
        }
        try Self.rejectApple(relative[...])
    }

    /// Anything with a `com.apple.` component belongs to macOS, except Xcode's developer
    /// caches (`com.apple.dt.*`), which are regenerated on demand.
    static func rejectApple(_ parts: ArraySlice<String>) throws {
        for part in parts {
            let lower = part.lowercased()
            if lower.hasPrefix("com.apple.dt.") { continue }
            if lower.hasPrefix("com.apple.") || lower.hasPrefix("group.com.apple.") { throw TrashRefusal.appleItem }
        }
    }

    /// Path components after resolving symlinks in the parent (the item itself may be a link,
    /// which is moved as a link).
    static func components(_ url: URL) -> [String] {
        let standardized = url.standardizedFileURL
        let parent = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
        let name = standardized.lastPathComponent
        var parts = parent.pathComponents.filter { $0 != "/" }
        if name != "/" && !name.isEmpty { parts.append(name) }
        return parts
    }
}
