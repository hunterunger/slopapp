import AppKit
import CoreGraphics
import TriggersCore

/// Modifier keys held right now (for gestures, which carry none of their own).
struct SystemModifiers: ModifierReader {
    func current() -> Modifiers { Modifiers(cgFlags: CGEventSource.flagsState(.combinedSessionState).rawValue) }
}

/// Follows the frontmost app through workspace notifications. Never polled.
@MainActor
final class FrontAppTracker {
    var onChange: ((FrontApp?) -> Void)?
    private(set) var current: FrontApp?
    /// The last app in front that wasn't Triggers itself (for "Turn Off in <app>").
    private(set) var lastOther: FrontApp?
    private var observer: NSObjectProtocol?

    func start() {
        update(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                     object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self.update(app) }
        }
    }

    private func update(_ app: NSRunningApplication?) {
        var app = app
        if let forced = Diagnostics.forcedFrontApp {
            app = NSRunningApplication.runningApplications(withBundleIdentifier: forced).first ?? app
        }
        let front = app.map { FrontApp(bundleID: $0.bundleIdentifier, name: $0.localizedName ?? $0.bundleIdentifier ?? "App", pid: $0.processIdentifier) }
        current = front
        if let front, front.bundleID != Bundle.main.bundleIdentifier { lastOther = front }
        onChange?(front)
    }
}

/// Reads macOS's trackpad gesture settings, read-only (`CFPreferencesCopyAppValue`).
enum SystemGestureReader {
    static func read() -> SystemGestureSettings {
        SystemGestureSettings { key, domain in
            guard let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) else { return nil }
            return (value as? NSNumber)?.intValue
        }
    }
}

/// An app a binding can be scoped to or open.
struct AppChoice: Identifiable, Hashable {
    var bundleID: String
    var name: String
    var url: URL?
    var id: String { bundleID }
}

/// Apps for pickers and sidebar icons. In test mode (`TRIGGERS_FAKE_APPS`) a made-up list, so
/// screenshots never show what's installed or running.
@MainActor
enum AppCatalog {
    static func runningApps() -> [AppChoice] {
        if Diagnostics.fakeApps { return FakeCatalog.apps }
        let own = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != own }
            .map { AppChoice(bundleID: $0.bundleIdentifier!, name: $0.localizedName ?? $0.bundleIdentifier!, url: $0.bundleURL) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Asks for an app in /Applications.
    static func chooseApp(message: String) -> AppChoice? {
        let panel = NSOpenPanel()
        panel.message = message
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return AppChoice(bundleID: id, name: name, url: url)
    }

    private static var iconCache: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage {
        if let cached = iconCache[bundleID] { return cached }
        let image: NSImage
        if Diagnostics.fakeApps || FakeCatalog.apps.contains(where: { $0.bundleID == bundleID }) {
            image = NSWorkspace.shared.icon(for: .application)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSWorkspace.shared.icon(for: .application)
        }
        iconCache[bundleID] = image
        return image
    }

    static func isRunning(_ bundleID: String) -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
    }
}

/// Made-up apps and Shortcuts for screenshots and tests. The test target is real (it's the
/// throwaway window walkthroughs act on).
enum FakeCatalog {
    static let testTarget = AppChoice(bundleID: "app.slopapp.triggers.testtarget", name: "Triggers Test Target", url: nil)

    static let apps: [AppChoice] = [
        AppChoice(bundleID: "com.example.atlas", name: "Atlas Notes", url: nil),
        AppChoice(bundleID: "com.example.canvas", name: "Canvas Studio", url: nil),
        AppChoice(bundleID: "com.example.harbor", name: "Harbor Browser", url: nil),
        AppChoice(bundleID: "com.example.ledger", name: "Ledger", url: nil),
        testTarget,
    ]

    static let shortcuts = ["Log Water", "Start Focus Session", "Resize Image", "Send Arrival Time"]
}
