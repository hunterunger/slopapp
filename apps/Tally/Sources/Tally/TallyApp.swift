import AppKit
import SlopKit
import SwiftUI
import TallyCore

// Archetype: a library window (design system 2c) shaped like the original: a minimal sheet
// editor with answers on the right, a slim total bar along the bottom and a collapsible
// sidebar of sheets; plus an optional menu bar panel. Closing the window quits unless a
// show/hide shortcut or the menu bar icon keeps Tally around.

@main
struct TallyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = SheetModel.shared
    private let info = AppInfo.current(fallbackName: "Tally")

    var body: some Scene {
        Window("Tally", id: WindowID.main) {
            ContentView(model: model)
        }
        .defaultSize(width: 600, height: 480)
        .windowToolbarStyle(.unifiedCompact(showsTitle: true))
        .commands { TallyCommands(model: model, info: info) }

        Window("Syntax Guide", id: WindowID.guide) {
            SyntaxGuideView()
        }
        .defaultSize(width: 520, height: 620)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(model: model, info: info)
        }
    }
}

enum WindowID {
    static let main = "main"
    static let guide = "guide"
}

struct TallyCommands: Commands {
    let model: SheetModel
    let info: AppInfo
    @AppStorage(Pref.textSizeStep, store: Pref.defaults) private var textSizeStep = TextSize.defaultStep
    @Environment(\.openWindow) private var openWindow

    private func setTextSize(_ step: Int) {
        let clamped = TextSize.clamp(step)
        if clamped == textSizeStep, step != TextSize.defaultStep { NSSound.beep() }
        textSizeStep = clamped
        model.setTextSize(step: clamped)
    }

    var body: some Commands {
        SidebarCommands()
        CommandGroup(replacing: .appInfo) {
            Button("About \(info.name)") { AboutWindow.show(info: info) }
        }
        CommandGroup(replacing: .newItem) {
            Button("New Sheet") {
                WindowToggler.show()
                model.newSheet()
            }
            .keyboardShortcut("n")
            Button("Import…") { model.importText() }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Close") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w")
            Button("Export…") { model.exportText() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button("Delete Sheet…") { model.deleteSheet(model.currentID) }
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Result") { model.copyCurrentResult() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Copy Total") { model.copyTotal() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("Copy All") { model.copyAll() }
                .keyboardShortcut("c", modifiers: [.command, .option])
            Button("Clear All") { model.clearAll() }
                .keyboardShortcut(.delete, modifiers: [.command, .option])
        }
        CommandGroup(after: .textEditing) {
            Menu("Find") {
                Button("Find…") { model.find(.showFindInterface) }
                    .keyboardShortcut("f")
                Button("Find and Replace…") { model.find(.showReplaceInterface) }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                Button("Find Next") { model.find(.nextMatch) }
                    .keyboardShortcut("g")
                Button("Find Previous") { model.find(.previousMatch) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Use Selection for Find") { model.find(.setSearchString) }
                    .keyboardShortcut("e")
            }
        }
        CommandGroup(before: .toolbar) {
            // No .disabled here: @AppStorage in Commands doesn't refresh menu state reliably.
            Button("Bigger") { setTextSize(textSizeStep + 1) }
                .keyboardShortcut("+")
            Button("Smaller") { setTextSize(textSizeStep - 1) }
                .keyboardShortcut("-")
            Button("Actual Size") { setTextSize(TextSize.defaultStep) }
                .keyboardShortcut("0")
            Divider()
            Menu("Theme") {
                ThemeMenuItems(model: model)
            }
            Divider()
        }
        CommandGroup(before: .windowList) {
            Button("Next Sheet") { model.selectNeighbour(1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Sheet") { model.selectNeighbour(-1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Toggle("Float on Top", isOn: Binding(get: { WindowFloat.isOn }, set: { _ in WindowFloat.toggle() }))
            Divider()
        }
        CommandGroup(replacing: .help) {
            // No shortcut: ⇧⌘/ belongs to the system's Help search.
            Button("Tally Syntax Guide") { openWindow(id: WindowID.guide) }
        }
    }
}
