import Foundation

/// GZip (RFC 1952), zlib (RFC 1950) and raw deflate (RFC 1951), using the system's
/// deflate implementation for the compressed stream.
public enum GZip {
    public enum Format: String, CaseIterable, Sendable, Identifiable {
        case gzip, zlib, deflate
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .gzip: "GZip"
            case .zlib: "zlib"
            case .deflate: "Raw Deflate"
            }
        }
    }

    public struct GZipError: Error, Equatable, Sendable, CustomStringConvertible {
        public var description: String
        public init(description: String) { self.description = description }
    }

    public static func compress(_ data: Data, format: Format = .gzip) throws -> Data {
        let deflated: Data
        do {
            deflated = try (data as NSData).compressed(using: .zlib) as Data
        } catch {
            throw GZipError(description: "Compression failed")
        }
        switch format {
        case .deflate:
            return deflated
        case .zlib:
            var out = Data([0x78, 0x9C])
            out.append(deflated)
            withUnsafeBytes(of: adler32(data).bigEndian) { out.append(contentsOf: $0) }
            return out
        case .gzip:
            // Header: magic, deflate, no flags, mtime 0 (reproducible), no extra flags, OS unknown.
            var out = Data([0x1F, 0x8B, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xFF])
            out.append(deflated)
            withUnsafeBytes(of: crc32(data).littleEndian) { out.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt32(truncatingIfNeeded: data.count).littleEndian) { out.append(contentsOf: $0) }
            return out
        }
    }

    /// Detects the format from its header.
    public static func decompress(_ data: Data) throws -> (data: Data, format: Format) {
        let bytes = [UInt8](data)
        if bytes.count >= 18, bytes[0] == 0x1F, bytes[1] == 0x8B {
            return (try gunzip(bytes), .gzip)
        }
        if bytes.count >= 6, bytes[0] & 0x0F == 8, (UInt16(bytes[0]) << 8 | UInt16(bytes[1])) % 31 == 0 {
            guard bytes[1] & 0x20 == 0 else { throw GZipError(description: "zlib streams with a preset dictionary aren't supported") }
            let output = try inflate(Data(bytes[2..<(bytes.count - 4)]))
            let expected = UInt32(bytes[bytes.count - 4]) << 24 | UInt32(bytes[bytes.count - 3]) << 16 | UInt32(bytes[bytes.count - 2]) << 8 | UInt32(bytes[bytes.count - 1])
            guard adler32(output) == expected else { throw GZipError(description: "The zlib checksum doesn't match; the data is damaged") }
            return (output, .zlib)
        }
        return (try inflate(data), .deflate)
    }

    static func gunzip(_ bytes: [UInt8]) throws -> Data {
        var output = Data()
        var index = 0
        while index + 18 <= bytes.count, bytes[index] == 0x1F, bytes[index + 1] == 0x8B {
            guard bytes[index + 2] == 8 else { throw GZipError(description: "Unknown gzip compression method") }
            let flags = bytes[index + 3]
            var cursor = index + 10
            if flags & 0x04 != 0 { // FEXTRA
                guard cursor + 2 <= bytes.count else { throw GZipError(description: "Truncated gzip header") }
                cursor += 2 + Int(bytes[cursor]) | Int(bytes[cursor + 1]) << 8
            }
            if flags & 0x08 != 0 { while cursor < bytes.count, bytes[cursor] != 0 { cursor += 1 }; cursor += 1 } // FNAME
            if flags & 0x10 != 0 { while cursor < bytes.count, bytes[cursor] != 0 { cursor += 1 }; cursor += 1 } // FCOMMENT
            if flags & 0x02 != 0 { cursor += 2 } // FHCRC
            guard cursor < bytes.count - 8 else { throw GZipError(description: "Truncated gzip data") }
            // The deflate stream's length isn't stored: it runs to the trailer at the end.
            let (member, consumed) = try inflateMember(Array(bytes[cursor...]))
            let trailer = cursor + consumed
            guard trailer + 8 <= bytes.count else { throw GZipError(description: "Truncated gzip trailer") }
            let crc = UInt32(bytes[trailer]) | UInt32(bytes[trailer + 1]) << 8 | UInt32(bytes[trailer + 2]) << 16 | UInt32(bytes[trailer + 3]) << 24
            guard crc32(member) == crc else { throw GZipError(description: "The gzip checksum (CRC-32) doesn't match; the data is damaged") }
            output.append(member)
            index = trailer + 8
        }
        return output
    }

    /// Inflates one member's deflate stream, which runs up to the 8-byte trailer.
    static func inflateMember(_ bytes: [UInt8]) throws -> (Data, Int) {
        (try inflate(Data(bytes.dropLast(8))), bytes.count - 8)
    }

    static func inflate(_ data: Data) throws -> Data {
        do {
            return try (data as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw GZipError(description: "The compressed data is damaged or isn't deflate")
        }
    }

    static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 != 0 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    public static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }

    public static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return b << 16 | a
    }

    /// Base64 that decodes to a gzip or zlib header.
    public static func looksLikeCompressedBase64(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 24, trimmed.hasPrefix("H4sI") || trimmed.hasPrefix("eJ") || trimmed.hasPrefix("eN") || trimmed.hasPrefix("eF") else { return false }
        guard let data = try? Base64.decode(trimmed) else { return false }
        return (try? decompress(data)) != nil
    }
}
