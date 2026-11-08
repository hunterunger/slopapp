import Foundation

/// A fixed-capacity ring buffer: appending past capacity drops the oldest element.
public struct Ring<Element: Sendable>: Sendable {
    private var storage: [Element] = []
    private var head = 0
    public let capacity: Int

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }

    public mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        head = 0
    }

    /// Oldest first.
    public var elements: [Element] {
        storage.count < capacity ? storage : Array(storage[head...] + storage[..<head])
    }

    public var last: Element? {
        guard !storage.isEmpty else { return nil }
        return storage.count < capacity ? storage.last : storage[(head + capacity - 1) % capacity]
    }
}

/// How far back a history graph looks.
public enum HistorySpan: String, Sendable, CaseIterable, Codable {
    case tenMinutes
    case hour

    public var seconds: TimeInterval {
        switch self {
        case .tenMinutes: 600
        case .hour: 3600
        }
    }

    public var title: String {
        switch self {
        case .tenMinutes: "10 min"
        case .hour: "1 hour"
        }
    }

    /// For VoiceOver and the graph's caption.
    public var spokenTitle: String {
        switch self {
        case .tenMinutes: "last 10 minutes"
        case .hour: "last hour"
        }
    }
}

/// One metric's history, in memory only: every sample for the last 10 minutes, and 30-second
/// averages for the last hour. Sleep shows up as a gap (a NaN point), never as a line drawn
/// across it.
public struct TimeSeries: Sendable {
    public struct Point: Sendable, Equatable {
        /// Monotonic seconds.
        public var time: Double
        /// NaN marks a gap.
        public var value: Float

        public init(time: Double, value: Float) {
            self.time = time
            self.value = value
        }

        public var isGap: Bool { value.isNaN }
    }

    public static let bucketSeconds: Double = 30

    private var fine: Ring<Point>
    private var coarse: Ring<Point>
    private var bucket: Int?
    private var bucketSum: Double = 0
    private var bucketCount = 0

    /// `fineCapacity` covers 10 minutes at the fastest rate (1 s); `coarseCapacity` an hour of
    /// 30 s buckets.
    public init(fineCapacity: Int = 600, coarseCapacity: Int = 120) {
        fine = Ring(capacity: fineCapacity)
        coarse = Ring(capacity: coarseCapacity)
    }

    public mutating func append(_ value: Double, at time: Double) {
        guard value.isFinite else { return }
        fine.append(Point(time: time, value: Float(value)))
        let index = Int((time / Self.bucketSeconds).rounded(.down))
        if let bucket, bucket != index { flushBucket() }
        bucket = index
        bucketSum += value
        bucketCount += 1
    }

    /// The Mac slept (or sampling paused): the graph breaks here.
    public mutating func appendGap(at time: Double) {
        if fine.last?.isGap == true { return }
        guard !fine.isEmpty else { return }
        fine.append(Point(time: time, value: .nan))
        flushBucket()
        coarse.append(Point(time: time, value: .nan))
    }

    private mutating func flushBucket() {
        guard let bucket, bucketCount > 0 else { return }
        let start = Double(bucket) * Self.bucketSeconds
        coarse.append(Point(time: start + Self.bucketSeconds / 2, value: Float(bucketSum / Double(bucketCount))))
        self.bucket = nil
        bucketSum = 0
        bucketCount = 0
    }

    /// Points within `span` of `now`, oldest first. 10 minutes uses every sample; an hour
    /// uses the 30 s averages plus the bucket still filling, so the graph is live.
    public func points(span: HistorySpan, now: Double) -> [Point] {
        let start = now - span.seconds
        switch span {
        case .tenMinutes:
            return fine.elements.filter { $0.time >= start }
        case .hour:
            var result = coarse.elements.filter { $0.time >= start }
            if let bucket, bucketCount > 0 {
                result.append(Point(time: Double(bucket) * Self.bucketSeconds + Self.bucketSeconds / 2,
                                    value: Float(bucketSum / Double(bucketCount))))
            }
            return result
        }
    }

    /// The highest value in the span (ignoring gaps), or nil if there's none.
    public func peak(span: HistorySpan, now: Double) -> Double? {
        points(span: span, now: now).lazy.filter { !$0.isGap }.map { Double($0.value) }.max()
    }

    /// At most about `maxCount` points for a graph that many points wide: each run of samples
    /// becomes its highest one (so spikes survive), and gaps stay gaps.
    public static func decimate(_ points: [Point], to maxCount: Int) -> [Point] {
        guard maxCount > 0, points.count > maxCount else { return points }
        let size = (points.count + maxCount - 1) / maxCount
        var result: [Point] = []
        result.reserveCapacity(maxCount + 8)
        var index = 0
        while index < points.count {
            let bucket = points[index..<min(points.count, index + size)]
            var kept: [Point] = []
            if let peak = bucket.filter({ !$0.isGap }).max(by: { $0.value < $1.value }) { kept.append(peak) }
            if let gap = bucket.first(where: \.isGap) { kept.append(gap) }
            result.append(contentsOf: kept.sorted { $0.time < $1.time })
            index += size
        }
        return result
    }

    public var latest: Double? {
        guard let last = fine.last, !last.isGap else { return nil }
        return Double(last.value)
    }

    public var isEmpty: Bool { fine.isEmpty }
}
