import Foundation

/// Colours for the parts of a line, the way the editor shows them: numbers, operator words
/// (`in`, `of`, `times`), units and currencies, variables, labels, comments and headers.
public enum Highlighter {
    public enum Kind: Sendable, Equatable {
        case number, keyword, unit, variable, label, comment, header
    }

    public struct Span: Sendable, Equatable {
        public var range: NSRange
        public var kind: Kind
    }

    /// Spans within `line` (UTF-16 ranges). `variables` are the lower-cased names defined in
    /// the sheet; other unknown words stay plain text.
    public static func spans(_ line: String, variables: Set<String>) -> [Span] {
        let syntax = LineSyntax.parse(line)
        let length = (line as NSString).length
        switch syntax.kind {
        case .blank: return []
        case .header: return [Span(range: NSRange(location: 0, length: length), kind: .header)]
        case .comment: return [Span(range: NSRange(location: 0, length: length), kind: .comment)]
        case .content: break
        }
        var spans: [Span] = []
        if let label = syntax.label { spans.append(Span(range: label, kind: .label)) }
        for q in syntax.quotes { spans.append(Span(range: q, kind: .comment)) }
        if let c = syntax.comment { spans.append(Span(range: c, kind: .comment)) }

        let units = Array(syntax.expression.utf16)
        // Conversational words ("and", "is", "with") are only operators in lines with numbers.
        let hasDigit = units.contains { $0 >= 0x30 && $0 <= 0x39 }
        var i = 0
        // The word before, for places: "in Lisbon", "to New York".
        var previousWord = ""
        func isLetter(_ u: UInt16) -> Bool {
            guard let scalar = Unicode.Scalar(u) else { return u >= 0xD800 } // surrogate halves: letters
            return CharacterSet.letters.contains(scalar) || u == 0x5F || u == 0xB0 || u == 0xB5 || u == 0x3C0
        }
        func isDigit(_ u: UInt16) -> Bool { u >= 0x30 && u <= 0x39 }
        while i < units.count {
            let u = units[i]
            if isDigit(u) || (u == 0x2E && i + 1 < units.count && isDigit(units[i + 1])) {
                let start = i
                // Digits, separators and glued hex/exponent/scale letters: "1,250.5", "0xFF", "3k".
                while i < units.count, isDigit(units[i]) || units[i] == 0x2E || units[i] == 0x2C || units[i] == 0x3A
                    || (i > start && isHexOrScale(units, i, start: start)) {
                    i += 1
                }
                // Don't swallow a trailing comma or colon.
                while i > start + 1, units[i - 1] == 0x2C || units[i - 1] == 0x3A || units[i - 1] == 0x2E { i -= 1 }
                spans.append(Span(range: NSRange(location: start, length: i - start), kind: .number))
            } else if isLetter(u) {
                let start = i
                while i < units.count, isLetter(units[i]) || isDigit(units[i]) || units[i] == 0xB2 || units[i] == 0xB3 {
                    i += 1
                }
                let word = String(utf16CodeUnits: Array(units[start..<i]), count: i - start)
                if !hasDigit, Words.softOperators.contains(word.lowercased()) || word.lowercased() == "a" {
                    // prose: leave it alone
                } else if let kind = classify(word, variables: variables) {
                    spans.append(Span(range: NSRange(location: start, length: i - start), kind: kind))
                } else if Words.conversions.contains(previousWord) || previousWord == "time",
                          let (zone, length) = Zones.lookup(Self.words(from: units, at: start)) {
                    // A place, possibly several words ("New York").
                    var end = start
                    for _ in 0..<length {
                        while end < units.count, units[end] == 0x20 { end += 1 }
                        while end < units.count, isLetter(units[end]) { end += 1 }
                    }
                    _ = zone
                    spans.append(Span(range: NSRange(location: start, length: end - start), kind: .unit))
                    i = end
                }
                previousWord = word.lowercased()
            } else if u == 0x24 || Currencies.symbols[String(utf16CodeUnits: [u], count: 1)] != nil {
                spans.append(Span(range: NSRange(location: i, length: 1), kind: .unit))
                i += 1
            } else {
                i += 1
            }
        }
        return spans
    }

