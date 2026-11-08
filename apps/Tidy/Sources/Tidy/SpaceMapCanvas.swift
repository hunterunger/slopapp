import SlopKit
import SwiftUI
import TidyCore

/// One folder's layout at one size: tiles and the items they stand for. A value, so views
/// that draw or describe it never see tiles from one layout with items from another.
struct MapLayoutResult {
    var tiles: [MapTile] = []
    /// Level-1 items and each one's nested items, as laid out.
    var items: [MapItem] = []
    var nested: [[MapItem]] = []
    /// The biggest level-1 size, for tinting.
    var largest: Int64 = 1

    func item(for tile: MapTile) -> MapItem? {
        if tile.level == 1 { return items.indices.contains(tile.index) ? items[tile.index] : nil }
        guard tiles.indices.contains(tile.parent) else { return nil }
        let parent = tiles[tile.parent]
        guard nested.indices.contains(parent.index), nested[parent.index].indices.contains(tile.index) else { return nil }
        return nested[parent.index][tile.index]
    }

    func tileIndex(for id: String) -> Int? {
        tiles.firstIndex { item(for: $0)?.id == id }
    }
}

/// Keeps the last layout, so hovering and redrawing never lay out again. Rebuilt when the
/// folder's contents change (up to 4 times a second while scanning) or the size does.
@MainActor
final class MapLayoutCache {
    struct Key: Equatable {
        var version: UInt64
        var place: MapPlace
        var count: Int
        var size: CGSize
        var first: Int64
    }

    private var key: Key?
    private(set) var result = MapLayoutResult()

    static let maxTiles = 2_000

    func layout(space: SpaceState, size: CGSize) -> MapLayoutResult {
        let source = space.items
        let key = Key(version: space.snapshot?.version ?? 0, place: space.place, count: source.count, size: size,
                      first: source.first?.size ?? 0)
        guard key != self.key else { return result }
        self.key = key
        let items = Array(source.prefix(Self.maxTiles))
        let remainder = source.dropFirst(Self.maxTiles).reduce(0) { $0 + Double($1.size) }
        let nested = items.map { item in item.isFolderLike ? space.nested(item) : [] }
        let layoutItems = zip(items, nested).map { item, children in
            MapLayoutItem(size: Double(item.size), children: children.isEmpty ? nil : children.map { Double($0.size) })
        }
        result = MapLayoutResult(tiles: MapLayout.tiles(layoutItems, remainder: remainder, in: CGRect(origin: .zero, size: size)),
                                 items: items, nested: nested, largest: max(1, items.first?.size ?? 1))
        return result
    }
}

/// The nested treemap: blocks sized by space on disk, folders as containers with a header
/// band. Click selects, double-click (or a click on a header band) opens, the pointer shows
/// details below. Arrow keys move between blocks, Space checks, Return opens.
struct TreemapView: View {
    @Bindable var model: AppModel
    @State private var cache = MapLayoutCache()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let space = model.space
        GeometryReader { proxy in
            let size = CGSize(width: max(0, proxy.size.width - 2 * Spacing.m), height: max(0, proxy.size.height - 2 * Spacing.m))
            let layout = cache.layout(space: space, size: size)
            ZStack(alignment: .topLeading) {
                if space.items.isEmpty {
                    emptyState
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    ZStack(alignment: .topLeading) {
                        MapTilesCanvas(model: model, cache: layout)
                        MapHoverCanvas(model: model, cache: layout)
                        MapInteraction(model: model, cache: layout)
                    }
                    .frame(width: size.width, height: size.height)
                    .offset(x: Spacing.m, y: Spacing.m)
                    .id(space.placeChanges)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.2), value: space.placeChanges)
        }
        .background(.background)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Space map")
    }

    @ViewBuilder private var emptyState: some View {
        let space = model.space
        if space.status == .scanning {
            ProgressView("Mapping…")
        } else if case .smaller = space.place, space.smallItems == nil {
            ProgressView()
        } else {
            ContentUnavailableView("This Folder Is Empty", systemImage: "folder",
                                   description: Text(space.total == 0 ? "Nothing in it takes up space." : "Nothing to show here."))
        }
    }
}

