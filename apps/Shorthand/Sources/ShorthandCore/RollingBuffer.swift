/// The last 32 typed characters, in memory only, overwritten as you type. Fixed storage:
/// appending never allocates. Holds Unicode scalar values.
public struct RollingBuffer: Sendable {
    public static let capacity = AbbreviationRules.maxLength

    private var storage: ContiguousArray<UInt32>
    private var start = 0
    public private(set) var count = 0
    /// What came before the oldest character: a word character, or a boundary (space,
    /// punctuation, a new line, or unknown: right after a reset we don't know what's before
    /// the caret, so it counts as a boundary).
    public private(set) var beforeIsWord = false

    public init() {
        storage = ContiguousArray(repeating: 0, count: Self.capacity)
    }

    public var isEmpty: Bool { count == 0 }

    public mutating func append(_ scalar: UInt32) {
        if count == Self.capacity {
            beforeIsWord = CharacterClass.isWord(storage[start])
            storage[start] = scalar
            start = (start + 1) % Self.capacity
        } else {
            storage[(start + count) % Self.capacity] = scalar
            count += 1
        }
    }

    public mutating func removeLast() {
        guard count > 0 else { return }
        count -= 1
        storage[(start + count) % Self.capacity] = 0
        // Deleting past what we saw: whatever is before the caret is unknown.
        if count == 0 { beforeIsWord = false }
    }

    /// Clears every character (zeroed, not just forgotten).
    public mutating func reset(beforeIsWord: Bool = false) {
        for index in storage.indices { storage[index] = 0 }
        start = 0
        count = 0
        self.beforeIsWord = beforeIsWord
    }

    /// `i` = 0 is the newest character.
    @inline(__always)
    public func fromEnd(_ i: Int) -> UInt32 {
        storage[(start + count - 1 - i) % Self.capacity]
    }

    /// Whether the character just before the last `length` characters is a word character.
    @inline(__always)
    public func isWordBefore(length: Int) -> Bool {
        length < count ? CharacterClass.isWord(fromEnd(length)) : beforeIsWord
    }

    /// The buffer as text (tests and seeding only; never logged).
    public var contents: String {
        var scalars = String.UnicodeScalarView()
        for i in stride(from: count - 1, through: 0, by: -1) {
            if let scalar = Unicode.Scalar(fromEnd(i)) { scalars.append(scalar) }
        }
        return String(scalars)
    }
}

/// Character tests that never allocate.
public enum CharacterClass {
    @inline(__always)
    public static func isWord(_ value: UInt32) -> Bool {
        if value < 0x80 {
            return (value >= 0x30 && value <= 0x39) || (value >= 0x41 && value <= 0x5A) || (value >= 0x61 && value <= 0x7A)
        }
        guard let scalar = Unicode.Scalar(value) else { return false }
        let properties = scalar.properties
        return properties.isAlphabetic || properties.numericType != nil
            || properties.generalCategory == .nonspacingMark || properties.generalCategory == .spacingMark
    }

    @inline(__always)
    public static func isLetter(_ value: UInt32) -> Bool {
        if value < 0x80 { return (value >= 0x41 && value <= 0x5A) || (value >= 0x61 && value <= 0x7A) }
        return Unicode.Scalar(value)?.properties.isAlphabetic ?? false
    }

    @inline(__always)
    public static func isUpper(_ value: UInt32) -> Bool {
        if value < 0x80 { return value >= 0x41 && value <= 0x5A }
        return Unicode.Scalar(value)?.properties.isUppercase ?? false
    }

    /// Case folding for "adapt case" abbreviations: ASCII and Latin-1 letters. Other
    /// scripts match as written.
    @inline(__always)
    public static func fold(_ value: UInt32) -> UInt32 {
        if value >= 0x41 && value <= 0x5A { return value + 0x20 }
        if value >= 0xC0 && value <= 0xDE && value != 0xD7 { return value + 0x20 }
        return value
    }
}
