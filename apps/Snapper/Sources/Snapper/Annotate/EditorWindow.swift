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
    /// The image the last commit gave the capture (nothing to commit while it's unchanged).
    @ObservationIgnored private var lastCommitted: CGImage?

    var tool: Tool {
        didSet {
            guard tool != oldValue else { return }
            Preferences.store.set(tool.rawValue, forKey: "editorTool")
            canvas?.toolChanged(from: oldValue)
        }
    }

    var color: PaletteColor {
        didSet { Preferences.store.set(color.name, forKey: "editorColor") }
    }

    var width: StrokeWidth {
        didSet { Preferences.store.set(width.rawValue, forKey: "editorWidth") }
    }

    var redaction: RedactionStyle {
        didSet { Preferences.store.set(redaction.rawValue, forKey: "editorRedaction") }
    }

    /// The Background tool's sidebar is open.
    var showsBackground = false

    /// Objects copied with ⌘C inside an editor (pasted with ⌘V into any editor).
    @ObservationIgnored static var objectClipboard: Annotation?

    /// What the current tool draws.
    var drawingKind: AnnotationKind? { tool.kind(redaction: redaction) }

    init(item: CaptureItem, app: AppModel) {
        self.item = item
        self.app = app
        lastCommitted = item.image
        renderer = AnnotationRenderer(base: item.original, scale: item.scale)
        renderer.drawsShadows = app.annotateShadows
        // Reopening picks up where you left off, undo history included.
        var state = item.editorState ?? AnnotationEditor(document: item.document ?? AnnotationDocument(imageSize: renderer.imageSize))
        state.selection = nil
        editor = state
        let defaults = Preferences.store
        let savedTool = defaults.string(forKey: "editorTool").flatMap(Tool.init) ?? .arrow
        tool = savedTool == .crop ? .arrow : savedTool
        color = defaults.string(forKey: "editorColor").flatMap(PaletteColor.named) ?? .default
        width = (defaults.object(forKey: "editorWidth") as? Int).flatMap(StrokeWidth.init) ?? .medium
        redaction = defaults.string(forKey: "editorRedaction").flatMap(RedactionStyle.init) ?? .pixelate
        showsBackground = state.document.background != nil
    }

    /// Called after every document change (the window updates its size subtitle).
    @ObservationIgnored var onChange: (() -> Void)?

    /// Call after every change to the document.
    func changed() {
        exported = false
        canvas?.needsDisplay = true
        canvas?.needsLayout = true
        onChange?()
    }

    /// "Annotate · 900 × 800 px": the size the result will have (after any crop).
    var subtitle: String {
        let visible = editor.document.outputRect
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

    func pickRedaction(_ style: RedactionStyle) {
        redaction = style
        if var selected = editor.selected, selected.kind.isRedaction, selected.kind != style.kind {
            selected.kind = style.kind
            editor.update(selected)
        }
        tool = .redact
        changed()
    }

    /// ⌘D.
    func duplicate() {
        editor.duplicateSelection()
        changed()
    }

    /// ⌘C: the selected object if there is one (for ⌘V), else the whole image.
    func copyObjectOrImage() {
        if let selected = editor.selected {
            Self.objectClipboard = selected
            HUD.show("Copied \(selected.kind.rawValue == "text" ? "text box" : "object")", systemImage: "doc.on.doc")
        } else {
            copy()
        }
    }

    /// ⌘V: pastes an object copied in an editor.
    func pasteObject() {
        guard let object = Self.objectClipboard else { return }
        editor.paste(object)
        changed()
    }

    // MARK: Background

    func toggleBackground() {
        canvas?.endTextEditing()
        if tool == .crop { tool = .select }
        showsBackground.toggle()
        if showsBackground, editor.document.background == nil {
            editor.setBackground(CaptureBackground())
            changed()
        }
    }

    func setBackground(_ background: CaptureBackground?) {
        editor.setBackground(background)
        changed()
    }

    func adjustBackground(editing: Bool, _ change: (inout CaptureBackground) -> Void) {
        if editing { editor.beginChange() }
        editor.adjustBackground(change)
        if !editing { editor.commitChange() }
        changed()
    }

    // MARK: Print

    func print() {
        let image = rendered()
        let view = NSImageView(frame: CGRect(origin: .zero, size: CGSize(width: CGFloat(image.width) / item.scale, height: CGFloat(image.height) / item.scale)))
        view.image = NSImage(cgImage: image, size: view.frame.size)
        view.imageScaling = .scaleProportionallyDown
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        info.orientation = view.frame.width > view.frame.height ? .landscape : .portrait
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = item.fileBaseName
        if let window = canvas?.window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }

    /// The Done button: close, keeping the edits.
    func done() {
        EditorWindowController.close(model: self)
    }

    /// A file of the current result, for dragging out of the editor.
    func fileForDrag() -> URL? {
        commitToItem()
        exported = true
        return item.temporaryFile(format: app.format)
    }

    func copyText() {
        commitToItem()
        app.copyText(item)
    }

    // MARK: Output

    /// The capture with the edits burned in, at full resolution.
    func rendered() -> CGImage {
        canvas?.endTextEditing()
        return renderer.render(editor.document) ?? item.original
    }

    /// Writes the edits back to the capture so cards, pins and Reopen Last Capture use them.
    func commitToItem() {
        canvas?.endTextEditing()
        item.editorState = editor
        // Nothing new since the last commit: keep the capture (and its history file) as is.
        let edits = editor.document.isEdited ? editor.document : nil
        if edits == item.document, item.image === lastCommitted { return }
        let image = rendered()
        item.apply(editor.document, rendered: image)
        lastCommitted = item.image
        app.history.edited(item)
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
        let controller = EditorWindowController(model: model, app: app)
        open.append(controller)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        controller.window?.makeKeyAndOrderFront(nil)
        // Once SwiftUI has built the title bar's tools (and again whenever it becomes key).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak controller] in
            ToolsMenuMarks.installToolTips(in: controller?.window)
        }
        Diagnostics.record("editor opened pixels=\(item.pixelSizeDescription)")
    }

    static func owns(_ window: NSWindow) -> Bool { open.contains { $0.window === window } }

    /// Captures open in editors (history never prunes them).
    static var openItems: [CaptureItem] { open.map(\.model.item) }

    /// Writes every open editor's edits to its capture (before quitting).
    static func commitAll() {
        for controller in open { controller.model.commitToItem() }
    }

    /// Settings → Annotate → Always on top.
    static func applyLevel() {
        for controller in open { controller.window?.level = AppModel.shared.annotateAlwaysOnTop ? .floating : .normal }
    }

    static func close(model: EditorModel) {
        open.first { $0.model === model }?.window?.performClose(nil)
    }

    init(model: EditorModel, app: AppModel) {
        self.model = model
        let hosting = NSHostingController(rootView: EditorView(model: model))
        hosting.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.title = model.item.sourceName
        window.subtitle = model.subtitle
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setContentSize(Self.initialContentSize(for: model.item.size))
        window.contentMinSize = CGSize(width: 900, height: 420)
        window.center()
        super.init(window: window)
        if app.annotateAlwaysOnTop { window.level = .floating }
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
        return CGSize(width: min(max(wanted.width, 960), visible.width * 0.9),
                      height: min(max(wanted.height, 420), visible.height * 0.85)).applying(.identity)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        ToolsMenuMarks.install()
        ToolsMenuMarks.installToolTips(in: window)
        if let canvas = model.canvas {
            window?.makeFirstResponder(canvas.editingField ?? canvas)
            canvas.needsDisplay = true
        }
    }

    /// The selection goes grey in a background window.
    func windowDidResignKey(_ notification: Notification) {
        model.canvas?.needsDisplay = true
    }

    func windowWillClose(_ notification: Notification) {
        model.finish()
        Self.open.removeAll { $0 === self }
    }
}

