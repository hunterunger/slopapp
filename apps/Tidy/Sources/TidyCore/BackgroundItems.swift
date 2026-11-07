import Foundation

/// Where a launch item lives, which decides who can remove it.
public enum LaunchScope: String, Sendable, CaseIterable, Comparable {
    /// `~/Library/LaunchAgents`: yours, runs while you're logged in.
    case userAgent
    /// `/Library/LaunchAgents`: every user's, installed by an administrator.
    case systemAgent
    /// `/Library/LaunchDaemons`: runs as root, without anyone logged in.
    case systemDaemon

    public var title: String {
        switch self {
        case .userAgent: "Your Launch Agents"
        case .systemAgent: "Launch Agents for All Users"
        case .systemDaemon: "Launch Daemons"
        }
    }

    public var folder: String {
        switch self {
        case .userAgent, .systemAgent: "LaunchAgents"
        case .systemDaemon: "LaunchDaemons"
        }
    }

    public var needsAdmin: Bool { self != .userAgent }

    public static func < (lhs: LaunchScope, rhs: LaunchScope) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// A launch agent or daemon: something macOS starts in the background.
public struct LaunchItem: Sendable, Hashable, Identifiable {
    public var id: String { url.path }
    /// The `.plist` that tells launchd about it.
    public var url: URL
    public var label: String
    /// The program it runs (`Program`, or the first of `ProgramArguments`).
    public var program: String?
    public var scope: LaunchScope
    public var runsAtLoad: Bool
    public var keepsAlive: Bool
    /// `Disabled` is set in the plist itself.
    public var isDisabled: Bool
    /// The program is an absolute path that no longer exists.
    public var isBroken: Bool
    /// The installed app it belongs to, if Tidy can tell.
    public var appName: String?
    public var appURL: URL?

    public init(url: URL, label: String, program: String?, scope: LaunchScope, runsAtLoad: Bool = false,
                keepsAlive: Bool = false, isDisabled: Bool = false, isBroken: Bool = false,
                appName: String? = nil, appURL: URL? = nil) {
        self.url = url
        self.label = label
        self.program = program
        self.scope = scope
        self.runsAtLoad = runsAtLoad
        self.keepsAlive = keepsAlive
        self.isDisabled = isDisabled
        self.isBroken = isBroken
        self.appName = appName
        self.appURL = appURL
    }

    /// A name for people: the app's name, else the program's, else the label.
    public var displayName: String {
        if let appName { return appName }
        if let program, !program.isEmpty {
            let name = (program as NSString).lastPathComponent
            if !name.isEmpty { return name }
        }
        return label
    }
}

/// A login item an app carries inside its bundle (`Contents/Library/LoginItems`). macOS keeps
/// the on/off switch for these in System Settings, so Tidy lists them and links there.
public struct AppLoginItem: Sendable, Hashable, Identifiable {
    public var id: String { url.path }
    public var url: URL
    public var name: String
    public var bundleID: String?
    public var appName: String
    public var appURL: URL

    public init(url: URL, name: String, bundleID: String?, appName: String, appURL: URL) {
        self.url = url
        self.name = name
        self.bundleID = bundleID
        self.appName = appName
        self.appURL = appURL
    }
}

/// Reads launchd plists and app login items. Read-only; macOS's own (`com.apple.*`) items are
/// never listed.
public struct BackgroundItemScanner: Sendable {
    public var environment: TidyEnvironment
    public var apps: [InstalledApp]
    /// Whether a program path exists (injected so tests don't depend on this Mac).
    public var fileExists: @Sendable (String) -> Bool

    public init(environment: TidyEnvironment, apps: [InstalledApp],
                fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.environment = environment
        self.apps = apps
        self.fileExists = fileExists
    }

