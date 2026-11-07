import Foundation

// MARK: - URL parser

public enum URLParser {
    public struct Parsed: Sendable, Equatable {
        public var parts: [(String, String)]
        public var query: [(String, String)]
        public var queryJSON: String

        public static func == (lhs: Parsed, rhs: Parsed) -> Bool {
            lhs.parts.map { [$0.0, $0.1] } == rhs.parts.map { [$0.0, $0.1] }
                && lhs.query.map { [$0.0, $0.1] } == rhs.query.map { [$0.0, $0.1] } && lhs.queryJSON == rhs.queryJSON
        }
    }

    public struct ParseError: Error, Equatable, Sendable, CustomStringConvertible {
        public var description: String { "Not a URL. Include the scheme (https://…), or paste just a query string (a=1&b=2)." }
    }

    /// Splits a URL (or a bare query string) into its parts and decoded query parameters.
    public static func parse(_ text: String) throws -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParseError() }
        // A bare query string: "?a=1&b=2" or "a=1&b=2".
        if !trimmed.contains("://"), !trimmed.hasPrefix("/"), trimmed.contains("="), !trimmed.contains(" ") {
            let query = trimmed.hasPrefix("?") ? String(trimmed.dropFirst()) : trimmed
            let items = queryItems(query)
            return Parsed(parts: [("Query", query)], query: items, queryJSON: json(items))
        }
        guard let components = URLComponents(string: trimmed) ?? URLComponents(string: trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed.union(["#", "%"])) ?? ""),
              components.scheme != nil || components.host != nil || trimmed.hasPrefix("/") else { throw ParseError() }
        var parts: [(String, String)] = []
        if let scheme = components.scheme { parts.append(("Scheme", scheme)) }
        if let user = components.user { parts.append(("User", user)) }
        if let password = components.password { parts.append(("Password", password)) }
        if let host = components.host { parts.append(("Host", host)) }
        if let port = components.port {
            parts.append(("Port", String(port)))
        } else if let scheme = components.scheme?.lowercased(), let port = defaultPorts[scheme] {
            parts.append(("Port", "\(port) (default)"))
        }
        parts.append(("Path", components.path.isEmpty ? "/" : components.path))
        let segments = components.path.split(separator: "/").map { $0.removingPercentEncoding ?? String($0) }
        if segments.count > 1 {
            for (index, segment) in segments.enumerated() { parts.append(("Path segment \(index + 1)", segment)) }
        }
        if let query = components.percentEncodedQuery { parts.append(("Query", query)) }
        if let fragment = components.fragment { parts.append(("Fragment", fragment)) }
        if let host = components.host {
            var origin = (components.scheme.map { $0 + "://" } ?? "") + host
            if let port = components.port { origin += ":\(port)" }
            parts.append(("Origin", origin))
        }
        let items = queryItems(components.percentEncodedQuery ?? "")
        return Parsed(parts: parts, query: items, queryJSON: json(items))
    }

    static let defaultPorts = ["http": 80, "https": 443, "ws": 80, "wss": 443, "ftp": 21, "ssh": 22]

    /// Form-style decoding: `+` is a space, `%XX` escapes are decoded.
    static func queryItems(_ query: String) -> [(String, String)] {
        query.split(separator: "&", omittingEmptySubsequences: true).map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let decode = { (text: Substring) in
                String(text).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(text)
            }
            return (decode(parts[0]), parts.count > 1 ? decode(parts[1]) : "")
        }
    }

    /// Query parameters as JSON; repeated keys (and `key[]`) become arrays.
    static func json(_ items: [(String, String)]) -> String {
        var pairs: [(String, JSONValue)] = []
        for (rawKey, value) in items {
            let key = rawKey.hasSuffix("[]") ? String(rawKey.dropLast(2)) : rawKey
            if let index = pairs.firstIndex(where: { $0.0 == key }) {
                if case let .array(existing) = pairs[index].1 {
                    pairs[index].1 = .array(existing + [.string(value)])
                } else {
                    pairs[index].1 = .array([pairs[index].1, .string(value)])
                }
            } else {
                pairs.append((key, rawKey.hasSuffix("[]") ? .array([.string(value)]) : .string(value)))
            }
        }
        return JSONTree.serialize(.object(pairs))
    }
}

