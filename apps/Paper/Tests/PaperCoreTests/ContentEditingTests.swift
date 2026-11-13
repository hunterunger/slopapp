import AppKit
import PDFKit
import Testing
@testable import PaperCore
import PaperFixtures

@Suite("Editing page content")
struct ContentEditingTests {
    /// The document must outlive its pages: a page doesn't keep its document's content alive
    /// (on macOS 26 a page of a released document draws and copies as empty).
    static func document() -> PDFDocument { doc(Fixtures.editableDocument()) }

    static func block(containing text: String, on page: PDFPage) -> TextBlock? {
        TextLayout.blocks(on: page).first { $0.text.contains(text) }
    }

    static func pixel(_ page: PDFPage, at point: CGPoint) -> (r: Int, g: Int, b: Int) {
        let image = PageRenderer.render(page, region: CGRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2), scale: 1, annotations: false)!
        let pixels = PageRenderer.rgba(image)!
        return (Int(pixels[0]), Int(pixels[1]), Int(pixels[2]))
    }

    @Test func linesGroupIntoBlocks() throws {
        let owner = Self.document()
        defer { withExtendedLifetime(owner) {} }
        let page = owner.page(at: 0)!
        let blocks = TextLayout.blocks(on: page)
        let paragraph = try #require(Self.block(containing: "untouched", on: page))
        #expect(paragraph.lines.count == 3)
        #expect(paragraph.text.replacingOccurrences(of: "\n", with: " ").hasPrefix("Paper keeps the original file untouched until you save"))
        #expect(abs(paragraph.lineSpacing - 17) < 0.5)
        let heading = try #require(Self.block(containing: "Quarterly", on: page))
        #expect(heading.lines.count == 1)
        #expect(blocks.count >= 4)
        // The scanner found the baselines the fixture drew at.
        #expect(abs(paragraph.lines[0].baseline - (640 - (NSFont(name: "Times New Roman", size: 13)!.descender))) < 1.5)
        #expect(paragraph.pdfFontName?.hasPrefix("TimesNewRoman") == true)
    }

    @Test func replacingTextRemovesTheOldText() throws {
        let owner = Self.document()
        defer { withExtendedLifetime(owner) {} }
        let page = owner.page(at: 0)!
        let block = try #require(Self.block(containing: "untouched", on: page))
        let edited = NSMutableAttributedString(attributedString: block.attributedText)
        let range = (edited.string as NSString).range(of: "untouched")
        edited.replaceCharacters(in: range, with: "unchanged")
        let rebuilt = try #require(ContentEditor.replaceText(block, with: edited, on: page))
        let text = try #require(rebuilt.string)
        #expect(text.contains("unchanged"))
        #expect(!text.contains("untouched"))
        // Everything else on the page is still there, as text.
        #expect(text.contains("Quarterly report"))
        #expect(text.contains("Total due: forty dollars"))
        // In the same font and colour.
        let again = try #require(Self.block(containing: "unchanged", on: rebuilt))
        let font = try #require(again.lines[0].attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.familyName == "Times New Roman")
        #expect(abs(font.pointSize - 13) < 0.5)
        let color = (again.lines[0].attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?.usingColorSpace(.sRGB)
        #expect(abs((color?.blueComponent ?? 0) - 0.5) < 0.05)
        // Still three lines, on the original baselines.
        #expect(again.lines.count == 3)
        #expect(abs(again.lines[0].baseline - block.lines[0].baseline) < 1)
        // A second edit of the rebuilt page works too (its old content is a nested form).
        let second = try #require(ContentEditor.replaceText(again, with: NSAttributedString(string: "Short.", attributes: [.font: font]), on: rebuilt))
        #expect(second.string?.contains("Short.") == true)
        #expect(second.string?.contains("unchanged") == false)
    }

    @Test func backgroundIsRepainted() throws {
        let owner = Self.document()
        defer { withExtendedLifetime(owner) {} }
        let page = owner.page(at: 0)!
        let block = try #require(Self.block(containing: "Total due", on: page))
        let rebuilt = try #require(ContentEditor.replaceText(block, with: NSAttributedString(string: "Paid", attributes: [.font: NSFont.systemFont(ofSize: 16)]), on: page))
        // Right of the new, shorter text the tinted box shows, not a white hole.
        let point = CGPoint(x: block.bounds.maxX - 4, y: block.bounds.midY)
        let color = Self.pixel(rebuilt, at: point)
        #expect(color.b > 240 && color.r < 230 && color.r > 200)
        #expect(rebuilt.string?.contains("forty") == false)
    }

    @Test func imagesAreFoundMovedReplacedAndDeleted() throws {
        let owner = Self.document()
        defer { withExtendedLifetime(owner) {} }
        let page = owner.page(at: 0)!
        let images = ContentScanner.scan(page).images
        let image = try #require(images.first)
        #expect(image.rect.isClose(to: CGRect(x: 72, y: 300, width: 200, height: 100)))
        #expect(image.pixelSize == CGSize(width: 200, height: 100))

        let target = CGRect(x: 320, y: 300, width: 100, height: 50)
        let moved = try #require(ContentEditor.moveImage(image, to: target, on: page))
        let after = ContentScanner.scan(moved).images
        #expect(after.contains { $0.rect.intersects(target) })
        // The old place is page white again; the new one has the gradient.
        let old = Self.pixel(moved, at: CGPoint(x: 172, y: 350))
        #expect(old.r > 245 && old.g > 245 && old.b > 245)
        let left = Self.pixel(moved, at: CGPoint(x: 325, y: 325)), right = Self.pixel(moved, at: CGPoint(x: 415, y: 325))
        #expect(left.b > left.r && right.r > right.b)
        #expect(moved.string?.contains("Figure 1") == true)

        let deleted = try #require(ContentEditor.deleteImage(image, on: page))
        let gone = Self.pixel(deleted, at: CGPoint(x: 172, y: 350))
        #expect(gone.r > 245 && gone.g > 245 && gone.b > 245)

        let red = NSImage(size: NSSize(width: 40, height: 20), flipped: false) { rect in
            NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill(); rect.fill(); return true
        }
        let cg = try #require(red.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let replaced = try #require(ContentEditor.replaceImage(image, with: cg, on: page))
        let center = Self.pixel(replaced, at: CGPoint(x: 172, y: 350))
        #expect(center.r > 200 && center.g < 60)
    }

    @Test func addsAnImage() throws {
        let owner = Self.document()
        defer { withExtendedLifetime(owner) {} }
        let page = owner.page(at: 0)!
        let gradient = Fixtures.gradientImage()
        let added = try #require(ContentEditor.addImage(gradient, in: CGRect(x: 350, y: 100, width: 100, height: 50), on: page))
        #expect(ContentScanner.scan(added).images.count == 2)
    }

    @Test func missingFontsAreNamedAndMatched() throws {
        let owner = doc(Fixtures.missingFontDocument())
        defer { withExtendedLifetime(owner) {} }
        let page = owner.page(at: 0)!
        let lines = TextLayout.lines(on: page)
        #expect(lines.count == 2)
        #expect(lines[0].pdfFontName == "Calibri-Bold")
        let pdfKitFont = try #require(lines[0].attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let calibri = FontMatcher.match(pdfKitFont: pdfKitFont, pdfName: lines[0].pdfFontName)
        if NSFont(name: "Calibri-Bold", size: 12) == nil {
            #expect(!calibri.isExact)
            #expect(calibri.originalName == "Calibri Bold")
            #expect(NSFontManager.shared.traits(of: calibri.font).contains(.boldFontMask))
            #expect(calibri.notice.contains("isn't on this Mac"))
        }
        let garamond = FontMatcher.match(pdfKitFont: pdfKitFont, pdfName: lines[1].pdfFontName)
        if !garamond.isExact { #expect(garamond.font.familyName == "Times New Roman") }
        // An installed font is used as it is.
        let times = NSFont(name: "TimesNewRomanPSMT", size: 13)!
        #expect(FontMatcher.match(pdfKitFont: times, pdfName: "TimesNewRomanPSMT").isExact)
        #expect(ContentScanner.stripSubset("ABCDEF+Calibri") == "Calibri")
        #expect(ContentScanner.stripSubset("Calibri+Bold") == "Calibri+Bold")
    }

    @Test func alignmentIsDetected() {
        func line(_ minX: CGFloat, _ width: CGFloat, _ baseline: CGFloat) -> TextLine {
            TextLine(range: NSRange(location: 0, length: 1), bounds: CGRect(x: minX, y: baseline - 3, width: width, height: 14),
                     text: "x", attributed: NSAttributedString(string: "x"), fontSize: 12, baseline: baseline, pdfFontName: nil, isHorizontal: true)
        }
        #expect(TextLayout.blocks(from: [line(72, 300, 700), line(72, 300, 686), line(72, 120, 672)]).first?.alignment == .justified)
        #expect(TextLayout.blocks(from: [line(72, 300, 700), line(72, 200, 686), line(72, 120, 672)]).first?.alignment == .left)
        #expect(TextLayout.blocks(from: [line(100, 300, 700), line(200, 200, 686)]).first?.alignment == .right)
        #expect(TextLayout.blocks(from: [line(100, 300, 700), line(150, 200, 686)]).first?.alignment == .center)
        // A big jump starts a new block.
        #expect(TextLayout.blocks(from: [line(72, 300, 700), line(72, 300, 640)]).count == 2)
    }
}

@Suite("Editing page content, follow-ups")
struct ContentEditingFollowUpTests {
    @Test func movedImagesLeaveNoGhost() throws {
        let owner = ContentEditingTests.document()
        defer { withExtendedLifetime(owner) {} }
        let page = owner.page(at: 0)!
        let image = try #require(ContentScanner.scan(page).images.first)
        let moved = try #require(ContentEditor.moveImage(image, to: image.rect.offsetBy(dx: 250, dy: 0), on: page))
        let images = ContentScanner.scan(moved).images
        #expect(images.count == 1)
        #expect(images.first?.rect.isClose(to: image.rect.offsetBy(dx: 250, dy: 0)) == true)
        let deleted = try #require(ContentEditor.deleteImage(image, on: page))
        #expect(ContentScanner.scan(deleted).images.isEmpty)
    }

    @Test func aSubstituteFamilyIsNotExact() throws {
        let helvetica = NSFont(name: "Helvetica", size: 12)!
        let choice = FontMatcher.match(pdfKitFont: helvetica, pdfName: "ABCDEF+NoSuchFontAnywhere-Bold")
        #expect(!choice.isExact)
        #expect(choice.originalName == "NoSuchFontAnywhere Bold")
    }
}

@Suite("Font matching names")
struct FontMatchingNameTests {
    @Test func postScriptSuffixesStillMatch() {
        let times = NSFont(name: "TimesNewRomanPSMT", size: 12)!
        #expect(FontMatcher.match(pdfKitFont: times, pdfName: "ABCDEF+TimesNewRomanPSMT").isExact)
        // A stand-in PDFKit picked for another family isn't the document's font.
        #expect(!FontMatcher.match(pdfKitFont: times, pdfName: "ABCDEF+Calibri-Bold").isExact)
    }
}
