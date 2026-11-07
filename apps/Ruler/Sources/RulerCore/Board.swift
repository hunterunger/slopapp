/// A measured box on screen: snapped to an element, drawn freely, or clicked.
public struct MeasuredArea: Identifiable, Hashable, Sendable, Codable {
    public let id: Int
    public var rect: PixelRect
    /// False while the snapped bounds are still being worked out (shown as drawn).
    public var isSettled: Bool

    public init(id: Int, rect: PixelRect, isSettled: Bool = true) {
        self.id = id
        self.rect = rect
        self.isSettled = isSettled
    }
}

/// A distance held on screen: one line along one axis, like a hover span frozen in place.
///
/// A horizontal one runs along row `at` from x `start` to `end` (its length is a width); a
/// vertical one runs along column `at` from y `start` to `end` (a height).
public struct PinnedDistance: Identifiable, Hashable, Sendable, Codable {
    public let id: Int
    public var axis: GuideAxis
    public var at: Int
    public var start: Int
    public var end: Int

    public init(id: Int, axis: GuideAxis, at: Int, start: Int, end: Int) {
        self.id = id
        self.axis = axis
        self.at = at
        self.start = start
        self.end = end
    }

    public var length: Int { end - start }

    /// The pixels the line covers (one pixel thick).
    public var rect: PixelRect {
        axis == .horizontal
            ? PixelRect(minX: start, minY: at, maxX: end, maxY: at + 1)
            : PixelRect(minX: at, minY: start, maxX: at + 1, maxY: end)
    }
}

/// A full-length guide line at a pixel boundary.
public struct Guide: Identifiable, Hashable, Sendable, Codable {
    public let id: Int
    public var axis: GuideAxis
    public var position: Int

    public init(id: Int, axis: GuideAxis, position: Int) {
        self.id = id
        self.axis = axis
        self.position = position
    }
}

public enum BoardItem: Hashable, Sendable, Codable {
    case area(Int)
    case pin(Int)
    case guide(Int)
}

/// What a measurement reads: a box (width and height) or a single distance.
public enum Reading: Equatable, Sendable {
    case size(width: Int, height: Int)
    /// A horizontal length is a width, a vertical one a height.
    case length(Int, axis: GuideAxis)
}

/// The gap between two neighbouring guides, or between a guide and the display edge.
public struct GuideGap: Equatable, Sendable {
    public var start: Int
    public var end: Int
    public var touchesEdge: Bool

    public init(start: Int, end: Int, touchesEdge: Bool) {
        self.start = start
        self.end = end
        self.touchesEdge = touchesEdge
    }

    public var length: Int { end - start }
}

/// Everything measured on one display during one overlay session. A value type, so undo
/// is just keeping the previous value, and saving the session is encoding it.
public struct Board: Equatable, Sendable, Codable {
    public private(set) var areas: [MeasuredArea] = []
    public private(set) var pins: [PinnedDistance] = []
    public private(set) var guides: [Guide] = []
    /// The most recently added area or pin (what Return copies when nothing is hovered).
    public private(set) var lastMeasured: BoardItem?
    private var nextID = 1

    public init() {}

    public var isEmpty: Bool { areas.isEmpty && pins.isEmpty && guides.isEmpty }
    public var count: Int { areas.count + pins.count + guides.count }

    // MARK: Adding

    @discardableResult
    public mutating func addArea(_ rect: PixelRect, settled: Bool = true) -> Int {
        let id = takeID()
        areas.append(MeasuredArea(id: id, rect: rect, isSettled: settled))
        lastMeasured = .area(id)
        return id
    }

    /// Replaces a pending area's rect with its snapped bounds. Returns false if it's gone.
    @discardableResult
    public mutating func settleArea(_ id: Int, rect: PixelRect) -> Bool {
        guard let index = areas.firstIndex(where: { $0.id == id }) else { return false }
        areas[index].rect = rect
        areas[index].isSettled = true
        return true
    }

    /// Sets an area's rect (resizing). Returns false if it's gone or the rect is empty.
    @discardableResult
    public mutating func resizeArea(_ id: Int, to rect: PixelRect) -> Bool {
        guard !rect.isEmpty, let index = areas.firstIndex(where: { $0.id == id }) else { return false }
        areas[index].rect = rect
        areas[index].isSettled = true
        return true
    }

    /// Holds the hover distance at `point` on screen: one line per axis asked for. Returns
    /// the new pins' ids.
    @discardableResult
    public mutating func addPins(point: PixelPoint, spans: PixelRect, axes: [GuideAxis] = [.horizontal, .vertical]) -> [Int] {
        var ids: [Int] = []
        for axis in axes {
            let pin = axis == .horizontal
                ? PinnedDistance(id: takeID(), axis: .horizontal, at: point.y, start: spans.minX, end: spans.maxX)
                : PinnedDistance(id: takeID(), axis: .vertical, at: point.x, start: spans.minY, end: spans.maxY)
            guard pin.length > 0 else { continue }
            pins.append(pin)
            ids.append(pin.id)
            lastMeasured = .pin(pin.id)
        }
        return ids
    }

