import Foundation
import Observation

/// Picks a color from the screen. The app uses the system sampler or its own precise
/// loupe; tests use a fake.
@MainActor
public protocol ColorSampling: AnyObject {
    /// The picked color, or nil if the person cancelled (Esc, switched apps). `prompt` says
    /// what to pick ("Pick the text color") where the picker can show it.
    func sample(prompt: String?) async -> ColorValue?
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
    /// Formats switched off in Settings › Formats: left out of the format menus.
    public var hiddenFormats: Set<ColorFormat>
    /// Per-app formats: picking while one of these apps is in front copies in its format.
    public var usesAppFormats: Bool
    public var appFormats: [String: ColorFormat]

    public init(format: ColorFormat = .hex, options: FormatOptions = .standard, hiddenFormats: Set<ColorFormat> = [],
                usesAppFormats: Bool = false, appFormats: [String: ColorFormat] = [:]) {
        self.format = format
        self.options = options
        self.hiddenFormats = hiddenFormats
        self.usesAppFormats = usesAppFormats
        self.appFormats = appFormats
    }

    /// Suggested per-app formats, offered when the feature is first turned on.
    public static let suggestedAppFormats: [String: ColorFormat] = [
        "com.apple.dt.Xcode": .swiftUI,
        "com.microsoft.VSCode": .hex,
        "com.google.android.studio": .compose,
    ]

    /// The format for a pick made while `app` (a bundle id) is in front.
    public func format(forApp app: String?) -> ColorFormat {
        guard usesAppFormats, let app, let format = appFormats[app] else { return format }
        return format
    }

    /// The formats offered in menus, in order. Always includes the current copy format.
    public var visibleFormats: [ColorFormat] {
        ColorFormat.allCases.filter { !hiddenFormats.contains($0) || $0 == format }
    }

    public func visible(in group: ColorFormat.Group) -> [ColorFormat] {
        group.formats.filter { !hiddenFormats.contains($0) || $0 == format }
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
    /// How many colors a multi-pick collected (1 for a normal pick).
    public var count: Int = 1
    /// Set when a per-app format was used instead of the copy format.
    public var appFormat: ColorFormat?
}

/// A list of colors: the history or one palette.
public enum ColorListID: Hashable, Sendable {
    case history
    case palette(UUID)
}

/// Dropper's state and actions, independent of AppKit.
@MainActor
@Observable
public final class DropperModel {
    public private(set) var history: ColorHistory
    public private(set) var palettes: [Palette]
    /// The palette new picks also go into (Sip-style "selected palette"), if any.
    public var activePaletteID: UUID? {
        didSet {
            if let id = activePaletteID, !palettes.contains(where: { $0.id == id }) { activePaletteID = nil }
            if activePaletteID != oldValue { persist() }
        }
    }
    public private(set) var isPicking = false
    /// Set when the library file couldn't be read at launch (it was moved aside).
    public private(set) var historyLoadError: String?

    public var preferences: Preferences {
        didSet { if preferences != oldValue { preferencesStore.save(preferences) } }
    }

    public var sampler: ColorSampling
    /// The app the person is working in (bundle id), for per-app formats.
    public var frontmostApp: () -> String? = { nil }
    private let clipboard: Clipboard
    private let store: LibraryStore
    private let preferencesStore: PreferencesStore
    private let now: () -> Date

    public init(sampler: ColorSampling, clipboard: Clipboard, historyStore store: LibraryStore,
                preferencesStore: PreferencesStore, now: @escaping () -> Date = Date.init) {
        self.sampler = sampler
        self.clipboard = clipboard
        self.store = store
        self.preferencesStore = preferencesStore
        self.now = now
        preferences = preferencesStore.load()
        do {
            let contents = try store.load()
            history = ColorHistory(items: contents.history)
            palettes = contents.palettes
            activePaletteID = contents.palettes.contains { $0.id == contents.activePaletteID } ? contents.activePaletteID : nil
        } catch {
            history = ColorHistory()
            palettes = []
            activePaletteID = nil
            historyLoadError = "Couldn’t read saved colors, so Dropper starts fresh. The old file was kept next to the new one."
        }
    }

    // MARK: Formatting

    public func text(for color: ColorValue, as format: ColorFormat? = nil, name: String? = nil) -> String {
        ColorFormatter.string(color, as: format ?? preferences.format, options: preferences.options, name: name)
    }

