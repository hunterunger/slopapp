import Foundation
import Observation

/// Picks a color from the screen. The app uses the system sampler; tests use a fake.
@MainActor
public protocol ColorSampling: AnyObject {
    /// The picked color, or nil if the person cancelled (Esc, switched apps).
    func sample() async -> ColorValue?
}

/// Writes text to the clipboard. Faked in tests.
@MainActor
public protocol Clipboard: AnyObject {
    func write(_ text: String)
}

/// The person's choices. Stored by the app (UserDefaults); faked in tests.
public struct Preferences: Equatable, Codable, Sendable {
    public var format: ColorFormat
    public var options: FormatOptions

    public init(format: ColorFormat = .hex, options: FormatOptions = .standard) {
        self.format = format
        self.options = options
    }
}

public protocol PreferencesStore: Sendable {
    func load() -> Preferences
    func save(_ preferences: Preferences)
}

/// What a finished pick did, for the confirmation HUD.
public struct PickResult: Equatable, Sendable {
    public var color: ColorValue
    public var text: String
    /// The color couldn't be shown exactly in the chosen space, so the value was clamped.
    public var wasClamped: Bool
}

/// Dropper's state and actions, independent of AppKit.
@MainActor
@Observable
public final class DropperModel {
    public private(set) var history: ColorHistory
    public private(set) var isPicking = false
    /// Set when the history file couldn't be read at launch (it was moved aside).
    public private(set) var historyLoadError: String?

    public var preferences: Preferences {
        didSet { if preferences != oldValue { preferencesStore.save(preferences) } }
    }

    private let sampler: ColorSampling
    private let clipboard: Clipboard
    private let historyStore: HistoryStore
    private let preferencesStore: PreferencesStore
    private let now: () -> Date

    public init(sampler: ColorSampling, clipboard: Clipboard, historyStore: HistoryStore,
                preferencesStore: PreferencesStore, now: @escaping () -> Date = Date.init) {
        self.sampler = sampler
        self.clipboard = clipboard
        self.historyStore = historyStore
        self.preferencesStore = preferencesStore
        self.now = now
        preferences = preferencesStore.load()
        do {
            history = ColorHistory(items: try historyStore.load())
        } catch {
            history = ColorHistory()
            historyLoadError = "Couldn’t read saved colors, so history starts fresh."
        }
    }

    // MARK: Formatting

    public func text(for color: ColorValue, as format: ColorFormat? = nil) -> String {
        ColorFormatter.string(color, as: format ?? preferences.format, options: preferences.options)
    }

    /// Whether the value shown for `color` in `format` had to be clamped.
    public func isClamped(_ color: ColorValue, as format: ColorFormat? = nil) -> Bool {
        let format = format ?? preferences.format
        return color.isOutside(format.followsOutputSpace ? preferences.options.space : .displayP3)
    }

    // MARK: Picking

    /// Opens the sampler. Returns the color and adds it to history, or nil if cancelled or a
    /// pick is already running (pressing the shortcut twice never stacks samplers).
    public func pickColor() async -> ColorValue? {
        guard !isPicking else { return nil }
        isPicking = true
        defer { isPicking = false }
        guard let color = await sampler.sample() else { return nil }
        history.add(color, at: now())
        persist()
        return color
    }

    /// The main job: pick, copy in the default format, remember.
    public func pickAndCopy() async -> PickResult? {
        guard let color = await pickColor() else { return nil }
        let text = text(for: color)
        clipboard.write(text)
        return PickResult(color: color, text: text, wasClamped: isClamped(color))
    }

    // MARK: History

    /// Copies a history color and moves it to the top.
    @discardableResult
    public func copy(_ item: PickedColor, as format: ColorFormat? = nil) -> String {
        let text = text(for: item.color, as: format)
        clipboard.write(text)
        history.touch(item.id, at: now())
        persist()
        return text
    }

    /// Adds a color that came from somewhere other than a pick (typed in the contrast checker).
    public func remember(_ color: ColorValue) {
        history.add(color, at: now())
        persist()
    }

    public func clearHistory() {
        history.clear()
        persist()
    }

    public func copyText(_ text: String) {
        clipboard.write(text)
    }

    private func persist() {
        try? historyStore.save(history.items)
    }
}