    /// Adds a guide unless one is already at that spot. Returns its id.
    @discardableResult
    public mutating func addGuide(_ axis: GuideAxis, at position: Int) -> Int {
        if let existing = guides.first(where: { $0.axis == axis && $0.position == position }) { return existing.id }
        let id = takeID()
        guides.append(Guide(id: id, axis: axis, position: position))
        return id
    }

    @discardableResult
    public mutating func moveGuide(_ id: Int, to position: Int) -> Bool {
        guard let index = guides.firstIndex(where: { $0.id == id }) else { return false }
        guides[index].position = position
        return true
    }

    private mutating func takeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    // MARK: Removing

    public mutating func remove(_ item: BoardItem) {
        switch item {
        case .area(let id): areas.removeAll { $0.id == id }
        case .pin(let id): pins.removeAll { $0.id == id }
        case .guide(let id): guides.removeAll { $0.id == id }
        }
        if lastMeasured == item { lastMeasured = areas.last.map { .area($0.id) } ?? pins.last.map { .pin($0.id) } }
    }

    public mutating func clear() {
        areas = []
        pins = []
        guides = []
        lastMeasured = nil
    }

    // MARK: Reading

    public func area(_ id: Int) -> MeasuredArea? { areas.first { $0.id == id } }
    public func pin(_ id: Int) -> PinnedDistance? { pins.first { $0.id == id } }
    public func guide(_ id: Int) -> Guide? { guides.first { $0.id == id } }

    /// What an area or pin reads (guides have no size).
    public func reading(of item: BoardItem) -> Reading? {
        switch item {
        case .area(let id): area(id).map { .size(width: $0.rect.width, height: $0.rect.height) }
        case .pin(let id): pin(id).map { .length($0.length, axis: $0.axis) }
        case .guide: nil
        }
    }

    /// The item under a pointer: guides and pin lines within `slop` pixels first, then the
    /// smallest area containing the point.
    public func item(at point: PixelPoint, slop: Int) -> BoardItem? {
        for pin in pins.reversed() {
            let along = pin.axis == .horizontal ? point.x : point.y
            let across = pin.axis == .horizontal ? point.y : point.x
            if abs(across - pin.at) <= slop && along >= pin.start - slop && along <= pin.end + slop { return .pin(pin.id) }
        }
        if let guide = guides
            .map({ ($0, abs(($0.axis == .vertical ? point.x : point.y) - $0.position)) })
            .filter({ $0.1 <= slop })
            .min(by: { $0.1 < $1.1 })?.0 {
            return .guide(guide.id)
        }
        return areas
            .filter { $0.rect.contains(point) }
            .min { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }
            .map { .area($0.id) }
    }

    /// The resize handle of a placed area under the pointer: corners first, then edges, of
    /// the topmost (latest) area whose border is within `slop` pixels.
    public func handle(at point: PixelPoint, slop: Int) -> (id: Int, handle: AreaHandle)? {
        for area in areas.reversed() {
            if let handle = AreaHandle.hit(point, rect: area.rect, slop: slop) { return (area.id, handle) }
        }
        return nil
    }

    /// How far a hover measurement from `point` may run before hitting a placed area's edge
    /// or a guide. Inside an area, its own edges are the limit, so hovering in it reads its
    /// size; outside, the gap to the nearest area or guide is measured.
    public func limits(for point: PixelPoint, in bounds: PixelRect) -> PixelRect {
        var result = bounds
        for area in areas {
            let r = area.rect
            if point.y >= r.minY && point.y < r.maxY {
                if r.maxX <= point.x { result.minX = max(result.minX, r.maxX) }
                else if r.minX > point.x { result.maxX = min(result.maxX, r.minX) }
                else { result.minX = max(result.minX, r.minX); result.maxX = min(result.maxX, r.maxX) }
            }
            if point.x >= r.minX && point.x < r.maxX {
                if r.maxY <= point.y { result.minY = max(result.minY, r.maxY) }
                else if r.minY > point.y { result.maxY = min(result.maxY, r.minY) }
                else { result.minY = max(result.minY, r.minY); result.maxY = min(result.maxY, r.maxY) }
            }
        }
        for guide in guides {
            switch guide.axis {
            case .vertical:
                if guide.position <= point.x { result.minX = max(result.minX, guide.position) }
                else { result.maxX = min(result.maxX, guide.position) }
            case .horizontal:
                if guide.position <= point.y { result.minY = max(result.minY, guide.position) }
                else { result.maxY = min(result.maxY, guide.position) }
            }
        }
        return result
    }

    /// The gaps along one axis between neighbouring guides, and from the outermost guides to
    /// the display edges (0 and `limit`). No guides: no gaps.
    public func guideGaps(_ axis: GuideAxis, limit: Int) -> [GuideGap] {
        let positions = Array(Set(guides.filter { $0.axis == axis }.map(\.position))).sorted()
        guard !positions.isEmpty else { return [] }
        let stops = [0] + positions + [limit]
        return zip(stops, stops.dropFirst()).enumerated().compactMap { index, pair in
            guard pair.1 > pair.0 else { return nil }
            return GuideGap(start: pair.0, end: pair.1, touchesEdge: index == 0 || index == stops.count - 2)
        }
    }

