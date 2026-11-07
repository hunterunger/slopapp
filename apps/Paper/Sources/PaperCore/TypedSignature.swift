import AppKit
import CoreText

/// A signature typed as a name in a handwriting font. The text is drawn black on white and
/// traced like an imported picture (`SignatureImport`), so it's stored, placed, resized and
/// flattened exactly as drawn and imported signatures are.
public enum TypedSignature {
    /// Handwriting faces that ship with macOS, in order of preference. Missing ones are skipped.
    public static let candidateFonts: [(name: String, title: String)] = [
        ("SnellRoundhand", "Script"),
        ("BradleyHandITCTT-Bold", "Hand"),
        ("Noteworthy-Light", "Marker"),
        ("SavoyeLetPlain", "Flourish"),
    ]

    /// The candidates installed on this Mac (at most three).
    public static var availableFonts: [(name: String, title: String)] {
        Array(candidateFonts.filter { NSFont(name: $0.name, size: 12) != nil }.prefix(3))
    }

    /// `text` in `fontName`, black on white, with a margin. Nil for empty text or a missing font.
    public static func image(_ text: String, fontName: String, pointSize: CGFloat = 96) -> CGImage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let font = NSFont(name: fontName, size: pointSize) else { return nil }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: trimmed, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let margin = pointSize / 4
        let width = Int((bounds.width + margin * 2).rounded(.up))
        let height = Int((bounds.height + margin * 2).rounded(.up))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.textPosition = CGPoint(x: margin - bounds.minX, y: margin - bounds.minY)
        CTLineDraw(line, context)
        return context.makeImage()
    }

    /// The traced signature for `text` in `fontName`.
    public static func signature(_ text: String, fontName: String, kind: Signature.Kind = .signature) -> Signature? {
        guard let image = image(text, fontName: fontName) else { return nil }
        return SignatureImport.signature(from: image, threshold: 0.5, kind: kind)
    }
}
