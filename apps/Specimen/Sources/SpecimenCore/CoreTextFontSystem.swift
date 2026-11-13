import CoreText
import Foundation

/// The real font registry, through CoreText. Thread-safe; call off the main actor.
public struct CoreTextFontSystem: FontSystem {
    public init() {}

    public func listFaces() -> [SystemFace] {
        let all = Self.descriptors(includeDisabled: true)
        // `kCTFontEnabledAttribute` goes stale for faces turned off while running (and the
        // include-disabled list can repeat them), so "enabled" means "in the enabled-only list".
        var enabled = Set<String>()
        for descriptor in Self.descriptors(includeDisabled: false) {
            guard let name = Self.string(descriptor, kCTFontNameAttribute) else { continue }
            enabled.insert(FontFace.makeID(postScriptName: name, path: Self.path(descriptor)))
        }
        var seen = Set<String>()
        var faces: [SystemFace] = []
        faces.reserveCapacity(all.count)
        for descriptor in all {
            guard let face = Self.face(from: descriptor, path: Self.path(descriptor), isEnabled: nil),
                  seen.insert(face.id).inserted else { continue }
            var listed = face
            listed.isEnabled = enabled.contains(face.id)
            faces.append(listed)
        }
        return faces
    }

    /// The cheap facts from one descriptor. Hidden (dot-named) faces give nil. `isEnabled` nil
    /// means "not known here" (set by the caller).
    public static func face(from descriptor: CTFontDescriptor, path: String?, isEnabled: Bool?) -> SystemFace? {
        guard let name = string(descriptor, kCTFontNameAttribute),
              let family = string(descriptor, kCTFontFamilyNameAttribute),
              !name.hasPrefix("."), !family.hasPrefix(".") else { return nil }
        let traits = CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute) as? [CFString: Any] ?? [:]
        let symbolic = (traits[kCTFontSymbolicTrait] as? NSNumber)?.uint32Value ?? 0
        let style = string(descriptor, kCTFontStyleNameAttribute) ?? "Regular"
        let display = CTFontDescriptorCopyLocalizedAttribute(descriptor, kCTFontFamilyNameAttribute, nil) as? String
        return SystemFace(
            postScriptName: name,
            familyName: family,
            displayFamilyName: display ?? family,
            styleName: style,
            fullName: string(descriptor, kCTFontDisplayNameAttribute) ?? "\(family) \(style)",
            path: path,
            isEnabled: isEnabled ?? false,
            weight: (traits[kCTFontWeightTrait] as? NSNumber)?.doubleValue ?? 0,
            width: (traits[kCTFontWidthTrait] as? NSNumber)?.doubleValue ?? 0,
            slant: (traits[kCTFontSlantTrait] as? NSNumber)?.doubleValue ?? 0,
            isItalic: symbolic & CTFontSymbolicTraits.traitItalic.rawValue != 0,
            isMonospaceTrait: symbolic & CTFontSymbolicTraits.traitMonoSpace.rawValue != 0,
            stylisticClass: Int((symbolic & CTFontSymbolicTraits.traitClassMask.rawValue) >> 28),
            format: format(descriptor, path: path)
        )
    }

    /// Every face in a font file (unregistered or not), read straight from the file.
    public static func faces(inFile path: String) -> [SystemFace] {
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(URL(fileURLWithPath: path) as CFURL) as? [CTFontDescriptor] ?? []
        var seen = Set<String>()
        return descriptors.compactMap { face(from: $0, path: path, isEnabled: false) }.filter { seen.insert($0.postScriptName).inserted }
    }

    public func details(for face: SystemFace) -> FaceDetails {
        guard let font = FontLoader.makeFont(postScriptName: face.postScriptName, path: face.path,
                                             isEnabled: face.isEnabled, size: 24) else { return FaceDetails() }
        let tables = Self.tableTags(font)
        let hasColor = [kCTFontTableSbix, kCTFontTableCOLR, 0x4342_4454 /* CBDT */].contains { tables.contains(UInt32($0)) }
        var panose: [UInt8]?
        if let os2 = CTFontCopyTable(font, CTFontTableTag(kCTFontTableOS2), []) as Data?, os2.count >= 42 {
            panose = Array(os2[32..<42])
        }
        let latin = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: latin.count)
        _ = CTFontGetGlyphsForCharacters(font, latin, &glyphs, latin.count)
        let covered = glyphs.filter { $0 != 0 }.count
        let coversLatin = covered >= latin.count * 9 / 10
        var equalAdvances: Bool?
        if coversLatin {
            let probe = Array("imW".utf16)
            var probeGlyphs = [CGGlyph](repeating: 0, count: 3)
            if CTFontGetGlyphsForCharacters(font, probe, &probeGlyphs, 3) {
                var advances = [CGSize](repeating: .zero, count: 3)
                CTFontGetAdvancesForGlyphs(font, .horizontal, probeGlyphs, &advances, 3)
                equalAdvances = abs(advances[0].width - advances[1].width) < 0.01 && abs(advances[1].width - advances[2].width) < 0.01
            }
        }
        let axes = (CTFontCopyVariationAxes(font) as? [[CFString: Any]] ?? []).compactMap { axis -> VariationAxis? in
            guard let identifier = (axis[kCTFontVariationAxisIdentifierKey] as? NSNumber)?.intValue else { return nil }
            let tag = VariationAxis.tag(from: identifier)
            return VariationAxis(
                tag: tag,
                name: axis[kCTFontVariationAxisNameKey] as? String ?? tag,
                minimum: (axis[kCTFontVariationAxisMinimumValueKey] as? NSNumber)?.doubleValue ?? 0,
                maximum: (axis[kCTFontVariationAxisMaximumValueKey] as? NSNumber)?.doubleValue ?? 0,
                defaultValue: (axis[kCTFontVariationAxisDefaultValueKey] as? NSNumber)?.doubleValue ?? 0
            )
        }
        func name(_ key: CFString) -> String? {
            (CTFontCopyName(font, key) as String?).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        }
        return FaceDetails(panose: panose, equalAdvances: equalAdvances, coversBasicLatin: coversLatin,
                           hasColorGlyphs: hasColor, axes: axes, foundry: name(kCTFontManufacturerNameKey),
                           version: name(kCTFontVersionNameKey).map(FontFormat.shortVersion))
    }

    public func modificationDate(path: String) -> Date? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
    }

    public func setEnabled(_ faces: [FontFace], enabled: Bool) {
        let descriptors = faces.compactMap { FontLoader.fileDescriptor(postScriptName: $0.postScriptName, path: $0.path) }
        guard !descriptors.isEmpty else { return }
        CTFontManagerEnableFontDescriptors(descriptors as CFArray, enabled)
    }

    // MARK: Helpers

    /// The font's table tags. The array holds raw tag values, not objects, so it can't be bridged.
    static func tableTags(_ font: CTFont) -> Set<UInt32> {
        guard let array = CTFontCopyAvailableTables(font, []) else { return [] }
        var tags = Set<UInt32>()
        for index in 0..<CFArrayGetCount(array) {
            tags.insert(UInt32(truncatingIfNeeded: Int(bitPattern: CFArrayGetValueAtIndex(array, index))))
        }
        return tags
    }

    static func descriptors(includeDisabled: Bool) -> [CTFontDescriptor] {
        let options = includeDisabled ? [kCTFontCollectionIncludeDisabledFontsOption: true] as CFDictionary : nil
        let collection = CTFontCollectionCreateFromAvailableFonts(options)
        return CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor] ?? []
    }

    static func string(_ descriptor: CTFontDescriptor, _ key: CFString) -> String? {
        CTFontDescriptorCopyAttribute(descriptor, key) as? String
    }

    static func path(_ descriptor: CTFontDescriptor) -> String? {
        (CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL)?.path
    }

    /// A rough kind from the file name. (Asking CoreText for the format opens every font file:
    /// about 40 MB for 666 faces. The Info section reads the exact format for one face.)
    static func format(_ descriptor: CTFontDescriptor, path: String?) -> String {
        FontFormat.kind(forExtension: (path as NSString?)?.pathExtension ?? "")
    }
}

