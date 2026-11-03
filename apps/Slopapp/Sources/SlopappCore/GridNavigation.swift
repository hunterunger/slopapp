import Foundation

/// Arrow-key movement through app cards laid out as sections of rows (Discover: Available
/// Now, then Coming Soon). Indexes are into the flattened list of all cards.
public struct GridNavigation: Sendable, Equatable {
    public enum Direction: Sendable { case left, right, up, down }

    /// Cards per section, in order.
    public var sections: [Int]
    public var columns: Int

    public init(sections: [Int], columns: Int) {
        self.sections = sections.filter { $0 > 0 }
        self.columns = max(1, columns)
    }

    public var count: Int { sections.reduce(0, +) }

    /// Columns that fit: adaptive grid items of `minimum` width with `spacing` between.
    public static func columns(width: Double, minimum: Double, spacing: Double) -> Int {
        guard width > 0 else { return 1 }
        return max(1, Int((width + spacing) / (minimum + spacing)))
    }

    /// The next selection; nil `from` selects the first card. Stays put at the edges.
    public func move(from index: Int?, _ direction: Direction) -> Int? {
        guard count > 0 else { return nil }
        guard let index, index >= 0, index < count else { return 0 }
        let (section, offset) = locate(index)
        let start = index - offset
        let row = offset / columns, column = offset % columns
        switch direction {
        case .left:
            return max(0, index - 1)
        case .right:
            return min(count - 1, index + 1)
        case .down:
            let rows = (sections[section] + columns - 1) / columns
            if row + 1 < rows {
                return start + min(sections[section] - 1, (row + 1) * columns + column)
            }
            guard section + 1 < sections.count else { return index }
            return start + sections[section] + min(sections[section + 1] - 1, column)
        case .up:
            if row > 0 { return start + (row - 1) * columns + column }
            guard section > 0 else { return index }
            let previous = sections[section - 1]
            let lastRow = (previous - 1) / columns
            return start - previous + min(previous - 1, lastRow * columns + column)
        }
    }

    private func locate(_ index: Int) -> (section: Int, offset: Int) {
        var remaining = index
        for (i, size) in sections.enumerated() {
            if remaining < size { return (i, remaining) }
            remaining -= size
        }
        return (sections.count - 1, sections.last.map { $0 - 1 } ?? 0)
    }
}
