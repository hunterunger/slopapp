import AppKit
import SwiftUI
import IconsmithCore
import Observation
import SlopKit
import UniformTypeIdentifiers

/// Everything the window shows and does. One per app (single window).
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    // MARK: State

    /// Every picture loaded (more than one is a batch: one template, exported for each).
    private(set) var sources: [IconSource] = []
    private(set) var index = 0
    var source: IconSource? { sources.indices.contains(index) ? sources[index] : nil }
    private(set) var isLoading = false
    /// Create icons, or restore standard icons (the bottom tabs).
    var mode: Mode = .create
    /// Popovers, so menu commands can open them too.
    var showsAdjust = false
    var showsText = false
    var showsExport = false
    private(set) var isRemovingBackground = false
    /// Apps waiting for a yes before their icon changes.
    var pendingApps: PendingApps?
    var style = IconStyle() {
        didSet {
            guard style != oldValue else { return }
            rememberStyle()
            // Thumbnails show every shape, so a shape change alone doesn't redraw them.
            if style.shape == oldValue.shape { thumbnailsDirty = true }
            scheduleRender()
        }
    }
    var prefs: IconsmithPreferences {
        didSet { if prefs != oldValue { store.save(prefs) } }
    }

    /// The big preview and the small sizes (keyed by points), drawn at the screen's scale.
    private(set) var preview: CGImage?
    private(set) var smallPreviews: [Int: CGImage] = [:]
    private(set) var thumbnails: [IconShape: CGImage] = [:]

    /// Results of the last apply/remove/undo, one row per item.
    private(set) var results: [TargetResult] = []
    private(set) var resultSummary: String?
    /// The results on show come from an undo (so the hint offers redo).
    private(set) var resultsAreUndo = false
    /// Whether the results can be undone (something changed), so the hint isn't offered for nothing.
    private(set) var resultsCanUndo = false
    private(set) var isExporting = false
    /// A save or open panel is up; menu commands that would open another wait.
    private(set) var isPresentingPanel = false
    var error: ErrorReport?
    /// Shown after an export that had to change something (e.g. filled transparency).
    private(set) var exportStatus: ExportStatus?
    /// What Edit ▸ Undo / Redo show; refreshed from the undo manager's notifications.
    private(set) var undoState = UndoState()

    static let smallSizes = [64, 32, 16]
    /// Gallery thumbnails, in points.
    static let thumbnailPoints: CGFloat = 64
    /// One arrow-key nudge: 4 px on a 1024 px icon.
    static let nudgeStep = 1.0 / 256

    // MARK: Plumbing

    /// Our own undo stack, so ⌘Z works whichever of our windows is in front (or none).
    @ObservationIgnored let undoManager = UndoManager()
    /// Undo targets: editor edits (dropped when a new picture loads) and icon changes (kept).
    @ObservationIgnored private let editTarget = NSObject()
    @ObservationIgnored private let iconTarget = NSObject()
    @ObservationIgnored var backingScale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2
    @ObservationIgnored private let store = PreferencesStore()
    @ObservationIgnored private lazy var applier = IconApplier(system: WorkspaceFileIcons(), allowedRoot: IconApplier.allowedRoot())
    @ObservationIgnored private lazy var folderArt = FolderArt.system()
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var editStart: IconStyle?
    @ObservationIgnored private var editName = "Change Icon"
    @ObservationIgnored private var thumbnailsDirty = true
    /// Cut-outs and the pictures they came from (Restore Background).
    @ObservationIgnored private var cutoutOriginals: [UUID: IconSource] = [:]
    /// What the gallery shows before a picture is loaded: a generic picture glyph. It's drawn
    /// into the icon (often on the white Automatic tile), off the main thread, so it uses a mid
    /// grey that reads on white and on a dark window alike; `secondaryLabelColor` resolved to
    /// light grey in dark mode and vanished on the white tile.
    @ObservationIgnored private let placeholder: IconSource? = {
        let config = NSImage.SymbolConfiguration(pointSize: 256, weight: .regular)
            .applying(.init(paletteColors: [.systemGray]))
        guard let symbol = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)?.withSymbolConfiguration(config)
        else { return IconSource.blank() }
        return IconSource(content: .vector(symbol), name: "", url: nil, size: symbol.size)
    }()

    private init() {
        prefs = store.load()
        style = IconStyle(shape: prefs.shape, background: prefs.background, color: prefs.color)
        let center = NotificationCenter.default
        for name in [Notification.Name.NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            center.addObserver(forName: name, object: undoManager, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshUndoState() }
            }
        }
    }

    private func refreshUndoState() {
        undoState = UndoState(canUndo: undoManager.canUndo, canRedo: undoManager.canRedo,
                              undoTitle: undoManager.undoMenuItemTitle, redoTitle: undoManager.redoMenuItemTitle)
    }

    func undo() { if undoManager.canUndo { undoManager.undo() } }
    func redo() { if undoManager.canRedo { undoManager.redo() } }

    var renderer: IconRenderer? {
        source.map { IconRenderer(source: $0, folder: folderArt) }
    }

    var hasSource: Bool { source != nil }
    var isBatch: Bool { sources.count > 1 }

    // MARK: Loading

    /// Image types offered by Open (anything else dropped still works: its icon is used).
    static let openTypes: [UTType] = [.image, .pdf, .svg, .icns, .application]

    func load(_ url: URL) { load([url]) }

    /// Loads one picture, or several as a batch. Replaces what was loaded.
    func load(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        loadTask?.cancel()
        isLoading = true
        mode = .create
        loadTask = Task {
            let results = await Task.detached(priority: .userInitiated) {
                urls.map { url in Result { try SourceLoader.load(url) } }
            }.value
            guard !Task.isCancelled else { return }
            isLoading = false
            let loaded = results.compactMap { try? $0.get() }
            if !loaded.isEmpty { setSources(loaded) }
            if let failure = results.lazy.compactMap({ result -> Error? in
                if case .failure(let error) = result { return error } else { return nil }
            }).first {
                self.error = ErrorReport(loaded.isEmpty ? "Couldn’t Open the Picture" : "Some Pictures Couldn’t Open", failure)
            }
        }
    }

    private func setSource(_ newSource: IconSource) { setSources([newSource]) }

    private func setSources(_ newSources: [IconSource]) {
        sources = newSources
        index = 0
        cutoutOriginals = [:]
        mode = .create
        exportStatus = nil
        resetPlacement()
        // Undo history for the old picture's edits doesn't apply to the new one.
        undoManager.removeAllActions(withTarget: editTarget)
        refreshUndoState()
    }

    /// Placement that suits the current picture (size, fit, centred); the template stays.
    private func resetPlacement() {
        guard let source else { return }
        let defaults = IconStyle.placementDefaults(transparentEdges: source.edges.isTransparent)
        thumbnails = [:]
        var fresh = style
        fresh.scale = defaults.scale
        fresh.fill = defaults.fill
        fresh.offset = .zero
        fresh.rotation = 0
        thumbnailsDirty = true
        if style == fresh { scheduleRender() } else { style = fresh }
    }

    /// Shows another picture of the batch. The template, colour and text stay.
    func select(_ newIndex: Int) {
        guard sources.indices.contains(newIndex), newIndex != index else { return }
        index = newIndex
        thumbnailsDirty = true
        scheduleRender()
    }

    /// A blank picture: an icon made of its template, colour and text.
    func newBlank() {
        guard let blank = IconSource.blank() else { return }
        setSource(blank)
        if !style.shape.isFolder && !style.shape.hasOutline { edit("Change Shape") { $0.shape = .folder } }
    }

    func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.openTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a picture to make an icon from"
        if let folder = source?.folder { panel.directoryURL = folder }
        present(panel) { [weak self] in self?.load(panel.urls) }
    }

    /// ⌘V: an image file on the clipboard, or image data (copied from a browser or Preview).
    func paste() {
        let pasteboard = AppPasteboard.current
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first {
            load(url)
            return
        }
        guard let image = NSImage(pasteboard: pasteboard) else {
            error = ErrorReport("Nothing to Paste", SourceError.noImageOnClipboard)
            return
        }
        do { setSource(try SourceLoader.load(image: image)) } catch { self.error = ErrorReport("Nothing to Paste", error) }
    }

    var canPaste: Bool {
        AppPasteboard.current.canReadObject(forClasses: [NSURL.self, NSImage.self], options: nil)
    }

    func closeImage() {
        sources = []
        index = 0
        cutoutOriginals = [:]
        preview = nil
        smallPreviews = [:]
        thumbnails = [:]
        thumbnailsDirty = true
        exportStatus = nil
        undoManager.removeAllActions(withTarget: editTarget)
        refreshUndoState()
        scheduleRender()
    }

    // MARK: Background removal

    var canRestoreBackground: Bool { source.map { cutoutOriginals[$0.id] != nil } ?? false }

    /// Lifts the subject off its background (Vision, on this Mac). Undoable.
    func removeBackground() {
        guard let source, !isRemovingBackground, !source.isBlank else { return }
        isRemovingBackground = true
        let at = index
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try Cutout.make(from: source, remover: VisionBackgroundRemover()) }
            }.value
            isRemovingBackground = false
            switch result {
            case .success(let cut):
                guard sources.indices.contains(at), sources[at].id == source.id else { return }
                cutoutOriginals[cut.id] = source
                swapSource(at: at, to: cut, from: source, name: "Remove Background")
            case .failure(let error):
                self.error = ErrorReport("Couldn’t Remove the Background", error)
            }
        }
    }

    func restoreBackground() {
        guard let source, let original = cutoutOriginals[source.id] else { return }
        swapSource(at: index, to: original, from: source, name: "Restore Background")
    }

    /// Replaces one picture of the batch; undo swaps it back (and redo again).
    private func swapSource(at position: Int, to new: IconSource, from old: IconSource, name: String, style target: IconStyle? = nil) {
        guard sources.indices.contains(position) else { return }
        closeContinuousEdit()
        let previousStyle = style
        sources[position] = new
        thumbnailsDirty = true
        // A cut-out is placed like a logo (whole, with a margin).
        var placed = target ?? style
        if target == nil { placed.fill = IconStyle.placementDefaults(transparentEdges: new.edges.isTransparent).fill }
        if placed != style { style = placed } else { scheduleRender() }
        undoManager.registerUndo(withTarget: editTarget) { [weak self] _ in
            MainActor.assumeIsolated { self?.swapSource(at: position, to: old, from: new, name: name, style: previousStyle) }
        }
        undoManager.setActionName(name)
    }

    // MARK: Style edits (undoable)

    /// A one-step change (menu, picker, button).
    func edit(_ actionName: String, _ change: (inout IconStyle) -> Void) {
        closeContinuousEdit()
        let old = style
        var new = style
        change(&new)
        new = new.clamped()
        guard new != old else { return }
        style = new
        registerStyleUndo(old, actionName)
    }

    /// Fit or Fill, from the panel and the Icon menu.
    func setFill(_ fill: Bool) { edit("Change Framing") { $0.fill = fill } }

    /// Continuous changes (slider, drag): one undo step for the whole gesture.
    func beginContinuousEdit(_ actionName: String = "Change Icon") {
        if editStart == nil {
            editStart = style
            editName = actionName
        }
    }

    func endContinuousEdit(_ actionName: String? = nil) {
        guard let start = editStart else { return }
        editStart = nil
        if start != style { registerStyleUndo(start, actionName ?? editName) }
    }

    /// Ends a gesture still in progress (typing, a slider) so the next step undoes separately.
    private func closeContinuousEdit() { endContinuousEdit() }

    /// Changes during a gesture (slider drag, typing): one undo step until it ends.
    func change(_ actionName: String, _ change: (inout IconStyle) -> Void) {
        beginContinuousEdit(actionName)
        var new = style
        change(&new)
        style = new.clamped()
    }

    @ObservationIgnored private var settleTask: Task<Void, Never>?

    /// Like `change`, for controls with no "done" moment (the colour panel, typing): the
    /// undo step closes after a short pause.
    func changeSettling(_ actionName: String, _ change: (inout IconStyle) -> Void) {
        self.change(actionName, change)
        settleTask?.cancel()
        settleTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            endContinuousEdit()
        }
    }

    private func registerStyleUndo(_ old: IconStyle, _ actionName: String) {
        ReversibleEdit.register(undoManager, target: editTarget, name: actionName, from: old, to: style) { [weak self] in
            self?.style = $0
        }
    }

    func setShape(_ shape: IconShape) { edit("Change Shape") { $0.shape = shape } }
    func resetPosition() { edit("Re-center") { $0.offset = .zero } }
    func rotate(by degrees: Double) {
        edit("Rotate") { style in
            var r = style.rotation + degrees
            while r > 180 { r -= 360 }
            while r < -180 { r += 360 }
            style.rotation = r
        }
    }

    /// Size, position and rotation back to how the picture first appeared; template,
    /// colour and text stay.
    func resetAdjustments() {
        guard let source else { return }
        let defaults = IconStyle.placementDefaults(transparentEdges: source.edges.isTransparent)
        edit("Reset Adjustments") {
            $0.scale = defaults.scale
            $0.fill = defaults.fill
            $0.offset = .zero
            $0.rotation = 0
        }
    }

    func removeText() { edit("Remove Text") { $0.text.string = "" } }

    func resetSize() {
        guard let source else { return }
        edit("Reset Size") { $0.scale = IconStyle.placementDefaults(transparentEdges: source.edges.isTransparent).scale }
    }

    func nudge(dx: Double, dy: Double) {
        edit("Move Picture") { $0.offset = CGPoint(x: $0.offset.x + dx, y: $0.offset.y + dy) }
    }

    func zoom(by factor: Double) {
        edit("Change Size") { $0.scale = ($0.scale * factor * 20).rounded() / 20 }
    }

    private func rememberStyle() {
        var p = prefs
        p.shape = style.shape
        p.background = style.background
        p.color = style.color
        prefs = p
    }

    // MARK: Rendering

    func scheduleRender() {
        guard let renderer else {
            renderPlaceholderThumbnails()
            return
        }
        let withThumbnails = thumbnailsDirty
        renderTask?.cancel()
        let style = style, scale = backingScale
        let previewPixels = 1024
        renderTask = Task {
            let output = await PreviewRenderer.shared.render(renderer, style: style, previewPixels: previewPixels,
                                                             smallSizes: Self.smallSizes, scale: scale,
                                                             thumbnails: withThumbnails ? Int(Self.thumbnailPoints * scale) : nil)
            guard !Task.isCancelled, let output else { return }
            preview = output.preview
            smallPreviews = output.small
            if withThumbnails {
                thumbnails = output.thumbnails
                thumbnailsDirty = false
            }
        }
    }

    /// With nothing loaded, the gallery shows each template empty, so a template can be
    /// picked before the picture.
    private func renderPlaceholderThumbnails() {
        guard let placeholder, thumbnails.isEmpty || thumbnailsDirty else { return }
        let renderer = IconRenderer(source: placeholder, folder: folderArt)
        var style = style
        style.text = IconText()
        let scale = backingScale
        renderTask?.cancel()
        renderTask = Task {
            let output = await PreviewRenderer.shared.render(renderer, style: style, previewPixels: 0, smallSizes: [], scale: scale,
                                                             thumbnails: Int(Self.thumbnailPoints * scale))
            guard !Task.isCancelled, let output, source == nil else { return }
            thumbnails = output.thumbnails
            thumbnailsDirty = false
        }
    }

    // MARK: Export

    /// Exports with a save panel; `all` exports every picture of a batch into one folder.
    func export(_ format: ExportFormat? = nil, all: Bool = false) {
        guard let source, renderer != nil, !isExporting, !isPresentingPanel else { return }
        let format = format ?? prefs.format
        if format != prefs.format { prefs.format = format }
        if format == .xcode, prefs.options.xcodePlatforms.isEmpty {
            error = ErrorReport("Choose a Platform", ExportError.noPlatforms)
            return
        }
        if all && isBatch {
            exportBatch(format)
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export Icon"
        panel.prompt = "Export"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.canSelectHiddenExtension = false
        configure(panel, for: format, source: source, initial: true)
        let accessory = NSHostingView(rootView: ExportAccessory(model: self) { [weak self, weak panel] newFormat in
            guard let self, let panel else { return }
            self.configure(panel, for: newFormat, source: source)
        })
        accessory.sizingOptions = [.intrinsicContentSize]
        panel.accessoryView = accessory
        panel.directoryURL = source.folder
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        present(panel) { [weak self] in
            guard let self, let url = panel.url else { return }
            let chosen = self.prefs.format
            if chosen == .xcode, self.prefs.options.xcodePlatforms.isEmpty {
                self.error = ErrorReport("Choose a Platform", ExportError.noPlatforms)
                return
            }
            self.write(chosen, to: url)
        }
    }

    /// Points the save panel at a format: its file type and a matching name.
    private func configure(_ panel: NSSavePanel, for format: ExportFormat, source: IconSource, initial: Bool = false) {
        let base = source.name, sourceName = source.url?.lastPathComponent
        // Folder formats get their extension from ExportWriter; a save panel given a
        // folder-ish type appends the extension a second time.
        if !format.isFolder, let ext = format.pathExtension, let type = UTType(filenameExtension: ext) {
            panel.allowedContentTypes = [type]
            panel.allowsOtherFileTypes = false
        } else {
            panel.allowedContentTypes = []
            panel.allowsOtherFileTypes = true
        }
        // Keep what the user typed, swap only the part that names the format.
        let typed = panel.nameFieldStringValue
        let untouched = initial || typed.isEmpty || ExportFormat.allCases.contains { typed == $0.suggestedName(base: base, source: sourceName) }
        if untouched || format == .xcode {
            panel.nameFieldStringValue = format.suggestedName(base: base, source: sourceName)
        } else {
            let stem = format.isFolder || ExportFormat.allCases.contains(where: { $0.pathExtension == URL(fileURLWithPath: typed).pathExtension.lowercased() })
                ? URL(fileURLWithPath: typed).deletingPathExtension().lastPathComponent : typed
            panel.nameFieldStringValue = format.suggestedName(base: stem, source: sourceName)
        }
    }

    private func write(_ format: ExportFormat, to url: URL) {
        guard let renderer else { return }
        let style = style, options = prefs.options, reveal = prefs.revealAfterExport
        isExporting = true
        exportStatus = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<(URL, [String]), Error> in
                Result {
                    let plan = try IconExporter(renderer: renderer).plan(format, style: style, options: options)
                    let written = try ExportWriter(trash: Trash.current()).write(plan, format: format, to: url)
                    return (written, plan.notes)
                }
            }.value
            isExporting = false
            switch result {
            case .success(let (written, notes)):
                if format == .folder, let failure = giveIcon(renderer, style: style, toNewFolder: written) {
                    self.error = ErrorReport("Couldn’t Export the Icon", ExportError.write(failure))
                    return
                }
                exportStatus = ExportStatus(url: written, notes: notes, hasHTML: format == .favicons)
                HUD.show("Exported", systemImage: "checkmark.circle")
                // Finder reuses a window already showing the folder.
                if reveal { NSWorkspace.shared.activateFileViewerSelecting([written]) }
            case .failure(let error):
                self.error = ErrorReport("Couldn’t Export the Icon", error)
            }
        }
    }

    func writeForDebug(_ format: ExportFormat, to url: URL) { write(format, to: url) }
    func writeBatchForDebug(_ format: ExportFormat, into folder: URL) { writeBatch(format, into: folder) }

    /// Gives a just-exported empty folder the icon. Returns why it failed (the folder is
    /// then removed again).
    private func giveIcon(_ renderer: IconRenderer, style: IconStyle, toNewFolder folder: URL) -> String? {
        let change = applier.apply(renderer.multiResolutionImage(style), to: [folder])
        guard let result = change.results.first, result.outcome != .applied else { return nil }
        try? FileManager.default.removeItem(at: folder)
        return result.outcome.message
    }

    /// Every picture of the batch, same template, into one chosen folder.
    private func exportBatch(_ format: ExportFormat) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export \(sources.count) Icons"
        panel.message = "Choose where to save \(format.title) for each of the \(sources.count) pictures"
        panel.directoryURL = source?.folder ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        present(panel) { [weak self] in
            guard let self, let folder = panel.url else { return }
            self.writeBatch(format, into: folder)
        }
    }

    private func writeBatch(_ format: ExportFormat, into folder: URL) {
        let renderers = sources.map { IconRenderer(source: $0, folder: folderArt) }
        let style = style, options = prefs.options, reveal = prefs.revealAfterExport
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let names = BatchNaming.names(for: sources.map(\.name), format: format, existing: existing)
        isExporting = true
        exportStatus = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<([URL], [String]), Error> in
                Result {
                    var written: [URL] = [], notes: [String] = []
                    for (renderer, name) in zip(renderers, names) {
                        let plan = try IconExporter(renderer: renderer).plan(format, style: style, options: options)
                        written.append(try ExportWriter(trash: Trash.current()).write(plan, format: format, to: folder.appending(path: name)))
                        for note in plan.notes where !notes.contains(note) { notes.append(note) }
                    }
                    return (written, notes)
                }
            }.value
            isExporting = false
            switch result {
            case .success(let (written, notes)):
                if format == .folder {
                    for (renderer, url) in zip(renderers, written) {
                        if let failure = giveIcon(renderer, style: style, toNewFolder: url) {
                            self.error = ErrorReport("Couldn’t Export the Icons", ExportError.write(failure))
                            return
                        }
                    }
                }
                exportStatus = ExportStatus(url: folder, notes: notes, hasHTML: format == .favicons, count: written.count)
                HUD.show("Exported \(written.count) Icons", systemImage: "checkmark.circle")
                if reveal { NSWorkspace.shared.activateFileViewerSelecting(written) }
            case .failure(let error):
                self.error = ErrorReport("Couldn’t Export the Icons", error)
            }
        }
    }

    // MARK: Drag out

    @ObservationIgnored private var lastDragFolder: URL?

    /// The icon as a file for dragging to Finder or another app: .icns, or PNG with ⌥.
    /// Written when the drag starts (a few dozen milliseconds).
    func dragItem() -> NSItemProvider {
        guard let renderer, let source else { return NSItemProvider() }
        let format: ExportFormat = NSEvent.modifierFlags.contains(.option) ? .png : .icns
        let fm = FileManager.default
        if let old = lastDragFolder { try? fm.removeItem(at: old) }
        let folder = fm.temporaryDirectory.appending(path: "Iconsmith Drag/\(UUID().uuidString)")
        lastDragFolder = folder
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var options = prefs.options
            options.pngSize = 1024
            let plan = try IconExporter(renderer: renderer).plan(format, style: style, options: options)
            let url = try ExportWriter().write(plan, format: format, to: folder.appending(path: format.suggestedName(base: source.name)))
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        } catch {
            return NSItemProvider()
        }
    }

    /// The favicon `<link>` tags, for the page's `<head>`.
    func copyFaviconHTML() {
        let pasteboard = AppPasteboard.current
        pasteboard.clearContents()
        pasteboard.setString(IconExporter.faviconHTML, forType: .string)
        HUD.show("HTML Copied", systemImage: "doc.on.doc")
    }

    /// ⌘C: the icon as a 1024 px PNG.
    func copyIcon() {
        guard let renderer, let image = renderer.render(style, pixels: 1024), let png = Bitmap.pngData(image) else { return }
        let pasteboard = AppPasteboard.current
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        pasteboard.setData(NSBitmapImageRep(cgImage: image).tiffRepresentation, forType: .tiff)
        HUD.show("Copied", systemImage: "doc.on.doc")
    }

    // MARK: Finder icons

    func chooseTargets(remove: Bool) {
        guard remove || hasSource else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = remove ? "Remove Icons" : "Apply Icon"
        // Scripted runs fenced to a folder start there.
        if let root = IconApplier.allowedRoot() { panel.directoryURL = root }
        panel.message = remove
            ? "Choose files, folders or disks to give back their standard icons"
            : "Choose files, folders or disks to give this icon"
        present(panel) { [weak self] in
            guard let self else { return }
            remove ? self.removeIcons(from: panel.urls) : self.applyIcon(to: panel.urls)
            if remove { self.mode = .restore }
        }
    }

    /// Gives items this icon. Apps are asked about first (their updates undo it, and it's
    /// easy to drop one meaning "use its icon").
    func applyIcon(to urls: [URL], fromDrop: Bool = false) {
        guard renderer != nil, !urls.isEmpty else { return }
        let apps = urls.filter(Self.isApp)
        let others = urls.filter { !Self.isApp($0) }
        if !others.isEmpty { performApply(others) }
        if !apps.isEmpty { pendingApps = PendingApps(apps: apps, fromDrop: fromDrop) }
    }

    func confirmApps(_ pending: PendingApps) {
        pendingApps = nil
        performApply(pending.apps)
    }

    func useAppIcon(_ pending: PendingApps) {
        pendingApps = nil
        load(pending.apps)
    }

    private func performApply(_ urls: [URL]) {
        guard let renderer else { return }
        let image = renderer.multiResolutionImage(style)
        record(applier.apply(image, to: urls), actionName: "Apply Icon")
    }

    /// A drop on the icon: pictures replace the picture; files, folders, disks and apps get
    /// the icon. With ⌥, everything gets the icon (pictures too).
    func dropOnCanvas(_ urls: [URL]) {
        let everything = NSEvent.modifierFlags.contains(.option)
        let pictures = urls.filter(Self.isPicture)
        if !everything, !pictures.isEmpty, pictures.count == urls.count {
            load(pictures)
            return
        }
        applyIcon(to: everything ? urls : urls.filter { !Self.isPicture($0) }, fromDrop: true)
    }

    static func isPicture(_ url: URL) -> Bool {
        guard let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? UTType(filenameExtension: url.pathExtension)
        else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf) || type.conforms(to: .svg)
    }

    static func isApp(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .application) ?? (url.pathExtension == "app")
    }

    func openAppManagementSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles") {
            NSWorkspace.shared.open(url)
        }
    }

    func removeIcons(from urls: [URL]) {
        guard !urls.isEmpty else { return }
        record(applier.remove(from: urls), actionName: "Remove Custom Icon")
    }

    private func record(_ change: IconChange, actionName: String) {
        results = change.results
        resultSummary = change.summary
        resultsAreUndo = false
        resultsCanUndo = change.changedCount > 0
        if change.changedCount > 0 { registerIconUndo(change, actionName: actionName, undoing: true) }
    }

    private func registerIconUndo(_ change: IconChange, actionName: String, undoing: Bool) {
        undoManager.registerUndo(withTarget: iconTarget) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let model = self else { return }
                let restored = model.applier.restore(change, toBefore: undoing)
                model.results = restored
                let ok = restored.filter(\.outcome.isSuccess).count
                model.resultSummary = undoing ? "Put back \(ok) icon\(ok == 1 ? "" : "s")" : change.summary
                model.resultsAreUndo = undoing
                model.resultsCanUndo = true
                model.registerIconUndo(change, actionName: actionName, undoing: !undoing)
            }
        }
        undoManager.setActionName(actionName)
    }

    func clearResults() {
        results = []
        resultSummary = nil
    }

    // MARK: Helpers

    /// Shows a panel as a sheet on the main window (or on its own when there's none).
    private func present(_ panel: NSSavePanel, onOK: @escaping @MainActor () -> Void) {
        guard !isPresentingPanel else { return }
        isPresentingPanel = true
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            MainActor.assumeIsolated {
                self?.isPresentingPanel = false
                if response == .OK { onOK() }
            }
        }
        if let window = MainWindow.current {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    var smallSourceWarning: String? {
        guard let source, source.isSmall else { return nil }
        return "This picture is only \(Int(source.size.width)) × \(Int(source.size.height)) pixels, so large sizes will look soft."
    }
}

