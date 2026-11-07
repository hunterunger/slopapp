import Foundation

/// A piece of the history graph inside one row. Rows are drawn independently: a line enters
/// at the top edge, leaves at the bottom edge, or meets the row's commit dot in the middle.
public struct GraphSegment: Sendable, Equatable {
    public enum Kind: UInt8, Sendable {
        /// Straight down through the row (another branch passing by).
        case through
        /// From the top edge at `lane` into the dot (a child above).
        case intoNode
        /// From the dot to the bottom edge at `lane` (a parent below).
        case outOfNode
    }

    public var kind: Kind
    public var lane: UInt16
    /// Index into the lane palette.
    public var color: UInt8

    public init(kind: Kind, lane: UInt16, color: UInt8) {
        self.kind = kind
        self.lane = lane
        self.color = color
    }
}

/// Assigns history rows to lanes, incrementally, as rows stream in (newest first,
/// topological order). Lanes never shift sideways, so every line is straight down or a
/// single diagonal into or out of a dot. Stored flat: a 100,000-row history is two
/// arrays, not 100,000 small ones.
public struct GraphLayout: Sendable {
    /// Number of distinct lane colours the UI provides.
    public static let paletteSize: UInt8 = 8

    private var lanes: [ObjectID?] = []
    private var laneColors: [UInt8] = []
    private var nextColor: UInt8 = 0

    private var segments: [GraphSegment] = []
    private var rowStarts: [Int32] = [0]
    private var columns: [UInt16] = []
    private var nodeColors: [UInt8] = []
    /// The most lanes any row has used so far.
    public private(set) var maxLanes = 0

    public init() {}

    public var rowCount: Int { columns.count }

    public mutating func reserve(_ rows: Int) {
        columns.reserveCapacity(rows)
        nodeColors.reserveCapacity(rows)
        rowStarts.reserveCapacity(rows + 1)
        segments.reserveCapacity(rows * 4)
    }

    /// Lays out the next row.
    public mutating func append(id: ObjectID, parents: [ObjectID]) {
        var column = lanes.firstIndex(where: { $0 == id }) ?? -1
        if column < 0 {
            column = lanes.firstIndex(where: { $0 == nil }) ?? lanes.count
            if column == lanes.count { lanes.append(nil); laneColors.append(0) }
            laneColors[column] = takeColor()
        }
        let nodeColor = laneColors[column]

        for i in lanes.indices {
            guard let lane = lanes[i] else { continue }
            if lane == id {
                segments.append(GraphSegment(kind: .intoNode, lane: UInt16(i), color: laneColors[i]))
                lanes[i] = nil
            } else {
                segments.append(GraphSegment(kind: .through, lane: UInt16(i), color: laneColors[i]))
            }
        }

        for (n, parent) in parents.enumerated() {
            if let existing = lanes.firstIndex(where: { $0 == parent }) {
                segments.append(GraphSegment(kind: .outOfNode, lane: UInt16(existing), color: laneColors[existing]))
                continue
            }
            let target: Int
            if n == 0 {
                target = column
                laneColors[target] = nodeColor
            } else {
                target = lanes.firstIndex(where: { $0 == nil }) ?? lanes.count
                if target == lanes.count { lanes.append(nil); laneColors.append(0) }
                laneColors[target] = takeColor()
            }
            lanes[target] = parent
            segments.append(GraphSegment(kind: .outOfNode, lane: UInt16(target), color: laneColors[target]))
        }
        maxLanes = max(maxLanes, lanes.count, column + 1)
        while let last = lanes.last, last == nil { lanes.removeLast(); laneColors.removeLast() }

        columns.append(UInt16(column))
        nodeColors.append(nodeColor)
        rowStarts.append(Int32(segments.count))
    }

    private mutating func takeColor() -> UInt8 {
        defer { nextColor = (nextColor + 1) % Self.paletteSize }
        return nextColor
    }

    /// The dot's lane in `row`.
    public func column(of row: Int) -> Int { Int(columns[row]) }
    public func nodeColor(of row: Int) -> UInt8 { nodeColors[row] }

    /// The segments drawn in `row`.
    public func segments(of row: Int) -> ArraySlice<GraphSegment> {
        segments[Int(rowStarts[row])..<Int(rowStarts[row + 1])]
    }

    /// The widest lane index used between these rows (for sizing the graph column).
    public func lanes(in rows: Range<Int>) -> Int {
        var widest = 0
        for row in rows.clamped(to: 0..<rowCount) {
            widest = max(widest, column(of: row) + 1)
            for s in segments(of: row) { widest = max(widest, Int(s.lane) + 1) }
        }
        return widest
    }
}