// MARK: - String inspector

public enum StringInspector {
    public struct Stats: Sendable, Equatable {
        public var characters: Int
        public var unicodeScalars: Int
        public var utf16Units: Int
        public var utf8Bytes: Int
        public var words: Int
        public var lines: Int
        public var sentences: Int
        public var paragraphs: Int
        public var spaces: Int
        public var letters: Int
        public var digits: Int
        public var nonASCII: Int
    }

    public static func stats(_ text: String) -> Stats {
        var words = 0, sentences = 0, paragraphs = 0
        let range = text.startIndex..<text.endIndex
        text.enumerateSubstrings(in: range, options: [.byWords, .substringNotRequired]) { _, _, _, _ in words += 1 }
        text.enumerateSubstrings(in: range, options: [.bySentences]) { sentence, _, _, _ in
            if let sentence, !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { sentences += 1 }
        }
        text.enumerateSubstrings(in: range, options: [.byParagraphs]) { paragraph, _, _, _ in
            if let paragraph, !paragraph.trimmingCharacters(in: .whitespaces).isEmpty { paragraphs += 1 }
        }
        var spaces = 0, letters = 0, digits = 0, nonASCII = 0, newlines = 0
        for scalar in text.unicodeScalars {
            if scalar == "\n" { newlines += 1 }
            if scalar.properties.isWhitespace && scalar != "\n" && scalar != "\r" { spaces += 1 }
            if scalar.properties.isAlphabetic { letters += 1 }
            if ("0"..."9").contains(scalar) { digits += 1 }
            if !scalar.isASCII { nonASCII += 1 }
        }
        let lines = text.isEmpty ? 0 : newlines + (text.hasSuffix("\n") ? 0 : 1)
        return Stats(characters: text.count, unicodeScalars: text.unicodeScalars.count, utf16Units: text.utf16.count,
                     utf8Bytes: text.utf8.count, words: words, lines: lines, sentences: sentences,
                     paragraphs: paragraphs, spaces: spaces, letters: letters, digits: digits, nonASCII: nonASCII)
    }

    /// One row per Unicode scalar: what the character really is.
    public struct ScalarInfo: Sendable, Equatable, Identifiable {
        public var id: Int
        public var character: String
        public var codePoint: String
        public var name: String
        public var utf8: String
        public var category: String
    }

    public static func scalars(_ text: String, limit: Int = 2000) -> [ScalarInfo] {
        text.unicodeScalars.prefix(limit).enumerated().map { index, scalar in
            let shown: String
            switch scalar {
            case "\n": shown = "↵"
            case "\t": shown = "⇥"
            case " ": shown = "␠"
            default: shown = scalar.properties.generalCategory == .control || scalar.properties.isDefaultIgnorableCodePoint ? "·" : String(scalar)
            }
            return ScalarInfo(
                id: index, character: shown, codePoint: String(format: "U+%04X", scalar.value),
                name: scalar.properties.name ?? scalar.properties.nameAlias ?? controlName(scalar),
                utf8: String(scalar).utf8.map { String(format: "%02X", $0) }.joined(separator: " "),
                category: categoryName(scalar.properties.generalCategory)
            )
        }
    }

    static func controlName(_ scalar: Unicode.Scalar) -> String {
        switch scalar.value {
        case 0x0A: "LINE FEED"
        case 0x0D: "CARRIAGE RETURN"
        case 0x09: "CHARACTER TABULATION"
        case 0x00: "NULL"
        default: "<control>"
        }
    }

    static func categoryName(_ category: Unicode.GeneralCategory) -> String {
        switch category {
        case .uppercaseLetter: "Uppercase letter"
        case .lowercaseLetter: "Lowercase letter"
        case .titlecaseLetter, .modifierLetter, .otherLetter: "Letter"
        case .decimalNumber, .letterNumber, .otherNumber: "Number"
        case .spaceSeparator: "Space"
        case .lineSeparator, .paragraphSeparator: "Separator"
        case .control: "Control"
        case .format: "Format (invisible)"
        case .nonspacingMark, .spacingMark, .enclosingMark: "Combining mark"
        case .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol: "Symbol"
        case .surrogate, .privateUse, .unassigned: "Other"
        default: "Punctuation"
        }
    }
}

