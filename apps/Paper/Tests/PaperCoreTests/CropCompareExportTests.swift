import AppKit
import PDFKit
import Testing
@testable import PaperCore
import PaperFixtures

@Suite("Crop")
struct CropTests {
    @Test func cropsOneOrAllPagesAndPersists() throws {
        let document = doc(Fixtures.textDocument())
        let first = document.page(at: 0)!
        let rect = CGRect(x: 50, y: 300, width: 500, height: 450)
        PageCrop.apply(rect, from: first, to: [first])
        #expect(PageCrop.isCropped(first))
        #expect(!PageCrop.isCropped(document.page(at: 1)!))
        let all = (0..<document.pageCount).compactMap { document.page(at: $0) }
        let old = PageCrop.apply(rect, from: first, to: all)
        #expect(old.count == 3)
        let reopened = doc(document.dataRepresentation()!)
        for index in 0..<3 { #expect(reopened.page(at: index)!.bounds(for: .cropBox).isClose(to: rect)) }
        // Content outside the crop is kept, so removing the crop brings it back.
        PageCrop.remove(from: all)
        #expect(!PageCrop.isCropped(first))
        #expect(first.string?.contains("Paper test page 1") == true)
    }

    @Test func otherPageSizesKeepTheSameMargins() {
        let letterDocument = doc(Fixtures.textDocument(pages: 1)), a4Document = doc(Fixtures.landscapeA4())
        defer { withExtendedLifetime((letterDocument, a4Document)) {} }
        let letter = letterDocument.page(at: 0)!
        let a4 = a4Document.page(at: 0)!
        PageCrop.apply(CGRect(x: 36, y: 36, width: 612 - 72, height: 792 - 72), from: letter, to: [letter, a4])
        #expect(a4.bounds(for: .cropBox).isClose(to: CGRect(x: 36, y: 36, width: 842 - 72, height: 595 - 72)))
    }

    @Test func tinyCropsAreIgnored() {
        let owner = doc(Fixtures.textDocument(pages: 1))
        defer { withExtendedLifetime(owner) {} }
        let page = owner.page(at: 0)!
        #expect(PageCrop.clamped(CGRect(x: 10, y: 10, width: 4, height: 300), to: page) == nil)
        #expect(PageCrop.clamped(CGRect(x: -50, y: -50, width: 200, height: 200), to: page) == CGRect(x: 0, y: 0, width: 150, height: 150))
    }
}

@Suite("Compare")
struct CompareTests {
    @Test func findsWordChangesAndTheirPages() {
        let changes = DocumentCompare.compare(doc(Fixtures.textDocument()), doc(Fixtures.revisedTextDocument()))
        let changed = changes.filter { $0.kind == .changed }
        #expect(changed.contains { $0.oldText.contains("public") && $0.newText.contains("revised") && $0.newPage == 1 })
        #expect(changes.contains { $0.kind == .deleted && $0.oldText.contains("jane@example.com") && $0.oldPage == 2 })
        // Unchanged pages produce nothing.
        #expect(!changes.contains { $0.oldPage == 0 || $0.newPage == 0 })
    }

    @Test func identicalDocumentsHaveNoChanges() {
        #expect(DocumentCompare.compare(doc(Fixtures.textDocument()), doc(Fixtures.textDocument())).isEmpty)
    }

    @Test func tokensMapToSelectableRanges() throws {
        let document = doc(Fixtures.textDocument(pages: 1))
        let tokens = DocumentCompare.tokens(document)
        let word = try #require(tokens.first { $0.text == "public" })
        #expect(document.page(at: 0)!.selection(for: word.range)?.string == "public")
        let merged = DocumentCompare.ranges(Array(tokens.prefix(3)))
        #expect(merged.count == 1)
        #expect((document.page(at: 0)!.string! as NSString).substring(with: merged[0].range) == "Paper test page")
    }

    @Test func pureInsertions() {
        func token(_ text: String, _ index: Int) -> DocumentCompare.Token { .init(text: text, page: 0, range: NSRange(location: index * 4, length: 3)) }
        let old = ["one", "two", "six"].enumerated().map { token($1, $0) }
        let new = ["one", "two", "new", "six", "end"].enumerated().map { token($1, $0) }
        let changes = DocumentCompare.compare(old, new)
        #expect(changes.map(\.kind) == [.inserted, .inserted])
        #expect(changes.map(\.newText) == ["new", "end"])
    }
}

@Suite("Office export")
struct OfficeExportTests {
    @Test func wordDocumentOpensWithTextAndPictures() throws {
        let document = doc(Fixtures.editableDocument())
        let data = OfficeExport.docx(document, title: "Report")
        #expect(data.prefix(2) == Data("PK".utf8))
        let text = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
        #expect(text.string.contains("Quarterly report"))
        #expect(text.string.contains("Paper keeps the original file untouched until"))
        #expect(text.string.contains("Total due: forty dollars"))
        // Reading order: heading, paragraph, the tinted line, then the caption.
        let s = text.string as NSString
        #expect(s.range(of: "Quarterly").location < s.range(of: "untouched").location)
        #expect(s.range(of: "forty").location < s.range(of: "Figure 1").location)
        // The paragraph keeps its font.
        let font = text.attribute(.font, at: s.range(of: "untouched").location, effectiveRange: nil) as? NSFont
        #expect(font?.familyName == "Times New Roman")
        // The picture is in the package.
        #expect(data.range(of: Data("word/media/image1.png".utf8)) != nil)
        #expect(OfficeExport.items(on: document.page(at: 0)!).contains { if case .image = $0 { true } else { false } })
    }

    @Test func pagesStartNewWordPages() {
        let data = OfficeExport.docx(doc(Fixtures.textDocument()))
        let xml = String(decoding: data, as: UTF8.self)
        #expect(xml.components(separatedBy: "w:type=\"page\"").count - 1 == 2)
    }

    @Test func missingFontsKeepTheirNameForWord() {
        let data = OfficeExport.docx(doc(Fixtures.missingFontDocument()))
        let xml = String(decoding: data, as: UTF8.self)
        #expect(xml.contains("w:ascii=\"Calibri\""))
    }

    @Test func richText() throws {
        let rtf = try #require(OfficeExport.rtf(doc(Fixtures.editableDocument())))
        let text = try NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        #expect(text.string.contains("Quarterly report"))
    }

    @Test func crcMatchesKnownValue() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF43926)
    }
}
