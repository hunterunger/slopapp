import AppKit
import CoreText
import PDFKit

// MARK: Text lines and blocks

/// One line of text on a page, as PDFKit selects it, with what the content stream says
/// about it (the real font name and the baseline).
public struct TextLine: @unchecked Sendable {
    public var range: NSRange
    public var bounds: CGRect
    public var text: String
    public var attributed: NSAttributedString
    public var fontSize: CGFloat
    public var baseline: CGFloat
    /// The PDF's font name for most of the line, when the scanner found it.
    public var pdfFontName: String?
    public var isHorizontal: Bool
}

/// A paragraph-like block of lines: what the Edit tool selects with one click, and what
/// Export as Word writes as one paragraph.
public struct TextBlock: @unchecked Sendable {
    public var lines: [TextLine]
    public var bounds: CGRect
    public var alignment: NSTextAlignment
    /// Distance between baselines (the font's line height for a single line).
    public var lineSpacing: CGFloat

    public var fontSize: CGFloat { lines.map(\.fontSize).max() ?? 12 }
    public var isEditable: Bool { lines.allSatisfy(\.isHorizontal) }
    public var pdfFontName: String? { lines.lazy.compactMap(\.pdfFontName).first }

    /// The block's text. Lines that wrap are joined with a space (a hyphen at the end of a
    /// line joins without one); a line much shorter than the block keeps its line break.
    public var attributedText: NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            let piece = NSMutableAttributedString(attributedString: line.attributed)
            Self.trimTrailingNewlines(piece)
            result.append(piece)
            guard index < lines.count - 1 else { break }
            let attributes = piece.length > 0 ? piece.attributes(at: piece.length - 1, effectiveRange: nil) : [:]
            if isHardBreak(after: index) {
                result.append(NSAttributedString(string: "\n", attributes: attributes))
            } else if !piece.string.hasSuffix("-"), !piece.string.hasSuffix(" ") {
                result.append(NSAttributedString(string: " ", attributes: attributes))
            }
        }
        return result
    }

    public var text: String { attributedText.string }

    func isHardBreak(after index: Int) -> Bool {
        guard lines.count > 1, index < lines.count - 1 else { return false }
        let width = lines[index].bounds.width
        let next = lines[index + 1].text.split(separator: " ").first.map(String.init) ?? ""
        // Would the next line's first word have fitted? Then the line ended on purpose.
        let font = lines[index].attributed.length > 0
            ? (lines[index].attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) ?? NSFont.systemFont(ofSize: fontSize)
            : NSFont.systemFont(ofSize: fontSize)
        let nextWidth = (next as NSString).size(withAttributes: [.font: font]).width
        return width + nextWidth + font.pointSize * 0.5 < bounds.width * 0.98
    }

    static func trimTrailingNewlines(_ text: NSMutableAttributedString) {
        while let last = text.string.last, last == "\n" || last == "\r" {
            text.deleteCharacters(in: NSRange(location: text.length - 1, length: 1))
        }
    }
}

public enum TextLayout {
    public static func lines(on page: PDFPage, scanned: [ScannedText]? = nil) -> [TextLine] {
        let count = page.numberOfCharacters
        guard count > 0, let selection = page.selection(for: NSRange(location: 0, length: count)),
              let attributed = page.attributedString else { return [] }
        let runs = scanned ?? ContentScanner.scan(page).text
        var result: [TextLine] = []
        for line in selection.selectionsByLine() {
            let bounds = line.bounds(for: page)
            guard bounds.width > 0, bounds.height > 0, line.numberOfTextRanges(on: page) > 0 else { continue }
            var range = line.range(at: 0, on: page)
            for index in 1..<max(1, line.numberOfTextRanges(on: page)) { range = NSUnionRange(range, line.range(at: index, on: page)) }
            guard range.location != NSNotFound, NSMaxRange(range) <= attributed.length else { continue }
            let piece = attributed.attributedSubstring(from: range)
            let text = piece.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let font = piece.length > 0 ? piece.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil
            let size = font?.pointSize ?? bounds.height * 0.8
            let inside = runs.filter {
                $0.origin.y >= bounds.minY - 1 && $0.origin.y <= bounds.maxY + 1
                    && $0.origin.x >= bounds.minX - size && $0.origin.x <= bounds.maxX
            }
            let baseline: CGFloat
            if let median = inside.map(\.origin.y).sorted().dropFirst(inside.count / 2).first {
                baseline = median
            } else {
                baseline = bounds.minY - (font?.descender ?? -size * 0.2)
            }
            let names = Dictionary(grouping: inside, by: \.fontName).max { $0.value.count < $1.value.count }?.key
            let horizontal = inside.isEmpty ? bounds.width >= bounds.height * 0.5 : inside.allSatisfy(\.isHorizontal)
            result.append(TextLine(range: range, bounds: bounds, text: text, attributed: piece, fontSize: size,
                                   baseline: baseline, pdfFontName: names, isHorizontal: horizontal))
        }
        return result
    }

