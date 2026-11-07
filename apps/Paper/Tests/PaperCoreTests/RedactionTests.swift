import AppKit
import PDFKit
import Testing
@testable import PaperCore
import PaperFixtures

/// Simulates a macOS where PDFKit's `Redact` annotation removes nothing.
struct RemovesNothing: ContentRemover {
    func removeContent(in document: PDFDocument, rects: [Int: [CGRect]]) -> Data? { document.dataRepresentation() }
}

struct FailsToWrite: ContentRemover {
    func removeContent(in document: PDFDocument, rects: [Int: [CGRect]]) -> Data? { nil }
}

/// A broken fallback that hands the page back unchanged.
struct CopiesInstead: PageRasterizing {
    func rasterize(_ page: PDFPage, blackRects: [CGRect], dpi: CGFloat) -> PDFPage? { page.copy() as? PDFPage }
}

@Suite struct RedactionMarkTests {
    @Test func markupRedactIsFakeAndNeverUsed() {
        // Research P2: PDFMarkupType.redact only draws a box; the text stays.
        let document = doc(Fixtures.textDocument(pages: 1))
        let page = document.page(at: 0)!
        let fake = PDFAnnotation(bounds: bounds(of: "\(Fixtures.secret)-1", in: document), forType: .highlight, withProperties: nil)
        fake.markupType = .redact
        page.addAnnotation(fake)
        #expect(allText(doc(document.dataRepresentation()!)).contains("\(Fixtures.secret)-1"))
    }

    @Test func pendingMarksDoNotChangeContentOnSave() throws {
        let document = doc(Fixtures.textDocument())
        mark("\(Fixtures.secret)-1", in: document)
        let data = try #require(document.dataRepresentation())
        let saved = try #require(AnnotationTags.open(data))
        #expect(allText(saved).contains("\(Fixtures.secret)-1"))
        let marks = RedactionMarks.marks(in: saved)
        // On failure, say what PDFKit read back and what's in the file, so a CI run on
        // another macOS shows which keys were lost.
        let mark = try #require(marks.first, "No mark after reopen. \(tagDiagnostics(saved, data))")
        #expect(marks.count == 1)
        #expect(!RedactionMarks.isRedactAnnotation(mark.annotation))
        #expect(RedactionMarks.redactAnnotations(in: saved).isEmpty)
    }

    @Test func foreignRedactAnnotationsBecomeMarksWithoutApplying() {
        let document = doc(Fixtures.foreignRedactDocument())
        #expect(RedactionMarks.redactAnnotations(in: document).count == 1)
        #expect(RedactionMarks.convertRedactAnnotations(in: document) == 1)
        #expect(RedactionMarks.redactAnnotations(in: document).isEmpty)
        #expect(RedactionMarks.marks(in: document).count == 1)
        let saved = doc(document.dataRepresentation()!)
        #expect(allText(saved).contains("\(Fixtures.secret)-1"))
    }

    @Test func summaryText() {
        #expect(MarkSummary(pageIndexes: [0, 0, 2]).text == "3 marks on 2 pages")
        #expect(MarkSummary(pageIndexes: [4]).text == "1 mark on 1 page")
    }
}

@Suite struct RedactorTests {
    @Test func removesMarkedTextAndKeepsTheRest() throws {
        let document = doc(Fixtures.textDocument())
        mark("\(Fixtures.secret)-1", in: document, page: 0)
        mark("\(Fixtures.secret)-3", in: document, page: 2)
        let (data, report) = try Redactor().apply(to: document.dataRepresentation()!)
        let output = doc(data)
        let text = allText(output)
        #expect(!text.contains("\(Fixtures.secret)-1"))
        #expect(!text.contains("\(Fixtures.secret)-3"))
        // Page 2 wasn't marked, so its number is still there.
        #expect(output.page(at: 1)!.string!.contains("\(Fixtures.secret)-2"))
        #expect(text.contains("This public sentence should survive redaction."))
        #expect(text.contains("belongs to nobody"))
        #expect(report.areaCount == 2)
        #expect(report.pageCount == 2)
        #expect(report.rasterizedPages.isEmpty)
        #expect(annotationCount(output) == 0)
        #expect(report.summary == "Removed 2 areas on 2 pages.")
    }

    @Test func paintsSolidBlackBoxes() throws {
        let document = doc(Fixtures.textDocument(pages: 1))
        let annotation = mark("\(Fixtures.secret)-1", in: document)
        let (data, _) = try Redactor().apply(to: document.dataRepresentation()!)
        let page = doc(data).page(at: 0)!
        let image = PageRenderer.render(page, region: annotation.bounds.insetBy(dx: 1, dy: 1), scale: 2)!
        #expect(PageRenderer.meanLuminance(image) < 0.05)
    }

    @Test func removesInvisibleOCRText() throws {
        let document = doc(Fixtures.scanDocument(withHiddenText: true))
        #expect(allText(document).contains(Fixtures.hidden))
        mark(Fixtures.hidden, in: document)
        let (data, report) = try Redactor().apply(to: document.dataRepresentation()!)
        #expect(!allText(doc(data)).contains(Fixtures.hidden))
        #expect(allText(doc(data)).contains("55821"))
        #expect(report.rasterizedPages.isEmpty)
    }

