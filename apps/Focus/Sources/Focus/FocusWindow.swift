import AppKit
import FocusCore
import SlopKit
import SwiftUI

/// The main window, hosted with AppKit so it only exists once asked for (it never opens by
/// itself at launch; Focus stays a menu bar app until you open it).
@MainActor
enum FocusWindow {
    private static var window: NSWindow?
    static let state = MainWindowState()
    static let identifier = NSUserInterfaceItemIdentifier("focus-main")
    static let floatKey = "floatOnTop"

    static var isVisible: Bool { window?.isVisible ?? false }

    static func show(_ section: MainSection? = nil) {
        if window == nil {
            let root = MainWindowView(controller: AppModel.controller, state: state,
                                      intention: AppModel.intention, reflection: AppModel.reflection)
            let hosting = NSHostingController(rootView: root)
            hosting.sizingOptions = [.minSize]
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.identifier = identifier
            newWindow.title = AppInfo.current(fallbackName: "Focus").name
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            newWindow.toolbarStyle = .unified
            newWindow.isReleasedWhenClosed = false
            newWindow.setContentSize(NSSize(width: 780, height: 580))
            if !newWindow.setFrameUsingName("FocusMain") { newWindow.center() }
            newWindow.setFrameAutosaveName("FocusMain")
            window = newWindow
            applyFloat()
        }
        if let section { state.section = section }
        AppActivation.activate()
        window?.makeKeyAndOrderFront(nil)
        DockPresence.update()
    }

    static var floatsOnTop: Bool {
        get { UserDefaults.standard.bool(forKey: floatKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: floatKey)
            applyFloat()
        }
    }

    private static func applyFloat() {
        window?.level = floatsOnTop ? .floating : .normal
    }
}

/// Focus is a menu bar app, but while its main window is open it shows in the Dock and gets a
/// menu bar (Timer, View, Window menus with every shortcut), like a regular app.
@MainActor
enum DockPresence {
    private static var observers: [NSObjectProtocol] = []

    static func start() {
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                // After the close finishes, so the closing window no longer counts.
                DispatchQueue.main.async { MainActor.assumeIsolated { update() } }
            })
        }
    }

    static func update() {
        let wanted: NSApplication.ActivationPolicy = FocusWindow.isVisible ? .regular : .accessory
        guard NSApp.activationPolicy() != wanted else { return }
        NSApp.setActivationPolicy(wanted)
        if wanted == .regular { AppActivation.activate() }
    }
}

/// Opens Settings on a tab from anywhere (menu bar panel, category menu, commands).
@MainActor
enum FocusSettingsOpener {
    private static var action: OpenSettingsAction?

    static func register(_ action: OpenSettingsAction) { self.action = action }

    static func open(_ tab: SettingsTab?) {
        if let tab { SettingsTab.select(tab) }
        AppActivation.activate()
        action?()
        SettingsWindow.bringToFront()
    }
}

/// The shared "primary" action: ⌘↩ saves a reflection that's waiting, otherwise starts a
/// session with what's in the intention field.
@MainActor
enum TimerActions {
    static func primary() {
        let controller = AppModel.controller
        if controller.pendingReflection != nil, controller.runningPhase != .focus {
            AppModel.reflection.save(controller)
        } else if controller.isIdle {
            controller.startFocus(intention: AppModel.intention.text)
        } else if controller.state.pendingBreak != nil {
            controller.startBreak()
        }
    }
}

/// The menus while the window is open: Timer, View (Timer ⌘1, Stats ⌘2), File ▸ Export,
/// Window ▸ Focus ⌘0 and Float on Top.
struct FocusCommands: Commands {
    let controller: FocusController
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        let _ = FocusSettingsOpener.register(openSettings)
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .importExport) {
            Button("Export Sessions as CSV…") { Exporter.exportCSV(controller: controller) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }
        CommandMenu("Timer") {
            Button("Start Focus or Save Reflection") { TimerActions.primary() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Pause or Resume") { controller.togglePause() }
                .keyboardShortcut("p")
            Button("Finish Session") { controller.finish() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
            Button("Stop") { controller.stop() }
                .keyboardShortcut(".")
            Button("Skip Break") { controller.skipBreak() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Divider()
            Button("Add \(TimerSettings.minutesAdded) Minutes") {
                controller.isIdle ? controller.updateSettings { $0.focusMinutes += TimerSettings.minutesAdded } : controller.addTime()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            Button("Remove \(TimerSettings.minutesAdded) Minutes") {
                controller.isIdle ? controller.updateSettings { $0.focusMinutes -= TimerSettings.minutesAdded } : controller.removeTime()
            }
            .keyboardShortcut(",", modifiers: [.command, .shift])
            Divider()
            Button("Edit Intention…") { IntentionEditor.ask(controller: controller) }
                .keyboardShortcut("l")
            Button("Edit Categories…") { FocusSettingsOpener.open(.categories) }
        }
        CommandGroup(before: .toolbar) {
            Button("Timer") { FocusWindow.show(.timer) }
                .keyboardShortcut("1")
            Button("Stats") { FocusWindow.show(.stats) }
                .keyboardShortcut("2")
            Divider()
        }
        CommandGroup(before: .windowList) {
            Button("Focus") { FocusWindow.show() }
                .keyboardShortcut("0")
            Button("Float on Top") { FocusWindow.floatsOnTop.toggle() }
            Divider()
        }
    }
}
