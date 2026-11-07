import AppKit
import QuartzCore
import SlopKit
import SpecimenCore
import SwiftUI

/// The font grid: an NSCollectionView (cell reuse, only visible cards exist) wrapped for SwiftUI.
struct FontGrid: NSViewRepresentable {
    var model: AppModel

    func makeCoordinator() -> FontGridController { FontGridController(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeScrollView()
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        // Reading these here makes SwiftUI call us again when they change.
        let state = FontGridController.State(
            itemsVersion: model.itemsVersion, previewText: model.previewText, previewSize: model.previewSize,
            selection: model.selection, favorites: model.favorites, focusRequest: model.focusGridRequest,
            tray: model.tray
        )
        context.coordinator.update(state)
    }
}

@MainActor
final class FontGridController: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
    struct State: Equatable {
        var itemsVersion: Int
        var previewText: String
        var previewSize: Double
        var selection: Set<String>
        var favorites: Set<String>
        var focusRequest: Int
        var tray: CompareTray
    }

    let model: AppModel
    private(set) var collectionView: FontCollectionView!
    private var layout: FontGridLayout!
    private var items: [GridEntry] = []
    private var state: State?
    private var applyingSelection = false
    /// The preview text the visible cards were last given (benchmarks wait for it).
    var appliedPreviewText: String? { state?.previewText }
    /// When the last preview text change reached the grid (benchmarks).
    private(set) var previewAppliedAt: CFTimeInterval = 0

    init(model: AppModel) {
        self.model = model
    }

