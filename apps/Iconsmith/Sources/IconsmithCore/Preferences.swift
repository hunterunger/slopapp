import Foundation

/// What Iconsmith remembers between launches. Picture placement (size, position, fit) is
/// per picture and isn't remembered.
public struct IconsmithPreferences: Codable, Equatable, Sendable {
    public var shape: IconShape = .macOSApp
    public var background: BackgroundMode = .automatic
    public var color: RGBA = .white
    public var format: ExportFormat = .icns
    public var options = ExportOptions()
    public var revealAfterExport = true

    public init() {}

    public init(from decoder: Decoder) throws {
        // Every field optional, so adding one later never resets the rest.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = IconsmithPreferences()
        shape = (try? c.decode(IconShape.self, forKey: .shape)) ?? d.shape
        background = (try? c.decode(BackgroundMode.self, forKey: .background)) ?? d.background
        color = (try? c.decode(RGBA.self, forKey: .color)) ?? d.color
        format = (try? c.decode(ExportFormat.self, forKey: .format)) ?? d.format
        options = (try? c.decode(ExportOptions.self, forKey: .options)) ?? d.options
        revealAfterExport = (try? c.decode(Bool.self, forKey: .revealAfterExport)) ?? d.revealAfterExport
    }
}

public struct PreferencesStore: @unchecked Sendable {
    let defaults: UserDefaults
    let key = "preferences"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> IconsmithPreferences {
        guard let data = defaults.data(forKey: key),
              let prefs = try? JSONDecoder().decode(IconsmithPreferences.self, from: data) else { return IconsmithPreferences() }
        return prefs
    }

    public func save(_ prefs: IconsmithPreferences) {
        if let data = try? JSONEncoder().encode(prefs) { defaults.set(data, forKey: key) }
    }
}