// MARK: - Line tools

public enum LineTools {
    public enum Sort: String, CaseIterable, Sendable, Identifiable {
        case none, ascending, descending, natural, length, reverse, shuffle
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .none: "Keep Order"
            case .ascending: "A → Z"
            case .descending: "Z → A"
            case .natural: "Natural (2 before 10)"
            case .length: "By Length"
            case .reverse: "Reverse"
            case .shuffle: "Shuffle"
            }
        }
    }

    public struct Options: Sendable, Equatable {
        public var sort: Sort
        public var removeDuplicates: Bool
        public var caseSensitive: Bool
        public var trimWhitespace: Bool
        public var removeEmpty: Bool
        public init(sort: Sort = .ascending, removeDuplicates: Bool = false, caseSensitive: Bool = true,
                    trimWhitespace: Bool = false, removeEmpty: Bool = false) {
            self.sort = sort
            self.removeDuplicates = removeDuplicates
            self.caseSensitive = caseSensitive
            self.trimWhitespace = trimWhitespace
            self.removeEmpty = removeEmpty
        }
    }

    public struct Result: Sendable, Equatable {
        public var text: String
        public var inputLines: Int
        public var outputLines: Int
        public var duplicatesRemoved: Int
    }

    public static func process<R: RandomNumberGenerator>(_ text: String, options: Options, random: inout R) -> Result {
        var lines = text.components(separatedBy: .newlines)
        // A trailing newline isn't an extra empty line.
        if text.hasSuffix("\n"), lines.last == "" { lines.removeLast() }
        let inputCount = lines.count
        if options.trimWhitespace { lines = lines.map { $0.trimmingCharacters(in: .whitespaces) } }
        if options.removeEmpty { lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        var removed = 0
        if options.removeDuplicates {
            var seen = Set<String>()
            lines = lines.filter { line in
                let key = options.caseSensitive ? line : line.lowercased()
                if seen.insert(key).inserted { return true }
                removed += 1
                return false
            }
        }
        let compareOptions: String.CompareOptions = options.caseSensitive ? [] : [.caseInsensitive]
        switch options.sort {
        case .none: break
        case .ascending: lines.sort { $0.compare($1, options: compareOptions) == .orderedAscending }
        case .descending: lines.sort { $0.compare($1, options: compareOptions) == .orderedDescending }
        case .natural: lines.sort { $0.compare($1, options: compareOptions.union(.numeric)) == .orderedAscending }
        case .length: lines = lines.enumerated().sorted { $0.element.count == $1.element.count ? $0.offset < $1.offset : $0.element.count < $1.element.count }.map(\.element)
        case .reverse: lines.reverse()
        case .shuffle: lines.shuffle(using: &random)
        }
        return Result(text: lines.joined(separator: "\n"), inputLines: inputCount, outputLines: lines.count, duplicatesRemoved: removed)
    }
}

// MARK: - Lorem ipsum

public enum LoremIpsum {
    public enum Unit: String, CaseIterable, Sendable, Identifiable {
        case paragraphs, sentences, words
        public var id: String { rawValue }
        public var title: String { rawValue.capitalized }
    }

    /// From Cicero's De finibus 1.10.32, the source of the classic placeholder text.
    static let words = """
    lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore \
    magna aliqua enim ad minim veniam quis nostrud exercitation ullamco laboris nisi aliquip ex ea commodo consequat \
    duis aute irure in reprehenderit voluptate velit esse cillum fugiat nulla pariatur excepteur sint occaecat \
    cupidatat non proident sunt culpa qui officia deserunt mollit anim id est laborum perspiciatis unde omnis iste \
    natus error voluptatem accusantium doloremque laudantium totam rem aperiam eaque ipsa quae ab illo inventore \
    veritatis quasi architecto beatae vitae dicta explicabo nemo ipsam quia voluptas aspernatur aut odit fugit \
    consequuntur magni dolores eos ratione sequi nesciunt neque porro quisquam dolorem adipisci numquam eius modi \
    tempora incidunt magnam aliquam quaerat
    """.split(separator: " ").map(String.init)

    public static let classicOpening = "Lorem ipsum dolor sit amet, consectetur adipiscing elit"