    /// Whether the value shown for `color` in `format` had to be clamped.
    public func isClamped(_ color: ColorValue, as format: ColorFormat? = nil) -> Bool {
        let format = format ?? preferences.format
        return color.isOutside(format.space(for: preferences.options))
    }

    // MARK: Picking

    /// Opens the picker. Returns the color and adds it to history (and the active palette),
    /// or nil if cancelled or a pick is already running (pressing the shortcut twice never
    /// stacks pickers).
    public func pickColor(prompt: String? = nil) async -> ColorValue? {
        guard !isPicking else { return nil }
        isPicking = true
        defer { isPicking = false }
        guard let color = await sampler.sample(prompt: prompt) else { return nil }
        remember(color)
        return color
    }

    /// The main job: pick, copy in the default format, remember.
    public func pickAndCopy() async -> PickResult? {
        let format = preferences.format(forApp: frontmostApp())
        guard let color = await pickColor() else { return nil }
        let text = text(for: color, as: format)
        clipboard.write(text)
        return PickResult(color: color, text: text, wasClamped: isClamped(color, as: format),
                          appFormat: format == preferences.format ? nil : format)
    }

    /// Picks until the person cancels (Esc). Every color is remembered; the clipboard gets
    /// them all, one per line, in the copy format.
    public func pickMultiple() async -> PickResult? {
        guard !isPicking else { return nil }
        let format = preferences.format(forApp: frontmostApp())
        var picked: [ColorValue] = []
        while true {
            let prompt = picked.isEmpty ? "Pick colors · Esc when done" : "\(picked.count) picked · Esc when done"
            guard let color = await pickColor(prompt: prompt) else { break }
            picked.append(color)
        }
        guard let last = picked.last else { return nil }
        let text = picked.map { self.text(for: $0, as: format) }.joined(separator: "\n")
        clipboard.write(text)
        return PickResult(color: last, text: picked.count == 1 ? text : "\(picked.count) colors",
                          wasClamped: picked.contains { isClamped($0, as: format) }, count: picked.count,
                          appFormat: format == preferences.format ? nil : format)
    }

    /// Two picks in a row: text, then background. Nil if either is cancelled.
    public func pickContrastPair() async -> (text: ColorValue, background: ColorValue)? {
        guard let text = await pickColor(prompt: "Pick the text color"),
              let background = await pickColor(prompt: "Pick the background color") else { return nil }
        return (text, background)
    }

    // MARK: Copying and history

    /// Copies a saved color and, if it's in the history, moves it to the top.
    @discardableResult
    public func copy(_ item: PickedColor, as format: ColorFormat? = nil) -> String {
        let text = text(for: item.color, as: format, name: item.name)
        clipboard.write(text)
        history.touch(item.id, at: now())
        persist()
        return text
    }

    /// Adds a color to the history and, if one is active, the active palette.
    public func remember(_ color: ColorValue) {
        history.add(color, at: now())
        if let id = activePaletteID, let index = palettes.firstIndex(where: { $0.id == id }) {
            palettes[index].add(color, at: now())
        }
        persist()
    }

    public func clearHistory() {
        history.clear()
        persist()
    }

    public func copyText(_ text: String) {
        clipboard.write(text)
    }

    // MARK: Lists

    public func items(in list: ColorListID) -> [PickedColor] {
        switch list {
        case .history: history.items
        case .palette(let id): palette(id)?.colors ?? []
        }
    }

    public func palette(_ id: UUID) -> Palette? {
        palettes.first { $0.id == id }
    }

    public func isLocked(_ list: ColorListID) -> Bool {
        if case .palette(let id) = list { return palette(id)?.isLocked ?? false }
        return false
    }

    /// Saves an edited color (name, note, value). Returns false if refused (locked palette,
    /// or the new color is already in that palette).
    @discardableResult
    public func update(_ item: PickedColor, in list: ColorListID) -> Bool {
        switch list {
        case .history:
            var item = item
            item.modified = now()
            history.update(item)
        case .palette(let id):
            guard let index = palettes.firstIndex(where: { $0.id == id }), palettes[index].update(item, at: now()) else { return false }
        }
        persist()
        return true
    }

    public func remove(_ ids: Set<PickedColor.ID>, from list: ColorListID) {
        switch list {
        case .history:
            for id in ids { history.remove(id) }
        case .palette(let pid):
            guard let index = palettes.firstIndex(where: { $0.id == pid }) else { return }
            palettes[index].remove(ids, at: now())
        }
        persist()
    }