    @Test func removesImagePixelsUnderAnAreaMark() throws {
        let document = doc(Fixtures.textDocument(pages: 1))
        let area = CGRect(x: 360, y: 420, width: 60, height: 60) // inside the gradient image
        let work = doc(document.dataRepresentation()!)
        let before = PageRenderer.render(work.page(at: 0)!, region: area.insetBy(dx: 2, dy: 2), scale: 2, annotations: false)!
        #expect(!PageRenderer.isUniform(before))
        #expect(!RedactionVerifier.regionsAreBlank(original: work.page(at: 0)!, redacted: work.page(at: 0)!, rects: [area]))
        let removed = PDFKitContentRemover().removeContent(in: work, rects: [0: [area]])!
        let pass1 = doc(removed)
        for item in RedactionMarks.redactAnnotations(in: pass1) { pass1.page(at: 0)!.removeAnnotation(item.annotation) }
        #expect(RedactionVerifier.regionsAreBlank(original: work.page(at: 0)!, redacted: pass1.page(at: 0)!, rects: [area]))
        // The remover leaves the input document as it found it.
        #expect(work.page(at: 0)!.annotations.isEmpty)
    }

    @Test func markOverAnImageEdgeIsRemovedWithoutRasterizing() throws {
        let document = doc(Fixtures.textDocument(pages: 1))
        // The gradient image spans (320, 400)-(520, 500); this box hangs off its bottom edge.
        document.page(at: 0)!.addAnnotation(RedactionMarks.makeMark(bounds: CGRect(x: 360, y: 380, width: 80, height: 50)))
        let (data, report) = try Redactor().apply(to: document.dataRepresentation()!)
        #expect(report.rasterizedPages.isEmpty)
        #expect(allText(doc(data)).contains("public sentence"))
    }

    @Test func partialAreaRemovesOnlyCoveredLetters() throws {
        let document = doc(Fixtures.textDocument(pages: 1))
        let word = bounds(of: "nobody", in: document)
        let half = CGRect(x: word.minX, y: word.minY, width: word.width * 0.5, height: word.height)
        document.page(at: 0)!.addAnnotation(RedactionMarks.makeMark(bounds: half))
        let (data, _) = try Redactor().apply(to: document.dataRepresentation()!)
        let text = allText(doc(data))
        #expect(!text.contains("nobody"))
        #expect(text.contains("belongs to"))
        #expect(text.contains("survive redaction"))
    }

    @Test func worksOnRotatedPages() throws {
        let document = doc(Fixtures.rotatedDocument())
        #expect(document.page(at: 0)!.rotation == 90)
        mark("\(Fixtures.secret)-1", in: document)
        let (data, _) = try Redactor().apply(to: document.dataRepresentation()!)
        let output = doc(data)
        #expect(!allText(output).contains(Fixtures.secret))
        #expect(output.page(at: 0)!.rotation == 90)
    }

    @Test func clearsMetadataWhenAsked() throws {
        let document = doc(Fixtures.textDocument(title: "Secret Title", author: "Jane Author"))
        mark("\(Fixtures.secret)-1", in: document)
        let source = document.dataRepresentation()!
        let cleared = doc(try Redactor(options: .init(removeMetadata: true)).apply(to: source).data)
        let attributes = cleared.documentAttributes ?? [:]
        #expect(attributes[PDFDocumentAttribute.titleAttribute] == nil)
        #expect(attributes[PDFDocumentAttribute.authorAttribute] == nil)
        #expect(attributes[PDFDocumentAttribute.keywordsAttribute] == nil)
        let kept = doc(try Redactor(options: .init(removeMetadata: false)).apply(to: source).data)
        #expect(kept.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Secret Title")
    }

    @Test func removesOverlappingAnnotations() throws {
        let document = doc(Fixtures.outlineDocument(pages: 2, chapterEvery: 1))
        let target = bounds(of: "page 1", in: document)
        let note = AnnotationFactory(author: nil).note("covers it", at: CGPoint(x: target.midX, y: target.midY))
        document.page(at: 0)!.addAnnotation(note)
        document.page(at: 0)!.addAnnotation(RedactionMarks.makeMark(bounds: target))
        let (data, report) = try Redactor().apply(to: document.dataRepresentation()!)
        #expect(report.removedAnnotations == 1)
        // The outline doesn't mention the redacted words, so it stays.
        #expect(!report.outlineRemoved)
        #expect(doc(data).outlineRoot?.numberOfChildren == 2)
    }

    @Test func dropsAnOutlineThatMentionsRedactedWords() throws {
        let document = doc(Fixtures.outlineDocument(pages: 4, chapterEvery: 2))
        document.page(at: 0)!.addAnnotation(RedactionMarks.makeMark(bounds: bounds(of: "Chapter 1", in: document)))
        let (data, report) = try Redactor().apply(to: document.dataRepresentation()!)
        #expect(report.outlineRemoved)
        #expect(report.outlineLine != nil)
        let output = doc(data)
        #expect(output.outlineRoot == nil || output.outlineRoot?.numberOfChildren == 0)
        #expect(output.pageCount == 4)
    }

