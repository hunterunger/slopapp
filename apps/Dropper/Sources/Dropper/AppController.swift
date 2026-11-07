import AppKit
import DropperCore
import Observation
import SlopKit

extension KeyboardShortcuts.Name {
    /// ⌥⇧C by default ("C" for color). Clear of macOS and the other Slopapp apps (Clips uses
    /// ⌥⇧V). It does take over typing "Ç" on US layouts; the recorder in Settings changes it.
    static let pickColor = Self("pickColor", default: .init(.c, modifiers: [.option, .shift]))
    /// The rest are unset by default.
    static let contrastChecker = Self("contrastChecker")
    static let pickMultiple = Self("pickMultiple")
    static let showPanel = Self("showPanel")
    static let showLibrary = Self("showLibrary")
    static let toggleDock = Self("toggleDock")
}

/// What the Library window shows: which list, and which colors in it.
@MainActor
@Observable
final class LibrarySelection {
    var list: ColorListID? = .history
    var colors: Set<PickedColor.ID> = []
    /// A palette whose name field should take focus (just created).
    var renaming: UUID?
}

/// Runs the app's actions: picking with the HUD, the panel, the windows, files.
@MainActor
@Observable
final class AppController {
    static let shared = AppController()

    let settings: AppSettings
    let model: DropperModel
    let contrast: ContrastState
    let library = LibrarySelection()
    let panelState = PanelState()
    let info = AppInfo.current(fallbackName: "Dropper")
    @ObservationIgnored let precise: PreciseSampler
    @ObservationIgnored private(set) lazy var statusItem = StatusItemController(controller: self)
    @ObservationIgnored private lazy var contrastWindow = ContrastWindowController(controller: self)
    @ObservationIgnored private lazy var libraryWindow = LibraryWindowController(controller: self)
    @ObservationIgnored private(set) lazy var dock = ColorDockController(controller: self)

    private static let hintShownKey = "firstPickHintShown"

    init() {
        let settings = AppSettings(defaults: Services.defaults)
        self.settings = settings
        let precise = PreciseSampler(settings: settings)
        self.precise = precise
        model = Services.makeModel(settings: settings, precise: precise)
        contrast = ContrastState(defaults: Services.defaults)
        precise.describe = { [unowned self] color in model.text(for: color) }
        trackFrontmostApp()
    }

    /// The last app other than Dropper that was in front: per-app formats follow the app
    /// you're working in, even when Dropper's panel took focus to start the pick.
    @ObservationIgnored private var workingApp: NSRunningApplication?