/// Tiles, labels, selection and check marks. Doesn't read the hover, so pointing around
/// never redraws it.
struct MapTilesCanvas: View {
    var model: AppModel
    let cache: MapLayoutResult
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let space = model.space
        let selection = space.selection
        let checked = Set(cache.items.filter { space.isChecked($0) || space.coveringCheck($0) != nil }.map(\.id))
        let accent = Color.windowAccent(activeState)
        let ring = Color.selectionRing(activeState)
        let separator = Color(nsColor: .separatorColor)
        let tiles = cache.tiles
        Canvas(rendersAsynchronously: false) { context, _ in
            let largest = Double(cache.largest)
            for tile in tiles {
                let item = cache.item(for: tile)
                let radius = tile.level == 1 ? Radius.s : Radius.nested(in: Radius.s, padding: MapLayoutStyle().inset)
                let path = Path(roundedRect: tile.rect, cornerRadius: radius, style: .continuous)
                let weight = item.map { min(1, Double($0.size) / largest) } ?? 0
                if let item, !tile.isSmaller, item.kind != .smaller, item.kind != .notMapped {
                    context.fill(path, with: .color(fill(for: item, level: tile.level, weight: weight, accent: accent)))
                } else {
                    hatch(context, path: path, rect: tile.rect, separator: separator)
                }
                if let header = tile.header, let item {
                    let band = Path(roundedRect: header, cornerRadii: RectangleCornerRadii(topLeading: radius, topTrailing: radius),
                                    style: .continuous)
                    context.fill(band, with: .color(accent.opacity(0.16)))
                    drawLabel(context, item: item, in: header.insetBy(dx: Spacing.s, dy: 0), header: true)
                } else if let item, tile.rect.width >= 64, tile.rect.height >= 34 {
                    drawLabel(context, item: item, in: tile.rect.insetBy(dx: Spacing.s, dy: Spacing.xs), header: false)
                } else if tile.isSmaller, tile.rect.width >= 64, tile.rect.height >= 34 {
                    let count = tile.level == 2 ? "Smaller items" : "Other items"
                    context.draw(Text(count).font(.caption).foregroundStyle(.secondary),
                                 in: tile.rect.insetBy(dx: Spacing.s, dy: Spacing.xs))
                }
                context.stroke(path, with: .color(separator), lineWidth: 0.5)
                if let item {
                    if selection.contains(item.id) {
                        context.stroke(Path(roundedRect: tile.rect.insetBy(dx: 1.25, dy: 1.25), cornerRadius: max(1, radius - 1.25),
                                            style: .continuous), with: .color(ring), lineWidth: 2.5)
                    }
                    if checked.contains(item.id), tile.rect.width >= 22, tile.rect.height >= 22 {
                        let center = CGPoint(x: tile.rect.maxX - 11, y: tile.rect.minY + 11)
                        context.fill(Path(ellipseIn: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)), with: .color(accent))
                        context.draw(Text(Image(systemName: "checkmark")).font(.caption2.weight(.bold)).foregroundColor(OnAccent.color),
                                     at: center)
                    }
                    if item.kind == .system, tile.rect.width >= 30, tile.rect.height >= 30, tile.rect.width < 64 || tile.rect.height < 34 {
                        context.draw(Text(Image(systemName: "lock.fill")).font(.caption).foregroundStyle(.secondary),
                                     at: CGPoint(x: tile.rect.midX, y: tile.rect.midY))
                    }
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .id(colorScheme)
    }

    private func fill(for item: MapItem, level: Int, weight: Double, accent: Color) -> Color {
        switch item.kind {
        case .folder, .package:
            return accent.opacity((level == 1 ? 0.2 : 0.16) + (level == 1 ? 0.4 : 0.28) * weight)
        case .system:
            return Color.secondary.opacity(0.3)
        default:
            return Color.secondary.opacity(0.12 + 0.22 * weight)
        }
    }

    /// Diagonal lines for groups ("smaller items", "Not mapped"): a group, not a thing.
    private func hatch(_ context: GraphicsContext, path: Path, rect: CGRect, separator: Color) {
        context.fill(path, with: .color(Color.secondary.opacity(0.08)))
        var lines = Path()
        let step: CGFloat = 6
        var x = rect.minX - rect.height
        while x < rect.maxX {
            lines.move(to: CGPoint(x: x, y: rect.maxY))
            lines.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += step
        }
        var clipped = context
        clipped.clip(to: path)
        clipped.stroke(lines, with: .color(separator), lineWidth: 0.5)
    }

    private func drawLabel(_ context: GraphicsContext, item: MapItem, in rect: CGRect, header: Bool) {
        let size = ByteFormat.string(item.size) + (item.isLowerBound ? "+" : "")
        if header {
            // The name wins; the size joins it only when both fit.
            let sizeWidth = LabelFitter.width(size, size: 10.5) + 8
            let both = LabelFitter.width(item.name, size: 10.5) + sizeWidth <= rect.width || rect.width - sizeWidth >= 60
            var text = Text(truncated(item.name, width: both ? rect.width - sizeWidth : rect.width, font: 10.5))
                .font(.caption.weight(.semibold))
            if both { text = text + Text("  " + size).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            context.draw(text, in: CGRect(x: rect.minX, y: rect.minY + 2, width: rect.width, height: rect.height - 2))
            return
        }
        let name = Text(truncated(item.name, width: rect.width, font: 12.5)).font(.callout.weight(.medium))
        context.draw(name, in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 18))
        if rect.height >= 34 {
            context.draw(Text(size).font(.caption.monospacedDigit()).foregroundStyle(.secondary),
                         in: CGRect(x: rect.minX, y: rect.minY + 17, width: rect.width, height: 16))
        }
    }

    /// Middle truncation, measured (Canvas text doesn't truncate in the middle on its own).
    private func truncated(_ name: String, width: CGFloat, font: CGFloat) -> String {
        LabelFitter.fit(name, width: width, size: font)
    }
}

/// Fits labels into tiles, measured with the system font and cached (the map redraws often,
/// names rarely change).
@MainActor
enum LabelFitter {
    private static var cache: [String: String] = [:]