    /// Up to four space-separated words starting at `start`, for place lookups.
    private static func words(from units: [UInt16], at start: Int) -> [String] {
        let rest = String(utf16CodeUnits: Array(units[start...]), count: units.count - start)
        return rest.split(separator: " ", maxSplits: Zones.maxWords, omittingEmptySubsequences: true)
            .prefix(Zones.maxWords).map { String($0.prefix { $0.isLetter }) }
    }

    /// Letters that belong to a number: `0x` digits, `e` exponents, `k`/`M` scales.
    private static func isHexOrScale(_ units: [UInt16], _ i: Int, start: Int) -> Bool {
        let u = units[i]
        let isHexPrefixed = units.count > start + 1 && units[start] == 0x30 && [0x78, 0x62, 0x6F].contains(units[start + 1])
        if isHexPrefixed {
            if i == start + 1 { return true }
            return (u >= 0x61 && u <= 0x66) || (u >= 0x41 && u <= 0x46)
        }
        let next = i + 1 < units.count ? units[i + 1] : 0x20
        let nextIsLetter = (next >= 0x41 && next <= 0x5A) || (next >= 0x61 && next <= 0x7A)
        if (u == 0x6B || u == 0x4D), !nextIsLetter { return true } // k, M
        return false
    }

    static func classify(_ word: String, variables: Set<String>) -> Kind? {
        let lower = word.lowercased()
        if Words.conversions.contains(lower) || Words.operators.contains(lower) || Words.functions[lower] != nil
            || Words.aggregates[lower] != nil || Words.styles[lower] != nil || Words.dateWords[lower] != nil
            || lower == "x" && !variables.contains(lower) || lower == "pm" || lower == "am" || lower == "a"
            || lower == "time" || lower == "root" {
            return .keyword
        }
        if variables.contains(lower) { return .variable }
        if Words.constant(word) != nil || Words.scales[lower] != nil { return .keyword }
        if Units.lookup(word) != nil || Units.rateAlias(word) != nil || Units.isCompoundPrefix(word)
            || Currencies.lookup(word) != nil || Zones.abbreviations[word] != nil || DateMath.months[lower] != nil {
            return .unit
        }
        return nil
    }
}

/// Suggestions for the word being typed: the sheet's variables first, then built-in words.
public enum Completions {
    /// Built-in words worth completing (long enough to save typing).
    static let builtIns: [String] = {
        var words = Set<String>()
        for name in Units.names.keys where name.count >= 4 && !name.contains(" ") { words.insert(name) }
        for name in Words.functions.keys where name.count >= 3 { words.insert(name) }
        for word in ["average", "total", "previous", "today", "tomorrow", "yesterday", "percent", "hexadecimal",
                     "binary", "octal", "scientific", "thousand", "million", "billion", "midnight", "noon"] {
            words.insert(word)
        }
        for (_, zone) in Zones.places where zone.label.count >= 4 && !zone.label.contains(" ") { words.insert(zone.label) }
        return words.sorted()
    }()

    /// Completions for `prefix` (case-insensitive), best first. Exact matches are left out.
    public static func candidates(for prefix: String, variables: [String], includeBuiltIns: Bool = true, limit: Int = 12) -> [String] {
        guard !prefix.isEmpty else { return [] }
        let lower = prefix.lowercased()
        var seen = Set<String>()
        var out: [String] = []
        for name in variables where name.lowercased().hasPrefix(lower) && name != prefix && seen.insert(name).inserted {
            out.append(name)
        }
        if includeBuiltIns {
            for word in builtIns where word.lowercased().hasPrefix(lower) && word.lowercased() != lower && seen.insert(word).inserted {
                out.append(word)
                if out.count >= limit { break }
            }
        }
        return Array(out.prefix(limit))
    }

