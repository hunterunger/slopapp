import Foundation

/// The preview text rules: what each card shows, which characters a font lacks, and the
/// sample to use when a font can't show the text at all.
public enum PreviewText {
    /// Grid cards show one line. Empty text means "each font's own name".
    public static func line(for text: String, familyName: String) -> String {
        let first = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return first.trimmingCharacters(in: .whitespaces).isEmpty ? familyName : first
    }

    /// Text runs, each marked covered or missing. `covers` gets one grapheme's UTF-16 units
    /// (without ignorable joiners and selectors) and says whether the font maps them all.
    public static func runs(_ text: String, covers: ([UInt16]) -> Bool) -> [(text: String, covered: Bool)] {
        var runs: [(text: String, covered: Bool)] = []
        for character in text {
            let units = relevantUnits(character)
            let covered = units.isEmpty || covers(units)
            if let last = runs.last, last.covered == covered {
                runs[runs.count - 1].text.append(character)
            } else {
                runs.append((String(character), covered))
            }
        }
        return runs
    }

    /// Share of visible characters the font can show, 0...1 (1 for blank text).
    public static func coverage(_ runs: [(text: String, covered: Bool)]) -> Double {
        var total = 0, covered = 0
        for run in runs {
            let count = run.text.filter { !$0.isWhitespace }.count
            total += count
            if run.covered { covered += count }
        }
        return total == 0 ? 1 : Double(covered) / Double(total)
    }

    public static func missingCount(_ runs: [(text: String, covered: Bool)]) -> Int {
        runs.filter { !$0.covered }.reduce(0) { $0 + $1.text.filter { !$0.isWhitespace }.count }
    }

    /// Below this share of covered characters, a card switches to the font's own sample.
    public static let sampleThreshold = 0.5

    static func relevantUnits(_ character: Character) -> [UInt16] {
        var units: [UInt16] = []
        for scalar in character.unicodeScalars {
            let value = scalar.value
            if scalar.properties.isWhitespace || scalar.properties.generalCategory == .control { continue }
            if value == 0x200D || (0xFE00...0xFE0F).contains(value) || (0xE0100...0xE01EF).contains(value)
                || (0x1F3FB...0x1F3FF).contains(value) { continue }
            units.append(contentsOf: String(scalar).utf16)
        }
        return units
    }

    /// A sample the font can show, from its own characters: emoji for colour fonts, else
    /// the first letters it has (skipping basic Latin, which it evidently lacks), else symbols.
    public static func sample(hasColorGlyphs: Bool, contains: (UInt32) -> Bool, length: Int = 14) -> String {
        if hasColorGlyphs {
            let emoji = "😀🎉🌍🐶🍎🚀🎨✨".unicodeScalars.filter { contains($0.value) }
            if !emoji.isEmpty { return String(String.UnicodeScalarView(emoji)) }
        }
        var letters = String.UnicodeScalarView()
        var symbols = String.UnicodeScalarView()
        var value: UInt32 = 0x00C0
        while value < 0x2FFFF, letters.count < length {
            if let scalar = Unicode.Scalar(value), contains(value) {
                let properties = scalar.properties
                if properties.isAlphabetic, !properties.isWhitespace, properties.generalCategory != .privateUse {
                    letters.append(scalar)
                } else if symbols.count < length, !properties.isWhitespace,
                          properties.generalCategory != .control, properties.generalCategory != .format,
                          properties.generalCategory != .privateUse, properties.generalCategory != .unassigned {
                    symbols.append(scalar)
                }
            }
            value += 1
        }
        if letters.count >= 4 { return String(letters) }
        if !symbols.isEmpty { return String(symbols) }
        // Fall back to whatever printable ASCII it has.
        let ascii = (0x21...0x7E).compactMap { contains(UInt32($0)) ? Unicode.Scalar(UInt32($0)) : nil }.prefix(length)
        return String(String.UnicodeScalarView(ascii))
    }
}

/// Ready-made preview texts (the menu next to the preview field).
public struct PreviewPreset: Identifiable, Hashable, Sendable {
    public var title: String
    public var text: String
    public var id: String { title }

    public static let all: [PreviewPreset] = [
        PreviewPreset(title: "Font Name", text: ""),
        PreviewPreset(title: "Pangram", text: "The quick brown fox jumps over the lazy dog"),
        PreviewPreset(title: "Short Pangram", text: "Sphinx of black quartz, judge my vow"),
        PreviewPreset(title: "Uppercase", text: "ABCDEFGHIJKLMNOPQRSTUVWXYZ"),
        PreviewPreset(title: "Lowercase", text: "abcdefghijklmnopqrstuvwxyz"),
        PreviewPreset(title: "Numbers", text: "0123456789 ½ ¾ %"),
        PreviewPreset(title: "Punctuation", text: "!?.,:;'\"“”‘’()[]{}&@#*/\\–—…"),
        PreviewPreset(title: "Accented Letters", text: "Àéîõü ÇÑ ßæøå Łódź Škoda"),
        PreviewPreset(title: "Currencies", text: "$ € £ ¥ ₹ ₩ ₽ ₺ ¢"),
        PreviewPreset(title: "Code", text: "0O 1lI {}[]() => != <= === // fn()"),
    ]
}

/// Preview size limits and steps (⌘+ / ⌘− walk these).
public enum PreviewSize {
    public static let range: ClosedRange<Double> = 8...200
    public static let standard: Double = 36
    public static let steps: [Double] = [8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 42, 48, 56, 64, 72, 84, 96, 112, 128, 144, 168, 200]

    public static func clamp(_ size: Double) -> Double { min(max(size, range.lowerBound), range.upperBound) }
    public static func bigger(_ size: Double) -> Double { steps.first { $0 > size + 0.5 } ?? range.upperBound }
    public static func smaller(_ size: Double) -> Double { steps.last { $0 < size - 0.5 } ?? range.lowerBound }
}
