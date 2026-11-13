import AppKit
import Observation
import SlopKit
import SnapperCore
import QuickLook
import SwiftUI

/// The Capture History window (library archetype): every kept capture as a thumbnail, grouped
/// by day, newest first; filter by kind, search by app; restore, annotate, pin, copy, save,
/// show, Quick Look, drag out or delete one or many.
@MainActor
final class HistoryWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: HistoryWindowController?
    let state: HistoryViewState

    static var isKey: Bool { shared?.window?.isKeyWindow == true }
    static var keyState: HistoryViewState? { isKey ? shared?.state : nil }
    /// The open window's state and undo manager, key or not (test hooks).
    static var openState: HistoryViewState? { shared?.window?.isVisible == true ? shared?.state : nil }
    static var undoManager: UndoManager? { shared?.window?.undoManager }

    static func show() {
        let controller = shared ?? HistoryWindowController()
        shared = controller
        NSApp.activate()
        controller.window?.makeKeyAndOrderFront(nil)
        Diagnostics.record("history window shown entries=\(AppModel.shared.history.entries.count)")
    }

    static func close() { shared?.window?.performClose(nil) }

    private init() {
        state = HistoryViewState(model: AppModel.shared)
        let hosting = NSHostingController(rootView: HistoryView(state: state))
        hosting.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.title = "Capture History"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentMinSize = CGSize(width: 520, height: 380)
        window.setContentSize(CGSize(width: 900, height: 640))
        super.init(window: window)
        window.delegate = self
        if !window.setFrameUsingName("CaptureHistory") { window.center() }
        window.setFrameAutosaveName("CaptureHistory")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func windowWillClose(_ notification: Notification) {
        // Undo ends with the window: deleted captures are erased for good.
        window?.undoManager?.removeAllActions()
        AppModel.shared.history.purgeDeleted()
        state.quickLookURL = nil
    }
}

/// Selection, filter and focus for the History window.
@MainActor
@Observable
final class HistoryViewState {
    @ObservationIgnored unowned let model: AppModel
    var kind: HistoryKind?
    var search = ""
    var selection: Set<UUID> = []
    /// The keyboard cursor (the last clicked or arrowed-to capture).
    var cursor: UUID?
    @ObservationIgnored var anchor: UUID?
    var columns = 4
    var quickLookURL: URL?

    init(model: AppModel) {
        self.model = model
    }

    var history: HistoryController { model.history }

    /// What the grid shows, newest first.
    var visible: [HistoryEntry] {
        HistoryIndex(entries: history.entries).filtered(kind: kind, search: search)
    }

    var selectedEntries: [HistoryEntry] { visible.filter { selection.contains($0.id) } }

    // MARK: Selection

    func click(_ entry: HistoryEntry, extending: Bool, toggling: Bool) {
        if toggling {
            if selection.contains(entry.id) { selection.remove(entry.id) } else { selection.insert(entry.id) }
            anchor = entry.id
        } else if extending, let anchor, let range = range(from: anchor, to: entry.id) {
            selection = Set(range)
        } else {
            selection = [entry.id]
            anchor = entry.id
        }
        cursor = entry.id
    }

    /// For a right-click or a drag: keep a multi-selection that includes it, else select just it.
    func prepareForAction(on entry: HistoryEntry) {
        if !selection.contains(entry.id) {
            selection = [entry.id]
            anchor = entry.id
        }
        cursor = entry.id
    }

    private func range(from a: UUID, to b: UUID) -> [UUID]? {
        let ids = visible.map(\.id)
        guard let i = ids.firstIndex(of: a), let j = ids.firstIndex(of: b) else { return nil }
        return Array(ids[min(i, j)...max(i, j)])
    }

    func selectAll() { selection = Set(visible.map(\.id)) }

    func move(_ move: GridNavigation.Move, extending: Bool) {
        let entries = visible
        let days = HistoryDays.group(entries)
        let ordered = days.flatMap(\.entries)
        let navigation = GridNavigation(sections: days.map(\.entries.count), columns: columns)
        let current = cursor.flatMap { id in ordered.firstIndex { $0.id == id } }
        guard let target = navigation.target(from: current, move) else { return }
        click(ordered[target], extending: extending, toggling: false)
        if !extending { anchor = ordered[target].id }
    }

    // MARK: Actions (on the selection)

