import AppKit
import FocusCore
import SlopKit
import SwiftUI

// Archetype: menu bar utility (docs/design-system.md, section 2a) with a main window (2c-ish).
// The status item shows the time left; its panel has the dial and controls. The main window
// (timer + notes/timeline, and Stats) opens on demand, like the original's window.

extension KeyboardShortcuts.Name {
    /// Start a session, or pause/resume the running one. Unset by default: every obvious
    /// combo is taken by some app, and the menu is one click away.
    static let startPause = Self("startPause")
    /// Bring up the Focus window. Unset by default.
    static let showWindow = Self("showWindow")
}

@MainActor
enum AppModel {
    static let controller: FocusController = {
        let storage = FileStorage(directory: TestHooks.dataDirectory)
        TestHooks.seedSampleHistoryIfAsked(into: storage)
        let testing = TestHooks.effectsLog != nil || !TestHooks.isInAppBundle
        let notifier: any Notifier = testing ? LogNotifier() : SystemNotifier()
        let sound: any SoundPlayer = testing ? LogSound() : SystemSound()
        let shortcuts: any ShortcutRunner = testing
            ? LogShortcutRunner(names: TestHooks.shortcutNames)
            : CommandShortcutRunner()
        let hidesForReal = TestHooks.effectsLog == nil || TestHooks.hideAppsForReal
        return FocusController(
            storage: storage,
            notifier: notifier,
            sound: sound,
            shortcuts: shortcuts,
            scheduler: TimerScheduler(),
            activity: ProcessActivity(),
            blocker: WorkspaceAppHider(performs: hidesForReal),
            unit: TestHooks.secondsPerMinute,
            reduceMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        )
    }()

    /// What's typed in the intention field, shared by the window and the menu bar panel.
    static let intention = IntentionDraft()
    /// The reflection being written, shared by the window, panel and break screen.
    static let reflection = ReflectionDraft()
    static let breakScreen = BreakScreen(controller: controller)
}

@main
struct FocusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(MenuBarIcon.storageKey) private var showMenuBarIcon = true
    @State private var controller = AppModel.controller
    private let info = AppInfo.current(fallbackName: "Focus")

    init() {
        // Created here, before launch finishes, so a notification button that launched
        // the app is still delivered.
        let controller = AppModel.controller
        KeyboardShortcuts.onKeyUp(for: .startPause) {
            MainActor.assumeIsolated { controller.primaryAction() }
        }
        KeyboardShortcuts.onKeyUp(for: .showWindow) {
            MainActor.assumeIsolated { FocusWindow.show() }
        }
        if TestHooks.startAtLaunch, controller.isIdle {
            controller.startFocus()
        }
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuPanel(controller: controller, intention: AppModel.intention, reflection: AppModel.reflection, info: info)
                .onAppear {
                    // Opening the panel: exact numbers, and notice a permission change.
                    controller.refresh()
                    Task { await controller.refreshPermission() }
                }
        } label: {
            StatusLabel(controller: controller)
        }
        .menuBarExtraStyle(.window)

        Settings {
            FocusSettingsView(controller: controller, info: info)
        }
        .commands {
            FocusCommands(controller: controller)
            HelpCommands(info: info)
        }
    }
}

/// Its own view, so a tick that changes the text re-renders only this, not the whole scene.
struct StatusLabel: View {
    let controller: FocusController

    var body: some View {
        Image(nsImage: StatusImage.make(StatusImage.symbol(for: controller), text: controller.menuBarText))
            .accessibilityLabel(controller.accessibilityLabel)
    }
}
