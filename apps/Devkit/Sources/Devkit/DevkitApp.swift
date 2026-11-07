import AppKit
import DevkitCore
import SlopKit
import SwiftUI

@main
struct DevkitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared
    private let info = AppInfo.current(fallbackName: "Devkit")

    var body: some Scene {
        // One window. Closing it quits the app (SlopAppDelegate).
        Window("Devkit", id: "main") {
            MainView(model: model)
                .defaultAppStorage(Diagnostics.defaults)
        }
        .defaultSize(width: 1040, height: 640)
        .commands { DevkitCommands(model: model, info: info) }

        Settings {
            DevkitSettings(info: info, model: model)
                .defaultAppStorage(Diagnostics.defaults)
        }

        // Optional, off by default: click to show the window, like a status-bar utility.
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            DevkitMenuBarMenu(model: model, info: info)
        } label: {
            Label(info.name, systemImage: "curlybraces.square")
        }
    }

    @AppStorage(SettingsKey.showMenuBarIcon, store: Diagnostics.defaults) private var showMenuBarIcon = false
}

struct DevkitMenuBarMenu: View {
    let model: AppModel
    let info: AppInfo
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Show \(info.name)") { show() }
        Button("Paste and Detect") {
            show()
            model.pasteAndDetect()
        }
        Button("Replace Clipboard") { model.replaceClipboard() }
            .help("Convert what's on the clipboard with the tool that recognizes it")
        MenuFooter(info: info)
    }

    private func show() {
        AppActivation.activate()
        if let window = model.mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}

struct DevkitCommands: Commands {
    @Bindable var model: AppModel
    let info: AppInfo
    @AppStorage(SettingsKey.stackVertically, store: Diagnostics.defaults) private var stackVertically = false

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(info.name)") { AboutWindow.show(info: info) }
        }
        CommandGroup(replacing: .newItem) {
            Button(model.selection == .hash ? "Hash a File…" : "Open File…") { openFile() }
                .keyboardShortcut("o")
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Paste and Detect") { model.pasteAndDetect() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            Button("Copy Output") { model.copyOutput() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!model.canCopyOutput)
            Button("Use Output as Input") { model.useOutputAsInput() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canCopyOutput)
            Button("Clear Input") { model.clearInput() }
                .keyboardShortcut("k")
                .disabled(!model.canClearInput)
            Button("Paste Clipboard into Tool") { model.pasteClipboardIntoCurrentTool() }
                .keyboardShortcut("v", modifiers: [.command, .option])
            Button("Load Sample") { model.loadSample() }
                .disabled(!model.canLoadSample)
            Divider()
            Button("Replace Clipboard with Output") { model.replaceClipboard() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            switch model.selection {
            case .uuid:
                Button("Generate New IDs") {
                    model.uuid.mode = .generate
                    model.uuid.generate()
                }
                .keyboardShortcut("r")
            case .lorem:
                Button("Generate New Text") { model.lorem.generate() }
                    .keyboardShortcut("r")
            case .randomString:
                Button("Generate New Strings") { model.randomString.generate() }
                    .keyboardShortcut("r")
            default:
                EmptyView()
            }
        }
        CommandGroup(after: .textEditing) {
            Menu("Find") {
                Button("Find…") { TextFinding.perform(.showFindInterface, fallback: WindowFocus.focusSearchField) }
                    .keyboardShortcut("f")
                Button("Find and Replace…") { TextFinding.perform(.showReplaceInterface) }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                Button("Find Next") { TextFinding.perform(.nextMatch) }
                    .keyboardShortcut("g")
                Button("Find Previous") { TextFinding.perform(.previousMatch) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Use Selection for Find") { TextFinding.perform(.setSearchString) }
                    .keyboardShortcut("e")
            }
        }
        CommandGroup(before: .sidebar) {
            Toggle("Stack Panes Vertically", isOn: $stackVertically)
                .keyboardShortcut("l", modifiers: [.command, .option])
            Divider()
        }
        CommandMenu("Tools") {
            ForEach(Array(model.shownTools.enumerated()), id: \.element) { index, tool in
                if index < 9 {
                    Toggle(tool.title, isOn: selected(tool))
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                } else {
                    Toggle(tool.title, isOn: selected(tool))
                }
            }
            Divider()
            Button("Previous Tool") { model.selectNext(-1) }
                .keyboardShortcut("[", modifiers: [.command, .option])
            Button("Next Tool") { model.selectNext(1) }
                .keyboardShortcut("]", modifiers: [.command, .option])
            Divider()
            Button("Filter Tools") { WindowFocus.focusSearchField() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Search Tools") { WindowFocus.focusSearchField() }
                .keyboardShortcut("/")
            Divider()
            Toggle("Keep Window on Top", isOn: $model.keepOnTop)
                .keyboardShortcut("t", modifiers: [.command, .option])
            if !model.hiddenTools.isEmpty {
                Button("Show \(model.hiddenTools.count) Hidden \(model.hiddenTools.count == 1 ? "Tool" : "Tools")") { model.hiddenTools = [] }
            }
        }
        CommandGroup(replacing: .help) {
            Button("\(info.name) Help") {
                NSWorkspace.shared.open(Brand.repoURL.appendingPathComponent("tree/main/apps/Devkit"))
            }
        }
    }

    private func selected(_ tool: Tool) -> Binding<Bool> {
        Binding(get: { model.selection == tool }, set: { if $0 { model.selection = tool } })
    }

    /// Opens a file into the current tool: hashes it in Hash, loads its text elsewhere.
    @MainActor
    private func openFile() {
        if model.selection == .hash {
            NotificationCenter.default.post(name: .devkitOpenFile, object: nil)
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a text file to open in \(model.selection.title)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            let alert = NSAlert()
            alert.messageText = "Couldn't open “\(url.lastPathComponent)”"
            alert.informativeText = "It isn't a UTF-8 text file. To get its checksum, use the Hash tool."
            alert.runModal()
            return
        }
        model.setInput(text, on: model.current, actionName: "Open File")
    }
}

/// Sends find-bar actions to the focused text view (SwiftUI apps get no Find menu).
@MainActor
enum TextFinding {
    static func perform(_ action: NSTextFinder.Action, fallback: (() -> Void)? = nil) {
        let sender = NSMenuItem()
        sender.tag = action.rawValue
        let handled = NSApp.keyWindow?.firstResponder is NSTextView
            && NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: sender)
        if !handled { fallback?() }
    }
}

