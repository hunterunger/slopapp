import AppKit
import SwitchboardCore

/// Hands links to browsers. The only place that opens anything.
@MainActor
enum Opener {
    enum Failure: Error {
        case appMissing(String)
        case failed(String)
    }

    /// Opens `url` in `target`. Returns when the request has been handed to macOS (not when
    /// the page has loaded).
    static func open(_ url: URL, in target: Target, background: Bool = false) async throws {
        let plan = LaunchPlan.make(for: target, url: url, background: background)
        guard let appURL = appURL(for: target) else {
            throw Failure.appMissing(target.appName)
        }
        if Diagnostics.isDryRun {
            Diagnostics.record("dry-run open target=\"\(target.displayName)\" plan=\(plan.method) activates=\(plan.activates)")
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
            }
        } catch {
            throw Failure.failed(error.localizedDescription)
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
