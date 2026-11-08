import AppKit
import GaugeCore
import SlopKit
import SwiftUI

// Archetype: menu bar utility with a rich panel (docs/design-system.md, section 2a). The
// status item is AppKit (one template image, redrawn only when it matters) and the panel is a
// FloatingPanel under it, because a MenuBarExtra can't keep its label this cheap or open from
// a global shortcut.

extension KeyboardShortcuts.Name {
    /// Opens the panel from anywhere. Unset by default: it's the way in when the menu bar is
    /// too full to show Gauge, and every obvious combination is taken by some app.
    static let togglePanel = Self("togglePanel")
}

@main
struct GaugeApp: App {
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
        // Never inserted: the real status item is AppController's. Without a non-window scene
        // first, SwiftUI opens Settings at launch as the app's "main" window.
        MenuBarExtra("Gauge", systemImage: "gauge.with.dots.needle.33percent", isInserted: .constant(false)) {
            EmptyView()
        }

        Settings {
            GaugeSettingsView(store: controller.store, info: controller.info, hasBattery: controller.hasBattery)
        }
    }
}
