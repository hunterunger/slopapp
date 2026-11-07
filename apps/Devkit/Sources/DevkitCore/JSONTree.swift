import Foundation

/// A JSON value that keeps object key order and numbers exactly as written, for the
/// converters (YAML, CSV). Parsing goes through `JSONFormatter` first so errors carry the
/// same line and column as the JSON tool.
public indirect enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    /// The number's original text, e.g. `12345678901234567890` or `1e3`.
    case number(String)
    case string(String)
    case array([JSONValue])
    case object([(String, JSONValue)])

    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): true
        case let (.bool(a), .bool(b)): a == b
        case let (.number(a), .number(b)): a == b
        case let (.string(a), .string(b)): a == b
        case let (.array(a), .array(b)): a == b
        case let (.object(a), .object(b)): a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        default: false
        }
    }

    /// The value for a key in an object (first match).
    public subscript(key: String) -> JSONValue? {
        if case let .object(pairs) = self { return pairs.first { $0.0 == key }?.1 }
        return nil
    }

    /// Scalars as plain text (strings unquoted); containers as compact JSON.
    public var plainText: String {
        switch self {
        case .null: ""
        case let .bool(value): value ? "true" : "false"
        case let .number(text): text
        case let .string(text): text
        case .array, .object: JSONTree.serialize(self, pretty: false)
        }
    }
}

public enum JSONTree {
    /// Parses strict JSON. Throws `JSONError` with a location.
    public static func parse(_ text: String) throws -> JSONValue {
        _ = try JSONFormatter.format(text, options: .init(style: .minified))
        var parser = TreeParser(bytes: Array(text.utf8))
        return try parser.parseDocument()
    }

    /// JSON text: pretty with two-space indent, or compact.
    public static func serialize(_ value: JSONValue, pretty: Bool = true, indent: String = "  ") -> String {
        var out = ""
        write(value, into: &out, pretty: pretty, indent: indent, depth: 0)
        return out
    }

    private static func write(_ value: JSONValue, into out: inout String, pretty: Bool, indent: String, depth: Int) {
        let newline = pretty ? "\n" : ""
        let pad = { (level: Int) in pretty ? String(repeating: indent, count: level) : "" }
        switch value {
        case .null: out += "null"
        case let .bool(flag): out += flag ? "true" : "false"
        case let .number(text): out += text
        case let .string(text): out += quote(text)
        case let .array(items):
            guard !items.isEmpty else { out += "[]"; return }
            out += "[" + newline
            for (index, item) in items.enumerated() {
                out += pad(depth + 1)
                write(item, into: &out, pretty: pretty, indent: indent, depth: depth + 1)
                out += (index < items.count - 1 ? "," : "") + newline
            }
            out += pad(depth) + "]"
        case let .object(pairs):
            guard !pairs.isEmpty else { out += "{}"; return }
            out += "{" + newline
            for (index, (key, item)) in pairs.enumerated() {
                out += pad(depth + 1) + quote(key) + (pretty ? ": " : ":")
                write(item, into: &out, pretty: pretty, indent: indent, depth: depth + 1)
                out += (index < pairs.count - 1 ? "," : "") + newline
            }
            out += pad(depth) + "}"
        }
    }

