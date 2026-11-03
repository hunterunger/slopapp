import Darwin

/// How different two neighbouring pixels must be to count as an edge.
///
/// The difference is the largest per-channel change (0–255). An edge sits wherever two
/// *neighbouring* pixels differ by more than the threshold, so smooth gradients and soft
/// shadows don't stop a measurement, while real element borders do. Even flat fills differ
/// by 1–2 levels in a real capture, so the strictest level still allows a little.
public enum Tolerance: Int, CaseIterable, Sendable, Identifiable {
    /// Almost any visible change is an edge.
    case strict
    case fine
    /// The default: ignores anti-aliasing haze, compression noise and soft shadows.
    case normal
    case loose

    public var id: Int { rawValue }

    public static let `default` = Tolerance.normal

    public var threshold: Int {
        switch self {
        case .strict: 3
        case .fine: 8
        case .normal: 20
        case .loose: 56
        }
    }

    public var title: String {
        switch self {
        case .strict: "Strict"
        case .fine: "Fine"
        case .normal: "Normal"
        case .loose: "Loose"
        }
    }

    /// One step more tolerant (fewer edges), or nil at the end.
    public var looser: Tolerance? { Tolerance(rawValue: rawValue + 1) }
    /// One step less tolerant (more edges), or nil at the end.
    public var stricter: Tolerance? { Tolerance(rawValue: rawValue - 1) }
}

/// Memory for a decoded display image, mapped straight from the system so it goes back to
/// it the moment the overlay closes (malloc keeps big freed blocks around otherwise, which
/// left ~90 MB resident after a session on a 5K + Retina setup).
public final class PixelStorage: @unchecked Sendable {
    public let pointer: UnsafeMutablePointer<UInt8>
    public let count: Int
    private let mappedLength: Int

    /// Zero-filled bytes, or nil if the system refuses the mapping.
    public init?(count: Int) {
        guard count > 0 else { return nil }
        let page = Int(getpagesize())
        let length = (count + page - 1) / page * page
        let raw = mmap(nil, length, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0)
        guard let raw, raw != MAP_FAILED else { return nil }
        pointer = raw.bindMemory(to: UInt8.self, capacity: count)
        self.count = count
        mappedLength = length
    }

    deinit {
        munmap(UnsafeMutableRawPointer(pointer), mappedLength)
    }

    var buffer: UnsafeBufferPointer<UInt8> { UnsafeBufferPointer(start: pointer, count: count) }
}

/// A frozen display's pixels, for finding edges. RGBA bytes (8-bit, sRGB, premultiplied), top
/// row first. Fully transparent pixels (masked in test mode) read as black.
public struct EdgeImage: Sendable {
    public let width: Int
    public let height: Int
    public let storage: PixelStorage

    public init?(width: Int, height: Int, storage: PixelStorage) {
        guard width > 0, height > 0, storage.count >= width * height * 4 else { return nil }
        self.width = width
        self.height = height
        self.storage = storage
    }

    /// Copies `bytes` (tests, small images).
    public init?(width: Int, height: Int, bytes: [UInt8]) {
        guard width > 0, height > 0, bytes.count >= width * height * 4,
              let storage = PixelStorage(count: width * height * 4) else { return nil }
        bytes.withUnsafeBufferPointer { storage.pointer.update(from: $0.baseAddress!, count: width * height * 4) }
        self.init(width: width, height: height, storage: storage)
    }

    /// Fresh zeroed storage for an image of this size, to draw into.
    public static func storage(width: Int, height: Int) -> PixelStorage? {
        PixelStorage(count: width * height * 4)
    }

    public var bounds: PixelRect { PixelRect(minX: 0, minY: 0, maxX: width, maxY: height) }

    /// The (r, g, b) of a pixel, or nil outside the image.
    public func color(at point: PixelPoint) -> (r: UInt8, g: UInt8, b: UInt8)? {
        guard bounds.contains(point) else { return nil }
        let i = (point.y * width + point.x) * 4
        let p = storage.pointer
        return (p[i], p[i + 1], p[i + 2])
    }

    private func withPixels<T>(_ body: (UnsafeBufferPointer<UInt8>) -> T) -> T {
        withExtendedLifetime(storage) { body(storage.buffer) }
    }

