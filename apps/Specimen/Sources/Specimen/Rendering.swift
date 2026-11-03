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

    func font(for face: FontFace, size: CGFloat) -> CTFont? {
        let key = "\(face.id)@\(size)" as NSString
        if let font = sizedFonts.object(forKey: key) { return font }
        guard let base = baseFont(for: face) else { return nil }
        let font = CTFontCreateCopyWithAttributes(base, size, nil, nil)
        sizedFonts.setObject(font, forKey: key)
        return font
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
    func line(for face: FontFace, text: String, size: CGFloat, width: CGFloat, allowSample: Bool = true) -> TypesetLine {
        let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let key = "\(face.id)|\(size)|\(Int(width))|\(dark)|\(allowSample)|\(text)" as NSString
        if let cached = lines.object(forKey: key) { return cached }
        let result = typeset(face: face, text: text, size: size, width: width, allowSample: allowSample)
        lines.setObject(result, forKey: key)
        return result
    }

    private func typeset(face: FontFace, text: String, size: CGFloat, width: CGFloat, allowSample: Bool) -> TypesetLine {
        guard let font = font(for: face, size: size) else {
            return TypesetLine(line: nil, ascent: size, descent: size * 0.3, missing: 0, isSample: false, unavailable: true)
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
                           missing: isSample ? 0 : PreviewText.missingCount(runs), isSample: isSample, unavailable: false)
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
    }
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

    init(line: CTLine?, ascent: CGFloat, descent: CGFloat, missing: Int, isSample: Bool, unavailable: Bool) {
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
