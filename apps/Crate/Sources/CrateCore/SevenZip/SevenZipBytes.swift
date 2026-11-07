import Foundation

/// Reading and writing the 7z header encoding (7-Zip's `7zFormat.txt`, public domain):
/// variable-length numbers, bit vectors and little-endian integers. Every read is bounds
/// checked, because headers come from untrusted files.
struct SevenZipReader {
    let bytes: [UInt8]
    private(set) var offset: Int

    init(_ bytes: [UInt8], offset: Int = 0) {
        self.bytes = bytes
        self.offset = offset
    }

    var isAtEnd: Bool { offset >= bytes.count }

    mutating func byte() throws -> UInt8 {
        guard offset < bytes.count else { throw SevenZipError.malformed("header ends early") }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func take(_ count: Int) throws -> [UInt8] {
        guard count >= 0, count <= bytes.count - offset else { throw SevenZipError.malformed("header ends early") }
        defer { offset += count }
        return Array(bytes[offset..<(offset + count)])
    }

    mutating func skip(_ count: UInt64) throws {
        guard count <= UInt64(bytes.count - offset) else { throw SevenZipError.malformed("header ends early") }
        offset += Int(count)
    }

    /// 7z's UINT64: the first byte's leading 1-bits say how many bytes follow.
    mutating func number() throws -> UInt64 {
        let first = try byte()
        var mask: UInt8 = 0x80
        var value: UInt64 = 0
        for index in 0..<8 {
            if first & mask == 0 {
                let high = UInt64(first & (mask &- 1))
                value |= high << (8 * UInt64(index))
                return value
            }
            value |= UInt64(try byte()) << (8 * UInt64(index))
            mask >>= 1
        }
        return value
    }

    /// A number used as a count or index: bounded so a hostile header can't ask for
    /// billions of items.
    mutating func count(max limit: Int = 1 << 24) throws -> Int {
        let value = try number()
        guard value <= UInt64(limit) else { throw SevenZipError.malformed("count too large") }
        return Int(value)
    }

    mutating func uint32() throws -> UInt32 {
        let b = try take(4)
        return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
    }

    mutating func uint64() throws -> UInt64 {
        let b = try take(8)
        return b.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
    }

    /// "AllAreDefined" byte, then (if 0) a bit vector, MSB first.
    mutating func definedVector(_ count: Int) throws -> [Bool] {
        if try byte() != 0 { return Array(repeating: true, count: count) }
        return try bitVector(count)
    }

    mutating func bitVector(_ count: Int) throws -> [Bool] {
        var result: [Bool] = []
        result.reserveCapacity(count)
        var current: UInt8 = 0
        var mask: UInt8 = 0
        for _ in 0..<count {
            if mask == 0 {
                current = try byte()
                mask = 0x80
            }
            result.append(current & mask != 0)
            mask >>= 1
        }
        return result
    }

    /// CRC digests: a defined vector, then a UInt32 for each defined one.
    mutating func digests(_ count: Int) throws -> [UInt32?] {
        let defined = try definedVector(count)
        return try defined.map { try $0 ? uint32() : nil }
    }
}

struct SevenZipWriter {
    private(set) var bytes: [UInt8] = []

    mutating func byte(_ value: UInt8) { bytes.append(value) }
    mutating func append(_ values: [UInt8]) { bytes += values }

    mutating func number(_ value: UInt64) {
        var first: UInt8 = 0
        var mask: UInt8 = 0x80
        var extra = 0
        while extra < 8 {
            if value < (UInt64(1) << (7 * UInt64(extra + 1))) {
                first |= UInt8(truncatingIfNeeded: value >> (8 * UInt64(extra)))
                break
            }
            first |= mask
            mask >>= 1
            extra += 1
        }
        bytes.append(first)
        for index in 0..<extra {
            bytes.append(UInt8(truncatingIfNeeded: value >> (8 * UInt64(index))))
        }
    }

    mutating func number(_ value: Int) { number(UInt64(value)) }

    mutating func uint32(_ value: UInt32) {
        for index in 0..<4 { bytes.append(UInt8(truncatingIfNeeded: value >> (8 * UInt32(index)))) }
    }

    mutating func uint64(_ value: UInt64) {
        for index in 0..<8 { bytes.append(UInt8(truncatingIfNeeded: value >> (8 * UInt64(index)))) }
    }

    mutating func digests(_ values: [UInt32?]) {
        if values.allSatisfy({ $0 != nil }) {
            byte(1)
        } else {
            byte(0)
            var current: UInt8 = 0
            var mask: UInt8 = 0x80
            for value in values {
                if value != nil { current |= mask }
                mask >>= 1
                if mask == 0 { byte(current); current = 0; mask = 0x80 }
            }
            if mask != 0x80 { byte(current) }
        }
        for case let value? in values { uint32(value) }
    }
}

/// CRC-32 (IEEE, as zip and 7z use).
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var c = UInt32(index)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum<C: Collection>(_ bytes: C, initial: UInt32 = 0) -> UInt32 where C.Element == UInt8 {
        var crc = ~initial
        for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return ~crc
    }

    static func checksum(_ buffer: UnsafeRawBufferPointer, initial: UInt32 = 0) -> UInt32 {
        var crc = ~initial
        for byte in buffer { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return ~crc
    }
}

/// Why a 7z archive couldn't be decrypted or encrypted. Mapped to `CrateError` by callers.
enum SevenZipError: Error, Equatable {
    case notSevenZip
    case malformed(String)
    case wrongPassword
    case passwordRequired
    case unsupported(String)
    case io(String)
}