    /// Lines grouped into blocks: same size, close together, overlapping horizontally.
    public static func blocks(on page: PDFPage) -> [TextBlock] {
        blocks(from: lines(on: page))
    }

    public static func blocks(from lines: [TextLine]) -> [TextBlock] {
        var groups: [[TextLine]] = []
        for line in lines {
            if var group = groups.last, let previous = group.last, belongs(line, after: previous, in: group) {
                group.append(line)
                groups[groups.count - 1] = group
            } else {
                groups.append([line])
            }
        }
        return groups.map(makeBlock)
    }

    static func belongs(_ line: TextLine, after previous: TextLine, in group: [TextLine]) -> Bool {
        let size = max(line.fontSize, previous.fontSize)
        guard abs(line.fontSize - previous.fontSize) <= max(1, size * 0.15) else { return false }
        // Below the previous line, with no more than about one empty line between.
        let gap = previous.baseline - line.baseline
        guard gap > size * 0.5, gap < size * 1.9 else { return false }
        if group.count >= 2 {
            let spacing = group[group.count - 2].baseline - previous.baseline
            guard abs(gap - spacing) < size * 0.3 else { return false }
        }
        // Overlapping columns.
        let overlap = min(line.bounds.maxX, previous.bounds.maxX) - max(line.bounds.minX, previous.bounds.minX)
        return overlap > 0
    }

    static func makeBlock(_ lines: [TextLine]) -> TextBlock {
        let bounds = lines.dropFirst().reduce(lines[0].bounds) { $0.union($1.bounds) }
        let spacing: CGFloat
        if lines.count > 1 {
            spacing = (lines[0].baseline - lines[lines.count - 1].baseline) / CGFloat(lines.count - 1)
        } else {
            let font = (lines[0].attributed.length > 0 ? lines[0].attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil)
                ?? NSFont.systemFont(ofSize: lines[0].fontSize)
            spacing = ceil(font.ascender - font.descender + font.leading)
        }
        return TextBlock(lines: lines, bounds: bounds, alignment: alignment(of: lines, in: bounds), lineSpacing: spacing)
    }

    static func alignment(of lines: [TextLine], in bounds: CGRect) -> NSTextAlignment {
        guard lines.count >= 2 else { return .left }
        let tolerance = max(2, (lines.map(\.fontSize).max() ?? 12) * 0.3)
        let lefts = lines.map(\.bounds.minX), rights = lines.map(\.bounds.maxX), centers = lines.map(\.bounds.midX)
        func same(_ values: ArraySlice<CGFloat>) -> Bool { (values.max() ?? 0) - (values.min() ?? 0) <= tolerance }
        let leftAligned = same(lefts[...]), rightAligned = same(rights[...])
        if leftAligned, lines.count >= 3, same(rights.dropLast()) { return .justified }
        if leftAligned, lines.count == 2, same(rights[...]) { return .justified }
        if leftAligned { return .left }
        if rightAligned { return .right }
        if same(centers[...]) { return .center }
        return .left
    }

    public static func block(at point: CGPoint, in blocks: [TextBlock]) -> TextBlock? {
        blocks.first { $0.bounds.insetBy(dx: -2, dy: -2).contains(point) }
    }
}

