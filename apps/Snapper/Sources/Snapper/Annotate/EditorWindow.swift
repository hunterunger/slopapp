import AppKit
import Observation
import SlopKit
import SnapperCore
import SwiftUI

/// State of one annotation window.
@MainActor
@Observable
final class EditorModel {
    let item: CaptureItem
    @ObservationIgnored let renderer: AnnotationRenderer
    @ObservationIgnored weak var canvas: CanvasView?
    @ObservationIgnored private let app: AppModel
    var editor: AnnotationEditor
    /// True once the current edits have been copied, saved, shared or pinned.
    private(set) var exported = false
    /// A text annotation is being typed.
    var isEditingText = false
    /// The canvas zoom, for the window subtitle.
    var zoomPercent = 100

    var tool: Tool {
        didSet {
            guard tool != oldValue else { return }
            UserDefaults.standard.set(tool.rawValue, forKey: "editorTool")
            canvas?.toolChanged(from: oldValue)
        }
    }

    var color: PaletteColor {
        didSet { UserDefaults.standard.set(color.name, forKey: "editorColor") }
    }

    var width: StrokeWidth {
        didSet { UserDefaults.standard.set(width.rawValue, forKey: "editorWidth") }
    }

    init(item: CaptureItem, app: AppModel) {
        self.item = item
        self.app = app
        renderer = AnnotationRenderer(base: item.original, scale: item.scale)
        // Reopening picks up where you left off, undo history included.
        var state = item.editorState ?? AnnotationEditor(document: item.document ?? AnnotationDocument(imageSize: renderer.imageSize))
        state.selection = nil
        editor = state
        let defaults = UserDefaults.standard
        let savedTool = defaults.string(forKey: "editorTool").flatMap(Tool.init) ?? .arrow
        tool = savedTool == .crop ? .arrow : savedTool
        color = defaults.string(forKey: "editorColor").flatMap(PaletteColor.named) ?? .default
        width = (defaults.object(forKey: "editorWidth") as? Int).flatMap(StrokeWidth.init) ?? .medium
    }

    /// Called after every document change (the window updates its size subtitle).
    @ObservationIgnored var onChange: (() -> Void)?

    /// Call after every change to the document.
    func changed() {
        exported = false
        canvas?.needsDisplay = true
        onChange?()
    }

    /// "Annotate · 900 × 800 px": the size the result will have (after any crop).
    var subtitle: String {
        let visible = editor.document.visibleRect
        return "Annotate · \(Int((visible.width * item.scale).rounded())) × \(Int((visible.height * item.scale).rounded())) px"
    }

    // MARK: Style

    func pickColor(_ color: PaletteColor) {
        self.color = color
        editor.setColor(color.color)
        changed()
    }

    func pickWidth(_ width: StrokeWidth) {
        self.width = width
        editor.setWidth(width.points)
        changed()
    }

    func stepWidth(_ step: Int) {
        let all = StrokeWidth.allCases
        guard let index = all.firstIndex(of: width) else { return }
        pickWidth(all[min(max(index + step, 0), all.count - 1)])
    }

    // MARK: Edit

    func undo() { canvas?.endTextEditing(); editor.undo(); changed() }
    func redo() { canvas?.endTextEditing(); editor.redo(); changed() }
    var canUndo: Bool { editor.canUndo }
    var canRedo: Bool { editor.canRedo }
    var hasSelection: Bool { editor.selection != nil }

    func deleteSelection() {
        editor.deleteSelection()
        changed()
    }

    // MARK: Output

    /// The capture with the edits burned in, at full resolution.
    func rendered() -> CGImage {
        canvas?.endTextEditing()
        return renderer.render(editor.document) ?? item.original
    }

    /// Writes the edits back to the capture so cards, pins and Reopen Last Capture use them.
    func commitToItem() {
        let image = rendered()
        item.apply(editor.document, rendered: image)
        item.editorState = editor
    }

    func copy() {
        commitToItem()
        app.copy(item, closeCard: false)
        exported = true
    }

    func save() {
        commitToItem()
        app.save(item, closeCard: false)
        exported = true
    }

    func saveAs() {
        commitToItem()
        let item = self.item
        Task {
            if let url = await Output.saveAs(item.image, suggestedName: item.fileBaseName, format: app.format, folder: app.saveFolder) {
                item.savedURL = url
                item.lastSavedURL = url
                exported = true
            }
        }
    }

    func share(from view: NSView) {
        commitToItem()
        guard let url = item.temporaryFile(format: app.format) else { return }
        Output.share(url, from: view)
        exported = true
    }

    func pin() {
        commitToItem()
        exported = true
        EditorWindowController.close(model: self)
        app.pins.pin(item)
    }

    /// When the window closes: keep the edits; if they weren't exported anywhere, put the
    /// card back so the work is never lost.
    func finish() {
        commitToItem()
        if app.pins.contains(item) || app.cards.contains(item) { return }
        if item.document != nil, !exported {
            app.cards.add(item)
        } else {
            app.remember(item)
        }
    }
}

