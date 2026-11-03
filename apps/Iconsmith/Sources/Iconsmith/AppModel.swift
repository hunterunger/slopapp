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

    private(set) var source: IconSource?
    private(set) var isLoading = false
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
    private(set) var isExporting = false
    /// A save or open panel is up; menu commands that would open another wait.
    private(set) var isPresentingPanel = false
    var error: ErrorReport?
    /// Shown after an export that had to change something (e.g. filled transparency).
    private(set) var exportStatus: ExportStatus?
    /// What Edit ▸ Undo / Redo show; refreshed from the undo manager's notifications.
    private(set) var undoState = UndoState()

    static let smallSizes = [128, 32, 16]
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
    @ObservationIgnored private var thumbnailsDirty = true

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

    // MARK: Loading

    /// Image types offered by Open (anything else dropped still works: its icon is used).
    static let openTypes: [UTType] = [.image, .pdf, .svg, .icns, .application]

    func load(_ url: URL) {
        loadTask?.cancel()
        isLoading = true
        loadTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try SourceLoader.load(url) }
            }.value
            guard !Task.isCancelled else { return }
            isLoading = false
            switch result {
            case .success(let source): setSource(source)
            case .failure(let error): self.error = ErrorReport("Couldn’t Open the Picture", error)
            }
        }
    }

    func load(_ urls: [URL]) {
        guard let first = urls.first else { return }
        load(first)
    }

    private func setSource(_ newSource: IconSource) {
        let defaults = IconStyle.placementDefaults(transparentEdges: newSource.edges.isTransparent)
        source = newSource
        exportStatus = nil
        thumbnails = [:]
        var fresh = style
        fresh.scale = defaults.scale
        fresh.fill = defaults.fill
        fresh.offset = .zero
        thumbnailsDirty = true
        if style == fresh { scheduleRender() } else { style = fresh }
        // Undo history for the old picture's edits doesn't apply to the new one.
        undoManager.removeAllActions(withTarget: editTarget)
        refreshUndoState()
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
        source = nil
        preview = nil
        smallPreviews = [:]
        thumbnails = [:]
        exportStatus = nil
        undoManager.removeAllActions(withTarget: editTarget)
        refreshUndoState()
    }

    // MARK: Style edits (undoable)

    /// A one-step change (menu, picker, button).
    func edit(_ actionName: String, _ change: (inout IconStyle) -> Void) {
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
    func beginContinuousEdit() {
        if editStart == nil { editStart = style }
    }

    func endContinuousEdit(_ actionName: String) {
        guard let start = editStart else { return }
        editStart = nil
        if start != style { registerStyleUndo(start, actionName) }
    }

    private func registerStyleUndo(_ old: IconStyle, _ actionName: String) {
        ReversibleEdit.register(undoManager, target: editTarget, name: actionName, from: old, to: style) { [weak self] in
            self?.style = $0
        }
    }

    func setShape(_ shape: IconShape) { edit("Change Shape") { $0.shape = shape } }
    func resetPosition() { edit("Re-center") { $0.offset = .zero } }

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

    private func scheduleRender() {
        guard let renderer else { return }
        let withThumbnails = thumbnailsDirty
        renderTask?.cancel()
        let style = style, scale = backingScale
        let previewPixels = 1024
        renderTask = Task {
            let output = await PreviewRenderer.shared.render(renderer, style: style, previewPixels: previewPixels,
                                                             smallSizes: Self.smallSizes, scale: scale,
                                                             thumbnails: withThumbnails ? 88 : nil)
            guard !Task.isCancelled, let output else { return }
            preview = output.preview
            smallPreviews = output.small
            if withThumbnails {
                thumbnails = output.thumbnails
                thumbnailsDirty = false
            }
        }
    }

    // MARK: Export

    func export(_ format: ExportFormat? = nil) {
        guard let source, renderer != nil, !isExporting, !isPresentingPanel else { return }
        let format = format ?? prefs.format
        if format != prefs.format { prefs.format = format }
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
                exportStatus = ExportStatus(url: written, notes: notes, hasHTML: format == .favicons)
                HUD.show("Exported", systemImage: "checkmark.circle")
                // Finder reuses a window already showing the folder.
                if reveal { NSWorkspace.shared.activateFileViewerSelecting([written]) }
            case .failure(let error):
                self.error = ErrorReport("Couldn’t Export the Icon", error)
            }
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
        }
    }

    func applyIcon(to urls: [URL]) {
        guard let renderer, !urls.isEmpty else { return }
        let image = renderer.multiResolutionImage(style)
        record(applier.apply(image, to: urls), actionName: "Apply Icon")
    }

    func removeIcons(from urls: [URL]) {
        guard !urls.isEmpty else { return }
        record(applier.remove(from: urls), actionName: "Remove Custom Icon")
    }

    private func record(_ change: IconChange, actionName: String) {
        results = change.results
        resultSummary = change.summary
        resultsAreUndo = false
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
        let preview = renderer.render(style, pixels: previewPixels)
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