// MARK: Fonts

/// The font Paper draws edited text in, and whether it's the document's own.
public struct FontChoice: Equatable, @unchecked Sendable {
    public var font: NSFont
    /// The font name as the PDF has it, for messages ("Calibri Bold").
    public var originalName: String
    /// The document's font is on this Mac, so the edit matches it.
    public var isExact: Bool

    /// What the editing bar says about the font.
    public var notice: String {
        let size = PDFWriter.number(Double(font.pointSize))
        if isExact { return "\(font.displayName ?? font.fontName), \(size) pt" }
        return "“\(originalName)” isn't on this Mac. Paper uses \(font.displayName ?? font.fontName), the closest it has."
    }
}

public enum FontMatcher {
    /// `pdfKitFont` is what PDFKit reports (it says Helvetica for any font that isn't
    /// installed); `pdfName` is the PDF's own `/BaseFont`.
    public static func match(pdfKitFont: NSFont, pdfName: String?) -> FontChoice {
        let size = pdfKitFont.pointSize
        guard let pdfName = pdfName.map(ContentScanner.stripSubset), !pdfName.isEmpty else {
            return FontChoice(font: pdfKitFont, originalName: pdfKitFont.fontName, isExact: true)
        }
        let display = displayName(pdfName)
        let lower = pdfName.lowercased()
        let (family, traits, weight) = parse(pdfName)
        // macOS may hand back a substitute for a name it doesn't have (Carlito for Calibri):
        // only the same family counts as the document's font.
        func isSameFamily(_ font: NSFont) -> Bool {
            var wanted = family.lowercased().replacingOccurrences(of: " ", with: "")
            for suffix in ["psmt", "mt", "ps"] where wanted.hasSuffix(suffix) && wanted.count > suffix.count + 2 {
                wanted = String(wanted.dropLast(suffix.count))
                break
            }
            let got = (font.familyName ?? "").lowercased().replacingOccurrences(of: " ", with: "")
            return !got.isEmpty && (got == wanted || got.hasPrefix(wanted) || wanted.hasPrefix(got))
                || font.fontName.lowercased() == pdfName.lowercased()
        }
        // PDFKit found an installed font (or a stand-in), or the PDF really is Helvetica.
        if pdfKitFont.familyName != "Helvetica" || lower.hasPrefix("helvetica") {
            return FontChoice(font: pdfKitFont, originalName: display, isExact: lower.hasPrefix("helvetica") || isSameFamily(pdfKitFont))
        }
        if let installed = NSFont(name: pdfName, size: size) {
            return FontChoice(font: installed, originalName: display, isExact: isSameFamily(installed))
        }
        if let font = NSFontManager.shared.font(withFamily: family, traits: traits, weight: weight, size: size) {
            return FontChoice(font: font, originalName: display, isExact: isSameFamily(font))
        }
        if lower.hasPrefix("arial") || lower.hasPrefix("liberationsans") {
            let font = NSFontManager.shared.font(withFamily: "Arial", traits: traits, weight: weight, size: size) ?? pdfKitFont
            return FontChoice(font: font, originalName: display, isExact: false)
        }
        let fallbackFamily: String
        if ["courier", "mono", "consol", "menlo", "code", "typewriter"].contains(where: lower.contains) {
            fallbackFamily = "Courier New"
        } else if isSerif(lower) {
            fallbackFamily = "Times New Roman"
        } else {
            fallbackFamily = "Helvetica Neue"
        }
        let font = NSFontManager.shared.font(withFamily: fallbackFamily, traits: traits, weight: weight, size: size) ?? pdfKitFont
        return FontChoice(font: font, originalName: display, isExact: false)
    }

    static func isSerif(_ name: String) -> Bool {
        if name.contains("sans") { return false }
        return ["times", "roman", "serif", "garamond", "georgia", "cambria", "minion", "palatino", "book", "baskerville",
                "caslon", "bodoni", "didot", "century", "charter", "cochin", "hoefler", "constantia", "utopia", "sabon"]
            .contains(where: name.contains)
    }

