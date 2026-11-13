import AppKit
import ClipsCore
import SlopKit
import SwiftUI

/// What the strip's cards, menus and tabs can do. Most act on several clips: the selection,
/// or the one card a menu was opened on.
struct PanelActions {
    let choose: ([Clip], _ plain: Bool) -> Void
    let copy: ([Clip]) -> Void
    let togglePin: ([Clip]) -> Void
    /// Onto a board, or off any board (nil).
    let pin: ([Clip], _ board: UUID?) -> Void
    /// A new board with these clips on it, its name ready to type.
    let newBoard: ([Clip]) -> Void
    let delete: ([Clip]) -> Void
    let preview: (Clip) -> Void
    /// `title`: start in the title field (Rename) instead of the text (Edit).
    let edit: (Clip, _ title: Bool) -> Void
    let open: (Clip) -> Void
    let reveal: (Clip) -> Void
    let copyImageText: (Clip) -> Void
    /// Start a paste stack with these clips (none: collect copies), or stop the running one.
    let pasteStack: ([Clip]) -> Void
    let requestBoardDelete: (Board) -> Void
    let dismiss: () -> Void
    /// A dragged card is over this point on screen: true if it's a board tab.
    let dragMoved: (NSPoint) -> Bool
    /// Dropped there: true if a board took the clips.
    let dragEnded: (NSPoint, [Clip]) -> Bool
}

enum PanelMetrics {
    /// One inset for the whole strip: panel edge to the top bar and to the cards.
    static let inset = Spacing.m
    /// The cards' radius; the panel's is this plus `inset`, so the two are concentric.
    static let cardCornerRadius = Radius.l
    /// The strip's corner radius (24 pt). Everything rounded inside derives from it (through
    /// `floatingPanelCornerRadius`).
    static let cornerRadius = cardCornerRadius + inset
    /// Between cards.
    static let cardGap = Spacing.l
    /// Gap between the panel and the screen's edges (and the Dock): it floats.
    static let margin = Spacing.l
    /// Search field, tab pills and the menu button share this height and centre line.
    static let controlHeight: CGFloat = 28
    static let searchWidth: CGFloat = 200
    /// Width of the hidden, parked panel (see PanelController.park).
    static let parkedWidth: CGFloat = 900
    static let cardSize = CGSize(width: 216, height: 216)
    static let strip = StripLayout(itemWidth: Double(cardSize.width), spacing: Double(cardGap), inset: Double(inset))
    /// The vertical stack and the concentric radii (tested in ClipsCore). The card strip keeps
    /// 8 pt above and below the cards for the selection ring and the cards' shadow.
    static let geometry = StripGeometry(panelRadius: Double(cornerRadius), inset: Double(inset),
                                        controlHeight: Double(controlHeight), cardHeight: Double(cardSize.height),
                                        ringOutset: Double(ClipCardView.ringOutset), overflow: Double(Spacing.s))
    static var stripVerticalInset: CGFloat { CGFloat(geometry.overflow) }
    static var stripHeight: CGFloat { CGFloat(geometry.stripHeight) }
    static var barToStrip: CGFloat { CGFloat(geometry.barToStrip) }
    static var bottomPadding: CGFloat { CGFloat(geometry.bottomPadding) }
    static var height: CGFloat { CGFloat(geometry.panelHeight) }

    /// The card's radius: concentric with the strip's corner, `inset` in from it.
    static func cardRadius(inPanel panelRadius: CGFloat) -> CGFloat {
        var geometry = geometry
        geometry.panelRadius = Double(panelRadius)
        return CGFloat(geometry.cardRadius)
    }
}

/// The strip along the bottom of the screen: a top bar (what Return does or a notice on the
/// left; search and tabs in the middle; count and a menu on the right) over a row of cards.
struct PanelView: View {
    @Bindable var state: PanelState
    let model: AppModel
    let actions: PanelActions