/// The editor's SwiftUI shell, laid out like the screenshot editors people know: every tool
/// in the title bar (crop and background first, then the drawing tools, then color and
/// style), Save As… and Done on the right; a bottom bar with zoom, a drag handle and the
/// quick outputs; the Background tool's options in a sidebar.
struct EditorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if model.showsBackground {
                    BackgroundPanel(model: model)
                        .frame(width: BackgroundPanel.width)
                    Hairline(axis: .vertical)
                }
                CanvasRepresentable(model: model)
                    .frame(minWidth: 480, minHeight: 280)
            }
            Hairline()
            BottomBar(model: model)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Toggle(isOn: Binding(get: { model.tool == .crop }, set: { model.tool = $0 ? .crop : .select })) {
                    Label("Crop", systemImage: Tool.crop.systemImage)
                }
                .help("Crop (K)")
                Toggle(isOn: Binding(get: { model.showsBackground }, set: { _ in model.toggleBackground() })) {
                    Label("Background", systemImage: "rectangle.inset.filled")
                }
                .help("Background (B)")
            }
            ToolbarItem(placement: .principal) {
                ToolPicker(model: model)
            }
            ToolbarItemGroup(placement: .principal) {
                ColorMenu(model: model)
                if model.tool == .redact || model.editor.selected?.kind.isRedaction == true {
                    RedactionMenu(model: model)
                } else {
                    WidthMenu(model: model)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Save As…") { model.saveAs() }
                    .help("Save As… (⇧⌘S)")
                Button("Done") { model.done() }
                    .buttonStyle(.borderedProminent)
                    .help("Close the editor, keeping your edits")
            }
        }
    }
}

