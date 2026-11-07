import Foundation

/// The rule-based passes over a transcript. Pure functions, so they're cheap to test.
public enum TextCleanup {
    /// Filler words removed when "Remove filler words" is on. Kept short on purpose, so
    /// words that carry meaning ("like", "so") are never touched.
    public static let fillerWords = [
        "um", "umm", "uh", "uhh", "uhm", "er", "err", "erm", "ah", "ahh", "eh", "hmm",
    ]

    /// Removes filler words (whole words, any case) with the commas around them, and tidies
    /// what's left. "I was, uh, thinking" keeps one comma (it may separate list items);
    /// "Um, so we" becomes "So we".
    public static func removeFillers(_ text: String, words: [String] = fillerWords) -> String {
        let alternation = words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        guard !alternation.isEmpty,
              let regex = try? NSRegularExpression(pattern: "(?i)(\\s*,)?[ \\t]*\\b(?:\(alternation))\\b([ \\t]*,)?")
        else { return text }
        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return text }

        var output = ""
        var cursor = 0
        var capitalizeNext = false
        for match in matches {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let hasLead = match.range(at: 1).location != NSNotFound
            let hasTrail = match.range(at: 2).location != NSNotFound
            let filler = source.substring(with: match.range).trimmingCharacters(in: CharacterSet(charactersIn: " \t,"))
            if filler.first?.isUppercase == true, !hasLead { capitalizeNext = true }
            output += (hasLead && hasTrail) ? ", " : " "
            cursor = match.range.location + match.range.length
            if capitalizeNext {
                // Uppercase the first letter that follows, if it's right after this filler.
                let rest = source.substring(from: cursor)
                if let index = rest.firstIndex(where: { !$0.isWhitespace }), rest[index].isLetter {
                    let prefix = rest[..<index]
                    output += prefix + String(rest[index]).uppercased()
                    cursor += (String(prefix) + String(rest[index])).utf16.count
                }
                capitalizeNext = false
            }
        }
        output += source.substring(from: cursor)
        return tidy(output)
    }

    /// Cleans up the spaces and punctuation a removal leaves behind, and capitalizes the start.
    public static func tidy(_ input: String) -> String {
        var t = input
        t = t.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "[ \\t]+([,.!?;:])", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: ",(\\s*,)+", with: ",", options: .regularExpression)
        t = t.replacingOccurrences(of: ",([.!?])", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "^[\\s,.;:]+", with: "", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = t.first, first.isLowercase {
            t.replaceSubrange(t.startIndex...t.startIndex, with: String(first).uppercased())
        }
        return t
    }

    /// Applies find/replace rules: whole words, case-insensitive, in order.
    public static func applyReplacements(_ text: String, _ rules: [Replacement]) -> String {
        var t = text
        for rule in rules {
            let from = rule.from.trimmingCharacters(in: .whitespaces)
            guard !from.isEmpty else { continue }
            // \b only works next to word characters; for "C#" or ".NET" fall back to spaces/edges.
            let escaped = NSRegularExpression.escapedPattern(for: from)
            let lead = from.first.map { $0.isLetter || $0.isNumber || $0 == "_" } == true ? "\\b" : "(?<![\\w])"
            let trail = from.last.map { $0.isLetter || $0.isNumber || $0 == "_" } == true ? "\\b" : "(?![\\w])"
            guard let regex = try? NSRegularExpression(pattern: "(?i)\(lead)\(escaped)\(trail)") else { continue }
            let range = NSRange(t.startIndex..., in: t)
            t = regex.stringByReplacingMatches(in: t, range: range,
                                               withTemplate: NSRegularExpression.escapedTemplate(for: rule.to))
        }
        return t
    }

    /// Lowercases the first letter and drops trailing periods and whitespace, for text that
    /// continues a sentence. Leaves "I" and acronyms ("NASA") alone.
    public static func applyLowercaseStyle(_ text: String) -> String {
        var t = text
        while let last = t.last, last == "." || last.isWhitespace {
            t.removeLast()
        }
        guard let first = t.first, first.isUppercase else { return t }
        let firstWord = t.prefix { $0.isLetter }
        let isAcronym = firstWord.count > 1 && firstWord.allSatisfy(\.isUppercase)
        let isPronounI = firstWord == "I"
        guard !isAcronym, !isPronounI else { return t }
        t.replaceSubrange(t.startIndex...t.startIndex, with: String(first).lowercased())
        return t
    }

    /// The transcript, trimmed, or nil when it holds no speech. On silence the models return
    /// blank text or annotations like "[BLANK_AUDIO]", "(silence)" or "[MUSIC]".
    public static func meaningfulText(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.replacingOccurrences(
            of: "\\[[^\\]]*\\]|\\([^\\)]*\\)|<\\|[^|]*\\|>|\\*[^*]*\\*", with: "", options: .regularExpression)
        guard stripped.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        // Keep parentheticals the person said, but drop whole-transcript annotations around speech.
        let withoutLeadingTags = trimmed.replacingOccurrences(
            of: "^(\\s*(\\[[A-Z_ ]+\\]|<\\|[^|]*\\|>))+\\s*", with: "", options: .regularExpression)
        return withoutLeadingTags.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The custom vocabulary: a free-form list, one term per line (commas also separate).
public enum Vocabulary {
    static func split(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Terms for the AI: the vocabulary plus every replacement's target, deduplicated
    /// (first spelling wins), in the order written.
    public static func terms(vocabulary: String, replacements: [Replacement]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for term in split(vocabulary) + replacements.map({ $0.to.trimmingCharacters(in: .whitespaces) })
        where !term.isEmpty && seen.insert(term.lowercased()).inserted {
            result.append(term)
        }
        return result
    }

    /// The vocabulary with `word` added on its own line, or nil if it's blank or already there.
    public static func adding(_ word: String, to vocabulary: String) -> String? {
        let word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return nil }
        guard !split(vocabulary).contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) else { return nil }
        let trimmed = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? word : trimmed + "\n" + word
    }
}