    @FocusState private var focus: PanelFocus?

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .frame(height: PanelMetrics.controlHeight)
                .padding(.top, PanelMetrics.inset)
                .padding(.bottom, PanelMetrics.barToStrip)
            content
                .frame(maxWidth: .infinity)
                .frame(height: PanelMetrics.stripHeight)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focus = .search }
        .onChange(of: state.focusRequest) { focus = .search }
        .onChange(of: state.renaming?.id) { _, renaming in focus = renaming == nil ? .search : .boardName }
        .onPreferenceChange(TabFramesKey.self) { frames in
            MainActor.assumeIsolated { state.tabFrames = frames }
        }
    }

    @ViewBuilder private var content: some View {
        if !model.isLoaded {
            ProgressView().controlSize(.small)
        } else if state.results.isEmpty {
            emptyState
        } else {
            ClipStrip(state: state, actions: actions)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: Spacing.m) {
            // Both sides always take equal room, so the middle stays centred even when one
            // of them has nothing to show.
            ZStack(alignment: .leading) {
                Color.clear.frame(height: 1)
                leading
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Spacing.s) {
                searchField
                TabBar(state: state, model: model, actions: actions, focus: $focus)
            }
            .fixedSize()
            ZStack(alignment: .trailing) {
                Color.clear.frame(height: 1)
                trailing
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, PanelMetrics.inset)
    }

    private var searchField: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            // On the glass strip the field's own placeholder draws solid black (or white),
            // darker than the secondary tab labels beside it, and ignores a styled prompt: so
            // the placeholder is drawn here, where the typed text starts.
            TextField("Search clips", text: $state.query, prompt: Text(verbatim: ""))
                .textFieldStyle(.plain)
                .background(alignment: .leading) {
                    if state.query.isEmpty {
                        Text("Search")
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .focused($focus, equals: .search)
                .focusEffectDisabled()
                .accessibilityLabel("Search clips")
            if !state.query.isEmpty {
                Button {
                    state.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .help("Clear the search (Esc)")
            }
        }
        .padding(.horizontal, Spacing.s)
        .frame(width: PanelMetrics.searchWidth, height: PanelMetrics.controlHeight)
        // Calm: a quiet capsule, no focus outline (the caret shows where typing goes; it hides
        // while the cards have the keyboard).
        .background(Capsule().fill(.quaternary))
        .help("Type to search. Return pastes, ⇧Return pastes plain text, Space previews (Tab first while searching), ⌘1–⌘9 paste a card.")
    }

    @ViewBuilder private var leading: some View {
        if let notice = PanelNotice.current(model: model, state: state) {
            NoticeLabel(notice: notice) { action in
                switch action {
                case .clipboardSettings: ClipboardAccess.openSettings()
                case .accessibility: Permission.accessibility.request()
                case .resume: model.resume()
                case .deleteBoard(let id): AppDelegate.panel?.confirmBoardDelete(id)
                case .stopStack: model.stack.cancel()
                }
            }
        }
    }

    private var trailing: some View {
        HStack(spacing: Spacing.s) {
            PanelMenu(model: model, state: state, actions: actions)
                // The ⋯ glyph sits inside a 28 pt hit area: let the area overhang so the
                // glyph itself lines up with the cards' right edge.
                .padding(.trailing, -Spacing.xs)
        }
    }

    // MARK: Empty states

    @ViewBuilder private var emptyState: some View {
        Group {
            if !state.query.isEmpty {
                ContentUnavailableView.search(text: state.query)
            } else if let id = state.filter.boardID {
                let name = model.boards.board(id: id)?.name ?? "This Board"
                let index = model.boards.index(of: id).map { $0 + 1 }
                ContentUnavailableView("\(name) Is Empty", systemImage: "pin",
                                       description: Text(index.map { $0 <= 9 ? "Drag cards onto this tab, or press ⌥⌘\($0) on a card. Clips on a board are never removed automatically." : "Drag cards onto this tab. Clips on a board are never removed automatically." }
                                                         ?? "Drag cards onto this tab."))
            } else if state.filter != .all, let title = state.filter.title {
                ContentUnavailableView("No \(title)", systemImage: state.filter.systemImage,
                                       description: Text("Nothing of this kind has been copied yet."))
            } else {
                ContentUnavailableView("No Clips Yet", systemImage: "doc.on.clipboard",
                                       description: Text("Copy text, links, images or files in any app and they show up here."))
            }
        }
        .controlSize(.small)
    }
}

// MARK: - Tabs

/// Where typing goes in the top bar.
enum PanelFocus: Hashable {
    case search, boardName
}

/// Collects every tab's frame in the panel, so a card dragged out of the strip can be dropped
/// on a board tab.
struct TabFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// All, the boards (coloured dots, + for a new one), then the kinds. ⌘← / ⌘→ switch.
/// Boards: double-click or right-click to rename, recolour, move or delete; drop cards on one
/// to pin them there.
struct TabBar: View {
    @Bindable var state: PanelState
    let model: AppModel
    let actions: PanelActions
    var focus: FocusState<PanelFocus?>.Binding

    var body: some View {
        HStack(spacing: Spacing.xs) {
            tab(.all, title: "All")
            ForEach(model.boards.all) { board in
                if state.renaming?.id == board.id {
                    nameField(board)
                } else {
                    boardTab(board)
                }
            }
            newBoardButton
            ForEach(ClipFilter.kinds) { kind in
                tab(kind, title: kind.title ?? "")
            }
        }
    }

    private func tab(_ item: ClipFilter, title: String) -> some View {
        let selected = item == state.filter
        return Button {
            state.filter = item
        } label: {
            TabLabel(title: title, color: nil, selected: selected, targeted: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help("Show \(title.lowercased()) (⌘← ⌘→ switch)")
        .reportFrame(id: item.id)
    }

    private func boardTab(_ board: Board) -> some View {
        let item = ClipFilter.board(board.id)
        let selected = item == state.filter
        let index = model.boards.index(of: board.id) ?? 0
        let count = model.clipCount(onBoard: board.id)
        return Button {
            state.filter = item
        } label: {
            TabLabel(title: board.name, color: board.color.color, selected: selected, targeted: state.dropTarget == item)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded { state.beginRenaming(board, isNew: false) })
        .accessibilityLabel("\(board.name), board, \(count == 1 ? "1 clip" : "\(count) clips")")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: "Rename") { state.beginRenaming(board, isNew: false) }
        .help(index < 9 ? "\(board.name): drop cards here, or press ⌥⌘\(index + 1) on a card. Double-click to rename."
                        : "\(board.name): drop cards here. Double-click to rename.")
        .contextMenu {
            Button("Rename") { state.beginRenaming(board, isNew: false) }
            Menu("Color") {
                ForEach(BoardColor.allCases) { color in
                    Toggle(isOn: Binding(get: { board.color == color }, set: { if $0 { model.setColor(color, ofBoard: board.id) } })) {
                        Label { Text(color.title) } icon: { Image(nsImage: BoardSwatch.image(color)) }
                    }
                }
            }
            Divider()
            Button("Move Left") { model.moveBoard(board.id, by: -1) }
                .disabled(index == 0)
            Button("Move Right") { model.moveBoard(board.id, by: 1) }
                .disabled(index >= model.boards.all.count - 1)
            Divider()
            Button(count > 0 ? "Delete Board…" : "Delete Board") { actions.requestBoardDelete(board) }
        }
        .reportFrame(id: item.id)
    }

    private func nameField(_ board: Board) -> some View {
        HStack(spacing: Spacing.s) {
            Circle().fill(board.color.color).frame(width: 8, height: 8).accessibilityHidden(true)
            TextField("Board name", text: Binding(get: { state.renaming?.draft ?? "" },
                                                  set: { state.renaming?.draft = $0 }))
                .textFieldStyle(.plain)
                .focused(focus, equals: .boardName)
                .focusEffectDisabled()
                .frame(width: 112)
                .onSubmit { state.commitRename() }
                .accessibilityLabel("Board name")
                .help("Type a name, then press Return (Esc cancels)")
        }
        .padding(.horizontal, Spacing.m)
        .frame(height: PanelMetrics.controlHeight)
        .background(Capsule().strokeBorder(Color.accentColor, lineWidth: 2))
        .background(Capsule().fill(.quaternary))
        .onChange(of: focus.wrappedValue) { _, now in
            // Clicking elsewhere keeps the name typed so far.
            if now != .boardName, state.renaming?.id == board.id { state.commitRename() }
        }
    }

    private var newBoardButton: some View {
        let targeted = state.dropTarget == PanelController.newBoardTab
        return Button {
            actions.newBoard([])
        } label: {
            Image(systemName: "plus")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: PanelMetrics.controlHeight, height: PanelMetrics.controlHeight)
                .background {
                    if targeted {
                        Circle().fill(Color.accentColor.opacity(0.18))
                        Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New Board")
        .help("New board (⇧⌘N). Drop cards here to put them on a new board.")
        .reportFrame(id: PanelController.newBoardTab.id)
    }
}

/// A tab's capsule: the name (with a board's colour dot), filled when selected, ringed while a
/// dragged card is over it.
private struct TabLabel: View {
    let title: String
    let color: Color?
    let selected: Bool
    let targeted: Bool

    var body: some View {
        HStack(spacing: Spacing.s) {
            if let color {
                Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
            }
            ZStack {
                // Reserve the semibold width so switching tabs never shifts the row.
                Text(title).font(.callout.weight(.semibold)).hidden()
                Text(title).font(.callout.weight(selected ? .semibold : .regular))
            }
            .lineLimit(1)
            .frame(maxWidth: 140)
        }
        .padding(.horizontal, Spacing.m)
        .frame(height: PanelMetrics.controlHeight)
        .background {
            if targeted {
                Capsule().fill(Color.accentColor.opacity(0.18))
                Capsule().strokeBorder(Color.accentColor, lineWidth: 2)
            } else if selected {
                Capsule().fill(.quaternary)
            }
        }
        .foregroundStyle(selected || targeted ? Color.primary : Color.secondary)
        .contentShape(Capsule())
    }
}

private extension View {
    func reportFrame(id: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: TabFramesKey.self, value: [id: proxy.frame(in: .global)])
        })
    }
}

extension BoardColor {
    /// A system colour, so it follows light and dark mode and Increase Contrast.
    var color: Color { Color(nsColor: nsColor) }

    var nsColor: NSColor {
        switch self {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .teal: .systemTeal
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .pink: .systemPink
        case .gray: .systemGray
        }
    }
}

/// A small coloured dot for menus (a colour swatch carries information, so menus may show it).
@MainActor
enum BoardSwatch {
    private static var cache: [BoardColor: NSImage] = [:]

    static func image(_ color: BoardColor) -> NSImage {
        if let cached = cache[color] { return cached }
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.nsColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = color.title
        cache[color] = image
        return image
    }
}

extension ClipFilter {
    var systemImage: String {
        switch self {
        case .all: "tray.full"
        case .pinned, .board: "pin"
        case .text: "text.alignleft"
        case .links: "link"
        case .images: "photo"
        case .files: "doc"
        }
    }

    /// The strip's tab icon: the full history reads as a timeline.
    var tabImage: String {
        self == .all ? "clock.arrow.circlepath" : systemImage
    }
}

extension ClipKind {
    var systemImage: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .file: "doc"
        case .color: "paintpalette"
        }
    }

    var spokenName: String {
        switch self {
        case .text: "Text"
        case .link: "Link"
        case .image: "Image"
        case .file: "File"
        case .color: "Color"
        }
    }
}

