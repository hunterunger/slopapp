import DropperCore
import Foundation
import os

/// Test hooks. All off unless an environment variable turns them on:
///
/// - `DROPPER_DATA_DIR=/tmp/dropper-test/data`: keep the color history here instead of
///   Application Support.
/// - `DROPPER_DEFAULTS=suite`: keep preferences in this UserDefaults suite instead of the app's.
/// - `DROPPER_PASTEBOARD=name`: write a private named pasteboard instead of the clipboard.
/// - `DROPPER_FAKE_PICKS=#3366CC,p3:#FF0000,cancel`: skip the system sampler and return these
///   colors in turn (sRGB hex, or `p3:` for Display P3; `cancel` acts like Esc). Scripted
///   walkthroughs of history and menus without moving the mouse.
/// - `DROPPER_LOG=/path/file.log`: append events (picked, copied text, cancelled) to a file.
///   Copied text is a color value, never clipboard content from elsewhere.
/// - `DROPPER_APPEARANCE=light|dark`: force an appearance (screenshots).
/// - `DROPPER_TEST_HOOKS=1`: listen for the distributed notifications
///   `app.slopapp.dropper.test.pick` and `.contrast` so scripts can start a pick without a
///   global key press.
enum Diagnostics {
    static let logger = Logger(subsystem: "app.slopapp.dropper", category: "dropper")

    private static let environment = ProcessInfo.processInfo.environment
    static let dataDirectory = environment["DROPPER_DATA_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
    static let defaultsSuite = environment["DROPPER_DEFAULTS"].flatMap { $0.isEmpty ? nil : $0 }
    static let pasteboardName = environment["DROPPER_PASTEBOARD"].flatMap { $0.isEmpty ? nil : $0 }
    static let forcedAppearance = environment["DROPPER_APPEARANCE"]
    static let testHooks = environment["DROPPER_TEST_HOOKS"] == "1"
    private static let logFile = environment["DROPPER_LOG"].map { URL(fileURLWithPath: $0) }

    /// nil when unset. Each entry is a color, or nil for a cancelled pick.
    static let fakePicks: [ColorValue?]? = environment["DROPPER_FAKE_PICKS"].map { list in
        list.split(separator: ",").map { raw -> ColorValue? in
            let token = raw.trimmingCharacters(in: .whitespaces)
            if token == "cancel" { return nil }
            if token.hasPrefix("p3:") { return HexParser.color(String(token.dropFirst(3)), in: .displayP3) }
            return HexParser.color(token, in: .sRGB)
        }
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
