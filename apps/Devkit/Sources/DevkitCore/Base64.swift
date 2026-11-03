import Foundation

/// Base64 (RFC 4648 §4) and base64url (§5). Decoding is forgiving the way people need it to
/// be: whitespace and line breaks are ignored, padding is optional, and both alphabets work.
public enum Base64 {
    public struct EncodeOptions: Sendable, Equatable {
        public var urlSafe: Bool
        public var padding: Bool

        public init(urlSafe: Bool = false, padding: Bool = true) {
            self.urlSafe = urlSafe
            self.padding = padding
        }
    }

    public enum DecodeError: Error, Equatable, Sendable, CustomStringConvertible {
        case invalidCharacter(Character, position: Int)
        case misplacedPadding(position: Int)
        case invalidLength
        case empty

        public var description: String {
            switch self {
            case let .invalidCharacter(character, position):
                let shown = character.isWhitespace ? "a space" : "“\(character)”"
                return "Base64 can only contain A–Z, a–z, 0–9, + and / (or - and _), found \(shown) at character \(position + 1)."
            case let .misplacedPadding(position):
                return "Padding (=) can only come at the end, found one at character \(position + 1)."
            case .invalidLength:
                return "This is one character too long or too short to be Base64. Check it wasn't cut off."
            case .empty:
                return "Nothing to decode."
            }
        }
    }

    public static func encode(_ data: Data, options: EncodeOptions = EncodeOptions()) -> String {
        var text = data.base64EncodedString()
        if options.urlSafe {
            text = String(text.map { $0 == "+" ? "-" : $0 == "/" ? "_" : $0 })
        }
        if !options.padding {
            while text.hasSuffix("=") { text.removeLast() }
        }
        return text
    }

    public static func encode(_ text: String, options: EncodeOptions = EncodeOptions()) -> String {
        encode(Data(text.utf8), options: options)
    }

    public static func decode(_ text: String) throws -> Data {
        var cleaned: [UInt8] = []
        cleaned.reserveCapacity(text.utf8.count)
        var paddingStart: Int?
        for (position, character) in text.enumerated() {
            if character.isWhitespace { continue }
            guard character.isASCII, let byte = character.asciiValue else {
                throw DecodeError.invalidCharacter(character, position: position)
            }
            switch byte {
            case UInt8(ascii: "="):
                if paddingStart == nil { paddingStart = position }
                continue
            case UInt8(ascii: "-"): cleaned.append(UInt8(ascii: "+"))
            case UInt8(ascii: "_"): cleaned.append(UInt8(ascii: "/"))
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "+"), UInt8(ascii: "/"):
                cleaned.append(byte)
            default:
                throw DecodeError.invalidCharacter(character, position: position)
            }
            if let paddingStart { throw DecodeError.misplacedPadding(position: paddingStart) }
        }
        if cleaned.isEmpty { throw DecodeError.empty }
        if cleaned.count % 4 == 1 { throw DecodeError.invalidLength }
        while cleaned.count % 4 != 0 { cleaned.append(UInt8(ascii: "=")) }
        guard let data = Data(base64Encoded: Data(cleaned)) else { throw DecodeError.invalidLength }
        return data
    }

    /// Decodes and, when the bytes are UTF-8 text, returns it.
    public static func decodeText(_ text: String) throws -> DecodedBytes {
        DecodedBytes(data: try decode(text))
    }
}

/// Bytes shown as text when they're UTF-8, or as a hex dump when they aren't.
public struct DecodedBytes: Sendable, Equatable {
    public var data: Data
    public var text: String?

    public init(data: Data) {
        self.data = data
        text = UTF8Text.string(data).flatMap { TextHeuristics.looksLikeText($0) ? $0 : nil }
    }

    /// What to show: the text, or a hex dump.
    public var display: String { text ?? HexDump.format(data) }
}

public enum TextHeuristics {
    /// True when nearly every character is printable (or a tab/newline). Used to tell
    /// decoded text from decoded binary.
    public static func looksLikeText(_ text: String, threshold: Double = 0.95) -> Bool {
        if text.isEmpty { return true }
        var printable = 0
        var total = 0
        for scalar in text.unicodeScalars {
            total += 1
            switch scalar.value {
            case 0x09, 0x0A, 0x0D: printable += 1
            case 0..<0x20, 0x7F, 0x80..<0xA0, 0xFFFD: break
            default: printable += 1
            }
        }
        return Double(printable) / Double(total) >= threshold
    }
}

/// A classic `hexdump -C`-style dump: offset, 16 bytes in hex, then the ASCII.
public enum HexDump {
    public static func format(_ data: Data, limit: Int = 64 * 1024) -> String {
        let bytes = [UInt8](data.prefix(limit))
        var lines: [String] = []
        lines.reserveCapacity(bytes.count / 16 + 2)
        let hexDigits = Array("0123456789abcdef")
        var offset = 0
        while offset < bytes.count {
            let row = bytes[offset..<min(offset + 16, bytes.count)]
            var line = String(format: "%08x  ", offset)
            for (index, byte) in row.enumerated() {
                line.append(hexDigits[Int(byte >> 4)])
                line.append(hexDigits[Int(byte & 0x0F)])
                line.append(" ")
                if index == 7 { line.append(" ") }
            }
            if row.count < 16 {
                line += String(repeating: "   ", count: 16 - row.count)
                if row.count <= 7 { line += " " }
            }
            line += " |"
            for byte in row {
                line.append(byte >= 0x20 && byte < 0x7F ? Character(UnicodeScalar(byte)) : ".")
            }
            line += "|"
            lines.append(line)
            offset += 16
        }
        if data.count > limit {
            lines.append("… \(data.count - limit) more bytes not shown")
        }
        return lines.joined(separator: "\n")
    }

    /// Plain lowercase hex, no spaces.
    public static func hex(_ data: some Sequence<UInt8>, uppercase: Bool = false) -> String {
        let digits = Array(uppercase ? "0123456789ABCDEF" : "0123456789abcdef")
        var text = ""
        for byte in data {
            text.append(digits[Int(byte >> 4)])
            text.append(digits[Int(byte & 0x0F)])
        }
        return text
    }
}
