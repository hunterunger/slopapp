import Foundation

/// Arrow-key movement in a grid split into sections (days), each starting on a new row:
/// left/right step through the flat order, up/down keep the column and cross into the
/// neighbouring section's nearest row, like Finder's icon view and Photos.
public struct GridNavigation: Equatable, Sendable {
    public enum Move: Sendable { case left, right, up, down, home, end }

    /// Item counts per section, in order.
    public let sections: [Int]
    public let columns: Int

    public init(sections: [Int], columns: Int) {
        self.sections = sections.filter { $0 > 0 }
        self.columns = max(columns, 1)
    }

    public var count: Int { sections.reduce(0, +) }

    /// Where `move` goes from flat index `index` (nil: nothing focused yet → the first item).
    public func target(from index: Int?, _ move: Move) -> Int? {
        guard count > 0 else { return nil }
        guard let index, index >= 0, index < count else { return move == .end ? count - 1 : 0 }
        switch move {
        case .left: return max(index - 1, 0)
        case .right: return min(index + 1, count - 1)
        case .home: return 0
        case .end: return count - 1
        case .up, .down:
            let (section, offset) = locate(index)
            let row = offset / columns, column = offset % columns
            let rows = rowCount(section)
            if move == .down {
                if row + 1 < rows { return start(of: section) + min((row + 1) * columns + column, sections[section] - 1) }
                guard section + 1 < sections.count else { return index }
                return start(of: section + 1) + min(column, sections[section + 1] - 1)
            } else {
                if row > 0 { return start(of: section) + (row - 1) * columns + column }
                guard section > 0 else { return index }
                let previous = section - 1, lastRow = rowCount(previous) - 1
                return start(of: previous) + min(lastRow * columns + column, sections[previous] - 1)
            }
        }
    }

    private func start(of section: Int) -> Int { sections.prefix(section).reduce(0, +) }
    private func rowCount(_ section: Int) -> Int { (sections[section] + columns - 1) / columns }

    private func locate(_ index: Int) -> (section: Int, offset: Int) {
        var remaining = index
        for (section, size) in sections.enumerated() {
            if remaining < size { return (section, remaining) }
            remaining -= size
        }
        return (sections.count - 1, sections.last.map { $0 - 1 } ?? 0)
    }

    /// The columns that fit `width` for tiles `tile` wide with `spacing` between them.
    public static func columns(width: Double, tile: Double, spacing: Double) -> Int {
        max(1, Int(((width + spacing) / (tile + spacing)).rounded(.down)))
    }
}
