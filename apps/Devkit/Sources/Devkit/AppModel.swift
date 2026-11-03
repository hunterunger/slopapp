import AppKit
import DevkitCore
import Observation
import SlopKit

/// App state: the selected tool, every tool's model, and the clipboard actions.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    var selection: Tool {
        didSet {
            guard selection != oldValue else { return }
            Diagnostics.defaults.set(selection.rawValue, forKey: SettingsKey.selectedTool)
            // Undo steps belong to the editors of the tool that was showing; they're gone now.
            mainWindow?.undoManager?.removeAllActions()
        }
    }
    var sidebarFilter = ""
    /// Bumped to ask the sidebar's filter field to take focus.
    var focusFilterRequest = 0

    @ObservationIgnored let clipboard: Clipboard
    @ObservationIgnored let reader = ClipboardReader()

    @ObservationIgnored lazy var json = JSONToolModel()
    @ObservationIgnored lazy var jwt = JWTToolModel()
    @ObservationIgnored lazy var base64 = Base64ToolModel()
    @ObservationIgnored lazy var url = URLToolModel()
    @ObservationIgnored lazy var timestamp = TimestampToolModel()
    @ObservationIgnored lazy var uuid = UUIDToolModel()
    @ObservationIgnored lazy var hash = HashToolModel()
    @ObservationIgnored lazy var regex = RegexToolModel()
    @ObservationIgnored lazy var diff = DiffToolModel()
    @ObservationIgnored lazy var color = ColorToolModel()
    @ObservationIgnored lazy var numberBase = NumberBaseToolModel()
    @ObservationIgnored lazy var textCase = CaseToolModel()

    init(clipboard: Clipboard = SystemClipboard.current()) {
        self.clipboard = clipboard
        selection = Diagnostics.defaults.string(forKey: SettingsKey.selectedTool).flatMap(Tool.init(rawValue:)) ?? .json
    }

    func model(for tool: Tool) -> ToolModel {
        switch tool {
        case .json: json
        case .jwt: jwt
        case .base64: base64
        case .url: url
        case .timestamp: timestamp
        case .uuid: uuid
        case .hash: hash
        case .regex: regex
        case .diff: diff
        case .color: color
        case .numberBase: numberBase
        case .textCase: textCase
        }
    }

    var current: ToolModel { model(for: selection) }

    var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "main" }
    }

    var visibleTools: [Tool] { Tool.allCases.filter { $0.matches(filter: sidebarFilter) } }

    // MARK: - Actions

    /// ⇧⌘V: read the clipboard, pick the matching tool, fill its input.
    func pasteAndDetect() {
        // A file copied in Finder: the Hash tool hashes it.
        if selection == .hash, let file = clipboard.fileURL() {
            hash.hashFile(file)
            return
        }
        switch reader.pasteAndDetect(from: clipboard) {
        case .noText:
            HUD.show("The clipboard has no text", systemImage: "doc.on.clipboard")
        case let .detected(detection):
            apply(detection, actionName: "Paste and Detect")
        case let .unmatched(text):
            setInput(text, on: current, actionName: "Paste")
            current.editor.focus()
            HUD.show("Pasted into \(selection.title)", systemImage: "doc.on.clipboard")
        }
    }

    /// Opt-in: on activation, read a new clipboard once and switch only when a tool matches.
    func readClipboardOnActivation() {
        let enabled = Diagnostics.defaults.bool(forKey: SettingsKey.readClipboardOnOpen)
        guard let detection = reader.automaticRead(from: clipboard, enabled: enabled) else { return }
        // Already showing exactly this? Leave it alone.
        if detection.tool == selection, model(for: detection.tool).input == detection.input { return }
        apply(detection, actionName: "Read Clipboard")
    }

    private func apply(_ detection: Detector.Detection, actionName: String) {
        let model = model(for: detection.tool)
        model.receive(detection)
        guard detection.tool != selection else {
            setInput(detection.input, on: model, actionName: actionName)
            model.editor.focus()
            return
        }
        selection = detection.tool
        // The new tool's editor appears on the next turn of the run loop; fill it then, so
        // the change is one undoable edit in that editor.
        DispatchQueue.main.async {
            self.setInput(detection.input, on: model, actionName: actionName)
            model.editor.focus()
        }
    }

    /// ⇧⌘C
    func copyOutput() {
        guard let output = current.primaryOutput, !output.isEmpty else {
            NSSound.beep()
            return
        }
        clipboard.setString(output)
        reader.noteOwnWrite(clipboard)
        HUD.show("Copied \(current.primaryOutputName)", systemImage: "doc.on.doc")
    }

    func copy(_ text: String, name: String) {
        clipboard.setString(text)
        reader.noteOwnWrite(clipboard)
        HUD.show("Copied \(name)", systemImage: "doc.on.doc")
    }

    var canCopyOutput: Bool { !(current.primaryOutput ?? "").isEmpty }

    /// ⌘↩: feed the output onward. Goes to whichever tool recognizes it, or stays here.
    func useOutputAsInput() {
        guard let output = current.primaryOutput, !output.isEmpty else {
            NSSound.beep()
            return
        }
        if let detection = Detector.detect(output), detection.tool != selection {
            apply(detection, actionName: "Use Output as Input")
            HUD.show("Opened in \(detection.tool.title)", systemImage: "arrow.turn.down.right")
            return
        }
        let model = current
        // Reversible tools flip direction, so decode → output → encode round-trips.
        if let base64 = model as? Base64ToolModel { base64.mode = base64.mode == .encode ? .decode : .encode }
        if let url = model as? URLToolModel { url.mode = url.mode == .encode ? .decode : .encode }
        setInput(output, on: model, actionName: "Use Output as Input")
        model.editor.focus()
    }

    /// ⌘K: undoable.
    func clearInput() {
        let model = current
        if let hash = model as? HashToolModel, hash.file != nil { hash.cancelFile() }
        if let diff = model as? DiffToolModel, diff.input.isEmpty, !diff.changed.isEmpty {
            if !diff.changedEditor.replaceAll(with: "", actionName: "Clear") { diff.changed = "" }
            return
        }
        setInput("", on: model, actionName: "Clear Input")
        model.editor.focus()
    }

    var canClearInput: Bool {
        let model = current
        if let diff = model as? DiffToolModel { return !diff.input.isEmpty || !diff.changed.isEmpty }
        if let hash = model as? HashToolModel, hash.file != nil { return true }
        return !model.input.isEmpty
    }

    /// Replaces a tool's input as one undo step: through its text editor when showing,
    /// otherwise through the window's undo manager.
    func setInput(_ text: String, on model: ToolModel, actionName: String) {
        if model.editor.replaceAll(with: text, actionName: actionName) { return }
        let old = model.input
        guard old != text else { return }
        model.input = text
        if let undoManager = mainWindow?.undoManager {
            undoManager.registerUndo(withTarget: self) { app in
                app.setInput(old, on: model, actionName: actionName)
            }
            undoManager.setActionName(actionName)
        }
    }

    func select(index: Int) {
        let tools = Tool.allCases
        guard tools.indices.contains(index) else { return }
        selection = tools[index]
    }

    func selectNext(_ offset: Int) {
        let tools = visibleTools.isEmpty ? Tool.allCases : visibleTools
        guard let index = tools.firstIndex(of: selection) else {
            selection = tools.first ?? .json
            return
        }
        selection = tools[(index + offset + tools.count) % tools.count]
    }
}
