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
            selection: model.selection, favorites: model.favorites, focusRequest: model.focusGridRequest
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
        collectionView.setAccessibilityLabel("Fonts")
        let scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = true
        return scrollView
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
        if old?.previewText != new.previewText || old?.previewSize != new.previewSize || old?.favorites != new.favorites {
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
            lock: model.lockReason(for: item.family), grouped: model.groupByFamily
        )
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
    private let spacing: CGFloat = 12
    private let inset: CGFloat = 16
    private var count = 0

    static func cardHeight(previewSize: CGFloat) -> CGFloat {
        FontCardView.headerHeight + FontCardView.previewHeight(for: previewSize) + 10
    }

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        count = collectionView.numberOfSections > 0 ? collectionView.numberOfItems(inSection: 0) : 0
        let width = max(collectionView.enclosingScrollView?.contentView.bounds.width ?? collectionView.bounds.width, 200) - inset * 2
        let minimum = min(max(previewSize * 9, 260), 1400)
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

/// Keyboard: arrows (⇧ extends), Return/Space open, Esc clears, letters jump, ⌘A, ⌘C.
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
        case 36, 76, 49: controller.open(index: position)   // Return, Enter, Space
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
}

/// One card: header (name, styles, category, state, ★) over a preview line drawn with CoreText.
final class FontCardView: NSView {
    static let headerHeight: CGFloat = 30
    static func previewHeight(for size: CGFloat) -> CGFloat { ceil(size * 1.45) + 8 }

    var isSelected = false { didSet { if isSelected != oldValue { needsDisplay = true; updateAccessibility() } } }
    var onToggleFavorite: (() -> Void)?
    var onPress: (() -> Void)?

    private var item: GridEntry?
    private var text = ""
    private var size: CGFloat = 36
    private var isFavorite = false
    private var lock: LockReason?
    private var grouped = true
    private let starButton = NSButton()
    private var caption: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        starButton.isBordered = false
        starButton.bezelStyle = .regularSquare
        starButton.imagePosition = .imageOnly
        starButton.target = self
        starButton.action = #selector(toggleFavorite)
        starButton.contentTintColor = .secondaryLabelColor
        addSubview(starButton)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { false }

    func configure(item: GridEntry, text: String, size: CGFloat, isFavorite: Bool, lock: LockReason?, grouped: Bool) {
        self.item = item
        self.text = text
        self.size = size
        self.isFavorite = isFavorite
        self.lock = lock
        self.grouped = grouped
        let symbol = isFavorite ? "star.fill" : "star"
        let label = isFavorite ? "Remove from Favorites" : "Add to Favorites"
        starButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        starButton.contentTintColor = isFavorite ? .controlAccentColor : .tertiaryLabelColor
        starButton.setAccessibilityLabel("\(label): \(item.family.displayName)")
        starButton.toolTip = label
        caption = nil
        needsDisplay = true
        updateAccessibility()
    }

    override func layout() {
        super.layout()
        starButton.frame = NSRect(x: bounds.maxX - 30, y: 5, width: 22, height: 20)
    }

    @objc private func toggleFavorite() { onToggleFavorite?() }

    // MARK: Drawing

    private var headerSubtitle: String {
        guard let item else { return "" }
        var parts: [String] = []
        if grouped {
            let total = item.family.faces.count
            parts.append(total == 1 ? "1 style" : "\(total) styles")
        } else {
            parts.append(item.representative.styleName)
            // Two files with the same PostScript name: say which folder this copy is in.
            let face = item.representative
            if item.family.faces.contains(where: { $0.postScriptName == face.postScriptName && $0.id != face.id }),
               let folder = face.path.map({ URL(fileURLWithPath: $0).deletingLastPathComponent().lastPathComponent }) {
                parts.append("in \(folder)")
            }
        }
        parts.append(item.family.category.title)
        return parts.joined(separator: " · ")
    }

