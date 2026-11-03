import Foundation

/// A minimal arbitrary-size unsigned integer: enough to convert numbers of any length
/// between bases 2–36. Little-endian 32-bit limbs.
public struct BigUInt: Sendable, Equatable {
    var limbs: [UInt32]

    public init() { limbs = [] }

    public init(_ value: UInt64) {
        limbs = value == 0 ? [] : [UInt32(truncatingIfNeeded: value), UInt32(truncatingIfNeeded: value >> 32)]
        normalize()
    }

    /// Big-endian bytes.
    public init(bytes: some Collection<UInt8>) {
        self.init()
        for byte in bytes { multiplyAdd(256, UInt32(byte)) }
    }

    public var isZero: Bool { limbs.isEmpty }

    public var bitWidth: Int {
        guard let top = limbs.last else { return 0 }
        return (limbs.count - 1) * 32 + (32 - top.leadingZeroBitCount)
    }

    mutating func normalize() {
        while limbs.last == 0 { limbs.removeLast() }
    }

    mutating func multiplyAdd(_ multiplier: UInt32, _ addend: UInt32) {
        var carry = UInt64(addend)
        for index in limbs.indices {
            let product = UInt64(limbs[index]) * UInt64(multiplier) + carry
            limbs[index] = UInt32(truncatingIfNeeded: product)
            carry = product >> 32
        }
        if carry > 0 { limbs.append(UInt32(carry)) }
    }

    /// Divides in place, returning the remainder.
    mutating func divide(by divisor: UInt32) -> UInt32 {
        var remainder: UInt64 = 0
        for index in limbs.indices.reversed() {
            let current = (remainder << 32) | UInt64(limbs[index])
            limbs[index] = UInt32(current / UInt64(divisor))
            remainder = current % UInt64(divisor)
        }
        normalize()
        return UInt32(remainder)
    }

    static let digits = Array("0123456789abcdefghijklmnopqrstuvwxyz")

    public func toString(radix: Int, uppercase: Bool = false) -> String {
        precondition((2...36).contains(radix))
        guard !isZero else { return "0" }
        // Peel off as many digits per division as fit in a UInt32.
        var chunkDigits = 1
        var chunk = UInt32(radix)
        while UInt64(chunk) * UInt64(radix) <= UInt64(UInt32.max) {
            chunk *= UInt32(radix)
            chunkDigits += 1
        }
        var value = self
        var pieces: [Character] = []
        while !value.isZero {
            var remainder = value.divide(by: chunk)
            for _ in 0..<chunkDigits {
                pieces.append(Self.digits[Int(remainder % UInt32(radix))])
                remainder /= UInt32(radix)
                if value.isZero, remainder == 0 { break }
            }
        }
        while pieces.count > 1, pieces.last == "0" { pieces.removeLast() }
        let text = String(pieces.reversed())
        return uppercase ? text.uppercased() : text
    }

    public static func parse(_ text: some StringProtocol, radix: Int) -> BigUInt? {
        guard (2...36).contains(radix), !text.isEmpty else { return nil }
        var value = BigUInt()
        for character in text {
            guard let digit = character.hexDigitValue ?? Self.letterValue(character), digit < radix else { return nil }
            value.multiplyAdd(UInt32(radix), UInt32(digit))
        }
        return value
    }

    static func letterValue(_ character: Character) -> Int? {
        guard let ascii = character.lowercased().first?.asciiValue, ascii >= 97, ascii <= 122 else { return nil }
        return Int(ascii - 97 + 10)
    }
}

/// Converts integers of any size between bases, with prefixes (0x, 0b, 0o) and digit
/// separators (_ , spaces) understood.
public enum NumberBase {
    public struct Value: Sendable, Equatable {
        public var magnitude: BigUInt
        public var negative: Bool
        public var detectedRadix: Int

        public func string(radix: Int, uppercase: Bool = false) -> String {
            (negative && !magnitude.isZero ? "-" : "") + magnitude.toString(radix: radix, uppercase: uppercase)
        }
    }

    public enum ParseError: Error, Equatable, Sendable, CustomStringConvertible {
        case empty
        case invalidDigit(Character, radix: Int)
        case tooLong

        public var description: String {
            switch self {
            case .empty: "Type a number, like 255, 0xFF or 0b1010."
            case let .invalidDigit(character, radix): "“\(character)” isn't a digit in base \(radix)."
            case .tooLong: "That number is too long (over 10,000 digits)."
            }
        }
    }

    /// `radix` nil means detect from the prefix (default decimal).
    public static func parse(_ text: String, radix: Int? = nil) throws -> Value {
        var body = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !body.isEmpty else { throw ParseError.empty }
        var negative = false
        if body.first == "-" { negative = true; body = body.dropFirst() } else if body.first == "+" { body = body.dropFirst() }
        var detected = radix ?? 10
        let lower = body.lowercased()
        let prefixes: [(String, Int)] = [("0x", 16), ("0b", 2), ("0o", 8), ("#", 16)]
        for (prefix, prefixRadix) in prefixes where lower.hasPrefix(prefix) {
            // With a base chosen, only strip that base's own prefix ("0b" is valid hex).
            if radix == nil || radix == prefixRadix {
                detected = prefixRadix
                body = body.dropFirst(prefix.count)
            }
            break
        }
        let digits = body.filter { $0 != "_" && $0 != "," && $0 != " " && $0 != "'" }
        guard !digits.isEmpty else { throw ParseError.empty }
        guard digits.count <= 10_000 else { throw ParseError.tooLong }
        for character in digits {
            let value = character.hexDigitValue ?? BigUInt.letterValue(character)
            if value == nil || value! >= detected { throw ParseError.invalidDigit(character, radix: detected) }
        }
        return Value(magnitude: BigUInt.parse(digits, radix: detected)!, negative: negative, detectedRadix: detected)
    }

    /// Groups digits from the right, e.g. 4 for binary/hex nibbles, 3 for decimal thousands.
    public static func grouped(_ text: String, size: Int, separator: Character = " ") -> String {
        let negative = text.hasPrefix("-")
        let digits = Array(negative ? text.dropFirst() : Substring(text))
        var out: [Character] = []
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index) % size == 0 { out.append(separator) }
            out.append(character)
        }
        return (negative ? "-" : "") + String(out)
    }
}
