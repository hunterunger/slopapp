import AppKit
import SlopKit
import SwiftUI
import TriggersCore

// Archetype: menu bar utility with a library window (the editor). See docs/design-system.md §2.

@main
struct TriggersApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(MenuBarIcon.storageKey) private var showMenuBarIcon = true
    @State private var model = AppModel.shared
    private let info = AppInfo.current(fallbackName: "Triggers")

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            TriggersMenu(model: model, info: info)
        } label: {
            Image(systemName: menuBarSymbol)
                .accessibilityLabel(model.isPaused ? "Triggers, paused" : "Triggers")
        }
        .menuBarExtraStyle(.menu)

        Window("Triggers", id: EditorWindow.id) {
            EditorView(model: model)
        }
        .defaultSize(width: 760, height: 480)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            TriggersCommands(model: model)
            HelpCommands(info: info)
        }

        Settings {
            SettingsView(model: model, info: info)
        }
    }

    private var menuBarSymbol: String {
        if model.isPaused { return "hand.raised.slash" }
        return model.config.enabledBindings.isEmpty ? "hand.tap" : "hand.tap.fill"
    }
}

/// Status line → main actions → options → footer (Settings…, About, Report a Problem…, Quit).
struct TriggersMenu: View {
    @Bindable var model: AppModel
    let info: AppInfo

    var body: some View {
        Text(model.statusLine)
        if !model.isTrusted && model.needsAccessibility {
            Button("Allow Accessibility Access…") { model.openAccessibilitySettings() }
        }
        if model.tapGaveUp {
            Button("Mouse Buttons Stopped: Try Again") { model.retryTap() }
        }
        Divider()
        Button("Edit Triggers…") { EditorWindow.show() }
            .keyboardShortcut("e")
        Toggle("Pause Triggers", isOn: $model.isPaused)
            .keyboardShortcut("p")
        if let app = model.menuTargetApp, let bundleID = app.bundleID {
            Toggle("Turn Off in \(app.name)", isOn: Binding(
                get: { !model.usesAllAppsTriggers(in: bundleID) },
                set: { model.setUsesAllAppsTriggers(!$0, in: bundleID, name: app.name, undo: nil) }
            ))
        }
        if !model.recent.entries.isEmpty {
            Menu("Recent") {
                ForEach(model.recent.entries.prefix(10)) { entry in
                    Button(recentTitle(entry)) { EditorWindow.show(binding: entry.bindingID) }
                }
            }
        }
        MenuFooter(info: info)
    }

    private func recentTitle(_ entry: RecentLog.Entry) -> String {
        var parts = ["\(KeyDisplay.title(entry.trigger)) → \(KeyDisplay.summary(entry.binding))"]
        if let app = entry.appName { parts.append(app) }
        parts.append(RelativeAge.describe(entry.date, now: Date()))
        return parts.joined(separator: " · ")
    }
}

/// The editor window's menu commands: File, Edit (Delete) and Trigger.
struct TriggersCommands: Commands {
    @Bindable var model: AppModel
    @FocusedValue(\.editorUndo) private var undo