    func makeScrollView() -> NSScrollView {
        layout = FontGridLayout()
        collectionView = FontCollectionView()
        collectionView.controller = self
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(FontCardItem.self, forItemWithIdentifier: FontCardItem.identifier)
        // Drag cards onto a tag in the sidebar (or family names into any text field).
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: true)
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
        collectionView.setAccessibilityLabel("Fonts")
        let scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = true
        observeWindowAndColors()
        return scrollView
    }

    /// Cards repaint when their window becomes or stops being the active one (selection and
    /// accent marks go grey in the background), and when the accent colour changes.
    private func observeWindowAndColors() {
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let window = note.object as? NSWindow
                MainActor.assumeIsolated {
                    guard let self, let window, window === self.collectionView?.window else { return }
                    self.refreshCardsForWindowState()
                }
            }
        }
        center.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                FontCardView.clearSymbolCache()
                self?.refreshCardsForWindowState()
            }
        }
    }

    private func refreshCardsForWindowState() {
        for case let item as FontCardItem in collectionView.visibleItems() {
            item.cardView.refreshForWindowState()
        }
    }

    func update(_ new: State) {
        let old = state
        state = new
        if old?.itemsVersion != new.itemsVersion {
            items = model.items
            collectionView.reloadData()
            applySelection(new.selection)
            if let first = new.selection.first, let index = items.firstIndex(where: { $0.id == first }) {
                collectionView.scrollToItems(at: [IndexPath(item: index, section: 0)], scrollPosition: .nearestHorizontalEdge)
            }
        } else if old?.selection != new.selection {
            applySelection(new.selection)
        }
        if old?.previewSize != new.previewSize {
            layout.previewSize = CGFloat(new.previewSize)
            layout.invalidateLayout()
        }
        if old?.previewText != new.previewText || old?.previewSize != new.previewSize || old?.favorites != new.favorites
            || old?.tray != new.tray {
            if old?.previewText != new.previewText { previewAppliedAt = CACurrentMediaTime() }
            refreshVisibleCards()
        }
        if let old, old.focusRequest != new.focusRequest {
            focus()
        }
    }

    func focus() {
        collectionView.window?.makeFirstResponder(collectionView)
        if model.selection.isEmpty, !items.isEmpty {
            select(indexes: [0], anchor: 0)
        } else if let index = items.firstIndex(where: { model.selection.contains($0.id) }) {
            // e.g. fonts just added: bring the selection into view.
            collectionView.scrollToItems(at: [IndexPath(item: index, section: 0)], scrollPosition: .nearestHorizontalEdge)
        }
    }

    private func refreshVisibleCards() {
        for case let item as FontCardItem in collectionView.visibleItems() {
            if let indexPath = collectionView.indexPath(for: item), indexPath.item < items.count {
                configure(item, with: items[indexPath.item])
            }
        }
    }

    private func configure(_ card: FontCardItem, with item: GridEntry) {
        card.cardView.configure(
            item: item, text: model.previewText, size: CGFloat(model.previewSize),
            isFavorite: model.favorites.contains(item.family.name),
            lock: model.lockReason(for: item.family), grouped: model.groupByFamily,
            inTray: model.isInTray(item)
        )
        card.cardView.onToggleTray = { [weak self] in
            self?.model.toggleTray(item)
        }
        card.cardView.onToggleFavorite = { [weak self] in
            guard let self else { return }
            model.setFavorite(!model.favorites.contains(item.family.name), families: [item.family.name])
        }
        card.cardView.onPress = { [weak self] in
            guard let self, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
            select(indexes: [index], anchor: index)
        }
    }

    // MARK: Selection

    private func applySelection(_ ids: Set<String>) {
        let wanted = Set(items.indices.filter { ids.contains(items[$0].id) }.map { IndexPath(item: $0, section: 0) })
        guard wanted != collectionView.selectionIndexPaths else { return }
        applyingSelection = true
        collectionView.selectionIndexPaths = wanted
        applyingSelection = false
    }

    private func syncSelectionToModel() {
        guard !applyingSelection else { return }
        let ids = Set(collectionView.selectionIndexPaths.compactMap { $0.item < items.count ? items[$0.item].id : nil })
        if ids != model.selection { model.selection = ids }
    }

    func select(indexes: [Int], anchor: Int?, extend: Bool = false) {
        var paths = Set(indexes.filter { $0 >= 0 && $0 < items.count }.map { IndexPath(item: $0, section: 0) })
        if extend { paths.formUnion(collectionView.selectionIndexPaths) }
        collectionView.selectionIndexPaths = paths
        if let anchor { collectionView.anchor = anchor }
        if let last = indexes.last, last >= 0, last < items.count {
            collectionView.scrollToItems(at: [IndexPath(item: last, section: 0)], scrollPosition: .nearestHorizontalEdge)
        }
        syncSelectionToModel()
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        syncSelectionToModel()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        syncSelectionToModel()
    }

    // MARK: Dragging

    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        true
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
        guard indexPath.item < items.count else { return nil }
        return items[indexPath.item].family.name as NSString
    }

    // MARK: Data source

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let card = collectionView.makeItem(withIdentifier: FontCardItem.identifier, for: indexPath) as! FontCardItem
        configure(card, with: items[indexPath.item])
        return card
    }

    // MARK: Keyboard and mouse (called by FontCollectionView)

    var columns: Int { layout.columns }
    var itemCount: Int { items.count }
    var titles: [String] { items.map(\.title) }

    func item(at index: Int) -> GridEntry? { index >= 0 && index < items.count ? items[index] : nil }

    func open(index: Int?) {
        if let index, let item = item(at: index) {
            model.selection = [item.id]
            model.openDetail(item)
        } else {
            model.openDetail()
        }
    }

    func toggleTray() {
        model.toggleTraySelection()
    }

    func clearSelectionOrSearch() {
        if !model.selection.isEmpty {
            collectionView.selectionIndexPaths = []
            syncSelectionToModel()
        } else if !model.search.isEmpty {
            model.search = ""
        }
    }

    func contextMenu(for index: Int?) -> NSMenu? {
        if let index, let item = item(at: index), !model.selection.contains(item.id) {
            select(indexes: [index], anchor: index)
        }
        guard !model.selection.isEmpty else { return nil }
        return ContextMenuBuilder(model: model).menu()
    }
}

/// Grid math in closed form, so layout cost depends on what's visible, not on library size.
final class FontGridLayout: NSCollectionViewLayout {
    var previewSize: CGFloat = 36
    private(set) var columns = 1
    private var itemSize = CGSize(width: 300, height: 100)
    private let spacing: CGFloat = Spacing.m
    private let inset: CGFloat = Spacing.l
    private var count = 0

