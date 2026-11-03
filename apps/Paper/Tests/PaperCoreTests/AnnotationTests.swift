import AppKit
import PDFKit
import Testing
@testable import PaperCore
import PaperFixtures

@Suite struct AnnotationTests {
    let factory = AnnotationFactory(author: "Test Reader", now: { Date(timeIntervalSince1970: 1_000_000) })

    @Test func multiLineHighlightIsOneAnnotation() {
        let rects = [CGRect(x: 72, y: 700, width: 200, height: 18), CGRect(x: 72, y: 680, width: 120, height: 18)]
        let highlight = factory.markup(.highlight, color: InkColor.green.nsColor, lineRects: rects)!
        #expect(highlight.type == "Highlight")
        #expect(highlight.bounds == CGRect(x: 72, y: 680, width: 200, height: 38))
        #expect(highlight.quadrilateralPoints?.count == 8)
        #expect(highlight.userName == "Test Reader")
        let document = doc(Fixtures.textDocument(pages: 1))
        document.page(at: 0)!.addAnnotation(highlight)
        let saved = doc(document.dataRepresentation()!).page(at: 0)!.annotations.first!
        #expect(saved.type == "Highlight")
        #expect(RedactionMarks.quadRects(of: saved).count == 2)
    }

    @Test func underlineAndStrike() {
        let rect = [CGRect(x: 0, y: 0, width: 10, height: 10)]
        #expect(factory.markup(.underline, color: .red, lineRects: rect)?.type == "Underline")
        #expect(factory.markup(.strikeOut, color: .red, lineRects: rect)?.type == "StrikeOut")
        #expect(factory.markup(.highlight, color: .red, lineRects: []) == nil)
    }

    @Test func shapes() {
        let box = factory.shape(.rectangle, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 50, y: 160), color: .red, fill: nil, lineWidth: 2)
        #expect(box.type == "Square")
        #expect(box.bounds == CGRect(x: 50, y: 100, width: 50, height: 60))
        #expect(factory.shape(.oval, from: .zero, to: CGPoint(x: 10, y: 10), color: .red, fill: .blue, lineWidth: 1).type == "Circle")
        let arrow = factory.shape(.arrow, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 150), color: .red, fill: nil, lineWidth: 2)
        #expect(arrow.type == "Line")
        #expect(arrow.endLineStyle == .openArrow)
        #expect(arrow.bounds.origin.x + arrow.startPoint.x == 100)
        #expect(arrow.bounds.origin.y + arrow.endPoint.y == 150)
    }

    @Test func textBoxGrowsWithText() {
        let short = factory.textBox("Hi", topLeft: CGPoint(x: 100, y: 500), fontSize: 12, color: .black)
        let long = factory.textBox("A much longer line of text", topLeft: CGPoint(x: 100, y: 500), fontSize: 12, color: .black)
        #expect(long.bounds.width > short.bounds.width)
        #expect(short.bounds.maxY == 500)
        #expect(short.type == "FreeText")
        #expect(short.contents == "Hi")
    }

    @Test func noteAndInk() {
        let note = factory.note("Check this", at: CGPoint(x: 50, y: 50))
        #expect(note.type == "Text")
        #expect(note.bounds.contains(CGPoint(x: 50, y: 50)))
        let ink = factory.ink([[CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 30), CGPoint(x: 40, y: 10)]], color: .blue, lineWidth: 2)!
        #expect(ink.type == "Ink")
        #expect(ink.paths?.count == 1)
        #expect(ink.bounds.contains(CGPoint(x: 10, y: 10)))
        #expect(factory.ink([], color: .blue, lineWidth: 2) == nil)
    }

    @Test func resizingInkScalesItsStrokes() {
        let ink = factory.ink([[CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50)]], color: .blue, lineWidth: 1)!
        let before = ink.paths!.first!.bounds
        let target = CGRect(x: ink.bounds.minX, y: ink.bounds.minY, width: ink.bounds.width * 2, height: ink.bounds.height * 2)
        AnnotationGeometry.resize(ink, to: target)
        #expect(ink.bounds == target)
        let after = ink.paths!.first!.bounds
        #expect(abs(after.width - before.width * 2) < 0.5)
    }

    @Test func resizingLinesScalesEnds() {
        let line = factory.shape(.line, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100), color: .red, fill: nil, lineWidth: 1)
        let end = line.endPoint
        AnnotationGeometry.resize(line, to: CGRect(origin: line.bounds.origin, size: CGSize(width: line.bounds.width * 2, height: line.bounds.height)))
        #expect(abs(line.endPoint.x - end.x * 2) < 0.01)
    }

    @Test func handleDragging() {
        let bounds = CGRect(x: 100, y: 100, width: 100, height: 50)
        let dragged = AnnotationGeometry.dragging(handle: 3, of: bounds, to: CGPoint(x: 300, y: 300), keepAspect: false)
        #expect(dragged == CGRect(x: 100, y: 100, width: 200, height: 200))
        let kept = AnnotationGeometry.dragging(handle: 3, of: bounds, to: CGPoint(x: 300, y: 120), keepAspect: true)
        #expect(abs(kept.width / kept.height - 2) < 0.001)
        let flipped = AnnotationGeometry.dragging(handle: 0, of: bounds, to: CGPoint(x: 50, y: 50), keepAspect: false)
        #expect(flipped == CGRect(x: 50, y: 50, width: 150, height: 100))
    }

    @Test func shiftConstrains() {
        let square = AnnotationGeometry.constrained(from: .zero, to: CGPoint(x: 30, y: -10), kind: .rectangle)
        #expect(square == CGPoint(x: 30, y: -30))
        let line = AnnotationGeometry.constrained(from: .zero, to: CGPoint(x: 100, y: 5), kind: .line)
        #expect(abs(line.y) < 0.001)
    }

    @Test func editability() {
        #expect(AnnotationGeometry.isEditable(factory.note("x", at: .zero)))
        #expect(!AnnotationGeometry.isResizable(factory.note("x", at: .zero)))
        let widget = PDFAnnotation(bounds: .zero, forType: .widget, withProperties: nil)
        #expect(!AnnotationGeometry.isEditable(widget))
        #expect(!AnnotationGeometry.isResizable(factory.markup(.highlight, color: .red, lineRects: [CGRect(x: 0, y: 0, width: 5, height: 5)])!))
    }

    @Test func nearestColor() {
        #expect(InkColor.nearest(to: InkColor.pink.nsColor) == .pink)
        #expect(InkColor.nearest(to: NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)) == nil)
    }
}

