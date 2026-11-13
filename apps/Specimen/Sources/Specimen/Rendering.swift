import AppKit
import CoreText
import SpecimenCore

/// Makes and caches fonts and typeset preview lines. Bounded caches: every live CTFont maps
/// its file, so an unbounded cache would grow without limit while scrolling a big library.
@MainActor
final class PreviewRenderer {
    static let shared = PreviewRenderer()

    private let baseFonts = NSCache<NSString, CTFont>()
    private let sizedFonts = NSCache<NSString, CTFont>()
    private let lines = NSCache<NSString, TypesetLine>()
    private let samples = NSCache<NSString, NSString>()
    private var unloadable = Set<String>()

    init() {
        // A full screen at 8 pt shows about 60 cards; keep a couple of screens' worth.
        // Each live font keeps its parsed tables in memory, so these stay small.
        baseFonts.countLimit = 80
        sizedFonts.countLimit = 100
        lines.countLimit = 240
        samples.countLimit = 300
    }

    func font(for face: FontFace, size: CGFloat, variation: [Int: Double] = [:], features: [FeatureValue] = []) -> CTFont? {
        let key = "\(face.id)@\(size)\(Self.variationKey(variation))\(Self.featureKey(features))" as NSString
        if let font = sizedFonts.object(forKey: key) { return font }
        guard let base = baseFont(for: face) else { return nil }
        var attributes: [CFString: Any] = [:]
        if !variation.isEmpty {
            // Start from the face's own position (a named instance), then move the axes.
            var merged = (CTFontCopyVariation(base) as? [NSNumber: NSNumber] ?? [:]).reduce(into: [Int: Double]()) {
                $0[$1.key.intValue] = $1.value.doubleValue
            }
            merged.merge(variation) { _, new in new }
            attributes[kCTFontVariationAttribute] = Dictionary(uniqueKeysWithValues: merged.map { (NSNumber(value: $0.key), NSNumber(value: $0.value)) })
        }
        if !features.isEmpty {
            attributes[kCTFontFeatureSettingsAttribute] = features.map(\.coreTextSetting)
        }
        let descriptor = attributes.isEmpty ? nil : CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        let font = CTFontCreateCopyWithAttributes(base, size, nil, descriptor)
        sizedFonts.setObject(font, forKey: key)
        return font
    }

    static func featureKey(_ features: [FeatureValue]) -> String {
        features.isEmpty ? "" : "|f:" + features.map(\.cacheKey).joined(separator: ",")
    }

    private var featureTypes: [String: [FontFeatureType]] = [:]

    /// The user-facing OpenType/AAT features of a face (read once per face).
    func featureTypes(for face: FontFace) -> [FontFeatureType] {
        if let cached = featureTypes[face.id] { return cached }
        let types = baseFont(for: face).map(FeatureCatalog.types(of:)) ?? []
        if featureTypes.count > 400 { featureTypes.removeAll() }
        featureTypes[face.id] = types
        return types
    }

    static func variationKey(_ variation: [Int: Double]) -> String {
        variation.isEmpty ? "" : "|" + variation.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    /// The face's own axis values (a named instance's position), as CoreText reports them.
    func variation(of face: FontFace) -> [Int: Double] {
        guard let base = baseFont(for: face) else { return [:] }
        return (CTFontCopyVariation(base) as? [NSNumber: NSNumber] ?? [:]).reduce(into: [Int: Double]()) {
            $0[$1.key.intValue] = $1.value.doubleValue
        }
    }

    private func baseFont(for face: FontFace) -> CTFont? {
        let key = face.id as NSString
        if let font = baseFonts.object(forKey: key) { return font }
        guard !unloadable.contains(face.id),
              let font = FontLoader.makeFont(postScriptName: face.postScriptName, path: face.path,
                                             isEnabled: face.isEnabled, size: 12) else {
            unloadable.insert(face.id)
            return nil
        }
        baseFonts.setObject(font, forKey: key)
        return font
    }

    /// One typeset line of `text` in `face`, truncated to `width`. Characters the font lacks
    /// are drawn faint (never silently in another font). If the font can't show most of the
    /// text, the line shows a sample of the font's own characters instead.
    func line(for face: FontFace, text: String, size: CGFloat, width: CGFloat, allowSample: Bool = true,
              variation: [Int: Double] = [:], features: [FeatureValue] = []) -> TypesetLine {
        let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let key = "\(face.id)|\(size)|\(Int(width))|\(dark)|\(allowSample)\(Self.variationKey(variation))\(Self.featureKey(features))|\(text)" as NSString
        if let cached = lines.object(forKey: key) { return cached }
        let result = typeset(face: face, text: text, size: size, width: width, allowSample: allowSample, variation: variation, features: features)
        lines.setObject(result, forKey: key)
        return result
    }

    private func typeset(face: FontFace, text: String, size: CGFloat, width: CGFloat, allowSample: Bool,
                         variation: [Int: Double], features: [FeatureValue]) -> TypesetLine {
        guard let font = font(for: face, size: size, variation: variation, features: features) else {
            return TypesetLine(line: nil, ascent: size, descent: size * 0.3, missing: 0, isSample: false, unavailable: true, width: 0)
        }
        var runs = PreviewText.runs(text) { units in
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            return CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count)
        }
        var isSample = false
        if allowSample, PreviewText.coverage(runs) < PreviewText.sampleThreshold {
            let sample = sampleText(for: face, font: font)
            if !sample.isEmpty {
                runs = [(sample, true)]
                isSample = true
            }
        }
        let missingColor = NSColor.tertiaryLabelColor.cgColor
        let textColor = NSColor.labelColor.cgColor
        let attributed = NSMutableAttributedString()
        let fallback = CTFontCreateUIFontForLanguage(.system, size, nil) ?? font
        for run in runs {
            var attributes: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): run.covered ? font : fallback]
            // Explicit colours on every run: a run with its own colour leaves the context's
            // fill colour changed, so "colour from context" runs after it would inherit it.
            attributes[.init(kCTForegroundColorAttributeName as String)] = run.covered ? textColor : missingColor
            attributed.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        var line = CTLineCreateWithAttributedString(attributed)
        if CTLineGetTypographicBounds(line, nil, nil, nil) > Double(width), width > 0 {
            let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: [
                .init(kCTFontAttributeName as String): font,
                .init(kCTForegroundColorAttributeName as String): textColor,
            ]))
            line = CTLineCreateTruncatedLine(line, Double(width), .end, token) ?? line
        }
        return TypesetLine(line: line, ascent: CTFontGetAscent(font), descent: CTFontGetDescent(font),
                           missing: isSample ? 0 : PreviewText.missingCount(runs), isSample: isSample, unavailable: false,
                           width: CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
    }

    private func sampleText(for face: FontFace, font: CTFont) -> String {
        let key = face.id as NSString
        if let cached = samples.object(forKey: key) { return cached as String }
        let set = CTFontCopyCharacterSet(font)
        let sample = PreviewText.sample(hasColorGlyphs: face.hasColorGlyphs) { CFCharacterSetIsLongCharacterMember(set, $0) }
        samples.setObject(sample as NSString, forKey: key)
        return sample
    }

    /// Empties every cache (benchmarks measure cold rendering).
    func clearAll() {
        lines.removeAllObjects()
        sizedFonts.removeAllObjects()
        baseFonts.removeAllObjects()
        samples.removeAllObjects()
        featureTypes.removeAll()
    }
}