@MainActor
enum MainWindow {
    static var current: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "main" && $0.isVisible }
            ?? NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel) && $0.title == "Iconsmith" }
    }
}

/// Renders previews off the main thread, one at a time (NSImage drawing is safest serialized).
actor PreviewRenderer {
    static let shared = PreviewRenderer()

    struct Output: Sendable {
        let preview: CGImage?
        let small: [Int: CGImage]
        let thumbnails: [IconShape: CGImage]
    }

    func render(_ renderer: IconRenderer, style: IconStyle, previewPixels: Int, smallSizes: [Int], scale: CGFloat,
                thumbnails thumbnailPixels: Int?) -> Output? {
        guard !Task.isCancelled else { return nil }
        let preview = previewPixels > 0 ? renderer.render(style, pixels: previewPixels) : nil
        var small: [Int: CGImage] = [:]
        for points in smallSizes {
            guard !Task.isCancelled else { return nil }
            small[points] = renderer.render(style, pixels: Int((CGFloat(points) * scale).rounded()))
        }
        var thumbnails: [IconShape: CGImage] = [:]
        if let thumbnailPixels {
            for shape in IconShape.allCases {
                guard !Task.isCancelled else { return nil }
                var shaped = style
                shaped.shape = shape
                thumbnails[shape] = renderer.render(shaped, pixels: thumbnailPixels)
            }
        }
        return Output(preview: preview, small: small, thumbnails: thumbnails)
    }
}