    @Test func scrubsNotesElsewhere() {
        let document = doc(Fixtures.textDocument(pages: 1))
        let note = AnnotationFactory(author: nil).note("Account \(Fixtures.secret)-1 is closed", at: CGPoint(x: 500, y: 100))
        document.page(at: 0)!.addAnnotation(note)
        Scrubber.scrub(document, removing: ["\(Fixtures.secret)-1"])
        #expect(note.contents == "Account █████ is closed")
    }

    @Test func handlesTheForeignRedactFixture() throws {
        let (data, report) = try Redactor().apply(to: Fixtures.foreignRedactDocument())
        #expect(!allText(doc(data)).contains(Fixtures.secret))
        #expect(report.areaCount == 1)
    }

    @Test func fallsBackToRasterizingWhenRemovalDoesNothing() throws {
        let document = doc(Fixtures.textDocument())
        mark("\(Fixtures.secret)-2", in: document, page: 1)
        let (data, report) = try Redactor(remover: RemovesNothing(), options: .init(rasterDPI: 72)).apply(to: document.dataRepresentation()!)
        let output = doc(data)
        #expect(report.rasterizedPages == [1])
        #expect((output.page(at: 1)!.string ?? "").isEmpty)
        #expect(!allText(output).contains("\(Fixtures.secret)-2"))
        // Other pages keep their text.
        #expect(output.page(at: 0)!.string!.contains("\(Fixtures.secret)-1"))
        #expect(output.page(at: 1)!.bounds(for: .mediaBox).size == CGSize(width: 612, height: 792))
        #expect(report.rasterizedLine?.hasPrefix("Page 2 was converted") == true)
    }

    @Test func neverReportsSuccessWhenTheFallbackFails() {
        let document = doc(Fixtures.textDocument())
        mark("\(Fixtures.secret)-1", in: document)
        #expect(throws: RedactionError.verificationFailed(pages: [0])) {
            try Redactor(remover: RemovesNothing(), rasterizer: CopiesInstead()).apply(to: document.dataRepresentation()!)
        }
    }

    @Test func reportsWriteFailures() {
        let document = doc(Fixtures.textDocument())
        mark("\(Fixtures.secret)-1", in: document)
        #expect(throws: RedactionError.writeFailed) {
            try Redactor(remover: FailsToWrite()).apply(to: document.dataRepresentation()!)
        }
    }

    @Test func refusesWithoutMarks() {
        #expect(throws: RedactionError.noMarks) { try Redactor().apply(to: Fixtures.textDocument()) }
        #expect(throws: RedactionError.unreadable) { try Redactor().apply(to: Data("nope".utf8)) }
    }

    @Test func findAndRedactEveryOccurrence() throws {
        let document = doc(Fixtures.textDocument())
        let hits = PDFSearch.hits(in: document, query: "secret-4417", options: .init())
        #expect(hits.count == 3)
        for hit in hits {
            let page = document.page(at: hit.pageIndex)!
            for rect in PDFSearch.lineRects(for: hit.range, on: page) {
                page.addAnnotation(RedactionMarks.makeMark(bounds: rect.insetBy(dx: -1, dy: -1)))
            }
        }
        let (data, report) = try Redactor().apply(to: document.dataRepresentation()!)
        #expect(!allText(doc(data)).contains(Fixtures.secret))
        #expect(report.areaCount == 3)
        #expect(report.pageCount == 3)
    }

    @Test func rasterizedLineListsPages() {
        var report = RedactionReport(areaCount: 1, pageCount: 1, rasterizedPages: [0, 3, 4], removedAnnotations: 0, metadataCleared: true)
        #expect(report.rasterizedLine == "Pages 1, 4 and 5 were converted to images to make sure their content is gone. Their text can no longer be selected.")
        report.rasterizedPages = []
        #expect(report.rasterizedLine == nil)
    }
}

@Suite struct VerifierTests {
    @Test func charactersInsideRects() {
        let document = doc(Fixtures.textDocument(pages: 1))
        let page = document.page(at: 0)!
        let rect = bounds(of: "\(Fixtures.secret)-1", in: document)
        #expect(RedactionVerifier.characters(on: page, in: [rect]) == "\(Fixtures.secret)-1")
    }

    @Test func checkFlagsSurvivingWords() {
        let document = doc(Fixtures.textDocument(pages: 1))
        let page = document.page(at: 0)!
        let rect = bounds(of: "\(Fixtures.secret)-1", in: document)
        let check = RedactionVerifier.check(original: page, redacted: page, rects: [rect])
        #expect(!check.passed)
        #expect(check.survivingWords == ["\(Fixtures.secret)-1"])
    }

    @Test func tokensDropSingleCharacters() {
        #expect(RedactionVerifier.tokens("a bc  def\nx") == ["bc", "def"])
    }
}