    private var stateDescription: (symbol: String, text: String) {
        guard let item else { return ("", "") }
        let state = grouped ? item.family.state : ActivationState(faces: item.faces)
        if let lock, state == .active { return ("lock.fill", "Active, \(lock.title)") }
        switch state {
        case .active: return ("checkmark.circle.fill", "Active")
        case .inactive: return ("circle.slash", "Inactive")
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
        let card = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: card, xRadius: 10, yRadius: 10)
        if isSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
            path.fill()
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2
            path.stroke()
        } else {
            NSColor.quaternaryLabelColor.withAlphaComponent(0.08).setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        // Header: name, styles · category, state symbol, then (right) the star button.
        let nameFont = NSFont.preferredFont(forTextStyle: .headline)
        let smallFont = NSFont.preferredFont(forTextStyle: .caption1)
        let nameAttributes: [NSAttributedString.Key: Any] = [.font: nameFont, .foregroundColor: NSColor.labelColor]
        let smallAttributes: [NSAttributedString.Key: Any] = [.font: smallFont, .foregroundColor: NSColor.secondaryLabelColor]
        let state = stateDescription
        var x: CGFloat = 12
        if let stateImage = Self.symbolImage(state.symbol) {
            let imageSize = stateImage.size
            stateImage.draw(in: NSRect(x: x, y: 15 - imageSize.height / 2, width: imageSize.width, height: imageSize.height))
            x += imageSize.width + 6
        }
        let title = item.title as NSString
        let subtitle = headerSubtitle as NSString
        let line = renderedLine()
        caption = line.caption
        let captionText = (line.caption ?? "") as NSString
        let captionWidth = line.caption == nil ? 0 : captionText.size(withAttributes: smallAttributes).width + 12
        let available = bounds.width - x - 40 - captionWidth
        let titleWidth = min(title.size(withAttributes: nameAttributes).width, available)
        title.draw(with: NSRect(x: x, y: 7, width: max(titleWidth, 0), height: 18),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: nameAttributes)
        let subtitleX = x + titleWidth + 8
        if available - titleWidth - 8 > 30 {
            subtitle.draw(with: NSRect(x: subtitleX, y: 9, width: available - titleWidth - 8, height: 16),
                          options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: smallAttributes)
        }
        if line.caption != nil {
            captionText.draw(at: NSPoint(x: bounds.width - 36 - captionWidth + 6, y: 9), withAttributes: [.font: smallFont, .foregroundColor: NSColor.tertiaryLabelColor])
        }

        // Preview, clipped to the card so tall glyphs can't spill into neighbours.
        let previewRect = NSRect(x: 12, y: Self.headerHeight, width: bounds.width - 24, height: bounds.height - Self.headerHeight - 6)
        context.saveGState()
        context.clip(to: previewRect)
        if line.unavailable {
            ("Can't preview this font" as NSString).draw(at: NSPoint(x: previewRect.minX, y: previewRect.minY + 4),
                                                         withAttributes: [.font: NSFont.preferredFont(forTextStyle: .body), .foregroundColor: NSColor.tertiaryLabelColor])
        } else {
            let baseline = previewRect.minY + 4 + min(line.ascent, size * 1.05)
            line.draw(in: context, x: previewRect.minX, baseline: baseline, color: .labelColor)
        }
        context.restoreGState()
    }

    /// Configured symbol images, made once: creating and rasterizing a symbol on every draw
    /// was the biggest cost of a card. The images are template-free bitmaps per appearance.
    private static var symbolCache: [String: NSImage] = [:]

    private static func symbolImage(_ name: String) -> NSImage? {
        let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let key = "\(name)|\(dark)"
        if let image = symbolCache[key] { return image }
        let color: NSColor = name == "checkmark.circle.fill" ? .systemGreen : .secondaryLabelColor
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular).applying(.init(hierarchicalColor: color))) else { return nil }
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

    private func renderedLine() -> TypesetLine {
        guard let item else { return TypesetLine(line: nil, ascent: 0, descent: 0, missing: 0, isSample: false, unavailable: true) }
        let lineText = PreviewText.line(for: text, familyName: item.family.displayName)
        return PreviewRenderer.shared.line(for: item.representative, text: lineText, size: size, width: bounds.width - 24)
    }

    // MARK: Accessibility

    private func updateAccessibility() {
        guard let item else { return }
        let state = stateDescription.text
        var parts = [item.title, headerSubtitle, state]
        if isFavorite { parts.append("Favorite") }
        setAccessibilityLabel(parts.joined(separator: ", "))
        setAccessibilitySelected(isSelected)
        setAccessibilityHelp(lock?.explanation ?? "Press Return to see every style")
        toolTip = lock?.explanation
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}
