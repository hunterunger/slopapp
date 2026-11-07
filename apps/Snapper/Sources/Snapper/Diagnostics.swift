import SlopKit
import Foundation
import os
import QuartzCore

/// Logging and test hooks. All off unless an environment variable turns them on:
///
/// - `SNAPPER_SAVE_DIR=/tmp/snapper-test/out`: Save (and "save after capture") write here
///   instead of the folder chosen in Settings. Tests must always set this.
/// - `SNAPPER_LOG=/path/file.log`: append timings (overlay shown, capture → card) to a file.
/// - `SNAPPER_APPEARANCE=light|dark`: force an appearance (screenshots).
/// - `SNAPPER_TEST_SCENE=1`: open a large window with a generated test pattern; every capture
///   (area, window, full screen, previous area) then contains only that window: the capture
///   filter keeps just the scene, everything outside its frame and the menu bar strip is
///   masked to transparent, and window capture refuses any other window. `SNAPPER_TEST_SCENE=full` covers the whole
///   screen of the pointer, menu bar and Dock included (for full-screen capture tests; keep
///   these short). The scene closes with the app.
/// - `SNAPPER_TEST_HOOKS=1`: listen for the distributed notifications
///   `app.slopapp.snapper.test.<area|window|fullScreen|previousArea|cancel|closeCards|closePins>`
///   so scripts can trigger and time captures without global keys.
/// - `SNAPPER_HISTORY_DIR=/tmp/snapper-test/history`: Capture History is kept here instead of
///   `~/Library/Application Support/app.slopapp.snapper/History`. Tests must always set it.
/// - `SNAPPER_SILENT=1`: no shutter sound regardless of the setting.
/// - `SNAPPER_CARD_HOVER=1`: thumbnails (and pins' close button) always look hovered (for
///   screenshots).
/// - More hooks for screenshots without the real mouse: `editorSample` (a few marks in the
///   front editor, the rectangle selected), `editorCrop`, `editorSelect`, `editorBackground`,
///   `editorDone`, `pinLast`, `permissionWindow`, `openSettings`, `settings.<pane>`, and
///   `appearanceLight` / `appearanceDark` (a live appearance change, to check that layer
///   colours follow it).
/// - `SNAPPER_PASTEBOARD=<name>`: Copy (images, recognized text, recordings) writes to a
///   private named pasteboard instead of the real clipboard, so tests can read it back
///   without touching the owner's clipboard.
/// - Test mode also covers the newer captures: scrolling captures and self-timer captures go
///   through the same filtered + masked snapshots, and recordings stream only the test scene
///   window (a single-window stream), clipped to the selection inside it.
enum Diagnostics {
    static let logger = Logger(subsystem: "app.slopapp.snapper", category: "snapper")

    private static let environment = ProcessInfo.processInfo.environment
    static let saveDirectory = environment["SNAPPER_SAVE_DIR"].flatMap { $0.isEmpty ? nil : $0 }
    static let forcedAppearance = environment["SNAPPER_APPEARANCE"]
    static let testScene = environment["SNAPPER_TEST_SCENE"].flatMap { $0.isEmpty || $0 == "0" ? nil : $0 }
    static let testHooks = environment["SNAPPER_TEST_HOOKS"] == "1"
    static let silent = environment["SNAPPER_SILENT"] == "1"
    /// `SNAPPER_CARD_HOVER=1`: thumbnails always show their hover controls (screenshots).
    static let forceCardHover = environment["SNAPPER_CARD_HOVER"] == "1"
    static let pasteboardName = environment["SNAPPER_PASTEBOARD"].flatMap { $0.isEmpty ? nil : $0 }
    /// `SNAPPER_HISTORY_DIR`: Capture History lives here instead of Application Support.
    static let historyDirectory = environment["SNAPPER_HISTORY_DIR"].flatMap { $0.isEmpty ? nil : $0 }
    /// `SNAPPER_SNAPSHOT_DIR`: where the `snapshotWindows` hook writes its PNGs.
    static let snapshotDirectory = environment["SNAPPER_SNAPSHOT_DIR"].flatMap { $0.isEmpty ? nil : $0 }
    private static let logFile = environment["SNAPPER_LOG"].map { URL(fileURLWithPath: $0) }

    /// Seconds since boot, monotonic. For latency measurements.
    static func now() -> TimeInterval { CACurrentMediaTime() }

    static func milliseconds(since start: TimeInterval) -> String {
        String(format: "%.1f", (now() - start) * 1000)
    }

    /// Records an event. Never pass capture content here: only sizes, kinds and timings.
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