    static func cardHeight(previewSize: CGFloat) -> CGFloat {
        FontCardView.headerHeight + FontCardView.previewHeight(for: previewSize) + FontCardView.footerHeight
    }

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        count = collectionView.numberOfSections > 0 ? collectionView.numberOfItems(inSection: 0) : 0
        let width = max(collectionView.enclosingScrollView?.contentView.bounds.width ?? collectionView.bounds.width, 200) - inset * 2
        // Typeface-like density: about three cards across a normal window at 30–36 pt.
        let minimum = min(max(previewSize * 6.5, 210), 1400)
        columns = max(1, Int((width + spacing) / (minimum + spacing)))
        let itemWidth = floor((width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        itemSize = CGSize(width: itemWidth, height: ceil(Self.cardHeight(previewSize: previewSize)))
    }

    override var collectionViewContentSize: NSSize {
        let rows = (count + columns - 1) / columns
        let width = collectionView?.enclosingScrollView?.contentView.bounds.width ?? 0
        return NSSize(width: width, height: inset * 2 + CGFloat(rows) * itemSize.height + CGFloat(max(rows - 1, 0)) * spacing)
    }

    private func frame(for index: Int) -> NSRect {
        let row = index / columns, column = index % columns
        return NSRect(x: inset + CGFloat(column) * (itemSize.width + spacing),
                      y: inset + CGFloat(row) * (itemSize.height + spacing),
                      width: itemSize.width, height: itemSize.height)
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        guard count > 0 else { return [] }
        let rowHeight = itemSize.height + spacing
        let firstRow = max(0, Int((rect.minY - inset) / rowHeight))
        let lastRow = max(0, Int((rect.maxY - inset) / rowHeight))
        let start = firstRow * columns
        let end = min(count - 1, (lastRow + 1) * columns - 1)
        guard start <= end else { return [] }
        return (start...end).compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.item < count else { return nil }
        let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
        attributes.frame = frame(for: indexPath.item)
        return attributes
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        abs(newBounds.width - (collectionView?.bounds.width ?? 0)) > 0.5
    }
}

/// Keyboard: arrows (⇧ extends), Space opens, Return collects into the compare tray,
/// Esc clears, letters jump, ⌘A, ⌘C.
final class FontCollectionView: NSCollectionView {
    weak var controller: FontGridController?
    var anchor = 0
    private var typeAhead = ""
    private var typeAheadTime = Date.distantPast

    override var acceptsFirstResponder: Bool { true }

    private var current: Int? {
        selectionIndexPaths.map(\.item).max()
    }

    /// The item the keyboard is on (the moving end of a ⇧-extended selection).
    var cursor: Int?

