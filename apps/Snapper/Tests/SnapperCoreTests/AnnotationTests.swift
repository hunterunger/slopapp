import CoreGraphics
import Foundation
import Testing
@testable import SnapperCore

@Suite("Annotations")
struct AnnotationTests {
    @Test func toolKeysAreUniqueAndCaseInsensitive() {
        #expect(Set(Tool.allCases.map(\.key)).count == Tool.allCases.count)
        #expect(Tool.forKey("A") == .arrow)
        #expect(Tool.forKey("c") == .crop)
        #expect(Tool.forKey("z") == nil)
    }

    @Test func lineHitTestingFollowsTheStroke() {
        let line = Annotation(kind: .line, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), width: 4)
        #expect(line.hitTest(CGPoint(x: 50, y: 3), tolerance: 2, loose: false))
        #expect(!line.hitTest(CGPoint(x: 50, y: 10), tolerance: 2, loose: false))
        #expect(!line.hitTest(CGPoint(x: 110, y: 0), tolerance: 2, loose: false))
    }

    @Test func boxesAreGrabbedByTheirOutlineUnlessLoose() {
        let box = Annotation(kind: .rectangle, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), width: 4)
        #expect(box.hitTest(CGPoint(x: 0, y: 50), tolerance: 2, loose: false))
        #expect(!box.hitTest(CGPoint(x: 50, y: 50), tolerance: 2, loose: false))
        #expect(box.hitTest(CGPoint(x: 50, y: 50), tolerance: 2, loose: true))
        let ellipse = Annotation(kind: .ellipse, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 50), width: 4)
        #expect(ellipse.hitTest(CGPoint(x: 100, y: 25), tolerance: 2, loose: false))
        #expect(!ellipse.hitTest(CGPoint(x: 50, y: 25), tolerance: 2, loose: false))
        let blur = Annotation(kind: .blur, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 50))
        #expect(blur.hitTest(CGPoint(x: 50, y: 25), tolerance: 2, loose: false))
    }

    @Test func handlesResizeAndNormalize() {
        let box = Annotation(kind: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 50, y: 50))
        #expect(box.handles.count == 4)
        let flipped = box.moving(.topLeft, to: CGPoint(x: 80, y: 70))
        #expect(flipped.rect == CGRect(x: 50, y: 50, width: 30, height: 20))
        let arrow = Annotation(kind: .arrow, start: .zero, end: CGPoint(x: 10, y: 10))
        #expect(arrow.moving(.end, to: CGPoint(x: 40, y: 0)).end == CGPoint(x: 40, y: 0))
        #expect(Annotation(kind: .counter, start: .zero).handles.isEmpty)
    }

    @Test func movingShiftsEveryPoint() {
        let marker = Annotation(kind: .highlighter, start: .zero, points: [CGPoint(x: 1, y: 1), CGPoint(x: 5, y: 5)])
        let moved = marker.moved(by: CGVector(dx: 10, dy: -1))
        #expect(moved.points == [CGPoint(x: 11, y: 0), CGPoint(x: 15, y: 4)])
    }

    @Test func shiftSnapsLinesTo45DegreesAndBoxesToSquares() {
        let snapped = Annotation.constrained(start: .zero, end: CGPoint(x: 100, y: 8), kind: .arrow)
        #expect(abs(snapped.y) < 0.001)
        let diagonal = Annotation.constrained(start: .zero, end: CGPoint(x: 100, y: 90), kind: .line)
        #expect(abs(diagonal.x - diagonal.y) < 0.001)
        #expect(Annotation.constrained(start: .zero, end: CGPoint(x: -30, y: 10), kind: .rectangle) == CGPoint(x: -30, y: 30))
    }

    @Test func emptyMarksAreDropped() {
        #expect(Annotation(kind: .arrow, start: .zero, end: CGPoint(x: 1, y: 1)).isEmpty)
        #expect(Annotation(kind: .text, start: .zero, text: "  \n").isEmpty)
        #expect(!Annotation(kind: .counter, start: .zero).isEmpty)
    }

    @Test func textSizeGrowsWithLinesAndWidth() {
        let one = TextMetrics.size(of: "Hello", fontSize: 24)
        let two = TextMetrics.size(of: "Hello\nHello", fontSize: 24)
        #expect(one.width > 20)
        #expect(abs(two.height - one.height * 2) < 0.5)
        #expect(TextMetrics.size(of: "Hello", fontSize: 36).width > one.width)
    }

    @Test func textIsKeptInsideTheImage() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
        let size: (Annotation) -> CGSize = { _ in CGSize(width: 80, height: 30) }
        let nearRight = Annotation(kind: .text, start: CGPoint(x: 180, y: 90), text: "Hello")
        let kept = nearRight.keptInside(bounds, textSize: size)
        #expect(kept.start == CGPoint(x: 120, y: 70))
        let inside = Annotation(kind: .text, start: CGPoint(x: 10, y: 10), text: "Hi")
        #expect(inside.keptInside(bounds, textSize: size).start == inside.start)
        let tooWide = Annotation(kind: .text, start: CGPoint(x: 50, y: 0), text: "x")
        #expect(tooWide.keptInside(bounds, textSize: { _ in CGSize(width: 500, height: 20) }).start.x == 0)
        let arrow = Annotation(kind: .arrow, start: CGPoint(x: 500, y: 500))
        #expect(arrow.keptInside(bounds) == arrow)
    }

    @Test func strokeWidthNearest() {
        #expect(StrokeWidth(nearest: 3.9) == .medium)
        #expect(StrokeWidth(nearest: 100) == .thick)
        #expect(PaletteColor.named("White")!.color.isLight)
        #expect(!PaletteColor.named("Blue")!.color.isLight)
    }
}

