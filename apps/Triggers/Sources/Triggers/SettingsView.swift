import SlopKit
import SwiftUI
import TriggersCore

extension KeyboardShortcuts.Name {
    /// No defaults: any combination could collide with someone's own triggers.
    static let togglePause = Self("togglePause")
    static let openEditor = Self("openEditor")
}

/// General (launch at login, menu bar, confirmation, sensitivity), Shortcuts, Advanced, About.
/// Triggers themselves live in the editor, not here.
struct SettingsView: View {
    @Bindable var model: AppModel
    let info: AppInfo

    var body: some View {
        @Bindable var settings = model.settings
        SlopSettings(info: info, isMenuBarApp: true) {
            Toggle(isOn: $settings.showsConfirmation) {
                Text("Show a confirmation when a trigger runs")
                Text("Names the trigger and its action at the bottom of the screen. Handy while you learn your gestures.")
            }
            Toggle(isOn: $settings.hyperKey) {
                Text("Use Caps Lock as a hyper key")
                Text(hyperDetail)
            }
            Picker(selection: $settings.tapSensitivity) {
                Text("Relaxed").tag(GestureTuning.TapSensitivity.relaxed)
                Text("Standard").tag(GestureTuning.TapSensitivity.standard)
                Text("Strict").tag(GestureTuning.TapSensitivity.strict)
            } label: {
                Text("Tap sensitivity")
                Text("Relaxed accepts slower, looser taps. Strict ignores anything that isn't quick and still.")
            }
            Picker(selection: $settings.swipeDistance) {
                Text("Short").tag(GestureTuning.SwipeDistance.short)
                Text("Standard").tag(GestureTuning.SwipeDistance.standard)
                Text("Long").tag(GestureTuning.SwipeDistance.long)
            } label: {
                Text("Swipe distance")
                Text("How far fingers travel before a swipe counts.")
            }
        } shortcuts: {
            ShortcutRow("Pause or resume Triggers", subtitle: "Works from any app.", name: .togglePause)
            ShortcutRow("Edit triggers", subtitle: "Opens the editor.", name: .openEditor)
        } advanced: {
            LabeledContent {
                Button("Export Diagnostics…") { model.exportDiagnostics() }
            } label: {
                Text("Diagnostics")
                Text("Versions, permissions, trackpad frame rate and input timings. No gestures, keys or apps you used.")
            }
            LabeledContent {
                HStack {
                    Button("Import…") { model.importFile(undo: nil) }
                    Button("Export…") { model.export() }
                        .disabled(model.config.bindings.isEmpty)
                }
            } label: {
                Text("Triggers")
                Text("A JSON file you can keep or move to another Mac.")
            }
        }
    }
}

extension SettingsView {
    private var hyperDetail: String {
        _ = model.hyperRevision
        if model.settings.hyperKey {
            if let problem = model.keyboard.hyperProblem { return problem }
            if !model.isTrusted { return "Needs Accessibility access. Until then Caps Lock works as before." }
            if model.isPaused { return "Off while Triggers is paused: Caps Lock works as before." }
        }
        return "Hold Caps Lock for ⌃⌥⇧⌘ (record combinations with it like any other), tap it for Escape. Caps Lock is back as soon as you turn this off, pause or quit Triggers."
    }
}

/// Global shortcuts for Settings › Shortcuts.
@MainActor
enum GlobalShortcuts {
    static func install(model: AppModel) {
        guard !Diagnostics.noInput else { return }
        KeyboardShortcuts.onKeyUp(for: .togglePause) { model.isPaused.toggle() }
        KeyboardShortcuts.onKeyUp(for: .openEditor) { EditorWindow.show() }
    }
}

/// Opens Settings (test hooks and `TRIGGERS_SETTINGS_TAB`).
@MainActor
enum SettingsNavigation {
    static func open(_ tab: String) {
        if Diagnostics.quiet {
            SettingsWindow.open()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { SettingsWindow.window?.orderBack(nil) }
        } else {
            SettingsWindow.open()
        }
        let titles = ["general": "General", "shortcuts": "Shortcuts", "advanced": "Advanced", "about": "About"]
        guard let title = titles[tab], tab != "general" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let toolbar = SettingsWindow.window?.toolbar,
                  let item = toolbar.items.first(where: { $0.label == title }) else { return }
            toolbar.selectedItemIdentifier = item.itemIdentifier
            if let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
        }
    }
}