// MARK: - Left of the top bar

/// The one notice worth showing right now, most important first.
struct PanelNotice: Equatable {
    var systemImage: String
    var text: String
    var button: String?
    var action: Action?
    /// Information, not a warning (the selection, a running paste stack): the accent colour.
    var isInfo = false

    enum Action: Equatable { case clipboardSettings, accessibility, resume, deleteBoard(UUID), stopStack }

    @MainActor
    static func current(model: AppModel, state: PanelState) -> PanelNotice? {
        if let error = model.storageError {
            return PanelNotice(systemImage: "exclamationmark.triangle", text: error)
        }
        if let pending = state.pendingDelete {
            let clips = state.results.filter { pending.contains($0.id) }
            let pinned = clips.filter(\.isPinned)
            if clips.count == 1, let clip = clips.first {
                return PanelNotice(systemImage: "pin", text: "“\(ClipText.title(of: clip, limit: 30))” is pinned. Press ⌘⌫ again to delete it.")
            }
            return PanelNotice(systemImage: "pin", text: "\(pinned.count) of these \(clips.count) clips are pinned. Press ⌘⌫ again to delete them all.")
        }
        if let id = state.pendingBoardDelete, let board = model.boards.board(id: id) {
            let count = model.clipCount(onBoard: id)
            return PanelNotice(systemImage: "trash",
                               text: "Delete “\(board.name)”? Its \(count == 1 ? "clip stays" : "\(count) clips stay") in your history, no longer pinned. Esc keeps it.",
                               button: "Delete Board", action: .deleteBoard(id))
        }
        switch model.clipboardAccess {
        case .denied:
            return PanelNotice(systemImage: "hand.raised", text: "macOS is blocking Clips from reading the clipboard, so new copies aren't recorded.",
                               button: "Open Settings…", action: .clipboardSettings)
        case .asks:
            return PanelNotice(systemImage: "hand.raised", text: "macOS asks before Clips reads each copy. Allow Clips under Paste from Other Apps.",
                               button: "Open Settings…", action: .clipboardSettings)
        case .allowed:
            break
        }
        if model.pasteDirectly, !model.hasAccessibility, !model.usesPrivatePasteboard {
            return PanelNotice(systemImage: "accessibility", text: "Return copies. To paste into apps, allow Clips in Accessibility.",
                               button: "Open Settings…", action: .accessibility)
        }
        if let stack = model.stack.stack {
            let text = stack.remaining == 0 ? "Paste stack on: what you copy now pastes one by one, in order."
                : "Paste stack: \(stack.remaining) to paste. Each ⌘V takes the next one."
            return PanelNotice(systemImage: "square.stack.3d.up", text: text, button: "Stop", action: .stopStack, isInfo: true)
        }
        if let paused = model.pauseDescription {
            return PanelNotice(systemImage: "pause.circle", text: "\(paused). New copies aren't recorded.", button: "Resume", action: .resume)
        }
        if state.isMultipleSelection {
            let clips = state.selectedClips
            return PanelNotice(systemImage: "checkmark.circle",
                               text: "\(ClipJoin.describe(clips)) selected. Return pastes them together, ⇧⌘C one by one.", isInfo: true)
        }
        return nil
    }
}