@Suite("Annotation editor")
struct AnnotationEditorTests {
    func makeEditor() -> AnnotationEditor {
        AnnotationEditor(document: AnnotationDocument(imageSize: CGSize(width: 400, height: 300)))
    }

    @Test func addUndoRedo() {
        var editor = makeEditor()
        let arrow = Annotation(kind: .arrow, start: .zero, end: CGPoint(x: 50, y: 50))
        editor.add(arrow)
        #expect(editor.document.annotations.count == 1)
        #expect(editor.selection == arrow.id)
        editor.undo()
        #expect(editor.document.annotations.isEmpty)
        #expect(editor.selection == nil)
        #expect(editor.canRedo)
        editor.redo()
        #expect(editor.document.annotations == [arrow])
    }

    @Test func aDragIsOneUndoStep() {
        var editor = makeEditor()
        let box = Annotation(kind: .rectangle, start: .zero, end: CGPoint(x: 10, y: 10))
        editor.add(box)
        editor.beginChange()
        for step in 1...20 {
            editor.update(box.moved(by: CGVector(dx: CGFloat(step), dy: 0)))
        }
        editor.commitChange()
        #expect(editor.document.annotations[0].start.x == 20)
        editor.undo()
        #expect(editor.document.annotations[0].start.x == 0)
        editor.undo()
        #expect(editor.document.annotations.isEmpty)
        #expect(!editor.canUndo)
    }

    @Test func cancelledDragLeavesNoTrace() {
        var editor = makeEditor()
        editor.beginChange()
        editor.add(Annotation(kind: .line, start: .zero, end: CGPoint(x: 30, y: 0)))
        editor.cancelChange()
        #expect(editor.document.annotations.isEmpty)
        #expect(!editor.canUndo)
    }

    @Test func newEditClearsRedo() {
        var editor = makeEditor()
        editor.add(Annotation(kind: .counter, start: .zero))
        editor.undo()
        editor.add(Annotation(kind: .counter, start: CGPoint(x: 5, y: 5)))
        #expect(!editor.canRedo)
    }

    @Test func countersRenumberWithoutGaps() {
        var editor = makeEditor()
        let first = Annotation(kind: .counter, start: CGPoint(x: 10, y: 10))
        let second = Annotation(kind: .counter, start: CGPoint(x: 50, y: 10))
        let third = Annotation(kind: .counter, start: CGPoint(x: 90, y: 10))
        editor.add(first)
        editor.add(Annotation(kind: .arrow, start: .zero, end: CGPoint(x: 40, y: 40)))
        editor.add(second)
        editor.add(third)
        #expect(editor.document.annotations.filter { $0.kind == .counter }.map(\.number) == [1, 2, 3])
        #expect(editor.nextCounterNumber == 4)
        editor.remove(id: second.id)
        #expect(editor.document.annotations.filter { $0.kind == .counter }.map(\.number) == [1, 2])
        editor.undo()
        #expect(editor.document.annotations.filter { $0.kind == .counter }.map(\.number) == [1, 2, 3])
    }

