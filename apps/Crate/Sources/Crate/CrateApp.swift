import AppKit
import CrateCore
import SlopKit
import SwiftUI

// Archetype: drop-in utility window. See docs/design-system.md, 2b.

@main
struct CrateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared
    private let info = AppInfo.current(fallbackName: "Crate")

    var body: some Scene {
        // One window. Closing it quits the app.
        Window("Crate", id: "main") {
            MainView(model: model)
        }
        .defaultSize(width: 560, height: 420)
        .commands { CrateCommands(model: model, info: info) }

        Settings {
            SettingsView(model: model, info: info)
        }
    }
}

struct CrateCommands: Commands {
    @Bindable var model: AppModel
    let info: AppInfo

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Crate") { AboutWindow.show(info: info) }
        }
        CommandGroup(replacing: .newItem) {
            Button("New Archive from Files…") { model.newArchiveFromFiles() }
                .keyboardShortcut("n")
            Button("Open…") { model.chooseFiles() }
                .keyboardShortcut("o")
            Button("Join Split Files…") { model.chooseSplitFilesToJoin() }
                .keyboardShortcut("j", modifiers: [.command, .option])
            Menu("Open Recent") {
                ForEach(model.recents, id: \.self) { url in
                    Button(url.lastPathComponent) { model.open([url], explicit: true, optionHeld: false) }
                }
                if !model.recents.isEmpty { Divider() }
                Button("Clear Menu") { model.clearRecents() }
                    .disabled(model.recents.isEmpty)
            }
        }
        CommandGroup(replacing: .saveItem) {
            Button("Close Archive") { model.closeCurrent() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(!model.canClose)
            Button("Close Window") { WindowCloser.closeFrontmost() }
                .keyboardShortcut("w")
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Find…") { WindowSearch.focus() }
                .keyboardShortcut("f")
                .disabled(model.browse?.isLoaded != true)
        }
        CommandMenu("Archive") {
            let browse = model.browse
            Button(browse?.hasSelection == true ? "Extract Selected Items" : "Extract All") { browse?.extractPrimary() }
                .keyboardShortcut("e")
                .disabled(browse?.canExtract != true)
            Button("Extract To…") { browse?.extractSelectionTo() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(browse?.canExtract != true)
            Button("Open") { browse?.openSelected() }
                .keyboardShortcut(.downArrow)
                .disabled(browse?.canExtract != true || browse?.selection.contains(where: { !$0.isFolder }) != true)
            Button("Quick Look") { browse?.toggleQuickLook() }
                .keyboardShortcut("y")
                .disabled(browse?.canExtract != true || browse?.hasSelection != true)
            Divider()
            Button("Convert…") { browse?.convert() }
                .keyboardShortcut("k")
                .disabled(browse?.canExtract != true || browse?.isShowingResult == true)
            Button("Split…") { splitAction() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(!canSplit)
            Button("Join Parts") { browse?.join() }
                .keyboardShortcut("j")
                .disabled(browse?.canJoin != true)
            Divider()
            Button("Show in Finder") { revealInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!canReveal)
            Button(model.create.map { !$0.isWorking } ?? false ? "Cancel New Archive" : "Stop") { stop() }
                .keyboardShortcut(".")
                .disabled(!isRunning)
            Divider()
            Button("Clear List") { model.clearQueue() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(model.queue.items.isEmpty || model.queue.isBusy)
        }
        HelpCommands(info: info) {
            Button("Crate Help") {
                NSWorkspace.shared.open(Brand.repoURL.appending(path: "tree/main/apps/Crate"))
            }
        }
    }

    private var canSplit: Bool {
        switch model.screen {
        case .browse(let browse): browse.canSplit && !browse.isShowingResult
        case .create(let create): create.canSplitFile && create.page == .review && !create.isDone
        default: false
        }
    }

    private func splitAction() {
        switch model.screen {
        case .browse(let browse): browse.splitting = true
        case .create(let create): create.splittingFile = true
        default: break
        }
    }

    private var canReveal: Bool {
        switch model.screen {
        case .browse(let browse): !browse.isWorking
        case .create(let create): create.isDone
        case .queue: !model.queue.items.isEmpty
        case .empty: false
        }
    }

    private func revealInFinder() {
        switch model.screen {
        case .browse(let browse): browse.revealResult()
        case .create(let create): create.reveal()
        case .queue: model.revealQueueSelection()
        case .empty: break
        }
    }

    private var isRunning: Bool {
        switch model.screen {
        case .browse(let browse): browse.isWorking
        case .create(let create): !create.isDone
        default: model.queue.isBusy
        }
    }

    private func stop() {
        switch model.screen {
        case .browse(let browse):
            if case .loading = browse.phase { model.closeCurrent() } else { browse.cancel() }
        case .create(let create):
            if create.isWorking { create.cancel() } else { model.closeCurrent() }
        default: model.queue.cancelAll()
        }
    }
}

/// ⌘F: focuses the toolbar search field (SwiftUI's `.searchable` has no ⌘F on macOS 14).
@MainActor
enum WindowSearch {
    static func focus() {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        let item = window?.toolbar?.items.lazy.compactMap { $0 as? NSSearchToolbarItem }.first
        item?.beginSearchInteraction()
    }
}

@MainActor
enum WindowCloser {
    static func closeFrontmost() {
        let window = NSApp.keyWindow
            ?? NSApp.orderedWindows.first { $0.isVisible && $0.styleMask.contains(.closable) && !($0 is NSPanel) }
        window?.performClose(nil)
    }
}
