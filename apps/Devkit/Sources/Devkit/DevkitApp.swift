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
            if model.selection == .uuid {
                Button("Generate New IDs") {
                    model.uuid.mode = .generate
                    model.uuid.generate()
                }
                .keyboardShortcut("r")
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
            ForEach(Array(Tool.allCases.enumerated()), id: \.element) { index, tool in
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
        standard.applicationShouldTerminateAfterLastWindowClosed(sender)
    }
}

struct DevkitSettings: View {
    let info: AppInfo
    let model: AppModel
    @AppStorage(SettingsKey.readClipboardOnOpen) private var readClipboard = false
    @AppStorage(SettingsKey.jsonIndent) private var jsonIndent = JSONFormatter.Indent.two.rawValue

    var body: some View {
        SlopSettings(info: info, isMenuBarApp: false) {
            Toggle("Read the clipboard when Devkit opens", isOn: $readClipboard)
            Text("When the clipboard holds something a tool recognizes, like a JWT or JSON, Devkit opens that tool with it. Passwords and other private clipboard items are skipped. Off by default; ⇧⌘V always works.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("JSON indent", selection: $jsonIndent) {
                ForEach(JSONFormatter.Indent.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .onChange(of: jsonIndent) { model.json.reloadSettings() }
        } shortcuts: {
            ShortcutRow("Show Devkit and paste and detect", name: .showAndDetect)
            Text("Works from any app. Not set by default.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
