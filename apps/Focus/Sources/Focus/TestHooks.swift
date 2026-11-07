import AppKit
import FocusCore
import Foundation
import SlopKit
import SwiftUI

/// Test and scripting hooks. All off unless an environment variable turns them on:
///
/// - `FOCUS_DATA_DIR=/tmp/focus-test/data`: keep state, settings and history there instead
///   of ~/Library/Application Support/app.slopapp.focus.
/// - `FOCUS_TEST_LOG=/tmp/focus-test/effects.log`: don't post real notifications, play
///   sounds or run shortcuts; append one line per effect to this file instead.
/// - `FOCUS_TEST_PERMISSION=authorized|denied|notDetermined`: the notification permission
///   the log notifier reports (default authorized). Asking turns notDetermined into denied.
/// - `FOCUS_TEST_SHORTCUTS="Work On,Work Off"`: shortcut names the log runner lists.
///   A name containing "fail" fails when run.
/// - `FOCUS_SECONDS_PER_MINUTE=1`: make a "minute" last one second, to run whole sessions fast.
/// - `FOCUS_APPEARANCE=light|dark`: force an appearance (screenshots).
/// - `FOCUS_START=1`: start a focus session at launch.
/// - `FOCUS_OPEN_WINDOW=1`: open the Focus window at launch.
/// - `FOCUS_HIDE_REAL=1`: with `FOCUS_TEST_LOG`, really hide the apps on the test settings'
///   hide list (otherwise hiding is only logged).
/// - `FOCUS_SNAPSHOT_DIR=/tmp/x`: render every window and state offscreen to PNGs, then quit.
/// - `FOCUS_SAMPLE_HISTORY=1`: with `FOCUS_DATA_DIR`, fill an empty test history with five
///   weeks of made-up sessions (stats screenshots without anyone's real data).
/// - `FOCUS_PANEL_WINDOW=1`: also show the menu bar panel's content in an ordinary window
///   titled "Panel", live (for driving and screenshots when the status item can't be clicked).
/// - `FOCUS_BREAK_WINDOW=1`: show the break screen as one opaque 1100 x 760 window on the main
///   display instead of a translucent cover over every screen (screenshots that can't
///   include anything behind it).
enum TestHooks {
    private static let environment = ProcessInfo.processInfo.environment

    /// Set only when `FOCUS_DATA_DIR` points somewhere: test hooks that write data need it.
    static let testDataDirectory: URL? = environment["FOCUS_DATA_DIR"].flatMap {
        $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true)
    }

    static let dataDirectory: URL = {
        if let path = environment["FOCUS_DATA_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return (try? AppPaths.applicationSupport)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("app.slopapp.focus")
    }()

    static let effectsLog: URL? = environment["FOCUS_TEST_LOG"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }

    static let permission: NotificationPermission =
        environment["FOCUS_TEST_PERMISSION"].flatMap(NotificationPermission.init(rawValue:)) ?? .authorized

    static let shortcutNames: [String] = (environment["FOCUS_TEST_SHORTCUTS"] ?? "")
        .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

    static let secondsPerMinute: TimeInterval = {
        guard let value = environment["FOCUS_SECONDS_PER_MINUTE"].flatMap(Double.init), value > 0, value.isFinite else { return 60 }
        return value
    }()

    static let forcedAppearance = environment["FOCUS_APPEARANCE"]
    /// With `FOCUS_TEST_LOG`, "Hide Apps" only logs unless this is 1.
    static let hideAppsForReal = environment["FOCUS_HIDE_REAL"] == "1"
    /// Render the windows offscreen to PNGs in this folder, then quit.
    static let snapshotDirectory = environment["FOCUS_SNAPSHOT_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
    /// Open the Focus window at launch (walkthroughs).
    static let openWindowAtLaunch = environment["FOCUS_OPEN_WINDOW"] == "1"
    static let startAtLaunch = environment["FOCUS_START"] == "1"
    static let panelWindow = environment["FOCUS_PANEL_WINDOW"] == "1"
    /// Break screen as one opaque window (screenshots).
    static let breakScreenWindowed = environment["FOCUS_BREAK_WINDOW"] == "1"

    /// `FOCUS_SAMPLE_HISTORY=1`: writes made-up history into an empty *test* data folder.
    /// Never touches the real one (requires `FOCUS_DATA_DIR`).
    static func seedSampleHistoryIfAsked(into storage: FileStorage) {
        guard environment["FOCUS_SAMPLE_HISTORY"] == "1", testDataDirectory != nil,
              storage.allRecords().isEmpty else { return }
        for record in SampleHistory.make(endingBefore: Date().addingTimeInterval(-40 * 60)) {
            try? storage.append(record)
        }
    }

    /// UNUserNotificationCenter only works inside a real .app bundle.
    static var isInAppBundle: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static func log(_ line: String) {
        guard let url = effectsLog else { return }
        let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(stamped.utf8))
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(stamped.utf8).write(to: url)
        }
    }
}

/// Notifications written to the test log instead of Notification Center.
@MainActor
final class LogNotifier: Notifier {
    var onAction: ((AlertAction) -> Void)?
    private var current = TestHooks.permission

    func permission() async -> NotificationPermission { current }

    func requestPermission() async -> NotificationPermission {
        TestHooks.log("permission requested (was \(current.rawValue))")
        if current == .notDetermined { current = .denied }
        return current
    }

    func post(_ content: AlertContent) {
        let actions = content.actions.map(\.title).joined(separator: "|")
        TestHooks.log("notify title=\"\(content.title)\" body=\"\(content.body)\" actions=\(actions) permission=\(current.rawValue)")
    }

    func clearDelivered() {}
}

@MainActor
final class LogSound: SoundPlayer {
    var availableSounds: [String] { SystemSound.systemSoundNames }
    func play(_ name: String) { TestHooks.log("sound \(name)") }
}

struct LogShortcutRunner: ShortcutRunner {
    let names: [String]

    func list() async throws -> [String] { names }

    func run(_ name: String) async throws {
        TestHooks.log("shortcut run \"\(name)\"")
        if name.lowercased().contains("fail") { throw ShortcutError.couldntRun(name) }
    }
}

/// `FOCUS_PANEL_WINDOW=1`: the menu bar panel's view in a plain window, live.
@MainActor
enum PanelTestWindow {
    private static var window: NSWindow?

    static func showIfAsked() {
        guard TestHooks.panelWindow, window == nil else { return }
        let view = MenuPanel(controller: AppModel.controller, intention: AppModel.intention,
                             reflection: AppModel.reflection, info: AppInfo.current(fallbackName: "Focus"))
        let hosting = NSHostingController(rootView: view)
        // Self-sizing, like the real menu bar window, so state changes resize it the same way.
        hosting.sizingOptions = [.preferredContentSize]
        let panel = NSWindow(contentViewController: hosting)
        panel.title = "Panel"
        panel.styleMask = [.titled, .closable]
        panel.isReleasedWhenClosed = false
        panel.setFrameTopLeftPoint(NSPoint(x: 80, y: (NSScreen.main?.visibleFrame.maxY ?? 800) - 40))
        panel.orderFrontRegardless()
        window = panel
    }
}