    func restore() {
        for entry in selectedEntries.reversed() { model.restore(entry) }
    }

    func annotate() {
        guard let entry = selectedEntries.first else { return }
        if entry.kind.isMedia { open(entry); return }
        model.withCapture(entry) { EditorWindowController.open($0, model: self.model) }
    }

    func open(_ entry: HistoryEntry) {
        if entry.kind.isMedia {
            NSWorkspace.shared.open(history.store.fileURL(for: entry))
        } else {
            model.withCapture(entry) { EditorWindowController.open($0, model: self.model) }
        }
    }

    func pin() {
        for entry in selectedEntries where !entry.kind.isMedia {
            model.withCapture(entry) { self.model.pins.pin($0) }
        }
    }

    func copy() {
        guard let entry = selectedEntries.first else { return }
        model.withCapture(entry) { self.model.copy($0, closeCard: false) }
    }

    func save() {
        guard let entry = selectedEntries.first else { return }
        model.withCapture(entry) { self.model.save($0, closeCard: false) }
    }

    func saveAs() {
        guard let entry = selectedEntries.first else { return }
        model.withCapture(entry) { self.model.saveAs($0) }
    }

    func showInFinder() {
        let urls = selectedEntries.map { entry in
            entry.savedPath.map { URL(fileURLWithPath: $0) }.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
                ?? history.store.fileURL(for: entry)
        }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func quickLook() {
        if quickLookURL != nil { quickLookURL = nil; return }
        guard let entry = selectedEntries.first(where: { $0.id == cursor }) ?? selectedEntries.first else { return }
        quickLookURL = history.store.fileURL(for: entry)
    }

    var quickLookURLs: [URL] { visible.map { history.store.fileURL(for: $0) } }

    func delete(undoManager: UndoManager?) {
        let ids = selection.subtracting(model.openHistoryIDs)
        guard !ids.isEmpty else {
            if !selection.isEmpty { HUD.show("Close it first: it's open", systemImage: "exclamationmark.triangle") }
            return
        }
        // Keep a cursor near where the deleted ones were.
        let ordered = HistoryDays.group(visible).flatMap(\.entries)
        let next = ordered.drop { !ids.contains($0.id) }.first { !ids.contains($0.id) }
            ?? ordered.last { !ids.contains($0.id) }
        history.delete(ids, undoManager: undoManager)
        selection = next.map { [$0.id] } ?? []
        cursor = next?.id
        anchor = next?.id
    }

    func fileURLs(for entries: [HistoryEntry]) -> [URL] { entries.map { history.store.fileURL(for: $0) } }
}

/// Thumbnails for the grid: ImageIO-downsampled off the main thread, kept in a bounded cache.
@MainActor
final class HistoryThumbnails {
    static let shared = HistoryThumbnails()
    private let cache = NSCache<NSString, CGImage>()

    private init() { cache.countLimit = 600 }

    func cached(_ key: String) -> CGImage? { cache.object(forKey: key as NSString) }

    func load(_ url: URL, key: String, pixels: Int) async -> CGImage? {
        if let hit = cached(key) { return hit }
        let image = await Task.detached(priority: .userInitiated) { HistoryThumbnail.make(from: url, maxPixelSize: pixels) }.value
        if let image { cache.setObject(image, forKey: key as NSString) }
        return image
    }
}

// MARK: Views

struct HistoryView: View {
    @Bindable var state: HistoryViewState
    @Environment(\.undoManager) private var undoManager
    @FocusState private var gridFocused: Bool

    static let tileWidth: CGFloat = 176
    static let gap = Spacing.s
    static let margin = Spacing.l

