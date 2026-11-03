import AppKit
import DropperCore
import Observation
import SlopKit

extension KeyboardShortcuts.Name {
    /// ⌥⇧C by default ("C" for color). Clear of macOS and the other Slopapp apps (Clips uses
    /// ⌥⇧V). It does take over typing "Ç" on US layouts; the recorder in Settings changes it.
    static let pickColor = Self("pickColor", default: .init(.c, modifiers: [.option, .shift]))
    /// Unset by default.
    static let contrastChecker = Self("contrastChecker")
}

/// Runs the app's actions: picking with the HUD, the contrast window, first-use hints.
@MainActor
@Observable
final class AppController {
    static let shared = AppController()

    let model: DropperModel
    let contrast: ContrastState
    @ObservationIgnored private lazy var contrastWindow = ContrastWindowController(controller: self)

    private static let hintShownKey = "firstPickHintShown"

    init(model: DropperModel = Services.makeModel()) {
        self.model = model
        contrast = ContrastState(defaults: Services.defaults)
    }

    /// The main job: loupe → click → value on the clipboard, with a confirmation.
    func pickAndCopy() {
        guard !model.isPicking else { return }
        Diagnostics.record("pick started")
        Task {
            guard let result = await model.pickAndCopy() else {
                Diagnostics.record("pick cancelled")
                return
            }
            Diagnostics.record("picked \(result.text)\(result.wasClamped ? " clamped" : "")")
            showHUD(color: result.color, text: result.text, clamped: result.wasClamped)
        }
    }

    func copy(_ item: PickedColor, as format: ColorFormat? = nil) {
        let text = model.copy(item, as: format)
        showHUD(color: item.color, text: text, clamped: model.isClamped(item.color, as: format))
    }

    private func showHUD(color: ColorValue, text: String, clamped: Bool) {
        let note = clamped ? "Outside \(model.preferences.options.space.title): copied the closest value" : nil
        var hint: String?
        if !Services.defaults.bool(forKey: Self.hintShownKey) {
            Services.defaults.set(true, forKey: Self.hintShownKey)
            hint = "Other formats and recent colors are in the Dropper menu in the menu bar."
            if let shortcut = KeyboardShortcuts.getShortcut(for: .pickColor) {
                hint = "Press \(shortcut) to pick from any app. " + (hint ?? "")
            }
        }
        ColorHUD.show(color: color, text: text, note: note, hint: hint)
    }

    // MARK: Contrast

    func showContrastChecker() {
        contrast.prepare(history: model.history, options: model.preferences.options)
        contrastWindow.show()
    }

    func pickForContrast(_ slot: ContrastState.Slot) {
        guard !model.isPicking else { return }
        Task {
            guard let color = await model.pickColor() else { return }
            contrast.set(color, for: slot, history: model.history, options: model.preferences.options)
            contrastWindow.bringToFront()
        }
    }

    // MARK: History

    func clearHistory() {
        let count = model.history.items.count
        guard count > 0 else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Clear color history?"
        alert.informativeText = "This removes \(count == 1 ? "1 color" : "\(count) colors"). You can’t undo this."
        alert.alertStyle = .warning
        let clear = alert.addButton(withTitle: "Clear History")
        clear.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            model.clearHistory()
        }
    }
}
