import AppKit
import FocusCore
import SlopKit
import SwiftUI

// Archetype: menu bar utility (docs/design-system.md, section 2a). The status item shows the
// time left; everything else lives in its menu.

extension KeyboardShortcuts.Name {
    /// Start a session, or pause/resume the running one. Unset by default: every obvious
    /// combo is taken by some app, and the menu is one click away.
    static let startPause = Self("startPause")
}

@MainActor
enum AppModel {
    static let controller: FocusController = {
        let storage = FileStorage(directory: TestHooks.dataDirectory)
        let testing = TestHooks.effectsLog != nil || !TestHooks.isInAppBundle
        let notifier: any Notifier = testing ? LogNotifier() : SystemNotifier()
        let sound: any SoundPlayer = testing ? LogSound() : SystemSound()
        let shortcuts: any ShortcutRunner = testing
            ? LogShortcutRunner(names: TestHooks.shortcutNames)
            : CommandShortcutRunner()
        return FocusController(
            storage: storage,
            notifier: notifier,
            sound: sound,
            shortcuts: shortcuts,
            scheduler: TimerScheduler(),
            activity: ProcessActivity(),
            unit: TestHooks.secondsPerMinute,
            reduceMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        )
    }()
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
        if TestHooks.startAtLaunch, controller.isIdle {
            controller.startFocus()
        }
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            FocusMenu(controller: controller, info: info)
        } label: {
            StatusLabel(controller: controller)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            FocusSettingsView(controller: controller, info: info)
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