struct NoticeLabel: View {
    let notice: PanelNotice
    let perform: (PanelNotice.Action) -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: notice.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(notice.isInfo ? AnyShapeStyle(.tint) : AnyShapeStyle(.orange))
                .accessibilityHidden(true)
            Text(notice.text)
                .font(.caption)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .help(notice.text)
            if let button = notice.button, let action = notice.action {
                Button(button) { perform(action) }
                    .controlSize(.small)
                    .fixedSize()
            }
        }
    }
}

// MARK: - Right of the top bar

/// The ⋯ button: the clip count, the selected clip's actions (their keys are in the help
/// tag), then History, pause, Settings and clearing. Text only (Golden Gate menus).
///
/// AppKit, and the menu is built when it opens: a SwiftUI `Menu` that names the selection
/// rebuilds its items on every keystroke and selection change (a cold search went 102 ms).
struct PanelMenu: NSViewRepresentable {
    let model: AppModel
    let state: PanelState
    let actions: PanelActions

    func makeNSView(context: Context) -> PanelMenuButton {
        let button = PanelMenuButton()
        button.build = { [model, state, actions] in Self.menu(model: model, state: state, actions: actions) }
        return button
    }

    func updateNSView(_ button: PanelMenuButton, context: Context) {
        button.build = { [model, state, actions] in Self.menu(model: model, state: state, actions: actions) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PanelMenuButton, context: Context) -> CGSize? {
        CGSize(width: PanelMetrics.controlHeight, height: PanelMetrics.controlHeight)
    }

    @MainActor
    static func menu(model: AppModel, state: PanelState, actions: PanelActions) -> NSMenu {
        let menu = NSMenu()
        let count = state.results.count
        let header = NSMenuItem(title: count == 1 ? "1 clip" : "\(count.formatted()) clips", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        let selected = state.selectedClips
        if !selected.isEmpty {
            ClipMenus.addItems(for: selected, to: menu, model: model, state: state, actions: actions)
            menu.addItem(.separator())
        }
        if model.stack.isActive {
            menu.addItem(ClosureMenuItem("Stop Paste Stack", key: "c", modifiers: [.command, .shift]) { actions.pasteStack([]) })
        } else if selected.count < 2 {
            menu.addItem(ClosureMenuItem("Start Paste Stack", key: "c", modifiers: [.command, .shift]) { actions.pasteStack([]) })
        }
        menu.addItem(ClosureMenuItem("New Board", key: "n", modifiers: [.command, .shift]) { actions.newBoard([]) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Open History", key: "y") {
            actions.dismiss()
            HistoryOpener.open()
        })
        if model.isPaused {
            menu.addItem(ClosureMenuItem("Resume Recording", key: "t") { model.resume() })
        } else {
            let pause = NSMenuItem(title: "Pause Recording", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            sub.addItem(ClosureMenuItem("For 15 Minutes") { model.pause(for: 15 * 60) })
            sub.addItem(ClosureMenuItem("For 1 Hour") { model.pause(for: 3_600) })
            sub.addItem(ClosureMenuItem("Until I Resume", key: "t") { model.pause(for: nil) })
            pause.submenu = sub
            menu.addItem(pause)
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Settings…", key: ",") {
            actions.dismiss()
            SettingsOpener.open()
        })
        menu.addItem(ClosureMenuItem("Clear History…") {
            actions.dismiss()
            ClearHistory.confirm(model: model)
        })
        return menu
    }
}

/// A borderless ⋯ button that pops up a freshly built menu.
final class PanelMenuButton: NSButton {
    var build: (() -> NSMenu)?

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: PanelMetrics.controlHeight, height: PanelMetrics.controlHeight))
        isBordered = false
        bezelStyle = .accessoryBarAction
        image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
        imagePosition = .imageOnly
        contentTintColor = .labelColor
        target = self
        action = #selector(open)
        setAccessibilityLabel("More")
        toolTip = "More: actions, History, Settings (Return pastes, ⇧Return plain text, Space previews, ⌘P pins, ⌘⌫ deletes)"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: PanelMetrics.controlHeight, height: PanelMetrics.controlHeight)
    }

    @objc private func open() {
        guard let menu = build?() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY + Spacing.xs), in: self)
    }
}

