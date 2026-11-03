import Foundation

/// UUID (RFC 9562) and ULID generation and inspection.
public enum IdentifierKind: String, CaseIterable, Sendable, Identifiable {
    case uuidV4 = "v4"
    case uuidV7 = "v7"
    case ulid

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .uuidV4: "UUID v4 (Random)"
        case .uuidV7: "UUID v7 (Time-Ordered)"
        case .ulid: "ULID"
        }
    }
}

/// Generates identifiers. Values from one generator are strictly increasing for v7 and ULID,
/// even within the same millisecond (RFC 9562 §6.2 method 1; the ULID spec's monotonic mode).
public struct IdentifierGenerator<Random: RandomNumberGenerator> {
    public var random: Random
    public var now: () -> Date
    private var lastV7: (ms: UInt64, counter: UInt16)?
    private var lastULID: (ms: UInt64, random: [UInt8])?

    public init(random: Random, now: @escaping () -> Date = Date.init) {
        self.random = random
        self.now = now
    }

    public mutating func generate(_ kind: IdentifierKind, count: Int, format: IdentifierFormat = IdentifierFormat()) -> [String] {
        (0..<max(0, count)).map { _ in
            switch kind {
            case .uuidV4: Identifiers.formatUUID(nextV4(), format: format)
            case .uuidV7: Identifiers.formatUUID(nextV7(), format: format)
            case .ulid:
                // ULIDs are always uppercase Crockford base32; the format options don't apply.
                Identifiers.encodeULID(nextULID())
            }
        }
    }

    public mutating func nextV4() -> [UInt8] {
        var bytes = randomBytes(16)
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return bytes
    }

    public mutating func nextV7() -> [UInt8] {
        var ms = Identifiers.milliseconds(now())
        var counter: UInt16
        if let last = lastV7, ms <= last.ms {
            // Same (or earlier) millisecond: count up in rand_a so order holds.
            ms = last.ms
            if last.counter >= 0x0FFF {
                ms += 1
                counter = UInt16.random(in: 0...0x07FF, using: &random)
            } else {
                counter = last.counter + 1
            }
        } else {
            // Start low so there's room to count within the millisecond.
            counter = UInt16.random(in: 0...0x07FF, using: &random)
        }
        lastV7 = (ms, counter)
        var bytes = randomBytes(16)
        for index in 0..<6 { bytes[index] = UInt8(truncatingIfNeeded: ms >> (40 - 8 * UInt64(index))) }
        bytes[6] = 0x70 | UInt8(counter >> 8)
        bytes[7] = UInt8(truncatingIfNeeded: counter)
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return bytes
    }

    public mutating func nextULID() -> [UInt8] {
        let ms = Identifiers.milliseconds(now())
        var randomPart: [UInt8]
        if let last = lastULID, ms <= last.ms {
            randomPart = last.random
            // Increment the 80-bit random part by one.
            var index = randomPart.count - 1
            while index >= 0 {
                randomPart[index] &+= 1
                if randomPart[index] != 0 { break }
                index -= 1
            }
            lastULID = (last.ms, randomPart)
            return Identifiers.ulidBytes(ms: last.ms, random: randomPart)
        }
        randomPart = randomBytes(10)
        lastULID = (ms, randomPart)
        return Identifiers.ulidBytes(ms: ms, random: randomPart)
    }

    private mutating func randomBytes(_ count: Int) -> [UInt8] {
        (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &random) }
    }
}

public struct IdentifierFormat: Sendable, Equatable {
    public var uppercase: Bool
    public var hyphens: Bool
    public init(uppercase: Bool = false, hyphens: Bool = true) {
        self.uppercase = uppercase
        self.hyphens = hyphens
    }
}

public enum Identifiers {
    static let crockford = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func milliseconds(_ date: Date) -> UInt64 {
        UInt64(max(0, (date.timeIntervalSince1970 * 1000).rounded(.down)))
    }