    /// Should typing have opened suggestions? Only for a variable the sheet defines, after two
    /// letters of a word, and never inside a comment or header.
    public static func shouldSuggest(line: String, cursor: Int, variables: [String]) -> String? {
        let ns = line as NSString
        guard cursor <= ns.length, cursor >= 2 else { return nil }
        let syntax = LineSyntax.parse(line)
        guard syntax.kind == .content else { return nil }
        if let c = syntax.comment, cursor > c.location { return nil }
        if syntax.quotes.contains(where: { cursor > $0.location && cursor <= NSMaxRange($0) }) { return nil }
        var start = cursor
        while start > 0 {
            let ch = ns.character(at: start - 1)
            guard let scalar = Unicode.Scalar(ch), CharacterSet.alphanumerics.contains(scalar) || ch == 0x5F else { break }
            start -= 1
        }
        let word = ns.substring(with: NSRange(location: start, length: cursor - start))
        guard word.count >= 2, word.first?.isLetter == true else { return nil }
        // The next character must end the word (don't pop up in the middle of one).
        if cursor < ns.length, let scalar = Unicode.Scalar(ns.character(at: cursor)), CharacterSet.alphanumerics.contains(scalar) {
            return nil
        }
        let lower = word.lowercased()
        return variables.contains { $0.lowercased().hasPrefix(lower) && $0 != word } ? word : nil
    }

    /// Words worth suggesting inline right after a number or `in`/`to`: units, currencies
    /// and places, shortest first.
    static let unitWords: [String] = {
        var words = Set<String>()
        for name in Units.names.keys where !name.contains(" ") { words.insert(name) }
        for name in Currencies.names.keys { words.insert(name) }
        for (_, zone) in Zones.places where !zone.label.contains(" ") { words.insert(zone.label) }
        return words.sorted { $0.count != $1.count ? $0.count < $1.count : $0 < $1 }
    }()

    /// The rest of the word being typed, shown greyed after the insertion point and accepted
    /// with Tab: a variable from the sheet (after two letters), or a unit, currency or place
    /// right after a number or a conversion word (after three letters). Nil inside comments,
    /// quotes and headers, mid-word, or when the word is already complete.
    public static func inline(line: String, cursor: Int, variables: [String]) -> String? {
        let ns = line as NSString
        guard cursor >= 2, cursor <= ns.length else { return nil }
        let syntax = LineSyntax.parse(line)
        guard syntax.kind == .content else { return nil }
        if let c = syntax.comment, cursor > c.location { return nil }
        if syntax.quotes.contains(where: { cursor > $0.location && cursor <= NSMaxRange($0) }) { return nil }
        if let label = syntax.label, cursor <= NSMaxRange(label) { return nil }
        if cursor < ns.length, let next = Unicode.Scalar(ns.character(at: cursor)), CharacterSet.alphanumerics.contains(next) {
            return nil
        }
        var start = cursor
        while start > 0 {
            let ch = ns.character(at: start - 1)
            guard let scalar = Unicode.Scalar(ch), CharacterSet.alphanumerics.contains(scalar) || ch == 0x5F else { break }
            start -= 1
        }
        let word = ns.substring(with: NSRange(location: start, length: cursor - start))
        guard word.count >= 2, word.first?.isLetter == true else { return nil }
        let lower = word.lowercased()
        if let name = variables.first(where: { $0.lowercased().hasPrefix(lower) && $0.count > word.count }),
           !variables.contains(where: { $0.lowercased() == lower }) {
            return String(name.dropFirst(word.count))
        }
        guard word.count >= 3, Units.lookup(word) == nil, Currencies.lookup(word) == nil else { return nil }
        // Only where a unit can go: after a number, or after in/to/as/into.
        let before = ns.substring(to: start).trimmingCharacters(in: .whitespaces)
        let lastWord = before.split(whereSeparator: { $0 == " " }).last.map { $0.lowercased() } ?? ""
        guard before.last?.isNumber == true || Words.conversions.contains(lastWord) else { return nil }
        guard let match = unitWords.first(where: { $0.lowercased().hasPrefix(lower) && $0.count > word.count }) else { return nil }
        return String(match.dropFirst(word.count))
    }
}
