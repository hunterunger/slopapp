import Foundation

/// A minimal DER (ASN.1) reader: enough for X.509 certificates and public keys.
public struct DERNode: Sendable, Equatable {
    public var tag: UInt8
    /// The whole TLV, header included.
    public var encoded: Data
    /// The value bytes.
    public var content: Data
    public var children: [DERNode]

    public var isConstructed: Bool { tag & 0x20 != 0 }
    /// Context-specific tags `[n]`.
    public var contextNumber: Int? { tag & 0xC0 == 0x80 ? Int(tag & 0x1F) : nil }

    public struct ParseError: Error, Equatable, Sendable, CustomStringConvertible {
        public var description: String
    }

    public static func parse(_ data: Data) throws -> DERNode {
        let bytes = [UInt8](data)
        var index = 0
        let node = try parseNode(bytes, at: &index, depth: 0)
        return node
    }

    static func parseNode(_ bytes: [UInt8], at index: inout Int, depth: Int) throws -> DERNode {
        guard depth < 64 else { throw ParseError(description: "Nested too deeply") }
        let start = index
        guard index + 2 <= bytes.count else { throw ParseError(description: "Truncated data") }
        let tag = bytes[index]
        index += 1
        var length = Int(bytes[index])
        index += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard count > 0, count <= 4, index + count <= bytes.count else { throw ParseError(description: "Unsupported length") }
            length = 0
            for _ in 0..<count {
                length = (length << 8) | Int(bytes[index])
                index += 1
            }
        }
        guard index + length <= bytes.count else { throw ParseError(description: "Truncated data") }
        let contentRange = index..<(index + length)
        var children: [DERNode] = []
        if tag & 0x20 != 0 {
            var childIndex = contentRange.lowerBound
            while childIndex < contentRange.upperBound {
                children.append(try parseNode(bytes, at: &childIndex, depth: depth + 1))
            }
        }
        index = contentRange.upperBound
        return DERNode(tag: tag, encoded: Data(bytes[start..<index]), content: Data(bytes[contentRange]), children: children)
    }

    /// Parses the content of a primitive node as DER (OCTET STRING / BIT STRING wrappers).
    public func parseContent(skipUnusedBitsByte: Bool = false) throws -> DERNode {
        try DERNode.parse(skipUnusedBitsByte ? content.dropFirst() : content)
    }

    public var oid: String? {
        guard tag == 0x06, !content.isEmpty else { return nil }
        let bytes = [UInt8](content)
        var parts = [Int(bytes[0]) / 40, Int(bytes[0]) % 40]
        if bytes[0] >= 80 { parts = [2, Int(bytes[0]) - 80] }
        var value = 0
        for byte in bytes.dropFirst() {
            value = (value << 7) | Int(byte & 0x7F)
            if byte & 0x80 == 0 {
                parts.append(value)
                value = 0
            }
        }
        return parts.map(String.init).joined(separator: ".")
    }

    /// Strings: UTF8String, PrintableString, IA5String, T61String, BMPString, UniversalString.
    public var string: String? {
        switch tag {
        case 0x0C, 0x13, 0x16, 0x14, 0x1A: return String(decoding: content, as: UTF8.self)
        case 0x1E: return String(data: content, encoding: .utf16BigEndian)
        case 0x1C: return String(data: content, encoding: .utf32BigEndian)
        default: return nil
        }
    }

    public var date: Date? {
        guard tag == 0x17 || tag == 0x18, let text = String(data: content, encoding: .ascii) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        if tag == 0x17 {
            // UTCTime: two-digit years 50–99 are 19xx (RFC 5280).
            formatter.dateFormat = "yyMMddHHmmss'Z'"
            formatter.twoDigitStartDate = Date(timeIntervalSince1970: -631_152_000) // 1950-01-01
        } else {
            formatter.dateFormat = "yyyyMMddHHmmss'Z'"
        }
        return formatter.date(from: text)
    }

    public var integerHex: String {
        var bytes = [UInt8](content)
        while bytes.count > 1, bytes.first == 0 { bytes.removeFirst() }
        return bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    /// Unsigned integer bit length (RSA modulus size).
    public var integerBitLength: Int {
        var bytes = [UInt8](content)
        while bytes.count > 1, bytes.first == 0 { bytes.removeFirst() }
        guard let first = bytes.first else { return 0 }
        return (bytes.count - 1) * 8 + (8 - first.leadingZeroBitCount)
    }

    // MARK: Writing (for building keys from JWK)

    static func encodeLength(_ length: Int) -> [UInt8] {
        if length < 0x80 { return [UInt8(length)] }
        var bytes: [UInt8] = []
        var value = length
        while value > 0 {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        }
        return [0x80 | UInt8(bytes.count)] + bytes
    }

    static func encode(tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        [tag] + encodeLength(content.count) + content
    }

    /// A positive INTEGER (adds a leading zero when the high bit is set).
    static func encodeUnsignedInteger(_ bytes: [UInt8]) -> [UInt8] {
        var value = Array(bytes.drop { $0 == 0 })
        if value.isEmpty { value = [0] }
        if value[0] & 0x80 != 0 { value.insert(0, at: 0) }
        return encode(tag: 0x02, value)
    }
}

/// PEM blocks: "-----BEGIN LABEL-----" … "-----END LABEL-----".
public enum PEM {
    public struct Block: Sendable, Equatable {
        public var label: String
        public var data: Data
    }

    public static func blocks(in text: String) -> [Block] {
        var blocks: [Block] = []
        var label: String?
        var body = ""
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("-----BEGIN "), line.hasSuffix("-----") {
                label = String(line.dropFirst(11).dropLast(5))
                body = ""
            } else if line.hasPrefix("-----END "), let current = label {
                if let data = Data(base64Encoded: body, options: .ignoreUnknownCharacters) {
                    blocks.append(Block(label: current, data: data))
                }
                label = nil
            } else if label != nil, !line.contains(":") {
                body += line
            }
        }
        return blocks
    }
}
