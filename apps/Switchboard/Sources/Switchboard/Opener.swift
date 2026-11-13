import AppKit
import ApplicationServices
import SwitchboardCore

/// Hands links to browsers. The only place that opens anything.
@MainActor
enum Opener {
    enum Failure: Error {
        case appMissing(String)
        case failed(String)
        /// A webmail target got something it can't write (or its compose address is broken).
        case cantCompose(String)
        case safari(SafariWindowError)
        /// An app link nothing on this Mac opens (or only Switchboard would).
        case noApp(String)

        var message: String {
            switch self {
            case .appMissing(let name): "\(name) isn't installed anymore. Choose another one in Switchboard's Settings."
            case .failed(let name): "Couldn't open the link in \(name). Try again, or pick another one."
            case .cantCompose(let name): "Couldn't start an email in \(name). Check its compose address in Switchboard's Settings › Email."
            case .safari(let error): error.message
            case .noApp(let scheme): "No app on this Mac opens \(scheme): links."
            }
        }
    }

    /// Safari private and profile windows. Replaced by a fake in dry runs.
    static var safari: SafariWindowOpening = AccessibilitySafariOpener()

    /// Opens `url` in `target`. Returns when the request has been handed to macOS (not when
    /// the page has loaded).
    static func open(_ url: URL, in target: Target, background: Bool = false) async throws {
        guard let plan = LaunchPlan.make(for: target, url: url, background: background) else {
            throw Failure.cantCompose(target.pickerTitle)
        }
        guard let appURL = appURL(for: target) else {
            throw Failure.appMissing(target.appName)
        }
        if Diagnostics.isDryRun {
            let access = plan.needsAccessibility ? " accessibility=\(AXIsProcessTrusted() ? "granted" : "missing")" : ""
            Diagnostics.record("dry-run open target=\"\(target.displayName)\" plan=\(plan.method) activates=\(plan.activates)\(access)")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = plan.activates
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false
        if plan.activates {
            // macOS 14+ only lets an app come forward if the active app allows it. We're a
            // background app, so this only matters when our Settings window is in front.
            NSApp.yieldActivation(toApplicationWithBundleIdentifier: target.bundleID)
        }

        do {
            switch plan.method {
            case .openURL(let link):
                try await NSWorkspace.shared.open([link], withApplicationAt: appURL, configuration: configuration)
            case .launchWithArguments(let arguments):
                // A new instance hands its arguments to the running browser (Chromium's
                // single-instance handoff), or starts the browser if it isn't running.
                configuration.arguments = arguments
                configuration.createsNewApplicationInstance = true
                try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            case .safariWindow(let request, let link):
                try await safari.open(request, url: link, safariURL: appURL)
            }
        } catch let error as SafariWindowError {
            throw Failure.safari(error)
        } catch {
            throw Failure.failed(target.appName)
        }
    }

    /// Whether some app other than Switchboard opens this app link (`zoommtg:`, `vscode:`).
    static func canOpen(_ url: URL) -> Bool {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return false }
        return Bundle(url: app)?.bundleIdentifier != Bundle.main.bundleIdentifier
    }

    /// Opens an app's own link (a handoff or a rewrite's result) in that app.
    static func open(_ app: AppLink) async throws {
        let scheme = app.url.scheme ?? ""
        let appURL = app.bundleID.flatMap(NSWorkspace.shared.urlForApplication(withBundleIdentifier:))
            ?? NSWorkspace.shared.urlForApplication(toOpen: app.url)
        guard let appURL, Bundle(url: appURL)?.bundleIdentifier != Bundle.main.bundleIdentifier else {
            throw Failure.noApp(scheme)
        }
        if Diagnostics.isDryRun {
            Diagnostics.record("dry-run open app=\"\(appURL.lastPathComponent)\" url=\(app.url.absoluteString.prefix(200))")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false
        if let id = Bundle(url: appURL)?.bundleIdentifier { NSApp.yieldActivation(toApplicationWithBundleIdentifier: id) }
        do {
            try await NSWorkspace.shared.open([app.url], withApplicationAt: appURL, configuration: configuration)
        } catch {
            throw Failure.failed(app.appName ?? appURL.deletingPathExtension().lastPathComponent)
        }
    }

    /// Lookups by bundle ID, cached: LaunchServices queries cost milliseconds and this runs
    /// for every link. A cached path is re-checked with a cheap file-exists.
    private static var locations: [String: URL] = [:]

    /// The app's current location: by bundle ID first (it may have moved), then the saved path.
    static func appURL(for target: Target) -> URL? {
        if let cached = locations[target.bundleID], FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleID)
            ?? Optional(URL(fileURLWithPath: target.appPath)).flatMap {
                FileManager.default.fileExists(atPath: $0.path) ? $0 : nil
            }
        locations[target.bundleID] = found
        return found
    }

    static func forgetLocations() {
        locations.removeAll()
    }

    static func isInstalled(_ target: Target) -> Bool {
        appURL(for: target) != nil
    }
}

/// Which app a handoff would use, cached like browser locations (LaunchServices lookups cost
/// milliseconds). Only asked for handoffs that are turned on.
@MainActor
enum HandoffApps {
    private static var found: [String: String?] = [:]

    static func installed(_ handoff: AppHandoff) -> String? {
        if let cached = found[handoff.id] { return cached }
        let id = handoff.bundleIDs.first { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        found[handoff.id] = id
        return id
    }

    static func forget() { found.removeAll() }
}
