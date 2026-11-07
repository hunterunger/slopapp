import Foundation

/// A Git object name (SHA-1, 40 hex digits, or SHA-256, 64) packed into four words, so
/// history rows and the lane layout compare and hash ids without strings.
public struct ObjectID: Hashable, Sendable, Comparable, CustomStringConvertible {
    public var w0: UInt64
    public var w1: UInt64
    public var w2: UInt64
    public var w3: UInt64
    /// Number of hex digits (40 or 64).
    public var length: UInt8

    public init(w0: UInt64, w1: UInt64, w2: UInt64, w3: UInt64, length: UInt8) {
        self.w0 = w0; self.w1 = w1; self.w2 = w2; self.w3 = w3; self.length = length
    }

    /// Parses 40 or 64 hex digits. Anything else is nil.
    public init?(hex: String) {
        guard let value = ObjectID(ascii: Array(hex.utf8)) else { return nil }
        self = value
    }

    /// Parses ASCII hex bytes (40 or 64 of them) from raw output.
    public init?<C: Collection>(ascii: C) where C.Element == UInt8 {
        let count = ascii.count
        guard count == 40 || count == 64 else { return nil }
        var a: UInt64 = 0, b: UInt64 = 0, c: UInt64 = 0, d: UInt64 = 0
        var i = 0
        for byte in ascii {
            guard let n = Self.nibble(byte) else { return nil }
            switch i >> 4 {
            case 0: a = (a << 4) | UInt64(n)
            case 1: b = (b << 4) | UInt64(n)
            case 2: c = (c << 4) | UInt64(n)
            default: d = (d << 4) | UInt64(n)
            }
            i += 1
        }
        if count == 40 { c <<= 32 } // 8 digits in the third word, left-aligned
        self.init(w0: a, w1: b, w2: c, w3: d, length: UInt8(count))
    }

    @inline(__always)
    static func nibble(_ c: UInt8) -> UInt8? {
        switch c {
        case 48...57: return c - 48
        case 97...102: return c - 87
        case 65...70: return c - 55
        default: return nil
        }
    }

    /// The full hex name.
    public var hex: String {
        let digits: [UInt8] = Array("0123456789abcdef".utf8)
        var bytes = [UInt8]()
        bytes.reserveCapacity(Int(length))
        for i in 0..<Int(length) {
            let word: UInt64
            switch i >> 4 {
            case 0: word = w0
            case 1: word = w1
            case 2: word = w2
            default: word = w3
            }
            let shift = UInt64(60 - (i & 15) * 4)
            bytes.append(digits[Int((word >> shift) & 0xF)])
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The first seven digits, Git's usual short form.
    public var short: String { String(hex.prefix(7)) }

    public var description: String { hex }

    public static func < (a: ObjectID, b: ObjectID) -> Bool {
        (a.w0, a.w1, a.w2, a.w3) < (b.w0, b.w1, b.w2, b.w3)
    }
}
