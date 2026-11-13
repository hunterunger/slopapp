import Foundation
import SlopKit
import os
import QuartzCore

/// Logging and test hooks. All off unless an environment variable turns them on:
///
/// - `SWITCHBOARD_LOG=/path/file.log`: append one line per routing decision, with timings.
/// - `SWITCHBOARD_DRY_RUN=1`: decide and log, but don't open anything (for scripted tests).
/// - `SWITCHBOARD_CONFIG=/path/config.json`: use this settings file instead of the real one.
/// - `SWITCHBOARD_APPEARANCE=light|dark`: force an appearance (for screenshots).
/// - `SWITCHBOARD_ASSUME_DEFAULT=1`: show the "is the default browser" state without being it
///   (screenshots of a test copy). With `SWITCHBOARD_DRY_RUN=1`, default-browser changes are
///   logged, never made.
/// - `SWITCHBOARD_SETTINGS_TAB=general|browsers|email|files|rules|rewrite|about`: open Settings on that tab at
///   launch (screenshots without Accessibility).
/// - `SLOP_SHOWCASE=picker|browsers|rules`: a store screenshot scene with synthetic settings
///   (`ShowcaseFixtures`; see Showcase.swift and docs/screenshots.md).
/// - `SWITCHBOARD_FLIP_APPEARANCE_AFTER=<seconds>`: switch light ↔ dark once while running
///   (checks that every surface follows a live appearance change).
///
/// - `SWITCHBOARD_INBOX=/path/dir`: route links dropped into this folder as `*.link` files,
///   as if macOS had sent them, so tests never use `open` (which would reach the installed
///   copy). Lines: `url=<link or file URL>`, optional `modifiers=option,command`,
///   `source=<bundle id>`, `pick=1`. Each file is deleted once read.
/// - `SWITCHBOARD_RENDER_DIR=/path/dir`: with the inbox, `render=<name>` draws our visible
///   windows into PNGs there (works with the screen locked); `tab=<name>` and `sheet=<name>`
///   show a Settings tab or sheet first.
/// - `SWITCHBOARD_MENU_PROBE=<bundle id>`: at launch, log that running app's File menu as
///   Accessibility reads it: positions, shortcuts and enabled state, never titles (checks the
///   menu reader used for Safari windows on a harmless app).
///
/// With `SWITCHBOARD_DRY_RUN=1`, becoming the browser, email app or a file type's app only
/// changes an in-memory copy of macOS's settings (seeded from the real ones) and is logged.
///
/// Timings also go to the unified log (subsystem app.slopapp.switchboard) at debug level.
enum Diagnostics {
    static let logger = Logger(subsystem: "app.slopapp.switchboard", category: "routing")

    private static let environment = ProcessInfo.processInfo.environment
    static let isDryRun = environment["SWITCHBOARD_DRY_RUN"] == "1"
    static let configOverride = environment["SWITCHBOARD_CONFIG"].map { URL(fileURLWithPath: $0) }
    static let forcedAppearance = environment["SWITCHBOARD_APPEARANCE"]
    static let assumesDefault = environment["SWITCHBOARD_ASSUME_DEFAULT"] == "1"
    static let appearanceFlipDelay = environment["SWITCHBOARD_FLIP_APPEARANCE_AFTER"].flatMap(Double.init)
    static let initialSettingsTab = environment["SWITCHBOARD_SETTINGS_TAB"].flatMap(SettingsTab.init(rawValue:))
        ?? ShowcaseRequest.parse(environment).flatMap { SettingsTab(rawValue: $0.scene) }
    private static let logFile = environment["SWITCHBOARD_LOG"].map { URL(fileURLWithPath: $0) }
    static let inboxDirectory = environment["SWITCHBOARD_INBOX"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    static let menuProbeBundleID = environment["SWITCHBOARD_MENU_PROBE"]
    static let renderDirectory = environment["SWITCHBOARD_RENDER_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }

    /// Seconds since boot, monotonic. For latency measurements.
    static func now() -> TimeInterval { CACurrentMediaTime() }

    static func milliseconds(since start: TimeInterval) -> String {
        String(format: "%.2f", (now() - start) * 1000)
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