/// Annotation windows. While one is open Snapper shows in the Dock and has a menu bar, so
/// every editor action is in a menu with its shortcut.
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private static var open: [EditorWindowController] = []
    let model: EditorModel

    /// The editor in front (key window first), for menu commands.
    static var front: EditorModel? {
        for window in [NSApp.keyWindow, NSApp.mainWindow].compactMap({ $0 }) {
            if let controller = open.first(where: { $0.window === window }) { return controller.model }
        }
        let ordered = NSApp.orderedWindows
        func rank(_ controller: EditorWindowController) -> Int {
            ordered.firstIndex { $0 === controller.window } ?? .max
        }
        return open.min { rank($0) < rank($1) }?.model
    }

    static func isEditing(_ item: CaptureItem) -> Bool {
        open.contains { $0.model.item === item }
    }

    static func open(_ item: CaptureItem, model app: AppModel) {
        if let existing = open.first(where: { $0.model.item === item }) {
            NSApp.activate()
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let model = EditorModel(item: item, app: app)
        let controller = EditorWindowController(model: model)
        open.append(controller)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        controller.window?.makeKeyAndOrderFront(nil)
        Diagnostics.record("editor opened pixels=\(item.pixelSizeDescription)")
    }

    static func close(model: EditorModel) {
        open.first { $0.model === model }?.window?.performClose(nil)
    }

    init(model: EditorModel) {
        self.model = model
        let hosting = NSHostingController(rootView: EditorView(model: model))
        hosting.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.title = model.item.sourceName
        window.subtitle = model.subtitle
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setContentSize(Self.initialContentSize(for: model.item.size))
        window.contentMinSize = CGSize(width: 640, height: 360)
        window.center()
        super.init(window: window)
        window.delegate = self
        model.onChange = { [weak window, weak model] in
            guard let window, let model else { return }
            if window.subtitle != model.subtitle { window.subtitle = model.subtitle }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The capture at 1:1 (in points) plus room for the toolbar, at most 85% of the screen.
    static func initialContentSize(for imageSize: CGSize) -> CGSize {
        let visible = (NSScreen.underPointer ?? NSScreen.main)?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let padding = CanvasView.padding * 2
        let wanted = CGSize(width: imageSize.width + padding, height: imageSize.height + padding + 90)
        return CGSize(width: min(max(wanted.width, 720), visible.width * 0.85),
                      height: min(max(wanted.height, 420), visible.height * 0.85)).applying(.identity)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        ToolsMenuMarks.install()
        if let canvas = model.canvas { window?.makeFirstResponder(canvas.editingField ?? canvas) }
    }

    func windowWillClose(_ notification: Notification) {
        model.finish()
        Self.open.removeAll { $0 === self }
    }
}

/// The editor's SwiftUI shell: a tool strip (tools, color, width) above the canvas, and the
/// output actions in the window toolbar.
struct EditorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            ToolStrip(model: model)
            Divider()
            CanvasRepresentable(model: model)
                .frame(minWidth: 520, minHeight: 300)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .help("Undo (⌘Z)")
                    .disabled(!model.canUndo)
                Button { model.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                    .help("Redo (⇧⌘Z)")
                    .disabled(!model.canRedo)
                Button { model.copy() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .help("Copy Image (⌘C)")
                Button { model.save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                    .help("Save to the save folder (⌘S)")
                Button {
                    if let canvas = model.canvas { model.share(from: canvas.shareAnchor) }
                } label: { Label("Share", systemImage: "square.and.arrow.up") }
                    .help("Share")
                Button { model.pin() } label: { Label("Pin to Screen", systemImage: "pin") }
                    .help("Pin to Screen (⇧⌘P)")
            }
        }
    }
}

/// Tools on the left, style on the right, like a markup bar.
struct ToolStrip: View {
    @Bindable var model: EditorModel

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(Tool.allCases) { tool in
                Toggle(isOn: Binding(get: { model.tool == tool }, set: { if $0 { model.tool = tool } })) {
                    Label(tool.title, systemImage: tool.systemImage)
                        .labelStyle(.iconOnly)
                        .frame(width: 22)
                }
                .help("\(tool.title) (\(String(tool.key).uppercased()))")
                .accessibilityLabel(tool.title)
                if tool == .select || tool == .highlighter || tool == .counter {
                    Divider().frame(height: 16).padding(.horizontal, Spacing.xs)
                }
            }
            Spacer(minLength: Spacing.m)
            ColorMenu(model: model)
            WidthMenu(model: model)
        }
        .toggleStyle(.button)
        .buttonStyle(.accessoryBar)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s - 2)
        .background(.bar)
    }
}

/// Standard pop-up menus, so VoiceOver always reads "Color, Blue" / "Line Width, Thick"
/// (label and current value), whatever state the toolbar is in.
struct ColorMenu: View {
    @Bindable var model: EditorModel

