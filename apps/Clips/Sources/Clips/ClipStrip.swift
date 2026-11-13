import AppKit
import ClipsCore
import SlopKit
import SwiftUI

/// The panel's row of cards, newest on the left. Only the cards on screen exist (about a
/// dozen, reused while scrolling), so 10,000 results cost no more than 10. The search field
/// keeps the keyboard; the panel's key handler moves the selection.
struct ClipStrip: NSViewRepresentable {
    let state: PanelState
    let actions: PanelActions
    @Environment(\.floatingPanelCornerRadius) private var panelRadius

    func makeNSView(context: Context) -> ClipStripView {
        let view = ClipStripView()
        view.state = state
        view.actions = actions
        return view
    }

    func updateNSView(_ view: ClipStripView, context: Context) {
        view.cardRadius = PanelMetrics.cardRadius(inPanel: panelRadius)
        // Reading these registers observation, so SwiftUI calls us again when they change.
        view.sync(resultsVersion: state.resultsVersion, selection: state.selection, scrollRequest: state.scrollRequest,
                  now: state.now, showsNumbers: state.commandHeld)
    }
}

@MainActor
final class ClipStripView: NSView {
    static let layout = PanelMetrics.strip
    static let verticalInset = PanelMetrics.stripVerticalInset
    static var height: CGFloat { PanelMetrics.stripHeight }

    weak var state: PanelState?
    var actions: PanelActions?
    /// Concentric with the panel's corner (see `PanelMetrics.cardRadius`).
    var cardRadius = PanelMetrics.cardRadius(inPanel: PanelMetrics.cornerRadius) {
        didSet {
            guard cardRadius != oldValue else { return }
            for card in visible.values { card.cornerRadius = cardRadius }
            for card in spare { card.cornerRadius = cardRadius }
        }
    }