/// The drawing tools as one segmented control (a native radio group for VoiceOver).
struct ToolPicker: View {
    @Bindable var model: EditorModel
    static let tools: [Tool] = [.select, .rectangle, .filledRectangle, .ellipse, .line, .arrow, .text,
                                .pencil, .highlighter, .redact, .spotlight, .counter]

    var body: some View {
        Picker("Tool", selection: Binding(get: { model.tool }, set: { model.tool = $0 })) {
            ForEach(Self.tools) { tool in
                Label(tool.title, systemImage: tool.systemImage)
                    .labelStyle(.iconOnly)
                    .help("\(tool.title) (\(String(tool.key).uppercased()))")
                    .tag(tool)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Tools: V, R, F, E, L, A, T, D, M, P, H, C")
    }
}

/// Zoom on the left, a drag handle in the middle, quick outputs on the right.
struct BottomBar: View {
    @Bindable var model: EditorModel
    static let height: CGFloat = 40

    var body: some View {
        HStack(spacing: Spacing.s) {
            Menu {
                Button("Zoom In") { model.canvas?.zoomIn() }
                Button("Zoom Out") { model.canvas?.zoomOut() }
                Button("Actual Size") { model.canvas?.zoomToActualSize() }
                Button("Zoom to Fit") { model.canvas?.zoomToFit() }
            } label: {
                Text("\(model.zoomPercent)%").monospacedDigit()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Zoom")
            .accessibilityLabel("Zoom, \(model.zoomPercent) percent")
            Text(model.subtitle.replacingOccurrences(of: "Annotate · ", with: ""))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            DragHandle(model: model)
                .frame(width: 120, height: 24)
            Spacer()
            Group {
                Button { if let canvas = model.canvas { model.share(from: canvas.shareAnchor) } } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .help("Share")
                Button { model.pin() } label: { Label("Pin to Screen", systemImage: "pin") }
                    .help("Pin to Screen (⇧⌘P)")
                Button { model.copy() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .help("Copy Image (⇧⌘C)")
                Button { model.save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                    .help("Save to the save folder (⌘S)")
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.accessoryBar)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.xs)
        .frame(height: BottomBar.height)
        // Opaque, like a window's status bar: inside a behind-window material the drag
        // handle's fill couldn't blend with what's under it (it measured 1:1 in dark mode).
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Drag this into another app to drop the edited image there.
struct DragHandle: NSViewRepresentable {
    let model: EditorModel

    func makeNSView(context: Context) -> DragHandleView {
        let view = DragHandleView()
        view.model = model
        return view
    }

    func updateNSView(_ view: DragHandleView, context: Context) { view.model = model }
}

@MainActor
final class DragHandleView: NSView, NSDraggingSource {
    weak var model: EditorModel?
    private var downAt: CGPoint?
    private let label = NSTextField(labelWithString: "Drag Out")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        let icon = NSImageView(image: NSImage(systemSymbolName: "hand.draw", accessibilityDescription: nil)!)
        icon.contentTintColor = .secondaryLabelColor
        let stack = NSStackView(views: [icon, label])
        stack.spacing = Spacing.xs
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: centerXAnchor), stack.centerYAnchor.constraint(equalTo: centerYAnchor)])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Drag out the image")
        toolTip = "Drag the edited image into another app"
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidChangeEffectiveAppearance() { updateColors() }
    override var wantsUpdateLayer: Bool { true }
    /// AppKit calls this with the view's appearance current, after any appearance change.
    override func updateLayer() { updateColors() }
    /// A capsule whatever height it's given.
    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }
    /// Layer colours don't follow the appearance by themselves: resolve them in this view's.
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        }
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) { downAt = event.locationInWindow }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downAt, let model else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 3 else { return }
        downAt = nil
        guard let url = model.fileForDrag() else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let image = NSImage(contentsOf: url) ?? NSImage()
        let size = CGSize(width: 120, height: 120 * max(image.size.height, 1) / max(image.size.width, 1))
        item.setDraggingFrame(CGRect(origin: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), size: size), contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy] : []
    }
}