    override func keyDown(with event: NSEvent) {
        guard let controller else { return super.keyDown(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let extend = flags.contains(.shift)
        let count = controller.itemCount
        guard count > 0 else { return super.keyDown(with: event) }
        let position = (cursor.flatMap { selectionIndexPaths.contains(IndexPath(item: $0, section: 0)) ? $0 : nil }) ?? current
        func move(_ delta: Int) {
            let target = position.map { min(max($0 + delta, 0), count - 1) } ?? 0
            go(to: target, extend: extend)
        }
        switch event.keyCode {
        case 123: move(-1)   // ←
        case 124: move(1)    // →
        case 125:            // ↓ (⌘↓ opens)
            if flags.contains(.command) { controller.open(index: position); return }
            move(controller.columns)
        case 126: move(-controller.columns)   // ↑
        case 115: go(to: 0, extend: extend)   // Home
        case 119: go(to: count - 1, extend: extend)   // End
        case 116: move(-controller.columns * 4)   // Page Up
        case 121: move(controller.columns * 4)    // Page Down
        case 49: controller.open(index: position)   // Space: details
        case 36, 76: controller.toggleTray()   // Return, Enter: add to (or take out of) the compare tray
        case 53: controller.clearSelectionOrSearch()   // Esc
        default:
            if flags.isDisjoint(with: [.command, .control, .option]), let characters = event.characters,
               let scalar = characters.unicodeScalars.first, !CharacterSet.controlCharacters.contains(scalar) {
                let now = Date()
                if now.timeIntervalSince(typeAheadTime) > 1 { typeAhead = "" }
                typeAheadTime = now
                typeAhead += characters
                if let index = LibraryFilter.typeAheadIndex(typeAhead, in: controller.titles) {
                    go(to: index, extend: false)
                }
            } else {
                super.keyDown(with: event)
            }
        }
    }

    func go(to target: Int, extend: Bool) {
        guard let controller else { return }
        if extend {
            let range = min(anchor, target)...max(anchor, target)
            controller.select(indexes: Array(range).filter { $0 != target } + [target], anchor: nil)
        } else {
            controller.select(indexes: [target], anchor: target)
        }
        cursor = target
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = indexPathForItem(at: point)?.item
        if event.clickCount == 2, let index {
            controller?.open(index: index)
            return
        }
        super.mouseDown(with: event)
        if let index {
            cursor = index
            if !event.modifierFlags.contains(.shift) { anchor = index }
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        return controller?.contextMenu(for: indexPathForItem(at: point)?.item)
    }

    @objc func copy(_ sender: Any?) {
        controller?.model.copyNames(postScript: false)
    }

    override func selectAll(_ sender: Any?) {
        controller?.model.selectAll()
    }

}

extension FontCollectionView: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(copy(_:)) { return !(controller?.model.selection.isEmpty ?? true) }
        return true
    }
}

final class FontCardItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("FontCard")
    let cardView = FontCardView()

    override func loadView() { view = cardView }

    override var isSelected: Bool {
        didSet { cardView.isSelected = isSelected }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cardView.updateTrackingAreas()
    }
}

/// One card, laid out like a type specimen tile: a small status mark and the family name
/// along the top, the style count on the right, the preview large and centred, and (on
/// hover, or when collected) the compare-tray button in the bottom-right corner.
final class FontCardView: NSView {
    /// Inset of everything in the card from its left and right edges (status mark, name,
    /// caption, preview; count, star, collect button).
    static let inset: CGFloat = Spacing.m
    static let headerHeight: CGFloat = 26
    static let footerHeight: CGFloat = 22
    /// The header's centre line (status mark, name caps, count, star) from the top, and the
    /// footer's (caption, collect button) from the bottom: the same, so the card is balanced.
    static let edgeCentre: CGFloat = 13
    static func previewHeight(for size: CGFloat) -> CGFloat { PreviewMetrics.height(for: size) }

    var isSelected = false { didSet { if isSelected != oldValue { needsDisplay = true; updateAccessibility() } } }
    var onToggleFavorite: (() -> Void)?
    var onToggleTray: (() -> Void)?
    var onPress: (() -> Void)?

    private var item: GridEntry?
    private var text = ""
    private var size: CGFloat = 36
    private var isFavorite = false
    private var inTray = false
    private var lock: LockReason?
    private var grouped = true
    private var isHovered = false { didSet { if isHovered != oldValue { updateButtons(); needsDisplay = true } } }
    private let starButton = NSButton()
    private let trayButton = NSButton()
    private var caption: String?
    private var countText = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        for button in [starButton, trayButton] {
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.imagePosition = .imageOnly
            button.target = self
            addSubview(button)
        }
        starButton.action = #selector(toggleFavorite)
        trayButton.action = #selector(toggleTray)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { false }

