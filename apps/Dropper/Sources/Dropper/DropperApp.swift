import AppKit
import DropperCore
import SlopKit
import SwiftUI

// Archetype: menu bar utility with a rich panel (docs/design-system.md 2a), plus the
// Library window, the Contrast Checker and the precise loupe overlay. The parity pass
// (docs/parity-pass.md) follows the original's layout: split status icon, a panel with a
// toolbar, format selector, history and palettes, and a bottom bar.

@main
struct DropperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var controller = AppController.shared

    var body: some Scene {
        // Never inserted: the real status item is StatusItemController's (it needs a split
        // click and a panel that opens from code). Without a non-window scene first, SwiftUI
        // would open Settings at launch.
        MenuBarExtra("Dropper", systemImage: "eyedropper", isInserted: .constant(false)) {
            EmptyView()
        }

        Settings {
            SettingsView(controller: controller, model: controller.model, settings: controller.settings)
        }
        .commands { DropperCommands(controller: controller) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let standard = SlopAppDelegate()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Settings always opens on General (SwiftUI would restore the last tab).
        UserDefaults.standard.removeObject(forKey: "com_apple_SwiftUI_Settings_selectedTabIndex")
        switch Diagnostics.forcedAppearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = AppController.shared
        controller.start()
        KeyboardShortcuts.onKeyDown(for: .pickColor) { controller.pickAndCopy() }
        KeyboardShortcuts.onKeyDown(for: .pickMultiple) { controller.pickMultiple() }
        KeyboardShortcuts.onKeyDown(for: .contrastChecker) { controller.showContrastChecker() }
        KeyboardShortcuts.onKeyDown(for: .showPanel) { controller.togglePanel() }
        KeyboardShortcuts.onKeyDown(for: .showLibrary) { controller.showLibrary() }
        KeyboardShortcuts.onKeyDown(for: .toggleDock) { controller.dock.toggle() }
        TestScene.showIfRequested()
        SnapshotRenderer.renderIfRequested(controller)
        if Diagnostics.testHooks { installTestHooks(controller) }
    }

    private func installTestHooks(_ controller: AppController) {
        let center = DistributedNotificationCenter.default()
        let prefix = "app.slopapp.dropper.test."
        let actions: [String: @MainActor (String?) -> Void] = [
            "pick": { _ in controller.pickAndCopy() },
            "multi": { _ in controller.pickMultiple() },
            "pair": { _ in controller.pickContrastPair() },
            "contrast": { _ in controller.showContrastChecker() },
            "panel": { _ in controller.togglePanel() },
            "library": { _ in controller.showLibrary() },
            "dock": { _ in controller.dock.toggle() },
            "export": { raw in
                let format = raw.flatMap(PaletteFileFormat.init(rawValue:)) ?? .json
                let palette = controller.model.palettes.first ?? controller.historyAsPalette
                PaletteFiles.export(palette, as: format, controller: controller)
            },
            "import": { path in if let path { PaletteFiles.importFiles([URL(fileURLWithPath: path)], into: controller) } },
            "jump": { slot in controller.precise.testJump(to: Int(slot ?? "0") ?? 0) },
        ]
        for (name, action) in actions {
            center.addObserver(forName: .init(prefix + name), object: nil, queue: .main) { note in
                let object = note.object as? String
                MainActor.assumeIsolated { action(object) }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        standard.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        standard.applicationDidBecomeActive(notification)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
