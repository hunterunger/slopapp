import AppKit
import PDFKit
import Testing
@testable import PaperCore
import PaperFixtures

/// A photo-like signature: dark strokes on off-white paper, with one speck of dust.
func signaturePhoto(width: Int = 800, height: Int = 300) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(gray: 0.92, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
    context.setLineWidth(10)
    context.setLineCap(.round)
    // Ink spans x 200...600, y 100...200 (y up).
    context.move(to: CGPoint(x: 200, y: 100))
    context.addCurve(to: CGPoint(x: 600, y: 200), control1: CGPoint(x: 300, y: 260), control2: CGPoint(x: 450, y: 40))
    context.strokePath()
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 20, y: 280, width: 1, height: 1)) // dust
    return context.makeImage()!
}

@Suite struct SignatureImportTests {
    @Test func thresholdFallsBetweenPaperAndInk() throws {
        let gray = try #require(SignatureImport.luminance(of: signaturePhoto()))
        let threshold = SignatureImport.suggestedThreshold(gray.values)
        #expect(threshold > 0.15 && threshold < 0.9)
    }

    @Test func knocksOutPaperAndCropsToInk() throws {
        let gray = try #require(SignatureImport.luminance(of: signaturePhoto()))
        let mask = try #require(SignatureImport.mask(width: gray.width, height: gray.height, values: gray.values, threshold: 0.5))
        // Scaled to 600 wide (0.75): ink about 300+stroke wide, the speck of dust ignored.
        #expect(mask.width > 290 && mask.width < 330)
        #expect(mask.height < 150)
        #expect(Double(mask.inkCount) / Double(mask.width * mask.height) < 0.5)
    }

    @Test func blankImagesMakeNoSignature() {
        let context = CGContext(data: nil, width: 100, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
        #expect(SignatureImport.signature(from: context.makeImage()!) == nil)
    }

    @Test func placesAsSolidInkThatSurvivesSaving() throws {
        let signature = try #require(SignatureImport.signature(from: signaturePhoto()))
        #expect(signature.isImage)
        #expect(signature.strokes.count > 20)
        #expect(signature.aspect > 2)
        let document = doc(Fixtures.pdf(pages: 1) { _, _ in })
        let page = try #require(document.page(at: 0))
        let ink = try #require(signature.annotation(centeredAt: CGPoint(x: 300, y: 400), width: 200, color: .black,
                                                     factory: AnnotationFactory(author: nil)))
        page.addAnnotation(ink)
        #expect(Signature.isSignature(ink))
        #expect(AnnotationGeometry.isBanded(ink.paths ?? []))
        let data = try #require(document.dataRepresentation())
        let saved = try #require(AnnotationTags.open(data))
        let placed = try #require(saved.page(at: 0)?.annotations.first)
        #expect(Signature.isSignature(placed))
        // The ink is dark where the stroke is and the paper stays white around it.
        let savedPage = try #require(saved.page(at: 0))
        let rendered = try #require(PageRenderer.render(savedPage, region: placed.bounds, scale: 2))
        let luminance = PageRenderer.meanLuminance(rendered)
        #expect(luminance > 0.5 && luminance < 0.97)
    }

    @Test func resizingKeepsBandsTouching() throws {
        let signature = try #require(SignatureImport.signature(from: signaturePhoto()))
        let ink = try #require(signature.annotation(centeredAt: CGPoint(x: 300, y: 400), width: 200, color: .black,
                                                     factory: AnnotationFactory(author: nil)))
        let before = try #require(ink.paths?.first?.lineWidth)
        AnnotationGeometry.resize(ink, to: CGRect(x: ink.bounds.minX, y: ink.bounds.minY, width: ink.bounds.width * 2, height: ink.bounds.height * 2))
        let after = try #require(ink.paths?.first?.lineWidth)
        #expect(abs(after - before * 2) < 0.01)
    }

    @Test func oldLibrariesWithoutLineWidthStillLoad() throws {
        let json = #"[{"id":"7D8E1F40-1C1B-4E43-9F33-2C9C9B6F1A11","kind":"signature","created":0,"strokes":[[[0,0],[1,0.2]]],"aspect":5}]"#
        let decoded = try JSONDecoder().decode([Signature].self, from: Data(json.utf8))
        #expect(decoded.first?.lineWidth == nil)
        #expect(decoded.first?.isImage == false)
    }
}

/// Returns fixed lines, like Vision would for the scan fixture.
struct FakeRecognizer: TextRecognizing {
    var lines: [RecognizedLine]
    func recognize(_ image: CGImage) throws -> [RecognizedLine] { lines }
}