/// The Background tool: none, gradients, plain colors, padding, corners and shadow.
struct BackgroundPanel: View {
    @Bindable var model: EditorModel
    @Environment(\.controlActiveState) private var activeState
    private var background: CaptureBackground? { model.editor.document.background }

    /// Four swatches across, `Spacing.l` margins: 4 × 40 + 3 × 8 + 2 × 16.
    static let swatchSide: CGFloat = 40
    static let columnsCount = 4
    static let width = CGFloat(columnsCount) * swatchSide + CGFloat(columnsCount - 1) * Spacing.s + 2 * Spacing.l
    private let columns = Array(repeating: GridItem(.fixed(BackgroundPanel.swatchSide), spacing: Spacing.s), count: BackgroundPanel.columnsCount)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Button { model.setBackground(nil) } label: {
                    Text("None").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(background == nil)
                section("Gradients") {
                    ForEach(GradientPreset.allCases) { preset in
                        swatch(selected: background?.fill == .gradient(preset), label: "Gradient, \(preset.title)") {
                            LinearGradient(colors: [Color(cgColor: preset.colors.0.cgColor), Color(cgColor: preset.colors.1.cgColor)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        } action: { pick(.gradient(preset)) }
                    }
                }
                section("Plain Colors") {
                    ForEach(Array(CaptureBackground.solidColors.enumerated()), id: \.offset) { index, color in
                        swatch(selected: background?.fill == .solid(RGBAValue(color)), label: "Color, \(CaptureBackground.solidColorNames[index])") {
                            Color(cgColor: color.cgColor)
                        } action: { pick(.solid(RGBAValue(color))) }
                    }
                }
                VStack(alignment: .leading, spacing: Spacing.m) {
                    slider("Padding", value: \.padding, range: CaptureBackground.paddingRange, unit: "pt")
                    slider("Corners", value: \.cornerRadius, range: CaptureBackground.cornerRange, unit: "pt")
                    slider("Shadow", value: \.shadow, range: 0...1, unit: "%")
                }
            }
            .padding(Spacing.l)
        }
        .background(.background.secondary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Background")
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title).font(.headline)
            LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.s) { content() }
        }
    }

    private func pick(_ fill: CaptureBackground.Fill) {
        var style = background ?? CaptureBackground()
        style.fill = fill
        model.setBackground(style)
    }

    /// A rounded swatch with a one-pixel edge; the selected one gets an accent ring just
    /// outside it, concentric with its corners.
    private func swatch<Fill: View>(selected: Bool, label: String, @ViewBuilder fill: () -> Fill, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
        let ring = Spacing.xs // 2 pt ring, 2 pt clear of the swatch
        return Button(action: action) {
            fill()
                .frame(width: Self.swatchSide, height: Self.swatchSide)
                .clipShape(shape)
                .hairlineBorder(shape)
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: Radius.m + ring, style: .continuous)
                            .strokeBorder(Color.selectionRing(activeState), lineWidth: 2)
                            .padding(-ring)
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func slider(_ title: String, value: WritableKeyPath<CaptureBackground, CGFloat>, range: ClosedRange<CGFloat>, unit: String) -> some View {
        let current = background?[keyPath: value] ?? range.lowerBound
        let shown = unit == "%" ? "\(Int((current * 100).rounded())) %" : "\(Int(current.rounded())) pt"
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer()
                Text(background == nil ? "–" : shown)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            Slider(value: Binding(get: { current },
                                  set: { newValue in model.adjustBackground(editing: true) { $0[keyPath: value] = newValue } }),
                   in: range) { editing in
                if !editing { model.adjustBackground(editing: false) { _ in } }
            }
            .controlSize(.small)
            .accessibilityLabel(title)
            .accessibilityValue(background == nil ? "Off" : shown)
        }
        .disabled(background == nil)
    }
}

/// Standard pop-up menus, so VoiceOver always reads "Color, Blue" / "Line Width, Thick"
/// (label and current value), whatever state the toolbar is in.
struct ColorMenu: View {
    @Bindable var model: EditorModel