    private var history: HistoryController { state.history }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Hairline()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Kind", selection: $state.kind) {
                    Text("All Captures").tag(HistoryKind?.none)
                    Divider()
                    ForEach(HistoryKind.allCases) { Text($0.title).tag(HistoryKind?.some($0)) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .help("Show one kind of capture")
            }
        }
        .searchable(text: $state.search, placement: .toolbar, prompt: "App or Kind")
        .quickLookPreview($state.quickLookURL, in: state.quickLookURLs)
    }

    @ViewBuilder private var content: some View {
        if !history.isLoaded {
            ProgressView { Text("Loading History…") }
                .controlSize(.small)
        } else if history.entries.isEmpty {
            if history.isOn {
                ContentUnavailableView {
                    Label("No Captures Yet", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text("Screenshots and recordings you take are kept here \(history.retention.keptFor).")
                } actions: {
                    Button("Capture Area") { HistoryWindowController.close(); state.model.capture(.area) }
                }
            } else {
                ContentUnavailableView {
                    Label("History Is Off", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Snapper isn't keeping your captures.")
                } actions: {
                    Button("Keep Captures for 1 Month") { history.retention = .month }
                }
            }
        } else if state.visible.isEmpty {
            if state.search.isEmpty {
                ContentUnavailableView {
                    Label("No \(state.kind?.title ?? "Captures")", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("There are none in history.")
                } actions: {
                    Button("Show All Captures") { state.kind = nil }
                }
            } else {
                ContentUnavailableView.search(text: state.search)
            }
        } else {
            grid
        }
    }

    private var grid: some View {
        let days = HistoryDays.group(state.visible)
        let now = Date()
        return ScrollViewReader { proxy in
            ScrollView {
                // As many columns as fit at the minimum width, sharing the width evenly, so the
                // grid has the same margin on both sides.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tileWidth), spacing: Self.gap, alignment: .top)],
                          alignment: .leading, spacing: Self.gap, pinnedViews: [.sectionHeaders]) {
                    ForEach(days) { day in
                        Section {
                            ForEach(day.entries) { entry in
                                HistoryTile(entry: entry, state: state, onFocus: { gridFocused = true })
                                    .id(entry.id)
                            }
                        } header: {
                            DayHeader(title: HistoryDays.title(for: day.start, now: now), count: day.entries.count)
                        }
                    }
                }
                .padding(.horizontal, Self.margin)
                .padding(.bottom, Self.margin)
            }
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { updateColumns(geometry.size.width) }
                        .onChange(of: geometry.size.width) { _, width in updateColumns(width) }
                }
            }
            .focusable()
            .focused($gridFocused)
            .focusEffectDisabled()
            .onKeyPress(phases: .down) { press in handle(press, proxy: proxy) }
            .onCommand(#selector(NSText.selectAll(_:))) { state.selectAll() }
            .onCommand(#selector(NSText.delete(_:))) { state.delete(undoManager: undoManager) }
            .onAppear { gridFocused = true }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Captures")
        }
    }

    private func updateColumns(_ width: CGFloat) {
        state.columns = GridNavigation.columns(width: width - 2 * Self.margin, tile: Self.tileWidth, spacing: Self.gap)
    }

    private func handle(_ press: KeyPress, proxy: ScrollViewProxy) -> KeyPress.Result {
        let shift = press.modifiers.contains(.shift), command = press.modifiers.contains(.command)
        func go(_ move: GridNavigation.Move) -> KeyPress.Result {
            state.move(move, extending: shift)
            if let cursor = state.cursor { withAnimation(nil) { proxy.scrollTo(cursor) } }
            return .handled
        }
        switch press.key {
        case .leftArrow: return go(.left)
        case .rightArrow: return go(.right)
        case .upArrow: return go(command ? .home : .up)
        case .downArrow: return go(command ? .end : .down)
        case .home: return go(.home)
        case .end: return go(.end)
        case .space: state.quickLook(); return .handled
        case .return: state.restore(); return .handled
        case .delete, .deleteForward: state.delete(undoManager: undoManager); return .handled
        case .escape:
            if state.quickLookURL != nil { state.quickLookURL = nil; return .handled }
            if !state.selection.isEmpty { state.selection = []; return .handled }
            return .ignored
        default: break
        }
        guard command, let character = press.characters.lowercased().first else { return .ignored }
        switch (character, shift) {
        case ("a", false): state.selectAll()
        case ("c", _): state.copy()
        case ("e", false): state.annotate()
        case ("s", true): state.saveAs()
        case ("p", true): state.pin()
        case ("r", false): state.showInFinder()
        case ("y", false): state.quickLook()
        default: return .ignored
        }
        return .handled
    }

    private var footer: some View {
        HStack(spacing: Spacing.s) {
            Text(summary)
                .monospacedDigit()
            Spacer()
            Text(history.isOn ? "Kept \(history.retention.keptFor)" : "History is off")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, Self.margin)
        .frame(height: 28)
    }

    private var summary: String {
        let count = state.visible.count, total = history.entries.count
        let size = ByteCountFormatter.string(fromByteCount: history.totalBytes, countStyle: .file)
        let captures = total == 1 ? "1 capture" : "\(total.formatted()) captures"
        if !state.selection.isEmpty {
            return "\(state.selection.count.formatted()) of \(count.formatted()) selected"
        }
        return count == total ? "\(captures) · \(size)" : "\(count.formatted()) of \(captures) · \(size)"
    }
}

private struct DayHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Spacer()
            Text(count.formatted())
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityLabel(count == 1 ? "1 capture" : "\(count) captures")
        }
        .padding(.top, Spacing.m)
        .padding(.bottom, Spacing.s)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One capture: its thumbnail and when / from where.