    /// A JSON string literal (RFC 8259 escapes; `/` and non-ASCII left as is).
    public static func quote(_ text: String) -> String {
        var out = "\""
        out.reserveCapacity(text.utf8.count + 2)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    /// True if `text` is a valid JSON number literal.
    public static func isNumberLiteral(_ text: String) -> Bool {
        var bytes = Array(text.utf8)[...]
        guard !bytes.isEmpty else { return false }
        if bytes.first == UInt8(ascii: "-") { bytes = bytes.dropFirst() }
        func digits(_ b: inout ArraySlice<UInt8>) -> Int {
            var n = 0
            while let c = b.first, c >= 0x30, c <= 0x39 { b = b.dropFirst(); n += 1 }
            return n
        }
        guard let first = bytes.first, first >= 0x30, first <= 0x39 else { return false }
        if first == UInt8(ascii: "0") { bytes = bytes.dropFirst() } else { _ = digits(&bytes) }
        if bytes.first == UInt8(ascii: ".") {
            bytes = bytes.dropFirst()
            guard digits(&bytes) > 0 else { return false }
        }
        if let e = bytes.first, e == UInt8(ascii: "e") || e == UInt8(ascii: "E") {
            bytes = bytes.dropFirst()
            if let sign = bytes.first, sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") { bytes = bytes.dropFirst() }
            guard digits(&bytes) > 0 else { return false }
        }
        return bytes.isEmpty
    }
}

/// Builds a tree from text already validated by `JSONFormatter`.
private struct TreeParser {
    let bytes: [UInt8]
    var index = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
        // Skip a UTF-8 byte order mark, as JSONFormatter does.
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { index = 3 }
    }

    mutating func parseDocument() throws -> JSONValue {
        skipWhitespace()
        return try parseValue(depth: 0)
    }

    mutating func skipWhitespace() {
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }

    mutating func parseValue(depth: Int) throws -> JSONValue {
        guard depth < 512 else { throw JSONError(message: "Nested too deeply", line: 1, column: 1, offset: index) }
        skipWhitespace()
        guard index < bytes.count else { throw JSONError(message: "Unexpected end", line: 1, column: 1, offset: index) }
        switch bytes[index] {
        case UInt8(ascii: "{"):
            index += 1
            var pairs: [(String, JSONValue)] = []
            skipWhitespace()
            if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(pairs) }
            while true {
                skipWhitespace()
                let key = try parseString()
                skipWhitespace()
                index += 1 // colon
                let value = try parseValue(depth: depth + 1)
                pairs.append((key, value))
                skipWhitespace()
                let next = bytes[index]
                index += 1
                if next == UInt8(ascii: "}") { return .object(pairs) }
            }
        case UInt8(ascii: "["):
            index += 1
            var items: [JSONValue] = []
            skipWhitespace()
            if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
            while true {
                items.append(try parseValue(depth: depth + 1))
                skipWhitespace()
                let next = bytes[index]
                index += 1
                if next == UInt8(ascii: "]") { return .array(items) }
            }
        case UInt8(ascii: "\""):
            return .string(try parseString())
        case UInt8(ascii: "t"): index += 4; return .bool(true)
        case UInt8(ascii: "f"): index += 5; return .bool(false)
        case UInt8(ascii: "n"): index += 4; return .null
        default:
            let start = index
            while index < bytes.count, "+-.0123456789eE".utf8.contains(bytes[index]) { index += 1 }
            return .number(String(decoding: bytes[start..<index], as: UTF8.self))
        }
    }

    mutating func parseString() throws -> String {
        index += 1 // opening quote
        var out = [UInt8]()
        var pendingHigh: UInt32?
        func append(_ scalar: UInt32) {
            out.append(contentsOf: Array(String(Unicode.Scalar(scalar).map(Character.init) ?? "\u{FFFD}").utf8))
        }
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") { index += 1; break }
            if byte == UInt8(ascii: "\\") {
                let escape = bytes[index + 1]
                index += 2
                if escape == UInt8(ascii: "u") {
                    let hex = String(decoding: bytes[index..<index + 4], as: UTF8.self)
                    index += 4
                    let unit = UInt32(hex, radix: 16) ?? 0xFFFD
                    if (0xD800...0xDBFF).contains(unit) {
                        pendingHigh = unit
                        continue
                    }
                    if (0xDC00...0xDFFF).contains(unit), let high = pendingHigh {
                        append(0x10000 + ((high - 0xD800) << 10) + (unit - 0xDC00))
                    } else {
                        append(unit)
                    }
                    pendingHigh = nil
                    continue
                }
                switch escape {
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                default: out.append(escape)
                }
                pendingHigh = nil
                continue
            }
            out.append(byte)
            index += 1
        }
        return String(decoding: out, as: UTF8.self)
    }
}
