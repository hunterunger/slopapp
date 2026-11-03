import AppKit
import ConvertCore
import SlopKit
import SwiftUI

// Archetype: drop-in utility window. See docs/design-system.md, 2b.

@main
struct ConvertApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared
    private let info = AppInfo.current(fallbackName: "Convert")

    var body: some Scene {
        // One window. Closing it quits the app.
        Window("Convert", id: "main") {
            MainView(model: model)
        }
        .defaultSize(width: 760, height: 460)
        .commands { ConvertCommands(model: model, info: info) }

        Settings {
            SettingsView(info: info)
        }
    }
}

struct ConvertCommands: Commands {
    @Bindable var model: AppModel
    let info: AppInfo
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        let _ = model.registerOpenWindow { openWindow(id: "main") }
        CommandGroup(before: .windowList) {
            Button("Convert") { model.showMainWindow() }
                .keyboardShortcut("0")
            Divider()
        }
        CommandGroup(replacing: .appInfo) {
            Button("About Convert") { AboutWindow.show(info: info) }
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
            Button(model.convertAgainTitle) { model.convertAgain() }
                .keyboardShortcut("r")
                .disabled(!model.canConvertAgain)
            Button("Stop All") { model.queue.cancelAll() }
                .keyboardShortcut(".")
                .disabled(!model.queue.isBusy)
            Button("Remove from List") { model.removeFromList(model.selectedItems) }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(model.selectedItems.isEmpty)
            Button("Clear List") { model.clearList() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(model.queue.items.isEmpty)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Close") { WindowCloser.closeFrontmost() }
                .keyboardShortcut("w")
        }
        // Convert has no text to edit: Copy copies converted files, Paste adds copied files.
        CommandGroup(replacing: .pasteboard) {
            Button("Copy") { model.copyOutputs() }
                .keyboardShortcut("c")
                .disabled(!model.canCopy)
            Button("Paste") { model.paste() }
                .keyboardShortcut("v")
            Button("Select All") { model.selectAll() }
                .keyboardShortcut("a")
                .disabled(model.queue.items.isEmpty)
        }
        CommandMenu("Format") {
            Menu("Video") { VideoMenuItems(model: model) }
            Menu("Audio") { AudioMenuItems(model: model) }
            Menu("Image") { ImageMenuItems(model: model) }
            Divider()
            QualityMenuItems(model: model, withShortcuts: true)
            Divider()
            Menu("Size") { SizeMenuItems(model: model) }
            Menu("Save To") { DestinationMenuItems(model: model) }
        }
        CommandGroup(replacing: .help) {
            Button("Convert Help") {
                NSWorkspace.shared.open(Brand.repoURL.appending(path: "tree/main/apps/Convert"))
            }
        }
    }
}

@MainActor
enum WindowCloser {
    static func closeFrontmost() {
        guard let window = NSApp.keyWindow
            ?? NSApp.orderedWindows.first(where: { $0.isVisible && $0.styleMask.contains(.closable) && !($0 is NSPanel) })
        else { return }
        if window.identifier?.rawValue.hasPrefix("main") == true {
            CloseConfirmer.shared.close(window)
        } else {
            window.performClose(nil)
        }
    }
}

/// Files opened with Convert (Open With, the Dock icon, `open -a`), and a confirmation
/// before quitting mid-batch. Wraps SlopKit's standard delegate.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let standard = SlopAppDelegate()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // For screenshots and tests: CONVERT_APPEARANCE=light|dark.
        switch ProcessInfo.processInfo.environment["CONVERT_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    private var escapeMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Esc closes the About window, like other small panels.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  let window = NSApp.keyWindow, window.title.hasPrefix("About ") else { return event }
            window.performClose(nil)
            return nil
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // Finder's Open With, a Dock drop, `open -a`: always into the one window.
        AppModel.shared.showMainWindow()
        AppModel.shared.add(urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // A Dock click with no window open brings the window back.
        if !flag { AppModel.shared.showMainWindow() }
        return standard.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // The main window only closes while busy after "Stop converting and close?", which
        // already stopped everything; never start quitting with work still running.
        !AppModel.shared.queue.isBusy && standard.applicationShouldTerminateAfterLastWindowClosed(sender)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let queue = AppModel.shared.queue
        guard queue.isBusy else { return .terminateNow }
        let alert = NSAlert()
        let remaining = queue.summary.remaining
        alert.messageText = remaining == 1 ? "Stop converting and quit?" : "Stop \(remaining) conversions and quit?"
        alert.informativeText = "Files that haven't finished won't be saved. Your originals aren't affected."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        // Unfinished files live in macOS's temporary-items folder, never next to the
        // originals, so stopping here leaves nothing behind for the user to clean up.
        queue.cancelAll()
        return .terminateNow
    }
}
