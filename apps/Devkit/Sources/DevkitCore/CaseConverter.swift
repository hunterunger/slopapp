import Foundation

/// Converts identifiers and phrases between naming styles. Splits on separators and on
/// case changes, keeping acronyms together ("parseHTTPResponse" → parse, HTTP, Response).
public enum CaseConverter {
    public enum Style: String, CaseIterable, Sendable, Identifiable {
        case camel, pascal, snake, kebab, constant, dot, title, sentence, lower, upper

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .camel: "camelCase"
            case .pascal: "PascalCase"
            case .snake: "snake_case"
            case .kebab: "kebab-case"
            case .constant: "CONSTANT_CASE"
            case .dot: "dot.case"
            case .title: "Title Case"
            case .sentence: "Sentence case"
            case .lower: "lower case"
            case .upper: "UPPER CASE"
            }
        }
    }

    public static func words(_ text: String) -> [String] {
        var words: [String] = []
        var current: [Character] = []
        let characters = Array(text)
        func flush() {
            if !current.isEmpty { words.append(String(current)) }
            current = []
        }
        for (index, character) in characters.enumerated() {
            guard character.isLetter || character.isNumber else {
                flush()
                continue
            }
            if let previous = current.last {
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                if character.isUppercase, previous.isLowercase {
                    flush() // fooBar
                } else if character.isUppercase, previous.isUppercase, let next, next.isLowercase {
                    flush() // HTTPServer → HTTP | Server
                } else if character.isUppercase, previous.isNumber {
                    flush() // utf8String → utf8 | String
                }
            }
            current.append(character)
        }
        flush()
        return words
    }

    /// Converts each line separately so lists of identifiers work.
    public static func convert(_ text: String, to style: Style) -> String {
        text.components(separatedBy: "\n").map { convertLine($0, to: style) }.joined(separator: "\n")
    }

    static func convertLine(_ line: String, to style: Style) -> String {
        switch style {
        case .lower: return line.lowercased()
        case .upper: return line.uppercased()
        default: break
        }
        let words = words(line)
        guard !words.isEmpty else { return line }
        func capitalized(_ word: String) -> String {
            guard let first = word.first else { return word }
            return first.uppercased() + word.dropFirst().lowercased()
        }
        switch style {
        case .camel: return words[0].lowercased() + words.dropFirst().map(capitalized).joined()
        case .pascal: return words.map(capitalized).joined()
        case .snake: return words.map { $0.lowercased() }.joined(separator: "_")
        case .kebab: return words.map { $0.lowercased() }.joined(separator: "-")
        case .constant: return words.map { $0.uppercased() }.joined(separator: "_")
        case .dot: return words.map { $0.lowercased() }.joined(separator: ".")
        case .title: return words.map(capitalized).joined(separator: " ")
        case .sentence: return ([capitalized(words[0])] + words.dropFirst().map { $0.lowercased() }).joined(separator: " ")
        case .lower, .upper: return line
        }
    }
}
