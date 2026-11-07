import Foundation
import os
import QuartzCore

/// Logging and test hooks. All off unless an environment variable turns them on:
///
/// - `RULER_TEST_SCENE=1`: open a window with shapes at known sizes ("Ruler Test Scene").
///   While it's open, the frozen screen contains only that window: the capture keeps just
///   the scene and everything else (other apps, the menu bar, the desktop) is masked out,
///   so the overlay can never show or measure anything personal.
/// - `RULER_TEST_HOOKS=1`: listen for the distributed notifications
///   `app.slopapp.ruler.test.<measure|close|selfcheck|hover|drag|key|background|resume|restore|shotcheck>`. `selfcheck` measures every test-scene
///   shape on the real frozen image (overlay must be open, test scene on) and logs the result.
/// - `RULER_LOG=/path/file.log`: append timings and measurements (sizes only) to a file.
/// - `RULER_APPEARANCE=light|dark`: force an appearance (screenshots).
/// - `RULER_PASTEBOARD=name`: copy to a private named pasteboard instead of the clipboard.
/// - `RULER_SCREENSHOT_DIR=/path`: save measurement screenshots there instead of the
///   folder in Settings.
enum Diagnostics {
    static let logger = Logger(subsystem: "app.slopapp.ruler", category: "ruler")

    private static let environment = ProcessInfo.processInfo.environment
    static let testScene = environment["RULER_TEST_SCENE"].map { !$0.isEmpty && $0 != "0" } ?? false
    static let testHooks = environment["RULER_TEST_HOOKS"] == "1"
    static let forcedAppearance = environment["RULER_APPEARANCE"]
    /// `RULER_FAKE_CAPTURE=1` (test scene only): freeze by drawing the scene, not by
    /// recording the screen. See `SceneRenderCapturer`.
    static let fakeCapture = testScene && environment["RULER_FAKE_CAPTURE"] == "1"
    static let pasteboardName = environment["RULER_PASTEBOARD"].flatMap { $0.isEmpty ? nil : $0 }
    static let screenshotDirectory = environment["RULER_SCREENSHOT_DIR"].flatMap { $0.isEmpty ? nil : $0 }
    private static let logFile = environment["RULER_LOG"].map { URL(fileURLWithPath: $0) }

    /// Seconds since boot, monotonic.
    static func now() -> TimeInterval { CACurrentMediaTime() }

    static func milliseconds(since start: TimeInterval) -> String {
        String(format: "%.1f", (now() - start) * 1000)
    }

    /// Records an event. Never pass screen content here: only sizes, kinds and timings.
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