    static func ulidBytes(ms: UInt64, random: [UInt8]) -> [UInt8] {
        var bytes = (0..<6).map { UInt8(truncatingIfNeeded: ms >> (40 - 8 * UInt64($0))) }
        bytes += random
        return bytes
    }

    public static func formatUUID(_ bytes: [UInt8], format: IdentifierFormat = IdentifierFormat()) -> String {
        let hex = HexDump.hex(bytes, uppercase: format.uppercase)
        guard format.hyphens else { return hex }
        let characters = Array(hex)
        return [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(characters[$0]) }.joined(separator: "-")
    }

    /// 128 bits → 26 Crockford base32 characters (the first carries only 3 bits).
    public static func encodeULID(_ bytes: [UInt8]) -> String {
        precondition(bytes.count == 16)
        var value = bytes.reduce((UInt64(0), UInt64(0))) { acc, byte in
            ((acc.0 << 8) | (acc.1 >> 56), (acc.1 << 8) | UInt64(byte))
        }
        var characters = [Character](repeating: "0", count: 26)
        for index in stride(from: 25, through: 0, by: -1) {
            characters[index] = crockford[Int(value.1 & 0x1F)]
            value = (value.0 >> 5, (value.1 >> 5) | (value.0 << 59))
        }
        return String(characters)
    }

    public static func decodeULID(_ text: String) -> [UInt8]? {
        let characters = Array(text.uppercased())
        guard characters.count == 26 else { return nil }
        var value: (UInt64, UInt64) = (0, 0)
        for (index, character) in characters.enumerated() {
            let normalized: Character = switch character {
            case "I", "L": "1"
            case "O": "0"
            default: character
            }
            guard let digit = crockford.firstIndex(of: normalized) else { return nil }
            if index == 0, digit > 7 { return nil } // would overflow 128 bits
            value = ((value.0 << 5) | (value.1 >> 59), (value.1 << 5) | UInt64(digit))
        }
        return (0..<16).map { index in
            let word = index < 8 ? value.0 : value.1
            return UInt8(truncatingIfNeeded: word >> (56 - 8 * UInt64(index % 8)))
        }
    }

    public static func parseUUID(_ text: String) -> [UInt8]? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("urn:uuid:") { trimmed = String(trimmed.dropFirst(9)) }
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") { trimmed = String(trimmed.dropFirst().dropLast()) }
        let characters = Array(trimmed)
        let hex: [Character]
        if characters.count == 36 {
            guard [8, 13, 18, 23].allSatisfy({ characters[$0] == "-" }) else { return nil }
            hex = characters.enumerated().filter { ![8, 13, 18, 23].contains($0.offset) }.map(\.element)
        } else if characters.count == 32 {
            hex = characters
        } else {
            return nil
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(16)
        var index = 0
        while index < 32 {
            guard let byte = UInt8(String(hex[index...index + 1]), radix: 16) else { return nil }
            bytes.append(byte)
            index += 2
        }
        return bytes
    }

    public struct Row: Sendable, Equatable, Identifiable {
        public var label: String
        public var value: String
        public var id: String { label }
        public init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    public enum InspectError: Error, Equatable, Sendable, CustomStringConvertible {
        case unrecognized
        public var description: String {
            "This isn't a UUID (like 123e4567-e89b-12d3-a456-426614174000) or a ULID (26 characters, like 01ARZ3NDEKTSV4RRFFQ69G5FAV)."
        }
    }

