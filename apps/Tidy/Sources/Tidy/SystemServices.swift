import AppKit
import UniformTypeIdentifiers
import CoreServices
import SlopKit
import TidyCore

/// Which apps are running, and quitting them. Test mode adds pretend-running bundle ids
/// (`TIDY_RUNNING_IDS`) so the "quit it first" path can be tried on fixture apps; quitting a
/// pretend app just forgets it, and real apps are never quit in test mode.
@MainActor
@Observable
final class RunningApps {
    private(set) var bundleIDs: Set<String> = []
    private var simulated: Set<String>
    private let isTestMode: Bool
    private var observers: [NSObjectProtocol] = []

    init(environment: TidyEnvironment) {
        simulated = Set(environment.simulatedRunningBundleIDs.map { $0.lowercased() })
        isTestMode = environment.isTestMode
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    func refresh() {
        let real = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() }
        let ids = Set(real).union(simulated)
        // Other apps start and quit all the time; only redraw when it matters.
        if ids != bundleIDs { bundleIDs = ids }
    }

    /// Running ids (lowercased) that belong to `app`: the app itself or one of its helpers.
    func runningIDs(of app: InstalledApp) -> [String] {
        let ids = app.allBundleIDs.map { $0.lowercased() }
        return ids.filter { bundleIDs.contains($0) }
    }

    func isRunning(_ app: InstalledApp) -> Bool { !runningIDs(of: app).isEmpty }

    /// Asks the app (and its helpers) to quit, like Quit in its menu.
    func quit(_ app: InstalledApp, force: Bool) {
        let ids = Set(runningIDs(of: app))
        if !simulated.isDisjoint(with: ids) {
            simulated.subtract(ids)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                refresh()
            }
            return
        }
        guard !isTestMode else { return }
        for running in NSWorkspace.shared.runningApplications {
            guard let id = running.bundleIdentifier?.lowercased(), ids.contains(id) else { continue }
            _ = force ? running.forceTerminate() : running.terminate()
        }
    }
}

/// Full Disk Access, with a test-mode override (`TIDY_ASSUME_FULL_DISK_ACCESS=1`) so the
/// granted path can be walked on fixtures without changing the Mac's privacy settings.
@MainActor
enum FullDiskAccess {
    static func isGranted(environment: TidyEnvironment) -> Bool {
        if environment.isTestMode, ProcessInfo.processInfo.environment["TIDY_ASSUME_FULL_DISK_ACCESS"] == "1" { return true }
        return Permission.fullDiskAccess.isGranted
    }
}

/// Facts from Spotlight and LaunchServices. Safe to call off the main thread.
enum SystemLookup {
    /// When Spotlight last saw the item opened.
    static func lastOpened(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL),
              let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date else { return nil }
        return date
    }

    /// Whether LaunchServices knows an app with this bundle id outside the Trash.
    static func isAppInstalled(bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        return !url.path.contains("/.Trash/")
    }
}

/// File icons, cached. Main actor only (NSImage isn't Sendable).
@MainActor
enum Icons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for url: URL) -> NSImage {
        if let cached = cache[url.path] { return cached }
        // A damaged app (no Info.plist) would get the "prohibited" icon; show a plain app.
        let isBrokenApp = url.pathExtension.lowercased() == "app"
            && !FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Info.plist").path)
        let image = isBrokenApp ? NSWorkspace.shared.icon(for: .applicationBundle) : NSWorkspace.shared.icon(forFile: url.path)
        cache[url.path] = image
        return image
    }
}

/// Paths shortened for display: `~/Library/Caches/x` (relative to the scanned home).
enum PathDisplay {
    static func short(_ url: URL, home: URL) -> String {
        let path = url.path
        let homePath = home.path
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
        return path
    }

    /// The folder a file is in, shortened.
    static func parent(_ url: URL, home: URL) -> String {
        short(url.deletingLastPathComponent(), home: home)
    }
}

enum Finder {
    @MainActor
    static func reveal(_ urls: [URL]) {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(existing)
    }
}
