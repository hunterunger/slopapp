import Foundation
import os
import QuartzCore

/// Logging and test hooks. All off unless an environment variable turns them on, so scripted
/// tests never touch someone's real settings, history, models, clipboard or apps:
///
/// - `DICTATE_DATA_DIR=/tmp/dictate-test/data`: keep history (and models, unless
///   `DICTATE_MODELS_DIR` says otherwise) here, and settings in the `app.slopapp.dictate.test`
///   defaults domain. The previous app's data is then only read from the `DICTATE_LEGACY_*`
///   paths below, never from its real location.
/// - `DICTATE_MODELS_DIR=/path`: where speech models live (default: Application Support/Models).
/// - `DICTATE_LEGACY_DEFAULTS=/path/prefs.plist`, `DICTATE_LEGACY_SUPPORT_DIR=/path`,
///   `DICTATE_LEGACY_MODELS_DIR=/path`: a fake previous install to import from (test mode).
/// - `DICTATE_FAKE_AUDIO=/path/speech.aiff`: "record" this file instead of the microphone, in
///   real time (no microphone permission needed, no room audio ever captured).
/// - `DICTATE_INSERT_ONLY_INTO=<bundle id or app name>`: type or paste only when that app is in
///   front; anything else is skipped and logged. Scripted tests use a throwaway window.
/// - `DICTATE_PASTEBOARD=name`: copy to this private pasteboard instead of the clipboard.
/// - `DICTATE_NO_HOTKEY=1`: no global shortcuts and no Fn monitor, so a test copy never
///   competes with another dictation app for the same key.
/// - `DICTATE_TEST_HOOKS=1`: listen for distributed notifications `app.slopapp.dictate.test.`
///   `start` (object "command" for Command Mode), `stop`, `cancel`, `file` (object: a path),
///   `history`, `onboarding`, `settings` (object: a tab name).
/// - `DICTATE_TRANSCRIBE=/path/audio` (+ `DICTATE_TRANSCRIBE_OUT=/path/result.txt`): load the
///   selected model, transcribe the file, write the text (and timings to the log), quit.
/// - `DICTATE_SETTINGS_TAB=general|shortcuts|models|cleanup|apps|about`: open Settings there.
/// - `DICTATE_ONBOARDING=1`: show the setup assistant at launch.
/// - `DICTATE_TEST_QUIET=1`: windows opened by test hooks never activate the app and go behind
///   other apps' windows, so a test run can screenshot them without taking anyone's focus.
/// - `DICTATE_LOG=/path/file.log`: append timings and decisions.
///
/// Keyboard shortcuts (KeyboardShortcuts), window positions and status item placement always
/// live in the app's own defaults domain. A copy of `build/Dictate.app` shares that domain
/// with an installed Dictate; `apps/Dictate/test-copy.sh` makes one with its own bundle id.
nonisolated enum Diagnostics {
    static let logger = Logger(subsystem: "app.slopapp.dictate", category: "dictate")

    private static let environment = ProcessInfo.processInfo.environment
    private static func path(_ key: String) -> URL? {
        environment[key].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }

    static let dataDirectory = path("DICTATE_DATA_DIR")
    static let modelsDirectory = path("DICTATE_MODELS_DIR")
    static let legacyDefaults = path("DICTATE_LEGACY_DEFAULTS")
    static let legacySupport = path("DICTATE_LEGACY_SUPPORT_DIR")
    static let legacyModels = path("DICTATE_LEGACY_MODELS_DIR")
    static let fakeAudio = path("DICTATE_FAKE_AUDIO")
    static let insertOnlyInto = environment["DICTATE_INSERT_ONLY_INTO"].flatMap { $0.isEmpty ? nil : $0 }
    static let pasteboardName = environment["DICTATE_PASTEBOARD"].flatMap { $0.isEmpty ? nil : $0 }
    static let noHotkey = environment["DICTATE_NO_HOTKEY"] == "1"
    static let testHooks = environment["DICTATE_TEST_HOOKS"] == "1"
    static let transcribeFile = path("DICTATE_TRANSCRIBE")
    static let transcribeOutput = path("DICTATE_TRANSCRIBE_OUT")
    static let initialSettingsTab = environment["DICTATE_SETTINGS_TAB"].flatMap(SettingsTab.init(rawValue:))
    static let showOnboarding = environment["DICTATE_ONBOARDING"] == "1"
    static let quiet = environment["DICTATE_TEST_QUIET"] == "1"
    /// scripts/smoke.sh: launch only, no first-run window.
    static let isSmokeTest = environment["SLOPAPP_SMOKE_TEST"] == "1"
    private static let logFile = path("DICTATE_LOG")

    /// Test mode: data, settings and the import source are all redirected.
    static var isTestMode: Bool { dataDirectory != nil }

    /// The installed app's bundle id. A test copy made by `apps/Dictate/test-copy.sh` has its
    /// own (`app.slopapp.dictate.test`), so everything it stores is separate by itself.
    static let sharesInstalledAppsDomain = Bundle.main.bundleIdentifier == "app.slopapp.dictate"

    /// Dictate's settings: its own domain, or a throwaway test domain.
    nonisolated(unsafe) static let defaults: UserDefaults = isTestMode && sharesInstalledAppsDomain
        ? UserDefaults(suiteName: "app.slopapp.dictate.test") ?? .standard : .standard

    /// Test copies never change login items: the switch would act on the installed app's
    /// registration (same bundle id) or add a login item for a throwaway copy.
    static var protectsLoginItems: Bool { isTestMode || !sharesInstalledAppsDomain }

    /// Seconds since boot, monotonic.
    static func now() -> TimeInterval { CACurrentMediaTime() }

    static func milliseconds(since start: TimeInterval) -> String {
        String(format: "%.0f", (now() - start) * 1000)
    }

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

/// Settings tabs, in order.
enum SettingsTab: String, Hashable, CaseIterable {
    case general, shortcuts, models, cleanup, apps, about
}