    public static func generate<R: RandomNumberGenerator>(count: Int, unit: Unit, startWithLorem: Bool = true, random: inout R) -> String {
        let count = max(1, min(count, 10_000))
        switch unit {
        case .words:
            var out: [String] = startWithLorem ? Array(classicOpening.lowercased().replacingOccurrences(of: ",", with: "").split(separator: " ").map(String.init).prefix(count)) : []
            while out.count < count { out.append(words.randomElement(using: &random)!) }
            return out.joined(separator: " ")
        case .sentences:
            var sentences: [String] = []
            for index in 0..<count { sentences.append(sentence(first: startWithLorem && index == 0, random: &random)) }
            return sentences.joined(separator: " ")
        case .paragraphs:
            var paragraphs: [String] = []
            for index in 0..<count {
                let length = Int.random(in: 4...7, using: &random)
                var sentences: [String] = []
                for sentenceIndex in 0..<length {
                    sentences.append(sentence(first: startWithLorem && index == 0 && sentenceIndex == 0, random: &random))
                }
                paragraphs.append(sentences.joined(separator: " "))
            }
            return paragraphs.joined(separator: "\n\n")
        }
    }

    static func sentence<R: RandomNumberGenerator>(first: Bool, random: inout R) -> String {
        if first { return classicOpening + "." }
        let length = Int.random(in: 6...14, using: &random)
        var parts: [String] = []
        for index in 0..<length {
            var word = words.randomElement(using: &random)!
            if index == 0 { word = word.prefix(1).uppercased() + word.dropFirst() }
            parts.append(word)
            if index > 2, index < length - 2, Int.random(in: 0..<8, using: &random) == 0 { parts[parts.count - 1] += "," }
        }
        return parts.joined(separator: " ") + "."
    }
}

// MARK: - Random strings

public enum RandomStrings {
    public struct Options: Sendable, Equatable {
        public var length: Int
        public var count: Int
        public var lowercase: Bool
        public var uppercase: Bool
        public var digits: Bool
        public var symbols: Bool
        /// Leave out look-alikes: 0 O o 1 l I.
        public var avoidAmbiguous: Bool
        /// Split into dash-separated groups of this size (0: no groups), e.g. license keys.
        public var groupSize: Int
        public init(length: Int = 24, count: Int = 1, lowercase: Bool = true, uppercase: Bool = true, digits: Bool = true,
                    symbols: Bool = false, avoidAmbiguous: Bool = false, groupSize: Int = 0) {
            self.length = length
            self.count = count
            self.lowercase = lowercase
            self.uppercase = uppercase
            self.digits = digits
            self.symbols = symbols
            self.avoidAmbiguous = avoidAmbiguous
            self.groupSize = groupSize
        }
    }

    public static let symbolSet = "!#$%&*+-=?@^_~"

    public static func alphabet(_ options: Options) -> [Character] {
        var set = ""
        if options.lowercase { set += "abcdefghijklmnopqrstuvwxyz" }
        if options.uppercase { set += "ABCDEFGHIJKLMNOPQRSTUVWXYZ" }
        if options.digits { set += "0123456789" }
        if options.symbols { set += symbolSet }
        if options.avoidAmbiguous { set.removeAll { "0Oo1lI".contains($0) } }
        return Array(set)
    }

    /// Uniform choices (no modulo bias) from a cryptographic generator in the app.
    public static func generate<R: RandomNumberGenerator>(_ options: Options, random: inout R) -> [String] {
        let alphabet = alphabet(options)
        guard !alphabet.isEmpty else { return [] }
        let length = max(1, min(options.length, 4096))
        return (0..<max(1, min(options.count, 1000))).map { _ in
            var characters = (0..<length).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &random)] }
            if options.groupSize > 0 {
                var grouped: [Character] = []
                for (index, character) in characters.enumerated() {
                    if index > 0, index.isMultiple(of: options.groupSize) { grouped.append("-") }
                    grouped.append(character)
                }
                characters = grouped
            }
            return String(characters)
        }
    }

    /// Bits of entropy per string.
    public static func entropyBits(_ options: Options) -> Double {
        let size = alphabet(options).count
        guard size > 1 else { return 0 }
        return Double(max(1, options.length)) * log2(Double(size))
    }
}