    static func width(_ text: String, size: CGFloat) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium)]).width
    }

    static func fit(_ name: String, width: CGFloat, size: CGFloat) -> String {
        guard width > 12 else { return "" }
        let key = "\(Int(width))|\(Int(size))|\(name)"
        if let hit = cache[key] { return hit }
        let font = NSFont.systemFont(ofSize: size, weight: .medium)
        func measure(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width }
        var result = name
        if measure(name) > width {
            let characters = Array(name)
            var low = 0, high = characters.count
            result = "…"
            // The longest middle-truncated version that fits.
            while low < high {
                let keep = (low + high + 1) / 2
                let head = (keep + 1) / 2, tail = keep / 2
                let candidate = String(characters[..<head]) + "…" + String(characters[(characters.count - tail)...])
                if measure(candidate) <= width { low = keep; result = candidate } else { high = keep - 1 }
            }
        }
        if cache.count > 4_000 { cache.removeAll() }
        cache[key] = result
        return result
    }
}

/// The hover highlight: the block under the pointer and the folder it's in.
struct MapHoverCanvas: View {
    var model: AppModel
    let cache: MapLayoutResult
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        let hovered = model.space.hovered
        let accent = Color.windowAccent(activeState)
        Canvas { context, _ in
            guard let hovered, let index = cache.tileIndex(for: hovered) else { return }
            let tile = cache.tiles[index]
            if tile.level == 2 {
                let parent = cache.tiles[tile.parent]
                context.stroke(Path(roundedRect: parent.rect.insetBy(dx: 0.75, dy: 0.75), cornerRadius: Radius.s - 0.75, style: .continuous),
                               with: .color(accent.opacity(0.7)), lineWidth: 1.5)
            }
            let radius = tile.level == 1 ? Radius.s : Radius.nested(in: Radius.s, padding: MapLayoutStyle().inset)
            context.fill(Path(roundedRect: tile.rect, cornerRadius: radius, style: .continuous), with: .color(accent.opacity(0.12)))
            context.stroke(Path(roundedRect: tile.rect.insetBy(dx: 1, dy: 1), cornerRadius: max(1, radius - 1), style: .continuous),
                           with: .color(accent), lineWidth: 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Pointer, clicks, keys, the context menu and the accessibility elements.
struct MapInteraction: View {
    @Bindable var model: AppModel
    let cache: MapLayoutResult
    @FocusState private var focused: Bool

    var body: some View {
        let space = model.space
        Color.clear
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point):
                    let id = MapLayout.hit(cache.tiles, at: point).flatMap { cache.item(for: cache.tiles[$0.tile])?.id }
                    if space.hovered != id { space.hovered = id }
                case .ended:
                    space.hovered = nil
                }
            }
            .gesture(SpatialTapGesture(count: 2).onEnded { value in
                guard let item = item(at: value.location) else { return }
                MapActions.primary(model, item)
            })
            .simultaneousGesture(SpatialTapGesture(count: 1).onEnded { value in
                focused = true
                guard let hit = MapLayout.hit(cache.tiles, at: value.location) else { space.selection = []; return }
                let tile = cache.tiles[hit.tile]
                guard let item = cache.item(for: tile) else { return }
                if hit.onHeader, item.canOpen {
                    space.open(item)
                } else {
                    space.selection = [item.id]
                }
            })
            .contextMenu { HoverContextMenu(model: model) }
            .focusable()
            .focused($focused)
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                move(press.key)
                return .handled
            }
            .onKeyPress(.return) {
                guard let id = space.selection.first, let item = space.item(id) else { return .ignored }
                MapActions.primary(model, item)
                return .handled
            }
            .onKeyPress(.space) {
                guard !space.selection.isEmpty else { return .ignored }
                space.toggle(space.selection)
                return .handled
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Space map blocks")
            .accessibilityChildren { accessibleBlocks }
    }

