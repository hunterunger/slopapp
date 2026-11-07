import AppKit
import DevkitCore

/// Test hooks, all off unless an environment variable turns them on:
///
/// - `DEVKIT_PASTEBOARD=<name>`: read and write a private named pasteboard instead of the
///   real clipboard (scripted tests must never touch the owner's clipboard).
/// - `DEVKIT_DEFAULTS=<suite>`: keep settings in this UserDefaults suite instead of the app's.
/// - `DEVKIT_APPEARANCE=light|dark`: force an appearance (for screenshots).
/// - `DEVKIT_NOW=<unix seconds>`: pretend it's this time (JWT expiry, relative dates).
/// - `DEVKIT_SEED=<number>`: repeatable "random" output (Lorem Ipsum, Random String) for screenshots.
/// - `DEVKIT_SNAPSHOT=<folder>`: render every tool offscreen to PNGs, light and dark, then quit
///   (see Snapshot.swift). For design review when the screen can't be captured.
enum Diagnostics {
    private static let environment = ProcessInfo.processInfo.environment

    static let pasteboardName = environment["DEVKIT_PASTEBOARD"]
    static let defaultsSuite = environment["DEVKIT_DEFAULTS"]
    static let forcedAppearance = environment["DEVKIT_APPEARANCE"]
    static let fixedNow = environment["DEVKIT_NOW"].flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }

    static func now() -> Date { fixedNow ?? Date() }

    static let seed = environment["DEVKIT_SEED"].flatMap(UInt64.init)

    /// The system's secure generator, or a seeded one under DEVKIT_SEED.
    static func randomSource() -> AppRandom { AppRandom(seed: seed) }

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

    func imageData() -> Data? {
        pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
    }

    func setPNG(_ data: Data) {
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
    }
}

/// SystemRandomNumberGenerator, or SplitMix64 when a seed is given (tests and screenshots).
struct AppRandom: RandomNumberGenerator {
    private var state: UInt64?
    private var system = SystemRandomNumberGenerator()

    init(seed: UInt64?) { state = seed }

    mutating func next() -> UInt64 {
        guard var z = state else { return system.next() }
        z &+= 0x9E37_79B9_7F4A_7C15
        state = z
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
