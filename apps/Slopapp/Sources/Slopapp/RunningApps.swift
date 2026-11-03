import AppKit
import SlopappCore

/// Running copies of apps, matched by their exact location on disk (two copies of the same
/// app in different folders are different apps here).
@MainActor
enum RunningApps {
    static func instance(at url: URL) -> NSRunningApplication? {
        let target = url.standardizedFileURL.resolvingSymlinksInPath().path
        return NSWorkspace.shared.runningApplications.first {
            $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path == target
        }
    }

    static func isRunning(at url: URL) -> Bool { instance(at: url) != nil }

    /// Asks the app to quit and waits up to `timeout` seconds. False if it's still running
    /// (e.g. it asked about unsaved changes and the user cancelled).
    static func quit(at url: URL, timeout: TimeInterval = 15) async -> Bool {
        guard let app = instance(at: url) else { return true }
        app.terminate()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.isTerminated { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return app.isTerminated
    }

    static func open(_ url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}
