import Foundation

/// The cheap facts about a face that the system lists for every font (no file access).
public struct SystemFace: Sendable, Equatable {
    public var postScriptName: String
    public var familyName: String
    public var displayFamilyName: String
    public var styleName: String
    public var fullName: String
    public var path: String?
    public var isEnabled: Bool
    public var weight: Double
    public var width: Double
    public var slant: Double
    public var isItalic: Bool
    public var isMonospaceTrait: Bool
    public var stylisticClass: Int
    public var format: String

    public init(postScriptName: String, familyName: String, displayFamilyName: String? = nil, styleName: String,
                fullName: String? = nil, path: String?, isEnabled: Bool = true, weight: Double = 0, width: Double = 0,
                slant: Double = 0, isItalic: Bool = false, isMonospaceTrait: Bool = false, stylisticClass: Int = 0,
                format: String = "OpenType") {
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
        self.isMonospaceTrait = isMonospaceTrait
        self.stylisticClass = stylisticClass
        self.format = format
    }

    public var id: String { FontFace.makeID(postScriptName: postScriptName, path: path) }
}

/// The slower facts that need the font itself (tables, character set, axes). Cached on disk.
public struct FaceDetails: Codable, Sendable, Equatable {
    public var panose: [UInt8]?
    public var equalAdvances: Bool?
    public var coversBasicLatin: Bool
    public var hasColorGlyphs: Bool
    public var axes: [VariationAxis]
    /// The font's manufacturer name (foundry), for the list view and sorting.
    public var foundry: String?
    /// The font's version string, cleaned ("1.000" from "Version 1.000;...").
    public var version: String?

    public init(panose: [UInt8]? = nil, equalAdvances: Bool? = nil, coversBasicLatin: Bool = true,
                hasColorGlyphs: Bool = false, axes: [VariationAxis] = [], foundry: String? = nil, version: String? = nil) {
        self.panose = panose
        self.equalAdvances = equalAdvances
        self.coversBasicLatin = coversBasicLatin
        self.hasColorGlyphs = hasColorGlyphs
        self.axes = axes
        self.foundry = foundry
        self.version = version
    }
}

/// The system's font registry. `CoreTextFontSystem` in the app; a fake in tests.
public protocol FontSystem: Sendable {
    /// Every face, including disabled ones. Hidden faces (names starting with ".") excluded.
    func listFaces() -> [SystemFace]
    func details(for face: SystemFace) -> FaceDetails
    /// File modification date, used to know when cached details are stale.
    func modificationDate(path: String) -> Date?
    /// Turns faces on or off (the switch Font Book uses). No error return: re-list to verify.
    func setEnabled(_ faces: [FontFace], enabled: Bool)
}