struct ErrorReport: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    init(_ title: String, _ error: Error) {
        self.title = title
        self.message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

struct UndoState: Equatable {
    var canUndo = false
    var canRedo = false
    var undoTitle = "Undo"
    var redoTitle = "Redo"
}

/// The last export, shown as one line under the Export button.
struct ExportStatus: Equatable {
    let url: URL
    /// Things that changed on the way (e.g. transparency filled with white).
    let notes: [String]
    /// A favicon export: offer to copy the HTML.
    let hasHTML: Bool
    /// More than one: a batch, `url` is the folder.
    var count = 1
}

enum Mode: String, CaseIterable, Identifiable {
    case create, restore
    var id: String { rawValue }
}

/// Apps dropped or chosen as targets, waiting for confirmation.
struct PendingApps: Identifiable {
    let id = UUID()
    let apps: [URL]
    let fromDrop: Bool

    var names: String {
        let names = apps.map { FileManager.default.displayName(atPath: $0.path) }
        return names.count == 1 ? "“\(names[0])”" : "\(names.count) apps"
    }
}

/// The clipboard the app reads and writes. `ICONSMITH_PASTEBOARD=<name>` swaps in a named
/// pasteboard so scripted runs never touch the real clipboard.
@MainActor
enum AppPasteboard {
    static let current: NSPasteboard = {
        if let name = ProcessInfo.processInfo.environment["ICONSMITH_PASTEBOARD"], !name.isEmpty {
            return NSPasteboard(name: NSPasteboard.Name(name))
        }
        return .general
    }()
}
