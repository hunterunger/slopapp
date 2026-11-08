import Foundation

/// A latency histogram: counts per bucket, plus max and total. Numbers only, never what was
/// typed. Recording never allocates.
public struct LatencyStats: Sendable, Equatable {
    /// Bucket upper bounds in microseconds.
    public static let bounds: [Double] = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1_000, 5_000, 30_000, 120_000, 600_000]
    public private(set) var buckets = [Int](repeating: 0, count: LatencyStats.bounds.count + 1)
    public private(set) var count = 0
    public private(set) var maxMicroseconds = 0.0
    public private(set) var totalMicroseconds = 0.0

    public init() {}

    public mutating func record(microseconds: Double) {
        var index = 0
        while index < Self.bounds.count && microseconds > Self.bounds[index] { index += 1 }
        buckets[index] += 1
        count += 1
        totalMicroseconds += microseconds
        if microseconds > maxMicroseconds { maxMicroseconds = microseconds }
    }

    public var meanMicroseconds: Double { count == 0 ? 0 : totalMicroseconds / Double(count) }

    /// The bucket bound under which `fraction` of samples fall (an upper estimate).
    public func percentile(_ fraction: Double) -> Double {
        guard count > 0 else { return 0 }
        let target = Int((Double(count) * fraction).rounded(.up))
        var seen = 0
        for (index, n) in buckets.enumerated() {
            seen += n
            if seen >= target { return index < Self.bounds.count ? Self.bounds[index] : maxMicroseconds }
        }
        return maxMicroseconds
    }

    public var summary: String {
        String(format: "n=%d mean_us=%.2f p50_us<=%.0f p99_us<=%.0f max_us=%.1f", count, meanMicroseconds,
               percentile(0.5), percentile(0.99), maxMicroseconds)
    }
}

/// Monotonic clock in nanoseconds.
public enum MonotonicClock {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    @inline(__always)
    public static func now() -> UInt64 {
        let ticks = mach_absolute_time()
        return ticks &* UInt64(timebase.numer) / UInt64(timebase.denom)
    }
}

/// A keystroke timeline for test mode (`SHORTHAND_REPLAY`): our own JSON, replayed in
/// process into the real engine. Never recorded from a keyboard.
public struct ReplayTimeline: Codable, Sendable, Equatable {
    public struct Step: Codable, Sendable, Equatable {
        /// Milliseconds after the previous step.
        public var after: Double
        /// Typed text (each character one key).
        public var text: String?
        /// A named key: backspace, return, tab, left, escape, click.
        public var key: String?

        public init(after: Double, text: String? = nil, key: String? = nil) {
            self.after = after
            self.text = text
            self.key = key
        }
    }

    public var steps: [Step]
    /// Also type each key into the test target (default). Off for CPU measurements, where
    /// posting the echo would be the harness's cost, not Shorthand's.
    public var echo: Bool?

    public init(steps: [Step], echo: Bool? = nil) {
        self.steps = steps
        self.echo = echo
    }

    /// Text typed at a steady interval, one key per character.
    public static func typing(_ text: String, interval: Double, start: Double = 0) -> ReplayTimeline {
        var steps: [Step] = []
        for (index, character) in text.enumerated() {
            steps.append(Step(after: index == 0 ? start : interval, text: String(character)))
        }
        return ReplayTimeline(steps: steps)
    }

    public static func inputs(for step: Step) -> [KeyInput] {
        if let text = step.text { return KeyInput.text(text) }
        switch step.key {
        case "backspace": return [KeyInput(kind: .backspace)]
        case "return", "tab": return [KeyInput(kind: .boundary)]
        case "left", "escape", "click": return [KeyInput(kind: .reset)]
        default: return []
        }
    }
}

/// The matcher benchmark: synthetic keystrokes through the engine with a large library.
public enum Benchmark {
    /// `count` snippets with abbreviations like `;k1234`.
    public static func library(count: Int) -> [Snippet] {
        let group = UUID()
        return (0..<count).map { i in
            Snippet(groupID: group, abbreviation: ";k\(i)", content: "slopapp-test expansion \(i)",
                    caseMode: i % 5 == 0 ? .adapt : .exact)
        }
    }

    /// Feeds `keys` keystrokes of ordinary text (no matches) and returns per-key timings.
    public static func run(index: AbbreviationIndex, keys: Int) -> LatencyStats {
        var engine = TapEngine()
        engine.index = index
        let text = Array("the quick brown fox jumps over the lazy dog; then types more words, with ;punctuation. ".unicodeScalars)
        var stats = LatencyStats()
        var inputs: [KeyInput] = []
        inputs.reserveCapacity(text.count)
        for scalar in text {
            if scalar == " " || scalar.properties.isAlphabetic || scalar == ";" || scalar == "," || scalar == "." {
                var input = KeyInput(kind: .characters)
                input.append(scalar.value)
                inputs.append(input)
            }
        }
        var now: UInt64 = 1
        for i in 0..<keys {
            let input = inputs[i % inputs.count]
            let start = MonotonicClock.now()
            let decision = engine.handle(input, now: now)
            let end = MonotonicClock.now()
            if case .expand(let match) = decision { engine.cancel(match.id) }
            stats.record(microseconds: Double(end &- start) / 1_000)
            now &+= 100_000_000
        }
        return stats
    }
}