/// Where a preview line sits. The baseline is the same for every font at a given size (not
/// derived from each font's own ascent, which varies by a third of the size), so previews
/// line up across a row of cards, down the styles list and in Compare.
enum PreviewMetrics {
    /// Space above the tallest ordinary ascender.
    static let topPadding: CGFloat = 4

    /// Height of a preview area for text at `size`: room for ascenders, accents and descenders.
    static func height(for size: CGFloat) -> CGFloat { ceil(size * 1.45) + 8 }

    /// Baseline, measured down from the top of the preview area. At 0.95 em most Latin
    /// ascenders and accents fit above it and descenders below, with the cap height a little
    /// above the area's centre (where text looks centred).
    static func baseline(for size: CGFloat) -> CGFloat { topPadding + (size * 0.95).rounded() }
}

/// A typeset preview line plus what the card says about it.
final class TypesetLine {
    let line: CTLine?
    let ascent: CGFloat
    let descent: CGFloat
    /// Characters the font can't show (drawn faint).
    let missing: Int
    /// The font couldn't show the text, so this is a sample of its own characters.
    let isSample: Bool
    /// The font couldn't be loaded at all (unsupported format, missing file).
    let unavailable: Bool
    /// Typographic width of the (possibly truncated) line.
    let width: CGFloat

    init(line: CTLine?, ascent: CGFloat, descent: CGFloat, missing: Int, isSample: Bool, unavailable: Bool, width: CGFloat = 0) {
        self.width = width
        self.line = line
        self.ascent = ascent
        self.descent = descent
        self.missing = missing
        self.isSample = isSample
        self.unavailable = unavailable
    }

    /// Draws with the baseline at `baseline` (flipped view coordinates), in the context's fill colour.
    func draw(in context: CGContext, x: CGFloat, baseline: CGFloat, color: NSColor) {
        guard let line else { return }
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: x, y: baseline)
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(color.cgColor)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    var caption: String? {
        if unavailable { return "Can't preview this font" }
        if isSample { return "Sample" }
        if missing > 0 { return missing == 1 ? "1 character missing" : "\(missing) characters missing" }
        return nil
    }
}

/// Details read from the font itself for the Info section (not indexed: only needed on demand).
struct FontInfo {
    var version: String?
    var designer: String?
    var manufacturer: String?
    var copyright: String?
    var license: String?
    var glyphCount: Int?
    var format: String?

    @MainActor
    init(face: FontFace) {
        guard let font = PreviewRenderer.shared.font(for: face, size: 12) else { return }
        func name(_ key: CFString) -> String? {
            (CTFontCopyName(font, key) as String?).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        }
        version = name(kCTFontVersionNameKey)
        designer = name(kCTFontDesignerNameKey)
        manufacturer = name(kCTFontManufacturerNameKey)
        copyright = name(kCTFontCopyrightNameKey)
        license = name(kCTFontLicenseNameKey)
        glyphCount = CTFontGetGlyphCount(font)
        format = FontFormat.describe(font).map { face.format == "Font collection" ? "\($0), in a font collection" : $0 }
    }
}
