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
        // One window, in three columns. Closing it quits the app.
        Window("Squish", id: "main") {
            MainView(model: model)
        }
        .defaultSize(width: 1080, height: 660)
        .commands {
            SquishCommands(model: model, info: info)
            SidebarCommands()
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
            Button("Copy Compressed File") { model.copyCompressed() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(!model.queue.items.contains { $0.output != nil })
            Divider()
            Button("Apply Settings to All") { model.redoOutdated() }
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
        CommandGroup(before: .sidebar) {
            Toggle("Compare Before and After", isOn: $model.comparing)
                .keyboardShortcut("k")
                .disabled(model.queue.items.isEmpty)
            Divider()
            Button("Zoom In") { model.preview.zoomIn() }
                .keyboardShortcut("+")
                .disabled(!model.preview.canZoom)
            Button("Zoom Out") { model.preview.zoomOut() }
                .keyboardShortcut("-")
                .disabled(!model.preview.canZoom)
            Button("Zoom to Fit") { model.preview.zoomToFit() }
                .keyboardShortcut("9")
                .disabled(!model.preview.canZoom)
            Button("Actual Size") { model.preview.actualSize() }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .disabled(!model.preview.canZoom)
            Divider()
            Button("Previous Page") { NotificationCenter.default.post(name: .squishPreviewPage, object: -1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Next Page") { NotificationCenter.default.post(name: .squishPreviewPage, object: 1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Divider()
        }
        CommandGroup(after: .sidebar) {
            Toggle("Show Options", isOn: $model.showsOptions)
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
        CommandMenu("Compression") {
            PresetMenuItems(model: model, withShortcuts: true)
        }
        CommandGroup(replacing: .saveItem) {
            // Closes the frontmost of our windows (main, Settings, About), even when
            // AppKit hasn't made it key yet.
            Button("Close") { WindowCloser.closeFrontmost() }
                .keyboardShortcut("w")
        }
        HelpCommands(info: info) {
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
