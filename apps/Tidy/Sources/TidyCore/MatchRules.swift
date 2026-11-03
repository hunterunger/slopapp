import Foundation

/// Bundle id rules. All comparisons ignore case (macOS treats bundle ids case-insensitively
/// and folders on the default volume are case-insensitive).
public enum BundleID {
    public static func isApple(_ id: String) -> Bool {
        let lower = id.lowercased()
        return lower.hasPrefix("com.apple.") || lower == "com.apple"
    }

    /// `candidate` is `id` itself or something the app namespaced under it
    /// (`com.acme.Widget.helper`, `com.acme.Widget.ShipIt`). Never a plain string prefix:
    /// `com.acme.WidgetPro` is a different app.
    public static func matches(_ candidate: String, _ id: String) -> Bool {
        let c = candidate.lowercased(), i = id.lowercased()
        return c == i || c.hasPrefix(i + ".")
    }

    /// Looks like a reverse-DNS bundle id with at least three parts (`com.acme.Widget`).
    public static func looksLikeBundleID(_ string: String) -> Bool {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return parts.allSatisfy { $0.unicodeScalars.allSatisfy { allowed.contains($0) } }
            && parts[0].unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
    }

    /// The bundle id part of a Group Containers folder name: strips a leading `group.` and/or
    /// a 10-character team id (`ABCDE12345.com.acme.Widget` → `com.acme.Widget`).
    public static func groupContainerID(_ name: String) -> String {
        var rest = Substring(name)
        let teamPrefix = rest.prefix(11)
        if teamPrefix.count == 11, teamPrefix.last == ".",
           teamPrefix.dropLast().allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) {
            rest = rest.dropFirst(11)
        }
        if rest.lowercased().hasPrefix("group.") { rest = rest.dropFirst(6) }
        return String(rest)
    }

    /// `com.acme.Widget.helper` → `com.acme.Widget`.
    public static func appKey(_ id: String) -> String {
        id.split(separator: ".").prefix(3).joined(separator: ".")
    }

    /// `com.acme.Widget` → `com.acme`.
    public static func vendor(_ id: String) -> String {
        id.lowercased().split(separator: ".").prefix(2).joined(separator: ".")
    }

    /// Strips the file extensions macOS adds to per-app items.
    public static func stem(_ name: String) -> String {
        for ext in [".plist", ".savedstate", ".binarycookies", ".sfl2", ".sfl3", ".sfl"] where name.lowercased().hasSuffix(ext) {
            return String(name.dropLast(ext.count))
        }
        return name
    }
}

/// Which app names are safe to match folders by. Names are matched exactly (ignoring case),
/// never fuzzily, and only when they're distinctive.
public enum NameRules {
    /// Words that are also generic folder names, vendor names or Apple app names. An app
    /// called one of these is matched by bundle id only.
    static let stopWords: Set<String> = [
        "app", "apps", "application", "applications", "assets", "audio", "backup", "backups", "books", "browser",
        "cache", "caches", "cachedata", "calendar", "calendars", "camera", "chrome", "chromium", "clock", "cloud",
        "code", "com", "config", "configuration", "contacts", "cookies", "crashpad", "crashreporter", "data",
        "default", "demo", "desktop", "diagnosticreports", "documents", "downloads", "drive", "editor", "electron",
        "extensions", "facetime", "file", "files", "finder", "fonts", "free", "frameworks", "games", "git",
        "global", "google", "gpucache", "helper", "helpers", "home", "icloud", "image", "images", "io", "java",
        "keychain", "launchagents", "library", "lite", "local", "log", "logs", "mail", "maps", "media",
        "messages", "microsoft", "mozilla", "music", "my", "net", "new", "news", "node", "notes", "org",
        "photos", "pictures", "player", "plug-ins", "plugins", "plus", "podcasts", "preferences", "preview",
        "pro", "profile", "profiles", "python", "reader", "reminders", "resources", "ruby", "safari", "sample",
        "sentry", "session", "sessions", "settings", "shared", "sparkle", "squirrel", "state", "stocks",
        "storage", "support", "sync", "system", "temp", "terminal", "test", "tests", "tmp", "tv", "untitled",
        "update", "updater", "updates", "user", "users", "video", "videos", "viewer", "weather", "webkit",
        "adobe", "apple", "setup", "agent", "steam", "launcher", "installer", "uninstaller", "client", "server",
    ]

    public static func isDistinctive(_ name: String) -> Bool {
        let trimmed = name.trimmed
        guard trimmed.count >= 4, trimmed.contains(where: \.isLetter) else { return false }
        return !stopWords.contains(trimmed.lowercased())
    }
}

/// What kind of leftover something is, which decides its group in the list.
public enum LeftoverKind: String, CaseIterable, Sendable, Codable, Comparable {
    case application, supportFiles, caches, preferences, containers, launchItems, savedState, webData, logs, other

    public var title: String {
        switch self {
        case .application: "Application"
        case .supportFiles: "Application Support"
        case .caches: "Caches"
        case .preferences: "Preferences"
        case .containers: "Containers"
        case .launchItems: "Launch Agents and Daemons"
        case .savedState: "Saved State"
        case .webData: "Web Data and Cookies"
        case .logs: "Logs and Crash Reports"
        case .other: "Other"
        }
    }

    public var systemImage: String {
        switch self {
        case .application: "square.stack.3d.up"
        case .supportFiles: "folder"
        case .caches: "internaldrive"
        case .preferences: "slider.horizontal.3"
        case .containers: "shippingbox"
        case .launchItems: "power"
        case .savedState: "macwindow"
        case .webData: "globe"
        case .logs: "doc.text"
        case .other: "doc"
        }
    }

    public static func < (lhs: LeftoverKind, rhs: LeftoverKind) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// Why an item was matched to an app, shown so the user can judge it.
public enum MatchReason: Sendable, Hashable {
    case appBundle
    case bundleID(String)
    case name(String)
    case launchProgram
    case crashReport
    /// Named like the app, but the name is too common or another app has it too. Shown
    /// unchecked so the user decides.
    case possibleName(String, PossibleReason)

    public enum PossibleReason: Sendable, Hashable {
        case commonName
        case sharedWith([String])
    }

    public var isPossibleMatch: Bool {
        if case .possibleName = self { return true }
        return false
    }

    public var explanation: String {
        switch self {
        case .appBundle: "The app itself"
        case .bundleID(let id): "Named after the app's ID (\(id))"
        case .name(let name): "Named “\(name)”"
        case .launchProgram: "Starts a program inside the app"
        case .crashReport: "A crash report from the app"
        case .possibleName(let name, .commonName): "Named “\(name)”, a common name other apps may use too"
        case .possibleName(let name, .sharedWith(let others)):
            "Named “\(name)”, like \(others.joined(separator: ", "))"
        }
    }
}
