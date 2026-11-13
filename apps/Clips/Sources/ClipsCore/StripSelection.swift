import Foundation

/// Which cards are selected in the strip, with the same rules as a Mac list (and Clips' History
/// window): a click selects one card; ⌘-click adds or removes one; ⇧-click selects the range
/// from the anchor; ⇧-arrows grow or shrink that range; ⌘A selects every card.
///
/// `cursor` is the card the keyboard is on (Space previews it, the strip scrolls to it).
/// `ids` is every selected card, the cursor included. `order` is the strip, left to right.
public struct StripSelection: Equatable, Sendable {
    public private(set) var cursor: UUID?
    /// Where ⇧-click and ⇧-arrow ranges start.
    public private(set) var anchor: UUID?
    public private(set) var ids: Set<UUID> = []

    public init(cursor: UUID? = nil) {
        select(cursor)
    }

    public var count: Int { ids.count }
    public var isMultiple: Bool { ids.count > 1 }

    public func contains(_ id: UUID) -> Bool { ids.contains(id) }

    /// Selects one card (or none).
    public mutating func select(_ id: UUID?) {
        cursor = id
        anchor = id
        ids = id.map { [$0] } ?? []
    }

    /// ⌘-click: adds a card, or removes it if it was selected (the last one stays).
    public mutating func toggle(_ id: UUID, in order: [UUID]) {
        if ids.contains(id) {
            guard ids.count > 1 else { return }
            ids.remove(id)
            if cursor == id {
                // The nearest selected card takes the cursor.
                let index = order.firstIndex(of: id) ?? 0
                let next = order[index...].first(where: ids.contains) ?? order[..<index].last(where: ids.contains)
                cursor = next ?? ids.first
            }
            if anchor == id { anchor = cursor }
        } else {
            ids.insert(id)
            cursor = id
            anchor = id
        }
    }

    /// ⇧-click: selects from the anchor to `id` (and keeps cards ⌘-clicked outside it).
    public mutating func extend(to id: UUID, in order: [UUID]) {
        guard let anchor, let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: id) else {
            select(id)
            return
        }
        // Like Finder: the previous ⇧ range is replaced, earlier ⌘-clicks stay.
        if let cursor, let old = order.firstIndex(of: cursor) {
            for index in min(from, old)...max(from, old) { ids.remove(order[index]) }
        }
        for index in min(from, to)...max(from, to) { ids.insert(order[index]) }
        cursor = id
    }

    /// ⇧-arrow: moves the cursor `delta` cards, extending (or shrinking) the range from the anchor.
    public mutating func extend(by delta: Int, in order: [UUID]) {
        guard !order.isEmpty else { return }
        guard let cursor, let index = order.firstIndex(of: cursor) else {
            select(order.first)
            return
        }
        let target = min(max(index + delta, 0), order.count - 1)
        extend(to: order[target], in: order)
    }

    /// ⇧Home / ⇧End: extends to the first or last card.
    public mutating func extend(toEdge last: Bool, in order: [UUID]) {
        guard let edge = last ? order.last : order.first else { return }
        extend(to: edge, in: order)
    }

    /// ⌘A. The cursor stays where it is.
    public mutating func selectAll(in order: [UUID]) {
        guard !order.isEmpty else { return }
        ids = Set(order)
        if cursor == nil || !ids.contains(cursor!) { cursor = order.first }
        if anchor == nil || !ids.contains(anchor!) { anchor = cursor }
    }

    /// Back to just the cursor.
    public mutating func collapse() {
        select(cursor)
    }

    /// After the strip's contents changed: drops cards that are gone. If the cursor went, the
    /// first remaining selected card (or `fallback`) takes it.
    public mutating func reconcile(with order: [UUID], fallback: UUID?) {
        if ids.count <= 1 {
            if let cursor, order.contains(cursor) { return }
            select(fallback)
            return
        }
        let present = Set(order)
        ids.formIntersection(present)
        if let cursor, ids.contains(cursor) {
            if let anchor, !ids.contains(anchor) { self.anchor = cursor }
            return
        }
        guard let first = order.first(where: ids.contains) else {
            select(fallback)
            return
        }
        cursor = first
        if let anchor, ids.contains(anchor) { return }
        anchor = first
    }

    /// The selected cards in `order`, left to right.
    public func ordered(in order: [UUID]) -> [UUID] {
        order.filter(ids.contains)
    }
}
