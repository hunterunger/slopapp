import Foundation

/// What the intention field understood: "Draft intro @work 45m" is the intention
/// "Draft intro" in the Work category for 45 minutes.
public struct ParsedIntention: Equatable, Sendable {
    public var text: String
    /// The category the "@word" matched, if any.
    public var categoryID: String?
    /// Minutes from a "30m", "1h" or "1h30m" word, if any (clamped to the focus range).
    public var minutes: Int?

    public init(text: String, categoryID: String? = nil, minutes: Int? = nil) {
        self.text = text
        self.categoryID = categoryID
        self.minutes = minutes
    }
}

public enum IntentionParser {
    /// Pulls "@category" and duration words out of the typed text. Words that don't match
    /// anything stay in the intention, so "Email @bob" keeps "@bob" if there's no such category.
    public static func parse(_ input: String, categories: [Category]) -> ParsedIntention {
        var kept: [Substring] = []
        var categoryID: String?
        var minutes: Int?
        for word in input.split(whereSeparator: \.isWhitespace) {
            if word.hasPrefix("@"), word.count > 1, let match = category(matching: String(word.dropFirst()), in: categories) {
                categoryID = match.id
            } else if let value = duration(String(word)) {
                minutes = TimerSettings.clamp(value, to: TimerSettings.focusRange)
            } else {
                kept.append(word)
            }
        }
        return ParsedIntention(text: kept.joined(separator: " "), categoryID: categoryID, minutes: minutes)
    }

    /// Exact name first, then a prefix ("@wo" → Work). Case- and accent-insensitive.
    public static func category(matching query: String, in categories: [Category]) -> Category? {
        let q = fold(query)
        guard !q.isEmpty else { return nil }
        let folded = categories.map { (fold($0.name.replacingOccurrences(of: " ", with: "")), $0) }
        return folded.first { $0.0 == q }?.1 ?? folded.first { $0.0.hasPrefix(q) }?.1
    }

    /// "25m", "25min", "1h", "2hr", "1h30m", "1h30" → minutes.
    public static func duration(_ word: String) -> Int? {
        let w = word.lowercased()
        let pattern = /^(?:(\d{1,3})(?:h|hr|hrs))?(?:(\d{1,3})(?:m|min|mins)?)?$/
        guard let match = try? pattern.wholeMatch(in: w) else { return nil }
        let hours = match.1.flatMap { Int($0) }
        let mins = match.2.flatMap { Int($0) }
        // A bare number ("30") is too ambiguous: it needs a unit, unless it follows hours.
        if hours == nil, mins != nil, !w.hasSuffix("m") && !w.hasSuffix("min") && !w.hasSuffix("mins") { return nil }
        guard hours != nil || mins != nil else { return nil }
        let total = (hours ?? 0) * 60 + (mins ?? 0)
        return total > 0 ? total : nil
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// A past intention offered while typing.
public struct IntentionSuggestion: Equatable, Hashable, Sendable, Identifiable {
    public var text: String
    public var categoryID: String?
    public var id: String { text }
}

public enum IntentionSuggestions {
    /// Distinct past intentions containing `query`, most recent first. Matches at the start
    /// of a word rank above matches inside one. An empty query lists the most recent ones.
    public static func make(query: String, records: [SessionRecord], limit: Int = 5) -> [IntentionSuggestion] {
        let q = IntentionParser.fold(query.trimmingCharacters(in: .whitespaces))
        var seen = Set<String>()
        var starts: [IntentionSuggestion] = []
        var inside: [IntentionSuggestion] = []
        for record in records.reversed() where record.isFocus && !record.deleted {
            guard let text = record.label, !text.isEmpty else { continue }
            let folded = IntentionParser.fold(text)
            guard folded != q, seen.insert(folded).inserted else { continue }
            let suggestion = IntentionSuggestion(text: text, categoryID: record.categoryID)
            if q.isEmpty || folded.hasPrefix(q) || folded.contains(" " + q) {
                starts.append(suggestion)
            } else if folded.contains(q) {
                inside.append(suggestion)
            }
            if starts.count >= limit { break }
        }
        return Array((starts + inside).prefix(limit))
    }
}
