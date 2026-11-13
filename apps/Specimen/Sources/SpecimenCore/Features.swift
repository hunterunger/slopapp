import CoreText
import Foundation

// OpenType (and AAT) features, as CoreText reports them per font (`CTFontCopyFeatures`):
// feature types ("Ligatures", "Number Case", "Stylistic Set 3") with selectors. Exclusive types
// are a choice of one selector; the others are on/off switches. CoreText maps OpenType tags
// to these types for OpenType fonts (and lists unmapped tags like `cv01` under their tag), so
// the same model covers Apple's AAT fonts and OpenType fonts.

public struct FeatureSelector: Hashable, Sendable {
    /// AAT selector identifier (for non-exclusive types, "on"; "off" is this + 1).
    public var id: Int
    public var name: String
    public var isDefault: Bool
    public var openTypeTag: String?
    public var openTypeValue: Int?

    public init(id: Int, name: String, isDefault: Bool = false, openTypeTag: String? = nil, openTypeValue: Int? = nil) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.openTypeTag = openTypeTag
        self.openTypeValue = openTypeValue
    }
}

public enum FeatureGroup: String, CaseIterable, Sendable {
    case ligatures, letterCase, figures, position, alternates, stylisticSets, characterVariants, other

    public var title: String {
        switch self {
        case .ligatures: "Ligatures"
        case .letterCase: "Letter Case"
        case .figures: "Figures"
        case .position: "Fractions and Position"
        case .alternates: "Alternates and Swashes"
        case .stylisticSets: "Stylistic Sets"
        case .characterVariants: "Character Variants"
        case .other: "Other"
        }
    }
}

public struct FontFeatureType: Hashable, Sendable, Identifiable {
    /// AAT type identifier; nil for OpenType features CoreText lists only by tag (`cv01`).
    public var typeID: Int?
    public var name: String
    public var isExclusive: Bool
    public var selectors: [FeatureSelector]

    public init(typeID: Int?, name: String, isExclusive: Bool, selectors: [FeatureSelector]) {
        self.typeID = typeID
        self.name = name
        self.isExclusive = isExclusive
        self.selectors = selectors
    }

    /// Stable key across faces of a family: the AAT type, or the OpenType tag.
    public var id: String {
        if let typeID { return "t\(typeID)" }
        return "ot:" + (selectors.compactMap(\.openTypeTag).first ?? name)
    }

    /// The tag of a tag-only type ("cv01").
    public var tag: String? { typeID == nil ? selectors.compactMap(\.openTypeTag).first : nil }

    public var defaultSelector: FeatureSelector? {
        selectors.first(where: \.isDefault) ?? (isExclusive ? selectors.first : nil)
    }

    public var group: FeatureGroup { FeatureCatalog.group(for: self) }

    /// A friendlier title for tag-only types ("Character Variant 1" for "'cv01'").
    public var title: String { FeatureCatalog.title(for: self) }
}

/// What the user changed, per type. Only differences from each type's default are stored.
public struct FeatureSettings: Hashable, Sendable {
    /// Exclusive types: type id → chosen selector id.
    public private(set) var choices: [String: Int] = [:]
    /// Switches: "type id/selector id" → on or off.
    public private(set) var switches: [String: Bool] = [:]

    public init() {}

    public var isDefault: Bool { choices.isEmpty && switches.isEmpty }
    public var changeCount: Int { choices.count + switches.count }

    public mutating func reset() {
        choices = [:]
        switches = [:]
    }

    static func key(_ type: FontFeatureType, _ selector: FeatureSelector) -> String { "\(type.id)/\(selector.id)" }

    public func isOn(_ selector: FeatureSelector, in type: FontFeatureType) -> Bool {
        if type.isExclusive { return chosen(in: type)?.id == selector.id }
        return switches[Self.key(type, selector)] ?? selector.isDefault
    }

    public func chosen(in type: FontFeatureType) -> FeatureSelector? {
        if let id = choices[type.id], let selector = type.selectors.first(where: { $0.id == id }) { return selector }
        return type.defaultSelector
    }

    /// Turns a switch on or off. Exclusive types: on picks it, off goes back to the default.
    public mutating func set(_ selector: FeatureSelector, in type: FontFeatureType, on: Bool) {
        if type.isExclusive {
            choose(on ? selector : type.defaultSelector, in: type)
            return
        }
        let key = Self.key(type, selector)
        switches[key] = on == selector.isDefault ? nil : on
    }

    public mutating func choose(_ selector: FeatureSelector?, in type: FontFeatureType) {
        guard let selector, selector.id != type.defaultSelector?.id else {
            choices[type.id] = nil
            return
        }
        choices[type.id] = selector.id
    }

