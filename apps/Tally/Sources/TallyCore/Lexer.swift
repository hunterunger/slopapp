import Foundation

enum Token: Equatable {
    case number(Decimal)
    case word(String)
    /// One of `+ - * / ^ % ! ( ) = ,` (Unicode forms are normalized: × → *, ÷ → /, − → -).
    case symbol(Character)
    /// `$ € £ ¥ ₹ ...`
    case currencySymbol(String)
}

/// Splits one line (already stripped of comments, quotes and labels) into tokens.
/// Throws `NotACalculation` on characters that can't be part of a calculation.
struct Lexer {
    private let chars: [Character]
    private var i = 0
    private(set) var tokens: [Token] = []

    static func tokenize(_ text: Substring) throws -> [Token] {
        var lexer = Lexer(chars: Array(text))
        try lexer.run()
        return lexer.tokens
    }

    private init(chars: [Character]) {
        self.chars = chars
    }

    private func peek(_ offset: Int = 0) -> Character? {
        let j = i + offset
        return j < chars.count ? chars[j] : nil
    }

    private mutating func run() throws {
        while let c = peek() {
            if c.isWhitespace {
                i += 1
            } else if c.isASCIIDigit || (c == "." && peek(1)?.isASCIIDigit == true) {
                try lexNumber()
            } else if Self.isWordStart(c) {
                lexWord()
            } else if let s = Self.symbol(c) {
                if c == "*", peek(1) == "*" {
                    tokens.append(.symbol("^"))
                    i += 2
                } else {
                    tokens.append(.symbol(s))
                    i += 1
                }
            } else if c == "$" || Currencies.symbols[String(c)] != nil {
                tokens.append(.currencySymbol(String(c)))
                i += 1
            } else {
                throw NotACalculation()
            }
        }
    }

    static func symbol(_ c: Character) -> Character? {
        switch c {
        case "+", "-", "*", "/", "^", "%", "!", "(", ")", "=", ",": c
        case "×", "·", "⋅": "*"
        case "÷", "∕": "/"
        case "−", "–": "-"
        default: nil
        }
    }

    static func isWordStart(_ c: Character) -> Bool {
        c.isLetter || c == "_" || c == "°" || c == "µ" || c == "π"
    }

    private static func isWordChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "²" || c == "³" || c == "°"
    }

    private mutating func lexWord() {
        let start = i
        // "°C" / "°F" read as one word; "30°" leaves "°" alone.
        if chars[i] == "°" {
            i += 1
            if let n = peek(), n == "C" || n == "F", !(peek(1).map(Self.isWordChar) ?? false) { i += 1 }
            tokens.append(.word(String(chars[start..<i])))
            return
        }
        // "3x4": an x glued between numbers is "times".
        if chars[i] == "x", peek(1)?.isASCIIDigit == true, case .number = tokens.last {
            i += 1
            tokens.append(.word("x"))
            return
        }
        while let c = peek(), Self.isWordChar(c), !(c == "°" && i > start) {
            i += 1
        }
        tokens.append(.word(String(chars[start..<i])))
    }

    private mutating func lexNumber() throws {
        // 0x / 0b / 0o prefixes.
        if chars[i] == "0", let p = peek(1), "xbo".contains(p), let d = peek(2), d.isHexDigit {
            let radix = p == "x" ? 16 : (p == "b" ? 2 : 8)
            var j = i + 2
            var digits = ""
            while j < chars.count, chars[j].isHexDigit || chars[j] == "_" {
                if chars[j] != "_" { digits.append(chars[j]) }
                j += 1
            }
            if j < chars.count, chars[j].isLetter { throw NotACalculation() }
            guard let n = UInt64(digits, radix: radix) else { throw NotACalculation() }
            i = j
            tokens.append(.number(Decimal(n)))
            return
        }
        var text = ""
        var integerDigits = 0
        while let c = peek() {
            if c.isASCIIDigit {
                text.append(c)
                integerDigits += 1
                i += 1
            } else if c == ",", integerDigits > 0, isGroup(at: i + 1) {
                // A comma followed by exactly three digits is a thousands separator.
                i += 1
            } else {
                break
            }
        }
        if peek() == ".", peek(1)?.isASCIIDigit == true || text.isEmpty == false {
            text.append(".")
            i += 1
            while let c = peek(), c.isASCIIDigit {
                text.append(c)
                i += 1
            }
        }
        if let e = peek(), e == "e" || e == "E" {
            var j = i + 1
            var exp = "e"
            if let s = chars[safe: j], s == "+" || s == "-" {
                exp.append(s)
                j += 1
            }
            if chars[safe: j]?.isASCIIDigit == true {
                while let c = chars[safe: j], c.isASCIIDigit {
                    exp.append(c)
                    j += 1
                }
                if !(chars[safe: j].map(Self.isWordChar) ?? false) {
                    text += exp
                    i = j
                }
            }
        }
        if text.hasSuffix(".") { text.removeLast() }
        if text.hasPrefix(".") { text = "0" + text }
        guard var value = Decimal(string: text, locale: DecimalMath.posix), !value.isNaN else { throw NotACalculation() }
        // Glued scales: 3k, 2.5M.
        if let s = peek(), s == "k" || s == "M", !(peek(1).map(Self.isWordChar) ?? false) {
            value *= s == "k" ? 1000 : 1_000_000
            i += 1
        }
        tokens.append(.number(value))
    }

    private func isGroup(at j: Int) -> Bool {
        for k in 0..<3 {
            guard chars[safe: j + k]?.isASCIIDigit == true else { return false }
        }
        return chars[safe: j + 3]?.isASCIIDigit != true
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        index >= 0 && index < count ? self[index] : nil
    }
}