public enum FontFormat {
    public static func kind(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "ttc", "otc": "Font collection"
        case "otf": "OpenType"
        case "ttf": "TrueType"
        case "dfont": "Data-fork suitcase"
        case "pfb", "pfa", "lwfn": "PostScript Type 1"
        case "woff", "woff2": "Web font"
        case "": "Font suitcase"
        default: ext.uppercased()
        }
    }

    /// "Version 1.000;PS 001.000;hotconv" → "1.000".
    public static func shortVersion(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if text.lowercased().hasPrefix("version") { text = String(text.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
        let cut = text.firstIndex { $0 == ";" || $0 == " " } ?? text.endIndex
        let short = String(text[..<cut])
        return short.isEmpty ? raw : short
    }

    /// The exact format of a loaded font.
    public static func describe(_ font: CTFont) -> String? {
        let raw = (CTFontCopyAttribute(font, kCTFontFormatAttribute) as? NSNumber)?.uint32Value
        switch raw.flatMap(CTFontFormat.init(rawValue:)) {
        case .openTypePostScript: return "OpenType (PostScript outlines)"
        case .openTypeTrueType: return "OpenType (TrueType outlines)"
        case .trueType: return "TrueType"
        case .postScript: return "PostScript Type 1"
        case .bitmap: return "Bitmap"
        default: return nil
        }
    }
}

/// Makes CTFonts for faces, including disabled ones (which can't be found by name).
public enum FontLoader {
    /// By name when the face is the active copy; from its file otherwise.
    public static func makeFont(postScriptName: String, path: String?, isEnabled: Bool, size: CGFloat) -> CTFont? {
        if isEnabled {
            let font = CTFontCreateWithName(postScriptName as CFString, size, nil)
            let fontPath = (CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL)?.path
            if CTFontCopyPostScriptName(font) as String == postScriptName, path == nil || fontPath == path {
                return font
            }
        }
        guard let descriptor = fileDescriptor(postScriptName: postScriptName, path: path) else { return nil }
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    /// A descriptor read straight from the font file, matched by PostScript name.
    public static func fileDescriptor(postScriptName: String, path: String?) -> CTFontDescriptor? {
        guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(URL(fileURLWithPath: path) as CFURL) as? [CTFontDescriptor] ?? []
        return descriptors.first { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String == postScriptName }
            ?? (descriptors.count == 1 ? descriptors.first : nil)
    }
}