/// Puts the cursor in the sidebar's filter field.
@MainActor
enum WindowFocus {
    static func focusSearchField() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) ?? NSApp.keyWindow,
              let root = window.contentView?.superview, let field = searchField(in: root) else { return }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(field)
    }

    private static func searchField(in view: NSView) -> NSSearchField? {
        if let field = view as? NSSearchField { return field }
        for child in view.subviews {
            if let field = searchField(in: child) { return field }
        }
        return nil
    }
}

extension KeyboardShortcuts.Name {
    /// Brings Devkit forward and runs Paste and Detect. Unset by default.
    static let showAndDetect = Self("showAndDetect")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let standard = SlopAppDelegate()

    func applicationWillFinishLaunching(_ notification: Notification) {
        switch Diagnostics.forcedAppearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Snapshot.runIfAsked() { return }
        KeyboardShortcuts.onKeyUp(for: .showAndDetect) {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                window.makeKeyAndOrderFront(nil)
            }
            AppModel.shared.pasteAndDetect()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppModel.shared.readClipboardOnActivation()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        standard.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // With the menu bar icon on, Devkit stays there after its window closes.
        if Diagnostics.defaults.bool(forKey: SettingsKey.showMenuBarIcon) { return false }
        return standard.applicationShouldTerminateAfterLastWindowClosed(sender)
    }
}

struct DevkitSettings: View {
    let info: AppInfo
    let model: AppModel
    @AppStorage(SettingsKey.readClipboardOnOpen) private var readClipboard = false
    @AppStorage(SettingsKey.jsonIndent) private var jsonIndent = JSONFormatter.Indent.two.rawValue
    @AppStorage(SettingsKey.showMenuBarIcon) private var showMenuBarIcon = false

    var body: some View {
        SlopSettings(info: info, isMenuBarApp: false) {
            Toggle(isOn: $readClipboard) {
                Text("Read the clipboard when Devkit opens")
                Text("When the clipboard holds something a tool recognizes, like a JWT or JSON, Devkit opens that tool with it. Passwords and other private clipboard items are skipped. ⇧⌘V always works.")
            }
            Picker("JSON indent", selection: $jsonIndent) {
                ForEach(JSONFormatter.Indent.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .onChange(of: jsonIndent) { model.json.reloadSettings() }
            Toggle(isOn: $showMenuBarIcon) {
                Text("Show in menu bar")
                Text("Click the icon to bring Devkit forward, paste and detect, or replace the clipboard. Closing the window keeps Devkit in the menu bar.")
            }
        } shortcuts: {
            ShortcutRow("Show Devkit and paste and detect", subtitle: "Works from any app. Not set by default.",
                        name: .showAndDetect)
        } advanced: {
            ToolVisibilitySettings(model: model)
        }
    }
}

/// Settings ▸ Advanced: which tools the sidebar shows.
struct ToolVisibilitySettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Section {
            // Two columns of checkboxes keep 33 tools to a window that fits a laptop screen.
            let tools = Tool.allCases
            let half = (tools.count + 1) / 2
            Grid(alignment: .leading, horizontalSpacing: Spacing.xl, verticalSpacing: Spacing.xs) {
                ForEach(0..<half, id: \.self) { row in
                    GridRow {
                        toggle(tools[row])
                        if row + half < tools.count { toggle(tools[row + half]) }
                    }
                }
            }
        } header: {
            Text("Tools in the Sidebar")
        } footer: {
            HStack {
                Text("Hidden tools still appear when you search for them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show All") { model.hiddenTools = [] }
                    .disabled(model.hiddenTools.isEmpty)
            }
        }
    }

    private func toggle(_ tool: Tool) -> some View {
        // Each column takes half the section, so the grid fills it evenly.
        Toggle(tool.title, isOn: Binding(
            get: { !model.hiddenTools.contains(tool) },
            set: { show in
                if show { model.hiddenTools.remove(tool) } else { model.hide(tool) }
            }
        ))
        .toggleStyle(.checkbox)
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(!model.hiddenTools.contains(tool) && model.shownTools.count <= 1)
    }
}