    @inline(__always)
    private static func difference(_ p: UnsafeBufferPointer<UInt8>, _ a: Int, _ b: Int) -> Int {
        let i = a &* 4, j = b &* 4
        let dr = abs(Int(p[i]) &- Int(p[j]))
        let dg = abs(Int(p[i &+ 1]) &- Int(p[j &+ 1]))
        let db = abs(Int(p[i &+ 2]) &- Int(p[j &+ 2]))
        return max(dr, max(dg, db))
    }

    /// The largest difference between neighbouring pixels inside `rect` (how noisy a flat
    /// fill is in a real capture; the self-check logs it to tune tolerances).
    public func noise(in rect: PixelRect) -> Int {
        guard let r = rect.intersection(bounds), r.width > 1, r.height > 1 else { return 0 }
        let w = width
        return withPixels { p in
            var most = 0
            for y in r.minY..<(r.maxY - 1) {
                for x in r.minX..<(r.maxX - 1) {
                    let i = y * w + x
                    most = max(most, Self.difference(p, i, i + 1), Self.difference(p, i, i + w))
                }
            }
            return most
        }
    }

    // MARK: Hover distance

    /// The run of pixels around `point` with no edge in it, horizontally (along the row) and
    /// vertically (along the column), stopping at `limits` (placed measurements, guides).
    ///
    /// The result's `minX`/`maxX` are the left and right edges of the horizontal span and
    /// `minY`/`maxY` the top and bottom of the vertical one. A side with no edge runs to the
    /// limit (normally the image border).
    public func spans(at point: PixelPoint, tolerance: Tolerance, limits: PixelRect? = nil) -> PixelRect? {
        let limit = (limits ?? bounds).intersection(bounds) ?? bounds
        guard limit.contains(point) else { return nil }
        let t = tolerance.threshold
        let w = width
        return withPixels { p -> PixelRect in
            let row = point.y * w
            var left = limit.minX
            var k = point.x
            while k > limit.minX {
                if Self.difference(p, row + k, row + k - 1) > t { left = k; break }
                k -= 1
            }
            var right = limit.maxX
            k = point.x
            while k < limit.maxX - 1 {
                if Self.difference(p, row + k, row + k + 1) > t { right = k + 1; break }
                k += 1
            }
            var top = limit.minY
            k = point.y
            while k > limit.minY {
                if Self.difference(p, k * w + point.x, (k - 1) * w + point.x) > t { top = k; break }
                k -= 1
            }
            var bottom = limit.maxY
            k = point.y
            while k < limit.maxY - 1 {
                if Self.difference(p, k * w + point.x, (k + 1) * w + point.x) > t { bottom = k + 1; break }
                k += 1
            }
            return PixelRect(minX: left, minY: top, maxX: right, maxY: bottom)
        }
    }

    /// The nearest edge to `position` along one axis through `point`, within `maxDistance`
    /// pixels (for snapping guides). Returns a boundary coordinate.
    public func nearestEdge(to point: PixelPoint, axis: GuideAxis, tolerance: Tolerance, maxDistance: Int) -> Int? {
        guard let s = spans(at: point, tolerance: tolerance) else { return nil }
        let (position, low, high, end) = axis == .vertical
            ? (point.x, s.minX, s.maxX, width) : (point.y, s.minY, s.maxY, height)
        var candidates: [Int] = []
        if low > 0 { candidates.append(low) }
        if high < end { candidates.append(high) }
        return candidates
            .filter { abs($0 - position) <= maxDistance }
            .min { abs($0 - position) < abs($1 - position) }
    }

    // MARK: Element bounds

