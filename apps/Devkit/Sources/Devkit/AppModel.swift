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
    @ObservationIgnored lazy var urlParser = URLParserToolModel()
    @ObservationIgnored lazy var stringInspector = StringInspectorToolModel()
    @ObservationIgnored lazy var lorem = LoremToolModel()
    @ObservationIgnored lazy var randomString = RandomStringToolModel()
    @ObservationIgnored lazy var qrCode = QRToolModel()
    @ObservationIgnored lazy var certificate = CertificateToolModel()
    @ObservationIgnored lazy var cron = CronToolModel()
    /// Converters and formatters share one model type, made on first use.
    @ObservationIgnored private var transforms: [Tool: TransformToolModel] = [:]

    /// Tools hidden from the sidebar (Settings ▸ Tools, or the sidebar's context menu).
    var hiddenTools: Set<Tool> {
        didSet {
            Diagnostics.defaults.set(hiddenTools.map(\.rawValue).sorted(), forKey: SettingsKey.hiddenTools)
        }
    }

    /// The window floats above other apps' windows.
    var keepOnTop: Bool {
        didSet {
            Diagnostics.defaults.set(keepOnTop, forKey: SettingsKey.keepOnTop)
            applyWindowLevel()
        }
    }

    init(clipboard: Clipboard = SystemClipboard.current()) {
        self.clipboard = clipboard
        selection = Diagnostics.defaults.string(forKey: SettingsKey.selectedTool).flatMap(Tool.init(rawValue:)) ?? .json
        hiddenTools = Set((Diagnostics.defaults.stringArray(forKey: SettingsKey.hiddenTools) ?? []).compactMap(Tool.init(rawValue:)))
        keepOnTop = Diagnostics.defaults.bool(forKey: SettingsKey.keepOnTop)
    }

    func transform(_ tool: Tool) -> TransformToolModel {
        if let model = transforms[tool] { return model }
        let model = TransformToolModel(spec: TransformSpec.make(tool)!)
        transforms[tool] = model
        return model
    }

    func applyWindowLevel() {
        mainWindow?.level = keepOnTop ? .floating : .normal
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
        case .urlParser: urlParser
        case .stringInspector: stringInspector
        case .lorem: lorem
        case .randomString: randomString
        case .qrCode: qrCode
        case .certificate: certificate
        case .cron: cron
        case .yamlToJSON, .jsonToYAML, .csvToJSON, .jsonToCSV, .htmlEntities, .backslash, .htmlFormat, .cssFormat,
             .xmlFormat, .sqlFormat, .svgToCSS, .hexText, .lineSort, .gzip:
            transform(tool)
        }
    }

    var current: ToolModel { model(for: selection) }

    var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "main" }
    }

    /// Sidebar tools: not hidden, matching the filter. A hidden tool still shows while a filter
    /// matches it, so typing its name always finds it.
    var visibleTools: [Tool] {
        let query = sidebarFilter.trimmingCharacters(in: .whitespaces)
        return Tool.allCases.filter { (!hiddenTools.contains($0) || !query.isEmpty) && $0.matches(filter: query) }
    }

    /// Tools in sidebar order without the hidden ones (⌘1…⌘9 follow this).
    var shownTools: [Tool] { Tool.allCases.filter { !hiddenTools.contains($0) } }

    func hide(_ tool: Tool) {
        hiddenTools.insert(tool)
        if selection == tool, let next = shownTools.first { selection = next }
    }

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
        if selection == .qrCode, qrCode.mode == .generate {
            guard let png = qrCode.pngData else { NSSound.beep(); return }
            clipboard.setPNG(png)
            reader.noteOwnWrite(clipboard)
            HUD.show("Copied QR Code", systemImage: "doc.on.doc")
            return
        }
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
        if let transform = model as? TransformToolModel { transform.flipMode() }
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

    // MARK: - Input header buttons

    /// "Clipboard": the clipboard's text into this tool, without detection.
    func pasteClipboardIntoCurrentTool() {
        if selection == .qrCode, qrCode.mode == .read {
            readQRFromClipboard()
            return
        }
        guard let text = clipboard.string(), !text.isEmpty else {
            HUD.show("The clipboard has no text", systemImage: "doc.on.clipboard")
            return
        }
        reader.noteOwnWrite(clipboard)
        let model = current
        model.receive(Detector.Detection(tool: selection, input: text, hint: Detector.detect(text)?.hint ?? .none))
        setInput(text, on: model, actionName: "Paste")
        model.editor.focus()
    }

    /// "Sample": an example input, so a tool can be tried right away.
    func loadSample() {
        switch selection {
        case .regex:
            regex.pattern = Samples.regexPattern
            setInput(Samples.regexText, on: regex, actionName: "Sample")
        case .diff:
            diff.changed = Samples.diffChanged
            setInput(Samples.diffOriginal, on: diff, actionName: "Sample")
        case .uuid:
            uuid.mode = .inspect
            setInput(uuid.sampleInput ?? "", on: uuid, actionName: "Sample")
        case .lorem:
            lorem.generate()
        case .randomString:
            randomString.generate()
        default:
            guard let sample = current.sampleInput else { NSSound.beep(); return }
            if selection == .qrCode { qrCode.mode = .generate }
            setInput(sample, on: current, actionName: "Sample")
        }
        current.editor.focus()
    }

    var canLoadSample: Bool {
        switch selection {
        case .regex, .diff, .uuid, .lorem, .randomString: true
        default: current.sampleInput != nil
        }
    }

    func readQRFromClipboard() {
        if let data = clipboard.imageData() {
            selection = .qrCode
            qrCode.read(imageData: data)
        } else if let file = clipboard.fileURL() {
            selection = .qrCode
            qrCode.read(url: file)
        } else {
            HUD.show("The clipboard has no image", systemImage: "photo")
        }
    }

    /// ⇧⌘R: detect what's on the clipboard, run the tool, and put the result back.
    func replaceClipboard() {
        guard let text = clipboard.string(), !text.isEmpty, let detection = Detector.detect(text) else {
            NSSound.beep()
            HUD.show("No tool recognizes the clipboard", systemImage: "doc.on.clipboard")
            return
        }
        apply(detection, actionName: "Replace Clipboard")
        let model = model(for: detection.tool)
        Task { @MainActor in
            // Small inputs are converted at once; large ones on a background thread.
            for _ in 0..<60 {
                await Task.yield()
                if model.input == detection.input, let output = model.primaryOutput, !output.isEmpty {
                    clipboard.setString(output)
                    reader.noteOwnWrite(clipboard)
                    HUD.show("Clipboard replaced (\(detection.tool.title))", systemImage: "arrow.triangle.2.circlepath")
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            NSSound.beep()
        }
    }

    func select(index: Int) {
        let tools = shownTools
        guard tools.indices.contains(index) else { return }
        selection = tools[index]
    }

    func selectNext(_ offset: Int) {
        let tools = visibleTools.isEmpty ? shownTools : visibleTools
        guard let index = tools.firstIndex(of: selection) else {
            selection = tools.first ?? .json
            return
        }
        selection = tools[(index + offset + tools.count) % tools.count]
    }
}
