import Foundation
import os
import QuartzCore

/// Logging and test hooks. All off unless an environment variable turns them on:
///
/// - `CLIPS_DATA_DIR=/tmp/clips-test/data`: keep the history here instead of Application Support,
///   the rendered sounds in its `Sounds` folder, and the settings in the `app.slopapp.clips.test`
///   defaults domain instead of Clips' own (so a test run never changes someone's settings).
/// - `CLIPS_PASTEBOARD=name`: watch and write a private named pasteboard instead of the
///   system clipboard (scripted tests; direct paste still sends ⌘V, which reads the real one).
/// - `CLIPS_SEED=5000`: fill an empty test history with synthetic clips (only with CLIPS_DATA_DIR).
/// - `CLIPS_LOG=/path/file.log`: append timings (panel shown, search, capture) to a file.
/// - `CLIPS_APPEARANCE=light|dark`: force an appearance (screenshots).
/// - `CLIPS_SHOW_PANEL=1`: open the panel right after launch (scripted tests).
/// - `CLIPS_TEST_HOOKS=1`: listen for the distributed notifications
///   `app.slopapp.clips.test.show` (object "passive": without taking the keyboard), `.hide`,
///   `.search` (object = query), `.numbers` (object "1" shows the ⌘-number badges as if ⌘
///   were held), `.select` (card index), `.preview` ("1"/"0"), `.tab` (tab index) and `.do`
///   ("pause", "resume", "pin", "copy" (the selected clip, as Return without direct paste), "delete", "cards", "search", "history", "settings",
///   "backdrop", "nobackdrop") so scripts can time and
///   screenshot the panel without Accessibility or synthetic keys.
/// - `CLIPS_NO_HOTKEY=1`: don't register the global shortcut, so a test copy can run beside
///   someone's real Clips without taking ⇧⌥V from it.
/// - `CLIPS_ALLOW_CAPTURE=1`: let screenshots see the panel even when "Hide from screen
///   sharing" is on (scripted tests and blind testers need screenshots).
enum Diagnostics {
    static let logger = Logger(subsystem: "app.slopapp.clips", category: "clips")

    private static let environment = ProcessInfo.processInfo.environment
    static let dataDirectory = environment["CLIPS_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    static let pasteboardName = environment["CLIPS_PASTEBOARD"].flatMap { $0.isEmpty ? nil : $0 }
    static let seedCount = environment["CLIPS_SEED"].flatMap(Int.init)
    static let forcedAppearance = environment["CLIPS_APPEARANCE"]
    static let showPanelAtLaunch = environment["CLIPS_SHOW_PANEL"] == "1"
    static let allowCapture = environment["CLIPS_ALLOW_CAPTURE"] == "1"
    static let testHooks = environment["CLIPS_TEST_HOOKS"] == "1"
    static let noHotkey = environment["CLIPS_NO_HOTKEY"] == "1"
    /// Clips' settings: its own domain, or `app.slopapp.clips.test` under `CLIPS_DATA_DIR`.
    /// (UserDefaults is thread-safe; the SDK just doesn't mark it Sendable.)
    nonisolated(unsafe) static let defaults: UserDefaults = dataDirectory == nil
        ? .standard : UserDefaults(suiteName: "app.slopapp.clips.test") ?? .standard
    private static let logFile = environment["CLIPS_LOG"].map { URL(fileURLWithPath: $0) }

    static var isLogging: Bool { logFile != nil }

    /// Seconds since boot, monotonic. For latency measurements.
    static func now() -> TimeInterval { CACurrentMediaTime() }

    static func milliseconds(since start: TimeInterval) -> String {
        String(format: "%.2f", (now() - start) * 1000)
    }

    /// Logs how long until the main thread is free again after `start`, i.e. after SwiftUI
    /// has applied the change and laid out. Two hops so the update transaction has run.
    @MainActor
    static func recordWhenIdle(_ label: String, since start: TimeInterval) {
        guard isLogging else { return }
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                record("\(label) ms=\(milliseconds(since: start))")
            }
        }
    }

    /// Records an event. Never pass clipboard content here: only sizes, kinds and timings.
    static func record(_ line: String) {
        logger.debug("\(line, privacy: .public)")
        guard let logFile else { return }
        let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(Data(stamped.utf8))
            try? handle.close()
        } else {
            try? Data(stamped.utf8).write(to: logFile)
        }
    }
}
