import Foundation

// MARK: - HTML entities

public enum HTMLEntities {
    public enum EncodeScope: String, CaseIterable, Sendable, Identifiable {
        /// & < > " ' only: what's needed to put text in HTML safely.
        case unsafeOnly
        /// Also non-ASCII characters, by name where HTML has one.
        case named
        /// Also non-ASCII characters, as numeric references.
        case numeric
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .unsafeOnly: "Only & < > \" '"
            case .named: "Non-ASCII by name"
            case .numeric: "Non-ASCII as numbers"
            }
        }
    }

    static let decodingTable: [String: String] = {
        var table: [String: String] = [:]
        for entry in HTMLEntityTable.decoding.split(separator: " ") {
            guard let equals = entry.firstIndex(of: "=") else { continue }
            let scalars = entry[entry.index(after: equals)...].split(separator: ".").compactMap { UInt32($0, radix: 16).flatMap(Unicode.Scalar.init) }
            table[String(entry[..<equals])] = String(String.UnicodeScalarView(scalars))
        }
        return table
    }()

    static let encodingTable: [Unicode.Scalar: String] = {
        var table: [Unicode.Scalar: String] = [:]
        for entry in HTMLEntityTable.encoding.split(separator: " ") {
            let parts = entry.split(separator: "=")
            guard parts.count == 2, let value = UInt32(parts[1], radix: 16), let scalar = Unicode.Scalar(value) else { continue }
            let name = String(parts[0])
            // Only names that decode back to the same character today (HTML 4's lang/rang changed).
            guard decodingTable[name] == String(scalar) else { continue }
            table[scalar] = name
        }
        return table
    }()

    public static func encode(_ text: String, scope: EncodeScope = .unsafeOnly) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default:
                if scalar.value > 0x7E, scope != .unsafeOnly {
                    if scope == .named, let name = encodingTable[scalar] {
                        out += "&\(name);"
                    } else {
                        out += "&#\(scalar.value);"
                    }
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }

    /// Decodes named (`&eacute;`), decimal (`&#233;`) and hex (`&#xE9;`) references. Unknown
    /// references are left as they are, like browsers do.
    public static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        out.reserveCapacity(text.utf8.count)
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            guard character == "&", let semicolon = text[index...].prefix(40).firstIndex(of: ";") else {
                out.append(character)
                index = text.index(after: index)
                continue
            }
            let body = text[text.index(after: index)..<semicolon]
            if let decoded = decodeReference(body) {
                out += decoded
                index = text.index(after: semicolon)
            } else {
                out.append(character)
                index = text.index(after: index)
            }
        }
        return out
    }

    static func decodeReference(_ body: Substring) -> String? {
        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let value: UInt32?
            if digits.hasPrefix("x") || digits.hasPrefix("X") {
                value = UInt32(digits.dropFirst(), radix: 16)
            } else {
                value = UInt32(digits, radix: 10)
            }
            guard let value else { return nil }
            // Per the HTML spec, 0 and surrogates become U+FFFD.
            guard value != 0, let scalar = Unicode.Scalar(value) else { return "\u{FFFD}" }
            return String(scalar)
        }
        return decodingTable[String(body)]
    }

    public static func containsReferences(_ text: String) -> Bool {
        text.range(of: "&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[A-Za-z][A-Za-z0-9]{1,31});", options: .regularExpression) != nil
    }
}

// MARK: - Backslash escapes

public enum BackslashEscapes {
    public struct UnescapeError: Error, Equatable, Sendable, CustomStringConvertible {
        public var message: String
        public var offset: Int
        public var description: String { "Character \(offset + 1): \(message)" }
    }