    /// One VoiceOver element per top-level block, placed over it. (Split out of `body` so the
    /// compiler type-checks it in reasonable time.)
    private var accessibleBlocks: some View {
        let blocks = cache.tiles.indices.filter { cache.tiles[$0].level == 1 }
        return ZStack(alignment: .topLeading) {
            ForEach(blocks, id: \.self) { index in accessibleBlock(cache.tiles[index]) }
        }
    }

    @ViewBuilder private func accessibleBlock(_ tile: MapTile) -> some View {
        let space = model.space
        if let item = cache.item(for: tile) {
            Rectangle()
                .frame(width: tile.rect.width, height: tile.rect.height)
                .offset(x: tile.rect.minX, y: tile.rect.minY)
                .accessibilityLabel(label(item))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { space.selection = [item.id] }
                .accessibilityAction(named: "Open") { MapActions.primary(model, item) }
                .accessibilityAction(named: space.isChecked(item) ? "Uncheck" : "Check") {
                    space.setChecked(item, !space.isChecked(item))
                }
                .accessibilityAction(named: "Show in Finder") { if let url = space.url(of: item) { Finder.reveal([url]) } }
                .accessibilityAction(named: "Quick Look") { model.previewURL = space.url(of: item) }
        }
    }

    private func item(at point: CGPoint) -> MapItem? {
        MapLayout.hit(cache.tiles, at: point).flatMap { cache.item(for: cache.tiles[$0.tile]) }
    }

    private func label(_ item: MapItem) -> String {
        let total = max(1, model.space.total)
        let percent = Int((Double(item.size) / Double(total) * 100).rounded())
        var text = "\(item.name), \(kindName(item)), \(ByteFormat.string(item.size)), \(percent) percent"
        if item.isCounting { text += ", counting" }
        if model.space.isChecked(item) { text += ", checked" }
        return text
    }

    private func move(_ key: KeyEquivalent) {
        let space = model.space
        let direction: MapLayout.Direction = switch key {
        case .leftArrow: .left
        case .rightArrow: .right
        case .upArrow: .up
        default: .down
        }
        let current = space.selection.first.flatMap(cache.tileIndex(for:))
        guard let current else {
            if let first = cache.tiles.first(where: { $0.level == 1 }), let item = cache.item(for: first) { space.selection = [item.id] }
            return
        }
        if let next = MapLayout.neighbor(of: current, direction, in: cache.tiles), let item = cache.item(for: cache.tiles[next]) {
            space.selection = [item.id]
        }
    }
}

/// The map's context menu acts on the block under the pointer (selecting it first).
struct HoverContextMenu: View {
    var model: AppModel

    var body: some View {
        let space = model.space
        let ids = space.hovered.map { Set([$0]) } ?? space.selection
        MapContextMenu(model: model, ids: ids)
            .onAppear { if let hovered = space.hovered { space.selection = [hovered] } }
    }
}
