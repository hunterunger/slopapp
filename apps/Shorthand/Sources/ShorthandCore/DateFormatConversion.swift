import Foundation

/// Turns other apps' date codes into a Unicode date pattern for `{date:format=…}`.
public enum DateFormatConversion {
    /// strftime (espanso, and the base of TextExpander's codes) → Unicode pattern pieces.
    /// `-`/`1` flags drop leading zeros.
    static func pattern(forCode code: Character, unpadded: Bool) -> String? {
        switch code {
        case "Y": return "yyyy"
        case "y": return "yy"
        case "C": return nil
        case "m": return unpadded ? "M" : "MM"
        case "B": return "MMMM"
        case "b", "h": return "MMM"
        case "d": return unpadded ? "d" : "dd"
        case "e": return "d"
        case "j": return unpadded ? "D" : "DDD"
        case "A": return "EEEE"
        case "a": return "EEE"
        case "u": return "e"
        case "H": return unpadded ? "H" : "HH"
        case "k": return "H"
        case "I": return unpadded ? "h" : "hh"
        case "l": return "h"
        case "M": return unpadded ? "m" : "mm"
        case "S": return unpadded ? "s" : "ss"
        case "p", "P": return "a"
        case "Z": return "zzz"
        case "z": return "ZZZ"
        case "F": return "yyyy-MM-dd"
        case "T": return "HH:mm:ss"
        case "R": return "HH:mm"
        case "D": return "MM/dd/yy"
        case "V": return "ww"
        case "G": return "YYYY"
        default: return nil
        }
    }

    /// A strftime format (`%d %B %Y`) as a Unicode pattern (`dd MMMM yyyy`). Literal letters
    /// are quoted. Codes with no equivalent are listed in `unknown` and left out. Braces
    /// can't appear inside a placeholder, so they're dropped too.
    public static func pattern(fromStrftime format: String) -> (pattern: String, unknown: [String]) {
        var result = ""
        var unknown: [String] = []
        var literal = ""
        func flushLiteral() {
            guard !literal.isEmpty else { return }
            result += quote(literal)
            literal = ""
        }
        let characters = Array(format)
        var i = 0
        while i < characters.count {
            let c = characters[i]
            if c == "%", i + 1 < characters.count {
                var j = i + 1
                var unpadded = false
                if characters[j] == "-" || characters[j] == "_" || characters[j] == "0" || characters[j] == "^" || characters[j] == "#" {
                    unpadded = characters[j] == "-"
                    j += 1
                }
                guard j < characters.count else { literal.append(c); i += 1; continue }
                let code = characters[j]
                if code == "%" {
                    literal.append("%")
                } else if code == "n" {
                    literal.append(" ")
                } else if code == "t" {
                    literal.append(" ")
                } else if let piece = pattern(forCode: code, unpadded: unpadded) {
                    flushLiteral()
                    result += piece
                } else {
                    unknown.append("%" + String(code))
                }
                i = j + 1
                continue
            }
            if c == "{" || c == "}" || c == "\n" {
                unknown.append(String(c))
            } else {
                literal.append(c)
            }
            i += 1
        }
        flushLiteral()
        return (result, unknown)
    }

    /// Literal text in a Unicode pattern: letters (and quotes) need quoting.
    public static func quote(_ literal: String) -> String {
        guard literal.contains(where: { $0.isLetter || $0 == "'" }) else { return literal }
        if literal == "'" { return "''" }
        return "'" + literal.replacingOccurrences(of: "'", with: "''") + "'"
    }
}