    /// Escapes text for a string literal in C-family languages (JavaScript, Swift, Java, JSON).
    public static func escape(_ text: String, escapeUnicode: Bool = false) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "'": out += "\\'"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\u{0B}": out += "\\v"
            case "\0": out += "\\0"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F || (escapeUnicode && scalar.value > 0x7E) {
                    if scalar.value > 0xFFFF {
                        // UTF-16 surrogate pair, which every language reads.
                        let v = scalar.value - 0x10000
                        out += String(format: "\\u%04X\\u%04X", 0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF))
                    } else {
                        out += String(format: "\\u%04X", scalar.value)
                    }
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }

    public static func unescape(_ text: String) throws -> String {
        let scalars = Array(text.unicodeScalars)
        var out = String.UnicodeScalarView()
        var index = 0
        var pendingHigh: UInt32?
        func hex(_ count: Int, at start: Int) throws -> UInt32 {
            guard start + count <= scalars.count else { throw UnescapeError(message: "Incomplete escape", offset: start - 2) }
            let digits = String(String.UnicodeScalarView(scalars[start..<start + count]))
            guard let value = UInt32(digits, radix: 16) else { throw UnescapeError(message: "“\(digits)” isn't hexadecimal", offset: start) }
            return value
        }
        func append(_ value: UInt32, at offset: Int) throws {
            if (0xD800...0xDBFF).contains(value) {
                pendingHigh = value
                return
            }
            if (0xDC00...0xDFFF).contains(value), let high = pendingHigh {
                out.append(Unicode.Scalar(0x10000 + ((high - 0xD800) << 10) + (value - 0xDC00))!)
                pendingHigh = nil
                return
            }
            guard let scalar = Unicode.Scalar(value) else { throw UnescapeError(message: "Not a Unicode character", offset: offset) }
            out.append(scalar)
        }
        while index < scalars.count {
            let scalar = scalars[index]
            if pendingHigh != nil, scalar != "\\" { throw UnescapeError(message: "Lone surrogate", offset: index) }
            guard scalar == "\\" else {
                out.append(scalar)
                index += 1
                continue
            }
            guard index + 1 < scalars.count else { throw UnescapeError(message: "Ends with a lone backslash", offset: index) }
            let code = scalars[index + 1]
            let start = index
            index += 2
            switch code {
            case "n": out.append("\n")
            case "r": out.append("\r")
            case "t": out.append("\t")
            case "b": out.append("\u{08}")
            case "f": out.append("\u{0C}")
            case "v": out.append("\u{0B}")
            case "0" where !(index < scalars.count && ("0"..."7").contains(scalars[index])): out.append("\0")
            case "\\", "\"", "'", "/", "`", "?", "$": out.append(code)
            case "\n": break // line continuation
            case "x":
                try append(try hex(2, at: index), at: start)
                index += 2
            case "u":
                if index < scalars.count, scalars[index] == "{" {
                    guard let close = scalars[index...].firstIndex(of: "}"), close - index <= 9 else {
                        throw UnescapeError(message: "\\u{…} isn't closed", offset: start)
                    }
                    try append(try hex(close - index - 1, at: index + 1), at: start)
                    index = close + 1
                } else {
                    try append(try hex(4, at: index), at: start)
                    index += 4
                }
                continue
            case "U":
                try append(try hex(8, at: index), at: start)
                index += 8
            default:
                if ("0"..."7").contains(code) {
                    // Octal: up to three digits.
                    var end = index
                    while end < scalars.count, end < index + 2, ("0"..."7").contains(scalars[end]) { end += 1 }
                    let digits = String(String.UnicodeScalarView(scalars[(index - 1)..<end]))
                    try append(UInt32(digits, radix: 8)!, at: start)
                    index = end
                } else {
                    throw UnescapeError(message: "Unknown escape \\\(Character(code))", offset: start)
                }
            }
            if pendingHigh != nil, code != "u" { throw UnescapeError(message: "Lone surrogate", offset: start) }
        }
        if pendingHigh != nil { throw UnescapeError(message: "Lone surrogate at the end", offset: scalars.count) }
        return String(out)
    }
}

// MARK: - Hex ⇄ text