    func configure(item: GridEntry, text: String, size: CGFloat, isFavorite: Bool, lock: LockReason?, grouped: Bool, inTray: Bool) {
        self.item = item
        self.text = text
        self.size = size
        self.isFavorite = isFavorite
        self.inTray = inTray
        self.lock = lock
        self.grouped = grouped
        let count = grouped ? item.family.faces.count : 0
        countText = count > 1 ? "\(count)" : ""
        let starLabel = isFavorite ? "Remove from Favorites" : "Add to Favorites"
        starButton.image = NSImage(systemSymbolName: isFavorite ? "star.fill" : "star", accessibilityDescription: starLabel)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
        starButton.contentTintColor = isFavorite ? Self.accent(windowIsActive) : .secondaryLabelColor
        starButton.setAccessibilityLabel("\(starLabel): \(item.family.displayName)")
        starButton.toolTip = "\(starLabel) (⌘D)"
        let trayLabel = inTray ? "Remove from Compare" : "Add to Compare"
        trayButton.image = NSImage(systemSymbolName: inTray ? "checkmark.circle.fill" : "plus.circle", accessibilityDescription: trayLabel)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        trayButton.contentTintColor = inTray ? Self.accent(windowIsActive) : .secondaryLabelColor
        trayButton.setAccessibilityLabel("\(trayLabel): \(item.title)")
        trayButton.toolTip = "\(trayLabel) (Return)"
        caption = nil
        updateButtons()
        needsLayout = true
        needsDisplay = true
        updateAccessibility()
    }

    /// Buttons fade in on hover; they stay visible when they hold state (favourite, collected).
    /// Hidden ones keep alpha 0 rather than isHidden so VoiceOver still finds them.
    private func updateButtons() {
        starButton.alphaValue = isFavorite || isHovered ? 1 : 0
        trayButton.alphaValue = inTray || isHovered ? 1 : 0
    }

    /// Width of the style count on the right of the header (0 when there's none).
    private var countWidth: CGFloat {
        countText.isEmpty ? 0 : ceil((countText as NSString).size(withAttributes: [.font: Self.smallFont]).width)
    }

    /// The star's slot, left of the count. Always reserved, so the name never re-truncates
    /// (jumps) when the star fades in on hover.
    private var starSlot: NSRect {
        let side: CGFloat = 18
        let glyph = starButton.image?.size.width ?? 12
        // Glyph's right edge on the inset line, or a Spacing.xs gap before the count.
        let glyphRight = bounds.maxX - Self.inset - (countText.isEmpty ? 0 : countWidth + Spacing.xs)
        let centreX = glyphRight - glyph / 2
        return NSRect(x: (centreX - side / 2).rounded(), y: Self.edgeCentre - side / 2, width: side, height: side)
    }

    override func layout() {
        super.layout()
        starButton.frame = starSlot
        // The collect button's glyph sits on the right inset line, centred on the footer's line.
        let side: CGFloat = 20
        let glyph = trayButton.image?.size.width ?? 15
        let centreX = bounds.maxX - Self.inset - glyph / 2
        trayButton.frame = NSRect(x: (centreX - side / 2).rounded(), y: bounds.maxY - Self.edgeCentre - side / 2, width: side, height: side)
    }

    // MARK: Hover

    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
        if let window, let point = window.mouseLocationOutsideOfEventStream as NSPoint? {
            isHovered = bounds.contains(convert(point, from: nil))
        }
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    @objc private func toggleFavorite() { onToggleFavorite?() }
    @objc private func toggleTray() { onToggleTray?() }

    // MARK: Drawing

    private static var nameFont: NSFont { NSFont.preferredFont(forTextStyle: .subheadline) }
    private static var smallFont: NSFont { NSFont.preferredFont(forTextStyle: .caption1) }

    /// Shown after the name when it isn't obvious which card is which.
    private var nameDetail: String? {
        guard let item, !grouped else { return nil }
        // Two files with the same PostScript name: say which folder this copy is in.
        let face = item.representative
        if item.family.faces.contains(where: { $0.postScriptName == face.postScriptName && $0.id != face.id }),
           let folder = face.path.map({ URL(fileURLWithPath: $0).deletingLastPathComponent().lastPathComponent }) {
            return "in \(folder)"
        }
        return nil
    }

    private var stateDescription: (symbol: String, text: String) {
        guard let item else { return ("", "") }
        let state = grouped ? item.family.state : ActivationState(faces: item.faces)
        if let lock, state == .active { return ("lock.fill", "Active, \(lock.title)") }
        switch state {
        case .active: return ("circle.fill", "Active")
        case .inactive: return ("circle", "Inactive")
        case .mixed: return ("circle.lefthalf.filled", "Partly active")
        }
    }

