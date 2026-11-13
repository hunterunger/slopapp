import Foundation
import QuartzCore
import os

/// Logging and test mode. Everything is off unless an environment variable turns it on, so
/// scripted tests never touch someone's real snippets, keyboard, clipboard or apps:
///
/// - `SHORTHAND_DATA_DIR=/tmp/shorthand-test/data`: keep the library there and settings in
///   the `app.slopapp.shorthand.test` defaults domain.
/// - `SHORTHAND_NO_TAP=1`: never install the keyboard tap (replays only).
/// - `SHORTHAND_REPLAY=/path/timeline.json`: feed our own keystroke timeline (`ReplayTimeline`)
///   into the real engine, in process, at launch. Each key is also typed into the test
///   target so it shows what a person would see.
/// - `SHORTHAND_INSERT_ONLY_INTO=<bundle id>`: that running app counts as the front app, and
///   every key Shorthand posts goes to its process only (`postToPid`), never to the system's
///   input stream. Nothing is inserted anywhere else.
/// - `SHORTHAND_PASTEBOARD=<name>`: a private pasteboard instead of the clipboard.
/// - `SHORTHAND_PASTE_PRIVACY=allowed|asks|denied`: pretend macOS's "Paste from Other Apps"
///   is set that way.
/// - `SHORTHAND_FAKE_REPLACEMENTS=/path.plist`: "Import from This Mac" reads this fixture,
///   never the person's own Text Replacements.
/// - `SHORTHAND_FAKE_APPS=1`: the app picker lists made-up apps (screenshots never show
///   what's installed).
/// - `SHORTHAND_ASSUME_TRUSTED=0|1`: pretend Accessibility/Input Monitoring are (not) granted.
/// - `SHORTHAND_TEST_HOOKS=1`: distributed notifications `app.slopapp.shorthand.test.<name>`
///   (see TestHooks.swift).
/// - `SHORTHAND_ASSUME_SECURE_INPUT=0|1`: pretend secure input is off/on (only together with
///   `SHORTHAND_INSERT_ONLY_INTO`: replays while the screen is locked, when loginwindow holds it).
/// - `SHORTHAND_SNAPSHOT_DIR=/path`: render the library, editor, import sheet and Settings
///   offscreen in light and dark, then quit (layout review when the screen can't be driven).
/// - `SHORTHAND_LOG=/path/file.log`: decisions and timings. Never typed characters, never
///   snippet text.
nonisolated enum Diagnostics {
    static let logger = Logger(subsystem: "app.slopapp.shorthand", category: "shorthand")
    static let signposter = OSSignposter(subsystem: "app.slopapp.shorthand", category: "expansion")

    private static let environment = ProcessInfo.processInfo.environment
    private static func path(_ key: String) -> URL? {
        environment[key].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }
    private static func value(_ key: String) -> String? {
        environment[key].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// scripts/smoke.sh: launch only, no first-run window. A smoke run is a test run: a
    /// throwaway library, its own settings and shortcut names, no keyboard tap, so it never
    /// touches the person's snippets, settings or shortcuts.
    static let isSmokeTest = environment["SLOPAPP_SMOKE_TEST"] == "1"
    static let dataDirectory = path("SHORTHAND_DATA_DIR")
        ?? (isSmokeTest ? FileManager.default.temporaryDirectory.appendingPathComponent("shorthand-smoke-\(getpid())") : nil)
    static let noTap = environment["SHORTHAND_NO_TAP"] == "1" || isSmokeTest
    static let replayFile = path("SHORTHAND_REPLAY")
    static let insertOnlyInto = value("SHORTHAND_INSERT_ONLY_INTO")
    static let pasteboardName = value("SHORTHAND_PASTEBOARD")
    static let pastePrivacy = value("SHORTHAND_PASTE_PRIVACY")
    static let fakeReplacements = path("SHORTHAND_FAKE_REPLACEMENTS")
    static let fakeApps = environment["SHORTHAND_FAKE_APPS"] == "1"
    static let assumeTrusted: Bool? = environment["SHORTHAND_ASSUME_TRUSTED"].map { $0 == "1" }
    static let testHooks = environment["SHORTHAND_TEST_HOOKS"] == "1"
    static let assumeSecureInput: Bool? = environment["SHORTHAND_INSERT_ONLY_INTO"] == nil
        ? nil : environment["SHORTHAND_ASSUME_SECURE_INPUT"].map { $0 == "1" }
    static let snapshotDirectory = path("SHORTHAND_SNAPSHOT_DIR")
    private static let logFile = path("SHORTHAND_LOG")

    static var isTestMode: Bool { dataDirectory != nil }

    nonisolated(unsafe) static let defaults: UserDefaults = isTestMode
        ? UserDefaults(suiteName: "app.slopapp.shorthand.test") ?? .standard : .standard

    /// Seconds since boot, monotonic (same clock as the test pad's log).
    static func now() -> TimeInterval { CACurrentMediaTime() }

    static func record(_ line: String) {
        logger.debug("\(line, privacy: .public)")
        guard let logFile else { return }
        let stamped = String(format: "%.6f ", now()) + line + "\n"
        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(Data(stamped.utf8))
            try? handle.close()
        } else {
            try? Data(stamped.utf8).write(to: logFile)
        }
    }
}
