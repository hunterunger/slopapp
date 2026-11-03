import Foundation

/// Everything the classifier looks at, read from the font once at index time.
/// Kept as plain values so the chain is testable without real fonts.
public struct FontFacts: Sendable, Equatable {
    public var familyName: String
    public var styleName: String
    /// `kCTFontTraitMonoSpace`.
    public var isMonospaceTrait: Bool
    /// CoreText stylistic class (`symbolicTraits & kCTFontClassMaskTrait`) >> 28, 0...15.
    public var stylisticClass: Int
    /// The 10 PANOSE bytes from the OS/2 table, if the font has one.
    public var panose: [UInt8]?
    /// Advances of "i", "m" and "W" are equal (nil when the font lacks basic Latin).
    public var equalAdvances: Bool?
    public var coversBasicLatin: Bool
    /// Has an sbix, COLR or CBDT table (colour or emoji glyphs).
    public var hasColorGlyphs: Bool

    public init(
        familyName: String, styleName: String = "Regular", isMonospaceTrait: Bool = false, stylisticClass: Int = 0,
        panose: [UInt8]? = nil, equalAdvances: Bool? = nil, coversBasicLatin: Bool = true, hasColorGlyphs: Bool = false
    ) {
        self.familyName = familyName
        self.styleName = styleName
        self.isMonospaceTrait = isMonospaceTrait
        self.stylisticClass = stylisticClass
        self.panose = panose
        self.equalAdvances = equalAdvances
        self.coversBasicLatin = coversBasicLatin
        self.hasColorGlyphs = hasColorGlyphs
    }
}

/// Sorts a face into a sidebar category. The chain, first match wins:
/// monospace → CoreText class → PANOSE → name hints → colour glyphs → Other / Other Scripts.
public enum Classifier {
    public static func classify(_ facts: FontFacts) -> FontCategory {
        if facts.isMonospaceTrait || facts.panose.map(isPanoseMonospaced) == true || facts.equalAdvances == true
            || nameCategory(facts) == .monospaced {
            return .monospaced
        }
        if let category = classCategory(facts.stylisticClass) { return category }
        if let panose = facts.panose, let category = panoseCategory(panose) { return category }
        if let category = nameCategory(facts) { return category }
        if facts.hasColorGlyphs { return .symbol }
        return facts.coversBasicLatin ? .other : .otherScripts
    }

    /// CoreText's stylistic class (from the OS/2 sFamilyClass).
    static func classCategory(_ stylisticClass: Int) -> FontCategory? {
        switch stylisticClass {
        case 1, 2, 3, 4, 5, 7: .serif
        case 8: .sansSerif
        case 9: .display
        case 10: .script
        case 12: .symbol
        default: nil
        }
    }

    static func isPanoseMonospaced(_ panose: [UInt8]) -> Bool {
        // Latin Text: proportion byte 9 = monospaced.
        panose.count >= 4 && panose[0] == 2 && panose[3] == 9
    }

    static func panoseCategory(_ panose: [UInt8]) -> FontCategory? {
        guard panose.count >= 2 else { return nil }
        switch panose[0] {
        case 2:
            switch panose[1] {
            case 11...15: return .sansSerif
            case 2...10: return .serif
            default: return nil
            }
        case 3: return .script
        case 4: return .display
        case 5: return .symbol
        default: return nil
        }
    }

    /// Whole-word hints in the family and style names.
    static func nameCategory(_ facts: FontFacts) -> FontCategory? {
        let words = Set(
            "\(facts.familyName) \(facts.styleName)".lowercased()
                .split(whereSeparator: { !$0.isLetter }).map(String.init)
        )
        func has(_ hints: [String]) -> Bool { hints.contains { words.contains($0) } }
        if has(["mono", "monospace", "monospaced", "code", "console"]) { return .monospaced }
        if has(["sans", "grotesk", "grotesque", "gothic"]) { return .sansSerif }
        if has(["serif", "slab", "antiqua"]) { return .serif }
        if has(["script", "hand", "handwriting", "brush", "calligraphy", "calligraphic"]) { return .script }
        if has(["display", "poster", "stencil", "inline", "shadow"]) { return .display }
        if has(["symbol", "symbols", "dingbat", "dingbats", "ornament", "ornaments", "icons", "emoji"]) { return .symbol }
        return nil
    }
}