    /// When a card last finished drawing (benchmarks).
    static var lastDrawEnd: CFTimeInterval = 0
    /// Total time spent drawing cards (benchmarks).
    static var totalDrawTime: CFTimeInterval = 0

    override func draw(_ dirtyRect: NSRect) {
        let drawStart = CACurrentMediaTime()
        defer {
            Self.lastDrawEnd = CACurrentMediaTime()
            Self.totalDrawTime += Self.lastDrawEnd - drawStart
        }
        guard let item, let context = NSGraphicsContext.current?.cgContext else { return }
        // Tile: a one-device-pixel separator border inside the bounds; selected: a 2 pt accent
        // ring and tint; hovered: a faint fill so the pointer's card reads before the buttons.
        let pixel = 1 / max(window?.backingScaleFactor ?? 2, 1)
        if isSelected {
            // In a background window the selection goes grey, like Finder's.
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: Radius.m - 1, yRadius: Radius.m - 1)
            (windowIsActive ? NSColor.controlAccentColor.withAlphaComponent(0.12) : .unemphasizedSelectedContentBackgroundColor).setFill()
            ring.fill()
            (windowIsActive ? NSColor.controlAccentColor : .systemGray).setStroke()
            ring.lineWidth = 2
            ring.stroke()
        } else {
            let tile = NSBezierPath(roundedRect: bounds, xRadius: Radius.m, yRadius: Radius.m)
            NSColor.controlBackgroundColor.setFill()
            tile.fill()
            if isHovered {
                NSColor.quaternarySystemFill.setFill()
                tile.fill()
            }
            let edge = NSBezierPath(roundedRect: bounds.insetBy(dx: pixel / 2, dy: pixel / 2),
                                    xRadius: Radius.m - pixel / 2, yRadius: Radius.m - pixel / 2)
            NSColor.separatorColor.setStroke()
            edge.lineWidth = pixel
            edge.stroke()
        }

        // Top line: status mark, family name (small, secondary) and the style count on the
        // right, all on one baseline with their caps centred on the header's centre line.
        let nameAttributes: [NSAttributedString.Key: Any] = [.font: Self.nameFont, .foregroundColor: NSColor.secondaryLabelColor]
        let smallAttributes: [NSAttributedString.Key: Any] = [.font: Self.smallFont, .foregroundColor: NSColor.secondaryLabelColor]
        let headerBaseline = Self.edgeCentre + (Self.nameFont.capHeight / 2).rounded()
        var x = Self.inset
        if let stateImage = Self.symbolImage(stateDescription.symbol, active: windowIsActive) {
            let imageSize = stateImage.size
            stateImage.draw(in: NSRect(x: x, y: Self.edgeCentre - imageSize.height / 2, width: imageSize.width, height: imageSize.height))
            x += imageSize.width + 5
        }
        if !countText.isEmpty {
            (countText as NSString).draw(at: NSPoint(x: bounds.maxX - Self.inset - countWidth, y: headerBaseline - Self.smallFont.ascender),
                                         withAttributes: smallAttributes)
        }
        let rightEdge = starSlot.minX - Spacing.xs
        var title = item.title
        if let detail = nameDetail { title += " — \(detail)" }
        (title as NSString).draw(with: NSRect(x: x, y: headerBaseline - Self.nameFont.ascender, width: max(rightEdge - x, 0), height: 18),
                                 options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: nameAttributes)

        // Preview, centred, clipped to the card so tall glyphs can't spill into neighbours.
        // The baseline is the same for every font at this size, so a row of cards lines up.
        let line = renderedLine()
        caption = line.caption
        let previewRect = NSRect(x: Self.inset, y: Self.headerHeight, width: bounds.width - Self.inset * 2,
                                 height: bounds.height - Self.headerHeight - Self.footerHeight + 4)
        context.saveGState()
        context.clip(to: previewRect)
        if line.unavailable {
            let message = "Can't preview this font" as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.preferredFont(forTextStyle: .body), .foregroundColor: NSColor.secondaryLabelColor]
            let width = message.size(withAttributes: attributes).width
            message.draw(at: NSPoint(x: previewRect.midX - width / 2, y: previewRect.minY + PreviewMetrics.topPadding), withAttributes: attributes)
        } else {
            let baseline = previewRect.minY + PreviewMetrics.baseline(for: size)
            let left = line.width < previewRect.width ? previewRect.minX + (previewRect.width - line.width) / 2 : previewRect.minX
            line.draw(in: context, x: left, baseline: baseline, color: .labelColor)
        }
        context.restoreGState()

