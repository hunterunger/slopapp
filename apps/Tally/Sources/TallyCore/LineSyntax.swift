import Foundation

/// The note-like parts of a line: headers, comments, labels and quoted text. Used both to
/// find the calculation inside a line and to style the editor.
public struct LineSyntax: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case blank, header, comment, content }

    public var kind: Kind
    /// UTF-16 ranges within the line, for styling.
    public var label: NSRange?
    public var comment: NSRange?
    public var quotes: [NSRange]
    /// The calculation text with labels, quotes and comments removed.
    public var expression: String

    public static func parse(_ line: String) -> LineSyntax {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let whole = NSRange(location: 0, length: (line as NSString).length)
        if trimmed.isEmpty { return LineSyntax(kind: .blank, quotes: [], expression: "") }
        if trimmed.hasPrefix("#") { return LineSyntax(kind: .header, quotes: [], expression: "") }
        if trimmed.hasPrefix("//") { return LineSyntax(kind: .comment, comment: whole, quotes: [], expression: "") }

        let units = Array(line.utf16)
        var quotes: [NSRange] = []
        var comment: NSRange?
        var colon: Int?
        var quoteStart: Int?
        var closingQuote: UInt16 = 0
        var i = 0
        let straight: UInt16 = 0x22, open: UInt16 = 0x201C, close: UInt16 = 0x201D, slash: UInt16 = 0x2F, colonUnit: UInt16 = 0x3A
        while i < units.count {
            let u = units[i]
            if let start = quoteStart {
                if u == closingQuote {
                    quotes.append(NSRange(location: start, length: i - start + 1))
                    quoteStart = nil
                }
            } else if u == straight || u == open {
                quoteStart = i
                closingQuote = u == open ? close : straight
            } else if u == slash, i + 1 < units.count, units[i + 1] == slash {
                comment = NSRange(location: i, length: units.count - i)
                break
            } else if u == colonUnit, colon == nil {
                colon = i
            }
            i += 1
        }
        if let start = quoteStart, comment == nil {
            quotes.append(NSRange(location: start, length: units.count - start))
        }

        var label: NSRange?
        if let colon {
            // A label needs a letter before the colon, so "12:30" isn't read as one.
            let before = String(utf16CodeUnits: Array(units[0..<colon]), count: colon)
            if before.contains(where: \.isLetter), !quotes.contains(where: { NSLocationInRange(colon, $0) }) {
                label = NSRange(location: 0, length: colon + 1)
            }
        }

        // Build the expression: blank out label, quotes and comment.
        var keep = [Bool](repeating: true, count: units.count)
        for r in quotes + [label, comment].compactMap({ $0 }) {
            for k in r.location..<min(r.location + r.length, units.count) { keep[k] = false }
        }
        var out: [UInt16] = []
        out.reserveCapacity(units.count)
        for (k, u) in units.enumerated() { out.append(keep[k] ? u : 0x20) }
        let expression = String(utf16CodeUnits: out, count: out.count)
        return LineSyntax(kind: .content, label: label, comment: comment, quotes: quotes, expression: expression)
    }
}
