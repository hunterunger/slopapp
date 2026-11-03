import AppKit
import DropperCore
import SlopKit

/// The system color sampler: the magnifier loupe macOS draws. Needs no permission because
/// it runs outside our process.
///
/// Measured on macOS 27 with a P3 display (see docs/research/dropper.md): it returns colors
/// tagged Display P3 at better than 8-bit precision. We convert to extended sRGB with
/// ColorSync, which keeps out-of-gamut values (plain `.sRGB` would clamp them silently).
@MainActor
final class SystemColorSampler: ColorSampling {
    private var sampler: NSColorSampler?

    func sample() async -> ColorValue? {
        await withCheckedContinuation { continuation in
            let sampler = NSColorSampler()
            self.sampler = sampler
            sampler.show { color in
                continuation.resume(returning: color.flatMap(Self.convert))
            }
        }
    }

    nonisolated static func convert(_ color: NSColor) -> ColorValue? {
        guard let c = color.usingColorSpace(.extendedSRGB) else { return nil }
        return ColorValue(red: Double(c.redComponent), green: Double(c.greenComponent), blue: Double(c.blueComponent))
    }
}

/// Returns preset colors instead of showing the loupe (`DROPPER_FAKE_PICKS`).
@MainActor
final class FakeColorSampler: ColorSampling {
    private var queue: [ColorValue?]

    init(_ queue: [ColorValue?]) {
        self.queue = queue
    }

    func sample() async -> ColorValue? {
        try? await Task.sleep(for: .milliseconds(150))
        guard !queue.isEmpty else { return nil }
        let next = queue.removeFirst()
        queue.append(next) // cycle so a walkthrough can keep going
        return next
    }
}

@MainActor
final class SystemClipboard: Clipboard {
    private let pasteboard: NSPasteboard

    init(name: String?) {
        pasteboard = name.map { NSPasteboard(name: NSPasteboard.Name($0)) } ?? .general
    }

    func write(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Diagnostics.record("copied \(text)")
    }
}

/// Preferences in UserDefaults, one key per setting so `defaults read` stays readable.
final class DefaultsPreferences: PreferencesStore, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load() -> Preferences {
        var p = Preferences()
        if let raw = defaults.string(forKey: "copyFormat"), let f = ColorFormat(rawValue: raw) { p.format = f }
        if let raw = defaults.string(forKey: "colorSpace"), let s = OutputSpace(rawValue: raw) { p.options.space = s }
        if defaults.object(forKey: "hexUppercase") != nil { p.options.hexUppercase = defaults.bool(forKey: "hexUppercase") }
        if defaults.object(forKey: "hexPrefix") != nil { p.options.hexPrefix = defaults.bool(forKey: "hexPrefix") }
        return p
    }

    func save(_ p: Preferences) {
        defaults.set(p.format.rawValue, forKey: "copyFormat")
        defaults.set(p.options.space.rawValue, forKey: "colorSpace")
        defaults.set(p.options.hexUppercase, forKey: "hexUppercase")
        defaults.set(p.options.hexPrefix, forKey: "hexPrefix")
    }
}

/// A history store that can't save (Application Support unavailable). The app still works.
struct UnavailableHistoryStore: HistoryStore {
    func load() throws -> [PickedColor] { [] }
    func save(_ items: [PickedColor]) throws {}
}

@MainActor
enum Services {
    static let defaults: UserDefaults = Diagnostics.defaultsSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard

    static func makeModel() -> DropperModel {
        let sampler: ColorSampling = Diagnostics.fakePicks.map { FakeColorSampler($0) } ?? SystemColorSampler()
        let store: HistoryStore
        if let dir = Diagnostics.dataDirectory {
            store = FileHistoryStore(directory: dir)
        } else if let dir = try? AppPaths.applicationSupport {
            store = FileHistoryStore(directory: dir)
        } else {
            store = UnavailableHistoryStore()
        }
        return DropperModel(sampler: sampler, clipboard: SystemClipboard(name: Diagnostics.pasteboardName),
                            historyStore: store, preferencesStore: DefaultsPreferences(defaults: defaults))
    }
}