        // Bottom-left: what the preview can't show ("2 characters missing", "Sample"), on the
        // footer's centre line like the collect button opposite.
        if let caption = line.caption, line.unavailable == false {
            let baseline = bounds.maxY - Self.edgeCentre + (Self.smallFont.capHeight / 2).rounded()
            (caption as NSString).draw(at: NSPoint(x: Self.inset, y: baseline - Self.smallFont.ascender), withAttributes: smallAttributes)
        }
    }

    /// Configured symbol images, made once: creating and rasterizing a symbol on every draw
    /// was the biggest cost of a card. The images are template-free bitmaps per appearance.
    private static var symbolCache: [String: NSImage] = [:]

    private static func symbolImage(_ name: String, active: Bool) -> NSImage? {
        let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let key = "\(name)|\(dark)|\(active)"
        if let image = symbolCache[key] { return image }
        let color: NSColor = name == "circle.fill" || name == "circle.lefthalf.filled" ? accent(active) : .secondaryLabelColor
        let pointSize: CGFloat = name == "lock.fill" ? 8 : 7
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .semibold).applying(.init(hierarchicalColor: color))) else { return nil }
        // Rasterize once at 2x so later draws are a plain bitmap blit.
        let size = symbol.size
        let image = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect)
            return true
        }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        if let rep {
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(origin: .zero, size: size))
            NSGraphicsContext.restoreGraphicsState()
            let bitmap = NSImage(size: size)
            bitmap.addRepresentation(rep)
            symbolCache[key] = bitmap
            return bitmap
        }
        symbolCache[key] = symbol
        return symbol
    }

    /// The accent colour can change while running; forget the cached marks.
    static func clearSymbolCache() { symbolCache = [:] }

    /// Accent in the active window, grey in a background one (Golden Gate greys selections
    /// and accent marks in windows you aren't using).
    static func accent(_ active: Bool) -> NSColor { active ? .controlAccentColor : .secondaryLabelColor }

    /// Whether this card's window is the one in use (key, or main under its own sheet).
    var windowIsActive: Bool {
        guard let window else { return true }
        return window.isKeyWindow || window.isMainWindow
    }

    /// Window activation and appearance changes repaint the card with re-resolved colours.
    func refreshForWindowState() {
        starButton.contentTintColor = isFavorite ? Self.accent(windowIsActive) : .secondaryLabelColor
        trayButton.contentTintColor = inTray ? Self.accent(windowIsActive) : .secondaryLabelColor
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func renderedLine() -> TypesetLine {
        guard let item else { return TypesetLine(line: nil, ascent: 0, descent: 0, missing: 0, isSample: false, unavailable: true) }
        let lineText = PreviewText.line(for: text, familyName: item.family.displayName)
        return PreviewRenderer.shared.line(for: item.representative, text: lineText, size: size, width: bounds.width - Self.inset * 2)
    }

    // MARK: Accessibility

    private func updateAccessibility() {
        guard let item else { return }
        let state = stateDescription.text
        var parts = [item.title]
        if grouped { parts.append(item.family.faces.count == 1 ? "1 style" : "\(item.family.faces.count) styles") }
        else { parts.append(item.representative.styleName) }
        if let detail = nameDetail { parts.append(detail) }
        parts.append(item.family.category.title)
        parts.append(state)
        if isFavorite { parts.append("Favorite") }
        if inTray { parts.append("In Compare") }
        setAccessibilityLabel(parts.joined(separator: ", "))
        setAccessibilitySelected(isSelected)
        setAccessibilityHelp(lock?.explanation ?? "Press Space to see every style, Return to add to Compare")
        toolTip = lock?.explanation
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}
