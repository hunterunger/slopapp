import AppKit
import PDFKit
import Testing
@testable import PaperCore
import PaperFixtures

/// Pending marks and signatures must survive save + reopen on every macOS Paper supports
/// (research P20). These simulate a PDFKit that doesn't read Paper's keys back.
@Suite struct AnnotationTagTests {
    /// A document with one pending mark, written to bytes.
    func savedMark() throws -> (data: Data, rect: CGRect) {
        let document = doc(Fixtures.textDocument(pages: 1))
        let annotation = mark("\(Fixtures.secret)-1", in: document)
        return (try #require(document.dataRepresentation()), annotation.bounds)
    }

    /// What a PDFKit that drops `/NM`, `/Subj` and `/Contents` on read would hand back.
    func forget(_ annotation: PDFAnnotation) {
        annotation.removeValue(forAnnotationKey: .name)
        annotation.removeValue(forAnnotationKey: AnnotationTags.subjectKey)
        annotation.contents = nil
        AnnotationTags.setMemoryTag(nil, on: annotation)
    }

    @Test func tagsAreWrittenIntoStandardEntries() throws {
        let (data, rect) = try savedMark()
        let entries = RawAnnotationReader.read(data)[0] ?? []
        let entry = try #require(entries.first, "No annotation in the file. \(tagDiagnostics(doc(data), data))")
        #expect(entry.subtype == "Square")
        #expect(entry.rect.isClose(to: rect))
        #expect(entry.tag == .redactionMark)
        #expect(entry.contents == AnnotationTags.legacyMarkContents)
        if let name = entry.name { #expect(name.hasPrefix("paper.redaction.")) }
        // /Subj is written by PDFKit on macOS 27; other versions may drop it, which the
        // other signals cover. Only check it where it's there.
        if let subject = entry.subject { #expect(subject == PaperTag.redactionMark.subject) }
    }

    @Test func marksComeBackFromTheFileWhenPDFKitForgetsThem() throws {
        let (data, _) = try savedMark()
        let reopened = doc(data)
        let annotation = try #require(reopened.page(at: 0)?.annotations.first)
        forget(annotation)
        #expect(!RedactionMarks.isMark(annotation))
        #expect(AnnotationTags.restore(in: reopened, from: data) == 1)
        #expect(RedactionMarks.isMark(annotation))
        // Restoring also puts the keys back in memory, so the next save writes them.
        #expect((annotation.value(forAnnotationKey: .name) as? String)?.hasPrefix("paper.redaction.") == true)
        #expect(annotation.contents == AnnotationTags.legacyMarkContents)
    }

    @Test func legacyMarksWithOnlyTheirContentsAreMigrated() throws {
        // A mark as Paper 0.1 saved it on a macOS that dropped `/NM`: a Square whose only
        // trace is "Pending redaction" in /Contents.
        let document = doc(Fixtures.textDocument(pages: 1))
        let square = PDFAnnotation(bounds: bounds(of: "\(Fixtures.secret)-1", in: document), forType: .square, withProperties: nil)
        square.contents = "Pending redaction"
        document.page(at: 0)!.addAnnotation(square)
        let legacy = try #require(document.dataRepresentation())
        #expect(RawAnnotationReader.read(legacy)[0]?.first?.name == nil)

        let opened = try #require(AnnotationTags.open(legacy))
        #expect(RedactionMarks.marks(in: opened).count == 1)
        // The next save writes the full tag.
        let resaved = try #require(opened.dataRepresentation())
        #expect(RawAnnotationReader.read(resaved)[0]?.first?.tag == .redactionMark)
        // And Apply still finds it.
        let (output, report) = try Redactor().apply(to: legacy)
        #expect(report.areaCount == 1)
        #expect(!allText(doc(output)).contains("\(Fixtures.secret)-1"))
    }

    @Test func ordinaryAnnotationsAreNotTagged() {
        #expect(AnnotationTags.classify(subtype: "Square", name: nil, subject: nil, contents: nil) == nil)
        #expect(AnnotationTags.classify(subtype: "Square", name: "abc", subject: "Rectangle", contents: "Note") == nil)
        #expect(AnnotationTags.classify(subtype: "Text", name: nil, subject: nil, contents: "Pending redaction") == nil)
        #expect(AnnotationTags.classify(subtype: "Ink", name: "paper.redaction.x", subject: nil, contents: nil) == nil)
        #expect(AnnotationTags.classify(subtype: "Square", name: nil, subject: "Pending Redaction", contents: nil) == .redactionMark)
        #expect(AnnotationTags.classify(subtype: "Ink", name: nil, subject: "Signature", contents: nil) == .signature)
    }

    @Test func untaggedSquaresAreLeftAlone() throws {
        let document = doc(Fixtures.textDocument(pages: 1))
        let square = PDFAnnotation(bounds: CGRect(x: 50, y: 50, width: 40, height: 40), forType: .square, withProperties: nil)
        document.page(at: 0)!.addAnnotation(square)
        let data = try #require(document.dataRepresentation())
        let opened = try #require(AnnotationTags.open(data))
        #expect(RedactionMarks.marks(in: opened).isEmpty)
    }

    @Test func signaturesSurviveSaveAndReopen() throws {
        let document = doc(Fixtures.textDocument(pages: 1))
        let signature = try #require(Signature.from(strokes: [[CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 5)], [CGPoint(x: 3, y: 0), CGPoint(x: 8, y: 9)]]))
        let ink = try #require(signature.annotation(centeredAt: CGPoint(x: 300, y: 200), width: 150, color: .black, factory: AnnotationFactory(author: nil)))
        document.page(at: 0)!.addAnnotation(ink)
        let data = try #require(document.dataRepresentation())
        let opened = try #require(AnnotationTags.open(data))
        let reopened = try #require(opened.page(at: 0)?.annotations.first)
        #expect(Signature.isSignature(reopened), "\(tagDiagnostics(opened, data))")
        // And when PDFKit forgets the keys, the file still says so.
        let plain = doc(data)
        let forgotten = try #require(plain.page(at: 0)?.annotations.first)
        forget(forgotten)
        AnnotationTags.restore(in: plain, from: data)
        #expect(Signature.isSignature(forgotten))
    }

    @Test func pageCopiesKeepTheirTags() throws {
        let document = doc(Fixtures.textDocument())
        mark("\(Fixtures.secret)-2", in: document, page: 1)
        let extracted = PageOps.extract(document, pages: IndexSet([1]))
        #expect(RedactionMarks.marks(in: extracted).count == 1)
        let combined = PageOps.combine([document, document])
        #expect(RedactionMarks.marks(in: combined).count == 2)
    }

    @Test func flattenLeavesReopenedMarksOut() throws {
        // Flattening reads the saved bytes; marks must still be found there and left out
        // instead of being baked in as red boxes.
        let (data, rect) = try savedMark()
        let flat = doc(try Flattener.flatten(data))
        let image = try #require(PageRenderer.render(flat.page(at: 0)!, region: rect.insetBy(dx: 2, dy: 2), scale: 1))
        #expect(PageRenderer.meanLuminance(image) < 0.9) // the text is still there
        #expect(allText(flat).contains("\(Fixtures.secret)-1"))
        #expect(annotationCount(flat) == 0)
    }

    @Test func encryptedFilesRestoreWithThePassword() throws {
        let document = doc(Fixtures.textDocument(pages: 1))
        mark("\(Fixtures.secret)-1", in: document)
        let data = try #require(document.dataRepresentation(options: [PDFDocumentWriteOption.userPasswordOption: "pw", PDFDocumentWriteOption.ownerPasswordOption: "pw"]))
        #expect(RawAnnotationReader.read(data).isEmpty)
        let raw = RawAnnotationReader.read(data, password: "pw")
        #expect(raw[0]?.first?.tag == .redactionMark)
        let opened = try #require(AnnotationTags.open(data, password: "pw"))
        #expect(RedactionMarks.marks(in: opened).count == 1)
    }
}