// MARK: - Quick Look

/// The selected clip, big: what Space shows above the strip.
struct QuickLookView: View {
    let state: PanelState
    /// Ends the editor (⌘E / ⌘R turn the preview into one): true saves.
    let finishEditing: (_ save: Bool) -> Void
    @Environment(\.floatingPanelCornerRadius) private var panelRadius

    /// The content sits on its own text-background surface, `Spacing.s` in from the panel's
    /// edges and concentric with them, so it stays readable over any wallpaper and at any
    /// glass setting (the header line is on the glass, like the strip's top bar).
    private var surfaceRadius: CGFloat { Radius.nested(in: panelRadius, padding: Spacing.s) }

    var body: some View {
        Group {
            if let clip = state.selected, let editor = state.editor, editor.clipID == clip.id {
                ClipEditorView(session: editor, clip: clip, onDone: finishEditing, surfaceRadius: surfaceRadius)
                    .padding(.bottom, editor.editsText || editor.dropsFormatting ? 0 : Spacing.s)
            } else if let clip = state.selected {
                VStack(spacing: 0) {
                    HStack(spacing: Spacing.s) {
                        Text(ClipText.headerTitle(of: clip)).font(.headline).lineLimit(1)
                        ClipSourceLine(clip: clip, now: state.now)
                        Spacer(minLength: Spacing.s)
                        Text(ClipEdit.canEditText(clip) ? "⌘E to edit · Space to close" : "⌘R to add a title · Space to close")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, Spacing.l)
                    .frame(height: QuickLookMetrics.headerHeight)
                    ClipContentView(clip: clip)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        // Shapes inside (the image) are concentric with this surface.
                        .environment(\.floatingPanelCornerRadius, surfaceRadius)
                        .background(Color(nsColor: .textBackgroundColor),
                                    in: RoundedRectangle(cornerRadius: surfaceRadius, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: surfaceRadius, style: .continuous))
                        .padding([.horizontal, .bottom], Spacing.s)
                }
            } else {
                Color.clear
            }
        }
        .frame(width: QuickLookMetrics.size.width, height: QuickLookMetrics.size.height)
    }
}

enum QuickLookMetrics {
    static let size = CGSize(width: 660, height: 440)
    static let headerHeight: CGFloat = 40
    static let gap: CGFloat = 10
}