    static func displayName(_ pdfName: String) -> String {
        var name = pdfName.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: ",", with: " ")
        for suffix in ["MT", "PSMT", "PS"] where name.hasSuffix(suffix) { name = String(name.dropLast(suffix.count)) }
        return name.trimmingCharacters(in: .whitespaces)
    }

    static func parse(_ pdfName: String) -> (String, NSFontTraitMask, Int) {
        let parts = pdfName.split(whereSeparator: { $0 == "-" || $0 == "," })
        let family = parts.first.map(String.init) ?? pdfName
        let style = parts.dropFirst().joined().lowercased() + (parts.count == 1 ? "" : "")
        let lower = pdfName.lowercased()
        var traits: NSFontTraitMask = []
        var weight = 5
        if lower.contains("bold") || lower.contains("black") || lower.contains("heavy") || style.contains("semibold") {
            traits.insert(.boldFontMask)
            weight = 9
        }
        if lower.contains("italic") || lower.contains("oblique") || style.hasSuffix("it") { traits.insert(.italicFontMask) }
        return (family, traits, weight)
    }

    /// The attributed text with every font PDFKit substituted replaced by Paper's match.
    public static func applying(_ choice: FontChoice, to text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        guard !choice.isExact || choice.font.familyName != "Helvetica" else { return result }
        result.enumerateAttribute(.font, in: NSRange(location: 0, length: result.length)) { value, range, _ in
            guard let font = value as? NSFont, font.familyName == "Helvetica", choice.font.familyName != "Helvetica" else { return }
            var replacement = NSFontManager.shared.convert(choice.font, toSize: font.pointSize)
            let traits = NSFontManager.shared.traits(of: font)
            if traits.contains(.boldFontMask) { replacement = NSFontManager.shared.convert(replacement, toHaveTrait: .boldFontMask) }
            if traits.contains(.italicFontMask) { replacement = NSFontManager.shared.convert(replacement, toHaveTrait: .italicFontMask) }
            result.addAttribute(.font, value: replacement, range: range)
        }
        return result
    }
}

// MARK: Editing page content

/// Changes what's printed on a page, not annotations on top of it. PDFKit can't rewrite a
/// content stream, so an edit is done in three steps on a copy of the page:
///
/// 1. The old content under the area is **removed** for good (PDFKit's `Redact`, as in
///    redaction, research P1): text there can't be selected, searched or extracted afterwards.
/// 2. The area is **repainted** with the page's background colour there, sampled around it
///    (removal also takes out background fills, research P28).
/// 3. The new text (real, selectable text in the matched font) or image is **drawn** in.
///
/// The result is a new page; the caller swaps it in (undo swaps the old one back).
public enum ContentEditor {
    /// Text drawn back into `block`'s place, wrapped to the block's width.
    public static func replaceText(_ block: TextBlock, with text: NSAttributedString, on page: PDFPage) -> PDFPage? {
        let patches = block.lines.map { $0.bounds.insetBy(dx: -0.75, dy: -0.75) }
        let background = backgroundColor(of: page, in: block.bounds)
        return rebuild(page, removing: patches) { context, _ in
            context.setFillColor(background)
            for patch in patches { context.fill(patch) }
            draw(text, in: block, context: context)
        }
    }

    /// Lines the text needs at the block's width (more than the block had means it runs
    /// past where the old text ended).
    public static func lineCount(_ text: NSAttributedString, in block: TextBlock) -> Int {
        layout(text, in: block).count
    }