    public func launchItems() -> [LaunchItem] {
        var folders: [(URL, LaunchScope)] = [(environment.library.appendingPathComponent("LaunchAgents"), .userAgent)]
        if let system = environment.systemLibrary {
            folders.append((system.appendingPathComponent("LaunchAgents"), .systemAgent))
            folders.append((system.appendingPathComponent("LaunchDaemons"), .systemDaemon))
        }
        var items: [LaunchItem] = []
        let fm = FileManager.default
        for (folder, scope) in folders {
            guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { continue }
            for name in names.sorted() where name.lowercased().hasSuffix(".plist") {
                let url = folder.appendingPathComponent(name)
                guard let item = read(url, scope: scope) else { continue }
                if BundleID.isApple(item.label) || BundleID.isApple(name) { continue }
                items.append(item)
            }
        }
        return items.sorted {
            $0.scope != $1.scope ? $0.scope < $1.scope
                : $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    func read(_ url: URL, scope: LaunchScope) -> LaunchItem? {
        guard let plist = AppCatalog.infoPlist(url) else {
            // Unreadable or damaged: still listed, by file name, so it can be dealt with.
            let label = BundleID.stem(url.lastPathComponent)
            return LaunchItem(url: url, label: label, program: nil, scope: scope, isBroken: false)
        }
        let label = (plist["Label"] as? String)?.trimmed.nilIfEmpty ?? BundleID.stem(url.lastPathComponent)
        let program = (plist["Program"] as? String)?.trimmed.nilIfEmpty
            ?? ((plist["ProgramArguments"] as? [Any])?.first as? String)?.trimmed.nilIfEmpty
        let keepAlive: Bool = {
            if let bool = plist["KeepAlive"] as? Bool { return bool }
            return plist["KeepAlive"] is [String: Any]
        }()
        var item = LaunchItem(url: url, label: label, program: program, scope: scope,
                              runsAtLoad: plist["RunAtLoad"] as? Bool ?? false, keepsAlive: keepAlive,
                              isDisabled: plist["Disabled"] as? Bool ?? false)
        if let program, program.hasPrefix("/") {
            item.isBroken = !fileExists(program)
        }
        if let app = owner(label: label, program: program) {
            item.appName = app.name
            item.appURL = app.url
        }
        return item
    }

    /// The app that owns it: the program lives inside the app, or the label is the app's
    /// bundle id or namespaced under it.
    func owner(label: String, program: String?) -> InstalledApp? {
        if let program, let range = program.range(of: ".app/", options: .caseInsensitive) {
            let appPath = String(program[..<range.lowerBound]) + ".app"
            if let app = apps.first(where: { $0.url.path.caseInsensitiveCompare(appPath) == .orderedSame }) { return app }
        }
        return apps.first { app in app.allBundleIDs.contains { BundleID.matches(label, $0) } }
    }

    /// Login items carried inside apps (`Contents/Library/LoginItems/*.app`).
    public func appLoginItems() -> [AppLoginItem] {
        let fm = FileManager.default
        var items: [AppLoginItem] = []
        for app in apps where !app.isApple {
            let folder = app.url.appendingPathComponent("Contents/Library/LoginItems")
            guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { continue }
            for name in names.sorted() where name.lowercased().hasSuffix(".app") {
                let url = folder.appendingPathComponent(name)
                let helper = AppCatalog.read(url)
                items.append(AppLoginItem(url: url, name: helper?.name ?? (name as NSString).deletingPathExtension,
                                          bundleID: helper?.bundleID, appName: app.name, appURL: app.url))
            }
        }
        return items
    }
}

/// Which launch items launchd has loaded right now, and their process ids.
public protocol LaunchStatusReader: Sendable {
    func loaded() -> [String: Int?]
}

/// `launchctl list` for the user's session (read-only).
public struct LaunchctlStatusReader: LaunchStatusReader {
    public init() {}

    public func loaded() -> [String: Int?] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Self.parse(String(decoding: data, as: UTF8.self))
    }

    /// `PID\tStatus\tLabel` lines; `-` for no process.
    public static func parse(_ output: String) -> [String: Int?] {
        var result: [String: Int?] = [:]
        for line in output.split(separator: "\n").dropFirst() {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 3 else { continue }
            let label = String(columns[2]).trimmed
            guard !label.isEmpty else { continue }
            result[label] = Int(columns[0].trimmingCharacters(in: .whitespaces))
        }
        return result
    }
}

/// Test mode: nothing is loaded except the labels given.
public struct FixedLaunchStatusReader: LaunchStatusReader {
    public var labels: [String: Int?]
    public init(_ labels: [String: Int?] = [:]) { self.labels = labels }
    public func loaded() -> [String: Int?] { labels }
}