struct HistoryTile: View {
    let entry: HistoryEntry
    let state: HistoryViewState
    let onFocus: () -> Void
    @State private var thumbnail: CGImage?
    @State private var hovering = false
    @Environment(\.controlActiveState) private var activeState

    static let radius = Radius.l
    static let inset = Spacing.s
    /// The thumbnail box's width : height (160 × 112 at the minimum tile width).
    static let thumbnailAspect: CGFloat = 160.0 / 112.0

    private var selected: Bool { state.selection.contains(entry.id) }
    private var key: String { "\(entry.id.uuidString)/\(entry.fileName)/\(entry.byteSize)" }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs + 2) { // lint:allow optical: caption sits 6 pt under the image
            preview
            caption
        }
        .padding(Self.inset)
        .frame(minWidth: HistoryView.tileWidth, maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .fill(selected ? Color.selectionTint(activeState, opacity: 0.16) : hovering ? Color.primary.opacity(0.05) : .clear)
        }
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .strokeBorder(Color.selectionRing(activeState), lineWidth: 2)
            }
        }
        .overlay {
            TileMouseView(entry: entry, state: state, onFocus: onFocus)
        }
        .onHover { hovering = $0 }
        .task(id: key) {
            thumbnail = HistoryThumbnails.shared.cached(key)
            if thumbnail == nil {
                thumbnail = await HistoryThumbnails.shared.load(state.history.store.thumbnailSourceURL(for: entry), key: key,
                                                                 pixels: Int(HistoryView.tileWidth * 2))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction { state.click(entry, extending: false, toggling: false); state.restore() }
        .accessibilityAction(named: "Annotate") { state.prepareForAction(on: entry); state.annotate() }
        .accessibilityAction(named: "Delete") { state.prepareForAction(on: entry); state.delete(undoManager: nil) }
    }

    private var preview: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.nested(in: Self.radius, padding: Self.inset), style: .continuous)
        return ZStack {
            shape.fill(.quaternary.opacity(0.5))
            if let thumbnail {
                Image(decorative: thumbnail, scale: 2)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: entry.kind.isMedia ? "film" : "photo")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
            if entry.kind.isMedia {
                Label(entry.kind == .gif ? "GIF" : Elapsed.string(entry.duration ?? 0), systemImage: entry.kind == .gif ? "photo.stack" : "play.fill")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, Spacing.s)
                    .frame(height: 20)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(Self.thumbnailAspect, contentMode: .fit)
        .clipShape(shape)
        .hairlineBorder(shape)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Spacing.xs) {
                Text(entry.createdAt, format: .dateTime.hour().minute())
                    .monospacedDigit()
                Spacer(minLength: Spacing.xs)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.callout)
            Text(entry.source?.name ?? entry.kind.singular)
                .font(.caption)
                .foregroundStyle(.secondary)
                .truncationMode(.tail)
        }
        .lineLimit(1)
    }

    /// "1440 × 900", "Edited", "0:07".
    private var detail: String {
        if entry.kind.isMedia { return entry.kind.singular }
        return entry.isEdited ? "Edited" : "\(entry.pixelWidth) × \(entry.pixelHeight)"
    }

    private var accessibilityTitle: String {
        var parts = [entry.kind.singular, entry.createdAt.formatted(date: .abbreviated, time: .shortened)]
        if let app = entry.source?.name { parts.append(app) }
        if entry.isEdited { parts.append("edited") }
        return parts.joined(separator: ", ")
    }
}

/// The tile's mouse handling in AppKit: click, ⌘/⇧-click selection, double-click to open, a
/// real file drag (the history files), and the context menu.
private struct TileMouseView: NSViewRepresentable {
    let entry: HistoryEntry
    let state: HistoryViewState
    let onFocus: () -> Void

