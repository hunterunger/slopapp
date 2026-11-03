import __NAME__Core
import SlopKit
import SwiftUI

// Archetype: menu bar utility. See docs/design-system.md, section 2a.

@main
struct __NAME__App: App {
    @NSApplicationDelegateAdaptor(SlopAppDelegate.self) private var appDelegate
    @AppStorage(MenuBarIcon.storageKey) private var showMenuBarIcon = true
    private let info = AppInfo.current(fallbackName: "__NAME__")

    var body: some Scene {
        // SF Symbols are fine here (in-app UI). Never use them in the app icon.
        // Show state with the symbol: outline when idle, .fill when active.
        MenuBarExtra("__NAME__", systemImage: "leaf", isInserted: $showMenuBarIcon) {
            __NAME__Menu()
            MenuFooter(info: info)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SlopSettings(info: info, isMenuBarApp: true)
        }
    }
}

/// Menu order: status line, main actions, options. MenuFooter adds Settings, About, Quit.
struct __NAME__Menu: View {
    var body: some View {
        Text("__NAME__ is under construction.")
    }
}