    private func trackFrontmostApp() {
        let own = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != own { workingApp = front }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                                          queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let app, app.processIdentifier != own else { return }
                self?.workingApp = app
            }
        }
        model.frontmostApp = { [weak self] in self?.workingApp?.bundleIdentifier }
    }

    func start() {
        statusItem.install()
        dock.start()
    }

    // MARK: Picking

    /// The main job: loupe → click → value on the clipboard, with a confirmation.
    func pickAndCopy() {
        guard !model.isPicking else { return }
        statusItem.closePanel()
        Diagnostics.record("pick started")
        Task {
            guard let result = await model.pickAndCopy() else {
                Diagnostics.record("pick cancelled")
                return
            }
            Diagnostics.record("picked \(result.text)\(result.wasClamped ? " clamped" : "")")
            showHUD(color: result.color, text: result.text, clamped: result.wasClamped, appFormat: result.appFormat)
        }
    }

    /// Keeps picking until Esc; copies every value, one per line.
    func pickMultiple() {
        guard !model.isPicking else { return }
        statusItem.closePanel()
        Diagnostics.record("multi-pick started")
        Task {
            guard let result = await model.pickMultiple() else {
                Diagnostics.record("multi-pick cancelled")
                return
            }
            Diagnostics.record("multi-picked \(result.count)")
            showHUD(color: result.color, text: result.text, clamped: result.wasClamped, appFormat: result.appFormat)
        }
    }

    /// Two picks (text, background), then the Contrast Checker with that pair.
    func pickContrastPair() {
        guard !model.isPicking else { return }
        statusItem.closePanel()
        Task {
            guard let pair = await model.pickContrastPair() else { return }
            contrast.prepare(history: model.history, options: model.preferences.options)
            contrast.set(pair.text, for: .text, history: model.history, options: model.preferences.options)
            contrast.set(pair.background, for: .background, history: model.history, options: model.preferences.options)
            contrastWindow.show()
        }
    }

    func copy(_ item: PickedColor, as format: ColorFormat? = nil) {
        let text = model.copy(item, as: format)
        showHUD(color: item.color, text: text, clamped: model.isClamped(item.color, as: format))
    }

    private func showHUD(color: ColorValue, text: String, clamped: Bool, appFormat: ColorFormat? = nil) {
        if settings.playSound { NSSound(named: "Pop")?.play() }
        var notes: [String] = []
        if let appFormat { notes.append("\(appFormat.title) for \(workingApp?.localizedName ?? "this app")") }
        if clamped { notes.append("Outside \(model.preferences.options.space.title): copied the closest value") }
        let note = notes.isEmpty ? nil : notes.joined(separator: ". ")
        var hint: String?
        if !Services.defaults.bool(forKey: Self.hintShownKey) {
            Services.defaults.set(true, forKey: Self.hintShownKey)
            hint = "Your colors, palettes and every format are in the Dropper panel in the menu bar."
            if let shortcut = KeyboardShortcuts.getShortcut(for: .pickColor) {
                hint = "Press \(shortcut) to pick from any app. " + (hint ?? "")
            }
        }
        ColorHUD.show(color: color, text: text, note: note, hint: hint)
    }

    // MARK: Windows

    func showContrastChecker() {
        statusItem.closePanel()
        contrast.prepare(history: model.history, options: model.preferences.options)
        contrastWindow.show()
    }

    /// Opens the checker with a saved color in one of its slots.
    func checkContrast(_ color: ColorValue, as slot: ContrastState.Slot) {
        statusItem.closePanel()
        contrast.prepare(history: model.history, options: model.preferences.options)
        contrast.set(color, for: slot, history: model.history, options: model.preferences.options)
        contrastWindow.show()
    }

    func pickForContrast(_ slot: ContrastState.Slot) {
        guard !model.isPicking else { return }
        Task {
            guard let color = await model.pickColor(prompt: slot == .text ? "Pick the text color" : "Pick the background color") else { return }
            contrast.set(color, for: slot, history: model.history, options: model.preferences.options)
            contrastWindow.bringToFront()
        }
    }

    func showLibrary(list: ColorListID? = nil, color: PickedColor.ID? = nil) {
        statusItem.closePanel()
        if let list { library.list = list }
        if let color { library.colors = [color] } else if list != nil { library.colors = [] }
        libraryWindow.show()
    }

    func showSettings() {
        statusItem.closePanel()
        SettingsWindow.open()
    }

    func togglePanel() {
        statusItem.togglePanel()
    }

    // MARK: Palettes

    @discardableResult
    func newPalette(colors: [PickedColor] = []) -> Palette {
        let palette = model.newPalette(colors: colors)
        library.renaming = palette.id
        return palette
    }

    func deletePalette(_ id: UUID) {
        guard let palette = model.palette(id) else { return }
        statusItem.closePanel()
        AppActivation.activate()
        let alert = NSAlert()
        alert.messageText = "Delete “\(palette.name)”?"
        alert.informativeText = palette.colors.isEmpty ? "This palette is empty." :
            "Its \(palette.colors.count == 1 ? "color" : "\(palette.colors.count) colors") will be removed. Colors stay in your history. You can’t undo this."
        alert.alertStyle = .warning
        let delete = alert.addButton(withTitle: "Delete Palette")
        delete.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            model.deletePalette(id)
            if library.list == .palette(id) { library.list = .history }
        }
    }

    func importPalettes() {
        statusItem.closePanel()
        PaletteFiles.chooseAndImport(into: self)
    }

    func exportPalette(_ id: UUID, as format: PaletteFileFormat) {
        statusItem.closePanel()
        guard let palette = model.palette(id) else { return }
        PaletteFiles.export(palette, as: format, controller: self)
    }

    /// The history as a palette (for export).
    var historyAsPalette: Palette {
        Palette(name: "Color History", colors: model.history.items, created: model.history.items.last?.date ?? .now)
    }

    // MARK: History

    func clearHistory() {
        let count = model.history.items.count
        guard count > 0 else { return }
        statusItem.closePanel()
        AppActivation.activate()
        let alert = NSAlert()
        alert.messageText = "Clear color history?"
        alert.informativeText = "This removes \(count == 1 ? "1 color" : "\(count) colors"). Palettes keep their colors. You can’t undo this."
        alert.alertStyle = .warning
        let clear = alert.addButton(withTitle: "Clear History")
        clear.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            model.clearHistory()
        }
    }
}

/// A short prompt near the bottom of the screen ("Pick the text color").
@MainActor
enum PromptHUD {
    static func show(_ text: String) {
        HUD.show(text, systemImage: "eyedropper", duration: .seconds(1.6))
    }
}
