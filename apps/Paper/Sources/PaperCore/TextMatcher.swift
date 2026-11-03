import Foundation

/// How a search term is matched against page text.
public struct MatchOptions: Sendable, Hashable {
    public var caseSensitive: Bool
    public var wholeWord: Bool

    public init(caseSensitive: Bool = false, wholeWord: Bool = false) {
        self.caseSensitive = caseSensitive
        self.wholeWord = wholeWord
    }
}

/// Finds a term in a string, returning UTF-16 ranges (what `PDFPage.selection(for:)` takes).
public enum TextMatcher {
    public static func ranges(of query: String, in text: String, options: MatchOptions = .init()) -> [NSRange] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, !text.isEmpty else { return [] }
        let haystack = text as NSString
        var compare: NSString.CompareOptions = [.widthInsensitive]
        if !options.caseSensitive { compare.insert(.caseInsensitive) }
        var results: [NSRange] = []
        var searchRange = NSRange(location: 0, length: haystack.length)
        while searchRange.length > 0 {
            let found = haystack.range(of: needle, options: compare, range: searchRange)
            guard found.location != NSNotFound, found.length > 0 else { break }
            if !options.wholeWord || isWholeWord(found, in: haystack) {
                results.append(found)
            }
            let next = found.location + max(found.length, 1)
            searchRange = NSRange(location: next, length: haystack.length - next)
        }
        return results
    }

    /// A match is a whole word when the characters around it aren't letters or digits.
    /// Scripts written without spaces (Chinese, Japanese, Thai...) have no word boundaries
    /// to check, so a match that starts or ends with one of their characters always counts.
    static func isWholeWord(_ range: NSRange, in text: NSString) -> Bool {
        let first = text.rangeOfComposedCharacterSequence(at: range.location)
        let last = text.rangeOfComposedCharacterSequence(at: range.location + range.length - 1)
        if range.location > 0, !isUnspacedScript(text.substring(with: first)) {
            let before = text.rangeOfComposedCharacterSequence(at: range.location - 1)
            if isWordCharacter(text.substring(with: before)) { return false }
        }
        let end = range.location + range.length
        if end < text.length, !isUnspacedScript(text.substring(with: last)) {
            let after = text.rangeOfComposedCharacterSequence(at: end)
            if isWordCharacter(text.substring(with: after)) { return false }
        }
        return true
    }

    static func isWordCharacter(_ s: String) -> Bool {
        guard let scalar = s.unicodeScalars.first else { return false }
        return CharacterSet.alphanumerics.contains(scalar)
    }

    static func isUnspacedScript(_ s: String) -> Bool {
        guard let v = s.unicodeScalars.first?.value else { return false }
        switch v {
        case 0x3040...0x30FF, // Hiragana, Katakana
             0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F, // CJK
             0x0E00...0x0E7F, // Thai
             0x0E80...0x0EFF, // Lao
             0x1780...0x17FF: // Khmer
            return true
        default:
            return false
        }
    }

    /// One line of context around a match, with whitespace collapsed: "…number 4417 belongs…".
    /// Less text before the match than after, so the match shows in a two-line row.
    public static func context(for range: NSRange, in text: String, radius: Int = 32) -> String {
        context(for: range, in: text, before: max(radius / 2, 8), after: radius + radius / 2)
    }

    public static func context(for range: NSRange, in text: String, before: Int, after: Int) -> String {
        let ns = text as NSString
        let start = max(0, range.location - before)
        let end = min(ns.length, range.location + range.length + after)
        let safe = ns.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: end - start))
        var snippet = ns.substring(with: safe)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if safe.location > 0 { snippet = "…" + snippet }
        if safe.location + safe.length < ns.length { snippet += "…" }
        return snippet
    }

    /// Counts non-overlapping occurrences (case-sensitive, exact). Used by the redaction verifier.
    public static func count(of needle: String, in text: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        return ranges(of: needle, in: text, options: MatchOptions(caseSensitive: true)).count
    }
}
