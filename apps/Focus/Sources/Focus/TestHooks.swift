import FocusCore
import Foundation
import SlopKit

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
enum TestHooks {
    private static let environment = ProcessInfo.processInfo.environment

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
    static let startAtLaunch = environment["FOCUS_START"] == "1"

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
