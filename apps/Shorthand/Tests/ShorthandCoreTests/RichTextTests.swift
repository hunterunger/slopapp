import AppKit
import Testing
@testable import ShorthandCore

/// A tiny PNG made in memory (never a file from the person's Mac).
func testPNG(width: Int = 4, height: Int = 3) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    return rep.representation(using: .png, properties: [:])!
}

func imageAttachment(_ data: Data = testPNG(), name: String = "slopapp-test.png") -> NSAttributedString {
    let wrapper = FileWrapper(regularFileWithContents: data)
    wrapper.preferredFilename = name
    return NSAttributedString(attachment: NSTextAttachment(fileWrapper: wrapper))
}

@Suite("Formatted text")
struct RichTextTests {
    var bold: NSFont { NSFontManager.shared.convert(RichText.baseFont, toHaveTrait: .boldFontMask) }

    func formatted(_ parts: [(String, [NSAttributedString.Key: Any])]) -> NSAttributedString {
        let text = NSMutableAttributedString()
        for (string, attributes) in parts { text.append(NSAttributedString(string: string, attributes: attributes)) }
        return text
    }

    func snippet(from text: NSAttributedString, abbreviation: String = ";r") -> Snippet {
        Snippet(groupID: UUID(), abbreviation: abbreviation, content: RichText.plain(text), richText: RichText.encode(text))
    }