    func makeNSView(context: Context) -> TileMouseNSView {
        let view = TileMouseNSView()
        view.configure(entry: entry, state: state, onFocus: onFocus)
        return view
    }

    func updateNSView(_ view: TileMouseNSView, context: Context) {
        view.configure(entry: entry, state: state, onFocus: onFocus)
    }
}

@MainActor
private final class TileMouseNSView: NSView, NSDraggingSource {
    private var entry: HistoryEntry?
    private weak var state: HistoryViewState?
    private var onFocus: (() -> Void)?
    private var downAt: CGPoint?
    private var clickedSelected = false

    func configure(entry: HistoryEntry, state: HistoryViewState, onFocus: @escaping () -> Void) {
        self.entry = entry
        self.state = state
        self.onFocus = onFocus
        setAccessibilityElement(false)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let entry, let state else { return }
        onFocus?()
        if event.clickCount == 2 {
            state.prepareForAction(on: entry)
            state.open(entry)
            return
        }
        let flags = event.modifierFlags
        clickedSelected = state.selection.contains(entry.id) && state.selection.count > 1
            && !flags.contains(.command) && !flags.contains(.shift)
        if clickedSelected {
            // Maybe the start of a drag of the whole selection; a plain click selects just it on mouse-up.
            state.cursor = entry.id
        } else {
            state.click(entry, extending: flags.contains(.shift), toggling: flags.contains(.command))
        }
        downAt = event.locationInWindow
    }

    override func mouseUp(with event: NSEvent) {
        if clickedSelected, let entry, let state { state.click(entry, extending: false, toggling: false) }
        clickedSelected = false
        downAt = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downAt, let entry, let state else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 4 else { return }
        downAt = nil
        clickedSelected = false
        state.prepareForAction(on: entry)
        let entries = state.selectedEntries
        let urls = state.fileURLs(for: entries)
        guard !urls.isEmpty else { return }
        var items: [NSDraggingItem] = []
        for (index, url) in urls.enumerated() {
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let thumb = HistoryThumbnails.shared.cached("\(entries[index].id.uuidString)/\(entries[index].fileName)/\(entries[index].byteSize)")
            let image = thumb.map { NSImage(cgImage: $0, size: CGSize(width: $0.width / 2, height: $0.height / 2)) }
                ?? NSWorkspace.shared.icon(forFile: url.path)
            let size = image.size.width > 0 ? image.size : bounds.size
            let offset = CGFloat(min(index, 4)) * 6
            item.setDraggingFrame(CGRect(x: bounds.midX - size.width / 2 + offset, y: bounds.midY - size.height / 2 - offset,
                                         width: size.width, height: size.height), contents: image)
            items.append(item)
        }
        Diagnostics.record("history drag count=\(urls.count)")
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy] : []
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let entry, let state else { return nil }
        onFocus?()
        state.prepareForAction(on: entry)
        let many = state.selection.count > 1
        let media = state.selectedEntries.allSatisfy(\.kind.isMedia)
        let menu = NSMenu(title: "Capture")
        menu.addItem(MenuAction(many ? "Restore \(state.selection.count) Thumbnails" : "Restore Thumbnail") { state.restore() })
        if !many {
            menu.addItem(MenuAction(media ? "Open" : "Annotate", key: media ? "" : "e") { state.open(entry) })
        }
        if !media {
            menu.addItem(MenuAction(many ? "Pin \(state.selection.count) to Screen" : "Pin to Screen") { state.pin() })
        }
        menu.addItem(.separator())
        if !many {
            menu.addItem(MenuAction("Copy", key: "c") { state.copy() })
            menu.addItem(MenuAction("Save As…") { state.saveAs() })
        }
        menu.addItem(MenuAction("Show in Finder") { state.showInFinder() })
        menu.addItem(MenuAction("Quick Look") { state.quickLook() })
        menu.addItem(.separator())
        let undoManager = window?.undoManager
        menu.addItem(MenuAction(many ? "Delete \(state.selection.count) Captures" : "Delete") { state.delete(undoManager: undoManager) })
        return menu
    }
}

extension HistoryRetention {
    /// "for 1 month", "until you delete them": for "Kept …".
    var keptFor: String {
        switch self {
        case .off: "for no time"
        case .day: "for 1 day"
        case .week: "for 1 week"
        case .month: "for 1 month"
        case .forever: "until you delete them"
        }
    }
}
