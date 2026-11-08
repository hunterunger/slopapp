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
        .commands { HelpCommands(info: info) }
    }
}

/// Status line → main actions → options → footer (Settings…, About, Report a Problem…, Quit).
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

        MenuFooter(info: info)
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
