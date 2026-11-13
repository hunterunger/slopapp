import Foundation

/// Just enough DER (ASN.1's distinguished encoding) to build CMS signatures and read the
/// parts of certificates they need. Not a general ASN.1 library.
public enum DER {
    public enum Tag {
        public static let integer: UInt8 = 0x02
        public static let bitString: UInt8 = 0x03
        public static let octetString: UInt8 = 0x04
        public static let null: UInt8 = 0x05
        public static let oid: UInt8 = 0x06
        public static let utf8String: UInt8 = 0x0C
        public static let printableString: UInt8 = 0x13
        public static let utcTime: UInt8 = 0x17
        public static let generalizedTime: UInt8 = 0x18
        public static let sequence: UInt8 = 0x30
        public static let set: UInt8 = 0x31
    }

    public static func tlv(_ tag: UInt8, _ content: Data) -> Data {
        var out = Data([tag])
        out.append(length(content.count))
        out.append(content)
        return out
    }

    static func length(_ count: Int) -> Data {
        if count < 0x80 { return Data([UInt8(count)]) }
        var bytes: [UInt8] = []
        var value = count
        while value > 0 { bytes.insert(UInt8(value & 0xFF), at: 0); value >>= 8 }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    public static func sequence(_ items: [Data]) -> Data { tlv(Tag.sequence, items.reduce(Data(), +)) }

    /// DER sets are sorted by their encodings.
    public static func set(_ items: [Data]) -> Data {
        tlv(Tag.set, items.sorted { $0.lexicographicallyPrecedes($1) }.reduce(Data(), +))
    }

    public static func integer(_ value: Int) -> Data {
        var bytes: [UInt8] = []
        var v = value
        repeat { bytes.insert(UInt8(v & 0xFF), at: 0); v >>= 8 } while v > 0
        if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
        return tlv(Tag.integer, Data(bytes))
    }

    /// A positive integer from big-endian bytes (serial numbers).
    public static func integer(unsigned bytes: Data) -> Data {
        var content = [UInt8](bytes.drop { $0 == 0 })
        if content.isEmpty { content = [0] }
        if content[0] & 0x80 != 0 { content.insert(0, at: 0) }
        return tlv(Tag.integer, Data(content))
    }

    public static func oid(_ dotted: String) -> Data {
        let parts = dotted.split(separator: ".").compactMap { UInt64($0) }
        guard parts.count >= 2 else { return tlv(Tag.oid, Data()) }
        var out = Data([UInt8(parts[0] * 40 + parts[1])])
        for part in parts.dropFirst(2) {
            var chunk: [UInt8] = [UInt8(part & 0x7F)]
            var v = part >> 7
            while v > 0 { chunk.insert(UInt8(v & 0x7F) | 0x80, at: 0); v >>= 7 }
            out.append(contentsOf: chunk)
        }
        return tlv(Tag.oid, out)
    }

    public static let null = Data([Tag.null, 0])
    public static func octetString(_ data: Data) -> Data { tlv(Tag.octetString, data) }
    public static func utf8String(_ text: String) -> Data { tlv(Tag.utf8String, Data(text.utf8)) }
    public static func bitString(_ data: Data) -> Data { tlv(Tag.bitString, Data([0]) + data) }

    /// `[n]` explicit (constructed) context tag.
    public static func explicit(_ number: UInt8, _ content: Data) -> Data { tlv(0xA0 | number, content) }
    /// `[n]` implicit constructed tag replacing a SET or SEQUENCE's own tag.
    public static func implicit(_ number: UInt8, constructed content: Data) -> Data { tlv(0xA0 | number, content) }

    public static func utcTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return tlv(Tag.utcTime, Data(formatter.string(from: date).utf8))
    }

    // MARK: Reading

    public struct Node {
        public var tag: UInt8
        /// The whole element (tag, length and content).
        public var range: Range<Int>
        public var content: Range<Int>
    }

    /// The element starting at `offset`, or nil if the bytes are malformed.
    public static func node(in data: Data, at offset: Int) -> Node? {
        let bytes = data
        let base = bytes.startIndex
        guard offset + 2 <= bytes.count else { return nil }
        let tag = bytes[base + offset]
        let first = bytes[base + offset + 1]
        var length = 0
        var header = 2
        if first & 0x80 == 0 {
            length = Int(first)
        } else {
            let count = Int(first & 0x7F)
            guard count > 0, count <= 4, offset + 2 + count <= bytes.count else { return nil }
            for i in 0..<count { length = length << 8 | Int(bytes[base + offset + 2 + i]) }
            header += count
        }
        guard offset + header + length <= bytes.count else { return nil }
        return Node(tag: tag, range: offset..<(offset + header + length), content: (offset + header)..<(offset + header + length))
    }

    /// The direct children of a constructed element.
    public static func children(of node: Node, in data: Data) -> [Node] {
        var result: [Node] = []
        var offset = node.content.lowerBound
        while offset < node.content.upperBound, let child = self.node(in: data, at: offset) {
            result.append(child)
            offset = child.range.upperBound
        }
        return result
    }

    public static func bytes(_ range: Range<Int>, of data: Data) -> Data {
        data.subdata(in: (data.startIndex + range.lowerBound)..<(data.startIndex + range.upperBound))
    }
}

/// The parts of an X.509 certificate a CMS signature refers to.
public struct CertificateInfo: Sendable {
    /// The issuer name exactly as encoded (a DER SEQUENCE).
    public var issuer: Data
    /// The serial number as an encoded INTEGER.
    public var serial: Data
    public var der: Data

    public init?(der: Data) {
        // Certificate ::= SEQUENCE { tbsCertificate, signatureAlgorithm, signature }
        // TBSCertificate ::= SEQUENCE { [0] version OPTIONAL, serialNumber, signature, issuer, … }
        guard let certificate = DER.node(in: der, at: 0), certificate.tag == DER.Tag.sequence,
              let tbs = DER.children(of: certificate, in: der).first, tbs.tag == DER.Tag.sequence else { return nil }
        var fields = DER.children(of: tbs, in: der)
        if fields.first?.tag == 0xA0 { fields.removeFirst() }
        guard fields.count >= 3, fields[0].tag == DER.Tag.integer, fields[2].tag == DER.Tag.sequence else { return nil }
        serial = DER.bytes(fields[0].range, of: der)
        issuer = DER.bytes(fields[2].range, of: der)
        self.der = der
    }
}