@Suite struct OCRTests {
    // The scan fixture's first line sits at about y 672...700 of 792 and x 72...420 of 612.
    let invoiceLine = RecognizedLine(text: "Scanned invoice number 55821",
                                     box: CGRect(x: 72.0 / 612, y: 668.0 / 792, width: 340.0 / 612, height: 30.0 / 792))
    let totalLine = RecognizedLine(text: "Total due forty dollars",
                                   box: CGRect(x: 72.0 / 612, y: 620.0 / 792, width: 280.0 / 612, height: 30.0 / 792))

    @Test func findsPagesWithoutText() {
        #expect(OCR.needsText(doc(Fixtures.scanDocument()).page(at: 0)!))
        #expect(!OCR.needsText(doc(Fixtures.scanDocument(withHiddenText: true)).page(at: 0)!))
        #expect(!OCR.needsText(doc(Fixtures.textDocument()).page(at: 0)!))
    }

    @Test func addsAnInvisibleSearchableLayer() throws {
        let document = doc(Fixtures.scanDocument())
        let page = try #require(document.page(at: 0))
        let before = try #require(PageRenderer.render(page, region: page.bounds(for: .mediaBox), scale: 0.5))
        let searchable = try #require(OCR.page(byAdding: [invoiceLine, totalLine], to: page))
        #expect(searchable.string?.contains("Scanned invoice number 55821") == true)
        #expect(searchable.string?.contains("Total due forty dollars") == true)
        // Nothing visible changed.
        let after = try #require(PageRenderer.render(searchable, region: searchable.bounds(for: .mediaBox), scale: 0.5))
        #expect(abs(PageRenderer.meanLuminance(before) - PageRenderer.meanLuminance(after)) < 0.002)
        // The words are where the scan shows them, so selecting and highlighting line up.
        let hit = try #require(PDFSearch.hits(on: searchable, pageIndex: 0, query: "55821", options: .init()).first)
        let rect = try #require(PDFSearch.lineRects(for: hit.range, on: searchable).first)
        #expect(rect.midY > 660 && rect.midY < 705)
        #expect(rect.minX > 250 && rect.maxX < 430)
    }

    @Test func survivesSavingAndKeepsPageGeometry() throws {
        let document = doc(Fixtures.rotatedDocument())
        let page = try #require(document.page(at: 0))
        let searchable = try #require(OCR.page(byAdding: [RecognizedLine(text: "Sideways words", box: CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.04))], to: page))
        #expect(searchable.rotation == page.rotation)
        #expect(searchable.bounds(for: .mediaBox) == page.bounds(for: .mediaBox))
        #expect(searchable.bounds(for: .cropBox) == page.bounds(for: .cropBox))
        document.removePage(at: 0)
        document.insert(searchable, at: 0)
        let saved = doc(try #require(document.dataRepresentation()))
        #expect(saved.page(at: 0)?.string?.contains("Sideways words") == true)
        #expect(saved.page(at: 0)?.rotation == 90)
    }

    @Test func movesAnnotationsAcross() throws {
        let document = doc(Fixtures.scanDocument())
        let page = try #require(document.page(at: 0))
        page.addAnnotation(RedactionMarks.makeMark(bounds: CGRect(x: 100, y: 100, width: 50, height: 20)))
        page.addAnnotation(AnnotationFactory(author: nil).note("hi", at: CGPoint(x: 300, y: 300)))
        let count = page.annotations.count // the note brings its pop-up along
        let searchable = try #require(OCR.page(byAdding: [invoiceLine], to: page))
        #expect(searchable.annotations.isEmpty)
        PageRewriter.moveAnnotations(from: page, to: searchable)
        #expect(page.annotations.isEmpty)
        #expect(searchable.annotations.count == count)
        #expect(searchable.annotations.contains(where: RedactionMarks.isMark))
    }

    @Test func copyTextReadsTopToBottom() throws {
        let page = try #require(doc(Fixtures.scanDocument()).page(at: 0))
        let text = try OCR.text(of: page, recognizer: FakeRecognizer(lines: [totalLine, invoiceLine]))
        #expect(text == "Scanned invoice number 55821\nTotal due forty dollars")
    }

    @Test func rendersThePageAsDisplayed() throws {
        let page = try #require(doc(Fixtures.rotatedDocument()).page(at: 0))
        let image = try #require(OCR.displayImage(of: page, scale: 1))
        let size = OCR.displaySize(of: page)
        #expect(image.width == Int(size.width.rounded()))
        #expect(image.height == Int(size.height.rounded()))
        #expect(size.width > size.height) // a portrait page rotated 90°
    }

    /// Real Vision. Slow the first time in a process (macOS prepares the model), so it only
    /// runs when asked: PAPER_VISION_TESTS=1 swift test --filter OCRTests
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PAPER_VISION_TESTS"] == "1"))
    func visionReadsTheScanFixture() throws {
        let page = try #require(doc(Fixtures.scanDocument()).page(at: 0))
        let image = try #require(OCR.displayImage(of: page))
        let lines = try VisionTextRecognizer().recognize(image)
        let searchable = try #require(OCR.page(byAdding: lines, to: page))
        let hit = try #require(PDFSearch.hits(on: searchable, pageIndex: 0, query: "55821", options: .init()).first)
        let rect = try #require(PDFSearch.lineRects(for: hit.range, on: searchable).first)
        #expect(rect.midY > 640 && rect.midY < 720)
    }
}

@Suite struct ImageExportTests {
    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("paper-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func namesSortInPageOrder() {
        #expect(ImageExport.fileName(base: "Report", page: 2, count: 12, format: .png) == "Report page 03.png")
        #expect(ImageExport.fileName(base: "Report", page: 0, count: 3, format: .jpeg) == "Report page 1.jpeg")
    }