    /// The settings CoreText needs, for the types the font has.
    public func values(for types: [FontFeatureType]) -> [FeatureValue] {
        var result: [FeatureValue] = []
        for type in types {
            if type.isExclusive {
                guard choices[type.id] != nil, let selector = chosen(in: type) else { continue }
                result.append(FeatureValue(typeID: type.typeID, selectorID: selector.id,
                                           tag: selector.openTypeTag, value: selector.openTypeValue ?? 1))
            } else {
                for selector in type.selectors {
                    guard let on = switches[Self.key(type, selector)] else { continue }
                    // AAT: "off" is the selector after "on".
                    result.append(FeatureValue(typeID: type.typeID, selectorID: on ? selector.id : selector.id + 1,
                                               tag: selector.openTypeTag, value: on ? (selector.openTypeValue ?? 1) : 0))
                }
            }
        }
        return result
    }

    /// `font-feature-settings: "ss01", "liga" 0;` for the changed features with an OpenType
    /// equivalent. Nil when nothing maps.
    public func css(for types: [FontFeatureType]) -> String? {
        let parts = values(for: types).compactMap { value -> String? in
            guard let (tag, number) = FeatureCatalog.openType(for: value) else { return nil }
            return number == 1 ? "\"\(tag)\"" : "\"\(tag)\" \(number)"
        }
        return parts.isEmpty ? nil : "font-feature-settings: \(parts.joined(separator: ", "));"
    }
}

/// One feature setting for CoreText: by OpenType tag when there is one, else by AAT ids.
public struct FeatureValue: Hashable, Sendable {
    public var typeID: Int?
    public var selectorID: Int
    public var tag: String?
    public var value: Int

    public init(typeID: Int?, selectorID: Int, tag: String?, value: Int) {
        self.typeID = typeID
        self.selectorID = selectorID
        self.tag = tag
        self.value = value
    }

    /// For `kCTFontFeatureSettingsAttribute`.
    public var coreTextSetting: [String: Any] {
        if let tag { return [kCTFontOpenTypeFeatureTag as String: tag, kCTFontOpenTypeFeatureValue as String: value] }
        return [kCTFontFeatureTypeIdentifierKey as String: typeID ?? 0, kCTFontFeatureSelectorIdentifierKey as String: selectorID]
    }

    /// A short stable key for caches.
    public var cacheKey: String { tag.map { "\($0)=\(value)" } ?? "\(typeID ?? 0):\(selectorID)" }
}

public enum FeatureCatalog {
    // AAT feature type identifiers (SFNTLayoutTypes.h).
    static let allTypographic = 0, ligatures = 1, letterCase = 3, verticalSubstitution = 4, linguisticRearrangement = 5
    static let numberSpacing = 6, smartSwash = 8, diacritics = 9, verticalPosition = 10, fractions = 11
    static let overlappingCharacters = 13, typographicExtras = 14, mathematicalExtras = 15, ornamentSets = 16
    static let characterAlternatives = 17, designComplexity = 18, styleOptions = 19, characterShape = 20
    static let numberCase = 21, textSpacing = 22, transliteration = 23, annotation = 24, kanaSpacing = 25
    static let ideographicSpacing = 26, unicodeDecomposition = 27, rubyKana = 28, cjkSymbolAlternatives = 29
    static let ideographicAlternatives = 30, cjkVerticalRomanPlacement = 31, italicCJKRoman = 32
    static let caseSensitiveLayout = 33, alternateKana = 34, stylisticAlternatives = 35, contextualAlternates = 36
    static let lowerCase = 37, upperCase = 38, languageTag = 39, cjkRomanSpacing = 103

    /// Types and tags that aren't user-facing (shaping, required, vertical, CJK layout).
    static let hiddenTypes: Set<Int> = [allTypographic, verticalSubstitution, linguisticRearrangement, unicodeDecomposition,
                                        languageTag, annotation, kanaSpacing, ideographicSpacing, rubyKana,
                                        cjkVerticalRomanPlacement, italicCJKRoman, alternateKana, cjkRomanSpacing, overlappingCharacters]
    static let hiddenTags: Set<String> = [
        "REQD", "ccmp", "locl", "mark", "mkmk", "rlig", "rclt", "init", "medi", "fina", "isol", "med2", "fin2", "fin3",
        "abvs", "blws", "akhn", "half", "haln", "pres", "psts", "nukt", "rphf", "blwf", "pstf", "vatu", "cjct", "abvm",
        "blwm", "dist", "curs", "rvrn", "ltra", "ltrm", "rtla", "rtlm", "vert", "vrt2", "vkrn", "valt", "vhal",
        "vpal", "vrtr", "vjmo", "ljmo", "tjmo", "dtls", "flac", "ssty", "mset", "stch", "dpng",
    ]

