import Foundation

/// Percent-encoding (RFC 3986). Two scopes, like JavaScript's two functions:
/// a component (query value, path segment) encodes everything but the unreserved set;
/// a whole URL keeps the characters that give a URL its structure.
public enum URLCoding {
    public enum Scope: String, CaseIterable, Sendable, Identifiable {
        case component
        case wholeURL

        public var id: String { rawValue }
        public var title: String { self == .component ? "Component" : "Whole URL" }
    }

    public enum DecodeError: Error, Equatable, Sendable, CustomStringConvertible {
        case invalidEscape(String, position: Int)
        case notUTF8

        public var description: String {
            switch self {
            case let .invalidEscape(escape, position):
                "“\(escape)” at character \(position + 1) isn't a valid escape. A % must be followed by two hex digits, like %20."
            case .notUTF8:
                "The escapes decode to bytes that aren't UTF-8 text."
            }
        }
    }

    static let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)
    static let reserved = Set(":/?#[]@!$&'()*+,;=".utf8)

    public static func encode(_ text: String, scope: Scope = .component, spaceAsPlus: Bool = false) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for byte in text.utf8 {
            if unreserved.contains(byte) || (scope == .wholeURL && (reserved.contains(byte) || byte == UInt8(ascii: "%"))) {
                out.append(Character(UnicodeScalar(byte)))
            } else if byte == 0x20, spaceAsPlus {
                out.append("+")
            } else {
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }

    public static func decode(_ text: String, plusAsSpace: Bool = true) throws -> String {
        let utf8 = Array(text.utf8)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(utf8.count)
        var index = 0
        func hexValue(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 0x30...0x39: byte - 0x30
            case 0x41...0x46: byte - 0x41 + 10
            case 0x61...0x66: byte - 0x61 + 10
            default: nil
            }
        }
        while index < utf8.count {
            let byte = utf8[index]
            if byte == UInt8(ascii: "%") {
                if index + 2 < utf8.count,
                   let high = hexValue(utf8[index + 1]), let low = hexValue(utf8[index + 2]) {
                    bytes.append(high << 4 | low)
                    index += 3
                    continue
                }
                let escape = String(decoding: utf8[index..<min(index + 3, utf8.count)], as: UTF8.self)
                let position = String(decoding: utf8[0..<index], as: UTF8.self).count
                throw DecodeError.invalidEscape(escape, position: position)
            }
            bytes.append(byte == UInt8(ascii: "+") && plusAsSpace ? 0x20 : byte)
            index += 1
        }
        guard let decoded = UTF8Text.string(bytes) else { throw DecodeError.notUTF8 }
        return decoded
    }

    /// True when the text has at least one valid %XX escape.
    public static func containsEscape(_ text: String) -> Bool {
        let utf8 = Array(text.utf8)
        guard utf8.count >= 3 else { return false }
        for index in 0..<(utf8.count - 2) where utf8[index] == UInt8(ascii: "%") {
            if utf8[index + 1].isHexDigit, utf8[index + 2].isHexDigit { return true }
        }
        return false
    }
}

extension UInt8 {
    var isHexDigit: Bool {
        (0x30...0x39).contains(self) || (0x41...0x46).contains(self) || (0x61...0x66).contains(self)
    }
}

enum UTF8Text {
    /// The bytes as a string, or nil when they aren't valid UTF-8 (macOS 14 has no
    /// `String(validating:)`).
    static func string(_ bytes: some Collection<UInt8>) -> String? {
        String(bytes: bytes, encoding: .utf8)
    }
}