    /// The exact bounds of whatever sits inside `rect`, or nil if the rect holds no edge at
    /// all (then the caller keeps the box as drawn).
    ///
    /// Each side moves inward to the first edge it meets, using the same rule as the hover
    /// distance: neighbouring pixels that differ by more than the tolerance. Gradients and
    /// soft shadows have no such edge, so a card's shadow is left out and its own border is
    /// found. A side that meets no edge stays where it was drawn (content running past the box).
    public func contentBounds(in rect: PixelRect, tolerance: Tolerance) -> PixelRect? {
        guard let r = rect.intersection(bounds), r.width >= 1, r.height >= 1 else { return nil }
        let t = tolerance.threshold
        let w = width
        return withPixels { p -> PixelRect? in
            // Left and right: the first horizontal edge from each side, over every row.
            var left = Int.max, right = Int.min
            if r.width > 1 {
                for y in r.minY..<r.maxY {
                    let row = y * w
                    var x = r.minX
                    let leftLimit = min(left, r.maxX - 1)
                    while x < leftLimit {
                        if Self.difference(p, row + x, row + x + 1) > t { left = x + 1; break }
                        x += 1
                    }
                    x = r.maxX - 1
                    let rightLimit = max(right, r.minX + 1)
                    while x >= rightLimit {
                        if Self.difference(p, row + x - 1, row + x) > t { right = x; break }
                        x -= 1
                    }
                }
            }
            // Top and bottom: the first row (from each side) with a vertical edge in it.
            var top = Int.max, bottom = Int.min
            if r.height > 1 {
                func rowHasEdge(_ y: Int) -> Bool {
                    let a = y * w, b = (y + 1) * w
                    for x in r.minX..<r.maxX where Self.difference(p, a + x, b + x) > t { return true }
                    return false
                }
                for y in r.minY..<(r.maxY - 1) where rowHasEdge(y) { top = y + 1; break }
                if top != Int.max {
                    for y in stride(from: r.maxY - 2, through: r.minY, by: -1) where rowHasEdge(y) { bottom = y + 1; break }
                }
            }
            guard left != Int.max || top != Int.max else { return nil }
            var result = r
            // Content running past the box on one side leaves a single edge on that axis: keep
            // the part of the box on the content's side of it (the side that isn't background).
            let background = Self.dominantColor(p, perimeterOf: r, width: w)
            if left != Int.max, right != Int.min {
                if right > left {
                    result.minX = left
                    result.maxX = right
                } else if let y = Self.rowWithEdge(p, column: left - 1, in: r, width: w, threshold: t),
                          Self.difference(p, y * w + left, background) <= Self.difference(p, y * w + left - 1, background) {
                    result.maxX = left // content is on the left: the edge is its right side
                } else {
                    result.minX = left
                }
            }
            if top != Int.max, bottom != Int.min {
                if bottom > top {
                    result.minY = top
                    result.maxY = bottom
                } else {
                    let x = Self.columnWithEdge(p, row: top - 1, in: r, width: w, threshold: t) ?? r.minX
                    if Self.difference(p, top * w + x, background) <= Self.difference(p, (top - 1) * w + x, background) {
                        result.maxY = top
                    } else {
                        result.minY = top
                    }
                }
            }
            return result
        }
    }

    /// The most common color on a rect's border (5 bits per channel), as a pixel index.
    private static func dominantColor(_ p: UnsafeBufferPointer<UInt8>, perimeterOf r: PixelRect, width w: Int) -> Int {
        var counts: [Int: (count: Int, sample: Int)] = [:]
        func add(_ index: Int) {
            let i = index * 4
            let key = Int(p[i] >> 3) << 10 | Int(p[i + 1] >> 3) << 5 | Int(p[i + 2] >> 3)
            let entry = counts[key] ?? (0, index)
            counts[key] = (entry.count + 1, entry.sample)
        }
        for x in r.minX..<r.maxX { add(r.minY * w + x); add((r.maxY - 1) * w + x) }
        for y in r.minY..<r.maxY { add(y * w + r.minX); add(y * w + r.maxX - 1) }
        return counts.max { $0.value.count < $1.value.count }?.value.sample ?? r.minY * w + r.minX
    }

    /// A row where pixels `column` and `column + 1` differ by more than the threshold.
    private static func rowWithEdge(_ p: UnsafeBufferPointer<UInt8>, column: Int, in r: PixelRect, width w: Int, threshold t: Int) -> Int? {
        (r.minY..<r.maxY).first { difference(p, $0 * w + column, $0 * w + column + 1) > t }
    }

    /// A column where pixels on `row` and `row + 1` differ by more than the threshold.
    private static func columnWithEdge(_ p: UnsafeBufferPointer<UInt8>, row: Int, in r: PixelRect, width w: Int, threshold t: Int) -> Int? {
        (r.minX..<r.maxX).first { difference(p, row * w + $0, (row + 1) * w + $0) > t }
    }
}
