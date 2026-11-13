import Foundation

/// The colour of a board's dot. Named system colours, so they follow light and dark mode and
/// the Increase Contrast setting; stored by name.
public enum BoardColor: String, Sendable, CaseIterable, Codable, Identifiable {
    case red, orange, yellow, green, teal, blue, purple, pink, gray

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .teal: "Teal"
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        case .gray: "Gray"
        }
    }
}

/// A named, coloured collection of clips the user keeps ("Addresses", "Work"). Clips on a board
/// are pinned: never removed by retention or Clear History. A clip is on one board at a time.
public struct Board: Identifiable, Sendable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var color: BoardColor

    public init(id: UUID = UUID(), name: String, color: BoardColor) {
        self.id = id
        self.name = name
        self.color = color
    }

    /// The board every history starts with, and where clips pinned before boards existed went.
    /// A fixed id, so an older build's pins (the `pinned` column alone) can always find it.
    public static let pinnedID = UUID(uuidString: "C1195000-0000-4000-8000-000000000001")!
    public static let pinned = Board(id: pinnedID, name: "Pinned", color: .orange)

    /// The longest name a board keeps (tabs truncate long ones anyway).
    public static let nameLimit = 60

    /// A name as typed: whitespace collapsed and trimmed, capped. Nil when nothing is left.
    public static func cleanName(_ raw: String) -> String? {
        let name = ClipText.oneLine(raw, limit: nameLimit)
        return name.isEmpty ? nil : name
    }
}

/// The user's boards in tab order. Pure: the app persists what changes.
public struct Boards: Sendable, Equatable {
    public private(set) var all: [Board]

    public init(_ boards: [Board] = []) {
        all = boards
    }

    public var isEmpty: Bool { all.isEmpty }
    public var first: Board? { all.first }

    public func board(id: UUID?) -> Board? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    public func index(of id: UUID) -> Int? { all.firstIndex { $0.id == id } }

    /// A colour no board uses yet (in palette order), or the least used one.
    public func nextColor() -> BoardColor {
        let used = all.map(\.color)
        if let free = BoardColor.allCases.first(where: { !used.contains($0) }) { return free }
        return BoardColor.allCases.min { a, b in used.filter { $0 == a }.count < used.filter { $0 == b }.count } ?? .blue
    }

    /// `base`, or `base 2`, `base 3`… so two boards never share a name by accident.
    public func uniqueName(_ base: String, ignoring id: UUID? = nil) -> String {
        let taken = Set(all.filter { $0.id != id }.map { $0.name.lowercased() })
        if !taken.contains(base.lowercased()) { return base }
        var n = 2
        while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }

    /// Adds a board at the end. The name is cleaned and made unique; empty means "New Board".
    @discardableResult
    public mutating func add(name: String = "New Board", color: BoardColor? = nil, id: UUID = UUID()) -> Board {
        let board = Board(id: id, name: uniqueName(Board.cleanName(name) ?? "New Board"), color: color ?? nextColor())
        all.append(board)
        return board
    }

    /// Renames a board. An empty name changes nothing. Returns the board if it changed.
    @discardableResult
    public mutating func rename(_ id: UUID, to raw: String) -> Board? {
        guard let index = index(of: id), let name = Board.cleanName(raw), name != all[index].name else { return nil }
        all[index].name = uniqueName(name, ignoring: id)
        return all[index]
    }

    @discardableResult
    public mutating func setColor(_ color: BoardColor, of id: UUID) -> Board? {
        guard let index = index(of: id), all[index].color != color else { return nil }
        all[index].color = color
        return all[index]
    }

    /// Moves a board `delta` places along the tabs (clamped). Returns true if it moved.
    @discardableResult
    public mutating func move(_ id: UUID, by delta: Int) -> Bool {
        guard let from = index(of: id) else { return false }
        let to = min(max(from + delta, 0), all.count - 1)
        guard to != from else { return false }
        let board = all.remove(at: from)
        all.insert(board, at: to)
        return true
    }

    /// The List `.onMove` form: boards at `offsets` go before `destination`.
    public mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let moving = offsets.sorted().map { all[$0] }
        let before = offsets.filter { $0 < destination }.count
        for index in offsets.sorted(by: >) { all.remove(at: index) }
        all.insert(contentsOf: moving, at: min(max(destination - before, 0), all.count))
    }

    @discardableResult
    public mutating func remove(_ id: UUID) -> Board? {
        guard let index = index(of: id) else { return nil }
        return all.remove(at: index)
    }

    /// Where ⌘P puts a clip: the first board (Pinned, unless the user changed things).
    public var defaultBoard: Board? { all.first }
}
