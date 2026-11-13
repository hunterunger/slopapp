import Foundation
import QuartzCore
import os

/// Logging and test mode. Everything is off unless an environment variable turns it on, so
/// scripted tests never touch someone's real triggers, apps, Shortcuts or input:
///
/// - `TRIGGERS_DATA_DIR=/tmp/triggers-test/data`: keep triggers there and settings in the
///   `app.slopapp.triggers.test` defaults domain.
/// - `TRIGGERS_NO_INPUT=1`: no MultitouchSupport, no event taps, no hotkeys. Only replays.
///   This is the default in test mode (`TRIGGERS_DATA_DIR` set): a test copy never watches
///   the owner's input unless `TRIGGERS_LIVE_INPUT=1` asks for it.
/// - `TRIGGERS_LIVE_INPUT=1`: in test mode, install the real sources anyway (tap self-test).
///   The hyper key's Caps Lock remap is never applied in test mode, live input or not.
/// - `TRIGGERS_DRY_RUN=1`: every action is logged, never performed (nothing posted, opened
///   or run).
/// - `TRIGGERS_RUN_SCRIPTS=1`: in test mode, shell scripts and AppleScripts run for real (for
///   walkthroughs whose scripts only touch /tmp). Otherwise test mode only logs them.
/// - `TRIGGERS_REPLAY=/path/timeline.json`: feed touch frames, button presses and key combos
///   (our own JSON, `ReplayTimeline`) into the real recognizer and router, in-process only.
/// - `TRIGGERS_ACT_ONLY_IN=<bundle id>`: act only while that app is in front; anything else is
///   skipped and logged. Keys and clicks go to that app's process (`postToPid`), never to the
///   system's input stream; menu and window actions only ever resolve that app.
/// - `TRIGGERS_FAKE_APPS=1`: app and Shortcut pickers list made-up apps and Shortcuts, so
///   screenshots never show what's installed. Open and Run Shortcut only log what they'd do.
/// - `TRIGGERS_TEST_HOOKS=1`: distributed notifications `app.slopapp.triggers.test.<name>`:
///   `editor`, `settings` (object: tab), `replay` (object: path), `newTrigger`, `edit` (object:
///   the binding's index), `select` (object: a bundle id, `allApps` or `browsers`), `record`
///   (object: a trigger description for the recognize pad), `tapStats`, `tapSelfTest`.
/// - `TRIGGERS_TEST_QUIET=1`: windows opened by hooks don't take focus.
/// - `TRIGGERS_ASSUME_TRUSTED=0|1`: pretend Accessibility is (not) granted (screenshots).
/// - `TRIGGERS_GESTURES_UNAVAILABLE=1`: act as if the trackpad source failed to load.
/// - `TRIGGERS_FRONT_APP=<bundle id>`: treat that running app as the front app whatever is
///   really in front (replays against the test target while the screen is locked or busy).
///   Only with `TRIGGERS_ACT_ONLY_IN` set to the same app.
/// - `TRIGGERS_SNAPSHOT_DIR=/path`: render the editor, sheet and Settings offscreen to PNGs in
///   light and dark, then quit (layout review when the screen can't be driven).
/// - `TRIGGERS_LOG=/path/file.log`: decisions and timings.
/// - `TRIGGERS_PERF_LOG=/path/perf.log`: latency histograms only (numbers, never inputs).
nonisolated enum Diagnostics {
    static let logger = Logger(subsystem: "app.slopapp.triggers", category: "triggers")

    private static let environment = ProcessInfo.processInfo.environment
    private static func path(_ key: String) -> URL? {
        environment[key].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }

    static let dataDirectory = path("TRIGGERS_DATA_DIR")
    static let liveInput = environment["TRIGGERS_LIVE_INPUT"] == "1"
    /// The smoke test (`scripts/smoke.sh`) runs the bare binary against the person's real
    /// settings for a few seconds: it never watches input, remaps keys or acts.
    static let noInput = environment["TRIGGERS_NO_INPUT"] == "1" || (dataDirectory != nil && !liveInput) || isSmokeTest
    static let dryRun = environment["TRIGGERS_DRY_RUN"] == "1" || isSmokeTest
    static let runScripts = environment["TRIGGERS_RUN_SCRIPTS"] == "1"
    static let replayFile = path("TRIGGERS_REPLAY")
    static let actOnlyIn = environment["TRIGGERS_ACT_ONLY_IN"].flatMap { $0.isEmpty ? nil : $0 }
    static let fakeApps = environment["TRIGGERS_FAKE_APPS"] == "1"
    static let testHooks = environment["TRIGGERS_TEST_HOOKS"] == "1"
    static let quiet = environment["TRIGGERS_TEST_QUIET"] == "1"
    static let assumeTrusted: Bool? = environment["TRIGGERS_ASSUME_TRUSTED"].map { $0 == "1" }
    static let gesturesUnavailable = environment["TRIGGERS_GESTURES_UNAVAILABLE"] == "1"
    static let initialSettingsTab = environment["TRIGGERS_SETTINGS_TAB"]
    static let opensEditor = environment["TRIGGERS_OPEN_EDITOR"] == "1"
    static let snapshotDirectory = path("TRIGGERS_SNAPSHOT_DIR")
    static let forcedFrontApp: String? = {
        guard let id = environment["TRIGGERS_FRONT_APP"], !id.isEmpty, id == environment["TRIGGERS_ACT_ONLY_IN"] else { return nil }
        return id
    }()
    /// scripts/smoke.sh: launch only, no first-run window.
    static let isSmokeTest = environment["SLOPAPP_SMOKE_TEST"] == "1"
    private static let logFile = path("TRIGGERS_LOG")
    static let perfLogFile = path("TRIGGERS_PERF_LOG")

    /// Test mode: data and settings are redirected.
    static var isTestMode: Bool { dataDirectory != nil }

    /// Actions that would reach the person's own apps (open, run Shortcut) are logged instead.
    static var fakesOutsideEffects: Bool { fakeApps || actOnlyIn != nil || dryRun }

    /// Actions that change the whole Mac (media keys, volume, brightness, sleeping or locking
    /// the screen, Mission Control, dark mode) are only ever logged in test mode: there's no
    /// test target to keep them in.
    static var fakesSystemEffects: Bool { isTestMode || fakesOutsideEffects }

    /// Whether the hyper key may really remap Caps Lock: never in test mode or a dry run.
    static var mayRemapKeys: Bool { !isTestMode && !noInput && !dryRun && !isSmokeTest }

    nonisolated(unsafe) static let defaults: UserDefaults = isTestMode
        ? UserDefaults(suiteName: "app.slopapp.triggers.test") ?? .standard : .standard

    /// Seconds since boot, monotonic (same clock as `NSEvent.timestamp`).
    static func now() -> TimeInterval { CACurrentMediaTime() }

    static func record(_ line: String) {
        logger.debug("\(line, privacy: .public)")
        guard let logFile else { return }
        append(line, to: logFile)
    }

    static func perf(_ line: String) {
        logger.debug("perf \(line, privacy: .public)")
        guard let perfLogFile else { return }
        append(line, to: perfLogFile)
    }

    private static func append(_ line: String, to url: URL) {
        let stamped = String(format: "%.6f ", now()) + line + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(stamped.utf8))
            try? handle.close()
        } else {
            try? Data(stamped.utf8).write(to: url)
        }
    }
}
