import Foundation

/// Made-up history for performance tests and screenshots. Text and links contain
/// "slopapp-test" so they can't be mistaken for real clipboard content. It only ever goes
/// into a test data directory (CLIPS_DATA_DIR), never onto the pasteboard.
public enum SyntheticHistory {
    public static let prefix = "slopapp-test"

    public static func make(count: Int, now: Date, seed: UInt64 = 42) -> [(Clip, ClipPayload)] {
        var rng = SplitMix(seed: seed)
        let words = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india",
                     "juliett", "kilo", "lima", "mike", "november", "oscar", "papa", "quebec", "romeo",
                     "sierra", "tango", "uniform", "victor", "whiskey", "xray", "yankee", "zulu",
                     "café", "naïve", "résumé", "invoice", "meeting", "deploy", "release", "draft"]
        let apps = [("com.apple.TextEdit", "TextEdit"), ("com.apple.Notes", "Notes"),
                    ("com.apple.Safari", "Safari"), ("com.apple.dt.Xcode", "Xcode"), ("com.apple.mail", "Mail")]
        var result: [(Clip, ClipPayload)] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            let date = now.addingTimeInterval(-Double(index) * 97 - Double(rng.next() % 60))
            let app = apps[Int(rng.next() % UInt64(apps.count))]
            let text: String
            switch index % 10 {
            case 0:
                text = "https://example.com/\(prefix)/\(words[Int(rng.next() % UInt64(words.count))])/\(index)"
            case 1:
                text = "#\(String(format: "%06X", Int(rng.next() % 0xFFFFFF)))"
            default:
                let wordCount = 4 + Int(rng.next() % 60)
                let body = (0..<wordCount).map { _ in words[Int(rng.next() % UInt64(words.count))] }.joined(separator: " ")
                let lines = index % 7 == 0 ? "\n\(body)\n\(body)" : ""
                text = "\(prefix) synthetic #\(index) \(body)\(lines)"
            }
            let built = ClipBuilder.build(PasteboardSnapshot(text: text), sourceBundleID: app.0, sourceName: app.1, now: date)
            if case .success(let entry) = built { result.append(entry) }
        }
        return result
    }
}

/// Small deterministic PRNG so synthetic data is the same every run.
struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
