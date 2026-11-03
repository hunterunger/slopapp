/// A measured box on screen: snapped to an element, drawn freely, or clicked.
public struct MeasuredArea: Identifiable, Hashable, Sendable {
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

/// A hover distance kept on screen (P).
public struct PinnedDistance: Identifiable, Hashable, Sendable {
    public let id: Int
    public var point: PixelPoint
    public var spans: PixelRect

    public init(id: Int, point: PixelPoint, spans: PixelRect) {
        self.id = id
        self.point = point
        self.spans = spans
    }
}

/// A full-length guide line at a pixel boundary.
public struct Guide: Identifiable, Hashable, Sendable {
    public let id: Int
    public var axis: GuideAxis
    public var position: Int

    public init(id: Int, axis: GuideAxis, position: Int) {
        self.id = id
        self.axis = axis
        self.position = position
    }
}

public enum BoardItem: Hashable, Sendable {
    case area(Int)
    case pin(Int)
    case guide(Int)
}

/// Everything measured on one display during one overlay session. A value type, so undo
/// is just keeping the previous value.
public struct Board: Equatable, Sendable {
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

    @discardableResult
    public mutating func addPin(point: PixelPoint, spans: PixelRect) -> Int {
        let id = takeID()
        pins.append(PinnedDistance(id: id, point: point, spans: spans))
        lastMeasured = .pin(id)
        return id
    }

    /// Adds a guide unless one is already at that spot. Returns its id.
    @discardableResult
    public mutating func addGuide(_ axis: GuideAxis, at position: Int) -> Int {
        if let existing = guides.first(where: { $0.axis == axis && $0.position == position }) { return existing.id }
        let id = takeID()
        guides.append(Guide(id: id, axis: axis, position: position))
        return id
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

    /// Width and height in pixels of an area or pin (guides have no size).
    public func size(of item: BoardItem) -> (width: Int, height: Int)? {
        switch item {
        case .area(let id): area(id).map { ($0.rect.width, $0.rect.height) }
        case .pin(let id): pin(id).map { ($0.spans.width, $0.spans.height) }
        case .guide: nil
        }
    }

    /// The item under a pointer: guides and pin lines within `slop` pixels first, then the
    /// smallest area containing the point.
    public func item(at point: PixelPoint, slop: Int) -> BoardItem? {
        if let guide = guides
            .map({ ($0, abs(($0.axis == .vertical ? point.x : point.y) - $0.position)) })
            .filter({ $0.1 <= slop })
            .min(by: { $0.1 < $1.1 })?.0 {
            return .guide(guide.id)
        }
        for pin in pins.reversed() {
            let s = pin.spans
            let onRow = abs(point.y - pin.point.y) <= slop && point.x >= s.minX - slop && point.x <= s.maxX + slop
            let onColumn = abs(point.x - pin.point.x) <= slop && point.y >= s.minY - slop && point.y <= s.maxY + slop
            if onRow || onColumn { return .pin(pin.id) }
        }
        return areas
            .filter { $0.rect.contains(point) }
            .min { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }
            .map { .area($0.id) }
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

    /// The gaps between neighbouring guides of one axis, as (start, end) boundary pairs.
    public func guideGaps(_ axis: GuideAxis) -> [(start: Int, end: Int)] {
        let positions = guides.filter { $0.axis == axis }.map(\.position).sorted()
        return zip(positions, positions.dropFirst()).map { ($0, $1) }.filter { $0.end > $0.start }
    }
}