    public static func moveImage(_ image: PageImage, to rect: CGRect, on page: PDFPage) -> PDFPage? {
        let background = backgroundColor(of: page, in: image.rect.insetBy(dx: -3, dy: -3), excluding: image.rect)
        let media = page.bounds(for: .mediaBox).insetBy(dx: -10, dy: -10)
        let old = image.rect
        // Everything except the image area, removed from a second copy: what's left is the
        // image itself, drawn again in its new place.
        let outside = [
            CGRect(x: media.minX, y: media.minY, width: media.width, height: max(0, old.minY - media.minY)),
            CGRect(x: media.minX, y: old.maxY, width: media.width, height: max(0, media.maxY - old.maxY)),
            CGRect(x: media.minX, y: old.minY, width: max(0, old.minX - media.minX), height: old.height),
            CGRect(x: old.maxX, y: old.minY, width: max(0, media.maxX - old.maxX), height: old.height),
        ].filter { $0.width > 0 && $0.height > 0 }
        return withRemoved(outside, from: page) { cutout in
            rebuild(page, removing: [old.insetBy(dx: -0.5, dy: -0.5)]) { context, _ in
                context.setFillColor(background)
                // A point past the edge: the zeroed image's anti-aliased border would show.
                context.fill(old.insetBy(dx: -1, dy: -1).intersection(page.bounds(for: .mediaBox)))
                guard let cutoutRef = cutout.pageRef, old.width > 0, old.height > 0 else { return }
                context.saveGState()
                context.clip(to: rect)
                context.translateBy(x: rect.minX, y: rect.minY)
                context.scaleBy(x: rect.width / old.width, y: rect.height / old.height)
                context.translateBy(x: -old.minX, y: -old.minY)
                context.clip(to: old)
                context.drawPDFPage(cutoutRef)
                context.restoreGState()
            }
        } ?? nil
    }

    public static func replaceImage(_ image: PageImage, with replacement: CGImage, on page: PDFPage) -> PDFPage? {
        let background = backgroundColor(of: page, in: image.rect.insetBy(dx: -3, dy: -3), excluding: image.rect)
        return rebuild(page, removing: [image.rect.insetBy(dx: -0.5, dy: -0.5)]) { context, _ in
            context.setFillColor(background)
            context.fill(image.rect.insetBy(dx: -1, dy: -1))
            let aspect = CGFloat(replacement.width) / CGFloat(max(replacement.height, 1))
            context.draw(replacement, in: Signature.fitted(aspect: aspect, in: image.rect))
        }
    }

    public static func deleteImage(_ image: PageImage, on page: PDFPage) -> PDFPage? {
        let background = backgroundColor(of: page, in: image.rect.insetBy(dx: -3, dy: -3), excluding: image.rect)
        return rebuild(page, removing: [image.rect.insetBy(dx: -0.5, dy: -0.5)]) { context, _ in
            context.setFillColor(background)
            context.fill(image.rect.insetBy(dx: -1, dy: -1))
        }
    }

    /// A new image drawn into the page's content at `rect`.
    public static func addImage(_ image: CGImage, in rect: CGRect, on page: PDFPage) -> PDFPage? {
        rebuild(page, removing: []) { context, _ in context.draw(image, in: rect) }
    }

    // MARK: Internals

    /// Removes the content under `rects` from a copy of `page`, then draws the copy into a
    /// new page with `overlay` on top.
    static func rebuild(_ page: PDFPage, removing rects: [CGRect], overlay: @escaping (CGContext, PDFPage) -> Void) -> PDFPage? {
        withRemoved(rects, from: page) { removed in
            let result = PageRewriter.rewrite(removed) { context in overlay(context, removed) }
            result?.rotation = page.rotation
            return result
        } ?? nil
    }

    /// Runs `body` with a copy of `page` whose content under `rects` is gone. The copy's
    /// document lives until `body` returns.
    static func withRemoved<T>(_ rects: [CGRect], from page: PDFPage, _ body: (PDFPage) -> T) -> T? {
        guard let copy = page.copy() as? PDFPage else { return nil }
        for annotation in copy.annotations { copy.removeAnnotation(annotation) }
        let single = PDFDocument()
        single.insert(copy, at: 0)
        guard !rects.isEmpty else { return body(copy) }
        for rect in rects where rect.width > 0 && rect.height > 0 {
            copy.addAnnotation(PDFAnnotation(bounds: rect, forType: RedactionMarks.redactSubtype, withProperties: nil))
        }
        guard let data = single.dataRepresentation(), let reopened = PDFDocument(data: data), let removed = reopened.page(at: 0) else { return nil }
        for annotation in removed.annotations { removed.removeAnnotation(annotation) }
        return withExtendedLifetime(reopened) { body(removed) }
    }

