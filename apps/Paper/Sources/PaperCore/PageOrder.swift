import Foundation

/// Index math for page surgery. An "order" is the list of old page indexes in their new
/// positions: `order[newIndex] == oldIndex`.
public enum PageOrder {
    public static func identity(_ count: Int) -> [Int] { Array(0..<count) }

    /// Moves `indices` so they sit together before `destination` (an index in the old
    /// order, `count` meaning the end). The same semantics as SwiftUI's `onMove`.
    public static func moving(_ indices: IndexSet, to destination: Int, count: Int) -> [Int] {
        let moving = indices.filter { $0 >= 0 && $0 < count }
        guard !moving.isEmpty else { return identity(count) }
        let staying = (0..<count).filter { !indices.contains($0) }
        let insertAt = staying.filter { $0 < destination }.count
        var order = staying
        order.insert(contentsOf: moving, at: insertAt)
        return order
    }

    /// Moves each selected page one place earlier. Nil when the first selected page is
    /// already first (nothing would move).
    public static func movingUp(_ indices: IndexSet, count: Int) -> [Int]? {
        guard let first = indices.first, first > 0 else { return nil }
        var order = identity(count)
        for index in indices.sorted() where index > 0 && index < count {
            order.swapAt(index, index - 1)
        }
        return order
    }

    public static func movingDown(_ indices: IndexSet, count: Int) -> [Int]? {
        guard let last = indices.last, last < count - 1 else { return nil }
        var order = identity(count)
        for index in indices.sorted(by: >) where index >= 0 && index < count - 1 {
            order.swapAt(index, index + 1)
        }
        return order
    }

    public static func reversed(_ count: Int) -> [Int] { Array((0..<count).reversed()) }

    /// The order that undoes `order`.
    public static func inverse(_ order: [Int]) -> [Int] {
        var inverse = [Int](repeating: 0, count: order.count)
        for (new, old) in order.enumerated() { inverse[old] = new }
        return inverse
    }

    /// Where each old index ends up, to keep a selection on the same pages after a move.
    public static func newIndexes(of indices: IndexSet, in order: [Int]) -> IndexSet {
        IndexSet(order.enumerated().filter { indices.contains($0.element) }.map(\.offset))
    }

    /// Front and back scans from a one-sided scanner: front pages in order, back pages
    /// usually come out last-to-first. Returns (document, page) pairs: 0 = front, 1 = back.
    public static func interleave(frontCount: Int, backCount: Int, reverseBack: Bool = true) -> [(document: Int, page: Int)] {
        let back = reverseBack ? Array((0..<backCount).reversed()) : Array(0..<backCount)
        var result: [(Int, Int)] = []
        for index in 0..<max(frontCount, backCount) {
            if index < frontCount { result.append((0, index)) }
            if index < back.count { result.append((1, back[index])) }
        }
        return result
    }

    /// Splits into chunks of `size` pages: 10 pages every 4 → 0..<4, 4..<8, 8..<10.
    public static func chunks(pageCount: Int, every size: Int) -> [Range<Int>] {
        guard pageCount > 0, size > 0 else { return [] }
        return stride(from: 0, to: pageCount, by: size).map { $0..<min($0 + size, pageCount) }
    }

    /// Splits at the given start pages (e.g. top-level outline entries). Pages before the
    /// first start become their own part.
    public static func ranges(pageCount: Int, starts: [Int]) -> [Range<Int>] {
        let cuts = Array(Set(starts.filter { $0 > 0 && $0 < pageCount } + [0])).sorted()
        guard pageCount > 0 else { return [] }
        return cuts.enumerated().map { offset, start in
            start..<(offset + 1 < cuts.count ? cuts[offset + 1] : pageCount)
        }
    }

    /// A short label for a range of pages, for file names: "1–4", "7".
    public static func label(_ range: Range<Int>) -> String {
        range.count == 1 ? "\(range.lowerBound + 1)" : "\(range.lowerBound + 1)–\(range.upperBound)"
    }
}