    var body: some Commands {
        MainWindowCommands(title: "Triggers", id: EditorWindow.id)
        CommandGroup(replacing: .newItem) {
            Button("New Trigger") { EditorWindow.show(); model.beginNew() }
                .keyboardShortcut("n")
            Button("Add App…") { EditorWindow.show(); EditorWindow.requestAddApp() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Duplicate") { model.duplicate(model.selectedBindings, undo: undo) }
                .keyboardShortcut("d")
                .disabled(model.selectedBindings.isEmpty)
            Divider()
            Button("Import…") { model.importFile(undo: undo) }
            Button("Export…") { model.export() }
                .disabled(model.config.bindings.isEmpty)
        }
        // Delete is the standard Edit › Delete (the table's `onDeleteCommand`): a plain ⌫ key
        // equivalent here would take Backspace away from the search field.
        CommandMenu("Trigger") {
            Button(toggleTitle) { model.toggle(model.selectedBindings, undo: undo) }
                .keyboardShortcut("t")
                .disabled(model.selectedBindings.isEmpty)
            Button("Edit Trigger…") { if let id = model.selectedBindings.first { model.beginEdit(id) } }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(model.selectedBindings.count != 1)
            Button("Run Action Now") { if let id = model.selectedBindings.first { model.runNow(id) } }
                .keyboardShortcut("r")
                .disabled(model.selectedBindings.count != 1)
            Divider()
            Toggle("Pause Triggers", isOn: $model.isPaused)
                .keyboardShortcut("p", modifiers: [.command, .shift])
        }
    }

    private var toggleTitle: String {
        let selected = model.config.bindings.filter { model.selectedBindings.contains($0.id) }
        return !selected.isEmpty && selected.allSatisfy(\.isEnabled) ? "Turn Off" : "Turn On"
    }
}

/// The editor window's undo manager, for menu commands.
struct EditorUndoKey: FocusedValueKey { typealias Value = UndoManager }

extension FocusedValues {
    var editorUndo: UndoManager? {
        get { self[EditorUndoKey.self] }
        set { self[EditorUndoKey.self] = newValue }
    }
}

/// Opens the editor from anywhere (status menu, reopen, test hooks).
@MainActor
enum EditorWindow {
    static let id = "editor"
    static var addAppRequest: (() -> Void)?

    static func show(binding: UUID? = nil) {
        if Diagnostics.quiet {
            MainWindow.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { MainWindow.window?.orderBack(nil) }
        } else {
            AppActivation.activate()
            MainWindow.show()
        }
        if let binding, let found = AppModel.shared.binding(binding) {
            AppModel.shared.selection = SidebarItem(found.scope)
            AppModel.shared.selectedBindings = [binding]
        }
    }

    static func requestAddApp() {
        DispatchQueue.main.async { addAppRequest?() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let standard = SlopAppDelegate()

    func applicationWillFinishLaunching(_ notification: Notification) {
        standard.applicationWillFinishLaunching(notification)
        standard.opensSettingsOnReopen = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel.shared
        model.start()
        AppPresence.start()
        GlobalShortcuts.install(model: model)
        if Diagnostics.testHooks { TestHooks.install(model: model) }
        if let replay = Diagnostics.replayFile { TestHooks.replay(file: replay, model: model) }
        if Snapshots.runIfAsked(model: model) { return }
        let firstRun = !model.settings.didShowFirstRun && !Diagnostics.isSmokeTest
        if firstRun || Diagnostics.opensEditor {
            model.settings.didShowFirstRun = true
            DispatchQueue.main.async { EditorWindow.show() }
        }
        if let tab = Diagnostics.initialSettingsTab {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { SettingsNavigation.open(tab) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                AppModel.shared.checkTrust()
                AppModel.shared.engine.apply()
            }
        }
    }

    /// Opening Triggers again shows the editor (and brings back a hidden menu bar icon).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        _ = standard.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
        if !flag { EditorWindow.show() }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppModel.shared.checkTrust()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// The hyper key's remap must not outlive Triggers.
    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.engine.shutDown()
    }
}

/// A menu bar app that shows in the Dock and gets a menu bar while its editor or Settings is
/// open, so every command is reachable from the app's menus (Snapper's pattern).
@MainActor
enum AppPresence {
    static func start() {
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { update() } }
            }
        }
    }

    static var hasRegularWindow: Bool {
        NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) && $0.level == .normal && !($0 is NSPanel) }
    }

    static func update() {
        let wanted: NSApplication.ActivationPolicy = hasRegularWindow ? .regular : .accessory
        guard NSApp.activationPolicy() != wanted else { return }
        NSApp.setActivationPolicy(wanted)
        if wanted == .regular, !Diagnostics.quiet { NSApp.activate() }
    }
}