    /// The most common colour in a region of the page as printed (annotations left out),
    /// optionally ignoring an inner rectangle. White when there's nothing to sample.
    public static func backgroundColor(of page: PDFPage, in rect: CGRect, excluding inner: CGRect? = nil) -> CGColor {
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let region = rect.intersection(page.bounds(for: .mediaBox))
        guard region.width > 0.5, region.height > 0.5 else { return white }
        let scale: CGFloat = 2
        guard let image = PageRenderer.render(page, region: region, scale: scale, annotations: false),
              let pixels = PageRenderer.rgba(image) else { return white }
        var counts: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
        for y in 0..<image.height {
            for x in 0..<image.width {
                if let inner {
                    let point = CGPoint(x: region.minX + (CGFloat(x) + 0.5) / scale, y: region.maxY - (CGFloat(y) + 0.5) / scale)
                    if inner.contains(point) { continue }
                }
                let index = (y * image.width + x) * 4
                let r = Int(pixels[index]), g = Int(pixels[index + 1]), b = Int(pixels[index + 2])
                let key = (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)
                let entry = counts[key] ?? (0, 0, 0, 0)
                counts[key] = (entry.count + 1, entry.r + r, entry.g + g, entry.b + b)
            }
        }
        guard let best = counts.values.max(by: { $0.count < $1.count }), best.count > 0 else { return white }
        let n = CGFloat(best.count) * 255
        return CGColor(srgbRed: CGFloat(best.r) / n, green: CGFloat(best.g) / n, blue: CGFloat(best.b) / n, alpha: 1)
    }

    struct PlacedLine {
        var line: CTLine
        var origin: CGPoint
    }

    static func layout(_ text: NSAttributedString, in block: TextBlock) -> [PlacedLine] {
        // A little slack: the widest original line is the block's width, and unchanged text
        // should wrap exactly where it did.
        let width = max(block.bounds.width + block.fontSize * 0.3, 20)
        var placed: [PlacedLine] = []
        var baseline = block.lines.first?.baseline ?? block.bounds.maxY - block.fontSize
        let string = text.string as NSString
        var paragraphs: [NSRange] = []
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            paragraphs.append(range)
        }
        if paragraphs.isEmpty { paragraphs = [NSRange(location: 0, length: string.length)] }
        for range in paragraphs {
            let colored = coloredForCoreText(text.attributedSubstring(from: range))
            let length = colored.length
            guard length > 0 else { baseline -= block.lineSpacing; continue }
            let typesetter = CTTypesetterCreateWithAttributedString(colored)
            var start = 0
            while start < length {
                let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
                guard count > 0 else { break }
                var line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
                let isLast = start + count >= length
                if block.alignment == .justified, !isLast, let justified = CTLineCreateJustifiedLine(line, 1, Double(block.bounds.width)) {
                    line = justified
                }
                let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line))
                var x = block.bounds.minX
                switch block.alignment {
                case .right: x = block.bounds.maxX - lineWidth
                case .center: x = block.bounds.midX - lineWidth / 2
                default: break
                }
                placed.append(PlacedLine(line: line, origin: CGPoint(x: x, y: baseline)))
                baseline -= block.lineSpacing
                start += count
            }
        }
        return placed
    }

    static func draw(_ text: NSAttributedString, in block: TextBlock, context: CGContext) {
        context.saveGState()
        context.textMatrix = .identity
        for item in layout(text, in: block) {
            context.textPosition = item.origin
            CTLineDraw(item.line, context)
        }
        context.restoreGState()
    }

    /// CoreText draws with its own colour attribute; PDFKit's attributed strings carry
    /// AppKit's.
    static func coloredForCoreText(_ text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        result.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: result.length)) { value, range, _ in
            let color = (value as? NSColor)?.usingColorSpace(.sRGB)?.cgColor ?? CGColor(gray: 0, alpha: 1)
            result.addAttribute(NSAttributedString.Key(kCTForegroundColorAttributeName as String), value: color, range: range)
        }
        return result
    }
}