    @Test func styleChangesApplyToTheSelection() {
        var editor = makeEditor()
        let box = Annotation(kind: .rectangle, start: .zero, end: CGPoint(x: 10, y: 10))
        editor.add(box)
        let blue = PaletteColor.named("Blue")!.color
        editor.setColor(blue)
        editor.setWidth(StrokeWidth.thick.points)
        #expect(editor.selected?.color == blue)
        #expect(editor.selected?.width == 8)
        let blur = Annotation(kind: .blur, start: .zero, end: CGPoint(x: 10, y: 10))
        editor.add(blur)
        editor.setColor(PaletteColor.named("Green")!.color)
        #expect(editor.selected?.color == blur.color)
    }

    @Test func hitPicksTheFrontMost() {
        var editor = makeEditor()
        let back = Annotation(kind: .blur, start: .zero, end: CGPoint(x: 100, y: 100))
        let front = Annotation(kind: .pixelate, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 60, y: 60))
        editor.add(back)
        editor.add(front)
        #expect(editor.hit(CGPoint(x: 30, y: 30), tolerance: 2, loose: false)?.id == front.id)
        #expect(editor.hit(CGPoint(x: 90, y: 90), tolerance: 2, loose: false)?.id == back.id)
        // A mark under a later redaction is still on top, so it's the one grabbed.
        let line = Annotation(kind: .line, start: CGPoint(x: 0, y: 90), end: CGPoint(x: 100, y: 90))
        editor.add(line)
        editor.add(Annotation(kind: .blur, start: CGPoint(x: 0, y: 80), end: CGPoint(x: 100, y: 100)))
        #expect(editor.hit(CGPoint(x: 50, y: 90), tolerance: 2, loose: false)?.id == line.id)
        editor.remove(id: line.id)
        editor.selection = front.id
        editor.deleteSelection()
        #expect(editor.document.annotations.first == back)
    }

    @Test func cropClampsAndClears() {
        var editor = makeEditor()
        editor.setCrop(CGRect(x: -50, y: 10, width: 200, height: 100))
        #expect(editor.document.crop == CGRect(x: 0, y: 10, width: 150, height: 100))
        #expect(editor.document.visibleRect == CGRect(x: 0, y: 10, width: 150, height: 100))
        editor.setCrop(CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(editor.document.crop == nil)
        editor.undo()
        #expect(editor.document.crop != nil)
        editor.setCrop(CGRect(x: 0, y: 0, width: 2, height: 2))
        #expect(editor.document.crop == nil)
    }
}

@Suite("Rendering")
struct RenderingTests {
    @Test func plainRenderKeepsPixelSize() throws {
        let base = TestImages.solid(width: 200, height: 100, red: 0, green: 0, blue: 1)
        let renderer = AnnotationRenderer(base: base, scale: 2)
        #expect(renderer.imageSize == CGSize(width: 100, height: 50))
        let output = try #require(renderer.render(AnnotationDocument(imageSize: renderer.imageSize)))
        #expect(output.width == 200 && output.height == 100)
        #expect(TestImages.pixel(output, x: 10, y: 10).b > 240)
    }

    @Test func cropCutsInPixels() throws {
        let base = TestImages.solid(width: 200, height: 100, red: 0, green: 1, blue: 0)
        let renderer = AnnotationRenderer(base: base, scale: 2)
        let output = try #require(renderer.render(AnnotationDocument(imageSize: renderer.imageSize, crop: CGRect(x: 10, y: 5, width: 30, height: 20))))
        #expect(output.width == 60 && output.height == 40)
    }