@Suite struct SignatureTests {
    let strokes: [[CGPoint]] = [[CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 60)], [CGPoint(x: 30, y: 20), CGPoint(x: 60, y: 40)]]

    @Test func normalizes() {
        let signature = Signature.from(strokes: strokes)!
        #expect(abs(signature.aspect - 2) < 0.001)
        let xs = signature.strokes.flatMap { $0 }.map(\.x)
        #expect(xs.min() == 0)
        #expect(xs.max() == 1)
        #expect(Signature.from(strokes: [[CGPoint(x: 1, y: 1)]]) == nil)
        #expect(Signature.from(strokes: [[CGPoint(x: 1, y: 1), CGPoint(x: 1.5, y: 1.2)]]) == nil)
    }

    @Test func fitsKeepingAspect() {
        let fit = Signature.fitted(aspect: 2, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(fit == CGRect(x: 0, y: 25, width: 100, height: 50))
    }

    @Test func placesAsTaggedInk() {
        let signature = Signature.from(strokes: strokes)!
        let ink = signature.annotation(centeredAt: CGPoint(x: 300, y: 300), width: 180, color: .black, factory: AnnotationFactory(author: nil))!
        #expect(ink.type == "Ink")
        #expect(Signature.isSignature(ink))
        #expect(abs(ink.bounds.midX - 300) < 0.5)
        #expect(ink.paths?.count == 2)
    }

    @Test func libraryKeepsNewestFirstAndCaps() throws {
        let store = InMemorySignatureStore()
        var library = SignatureLibrary(store: store)
        for _ in 0..<(SignatureLibrary.limit + 2) { try library.add(Signature.from(strokes: strokes)!) }
        #expect(library.signatures.count == SignatureLibrary.limit)
        let newest = Signature.from(strokes: strokes)!
        try library.add(newest)
        #expect(library.signatures.first?.id == newest.id)
        try library.remove(id: newest.id)
        #expect(try store.load().count == SignatureLibrary.limit - 1)
    }

    @Test func fileStoreRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("paper-unit-\(UUID().uuidString)/signatures.json")
        let store = FileSignatureStore(url: url)
        #expect(try store.load().isEmpty)
        let signature = Signature.from(strokes: strokes)!
        try store.save([signature])
        #expect(try store.load() == [signature])
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

@Suite struct AppearanceTests {
    @Test func resizingDropsASavedAppearance() {
        let document = doc(Fixtures.textDocument(pages: 1))
        let factory = AnnotationFactory(author: nil)
        document.page(at: 0)!.addAnnotation(factory.shape(.rectangle, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 150), color: .red, fill: nil, lineWidth: 2))
        let saved = doc(document.dataRepresentation()!)
        let box = saved.page(at: 0)!.annotations.first!
        AnnotationGeometry.resize(box, to: CGRect(x: 100, y: 100, width: 200, height: 120))
        #expect(box.value(forAnnotationKey: .appearanceDictionary) == nil)
        #expect(box.bounds.size == CGSize(width: 200, height: 120))
    }
}
