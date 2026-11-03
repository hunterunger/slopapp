import AppKit
import DevkitCore

/// Test hooks, all off unless an environment variable turns them on:
///
/// - `DEVKIT_PASTEBOARD=<name>`: read and write a private named pasteboard instead of the
///   real clipboard (scripted tests must never touch the owner's clipboard).
/// - `DEVKIT_DEFAULTS=<suite>`: keep settings in this UserDefaults suite instead of the app's.
/// - `DEVKIT_APPEARANCE=light|dark`: force an appearance (for screenshots).
/// - `DEVKIT_NOW=<unix seconds>`: pretend it's this time (JWT expiry, relative dates).
enum Diagnostics {
    private static let environment = ProcessInfo.processInfo.environment

    static let pasteboardName = environment["DEVKIT_PASTEBOARD"]
    static let defaultsSuite = environment["DEVKIT_DEFAULTS"]
    static let forcedAppearance = environment["DEVKIT_APPEARANCE"]
    static let fixedNow = environment["DEVKIT_NOW"].flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }

    static func now() -> Date { fixedNow ?? Date() }

    /// Settings storage: the app's own defaults, or a throwaway suite for tests.
    nonisolated(unsafe) static let defaults: UserDefaults = defaultsSuite.flatMap { UserDefaults(suiteName: $0) } ?? .standard
}

/// The real pasteboard (or a private named one under test).
final class SystemClipboard: Clipboard {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    static func current() -> SystemClipboard {
        if let name = Diagnostics.pasteboardName {
            return SystemClipboard(pasteboard: NSPasteboard(name: NSPasteboard.Name(name)))
        }
        return SystemClipboard(pasteboard: .general)
    }

    var changeCount: Int { pasteboard.changeCount }
    var types: [String] { pasteboard.types?.map(\.rawValue) ?? [] }
    func string() -> String? { pasteboard.string(forType: .string) }

    func fileURL() -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first
    }

    func setString(_ string: String) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