    /// Describes a UUID or ULID: format, version, variant and embedded time.
    public static func inspect(_ text: String, timeZone: TimeZone = .current) throws -> [Row] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let bytes = parseUUID(trimmed) {
            return describeUUID(bytes, timeZone: timeZone)
        }
        if let bytes = decodeULID(trimmed) {
            let ms = bytes[0..<6].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            let date = Date(timeIntervalSince1970: Double(ms) / 1000)
            return [
                Row("Format", "ULID"),
                Row("Canonical", encodeULID(bytes)),
                Row("Time", Timestamps.isoString(date, timeZone: TimeZone(identifier: "UTC")!, fractional: true)),
                Row("Local time", Timestamps.isoString(date, timeZone: timeZone, fractional: true)),
                Row("Unix milliseconds", String(ms)),
                Row("Randomness", HexDump.hex(bytes[6...])),
                Row("As UUID", formatUUID(bytes)),
            ]
        }
        throw InspectError.unrecognized
    }

    static func describeUUID(_ bytes: [UInt8], timeZone: TimeZone) -> [Row] {
        let canonical = formatUUID(bytes)
        if bytes.allSatisfy({ $0 == 0 }) {
            return [Row("Format", "UUID"), Row("Canonical", canonical), Row("Version", "Nil UUID (all zeros)")]
        }
        if bytes.allSatisfy({ $0 == 0xFF }) {
            return [Row("Format", "UUID"), Row("Canonical", canonical), Row("Version", "Max UUID (all ones)")]
        }
        let version = Int(bytes[6] >> 4)
        let variantBits = bytes[8] >> 4
        let variant: String = switch variantBits {
        case 0x0...0x7: "NCS (reserved, backward compatibility)"
        case 0x8...0xB: "RFC 9562 (standard)"
        case 0xC...0xD: "Microsoft (reserved, backward compatibility)"
        default: "Reserved for future use"
        }
        let isStandard = (0x8...0xB).contains(variantBits)
        let versionName: String = switch version {
        case 1: "1 (time and node)"
        case 2: "2 (DCE security)"
        case 3: "3 (name-based, MD5)"
        case 4: "4 (random)"
        case 5: "5 (name-based, SHA-1)"
        case 6: "6 (reordered time)"
        case 7: "7 (Unix time, sortable)"
        case 8: "8 (custom)"
        default: "\(version) (unknown)"
        }
        var rows = [
            Row("Format", "UUID"),
            Row("Canonical", canonical),
            Row("Version", isStandard ? versionName : "\(version) (not meaningful for this variant)"),
            Row("Variant", variant),
        ]
        let utc = TimeZone(identifier: "UTC")!
        func addTime(_ date: Date) {
            rows.append(Row("Time", Timestamps.isoString(date, timeZone: utc, fractional: true)))
            rows.append(Row("Local time", Timestamps.isoString(date, timeZone: timeZone, fractional: true)))
        }
        if isStandard {
            switch version {
            case 1, 6:
                let timeLow = bytes[0..<4].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                let timeMid = bytes[4..<6].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                let timeHigh = (UInt64(bytes[6] & 0x0F) << 8) | UInt64(bytes[7])
                let ticks: UInt64 = version == 1
                    ? (timeHigh << 48) | (timeMid << 32) | timeLow
                    : (timeLow << 28) | (timeMid << 12) | timeHigh
                // 100 ns intervals since 1582-10-15 (the Gregorian reform).
                let unix100ns = Int64(bitPattern: ticks) - 0x01B2_1DD2_1381_4000
                addTime(Date(timeIntervalSince1970: Double(unix100ns) / 10_000_000))
                let clockSequence = (Int(bytes[8] & 0x3F) << 8) | Int(bytes[9])
                rows.append(Row("Clock sequence", String(clockSequence)))
                rows.append(Row("Node", bytes[10...].map { String(format: "%02x", $0) }.joined(separator: ":")))
            case 7:
                let ms = bytes[0..<6].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                addTime(Date(timeIntervalSince1970: Double(ms) / 1000))
                rows.append(Row("Unix milliseconds", String(ms)))
            default:
                break
            }
        }
        rows.append(Row("As ULID", encodeULID(bytes)))
        rows.append(Row("Integer", BigUInt(bytes: bytes).toString(radix: 10)))
        return rows
    }
}