    func isBold(_ text: NSAttributedString, at index: Int) -> Bool {
        (text.attribute(.font, at: index, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true
    }

    @Test func storesAndReadsBack() throws {
        let text = formatted([("slopapp-test ", RichText.baseAttributes), ("bold", [.font: bold])])
        let data = try #require(RichText.encode(text))
        let back = try #require(RichText.decode(data))
        #expect(back.string == "slopapp-test bold")
        #expect(isBold(back, at: 14))
        #expect(!isBold(back, at: 0))
        #expect(RichText.hasFormatting(back))
        #expect(!RichText.hasFormatting(RichText.make(fromPlain: "slopapp-test")))
    }

    @Test func dropsTheTextViewsDefaultColour() {
        let text = formatted([("a", [.foregroundColor: NSColor.textColor]), ("b", [.foregroundColor: NSColor.systemRed])])
        let clean = RichText.normalized(text)
        #expect(clean.attribute(.foregroundColor, at: 0, effectiveRange: nil) == nil)
        #expect(clean.attribute(.foregroundColor, at: 1, effectiveRange: nil) != nil)
    }

    @Test func formattingFollowsThroughPlaceholders() throws {
        // "Hi {field:Name}, bold" with the field token and "bold" in bold.
        let text = formatted([("Hi ", RichText.baseAttributes), ("{field:Name}", [.font: bold]), (", ", RichText.baseAttributes), ("bold", [.font: bold])])
        let s = snippet(from: text)
        let resolved = PlaceholderResolver(now: Date()).resolve(s, values: FillValues(["Name": .text("Ann")]), lookup: { _ in nil }) { .none }
        #expect(resolved.isFormatted)
        let decoded = try #require(RichText.decode(s.richText!))
        let out = RichText.assemble(resolved) { $0 == s.id ? decoded : nil }
        #expect(out.string == "Hi Ann, bold")
        #expect(!isBold(out, at: 0))
        #expect(isBold(out, at: 3))      // the field's value took the token's formatting
        #expect(!isBold(out, at: 6))
        #expect(isBold(out, at: 8))
    }

    @Test func adaptedCaseKeepsRuns() throws {
        let text = formatted([("he", [.font: bold]), ("llo", RichText.baseAttributes)])
        let s = snippet(from: text)
        let resolved = PlaceholderResolver(now: Date()).resolve(s, typedCase: .upper, lookup: { _ in nil }) { .none }
        let decoded = try #require(RichText.decode(s.richText!))
        let out = RichText.assemble(resolved) { _ in decoded }
        #expect(out.string == "HELLO")
        #expect(isBold(out, at: 1) && !isBold(out, at: 2))
    }

    @Test func plainSnippetsInsideFormattedOnesGetTheDefaultFont() throws {
        let sig = Snippet(groupID: UUID(), abbreviation: ";plain", content: "slopapp-test plain")
        let text = formatted([("Top ", [.font: bold]), ("{snippet:;plain}", RichText.baseAttributes)])
        let outer = snippet(from: text)
        let resolved = PlaceholderResolver(now: Date()).resolve(outer, lookup: { $0 == ";plain" ? sig : nil }) { .none }
        let decoded = try #require(RichText.decode(outer.richText!))
        let out = RichText.assemble(resolved) { $0 == outer.id ? decoded : nil }
        #expect(out.string == "Top slopapp-test plain")
        #expect((out.attribute(.font, at: 6, effectiveRange: nil) as? NSFont) == RichText.baseFont)
    }

    @Test func imagesTravelInRTFDAndHTML() throws {
        let text = NSMutableAttributedString(attributedString: formatted([("slopapp-test logo ", RichText.baseAttributes)]))
        text.append(imageAttachment())
        let s = snippet(from: text)
        #expect(s.content == "slopapp-test logo \u{FFFC}")
        let decoded = try #require(RichText.decode(s.richText!))
        #expect(RichText.attachments(in: decoded).count == 1)
        let resolved = PlaceholderResolver(now: Date()).resolve(s, lookup: { _ in nil }) { .none }
        #expect(resolved.text == "slopapp-test logo ")
        let out = RichText.assemble(resolved) { _ in decoded }
        let types = RichText.pasteboardTypes(out, plain: resolved.text)
        let names = types.map(\.0.rawValue)
        #expect(names.contains(NSPasteboard.PasteboardType.rtfd.rawValue))
        #expect(names.contains(NSPasteboard.PasteboardType.rtf.rawValue))
        #expect(names.contains(NSPasteboard.PasteboardType.html.rawValue))
        #expect(names.contains(NSPasteboard.PasteboardType.string.rawValue))
        #expect(!names.contains(NSPasteboard.PasteboardType.png.rawValue))
        let html = String(decoding: types.first { $0.0 == .html }!.1, as: UTF8.self)
        #expect(html.contains("<img src=\"data:image/png;base64,"))
        #expect(html.contains("width=\"4\" height=\"3\""))
        #expect(html.contains("slopapp-test logo"))
        #expect(String(decoding: types.first { $0.0 == .string }!.1, as: UTF8.self) == "slopapp-test logo ")
        // What's pasted reads back with the image.
        let back = try #require(NSAttributedString(rtfd: types.first { $0.0 == .rtfd }!.1, documentAttributes: nil))
        #expect(RichText.attachments(in: back).count == 1)
    }

    @Test func anImageOnItsOwnAlsoGoesAsAnImage() throws {
        let text = imageAttachment()
        let types = RichText.pasteboardTypes(text, plain: "")
        let png = try #require(types.first { $0.0 == .png }?.1)
        #expect(NSImage(data: png)?.size == CGSize(width: 4, height: 3))
        #expect(types.contains { $0.0 == .tiff })
    }

    @MainActor @Test func markdownAndHTML() throws {
        let md = try #require(RichText.fromMarkdown("slopapp-test **bold** and *it* `code` [link](https://example.com)"))
        #expect(md.string == "slopapp-test bold and it code link")
        #expect(isBold(md, at: 14))
        #expect(md.attribute(.link, at: md.length - 1, effectiveRange: nil) != nil)
        let html = try #require(RichText.fromHTML("<p>slopapp-test <b>bold</b></p>"))
        #expect(html.string == "slopapp-test bold")
        #expect(isBold(html, at: 14))
    }

    @Test func editsKeepFormattingAround() {
        let text = formatted([("Hi ", RichText.baseAttributes), ("%clipboard", [.font: bold]), (" {x}", RichText.baseAttributes)])
        let conversion = TextExpanderMacros.convert(text.string)
        let out = RichText.applying(conversion.edits, to: text)
        #expect(out.string == "Hi {clipboard} {{x}}")
        #expect(isBold(out, at: 4))
        #expect(!isBold(out, at: 15))
    }
}