    /// Whether a type is worth a control: user-facing, and something to choose between.
    public static func isUserFacing(_ type: FontFeatureType) -> Bool {
        if let id = type.typeID, hiddenTypes.contains(id) { return false }
        if let tag = type.tag, hiddenTags.contains(tag) { return false }
        // Required ligatures can't be turned off.
        let selectors = type.selectors.filter { !(type.typeID == ligatures && $0.id == 0) }
        return type.isExclusive ? selectors.count > 1 : !selectors.isEmpty
    }

    public static func group(for type: FontFeatureType) -> FeatureGroup {
        if let tag = type.tag ?? type.selectors.compactMap(\.openTypeTag).first {
            if tag.hasPrefix("ss"), Int(tag.dropFirst(2)) != nil { return .stylisticSets }
            if tag.hasPrefix("cv"), Int(tag.dropFirst(2)) != nil { return .characterVariants }
        }
        switch type.typeID {
        case ligatures?: return .ligatures
        case letterCase?, lowerCase?, upperCase?, caseSensitiveLayout?: return .letterCase
        case numberSpacing?, numberCase?: return .figures
        case typographicExtras? where type.selectors.contains(where: { $0.openTypeTag == "zero" || $0.id == 4 }): return .figures
        case fractions?, verticalPosition?, mathematicalExtras?: return .position
        case smartSwash?, characterAlternatives?, contextualAlternates?, styleOptions?, ornamentSets?, designComplexity?, characterShape?:
            return .alternates
        case stylisticAlternatives?: return .stylisticSets
        default: return .other
        }
    }

    public static func title(for type: FontFeatureType) -> String {
        guard let tag = type.tag else { return type.name }
        if tag.hasPrefix("cv"), let number = Int(tag.dropFirst(2)) { return "Character Variant \(number)" }
        if tag.hasPrefix("ss"), let number = Int(tag.dropFirst(2)) { return "Stylistic Set \(number)" }
        if let known = knownTitles[tag] { return known }
        return type.name.trimmingCharacters(in: CharacterSet(charactersIn: "' "))
    }

    /// The label for a switch that's the type's only choice: the selector's name, unless it's
    /// just "On", or two types would both say "Small Capitals".
    public static func label(for selector: FeatureSelector, in type: FontFeatureType) -> String {
        if ["on", "1"].contains(selector.name.lowercased()) { return type.title }
        switch (type.typeID, selector.id) {
        case (lowerCase?, 1): return "Small Capitals"
        case (lowerCase?, 2): return "Petite Capitals"
        case (upperCase?, 1): return "Capitals to Small Capitals"
        case (upperCase?, 2): return "Capitals to Petite Capitals"
        default: return selector.name
        }
    }

    static let knownTitles: [String: String] = [
        "salt": "Stylistic Alternates", "swsh": "Swashes", "cswh": "Contextual Swashes", "titl": "Titling",
        "hist": "Historical Forms", "nalt": "Alternate Annotation", "zero": "Slashed Zero", "case": "Case-Sensitive Forms",
        "calt": "Contextual Alternates", "aalt": "Access All Alternates", "frac": "Fractions", "ordn": "Ordinals",
    ]

