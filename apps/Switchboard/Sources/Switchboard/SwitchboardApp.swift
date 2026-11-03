import AppKit
import SlopKit
import SwiftUI
import SwitchboardCore

// Archetype: menu bar utility + overlay (the picker). See docs/design-system.md, section 2.

@main
struct SwitchboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(MenuBarIcon.storageKey) private var showMenuBarIcon = true
    @State private var model = AppModel.shared
    private let info = AppInfo.current(fallbackName: "Switchboard")

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            SwitchboardMenu(model: model, info: info)
        } label: {
            Image(systemName: model.isDefaultBrowser ? "signpost.right.fill" : "signpost.right")
                .accessibilityLabel(model.isDefaultBrowser ? "Switchboard" : "Switchboard: not the default browser")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model, info: info)
        }
    }
}

/// Status line → main actions → options → footer (Settings…, About, Quit).
struct SwitchboardMenu: View {
    @Bindable var model: AppModel
    let info: AppInfo

    var body: some View {
        if model.isDefaultBrowser {
            Text("Switchboard is your default browser")
        } else {
            Text("Switchboard isn't your default browser")
            Button("Make Default Browser…") { model.makeDefaultBrowser() }
        }
        Divider()

        Button("Open Link from Clipboard") { openFromClipboard() }
            .keyboardShortcut("v")
        if let last = model.lastDismissedLink {
            Button("Reopen \(LinkText.host(of: last))") {
                model.lastDismissedLink = nil
                LinkRouter.shared.receive(last, forcePicker: true)
            }
            .keyboardShortcut("r")
        }

        if let undo = model.learnedRuleUndo {
            Button("Undo “Always Open \(undo.host)”") { model.undoLearnedRule(undo) }
                .keyboardShortcut("z")
        }

        if model.isDefaultBrowser, !model.installedBrowsers.isEmpty {
            Divider()
            Menu("Stop Being Default Browser") {
                ForEach(model.installedBrowsers, id: \.bundleID) { app in
                    Button("Use \(app.name) Instead…") { model.handBack(to: app) }
                }
            }
        }

        SwitchboardMenuFooter(info: info)
    }

    private func openFromClipboard() {
        let board = NSPasteboard.general
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        guard board.types?.contains(concealed) != true,
              let text = board.string(forType: .string), let url = LinkParser.webLink(in: text)
        else {
            HUD.show("There's no link on the clipboard.", systemImage: "doc.on.clipboard")
            return
        }
        // Always ask: the user chose this on purpose, so let them pick.
        LinkRouter.shared.receive(url, forcePicker: true)
    }
}

/// Settings…, About, Quit. Like SlopKit's `MenuFooter`, but Settings… really comes to the
/// front: a menu bar app isn't active, and macOS 14's cooperative `NSApp.activate()` can be
/// declined, leaving the window inactive behind other apps. (Worth moving into SlopKit.)
struct SwitchboardMenuFooter: View {
    let info: AppInfo
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Divider()
        Button("Settings…") { showSettings() }
            .keyboardShortcut(",")
        Button("About \(info.name)") {
            NSApp.activate(ignoringOtherApps: true)
            AboutWindow.show(info: info)
        }
        Divider()
        Button("Quit \(info.name)") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        // The window may not exist until the next turn of the run loop.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("Settings") == true }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