    /// Adds copies of colors to a palette (keeping names). Returns how many were new.
    @discardableResult
    public func add(_ items: [PickedColor], to paletteID: UUID) -> Int {
        guard let index = palettes.firstIndex(where: { $0.id == paletteID }) else { return 0 }
        var added = 0
        for item in items where palettes[index].add(PickedColor(color: item.color, date: now(), name: item.name, note: item.note), at: now()) {
            added += 1
        }
        persist()
        return added
    }

    @discardableResult
    public func add(_ color: ColorValue, to paletteID: UUID) -> Bool {
        add([PickedColor(color: color, date: now())], to: paletteID) == 1
    }

    public func moveColors(in paletteID: UUID, fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard let index = palettes.firstIndex(where: { $0.id == paletteID }) else { return }
        palettes[index].move(fromOffsets: offsets, toOffset: destination, at: now())
        persist()
    }

    // MARK: Palettes

    /// A new palette at the end of the list, named "New Palette" (numbered if taken).
    @discardableResult
    public func newPalette(name: String? = nil, colors: [PickedColor] = []) -> Palette {
        let palette = Palette(name: name ?? uniqueName("New Palette"), colors: colors, created: now())
        palettes.append(palette)
        persist()
        return palette
    }

    func uniqueName(_ base: String) -> String {
        let names = Set(palettes.map(\.name))
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    public func renamePalette(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        edit(id) { $0.name = trimmed }
    }

    public func setNote(_ note: String, forPalette id: UUID) {
        edit(id) { $0.note = note }
    }

    public func setLocked(_ locked: Bool, palette id: UUID) {
        guard let index = palettes.firstIndex(where: { $0.id == id }) else { return }
        palettes[index].isLocked = locked
        palettes[index].modified = now()
        persist()
    }

    /// Locked palettes can't be deleted (unlock first).
    /// Adds a palette to the Color Dock or takes it out (allowed even when locked).
    public func setInDock(_ inDock: Bool, palette id: UUID) {
        guard let index = palettes.firstIndex(where: { $0.id == id }) else { return }
        palettes[index].inDock = inDock
        persist()
    }

    public var dockPalettes: [Palette] { palettes.filter(\.inDock) }

    public func deletePalette(_ id: UUID) {
        guard palette(id)?.isLocked == false else { return }
        palettes.removeAll { $0.id == id }
        if activePaletteID == id { activePaletteID = nil }
        persist()
    }

    @discardableResult
    public func duplicatePalette(_ id: UUID) -> Palette? {
        guard let index = palettes.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = palettes[index].duplicate(at: now())
        copy.name = uniqueName(copy.name)
        palettes.insert(copy, at: index + 1)
        persist()
        return copy
    }

    public func sortPalette(_ id: UUID, by order: Palette.SortOrder) {
        guard let index = palettes.firstIndex(where: { $0.id == id }) else { return }
        palettes[index].sort(by: order, at: now())
        persist()
    }

    public func movePalettes(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let moving = offsets.compactMap { palettes.indices.contains($0) ? palettes[$0] : nil }
        let insertAt = destination - offsets.filter { $0 < destination }.count
        palettes.removeAll { p in moving.contains { $0.id == p.id } }
        palettes.insert(contentsOf: moving, at: min(max(insertAt, 0), palettes.count))
        persist()
    }

    /// Merges `others` into `target` (colors not already there), then deletes `others`.
    /// Returns how many colors moved over.
    @discardableResult
    public func merge(_ others: [UUID], into target: UUID) -> Int {
        guard let t = palettes.firstIndex(where: { $0.id == target }), !palettes[t].isLocked else { return 0 }
        var added = 0
        for id in others where id != target {
            guard let source = palette(id) else { continue }
            added += palettes[t].merge(source, at: now())
        }
        palettes.removeAll { others.contains($0.id) && $0.id != target && !$0.isLocked }
        persist()
        return added
    }

    /// Adds imported palettes at the end (names made unique).
    @discardableResult
    public func importPalettes(_ imported: [Palette]) -> [Palette] {
        var added: [Palette] = []
        for var palette in imported {
            palette.name = uniqueName(palette.name)
            palettes.append(palette)
            added.append(palette)
        }
        persist()
        return added
    }

    private func edit(_ id: UUID, _ change: (inout Palette) -> Void) {
        guard let index = palettes.firstIndex(where: { $0.id == id }), !palettes[index].isLocked else { return }
        change(&palettes[index])
        palettes[index].modified = now()
        persist()
    }

    private func persist() {
        try? store.save(LibraryContents(history: history.items, palettes: palettes, activePaletteID: activePaletteID))
    }
}