    /// The OpenType tag and value a setting stands for, for CSS. AAT-only fonts' settings map
    /// through Apple's table of equivalents.
    public static func openType(for value: FeatureValue) -> (String, Int)? {
        if let tag = value.tag { return (tag, value.value) }
        guard let type = value.typeID else { return nil }
        let selector = value.selectorID
        switch (type, selector) {
        case (ligatures, 2): return ("liga", 1)
        case (ligatures, 3): return ("liga", 0)
        case (ligatures, 4): return ("dlig", 1)
        case (ligatures, 5): return ("dlig", 0)
        case (ligatures, 18): return ("clig", 1)
        case (ligatures, 19): return ("clig", 0)
        case (ligatures, 20): return ("hlig", 1)
        case (ligatures, 21): return ("hlig", 0)
        case (letterCase, 3): return ("smcp", 1)
        case (numberSpacing, 0): return ("tnum", 1)
        case (numberSpacing, 1): return ("pnum", 1)
        case (verticalPosition, 1): return ("sups", 1)
        case (verticalPosition, 2): return ("subs", 1)
        case (verticalPosition, 3): return ("ordn", 1)
        case (verticalPosition, 4): return ("sinf", 1)
        case (fractions, 1): return ("afrc", 1)
        case (fractions, 2): return ("frac", 1)
        case (typographicExtras, 4): return ("zero", 1)
        case (typographicExtras, 5): return ("zero", 0)
        case (numberCase, 0): return ("onum", 1)
        case (numberCase, 1): return ("lnum", 1)
        case (caseSensitiveLayout, 0): return ("case", 1)
        case (caseSensitiveLayout, 1): return ("case", 0)
        case (contextualAlternates, 0): return ("calt", 1)
        case (contextualAlternates, 1): return ("calt", 0)
        case (contextualAlternates, 2): return ("swsh", 1)
        case (contextualAlternates, 3): return ("swsh", 0)
        case (contextualAlternates, 4): return ("cswh", 1)
        case (contextualAlternates, 5): return ("cswh", 0)
        case (lowerCase, 1): return ("smcp", 1)
        case (lowerCase, 2): return ("pcap", 1)
        case (upperCase, 1): return ("c2sc", 1)
        case (upperCase, 2): return ("c2pc", 1)
        case (styleOptions, 4): return ("titl", 1)
        case (characterAlternatives, let n) where n > 0: return ("salt", n)
        case (stylisticAlternatives, let n) where n >= 2 && n <= 41:
            let set = n / 2
            return (String(format: "ss%02d", set), n % 2 == 0 ? 1 : 0)
        default: return nil
        }
    }

    /// Text that shows what a feature does, when the preview text may not.
    public static func sample(for type: FontFeatureType, previewText: String) -> String {
        let own = previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch type.typeID {
        case ligatures?: return "fi fl ff ffi ffl Th ct st"
        case letterCase?, lowerCase?: return "Small Caps 2026"
        case upperCase?: return "NASA, USA and BBC"
        case caseSensitiveLayout?: return "(HELLO) [H-O] {A}·B"
        case numberSpacing?: return "1111 · 0000 · 1234567890"
        case numberCase?: return "Since 1984 to 2026: 0123456789"
        case fractions?: return "1/2 3/4 5/8 7/16"
        case verticalPosition?: return "x2 H2O 1st 2nd Mme"
        case typographicExtras?: return "0 O 100 0.05"
        default: break
        }
        if type.tag == "zero" { return "0 O 100 0.05" }
        if type.tag == "frac" { return "1/2 3/4 5/8" }
        return own.isEmpty ? "The quick brown fox jumps over the lazy dog 0123456789" : own
    }

    // MARK: Reading a font

    /// The user-facing feature types of a font, from `CTFontCopyFeatures`.
    public static func types(of font: CTFont) -> [FontFeatureType] {
        let raw = CTFontCopyFeatures(font) as? [[String: Any]] ?? []
        return types(fromCoreText: raw)
    }

    /// Parses `CTFontCopyFeatures` output (pure, for tests).
    public static func types(fromCoreText raw: [[String: Any]]) -> [FontFeatureType] {
        var seen = Set<String>()
        return raw.compactMap { entry -> FontFeatureType? in
            let list = entry[kCTFontFeatureTypeSelectorsKey as String] as? [[String: Any]] ?? []
            let selectors = list.enumerated().map { index, selector -> FeatureSelector in
                // Tag-only features (cv01) come without selector ids; they're applied by tag.
                let id = (selector[kCTFontFeatureSelectorIdentifierKey as String] as? NSNumber)?.intValue ?? index
                return FeatureSelector(
                    id: id,
                    name: selector[kCTFontFeatureSelectorNameKey as String] as? String ?? "\(id)",
                    isDefault: (selector[kCTFontFeatureSelectorDefaultKey as String] as? NSNumber)?.boolValue ?? false,
                    openTypeTag: selector[kCTFontOpenTypeFeatureTag as String] as? String,
                    openTypeValue: (selector[kCTFontOpenTypeFeatureValue as String] as? NSNumber)?.intValue
                )
            }
            let type = FontFeatureType(
                typeID: (entry[kCTFontFeatureTypeIdentifierKey as String] as? NSNumber)?.intValue,
                name: entry[kCTFontFeatureTypeNameKey as String] as? String ?? "Feature",
                isExclusive: (entry[kCTFontFeatureTypeExclusiveKey as String] as? NSNumber)?.boolValue ?? false,
                selectors: selectors
            )
            guard isUserFacing(type), seen.insert(type.id).inserted else { return nil }
            return type
        }
    }
}