    @Test func writesOneImagePerPageAtTheChosenResolution() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try ImageExport.export(doc(Fixtures.textDocument()), pages: IndexSet([0, 2]), format: .png, dpi: 144,
                                          to: directory, baseName: "text")
        #expect(urls.map(\.lastPathComponent) == ["text page 1.png", "text page 3.png"])
        let image = try #require(NSImage(contentsOf: urls[0])?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(image.width == 1224 && image.height == 1584)
    }

    @Test func rotatedAndLandscapePagesKeepTheirShape() throws {
        let page = try #require(doc(Fixtures.rotatedDocument()).page(at: 0))
        let image = try #require(ImageExport.image(of: page, dpi: 72))
        #expect(image.width > image.height)
    }

    @Test func stopsWhenCancelled() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try ImageExport.export(doc(Fixtures.textDocument()), pages: IndexSet(0..<3), format: .jpeg, dpi: 72,
                                          to: directory, baseName: "t") { done, _ in done < 1 }
        #expect(urls.count == 1)
    }

    @Test func pngAndJPEGAreAlwaysAvailable() {
        #expect(ImageExport.Format.available.contains(.png))
        #expect(ImageExport.Format.available.contains(.jpeg))
    }
}

@Suite struct ProtectionTests {
    @Test func openPasswordLocksTheCopy() throws {
        let data = try Protection(openPassword: "s3cret").protect(doc(Fixtures.textDocument()))
        let copy = doc(data)
        #expect(copy.isEncrypted && copy.isLocked)
        #expect(!copy.unlock(withPassword: "wrong"))
        #expect(copy.unlock(withPassword: "s3cret"))
        #expect(allText(copy).contains("public sentence"))
    }

    @Test func restrictionsNeedTheirOwnPassword() throws {
        #expect(Protection().problem == .nothingToProtect)
        #expect(Protection(allowPrinting: false).problem == .needsPermissionsPassword)
        #expect(Protection(openPassword: "a", permissionsPassword: "a", allowCopying: false).problem == .samePasswords)
        let data = try Protection(permissionsPassword: "owner", allowPrinting: false, allowCopying: false).protect(doc(Fixtures.textDocument()))
        let copy = doc(data)
        #expect(copy.isEncrypted && !copy.isLocked)
        #expect(!copy.allowsPrinting)
        #expect(!copy.allowsCopying)
    }

    @Test func theOriginalIsUntouched() throws {
        let document = doc(Fixtures.textDocument())
        _ = try Protection(openPassword: "x").protect(document)
        #expect(!document.isEncrypted)
        #expect(!doc(try #require(document.dataRepresentation())).isEncrypted)
    }
}

