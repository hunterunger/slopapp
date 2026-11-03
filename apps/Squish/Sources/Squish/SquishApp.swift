import AppKit
import SlopKit
import SquishCore
import SwiftUI

// Archetype: drop-in utility window. See docs/design-system.md, 2b.

@main
struct SquishApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared
    private let info = AppInfo.current(fallbackName: "Squish")

    var body: some Scene {
        // One window. Closing it quits the app.
        Window("Squish", id: "main") {
            MainView(model: model)
        }
        .defaultSize(width: 560, height: 440)
        .commands {
            SquishCommands(model: model, info: info)
            MainWindowCommands(title: "Squish")
        }

        Settings {
            SettingsView(model: model, info: info)
        }
    }
}

struct SquishCommands: Commands {
    @Bindable var model: AppModel
    let info: AppInfo

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Squish") { AboutWindow.show(info: info) }
        }
        CommandGroup(replacing: .newItem) {
            Button("Choose Files…") { model.chooseFiles() }
                .keyboardShortcut("o")
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button("Show in Finder") { model.revealTargets() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.queue.items.isEmpty)
            Button("Quick Look") { model.toggleQuickLook() }
                .keyboardShortcut("y")
                .disabled(model.queue.items.isEmpty)
            Divider()
            Button("Redo All with New Settings") { model.redoOutdated() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(model.queue.isBusy || model.outdatedItems.isEmpty)
            Button("Compress Again") { model.processAgain() }
                .keyboardShortcut("r")
                .disabled(!model.queue.items.contains(where: \.canRetry))
            Button("Stop") { model.queue.cancelAll() }
                .keyboardShortcut(".")
                .disabled(!model.queue.isBusy)
            Button("Remove from List") { model.removeRows(model.selectedItems) }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(model.selectedItems.isEmpty)
            Button("Put Back Originals…") { model.putBackFromMenu() }
                .disabled(!model.canPutBack)
            Button("Clear List") { model.clearList() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(model.queue.items.isEmpty)
        }
        CommandMenu("Compression") {
            QualityMenuItems(model: model, withShortcuts: true)
            Divider()
            Menu("Size") { SizeMenuItems(model: model) }
            Menu("Format") { FormatMenuItems(model: model) }
            Menu("Save To") { DestinationMenuItems(model: model) }
        }
        CommandGroup(replacing: .saveItem) {
            // Closes the frontmost of our windows (main, Settings, About), even when
            // AppKit hasn't made it key yet.
            Button("Close") { WindowCloser.closeFrontmost() }
                .keyboardShortcut("w")
        }
        CommandGroup(replacing: .help) {
            Button("Squish Help") {
                NSWorkspace.shared.open(Brand.repoURL.appending(path: "tree/main/apps/Squish"))
            }
        }
    }
}

@MainActor
enum WindowCloser {
    static func closeFrontmost() {
        let window = NSApp.keyWindow
            ?? NSApp.orderedWindows.first { $0.isVisible && $0.styleMask.contains(.closable) && !($0 is NSPanel) }
        if let window { CloseConfirmation.shared.close(window) }
    }
}
