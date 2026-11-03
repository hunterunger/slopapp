import AppKit
import PDFKit
import Testing
@testable import PaperCore
import PaperFixtures

@Suite struct PageOpsTests {
    @Test func reorderPersistsAndUndoes() {
        let document = doc(Fixtures.textDocument())
        let order = PageOrder.moving([0], to: 3, count: 3)
        PageOps.reorder(document, to: order)
        let saved = doc(document.dataRepresentation()!)
        #expect(pageNames(saved) == ["Paper test page 2", "Paper test page 3", "Paper test page 1"])
        PageOps.reorder(document, to: PageOrder.inverse(order))
        #expect(pageNames(document) == ["Paper test page 1", "Paper test page 2", "Paper test page 3"])
    }

    @Test func reverse() {
        let document = doc(Fixtures.textDocument())
        PageOps.reorder(document, to: PageOrder.reversed(3))
        #expect(pageNames(document).first == "Paper test page 3")
    }

    @Test func rotationNormalizesAndPersists() {
        let document = doc(Fixtures.textDocument())
        PageOps.rotate(document, pages: [0, 2], by: -90)
        #expect(document.page(at: 0)!.rotation == 270)
        PageOps.rotate(document, pages: [0], by: 90)
        #expect(document.page(at: 0)!.rotation == 0)
        let saved = doc(document.dataRepresentation()!)
        #expect(saved.page(at: 2)!.rotation == 270)
        #expect(PageOps.normalizedRotation(450) == 90)
        #expect(PageOps.normalizedRotation(-450) == 270)
    }

    @Test func removeAndInsertRoundTrip() {
        let document = doc(Fixtures.textDocument())
        let removed = PageOps.remove(document, pages: [0, 2])
        #expect(document.pageCount == 1)
        #expect(removed.map(\.index) == [0, 2])
        PageOps.insert(document, pages: removed)
        #expect(pageNames(document) == ["Paper test page 1", "Paper test page 2", "Paper test page 3"])
    }

    @Test func extractLeavesTheSourceUnchanged() {
        let source = doc(Fixtures.textDocument())
        let extracted = PageOps.extract(source, pages: [1, 2])
        #expect(extracted.pageCount == 2)
        #expect(source.pageCount == 3)
        let saved = doc(extracted.dataRepresentation()!)
        #expect(pageNames(saved) == ["Paper test page 2", "Paper test page 3"])
    }

    @Test func extractKeepsAnnotations() {
        let source = doc(Fixtures.textDocument())
        let note = AnnotationFactory(author: nil).note("Hello", at: CGPoint(x: 100, y: 100))
        source.page(at: 1)!.addAnnotation(note)
        let extracted = doc(PageOps.extract(source, pages: [1]).dataRepresentation()!)
        #expect(extracted.page(at: 0)!.annotations.contains { $0.contents == "Hello" })
    }

    @Test func combineAppendsAndKeepsPageSizes() {
        let a = doc(Fixtures.textDocument())
        let b = doc(Fixtures.landscapeA4())
        let combined = doc(PageOps.combine([a, b]).dataRepresentation()!)
        #expect(combined.pageCount == 4)
        #expect(combined.page(at: 3)!.bounds(for: .mediaBox).size == CGSize(width: 842, height: 595))
        #expect(combined.page(at: 0)!.bounds(for: .mediaBox).size == CGSize(width: 612, height: 792))
    }

    @Test func combineInterleaves() {
        let front = doc(Fixtures.outlineDocument(pages: 2, chapterEvery: 1))
        let back = doc(Fixtures.textDocument(pages: 2))
        let combined = PageOps.combine([front, back], interleave: true)
        #expect(pageNames(combined) == ["Chapter 1, page 1", "Paper test page 2", "Chapter 2, page 2", "Paper test page 1"])
    }

    @Test func splitIntoRanges() {
        let document = doc(Fixtures.longDocument(pages: 10))
        let parts = PageOps.split(document, into: PageOrder.chunks(pageCount: 10, every: 4))
        #expect(parts.map(\.pageCount) == [4, 4, 2])
    }

    @Test func blankPageMatchesTheCurrentPage() {
        let landscape = doc(Fixtures.landscapeA4()).page(at: 0)!
        let blank = PageOps.blankPage(like: landscape)
        #expect(blank.bounds(for: .mediaBox).size == CGSize(width: 842, height: 595))
        #expect(PageOps.blankPage(like: nil).bounds(for: .mediaBox).size == CGSize(width: 612, height: 792))
    }

    @Test func topLevelOutline() {
        let document = doc(Fixtures.outlineDocument(pages: 6, chapterEvery: 2))
        let entries = PageOps.topLevelOutline(document)
        #expect(entries.map(\.title) == ["Chapter 1", "Chapter 2", "Chapter 3"])
        #expect(entries.map(\.pageIndex) == [0, 2, 4])
        #expect(PageOps.topLevelOutline(doc(Fixtures.textDocument())).isEmpty)
    }

    @Test func detectsCollidingFieldNames() {
        let one = doc(Fixtures.formDocument()), two = doc(Fixtures.formDocument())
        #expect(PageOps.collidingFieldNames([one, two]).contains("fullName"))
        #expect(PageOps.collidingFieldNames([one, doc(Fixtures.textDocument())]).isEmpty)
    }

    @Test func imagePagesUseLocalPaper() {
        #expect(ImagePages.paperSize(for: "US") == CGSize(width: 612, height: 792))
        #expect(ImagePages.paperSize(for: "DE") == CGSize(width: 595, height: 842))
        #expect(ImagePages.pageBox(forImageSize: CGSize(width: 400, height: 300), region: "US").width == 792)
        let image = NSImage(data: Fixtures.pngData())!
        let page = ImagePages.page(for: image, region: "FR")!
        #expect(page.bounds(for: .mediaBox).size == CGSize(width: 842, height: 595))
    }
}
