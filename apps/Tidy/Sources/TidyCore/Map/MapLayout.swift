import CoreGraphics
import Foundation

/// One block of the map.
public struct MapTile: Sendable, Equatable {
    public var rect: CGRect
    /// 1: an item of the folder shown. 2: an item inside one of those folders.
    public var level: Int
    /// Index into the folder's items (level 1) or into that item's nested items (level 2);
    /// -1 for a "smaller items" block.
    public var index: Int
    /// Level 2: the index of its level-1 tile in the tile array. Level 1: -1.
    public var parent: Int
    /// A folder drawn as a container: the band at its top with its name and size.
    public var header: CGRect?

    public var isSmaller: Bool { index < 0 }
}

/// Spacing for the nested map. Defaults follow the design system (4 pt grid, `Spacing.xs`
/// inset inside folders).
public struct MapLayoutStyle: Sendable, Equatable {
    /// Gap between neighbouring blocks.
    public var gap: CGFloat = 2
    /// Even inset of a folder's children inside it (sides and bottom; the header is on top).
    public var inset: CGFloat = 4
    public var headerHeight: CGFloat = 18
    /// Blocks smaller than this on either side are merged into the "smaller items" block.
    public var minSide: CGFloat = 4
    /// A folder needs at least this much room to show what's inside it.
    public var minNestedSize = CGSize(width: 56, height: 44)

    public init() {}
}

/// The size of one item for the layout, with the sizes of what's inside it (for folders).
public struct MapLayoutItem: Sendable, Equatable {
    public var size: Double
    /// Biggest first. nil: not a container (a file, or a folder whose contents aren't known).
    public var children: [Double]?

    public init(size: Double, children: [Double]? = nil) {
        self.size = size
        self.children = children
    }
}

/// The map's two-level squarified treemap: the folder's items, and inside each folder big
/// enough, its own items under a header band. Blocks too small to see or point at are merged
/// into one "smaller items" block per level. Pure and cheap (well under a millisecond for a
/// few thousand blocks), so it's cached per folder and size.
public enum MapLayout {
    public static func tiles(_ items: [MapLayoutItem], remainder: Double = 0, in rect: CGRect,
                             style: MapLayoutStyle = MapLayoutStyle()) -> [MapTile] {
        var tiles: [MapTile] = []
        let level1 = level(items.map(\.size), remainder: remainder, in: rect, style: style)
        tiles.reserveCapacity(level1.count * 4)
        for (index, rect) in level1 {
            let tileIndex = tiles.count
            var tile = MapTile(rect: rect.insetBy(dx: style.gap / 2, dy: style.gap / 2), level: 1, index: index, parent: -1)
            guard index >= 0, let children = items[index].children, !children.isEmpty,
                  tile.rect.width >= style.minNestedSize.width, tile.rect.height >= style.minNestedSize.height else {
                if tile.rect.width >= 1, tile.rect.height >= 1 { tiles.append(tile) }
                continue
            }
            let header = CGRect(x: tile.rect.minX, y: tile.rect.minY, width: tile.rect.width, height: style.headerHeight)
            tile.header = header
            tiles.append(tile)
            let content = CGRect(x: tile.rect.minX + style.inset, y: header.maxY,
                                 width: tile.rect.width - 2 * style.inset,
                                 height: tile.rect.height - style.headerHeight - style.inset)
            let shown = children.reduce(0, +)
            let rest = max(0, items[index].size - shown)
            for (childIndex, childRect) in level(children, remainder: rest, in: content, style: style) {
                let r = childRect.insetBy(dx: style.gap / 2, dy: style.gap / 2)
                guard r.width >= 1, r.height >= 1 else { continue }
                tiles.append(MapTile(rect: r, level: 2, index: childIndex, parent: tileIndex))
            }
        }
        return tiles
    }

    /// One level: (index, rect) pairs, index -1 for the merged small block.
    static func level(_ sizes: [Double], remainder: Double, in rect: CGRect, style: MapLayoutStyle) -> [(Int, CGRect)] {
        guard rect.width > 0, rect.height > 0 else { return [] }
        let positive = sizes.map { max(0, $0) }
        let total = positive.reduce(0, +) + max(0, remainder)
        guard total > 0 else { return [] }
        let scale = Double(rect.width * rect.height) / total
        // A block needs a little more than minSide² so the gap doesn't eat it.
        let side = Double(style.minSide + style.gap)
        let minArea = side * side
        var kept: [Int] = []
        var merged = max(0, remainder)
        // Biggest first, so everything after the first too-small block is merged too.
        let order = positive.indices.sorted { positive[$0] > positive[$1] }
        var cut = false
        for i in order {
            if !cut, positive[i] * scale >= minArea {
                kept.append(i)
            } else {
                cut = true
                merged += positive[i]
            }
        }
        var values = kept.map { positive[$0] }
        let hasMerged = merged * scale >= minArea
        if hasMerged { values.append(merged) }
        let rects = Treemap.layout(values, in: rect)
        var result: [(Int, CGRect)] = []
        result.reserveCapacity(rects.count)
        for (n, r) in rects.enumerated() {
            result.append((n < kept.count ? kept[n] : -1, r))
        }
        return result
    }

    /// The tile under `point`: the deepest one, and whether the point is on a folder's
    /// header band.
    public static func hit(_ tiles: [MapTile], at point: CGPoint) -> (tile: Int, onHeader: Bool)? {
        var best: Int?
        for (i, tile) in tiles.enumerated() where tile.rect.contains(point) {
            if best == nil || tile.level > tiles[best!].level { best = i }
        }
        guard let best else { return nil }
        let onHeader = tiles[best].header?.contains(point) ?? false
        return (best, onHeader)
    }

    public enum Direction: Sendable { case left, right, up, down }

    /// The level-1 tile next to `index` in `direction` (arrow keys in the map).
    public static func neighbor(of index: Int, _ direction: Direction, in tiles: [MapTile]) -> Int? {
        guard tiles.indices.contains(index) else { return nil }
        let from = tiles[index].level == 2 ? tiles[index].parent : index
        let a = tiles[from].rect
        var best: (Int, CGFloat)?
        for (i, tile) in tiles.enumerated() where i != from && tile.level == 1 {
            let b = tile.rect
            let ahead: Bool
            let overlap: Bool
            switch direction {
            case .right: ahead = b.minX >= a.maxX - 0.5; overlap = b.minY < a.maxY && b.maxY > a.minY
            case .left: ahead = b.maxX <= a.minX + 0.5; overlap = b.minY < a.maxY && b.maxY > a.minY
            case .down: ahead = b.minY >= a.maxY - 0.5; overlap = b.minX < a.maxX && b.maxX > a.minX
            case .up: ahead = b.maxY <= a.minY + 0.5; overlap = b.minX < a.maxX && b.maxX > a.minX
            }
            guard ahead else { continue }
            let dx = b.midX - a.midX, dy = b.midY - a.midY
            // Blocks in the same row or column win over diagonal ones.
            let distance = (dx * dx + dy * dy).squareRoot() + (overlap ? 0 : 10_000)
            if best == nil || distance < best!.1 { best = (i, distance) }
        }
        return best?.0
    }
}