    var body: some View {
        Picker("Color", selection: Binding(get: { model.color }, set: { model.pickColor($0) })) {
            ForEach(PaletteColor.all) { color in
                Label { Text(color.name) } icon: { Image(nsImage: Swatch.image(color.color, selected: false)) }
                    .tag(color)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help("Color")
    }
}

struct WidthMenu: View {
    @Bindable var model: EditorModel

    var body: some View {
        Picker("Line Width", selection: Binding(get: { model.width }, set: { model.pickWidth($0) })) {
            ForEach(StrokeWidth.allCases) { width in
                Text(width.title).tag(width)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help("Line width ([ and ])")
    }
}

/// Round color swatches for menus and the toolbar (annotation colors are content, so they're drawn as-is).
enum Swatch {
    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor
    static func image(_ color: RGBA, selected: Bool) -> NSImage {
        let key = "\(color.red),\(color.green),\(color.blue),\(selected)"
        if let cached = cache[key] { return cached }
        let image = NSImage(size: CGSize(width: 16, height: 16), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            NSColor(cgColor: color.cgColor)?.setFill()
            circle.fill()
            NSColor.separatorColor.setStroke()
            circle.lineWidth = 1
            circle.stroke()
            if selected {
                let dot = NSBezierPath(ovalIn: rect.insetBy(dx: 6, dy: 6))
                (color.isLight ? NSColor.black : NSColor.white).setFill()
                dot.fill()
            }
            return true
        }
        image.isTemplate = false
        cache[key] = image
        return image
    }
}

/// Menu bar commands for the front editor. SwiftUI doesn't re-evaluate `Commands` when app
/// state changes, so items stay enabled and find their editor when chosen; single-key tool
/// shortcuts and Delete are handled by the canvas (as menu key equivalents they would also
/// fire while typing in text fields).
struct EditorCommands: Commands {
    private var editor: EditorModel? { EditorWindowController.front }
    private var pin: PinPanel? { NSApp.keyWindow as? PinPanel }

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { editor?.undo() }
                .keyboardShortcut("z")
            Button("Redo") { editor?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .saveItem) {
            Button("Close") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w")
            Divider()
            Button("Save") { editor?.save() }
                .keyboardShortcut("s")
            Button("Save As…") { editor?.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Pin to Screen") { editor?.pin() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
        }
        CommandGroup(after: .toolbar) {
            // A pinned capture in front zooms itself; otherwise the editor does.
            Button("Zoom In") { pin?.zoom(by: PinGeometry.zoomStep) ?? editor?.canvas?.zoomIn() }
                .keyboardShortcut("=")
            Button("Zoom Out") { pin?.zoom(by: 1 / PinGeometry.zoomStep) ?? editor?.canvas?.zoomOut() }
                .keyboardShortcut("-")
            Button("Actual Size") { pin?.actualSize() ?? editor?.canvas?.zoomToActualSize() }
                .keyboardShortcut("0")
            Button("Zoom to Fit") { editor?.canvas?.zoomToFit() }
                .keyboardShortcut("9")
            Divider()
        }
        CommandMenu("Tools") {
            // The single-key shortcut shows as a subtitle: as a menu key equivalent it would
            // also fire while typing text (the canvas handles the key instead).
            ForEach(Tool.allCases) { tool in
                Button { editor?.tool = tool } label: {
                    Text(tool.title)
                    Text("Press \(String(tool.key).uppercased())")
                }
            }
            Divider()
            Menu("Color") {
                ForEach(PaletteColor.all) { color in
                    Button(color.name) { editor?.pickColor(color) }
                }
            }
            Menu("Line Width") {
                ForEach(StrokeWidth.allCases) { width in
                    Button(width.title) { editor?.pickWidth(width) }
                }
                Divider()
                Button { editor?.stepWidth(1) } label: { Text("Thicker"); Text("Press ]") }
                Button { editor?.stepWidth(-1) } label: { Text("Thinner"); Text("Press [") }
            }
            Divider()
            Button { editor?.deleteSelection() } label: { Text("Delete Selection"); Text("Press ⌫") }
        }
    }
}

/// Checkmarks the current tool, color and width in the Tools menu each time it opens.
/// (SwiftUI builds the menu once and doesn't re-read editor state, so an AppKit menu
/// delegate fills the marks in when the menu is about to show.)
@MainActor
final class ToolsMenuMarks: NSObject, NSMenuDelegate {
    static let shared = ToolsMenuMarks()

    static func install() {
        DispatchQueue.main.async {
            guard let tools = NSApp.mainMenu?.items.first(where: { $0.title == "Tools" })?.submenu else { return }
            tools.delegate = shared
            for item in tools.items { item.submenu?.delegate = shared }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let editor = EditorWindowController.front else { return }
        let marked = [editor.tool.title, editor.color.name, editor.width.title]
        for item in menu.items where item.submenu == nil {
            item.state = marked.contains(item.title) ? .on : .off
        }
    }
}
