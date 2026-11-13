import Foundation

/// A word and when it was said, in seconds from the start of the audio.
public struct TimedWord: Equatable, Sendable {
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval

    public init(_ text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = max(start, end)
    }

    /// Joins sub-word tokens into words. A token that starts with a space or SentencePiece's
    /// "▁" begins a new word; blank and padding tokens are skipped.
    public static func words(fromTokens tokens: [(text: String, start: TimeInterval, end: TimeInterval)]) -> [TimedWord] {
        var words: [TimedWord] = []
        var current: TimedWord?
        for token in tokens {
            let text = token.text
            if text.isEmpty || text == "<blank>" || text == "<pad>" || text.hasPrefix("<|") { continue }
            let startsWord = text.hasPrefix(" ") || text.hasPrefix("▁")
            let piece = startsWord ? String(text.drop { $0 == " " || $0 == "▁" }) : text
            if startsWord || current == nil {
                if let word = current, !word.text.isEmpty { words.append(word) }
                current = TimedWord(piece, start: token.start, end: token.end)
            } else if var word = current {
                word.text += piece
                word.end = max(word.end, token.end)
                current = word
            }
        }
        if let word = current, !word.text.isEmpty { words.append(word) }
        return words
    }

    /// Spreads `text` evenly over `duration`, for engines that don't report timings. Words
    /// split on spaces; text without spaces (Chinese, Japanese) splits into characters.
    public static func spread(_ text: String, over duration: TimeInterval) -> [TimedWord] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, duration > 0 else { return [] }
        var pieces = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        if pieces.count == 1, trimmed.count > 24 { pieces = trimmed.map { String($0) } }
        let weights = pieces.map { Double(max(1, $0.count)) }
        let total = weights.reduce(0, +)
        var words: [TimedWord] = []
        var time = 0.0
        for (piece, weight) in zip(pieces, weights) {
            let length = duration * weight / total
            words.append(TimedWord(piece, start: time, end: time + length))
            time += length
        }
        return words
    }
}

/// A transcript with word timings (empty when the engine doesn't report them).
public struct TimedTranscript: Equatable, Sendable {
    public var text: String
    public var words: [TimedWord]

    public init(text: String, words: [TimedWord] = []) {
        self.text = text
        self.words = words
    }

    /// Without the engine's annotations ("[BLANK_AUDIO]", "*music*"), and with timings for
    /// every word: spread over the audio when the engine gave none. Nil when nothing was said.
    public func cleaned(duration: TimeInterval) -> TimedTranscript? {
        guard let text = TextCleanup.meaningfulText(text) else { return nil }
        var words = words.compactMap { word -> TimedWord? in
            guard let cleaned = TextCleanup.meaningfulText(word.text) else { return nil }
            return TimedWord(cleaned, start: word.start, end: word.end)
        }
        if words.isEmpty { words = TimedWord.spread(text, over: duration) }
        return TimedTranscript(text: text, words: words)
    }
}

/// One subtitle: up to two short lines on screen for a few seconds.
public struct SubtitleCue: Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var lines: [String]

    public init(start: TimeInterval, end: TimeInterval, lines: [String]) {
        self.start = start
        self.end = end
        self.lines = lines
    }
}

/// Groups timed words into subtitle cues, following common subtitling practice: at most two
/// lines of about 42 characters, at most about 6 seconds on screen, a new cue after a pause
/// or the end of a sentence.
public enum Subtitles {
    public static let lineLength = 42
    public static let maxLines = 2
    public static let maxDuration: TimeInterval = 6
    /// A silence this long starts a new cue.
    public static let pause: TimeInterval = 0.8
    /// A cue that ends a sentence and has been up this long ends there.
    public static let sentenceBreakAfter: TimeInterval = 1.5
    /// Shortest time a cue stays up, when the next one leaves room.
    public static let minDuration: TimeInterval = 1

