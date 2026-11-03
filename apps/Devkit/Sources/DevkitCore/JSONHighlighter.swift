import Foundation

/// Finds the parts of JSON text worth coloring. Ranges are UTF-16 (`NSRange`) so the UI
/// can apply them to an `NSTextStorage` directly. Tolerant: never throws on bad input.
public enum JSONHighlighter {
    public enum Kind: Sendable, Equatable {
        case key, string, number, keyword
    }

    public struct Span: Sendable, Equatable {
        public var kind: Kind
        public var range: NSRange
    }

    /// Above this many UTF-16 units, highlighting costs more than it helps.
    public static let limit = 1_000_000

    public static func spans(in text: String, limit: Int = limit) -> [Span] {
        let units = Array(text.utf16)
        guard units.count <= limit else { return [] }
        var spans: [Span] = []
        var index = 0
        let count = units.count
        func isDigitish(_ unit: UInt16) -> Bool {
            (unit >= 0x30 && unit <= 0x39) || unit == 0x2D || unit == 0x2B || unit == 0x2E || unit == 0x65 || unit == 0x45
        }
        while index < count {
            let unit = units[index]
            switch unit {
            case 0x22: // "
                let start = index
                index += 1
                while index < count, units[index] != 0x22 {
                    index += units[index] == 0x5C ? 2 : 1
                }
                index = min(index + 1, count)
                // A string followed by a colon is a key.
                var look = index
                while look < count, units[look] == 0x20 || units[look] == 0x09 || units[look] == 0x0A || units[look] == 0x0D { look += 1 }
                let kind: Kind = look < count && units[look] == 0x3A ? .key : .string
                spans.append(Span(kind: kind, range: NSRange(location: start, length: index - start)))
            case 0x2D, 0x30...0x39:
                let start = index
                while index < count, isDigitish(units[index]) { index += 1 }
                spans.append(Span(kind: .number, range: NSRange(location: start, length: index - start)))
            case 0x74, 0x66, 0x6E: // t f n
                let start = index
                while index < count, units[index] >= 0x61, units[index] <= 0x7A { index += 1 }
                let word = String(utf16CodeUnits: Array(units[start..<index]), count: index - start)
                if word == "true" || word == "false" || word == "null" {
                    spans.append(Span(kind: .keyword, range: NSRange(location: start, length: index - start)))
                }
            default:
                index += 1
            }
        }
        return spans
    }
}