public enum HexText {
    public enum Separator: String, CaseIterable, Sendable, Identifiable {
        case space, none, colon, prefixed
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .space: "48 65 6c"
            case .none: "48656c"
            case .colon: "48:65:6c"
            case .prefixed: "0x48 0x65"
            }
        }
    }

    public struct DecodeError: Error, Equatable, Sendable, CustomStringConvertible {
        public var message: String
        public var description: String { message }
    }

    /// Text → hex of its UTF-8 bytes.
    public static func encode(_ text: String, separator: Separator = .space, uppercase: Bool = false) -> String {
        let bytes = Array(text.utf8)
        let digits = bytes.map { String(format: uppercase ? "%02X" : "%02x", $0) }
        switch separator {
        case .space: return digits.joined(separator: " ")
        case .none: return digits.joined()
        case .colon: return digits.joined(separator: ":")
        case .prefixed: return digits.map { "0x" + $0 }.joined(separator: " ")
        }
    }

    /// Hex → bytes. Ignores whitespace, `0x`, `\x`, `:`, `-` and `,` between bytes.
    public static func bytes(from hex: String) throws -> Data {
        var cleaned = hex.replacingOccurrences(of: "0x", with: " ").replacingOccurrences(of: "0X", with: " ")
            .replacingOccurrences(of: "\\x", with: " ")
        cleaned.removeAll { $0.isWhitespace || $0 == ":" || $0 == "-" || $0 == "," }
        guard !cleaned.isEmpty else { return Data() }
        if let bad = cleaned.first(where: { !$0.isHexDigit }) {
            throw DecodeError(message: "“\(bad)” isn't a hex digit")
        }
        guard cleaned.count.isMultiple(of: 2) else { throw DecodeError(message: "Odd number of hex digits (\(cleaned.count)); each byte needs two") }
        var data = Data(capacity: cleaned.count / 2)
        var iterator = cleaned.makeIterator()
        while let high = iterator.next(), let low = iterator.next() {
            data.append(UInt8(String([high, low]), radix: 16)!)
        }
        return data
    }

    public static func decode(_ hex: String) throws -> DecodedBytes {
        DecodedBytes(data: try bytes(from: hex))
    }
}

// MARK: - SVG → CSS

public enum SVGToCSS {
    public enum Encoding: String, CaseIterable, Sendable, Identifiable {
        case url, base64
        public var id: String { rawValue }
        public var title: String { self == .url ? "URL-encoded" : "Base64" }
    }

    public struct SVGError: Error, Equatable, Sendable, CustomStringConvertible {
        public var description: String { "Paste SVG markup that starts with <svg (or an XML declaration)" }
    }

    /// A CSS `background-image` with the SVG as a data URI. URL encoding keeps it short and
    /// readable: quotes become single quotes, and only characters CSS or URLs need are escaped.
    public static func convert(_ svg: String, encoding: Encoding = .url) throws -> String {
        let trimmed = svg.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: "<svg", options: .caseInsensitive) != nil else { throw SVGError() }
        return "background-image: url(\"\(dataURI(trimmed, encoding: encoding))\");"
    }

    public static func dataURI(_ svg: String, encoding: Encoding) -> String {
        switch encoding {
        case .base64:
            return "data:image/svg+xml;base64," + Data(svg.utf8).base64EncodedString()
        case .url:
            // Collapse whitespace between tags and line breaks, then escape.
            var text = svg.replacingOccurrences(of: ">\\s+<", with: "><", options: .regularExpression)
            text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            text = text.replacingOccurrences(of: "\"", with: "'")
            var out = ""
            for scalar in text.unicodeScalars {
                switch scalar {
                case "%": out += "%25"
                case "#": out += "%23"
                case "<": out += "%3C"
                case ">": out += "%3E"
                case "{": out += "%7B"
                case "}": out += "%7D"
                case "\"": out += "%22"
                default:
                    if scalar.value > 0x7E || scalar.value < 0x20 {
                        out += String(scalar).utf8.map { String(format: "%%%02X", $0) }.joined()
                    } else {
                        out.unicodeScalars.append(scalar)
                    }
                }
            }
            return "data:image/svg+xml," + out
        }
    }
}