    // A menu showing just the current swatch (a pop-up button in the toolbar reserved room
    // for a title it never drew), with the colors as a checkmarked list inside.
    var body: some View {
        Menu {
            Picker("Color", selection: Binding(get: { model.color }, set: { model.pickColor($0) })) {
                ForEach(PaletteColor.all) { color in
                    Label { Text(color.name) } icon: { Image(nsImage: Swatch.image(color.color, selected: false)) }
                        .tag(color)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label { Text("Color") } icon: { Image(nsImage: Swatch.image(model.color.color, selected: false)) }
                .labelStyle(.iconOnly)
        }
        .menuIndicator(.visible)
        .fixedSize()
        .help("Color")
        .accessibilityLabel("Color")
        .accessibilityValue(model.color.name)
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

struct RedactionMenu: View {
    @Bindable var model: EditorModel

    var body: some View {
        Picker("Redaction", selection: Binding(get: { model.redaction }, set: { model.pickRedaction($0) })) {
            ForEach(RedactionStyle.allCases) { style in
                Text(style.title).tag(style)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help("Pixelate or blur")
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
    private var editor: EditorModel? { card == nil && pin == nil && history == nil ? EditorWindowController.front : nil }
    /// The Capture History window, when it's in front: file commands act on its selection.
    @MainActor private var history: HistoryViewState? { HistoryWindowController.keyState }
    private var pin: PinPanel? { NSApp.keyWindow as? PinPanel }
    /// A thumbnail that was clicked (key): file commands act on it.
    @MainActor private var card: CaptureItem? { AppModel.shared.cards.item(for: NSApp.keyWindow) }
    @MainActor private var app: AppModel { AppModel.shared }

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { if history != nil { NSApp.keyWindow?.undoManager?.undo() } else { editor?.undo() } }
                .keyboardShortcut("z")
            Button("Redo") { if history != nil { NSApp.keyWindow?.undoManager?.redo() } else { editor?.redo() } }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .saveItem) {
            Button("Close") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w")
            Divider()
            Button("Save") {
                if let card { app.save(card) } else if let pin { app.pins.save(pin) } else if let history { history.save() } else { editor?.save() }
            }
                .keyboardShortcut("s")
            Button("Save As…") { if let card { app.saveAs(card) } else if let history { history.saveAs() } else { editor?.saveAs() } }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Copy Image") {
                if let card { app.copy(card) } else if let pin { app.pins.copy(pin) } else if let history { history.copy() } else { editor?.copy() }
            }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Copy Text in Image") { if let card { app.copyText(card) } else { editor?.copyText() } }
            Button("Pin to Screen") { if let card { app.pin(card) } else if let history { history.pin() } else { editor?.pin() } }
                .keyboardShortcut("p", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .printItem) {
            Button("Print…") { editor?.print() }
                .keyboardShortcut("p")
        }
        CommandGroup(after: .pasteboard) {
            Button("Duplicate") { editor?.duplicate() }
                .keyboardShortcut("d")
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
            Button { editor?.toggleBackground() } label: { Text("Background"); Text("Press B") }
            Divider()
            Menu("Color") {
                ForEach(PaletteColor.all) { color in
                    Button(color.name) { editor?.pickColor(color) }
                }
            }
            Menu("Blur and Pixelate Style") {
                ForEach(RedactionStyle.allCases) { style in
                    Button(style.title) { editor?.pickRedaction(style) }
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
        // Each tool's single-key shortcut under its name (SwiftUI drops a menu button's
        // second line, and a real key equivalent would fire while typing text).
        let letters = Dictionary(Tool.allCases.map { ($0.title, String($0.key).uppercased()) }, uniquingKeysWith: { a, _ in a })
            .merging(["Background": "B"]) { a, _ in a }
        if #available(macOS 14.4, *) {
            for item in menu.items where item.submenu == nil {
                if let letter = letters[item.title] { item.subtitle = "Press \(letter)" }
            }
        }
        guard let editor = EditorWindowController.front else { return }
        let marked = [editor.tool.title, editor.color.name, editor.width.title, editor.redaction.title]
        for item in menu.items where item.submenu == nil {
            item.state = marked.contains(item.title) ? .on : .off
        }
    }

    /// Tooltips on the title bar's tool segments ("Arrow (A)"): SwiftUI doesn't pass a
    /// segment's help on to the segmented control.
    static func installToolTips(in window: NSWindow?) {
        DispatchQueue.main.async {
            guard let window else { return }
            func controls(in view: NSView) -> [NSSegmentedControl] {
                ((view as? NSSegmentedControl).map { [$0] } ?? []) + view.subviews.flatMap(controls)
            }
            // The toolbar lives in the title bar's own view tree (the theme frame).
            let roots = [window.contentView?.superview, window.standardWindowButton(.closeButton)?.superview?.superview].compactMap { $0 }
                + (window.toolbar?.items.compactMap(\.view) ?? [])
            for control in roots.flatMap(controls) where control.segmentCount == ToolPicker.tools.count {
                for (index, tool) in ToolPicker.tools.enumerated() {
                    control.setToolTip("\(tool.title) (\(String(tool.key).uppercased()))", forSegment: index)
                }
            }
        }
    }
}