    public static func cues(from words: [TimedWord]) -> [SubtitleCue] {
        let words = words.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        var groups: [[TimedWord]] = []
        var current: [TimedWord] = []
        for word in words {
            if let first = current.first, let last = current.last {
                let text = (current + [word]).map(\.text).joined(separator: " ")
                let tooLong = text.count > lineLength * maxLines
                let tooSlow = word.end - first.start > maxDuration
                let paused = word.start - last.end >= pause
                let sentenceDone = endsSentence(last.text) && last.end - first.start >= sentenceBreakAfter
                if tooLong || tooSlow || paused || sentenceDone {
                    groups.append(current)
                    current = []
                }
            }
            current.append(word)
        }
        if !current.isEmpty { groups.append(current) }

        var cues = groups.map { group in
            SubtitleCue(start: group[0].start, end: group[group.count - 1].end,
                        lines: wrap(group.map(\.text).joined(separator: " ")))
        }
        // Give very short cues a moment on screen, without overlapping the next one.
        for index in cues.indices where cues[index].end - cues[index].start < minDuration {
            let limit = index + 1 < cues.count ? cues[index + 1].start : .infinity
            cues[index].end = min(cues[index].start + minDuration, max(cues[index].end, limit))
        }
        return cues
    }

    /// Breaks text into balanced lines of at most `lineLength` characters where it can.
    public static func wrap(_ text: String) -> [String] {
        let words = text.split(separator: " ").map(String.init)
        guard text.count > lineLength, words.count > 1 else { return [text] }
        // Two lines, split at the space that makes them most even and keeps both short.
        var best: (index: Int, score: Int)?
        for split in 1..<words.count {
            let first = words[..<split].joined(separator: " ").count
            let second = words[split...].joined(separator: " ").count
            let over = max(0, first - lineLength) + max(0, second - lineLength)
            let score = over * 100 + abs(first - second)
            if let current = best, current.score <= score { continue }
            best = (split, score)
        }
        let split = best?.index ?? 1
        return [words[..<split].joined(separator: " "), words[split...].joined(separator: " ")]
    }

    static func endsSentence(_ word: String) -> Bool {
        guard let last = word.trimmingCharacters(in: CharacterSet(charactersIn: "\"”’)»")).last else { return false }
        return ".?!。？！".contains(last)
    }
}

/// What a file transcript can be saved as.
public enum TranscriptFormat: String, CaseIterable, Identifiable, Sendable {
    case plainText, subRip, webVTT

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .plainText: "Plain Text"
        case .subRip: "Subtitles (SRT)"
        case .webVTT: "Subtitles (WebVTT)"
        }
    }

    public var fileExtension: String {
        switch self {
        case .plainText: "txt"
        case .subRip: "srt"
        case .webVTT: "vtt"
        }
    }

    public func render(_ transcript: TimedTranscript) -> String {
        switch self {
        case .plainText:
            return transcript.text.hasSuffix("\n") ? transcript.text : transcript.text + "\n"
        case .subRip:
            let cues = Subtitles.cues(from: transcript.words)
            return cues.enumerated().map { index, cue in
                "\(index + 1)\n\(Self.timestamp(cue.start, separator: ",")) --> \(Self.timestamp(cue.end, separator: ","))\n"
                    + cue.lines.joined(separator: "\n") + "\n"
            }.joined(separator: "\n")
        case .webVTT:
            let cues = Subtitles.cues(from: transcript.words)
            return "WEBVTT\n\n" + cues.map { cue in
                "\(Self.timestamp(cue.start, separator: ".")) --> \(Self.timestamp(cue.end, separator: "."))\n"
                    + cue.lines.joined(separator: "\n") + "\n"
            }.joined(separator: "\n")
        }
    }

    /// "01:02:03,456" (SRT) or "01:02:03.456" (WebVTT).
    static func timestamp(_ seconds: TimeInterval, separator: String) -> String {
        let millis = Int((max(0, seconds) * 1000).rounded())
        let hours = millis / 3_600_000
        let minutes = millis / 60_000 % 60
        let secs = millis / 1000 % 60
        let rest = millis % 1000
        return String(format: "%02d:%02d:%02d", hours, minutes, secs) + separator + String(format: "%03d", rest)
    }
}
