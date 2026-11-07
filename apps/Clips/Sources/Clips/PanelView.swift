import AppKit
import ClipsCore
import SlopKit
import SwiftUI

struct PanelActions {
    let choose: (Clip, _ plain: Bool) -> Void
    let copy: (Clip) -> Void
    let togglePin: (Clip) -> Void
    let delete: (Clip) -> Void
    let preview: (Clip) -> Void
    let open: (Clip) -> Void
    let reveal: (Clip) -> Void
    let dismiss: () -> Void
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

    @FocusState private var searchFocused: Bool

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
        .onAppear { searchFocused = true }
        .onChange(of: state.focusRequest) { searchFocused = true }
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
                TabBar(filter: $state.filter)
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
                .focused($searchFocused)
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
            NoticeLabel(notice: notice)
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
            } else if state.filter == .pinned {
                ContentUnavailableView("No Pinned Clips", systemImage: "pin",
                                       description: Text("Press ⌘P to pin the selected clip. Pinned clips are never removed automatically."))
            } else if state.filter != .all {
                ContentUnavailableView("No \(state.filter.title)", systemImage: state.filter.systemImage,
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

/// All, Pinned and the kinds of clip. ⌘← / ⌘→ switch.
struct TabBar: View {
    @Binding var filter: ClipFilter

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(ClipFilter.allCases) { item in
                let selected = item == filter
                Button {
                    filter = item
                } label: {
                    ZStack {
                        // Reserve the semibold width so switching tabs never shifts the row.
                        Text(item.title).font(.callout.weight(.semibold)).hidden()
                        Text(item.title).font(.callout.weight(selected ? .semibold : .regular))
                    }
                        .padding(.horizontal, Spacing.m)
                        .frame(height: PanelMetrics.controlHeight)
                        .background {
                            if selected { Capsule().fill(.quaternary) }
                        }
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .help("Show \(item.title.lowercased()) (⌘← ⌘→ switch)")
            }
        }
    }
}

extension ClipFilter {
    var systemImage: String {
        switch self {
        case .all: "tray.full"
        case .pinned: "pin"
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

    enum Action { case clipboardSettings, accessibility, resume }

    @MainActor
    static func current(model: AppModel, state: PanelState) -> PanelNotice? {
        if let error = model.storageError {
            return PanelNotice(systemImage: "exclamationmark.triangle", text: error)
        }
        if let pending = state.pendingPinnedDelete, let clip = state.results.first(where: { $0.id == pending }) {
            return PanelNotice(systemImage: "pin", text: "“\(ClipText.title(of: clip, limit: 30))” is pinned. Press ⌘⌫ again to delete it.")
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
        if let paused = model.pauseDescription {
            return PanelNotice(systemImage: "pause.circle", text: "\(paused). New copies aren't recorded.", button: "Resume", action: .resume)
        }
        return nil
    }
}

struct NoticeLabel: View {
    let notice: PanelNotice

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: notice.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(notice.text)
                .font(.caption)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .help(notice.text)
            if let button = notice.button, let action = notice.action {
                Button(button) { run(action) }
                    .controlSize(.small)
                    .fixedSize()
            }
        }
    }

    @MainActor private func run(_ action: PanelNotice.Action) {
        switch action {
        case .clipboardSettings: ClipboardAccess.openSettings()
        case .accessibility: Permission.accessibility.request()
        case .resume: AppModel.shared.resume()
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
        if let clip = state.selected {
            let paste = model.willPasteDirectly(into: state.target) ? state.targetName.map { "Paste in \($0)" } ?? "Paste" : "Copy"
            menu.addItem(ClosureMenuItem(paste) { actions.choose(clip, false) })
            if clip.kind != .image, clip.kind != .file {
                menu.addItem(ClosureMenuItem("\(paste) as Plain Text") { actions.choose(clip, true) })
            }
            menu.addItem(ClosureMenuItem("Preview") { actions.preview(clip) })
            menu.addItem(ClosureMenuItem(clip.isPinned ? "Unpin" : "Pin") { actions.togglePin(clip) })
            menu.addItem(ClosureMenuItem("Delete") { actions.delete(clip) })
            menu.addItem(.separator())
        }
        menu.addItem(ClosureMenuItem("Open History") {
            actions.dismiss()
            HistoryOpener.open()
        })
        if model.isPaused {
            menu.addItem(ClosureMenuItem("Resume Recording") { model.resume() })
        } else {
            let pause = NSMenuItem(title: "Pause Recording", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            sub.addItem(ClosureMenuItem("For 15 Minutes") { model.pause(for: 15 * 60) })
            sub.addItem(ClosureMenuItem("For 1 Hour") { model.pause(for: 3_600) })
            sub.addItem(ClosureMenuItem("Until I Resume") { model.pause(for: nil) })
            pause.submenu = sub
            menu.addItem(pause)
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Settings…") {
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
    @Environment(\.floatingPanelCornerRadius) private var panelRadius

    /// The content sits on its own text-background surface, `Spacing.s` in from the panel's
    /// edges and concentric with them, so it stays readable over any wallpaper and at any
    /// glass setting (the header line is on the glass, like the strip's top bar).
    private var surfaceRadius: CGFloat { Radius.nested(in: panelRadius, padding: Spacing.s) }

    var body: some View {
        Group {
            if let clip = state.selected {
                VStack(spacing: 0) {
                    HStack(spacing: Spacing.s) {
                        Text(ClipText.kindName(of: clip)).font(.headline)
                        ClipSourceLine(clip: clip, now: state.now)
                        Spacer(minLength: Spacing.s)
                        Text("Space to close").font(.caption).foregroundStyle(.secondary)
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
