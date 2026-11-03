import AppKit
import ApplicationServices

enum Apps {
    /// Repo root, set by scripts/drive. Used to find build/<Name>.app.
    static var repoRoot: String? { ProcessInfo.processInfo.environment["SLOPDRIVE_ROOT"] }

    /// Finds a running app by pid, bundle id, name (case-insensitive) or .app path.
    static func running(_ query: String) throws -> NSRunningApplication {
        let apps = NSWorkspace.shared.runningApplications
        if let pid = Int32(query), let app = NSRunningApplication(processIdentifier: pid) { return app }
        if query.hasSuffix(".app") {
            let path = URL(fileURLWithPath: query).standardizedFileURL.path
            if let app = apps.last(where: { $0.bundleURL?.standardizedFileURL.path == path }) { return app }
        }
        let q = query.lowercased()
        let candidates = apps.filter {
            $0.bundleIdentifier?.lowercased() == q
                || $0.localizedName?.lowercased() == q
                || $0.bundleURL?.deletingPathExtension().lastPathComponent.lowercased() == q
        }
        // Prefer our own build of an app over a same-named app elsewhere, then the newest.
        if let root = repoRoot, let ours = candidates.last(where: { $0.bundleURL?.path.hasPrefix(root + "/build/") == true }) {
            return ours
        }
        if let app = candidates.max(by: { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }) {
            return app
        }
        throw DriveError("no running app matches \(quote(query)). Launch it with `launch \(query)`, or see `apps`.")
    }

    /// Resolves a name or path to an .app bundle on disk. Our builds win over installed apps.
    static func bundleURL(_ query: String) throws -> URL {
        let fm = FileManager.default
        if query.hasSuffix(".app") {
            let url = URL(fileURLWithPath: query)
            guard fm.fileExists(atPath: url.path) else { throw DriveError("\(query) does not exist") }
            return url
        }
        var places: [String] = []
        if let root = repoRoot { places.append("\(root)/build/\(query).app") }
        places += [
            "/Applications/\(query).app",
            "/Applications/Setapp/\(query).app",
            "/System/Applications/\(query).app",
            "/System/Applications/Utilities/\(query).app",
            NSHomeDirectory() + "/Applications/\(query).app",
        ]
        if let path = places.first(where: { fm.fileExists(atPath: $0) }) { return URL(fileURLWithPath: path) }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: query) { return url }
        throw DriveError("can't find \(query).app. Looked in: \(places.joined(separator: ", ")). Build it with scripts/bundle.sh \(query), or pass a path.")
    }

    struct Launched {
        let app: NSRunningApplication
        let launchMs: Int
    }

    /// Launches (or finds) the app and waits until it has finished launching.
    static func launch(_ url: URL, env: [String: String], activate: Bool, timeout: TimeInterval = 15) async throws -> Launched {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = activate
        config.addsToRecentItems = false
        config.promptsUserIfNeeded = false
        if !env.isEmpty { config.environment = env }
        let start = Date()
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        // NSRunningApplication only refreshes on the run loop, which a CLI doesn't spin: ask fresh.
        let pid = app.processIdentifier
        func finished() -> Bool { NSRunningApplication(processIdentifier: pid)?.isFinishedLaunching ?? false }
        while !finished() && Date().timeIntervalSince(start) < timeout {
            try await Task.sleep(for: .milliseconds(5))
        }
        guard finished() else { throw DriveError("\(url.lastPathComponent) didn't finish launching within \(Int(timeout))s") }
        return Launched(app: app, launchMs: Int(Date().timeIntervalSince(start) * 1000))
    }

    /// Starts the bundle's executable as a child of this process instead of through
    /// LaunchServices. macOS then attributes privacy permissions (Accessibility, Screen
    /// Recording) to this terminal, so permission-gated features can be tested without a
    /// human approving the app. Output goes to /tmp/slopdrive/<name>.log.
    static func launchDirect(_ url: URL, env: [String: String], timeout: TimeInterval = 15) async throws -> Launched {
        guard let bundle = Bundle(url: url), let exe = bundle.executableURL else {
            throw DriveError("\(url.lastPathComponent) has no executable")
        }
        try? FileManager.default.createDirectory(atPath: "/tmp/slopdrive", withIntermediateDirectories: true)
        let log = "/tmp/slopdrive/\(url.deletingPathExtension().lastPathComponent).log"
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_addopen(&fileActions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, 1, log, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        posix_spawn_file_actions_adddup2(&fileActions, 1, 2)
        var attrs: posix_spawnattr_t?
        posix_spawnattr_init(&attrs)
        posix_spawnattr_setflags(&attrs, Int16(POSIX_SPAWN_SETSID))
        var environment = ProcessInfo.processInfo.environment
        for (k, v) in env { environment[k] = v }
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup(exe.path), nil]
        defer {
            envp.forEach { free($0) }; argv.forEach { free($0) }
            posix_spawn_file_actions_destroy(&fileActions); posix_spawnattr_destroy(&attrs)
        }
        let start = Date()
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, exe.path, &fileActions, &attrs, argv, envp)
        guard rc == 0 else { throw DriveError("couldn't start \(exe.path): \(String(cString: strerror(rc)))") }
        func running() -> NSRunningApplication? {
            guard let app = NSRunningApplication(processIdentifier: pid), app.isFinishedLaunching else { return nil }
            return app
        }
        while running() == nil && Date().timeIntervalSince(start) < timeout {
            if kill(pid, 0) != 0 { throw DriveError("\(url.lastPathComponent) exited during launch; see \(log)") }
            try await Task.sleep(for: .milliseconds(5))
        }
        guard let app = running() else { throw DriveError("\(url.lastPathComponent) didn't finish launching within \(Int(timeout))s; see \(log)") }
        return Launched(app: app, launchMs: Int(Date().timeIntervalSince(start) * 1000))
    }

    static func quit(_ app: NSRunningApplication, force: Bool, timeout: TimeInterval = 5) async -> Bool {
        _ = force ? app.forceTerminate() : app.terminate()
        let start = Date()
        let pid = app.processIdentifier
        func gone() -> Bool { kill(pid, 0) != 0 }
        while !gone() && Date().timeIntervalSince(start) < timeout {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return gone()
    }

    static func policyName(_ p: NSApplication.ActivationPolicy) -> String {
        switch p {
        case .regular: "dock"
        case .accessory: "menu-bar"
        case .prohibited: "background"
        @unknown default: "?"
        }
    }
}

/// On-screen windows owned by a pid, from the window server (includes menus and panels).
struct ServerWindow {
    let id: CGWindowID
    let title: String
    let layer: Int
    let bounds: CGRect

    static func list(pid: pid_t) -> [ServerWindow] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { w in
            guard (w[kCGWindowOwnerPID as String] as? Int32) == pid,
                  let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            let alpha = w[kCGWindowAlpha as String] as? Double ?? 1
            let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            guard alpha > 0, rect.width > 2, rect.height > 2 else { return nil }
            return ServerWindow(id: id, title: w[kCGWindowName as String] as? String ?? "",
                                layer: w[kCGWindowLayer as String] as? Int ?? 0, bounds: rect)
        }
    }

    var kind: String {
        switch layer {
        case 0: "window"
        case 101: "menu"
        default: "overlay(layer \(layer))"
        }
    }
}