    @Test func shapesDrawInTheRightPlaceAndColor() throws {
        let base = TestImages.solid(width: 100, height: 100, red: 1, green: 1, blue: 1)
        let renderer = AnnotationRenderer(base: base, scale: 1)
        var document = AnnotationDocument(imageSize: renderer.imageSize)
        // A thick red line across the top 10 points: y is measured from the top.
        document.annotations.append(Annotation(kind: .line, start: CGPoint(x: 0, y: 5), end: CGPoint(x: 100, y: 5),
                                               color: PaletteColor.named("Red")!.color, width: 8))
        let output = try #require(renderer.render(document))
        let top = TestImages.pixel(output, x: 50, y: 5)
        #expect(top.r > 200 && top.g < 100)
        let bottom = TestImages.pixel(output, x: 50, y: 90)
        #expect(bottom.r > 240 && bottom.g > 240)
    }

    @Test func counterAndTextRender() throws {
        let base = TestImages.solid(width: 120, height: 120, red: 1, green: 1, blue: 1)
        let renderer = AnnotationRenderer(base: base, scale: 1)
        var document = AnnotationDocument(imageSize: renderer.imageSize)
        document.annotations.append(Annotation(kind: .counter, start: CGPoint(x: 30, y: 30), color: PaletteColor.named("Blue")!.color, number: 1))
        document.annotations.append(Annotation(kind: .text, start: CGPoint(x: 10, y: 80), color: PaletteColor.named("Black")!.color, text: "Hi"))
        let output = try #require(renderer.render(document))
        // Counter fill just inside its edge is blue.
        let edge = TestImages.pixel(output, x: 30, y: 30 - Int(document.annotations[0].counterRadius) + 3)
        #expect(edge.b > 200 && edge.r < 100)
        // Some dark text pixels exist in the text box.
        let size = TextMetrics.size(document.annotations[1])
        var dark = 0
        for x in 10..<(10 + Int(size.width)) {
            for y in 80..<(80 + Int(size.height)) where TestImages.pixel(output, x: x, y: y).r < 80 {
                dark += 1
            }
        }
        #expect(dark > 10)
    }

    @Test func marksStayVisibleOverALaterRedaction() throws {
        let base = TestImages.solid(width: 100, height: 100, red: 1, green: 1, blue: 1)
        let renderer = AnnotationRenderer(base: base, scale: 1)
        var document = AnnotationDocument(imageSize: renderer.imageSize)
        // A red line first, then a blur over all of it: the line must still show.
        document.annotations.append(Annotation(kind: .line, start: CGPoint(x: 0, y: 50), end: CGPoint(x: 100, y: 50),
                                               color: PaletteColor.named("Red")!.color, width: 8))
        document.annotations.append(Annotation(kind: .blur, start: .zero, end: CGPoint(x: 100, y: 100)))
        let output = try #require(renderer.render(document))
        let onLine = TestImages.pixel(output, x: 50, y: 50)
        #expect(onLine.r > 200 && onLine.g < 100)
    }

    @Test func pixelBlocksGrowWithTheBox() {
        #expect(AnnotationRenderer.pixelBlock(for: CGRect(x: 0, y: 0, width: 200, height: 20)) == 10)
        #expect(AnnotationRenderer.pixelBlock(for: CGRect(x: 0, y: 0, width: 300, height: 100)) == 20)
    }

    @Test(arguments: [AnnotationKind.pixelate, .blur])
    func redactionDestroysDetail(kind: AnnotationKind) throws {
        let base = TestImages.stripes(width: 120, height: 60)
        let renderer = AnnotationRenderer(base: base, scale: 1)
        var document = AnnotationDocument(imageSize: renderer.imageSize)
        document.annotations.append(Annotation(kind: kind, start: CGPoint(x: 20, y: 10), end: CGPoint(x: 100, y: 50)))
        let output = try #require(renderer.render(document))
        // Inside: neighbouring columns no longer alternate black/white.
        let a = TestImages.pixel(output, x: 60, y: 30).r, b = TestImages.pixel(output, x: 61, y: 30).r
        #expect(abs(Int(a) - Int(b)) < 60)
        // Outside: untouched.
        let c = TestImages.pixel(output, x: 4, y: 30).r, d = TestImages.pixel(output, x: 5, y: 30).r
        #expect(abs(Int(c) - Int(d)) > 200)
    }
}
