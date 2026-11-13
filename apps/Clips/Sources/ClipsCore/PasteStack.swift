import Foundation

/// A paste stack: clips lined up to paste one after another (filling in a form). While it's
/// on, every recorded copy joins the end, and each paste takes the next clip. It ends by
/// itself after the last one, or when cancelled.
public struct PasteStack: Equatable, Sendable {
    /// Every clip in the stack, in paste order (pasted ones included, so the stack can show them).
    public private(set) var items: [UUID]
    /// The next clip to paste.
    public private(set) var position = 0

    public init(items: [UUID] = []) {
        self.items = items
    }

    public var next: UUID? { items.indices.contains(position) ? items[position] : nil }
    public var remaining: Int { max(0, items.count - position) }
    public var pastedCount: Int { min(position, items.count) }
    /// Nothing left to paste (and something was in it).
    public var isFinished: Bool { !items.isEmpty && position >= items.count }
    /// The clips still to come, next first.
    public var upcoming: ArraySlice<UUID> { items[min(position, items.count)...] }

    /// A copy was recorded: it joins the end. The same clip twice is allowed (a form can need
    /// the same value twice).
    public mutating func add(_ id: UUID) {
        items.append(id)
    }

    /// The next clip was pasted. Returns the one after it, or nil when the stack is done.
    @discardableResult
    public mutating func advance() -> UUID? {
        if position < items.count { position += 1 }
        return next
    }

    /// Makes the clip at `index` (in `items`) the next one: skip ahead, or go back to one.
    public mutating func move(to index: Int) {
        guard items.indices.contains(index) else { return }
        position = index
    }

    /// Clips that were deleted leave the stack.
    public mutating func remove(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let before = items[..<min(position, items.count)].filter { ids.contains($0) }.count
        items.removeAll { ids.contains($0) }
        position = max(0, position - before)
    }
}

/// Tells a paste apart from the other reads of the clipboard. Clips puts the stack's next clip
/// on the clipboard as a promise, so it hears when an app asks for the data, which happens
/// when you paste. One paste can ask for several types (RTF, then text), so only the first
/// read of each clip put out counts; later reads of the same one are the same paste.
public struct PasteReadTracker: Equatable, Sendable {
    /// Which clip put out is current; each one gets a new number.
    public private(set) var current = 0
    private var counted = Set<Int>()

    public init() {}

    /// A new clip went on the clipboard. Returns its number, for the reads to quote.
    public mutating func arm() -> Int {
        current += 1
        return current
    }

    /// The clipboard was replaced by something else (a copy, or Clips' own paste).
    public mutating func disarm() {
        current += 1
    }

    /// An app read clip number `serial`. True when that's a paste of the current clip that
    /// hasn't been counted yet.
    public mutating func read(serial: Int) -> Bool {
        guard serial > 0, serial == current, counted.insert(serial).inserted else { return false }
        return true
    }
}