@Suite struct DocumentInfoTests {
    @Test func readsAndWritesTheEditableFields() throws {
        let document = doc(Fixtures.textDocument(title: "Old", author: "Someone"))
        var info = DocumentInfo(document)
        #expect(info.title == "Old")
        #expect(info.author == "Someone")
        #expect(info.keywords == "fixture")
        info.title = "Quarterly report"
        info.subject = "Numbers"
        info.keywords = "q3,  finance , ,"
        info.author = "  "
        info.apply(to: document)
        let saved = doc(try #require(document.dataRepresentation()))
        let reread = DocumentInfo(saved)
        #expect(reread.title == "Quarterly report")
        #expect(reread.subject == "Numbers")
        #expect(reread.keywords == "q3, finance")
        #expect(reread.author.isEmpty)
    }

    @Test func describesPaperSizes() {
        #expect(FileFacts.describe(CGSize(width: 612, height: 792), rotation: 0, metric: false) == "8.5 × 11 in (Letter)")
        #expect(FileFacts.describe(CGSize(width: 595, height: 842), rotation: 0, metric: true) == "210 × 297 mm (A4)")
        #expect(FileFacts.describe(CGSize(width: 595, height: 842), rotation: 90, metric: true) == "297 × 210 mm (A4, landscape)")
        #expect(FileFacts.describe(CGSize(width: 300, height: 300), rotation: 0, metric: false) == "4.17 × 4.17 in")
    }

    @Test func factsComeFromTheFile() throws {
        let document = doc(Fixtures.textDocument())
        let facts = FileFacts(document, fileURL: nil)
        #expect(facts.pageCount == 3)
        #expect(facts.pageSize?.contains("Letter") == true)
        #expect(facts.fileSize == nil)
        #expect(!facts.isEncrypted)
    }
}

@Suite struct TextMarkupTests {
    @Test func highlightsEverySearchResult() throws {
        let document = doc(Fixtures.textDocument())
        let hits = PDFSearch.hits(in: document, query: "public sentence", options: .init())
        let made = TextMarkup.annotations(for: hits, in: document, style: .highlight, color: InkColor.yellow.nsColor,
                                          factory: AnnotationFactory(author: "Reviewer"))
        #expect(made.count == 3)
        #expect(made.allSatisfy { $0.annotation.type == "Highlight" && $0.annotation.userName == "Reviewer" })
        for item in made { item.page.addAnnotation(item.annotation) }
        let saved = doc(try #require(document.dataRepresentation()))
        #expect(annotationCount(saved) == 3)
    }

    @Test func findsMarkupUnderASelection() throws {
        let document = doc(Fixtures.textDocument(pages: 1))
        let page = try #require(document.page(at: 0))
        let hit = try #require(PDFSearch.hits(in: document, query: "nobody", options: .init()).first)
        let rects = PDFSearch.lineRects(for: hit.range, on: page)
        let highlight = try #require(AnnotationFactory(author: nil).markup(.highlight, color: .yellow, lineRects: rects))
        page.addAnnotation(highlight)
        page.addAnnotation(AnnotationFactory(author: nil).note("not markup", at: CGPoint(x: rects[0].midX, y: rects[0].midY)))
        #expect(TextMarkup.markup(on: page, overlapping: rects) == [highlight])
        #expect(TextMarkup.markup(on: page, overlapping: [CGRect(x: 0, y: 0, width: 10, height: 10)]).isEmpty)
    }
}

@Suite struct HeaderFooterTests {
    @Test func expandsTokens() {
        var stamp = HeaderFooter()
        stamp.batesPrefix = "ACME-"
        stamp.batesStart = 41
        stamp.batesDigits = 5
        let context = HeaderFooter.Context(page: 2, pageCount: 9, sequence: 1, name: "Lease")
        #expect(stamp.expand("Page {page} of {pages}", context) == "Page 2 of 9")
        #expect(stamp.expand("{bates}", context) == "ACME-00042")
        #expect(stamp.expand("{name}", context) == "Lease")
        #expect(HeaderFooter().isEmpty)
        #expect(!HeaderFooter.pageNumbers.isEmpty)
    }

    @Test func stampsSearchableTextAtTheBottom() throws {
        let document = doc(Fixtures.textDocument())
        let page = try #require(document.page(at: 1))
        let stamped = try #require(HeaderFooter.pageNumbers.stamped(page, .init(page: 2, pageCount: 3, sequence: 1, name: "t")))
        #expect(stamped.string?.contains("Page 2 of 3") == true)
        #expect(stamped.string?.contains("public sentence") == true)
        let hit = try #require(PDFSearch.hits(on: stamped, pageIndex: 0, query: "Page 2 of 3", options: .init()).first)
        let rect = try #require(PDFSearch.lineRects(for: hit.range, on: stamped).first)
        #expect(rect.minY < 60)
        #expect(abs(rect.midX - 306) < 10)
    }

    @Test func followsRotation() throws {
        let page = try #require(doc(Fixtures.rotatedDocument()).page(at: 0))
        var stamp = HeaderFooter()
        stamp.topRight = "CONFIDENTIAL"
        let stamped = try #require(stamp.stamped(page, .init(page: 1, pageCount: 1, sequence: 0, name: "r")))
        #expect(stamped.rotation == page.rotation)
        #expect(stamped.string?.contains("CONFIDENTIAL") == true)
    }
}