    /// Positions a guide on `axis` snaps to besides image edges: placed areas' sides and the
    /// midpoints between neighbouring guides. `excluding` leaves out a guide being moved.
    public func guideSnapPositions(_ axis: GuideAxis, excluding: Int? = nil) -> [Int] {
        var result: [Int] = []
        for area in areas {
            if axis == .vertical { result += [area.rect.minX, area.rect.maxX] } else { result += [area.rect.minY, area.rect.maxY] }
        }
        let positions = guides.filter { $0.axis == axis && $0.id != excluding }.map(\.position).sorted()
        for (a, b) in zip(positions, positions.dropFirst()) where b - a >= 2 {
            result.append((a + b) / 2)
        }
        return result
    }

    /// The snap position nearest to `position` within `maxDistance`, or nil.
    public func nearestGuideSnap(_ axis: GuideAxis, to position: Int, maxDistance: Int, excluding: Int? = nil) -> Int? {
        guideSnapPositions(axis, excluding: excluding)
            .map { ($0, abs($0 - position)) }
            .filter { $0.1 <= maxDistance }
            .min { $0.1 < $1.1 }?.0
    }

    /// The pixels covered by areas and pins (not guides, which span the display), or nil.
    public var measuredBounds: PixelRect? {
        let rects = areas.map(\.rect) + pins.map(\.rect)
        return rects.dropFirst().reduce(rects.first) { $0?.union($1) }
    }
}

/// A grab point on a placed area's border.
public enum AreaHandle: String, CaseIterable, Sendable {
    case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight

    public var movesLeft: Bool { self == .left || self == .topLeft || self == .bottomLeft }
    public var movesRight: Bool { self == .right || self == .topRight || self == .bottomRight }
    public var movesTop: Bool { self == .top || self == .topLeft || self == .topRight }
    public var movesBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }
    public var isCorner: Bool { (movesLeft || movesRight) && (movesTop || movesBottom) }

    /// The handle of `rect` within `slop` of `point`, corners first. Rects too small to grab
    /// without covering their inside only offer corners outside them.
    public static func hit(_ point: PixelPoint, rect r: PixelRect, slop: Int) -> AreaHandle? {
        let nearLeft = abs(point.x - r.minX) <= slop, nearRight = abs(point.x - r.maxX) <= slop
        let nearTop = abs(point.y - r.minY) <= slop, nearBottom = abs(point.y - r.maxY) <= slop
        let withinX = point.x >= r.minX - slop && point.x <= r.maxX + slop
        let withinY = point.y >= r.minY - slop && point.y <= r.maxY + slop
        guard withinX && withinY else { return nil }
        // For thin rects both sides are "near": prefer the side the pointer is on.
        let left = nearLeft && (!nearRight || point.x < (r.minX + r.maxX) / 2)
        let right = nearRight && !left
        let top = nearTop && (!nearBottom || point.y < (r.minY + r.maxY) / 2)
        let bottom = nearBottom && !top
        switch (left, right, top, bottom) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        case (true, _, _, _): return .left
        case (_, true, _, _): return .right
        case (_, _, true, _): return .top
        case (_, _, _, true): return .bottom
        default: return nil
        }
    }

    /// `rect` with this handle dragged to the boundary `to`, never smaller than `minimum`
    /// pixels (the opposite side stays put). `keepAspect` keeps the original's proportions:
    /// corners follow the larger change, edges grow the other side around its center.
    public func resize(_ r: PixelRect, to p: PixelPoint, keepAspect: Bool = false, minimum: Int = 1) -> PixelRect {
        var out = r
        if movesLeft { out.minX = min(p.x, r.maxX - minimum) }
        if movesRight { out.maxX = max(p.x, r.minX + minimum) }
        if movesTop { out.minY = min(p.y, r.maxY - minimum) }
        if movesBottom { out.maxY = max(p.y, r.minY + minimum) }
        guard keepAspect, r.width > 0, r.height > 0 else { return out }
        let ratio = Double(r.width) / Double(r.height)
        if isCorner {
            let widthDriven = abs(Double(out.width - r.width)) >= abs(Double(out.height - r.height)) * ratio
            if widthDriven {
                let h = max(minimum, Int((Double(out.width) / ratio).rounded()))
                if movesTop { out.minY = out.maxY - h } else { out.maxY = out.minY + h }
            } else {
                let w = max(minimum, Int((Double(out.height) * ratio).rounded()))
                if movesLeft { out.minX = out.maxX - w } else { out.maxX = out.minX + w }
            }
        } else if movesLeft || movesRight {
            let h = max(minimum, Int((Double(out.width) / ratio).rounded()))
            let center = r.minY + r.height / 2
            out.minY = center - h / 2
            out.maxY = out.minY + h
        } else {
            let w = max(minimum, Int((Double(out.height) * ratio).rounded()))
            let center = r.minX + r.width / 2
            out.minX = center - w / 2
            out.maxX = out.minX + w
        }
        return out
    }
}
