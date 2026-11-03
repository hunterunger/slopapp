import AppKit
import SlopKit
import SwiftUI
import TallyCore

// Archetype: a single-window utility (design system 2b), with the window being an editor
// instead of a drop zone. One autosaved sheet; closing the window quits unless a
// show/hide shortcut is set (then Tally stays ready in the background).

@main
struct TallyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = SheetModel.shared
    private let info = AppInfo.current(fallbackName: "Tally")

    var body: some Scene {
        Window("Tally", id: WindowID.main) {
            ContentView(model: model)
        }
        .defaultSize(width: 560, height: 480)
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

struct ContentView: View {
    let model: SheetModel
    @AppStorage(Pref.textSizeStep) private var textSizeStep = TextSize.defaultStep
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SheetEditor(model: model, textSizeStep: textSizeStep)
            .frame(minWidth: 340, minHeight: 220)
            .ignoresSafeArea(.container, edges: .bottom)
            .onAppear {
                model.openSettingsAction = { openSettingsWindow() }
                WindowToggler.openMain = { openWindow(id: WindowID.main) }
            }
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        DispatchQueue.main.async {
            NSApp.windows.first { $0.identifier?.rawValue.contains("Settings") == true }?.makeKeyAndOrderFront(nil)
        }
    }
}

struct TallyCommands: Commands {
    let model: SheetModel
    let info: AppInfo
    @AppStorage(Pref.textSizeStep) private var textSizeStep = TextSize.defaultStep
    @Environment(\.openWindow) private var openWindow

    private func setTextSize(_ step: Int) {
        let clamped = TextSize.clamp(step)
        if clamped == textSizeStep, step != TextSize.defaultStep { NSSound.beep() }
        textSizeStep = clamped
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(info.name)") { AboutWindow.show(info: info) }
        }
        CommandGroup(replacing: .newItem) {
            Button("Import…") { model.importText() }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Close") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w")
            Button("Export…") { model.exportText() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Result") { model.copyCurrentResult() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
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
        }
        CommandGroup(replacing: .help) {
            // No shortcut: ⇧⌘/ belongs to the system's Help search.
            Button("Tally Syntax Guide") { openWindow(id: WindowID.guide) }
        }
    }
}