    private let scrollView = StripScrollView()
    private let documentView = StripDocumentView()
    private var visible: [Int: ClipCardView] = [:]
    private var spare: [ClipCardView] = []
    private var clips: [Clip] = []
    private var query = ""
    private var now = Date()
    private var selectedIndex: Int?
    /// Every selected card (several after ⇧/⌘-click, ⇧-arrows or ⌘A).
    private var selectedIDs: Set<UUID> = []
    private var showsNumbers = false
    private var resultsVersion = -1
    private var scrollRequest = -1
    /// Image payloads fetched when a card is pressed, so dragging it out has the data ready.
    private var dragPayloads: [UUID: ClipPayload] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        // No scroller: it drew over the cards. Trackpad, wheel and keys scroll the strip.
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = documentView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tile() }
        }
        documentView.setAccessibilityElement(true)
        documentView.setAccessibilityRole(.list)
        documentView.setAccessibilityLabel("Clips")
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        updateDocumentSize()
        tile()
    }

    // MARK: - Sync with the panel state

    func sync(resultsVersion: Int, selection: StripSelection, scrollRequest: Int, now: Date, showsNumbers: Bool) {
        guard let state else { return }
        var reconfigure = false
        if resultsVersion != self.resultsVersion || now != self.now {
            self.resultsVersion = resultsVersion
            self.now = now
            clips = state.results
            query = state.query
            dragPayloads.removeAll()
            updateDocumentSize()
            reconfigure = true
        }
        let newSelection = state.selectedIndex
        if newSelection != selectedIndex || selection.ids != selectedIDs {
            selectedIndex = newSelection
            selectedIDs = selection.ids
            for card in visible.values {
                card.setSelected(card.clip.map { selectedIDs.contains($0.id) } ?? false)
            }
        }
        if showsNumbers != self.showsNumbers {
            self.showsNumbers = showsNumbers
            for card in visible.values { card.setShowsNumber(showsNumbers) }
        }
        if reconfigure {
            for (index, card) in visible where clips.indices.contains(index) {
                configure(card, at: index)
            }
        }
        if scrollRequest != self.scrollRequest {
            self.scrollRequest = scrollRequest
            if let index = selectedIndex {
                reveal(index)
            } else {
                scroll(to: 0)
            }
        }
        tile()
        state.pageSize = Self.layout.pageSize(viewportWidth: Double(scrollView.contentView.bounds.width))
    }

    private func updateDocumentSize() {
        let width = max(CGFloat(Self.layout.contentWidth(count: clips.count)), scrollView.contentView.bounds.width)
        let size = CGSize(width: width, height: max(scrollView.contentView.bounds.height, Self.height))
        if documentView.frame.size != size { documentView.setFrameSize(size) }
    }

    private func reveal(_ index: Int) {
        let clip = scrollView.contentView
        let current = Double(clip.bounds.origin.x)
        let target = index == 0 ? 0 : Self.layout.offset(revealing: index, from: current,
                                                          viewportWidth: Double(clip.bounds.width), count: clips.count)
        if target != current { scroll(to: CGFloat(target)) }
    }

    private func scroll(to x: CGFloat) {
        scrollView.contentView.scroll(to: NSPoint(x: x, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - Tiling

    /// Places a card for every clip in view, reusing the ones that scrolled out.
    private func tile() {
        let bounds = scrollView.contentView.bounds
        let range = Self.layout.visibleRange(offset: Double(bounds.minX), viewportWidth: Double(bounds.width), count: clips.count)
        for (index, card) in visible where !range.contains(index) {
            card.isHidden = true
            spare.append(card)
            visible[index] = nil
        }
        for index in range where visible[index] == nil {
            let card = spare.popLast() ?? makeCard()
            card.isHidden = false
            card.frame = CGRect(x: CGFloat(Self.layout.x(of: index)), y: Self.verticalInset,
                                width: ClipCardView.size.width, height: ClipCardView.size.height)
            configure(card, at: index)
            visible[index] = card
        }
        // Don't hoard cards that scrolled away (or a parked, narrow panel's leftovers).
        while spare.count > 4 { spare.removeLast().removeFromSuperview() }
        let ordered = range.compactMap { visible[$0] }
        documentView.setAccessibilityChildren(ordered)
    }

    private func makeCard() -> ClipCardView {
        let card = ClipCardView(frame: CGRect(origin: .zero, size: ClipCardView.size))
        card.cornerRadius = cardRadius
        card.strip = self
        documentView.addSubview(card)
        return card
    }

    private func configure(_ card: ClipCardView, at index: Int) {
        let clip = clips[index]
        card.configure(clip: clip, index: index, number: index < 9 ? index + 1 : nil, now: now, query: query,
                       selected: selectedIDs.contains(clip.id) || index == selectedIndex, showsNumber: showsNumbers,
                       board: clip.boardID.flatMap { AppModel.shared.boards.board(id: $0) })
    }

    // MARK: - Card events

    /// A click: ⌘ adds or removes the card, ⇧ selects the range to it, a double-click pastes.
    func cardClicked(_ card: ClipCardView, clickCount: Int, modifiers: NSEvent.ModifierFlags = []) {
        guard let state, let clip = card.clip else { return }
        let command = modifiers.contains(.command), shift = modifiers.contains(.shift)
        // Pressing a selected card of several keeps them all (it may be the start of a drag).
        if !command, !shift, state.isMultipleSelection, state.selection.contains(clip.id), clickCount == 1 {
            pendingCollapse = clip.id
        } else {
            state.click(clip.id, command: command, shift: shift)
        }
        if clickCount >= 2, !command, !shift {
            actions?.choose([clip], false)
        } else if clip.kind == .image, dragPayloads[clip.id] == nil {
            let id = clip.id
            Task { [weak self] in
                if let payload = await AppModel.shared.payload(for: id) { self?.dragPayloads[id] = payload }
            }
        }
    }

    /// A press on one of several selected cards that turned out to be a click, not a drag:
    /// now it selects just that card.
    private var pendingCollapse: UUID?

    func cardMouseUp(_ card: ClipCardView) {
        guard let id = pendingCollapse else { return }
        pendingCollapse = nil
        if card.clip?.id == id { state?.selectedID = id }
    }

    /// The clips a drag or a right-click on `card` acts on: the selection if the card is in
    /// it, else just the card.
    func targets(for card: ClipCardView) -> [Clip] {
        guard let state, let clip = card.clip else { return [] }
        if state.isMultipleSelection, state.selection.contains(clip.id) { return state.selectedClips }
        return [clip]
    }

    func dragStarted() {
        pendingCollapse = nil
    }

    /// What a card puts on the drag pasteboard: text, file URLs, or an image file and its data.
    func dragWriters(for clip: Clip) -> [NSPasteboardWriting] {
        switch clip.kind {
        case .text, .link, .color:
            return [clip.text as NSString]
        case .file:
            return clip.filePaths.map { URL(fileURLWithPath: $0) as NSURL }
        case .image:
            let image = dragPayloads[clip.id]?.items.first.flatMap(ImageExport.image(in:))
            return [ImageDragProvider(clip: clip, image: image)]
        }
    }

    /// The drag is over `point` (screen): true while it's over a board tab.
    func dragMoved(to point: NSPoint) -> Bool {
        actions?.dragMoved(point) ?? false
    }

    func dragEnded(at point: NSPoint, clips: [Clip]) -> Bool {
        actions?.dragEnded(point, clips) ?? false
    }

    func menu(for card: ClipCardView) -> NSMenu? {
        guard let state, let actions, let clip = card.clip else { return nil }
        let clips = targets(for: card)
        if clips.count == 1 { state.selectedID = clip.id }
        let menu = NSMenu()
        ClipMenus.addItems(for: clips, to: menu, model: AppModel.shared, state: state, actions: actions)
        return menu
    }
}

/// Holds the cards. Top-left origin.
final class StripDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// Scrolls sideways with an ordinary mouse wheel too (vertical wheel → horizontal scroll).
final class StripScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX), let document = documentView else {
            super.scrollWheel(with: event)
            return
        }
        let step = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 16
        var origin = contentView.bounds.origin
        let maxX = max(0, document.frame.width - contentView.bounds.width)
        origin.x = min(max(origin.x - step, 0), maxX)
        contentView.scroll(to: origin)
        reflectScrolledClipView(contentView)
    }
}
