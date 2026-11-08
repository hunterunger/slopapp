import AppKit
import SlopKit
import SwiftUI
import ZonesCore

// Archetype: menu bar utility with a rich panel (docs/design-system.md, section 2a). The
// panel is an NSPopover under an NSStatusItem rather than a `MenuBarExtra` so it can open
// from a global shortcut, show a clock beside the icon, and reset to "now" on close.

extension KeyboardShortcuts.Name {
    /// Opens the panel from anywhere. Unset by default: every obvious combo is taken by
    /// some app, and the icon is one click away.
    static let togglePanel = Self("togglePanel")
}

@main
struct ZonesApp: App {
    @NSApplicationDelegateAdaptor(SlopAppDelegate.self) private var appDelegate
    @State private var controller = AppController.shared

    init() {
        // The status item needs a running NSApplication.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { AppController.shared.start() }
        }
    }

    var body: some Scene {
        // Never inserted: the real status item is AppController's. Without a non-window
        // scene first, SwiftUI opens Settings at launch as the app's "main" window.
        MenuBarExtra("Zones", systemImage: "globe", isInserted: .constant(false)) {
            EmptyView()
        }

        Settings {
            ZonesSettingsView(model: controller.model, panel: controller.panel, info: controller.info)
        }
        .commands { HelpCommands(info: controller.info) }
    }
}
