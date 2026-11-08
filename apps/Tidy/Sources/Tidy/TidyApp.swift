import SlopKit
import SwiftUI
import TidyCore

// Archetype: library window (docs/design-system.md, 2c), laid out like the cleaner it replaces:
// a sidebar of modules (Smart Scan, Cleanup, Maintenance, Applications, Large & Old, Space
// Map), each with an intro, a scan, result tiles and a review list. Everything is reviewed and
// moved to the Trash; the only permanent delete is emptying the Trash, which always asks.

@main
struct TidyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared
    private let info = AppInfo.current(fallbackName: "Tidy")

    var body: some Scene {
        Window("Tidy", id: "main") {
            MainView(model: model)
        }
        .defaultSize(width: 1040, height: 660)
        .windowToolbarStyle(.unified)
        .commands { TidyCommands(model: model, info: info) }

        Settings {
            SettingsView(model: model, info: info)
        }
    }
}

struct TidyCommands: Commands {
    @Bindable var model: AppModel
    let info: AppInfo
    @Environment(\.openWindow) private var openWindow

    private var scanTitle: String {
        switch model.section {
        case .uninstall, .leftovers: "Scan Again"
        case .spaceLens: model.space.hasMap ? "Rescan" : "Scan"
        default: "Scan"
        }
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Tidy") { AboutWindow.show(info: info) }
        }
        CommandGroup(replacing: .newItem) {
            Button("Choose App…") { model.chooseApp() }
                .keyboardShortcut("o")
            // Follows the section: map a folder in Space Map, look for large files elsewhere.
            Button(model.section == .spaceLens ? "Map Folder…" : "Choose Folder for Large Files…") {
                if model.section == .spaceLens { model.chooseSpaceFolder() } else { model.chooseLargeFolder() }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(model.isModalUp)
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button("Move to Trash") {
                // ⌘⌫ while typing deletes to the start of the line, as in every text field.
                if TextEditing.forward(#selector(NSStandardKeyBindingResponding.deleteToBeginningOfLine(_:))) { return }
                model.moveCheckedToTrash(.menuCommand)
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled((!model.canMoveToTrash || model.isModalUp) && !model.isEditingText)
            Button("Recently Moved to Trash…") { model.showingHistory = true }
                .disabled(model.history.isEmpty || model.isModalUp)
            Divider()
            Button("Show in Finder") { model.revealSelection() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.selectedURLs.isEmpty)
            Button("Quick Look") { model.quickLookSelection() }
                .keyboardShortcut("y")
                .disabled(model.selectedURLs.isEmpty)
            Button("Get Info") { model.mapGetInfo() }
                .keyboardShortcut("i")
                .disabled(!model.mapHasSingleSelection || model.isModalUp)
            Button("Copy Path") { model.copyMapPaths(model.space.selection) }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(model.section != .spaceLens || model.selectedURLs.isEmpty)
            Divider()
            Button(scanTitle) { model.rescan() }
                .keyboardShortcut("r")
                .disabled(model.isModalUp)
            Button("Rescan This Folder") { model.space.rescanCurrentFolder() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(!model.mapIsBrowsable || model.space.isScanning || model.isModalUp)
            Button("Empty Trash…") { model.emptyTrashCommand() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(model.isModalUp)
        }
        CommandGroup(replacing: .undoRedo) {
            // While typing, Undo and Redo belong to the text.
            Button(model.isEditingText || model.undoableEntry == nil ? "Undo" : "Undo Move to Trash") {
                if TextEditing.forward(Selector(("undo:"))) { return }
                model.undo()
            }
            .keyboardShortcut("z")
            .disabled(!model.isEditingText && (model.undoableEntry == nil || model.isModalUp))
            Button(model.isEditingText || model.redoableEntry == nil ? "Redo" : "Redo Move to Trash") {
                if TextEditing.forward(Selector(("redo:"))) { return }
                model.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!model.isEditingText && (model.redoableEntry == nil || model.isModalUp))
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Find") { TextEditing.focusSearchField() }
                .keyboardShortcut("f")
                .disabled(model.isModalUp)
        }
        CommandGroup(before: .sidebar) {
            // Space Map navigation.
            Button("Open") { model.mapOpenSelection() }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(!model.mapCanOpenSelection)
            Button("Enclosing Folder") { model.space.goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(!model.mapIsBrowsable || !model.space.canGoUp)
            Button("Back") { model.space.back() }
                .keyboardShortcut("[")
                .disabled(!model.mapIsBrowsable || model.space.backStack.isEmpty)
            Button("Forward") { model.space.forward() }
                .keyboardShortcut("]")
                .disabled(!model.mapIsBrowsable || model.space.forwardStack.isEmpty)
            Button("Show Package Contents") { model.mapShowPackageContents() }
                .disabled(model.mapSelectedPackage == nil || model.space.isScanning)
            Button("Show Checked Items") { model.space.showingTray = true }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(!model.mapIsBrowsable || model.space.tray.isEmpty)
            Divider()
            ForEach(Array(SidebarSection.sidebar.enumerated()), id: \.element) { index, section in
                Button(section.title) { model.section = section }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                    .disabled(model.isModalUp)
            }
            Divider()
            Menu("Sort Apps By") {
                ForEach(AppSort.allCases.filter { $0 != .lastOpened || model.canSortByLastOpened }) { sort in
                    Toggle(sort.title, isOn: Binding(get: { model.appSort == sort }, set: { if $0 { model.appSort = sort } }))
                }
            }
            Divider()
        }
        CommandGroup(before: .windowList) {
            // Tidy is a single-window utility: closing the window quits (SlopAppDelegate).
            Button("Tidy") { openWindow(id: "main") }
                .keyboardShortcut("0")
            Divider()
        }
        HelpCommands(info: info) {
            Button("Tidy Help") {
                NSWorkspace.shared.open(Brand.repoURL.appendingPathComponent("tree/main/apps/Tidy"))
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let standard = SlopAppDelegate()

    func applicationWillFinishLaunching(_ notification: Notification) {
        switch ProcessInfo.processInfo.environment["TIDY_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()
        SnapshotScript.runIfRequested(AppModel.shared)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // A non-app is passed on too, so Tidy can say why it's ignored.
        if let url = urls.first(where: { $0.pathExtension.lowercased() == "app" }) ?? urls.first {
            AppModel.shared.open(appAt: url)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppModel.shared.refreshAccess()
        AppModel.shared.running.refresh()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        standard.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        standard.applicationShouldTerminateAfterLastWindowClosed(sender)
    }
}

/// Keeps text fields' own editing shortcuts (⌘⌫, ⌘Z) working when a menu item shares them.
@MainActor
enum TextEditing {
    /// A text field or text view is being edited in the key window.
    static var isActive: Bool { NSApp.keyWindow?.firstResponder is NSText }

    /// Puts the cursor in the toolbar's search field (Edit ▸ Find).
    static func focusSearchField() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) else { return }
        let roots = [window.contentView?.superview].compactMap { $0 }
        for root in roots {
            if let field = searchField(in: root) {
                window.makeFirstResponder(field)
                return
            }
        }
    }

    private static func searchField(in view: NSView) -> NSSearchField? {
        if let field = view as? NSSearchField { return field }
        for child in view.subviews {
            if let field = searchField(in: child) { return field }
        }
        return nil
    }

    /// Sends `action` to the text being edited. Returns false if nothing is being edited.
    static func forward(_ action: Selector) -> Bool {
        guard ReviewRules.routesToTextField(isEditingText: isActive),
              let text = NSApp.keyWindow?.firstResponder as? NSText else { return false }
        return NSApp.sendAction(action, to: text, from: nil)
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    let info: AppInfo

    var body: some View {
        SlopSettings(info: info, isMenuBarApp: false) {
            // Each explanation sits under its own label (the form's subtitle style), not in a
            // row of its own.
            LabeledContent {
                if model.hasFullDiskAccess {
                    Label("On", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.textGreen)
                } else {
                    Button("Open System Settings") { Permission.fullDiskAccess.request() }
                }
            } label: {
                Text("Full Disk Access")
                Text("Lets Tidy measure and move protected app data, and look in Desktop, Documents and Downloads.")
            }
            Toggle(isOn: Binding(get: { model.smart.includeTrash }, set: { model.smart.includeTrash = $0 })) {
                Text("Smart Scan empties the Trash")
                Text("Off by default. Emptying the Trash erases for good, so Tidy always asks first.")
            }
        } advanced: {
            // The same setting as the size filter in Large & Old.
            Section("Large & Old") {
                Picker("Large files start at", selection: $model.largeFilter.minimumSize) {
                    ForEach(LargeFilesView.thresholds, id: \.1) { Text($0.0).tag($0.1) }
                }
            }
        }
    }
}
