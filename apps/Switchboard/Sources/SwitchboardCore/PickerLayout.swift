import Foundation

/// How big the picker's rows are. Set in General.
public enum PickerSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large

    public var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// App icon edge, in points.
    public var iconSize: Double {
        switch self {
        case .small: 24
        case .medium: 32
        case .large: 44
        }
    }

    /// The gap around the icon inside a row, on every side (the row's horizontal padding
    /// is the same, so the icon sits evenly inside the selection highlight).
    public static let rowInset: Double = 8

    /// One row: the icon plus `rowInset` above and below.
    public var rowHeight: Double { iconSize + 2 * Self.rowInset }
}

/// The picker's list geometry: every row fits, or the list scrolls so the panel stays on screen.
/// Pure arithmetic so it's unit-tested; the view uses fixed row heights to match it.
public struct PickerLayout: Equatable, Sendable {
    public static let rowSpacing: Double = 2

    public let rowCount: Int
    public let rowHeight: Double
    /// Height of the list area (all rows, or as many as fit when scrolling).
    public let listHeight: Double
    public let scrolls: Bool

    /// - Parameter availableHeight: room for the list: the screen's visible height minus the
    ///   panel's margins, header and footer.
    public init(rowCount: Int, size: PickerSize, availableHeight: Double) {
        self.rowCount = max(rowCount, 0)
        rowHeight = size.rowHeight
        let full = Self.height(rows: self.rowCount, rowHeight: rowHeight)
        // Leave room for three rows even on a tiny screen (two and a half show when it scrolls).
        let floor = Self.height(rows: min(self.rowCount, 3), rowHeight: rowHeight)
        let room = max(availableHeight, floor)
        if full <= room {
            listHeight = full
            scrolls = false
        } else {
            // Show whole rows plus half of the next, so it's obvious the list scrolls.
            let whole = max(Int((room - rowHeight / 2) / (rowHeight + Self.rowSpacing)), 1)
            listHeight = min(Self.height(rows: whole, rowHeight: rowHeight) + rowHeight / 2, room)
            scrolls = true
        }
    }

    static func height(rows: Int, rowHeight: Double) -> Double {
        guard rows > 0 else { return 0 }
        return Double(rows) * rowHeight + Double(rows - 1) * rowSpacing
    }
}

/// Keyboard selection in the picker list.
public enum PickerSelection {
    /// Moves by `delta`, wrapping at both ends (Tab keeps cycling, like a menu).
    public static func moved(from index: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let start = min(max(index, 0), count - 1)
        return ((start + delta) % count + count) % count
    }

    /// The number key shown on a row: 1–9 for the first nine, nothing after.
    public static func keyLabel(for index: Int) -> String? {
        (0..<9).contains(index) ? String(index + 1) : nil
    }
}
