import Foundation

/// One font face (one PostScript name in one file), as indexed from the system.
public struct FontFace: Codable, Hashable, Sendable, Identifiable {
    /// Unique per face: PostScript name plus file path (two files can share a PostScript name).
    public var id: String
    public var postScriptName: String
    public var familyName: String
    /// The family name in the user's language, when the font has one.
    public var displayFamilyName: String
    public var styleName: String
    public var fullName: String
    public var path: String?
    public var isEnabled: Bool
    /// Weight trait, -1 (thinnest) ... 0 (regular) ... 1 (heaviest).
    public var weight: Double
    public var width: Double
    public var slant: Double
    public var isItalic: Bool
    public var isVariable: Bool
    public var axes: [VariationAxis]
    public var format: String
    public var category: FontCategory
    /// The font maps most of A–Z and a–z.
    public var coversBasicLatin: Bool
    public var hasColorGlyphs: Bool
    public var fileModified: Date?
    /// Manufacturer (foundry) and version from the font's name table, when it has them.
    public var foundry: String?
    public var version: String?

    public init(
        postScriptName: String, familyName: String, displayFamilyName: String? = nil, styleName: String,
        fullName: String? = nil, path: String?, isEnabled: Bool = true, weight: Double = 0, width: Double = 0,
        slant: Double = 0, isItalic: Bool = false, isVariable: Bool = false, axes: [VariationAxis] = [],
        format: String = "OpenType", category: FontCategory = .other, coversBasicLatin: Bool = true,
        hasColorGlyphs: Bool = false, fileModified: Date? = nil, foundry: String? = nil, version: String? = nil
    ) {
        self.id = FontFace.makeID(postScriptName: postScriptName, path: path)
        self.postScriptName = postScriptName
        self.familyName = familyName
        self.displayFamilyName = displayFamilyName ?? familyName
        self.styleName = styleName
        self.fullName = fullName ?? "\(familyName) \(styleName)"
        self.path = path
        self.isEnabled = isEnabled
        self.weight = weight
        self.width = width
        self.slant = slant
        self.isItalic = isItalic
        self.isVariable = isVariable
        self.axes = axes
        self.format = format
        self.category = category
        self.coversBasicLatin = coversBasicLatin
        self.hasColorGlyphs = hasColorGlyphs
        self.fileModified = fileModified
        self.foundry = foundry
        self.version = version
    }

    public static func makeID(postScriptName: String, path: String?) -> String {
        "\(postScriptName)|\(path ?? "")"
    }

    public var location: FontLocation { FontLocation(path: path) }

    /// How far this face is from a plain Regular: used to pick a family's representative.
    /// CSS-style weight (100...900) from CoreText's -1...1 weight trait.
    public var cssWeight: Int {
        FontFace.cssWeight(fromTrait: weight)
    }

    /// Maps CoreText's weight trait to the nearest CSS weight. CoreText's table: 100 -0.8,
    /// 200 -0.6, 300 -0.4, 400 0, 500 0.23, 600 0.3, 700 0.4, 800 0.56, 900 0.62.
    public static func cssWeight(fromTrait trait: Double) -> Int {
        let table: [(Double, Int)] = [(-0.8, 100), (-0.6, 200), (-0.4, 300), (0, 400), (0.23, 500), (0.3, 600), (0.4, 700), (0.56, 800), (0.62, 900)]
        return table.min { abs($0.0 - trait) < abs($1.0 - trait) }?.1 ?? 400
    }

    public var distanceFromRegular: Double {
        abs(weight) * 4 + abs(width) * 2 + (isItalic || abs(slant) > 0.01 ? 3 : 0)
    }
}

/// A variation axis of a variable font (weight, width, optical size, ...).
public struct VariationAxis: Codable, Hashable, Sendable {
    public var tag: String
    public var name: String
    public var minimum: Double
    public var maximum: Double
    public var defaultValue: Double

    public init(tag: String, name: String, minimum: Double, maximum: Double, defaultValue: Double) {
        self.tag = tag
        self.name = name
        self.minimum = minimum
        self.maximum = maximum
        self.defaultValue = defaultValue
    }

    /// "Weight 100–900".
    public var summary: String {
        "\(name) \(Self.format(minimum))–\(Self.format(maximum))"
    }

    static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// Four-character tag from CoreText's integer identifier ('wght' etc.).
    public static func tag(from identifier: Int) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((identifier >> $0) & 0xFF) }
        guard bytes.allSatisfy({ (0x20...0x7E).contains($0) }) else { return String(identifier) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// Where a font file lives, which decides whether Specimen may turn it on or off.
public enum FontLocation: String, Codable, Sendable {
    /// Ships with macOS (`/System/...`, including Apple's downloadable fonts).
    case system
    /// Installed for every user (`/Library/Fonts`, `/Network`). Changing them can need an administrator.
    case computer
    /// The user's own Fonts folder.
    case user
    /// Anywhere else (fonts registered by apps or from a folder).
    case other

    public init(path: String?, home: String = NSHomeDirectory()) {
        guard let path else { self = .system; return }
        if path.hasPrefix("/System/") {
            self = .system
        } else if path.hasPrefix("/Library/Fonts/") || path.hasPrefix("/Network/") || path.hasPrefix("/Library/Application Support/Apple/Fonts/") {
            self = .computer
        } else if path.hasPrefix(home + "/Library/Fonts/") {
            self = .user
        } else {
            self = .other
        }
    }

    public var title: String {
        switch self {
        case .system: "macOS"
        case .computer: "All users"
        case .user: "Your Fonts folder"
        case .other: "Other location"
        }
    }
}

/// The categories in the sidebar.
public enum FontCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case serif, sansSerif, monospaced, script, display, symbol, other, otherScripts

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .serif: "Serif"
        case .sansSerif: "Sans Serif"
        case .monospaced: "Monospaced"
        case .script: "Script"
        case .display: "Display"
        case .symbol: "Symbol"
        case .other: "Other"
        case .otherScripts: "Other Scripts"
        }
    }

    public var systemImage: String {
        switch self {
        case .serif: "textformat"
        case .sansSerif: "textformat.alt"
        case .monospaced: "chevron.left.forwardslash.chevron.right"
        case .script: "signature"
        case .display: "textformat.size.larger"
        case .symbol: "star.square"
        case .other: "questionmark.square.dashed"
        case .otherScripts: "globe"
        }
    }
}

/// Whether a family (or selection) is on, off, or a mix.
public enum ActivationState: Sendable, Equatable {
    case active, inactive, mixed

    public init(faces: [FontFace]) {
        let enabled = faces.filter(\.isEnabled).count
        self = enabled == faces.count ? .active : enabled == 0 ? .inactive : .mixed
    }

    public var title: String {
        switch self {
        case .active: "Active"
        case .inactive: "Inactive"
        case .mixed: "Partly active"
        }
    }
}
