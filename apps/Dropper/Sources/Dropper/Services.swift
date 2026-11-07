import AppKit
import DropperCore
import Observation
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

    func sample(prompt: String?) async -> ColorValue? {
        if let prompt { PromptHUD.show(prompt) }
        return await withCheckedContinuation { continuation in
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

/// Uses the precise loupe when it's chosen and Screen Recording is allowed; the system
/// sampler otherwise (with a one-line note when the precise loupe can't run).
@MainActor
final class RoutingSampler: ColorSampling {
    let system: ColorSampling
    let precise: ColorSampling
    let settings: AppSettings
    let hasScreenRecording: () -> Bool

    init(system: ColorSampling, precise: ColorSampling, settings: AppSettings, hasScreenRecording: @escaping () -> Bool) {
        self.system = system
        self.precise = precise
        self.settings = settings
        self.hasScreenRecording = hasScreenRecording
    }

    func sample(prompt: String?) async -> ColorValue? {
        guard settings.pickerEngine == .precise else { return await system.sample(prompt: prompt) }
        guard hasScreenRecording() else {
            Diagnostics.record("precise picker unavailable: no screen recording")
            PromptHUD.show("Screen Recording is off, so Dropper uses the system magnifier")
            return await system.sample(prompt: prompt)
        }
        return await precise.sample(prompt: prompt)
    }
}

/// Returns preset colors instead of showing the loupe (`DROPPER_FAKE_PICKS`).
@MainActor
final class FakeColorSampler: ColorSampling {
    private var queue: [ColorValue?]

    init(_ queue: [ColorValue?]) {
        self.queue = queue
    }

    func sample(prompt: String?) async -> ColorValue? {
        if let prompt { Diagnostics.record("prompt \(prompt)") }
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
        Diagnostics.record("copied \(text.replacingOccurrences(of: "\n", with: " | "))")
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
        if let hidden = defaults.stringArray(forKey: "hiddenFormats") {
            p.hiddenFormats = Set(hidden.compactMap(ColorFormat.init(rawValue:)))
        }
        p.usesAppFormats = defaults.bool(forKey: "useAppFormats")
        if let table = defaults.dictionary(forKey: "appFormats") as? [String: String] {
            p.appFormats = table.compactMapValues(ColorFormat.init(rawValue:))
        }
        return p
    }

    func save(_ p: Preferences) {
        defaults.set(p.format.rawValue, forKey: "copyFormat")
        defaults.set(p.options.space.rawValue, forKey: "colorSpace")
        defaults.set(p.options.hexUppercase, forKey: "hexUppercase")
        defaults.set(p.options.hexPrefix, forKey: "hexPrefix")
        defaults.set(p.hiddenFormats.map(\.rawValue).sorted(), forKey: "hiddenFormats")
        defaults.set(p.usesAppFormats, forKey: "useAppFormats")
        defaults.set(p.appFormats.mapValues(\.rawValue), forKey: "appFormats")
    }
}

/// A library store that can't save (Application Support unavailable). The app still works.
struct UnavailableLibraryStore: LibraryStore {
    func load() throws -> LibraryContents { LibraryContents() }
    func save(_ contents: LibraryContents) throws {}
}

/// App-only settings (how things look and which picker runs), in the same defaults.
@MainActor
@Observable
final class AppSettings {
    enum PickerEngine: String, CaseIterable, Identifiable {
        case system, precise
        var id: String { rawValue }
        var title: String {
            switch self {
            case .system: "System magnifier"
            case .precise: "Dropper loupe"
            }
        }
    }

    enum IconStyle: String, CaseIterable, Identifiable {
        case split, single
        var id: String { rawValue }
        var title: String {
            switch self {
            case .split: "Pick button and panel arrow"
            case .single: "Single icon"
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    var pickerEngine: PickerEngine { didSet { defaults.set(pickerEngine.rawValue, forKey: "pickerEngine") } }
    var iconStyle: IconStyle { didSet { defaults.set(iconStyle.rawValue, forKey: "menuBarIconStyle") } }
    var tintIcon: Bool { didSet { defaults.set(tintIcon, forKey: "tintMenuBarIcon") } }
    var colorVision: ColorVision { didSet { defaults.set(colorVision.rawValue, forKey: "colorVision") } }
    var loupe: LoupeGeometry {
        didSet {
            defaults.set(loupe.sizeStep, forKey: "loupeSize")
            defaults.set(loupe.zoomStep, forKey: "loupeZoom")
        }
    }
    var playSound: Bool { didSet { defaults.set(playSound, forKey: "playSound") } }
    var showDock: Bool { didSet { defaults.set(showDock, forKey: "showColorDock") } }
    var dockPlacement: DockPlacement {
        didSet { defaults.set(try? JSONEncoder().encode(dockPlacement), forKey: "colorDockPlacement") }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        pickerEngine = defaults.string(forKey: "pickerEngine").flatMap(PickerEngine.init(rawValue:)) ?? .system
        iconStyle = defaults.string(forKey: "menuBarIconStyle").flatMap(IconStyle.init(rawValue:)) ?? .split
        tintIcon = defaults.object(forKey: "tintMenuBarIcon") as? Bool ?? true
        colorVision = defaults.string(forKey: "colorVision").flatMap(ColorVision.init(rawValue:)) ?? .normal
        loupe = LoupeGeometry(sizeStep: defaults.object(forKey: "loupeSize") as? Int ?? 1,
                              zoomStep: defaults.object(forKey: "loupeZoom") as? Int ?? 1)
        playSound = defaults.bool(forKey: "playSound")
        showDock = defaults.object(forKey: "showColorDock") as? Bool ?? true
        dockPlacement = defaults.data(forKey: "colorDockPlacement").flatMap { try? JSONDecoder().decode(DockPlacement.self, from: $0) }
            ?? DockPlacement()
    }
}

@MainActor
enum Services {
    static let defaults: UserDefaults = Diagnostics.defaultsSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard

    static func makeModel(settings: AppSettings, precise: ColorSampling) -> DropperModel {
        let sampler: ColorSampling
        if let fake = Diagnostics.fakePicks {
            sampler = FakeColorSampler(fake)
        } else {
            sampler = RoutingSampler(system: SystemColorSampler(), precise: precise, settings: settings,
                                     hasScreenRecording: { Permission.screenRecording.isGranted })
        }
        let store: LibraryStore
        if let dir = Diagnostics.dataDirectory {
            store = FileLibraryStore(directory: dir)
        } else if let dir = try? AppPaths.applicationSupport {
            store = FileLibraryStore(directory: dir)
        } else {
            store = UnavailableLibraryStore()
        }
        return DropperModel(sampler: sampler, clipboard: SystemClipboard(name: Diagnostics.pasteboardName),
                            historyStore: store, preferencesStore: DefaultsPreferences(defaults: defaults))
    }
}
