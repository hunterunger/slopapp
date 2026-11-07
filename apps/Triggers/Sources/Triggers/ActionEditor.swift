import AppKit
import SlopKit
import SwiftUI
import TriggersCore

/// The action picker and its one or two fields.
struct ActionEditor: View {
    let model: AppModel
    @Binding var action: Action
    let scope: Scope

    var body: some View {
        Picker("Action", selection: Binding(get: { action.kind }, set: { action = $0.defaultAction(from: action) })) {
            ForEach(ActionKind.groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.kinds, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
            }
            if scope != .allApps {
                Divider()
                Text(ActionKind.passThrough.title).tag(ActionKind.passThrough)
            }
        }
        fields
        if action.needsAccessibility && !model.isTrusted {
            HStack {
                Label("Needs Accessibility access.", systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.callout)
                Spacer()
                Button("Open System Settings") { model.openAccessibilitySettings() }
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder private var fields: some View {
        switch action {
        case .pressKeys(let combo):
            LabeledContent("Keys") {
                KeyComboField(combo: Binding(get: { combo }, set: { action = .pressKeys($0) }))
            }
        case .click(let kind):
            caption(kind == .middle ? "Clicks the middle button where the pointer is: opens links in a new tab, closes tabs."
                                    : "Clicks where the pointer is.")
        case .menuItem(let path):
            MenuItemField(model: model, path: Binding(get: { path }, set: { action = .menuItem($0) }), scope: scope)
        case .open(.app(let bundleID, let name)):
            AppField(app: Binding(get: { bundleID.isEmpty ? nil : AppChoice(bundleID: bundleID, name: name, url: nil) },
                                  set: { if let app = $0 { action = .open(.app(bundleID: app.bundleID, name: app.name)) } }))
        case .open(.url(let url)):
            TextField("Link", text: Binding(get: { url }, set: { action = .open(.url($0)) }), prompt: Text("https://example.com"))
            if !url.isEmpty && !OpenURLCheck.isOpenable(url) {
                caption("Enter a full link, starting with https:// or an app's own scheme.")
            }
        case .open(.file(let path)):
            LabeledContent("File") {
                HStack {
                    Text(path.isEmpty ? "None" : (path as NSString).lastPathComponent)
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(path.isEmpty ? .secondary : .primary)
                    Button("Choose File…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        if panel.runModal() == .OK, let url = panel.url { action = .open(.file(path: url.path)) }
                    }
                }
            }
        case .runShortcut(let name):
            ShortcutField(name: Binding(get: { name }, set: { action = .runShortcut($0) }))
        case .window(let move):
            caption(move == .nextDisplay ? "Moves the front window to the next display." : "Moves the front window.")
        case .passThrough:
            caption("Lets the app have the input, instead of the All Apps or Browsers trigger.")
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// Click, then press the keys to send. Esc cancels.
struct KeyComboField: View {
    @Binding var combo: KeyCombo
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stop() : start()
        } label: {
            Text(isRecording ? "Type the keys…" : KeyDisplay.name(combo))
                .monospacedDigit()
                .frame(minWidth: 96)
        }
        .accessibilityLabel(isRecording ? "Recording keys" : "Keys to press: \(KeyDisplay.spoken(combo))")
        .accessibilityHint("Click, then press the key combination to send.")
        .onDisappear { stop() }
    }

    private func start() {
        isRecording = true
        KeyRecorder.isActive = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = Int(event.keyCode)
            let modifiers = Modifiers(cgFlags: UInt64(event.cgEvent?.flags.rawValue ?? 0))
            MainActor.assumeIsolated {
                if keyCode != KeyNames.escape || !modifiers.isEmpty {
                    combo = KeyCombo(keyCode: keyCode, modifiers: modifiers)
                }
                stop()
            }
            return nil
        }
    }

    private func stop() {
        isRecording = false
        KeyRecorder.isActive = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Lets the sheet's own listener ignore keys meant for a key field.
@MainActor
enum KeyRecorder {
    static var isActive = false
}

/// A menu path: typed ("File › Export…") or picked from the app's real menus when it's running.
private struct MenuItemField: View {
    let model: AppModel
    @Binding var path: [String]
    let scope: Scope
    @State private var text = ""
    @State private var menus: [MenuNode] = []
    @State private var isLoading = false

    var body: some View {
        TextField("Menu item", text: $text, prompt: Text("File › Export…"))
            .onAppear { text = path.joined(separator: " › ") }
            .onChange(of: text) { _, value in path = Self.parse(value) }
        if let bundleID = scope.bundleID, let pid = AppCatalog.isRunning(bundleID), model.isTrusted {
            LabeledContent("Pick from \(model.appName(bundleID))") {
                if menus.isEmpty {
                    Button(isLoading ? "Reading Menus…" : "Read Menus") { load(pid: pid) }
                        .disabled(isLoading)
                } else {
                    Menu("Choose…") {
                        ForEach(menus) { node in MenuNodeView(node: node, prefix: []) { picked in
                            path = picked
                            text = picked.joined(separator: " › ")
                        } }
                    }
                    .fixedSize()
                }
            }
        } else {
            Text(scope.bundleID == nil
                 ? "Works in whichever app is in front, if it has this menu item. Separate menus with ›."
                 : "Separate menus with ›. Open the app to pick from its menus.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func load(pid: pid_t) {
        isLoading = true
        Task.detached {
            let nodes = MenuInvoker.read(pid: pid)
            await MainActor.run {
                menus = nodes
                isLoading = false
            }
        }
    }

    static func parse(_ text: String) -> [String] {
        text.replacingOccurrences(of: ">", with: "›").split(separator: "›")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

private struct MenuNodeView: View {
    let node: MenuNode
    let prefix: [String]
    let pick: ([String]) -> Void

    var body: some View {
        if node.children.isEmpty {
            Button(node.title) { pick(prefix + [node.title]) }
        } else {
            Menu(node.title) {
                ForEach(node.children) { child in MenuNodeView(node: child, prefix: prefix + [node.title], pick: pick) }
            }
        }
    }
}

/// Choose an app to open: open apps first, then any app.
private struct AppField: View {
    @Binding var app: AppChoice?

    var body: some View {
        LabeledContent("App") {
            Menu {
                ForEach(AppCatalog.runningApps()) { choice in
                    Button(choice.name) { app = choice }
                }
                Divider()
                Button("Choose App…") {
                    if let choice = AppCatalog.chooseApp(message: "Choose the app to open.") { app = choice }
                }
            } label: {
                Text(app?.name ?? "Choose…")
            }
            .fixedSize()
            .accessibilityLabel("App to open: \(app?.name ?? "none")")
        }
    }
}

/// Pick a Shortcut by name.
private struct ShortcutField: View {
    @Binding var name: String
    @State private var names: [String]?

    var body: some View {
        Group {
            if let names, !names.isEmpty {
                Picker("Shortcut", selection: $name) {
                    if name.isEmpty || !names.contains(name) {
                        Text(name.isEmpty ? "Choose…" : name).tag(name)
                    }
                    ForEach(names, id: \.self) { Text($0).tag($0) }
                }
            } else {
                TextField("Shortcut", text: $name, prompt: Text(names == nil ? "Loading Shortcuts…" : "Shortcut name"))
            }
        }
        .task { names = await ShortcutRunner.list() }
    }
}
