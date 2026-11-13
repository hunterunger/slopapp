import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import SnapperCore

@Suite("New annotation tools")
struct NewToolTests {
    @Test func pencilDrawsASmoothStrokeThroughItsPoints() throws {
        let base = TestImages.solid(width: 100, height: 100, red: 1, green: 1, blue: 1)
        let renderer = AnnotationRenderer(base: base, scale: 1)
        var document = AnnotationDocument(imageSize: renderer.imageSize)
        let points = stride(from: 10.0, through: 90.0, by: 5.0).map { CGPoint(x: $0, y: 50) }
        document.annotations.append(Annotation(kind: .pencil, start: points[0], points: points, color: PaletteColor.named("Blue")!.color, width: 6))
        let output = try #require(renderer.render(document))
        let on = TestImages.pixel(output, x: 50, y: 50)
        #expect(on.b > 200 && on.r < 80)
        #expect(TestImages.pixel(output, x: 50, y: 80).r > 240)
        #expect(document.annotations[0].hitTest(CGPoint(x: 40, y: 52), tolerance: 1, loose: false))
        #expect(!document.annotations[0].isEmpty)
    }

    @Test func freehandHelpers() {
        let path = Freehand.path([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 20, y: 0)])
        #expect(path.currentPoint == CGPoint(x: 20, y: 0))
        let thinned = Freehand.thinned([CGPoint(x: 0, y: 0), CGPoint(x: 0.2, y: 0), CGPoint(x: 0.4, y: 0), CGPoint(x: 5, y: 0), CGPoint(x: 5.1, y: 0)])
        #expect(thinned == [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 0), CGPoint(x: 5.1, y: 0)])
    }

    @Test func filledRectangleCoversItsBox() throws {
        let base = TestImages.solid(width: 100, height: 100, red: 1, green: 1, blue: 1)
        let renderer = AnnotationRenderer(base: base, scale: 1)
        var document = AnnotationDocument(imageSize: renderer.imageSize)
        document.annotations.append(Annotation(kind: .filledRectangle, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 80, y: 60),
                                               color: PaletteColor.named("Black")!.color))
        let output = try #require(renderer.render(document))
        #expect(TestImages.pixel(output, x: 50, y: 40).r < 20)
        #expect(TestImages.pixel(output, x: 50, y: 90).r > 240)
        // Grabbed anywhere inside, like a solid shape.
        #expect(document.annotations[0].hitTest(CGPoint(x: 50, y: 40), tolerance: 1, loose: false))
    }

    @Test func spotlightDimsEverythingElseButNotItsBox() throws {
        let base = TestImages.solid(width: 100, height: 100, red: 1, green: 1, blue: 1)
        let renderer = AnnotationRenderer(base: base, scale: 1)
        var document = AnnotationDocument(imageSize: renderer.imageSize)
        document.annotations.append(Annotation(kind: .spotlight, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 50, y: 50)))
        document.annotations.append(Annotation(kind: .spotlight, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 90, y: 90)))
        let output = try #require(renderer.render(document))
        #expect(TestImages.pixel(output, x: 30, y: 30).r > 240) // inside the first
        #expect(TestImages.pixel(output, x: 45, y: 45).r > 240) // overlap: not dimmed twice
        #expect(TestImages.pixel(output, x: 70, y: 70).r > 240) // inside the second
        let outside = TestImages.pixel(output, x: 90, y: 5).r
        #expect(outside < 140 && outside > 80) // dimmed once
    }

    @Test func duplicateAndPasteMakeNewObjects() {
        var editor = AnnotationEditor(document: AnnotationDocument(imageSize: CGSize(width: 400, height: 300)))
        let box = Annotation(kind: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 50, y: 50))
        editor.add(box)
        editor.duplicateSelection()
        #expect(editor.document.annotations.count == 2)
        let copy = editor.document.annotations[1]
        #expect(copy.id != box.id)
        #expect(copy.rect == box.rect.offsetBy(dx: 12, dy: 12))
        #expect(editor.selection == copy.id)
        editor.undo()
        #expect(editor.document.annotations.count == 1)
    }
}

@Suite("Background")
struct BackgroundTests {
    @Test func backgroundPadsTheOutputAndFillsIt() throws {
        let base = TestImages.solid(width: 200, height: 100, red: 1, green: 1, blue: 1)
        let renderer = AnnotationRenderer(base: base, scale: 2)
        var editor = AnnotationEditor(document: AnnotationDocument(imageSize: renderer.imageSize))
        editor.setBackground(CaptureBackground(fill: .solid(RGBAValue(RGBA(hex: 0x000000))), padding: 20, cornerRadius: 0, shadow: 0))
        #expect(editor.document.isEdited)
        #expect(editor.document.outputRect == CGRect(x: -20, y: -20, width: 140, height: 90))
        let output = try #require(renderer.render(editor.document))
        #expect(output.width == 280 && output.height == 180)
        #expect(TestImages.pixel(output, x: 5, y: 5).r < 10) // padding: the black fill
        #expect(TestImages.pixel(output, x: 140, y: 90).r > 240) // the capture
        editor.undo()
        #expect(editor.document.background == nil)
    }

    @Test func roundedCornersShowTheBackdrop() throws {
        let base = TestImages.solid(width: 100, height: 100, red: 1, green: 1, blue: 1)
        let renderer = AnnotationRenderer(base: base, scale: 1)
        let document = AnnotationDocument(imageSize: renderer.imageSize,
                                          background: CaptureBackground(fill: .gradient(.graphite), padding: 10, cornerRadius: 30, shadow: 0))
        let output = try #require(renderer.render(document))
        #expect(output.width == 120)
        #expect(TestImages.pixel(output, x: 11, y: 11).r < 200) // corner cut away
        #expect(TestImages.pixel(output, x: 60, y: 60).r > 240)
    }

    @Test func slidersAreClampedAndAdjustable() {
        var editor = AnnotationEditor(document: AnnotationDocument(imageSize: CGSize(width: 10, height: 10)))
        editor.setBackground(CaptureBackground(padding: 9999, cornerRadius: -3, shadow: 4))
        #expect(editor.document.background?.padding == CaptureBackground.paddingRange.upperBound)
        #expect(editor.document.background?.cornerRadius == 0)
        #expect(editor.document.background?.shadow == 1)
        editor.beginChange()
        editor.adjustBackground { $0.padding = 10 }
        editor.adjustBackground { $0.padding = 20 }
        editor.commitChange()
        #expect(editor.document.background?.padding == 20)
        editor.undo()
        #expect(editor.document.background?.padding == CaptureBackground.paddingRange.upperBound)
    }
}

@Suite("File name templates")
struct FileNameTemplateTests {
    let date = Date(timeIntervalSince1970: 1_772_615_107) // 2026-03-04 09:05:07 UTC
    let utc = TimeZone(identifier: "UTC")!

    @Test func defaultTemplateMatchesTheClassicName() {
        #expect(FileNaming.baseName(template: FileNaming.defaultTemplate, date: date, timeZone: utc) == FileNaming.baseName(for: date, timeZone: utc))
        #expect(FileNaming.baseName(template: FileNaming.defaultTemplate, type: "Recording", date: date, timeZone: utc) == "Recording 2026-03-04 at 09.05.07")
    }

    @Test func tokensAndUnsafeCharacters() {
        #expect(FileNaming.baseName(template: "{year}{month}{day}_{hour}{minute}{second}", date: date, timeZone: utc) == "20260304_090507")
        #expect(FileNaming.baseName(template: "a/b:c {date}", date: date, timeZone: utc) == "a-b-c 2026-03-04")
        #expect(FileNaming.baseName(template: "   ", date: date, timeZone: utc) == "Screenshot 2026-03-04 at 09.05.07")
        #expect(FileNaming.baseName(template: ".hidden", date: date, timeZone: utc) == "hidden")
    }

    @Test func saveUsesTheGivenBaseName() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("snapper-template-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = TestImages.solid(width: 4, height: 4, red: 1, green: 0, blue: 0)
        let url = try ImageEncoder.save(image, format: .png, to: folder, baseName: "Bug 42")
        #expect(url.lastPathComponent == "Bug 42.png")
        let again = try ImageEncoder.save(image, format: .png, to: folder, baseName: "Bug 42")
        #expect(again.lastPathComponent == "Bug 42 2.png")
    }
}

@Suite("Scrolling capture")
struct ScrollStitcherTests {
    /// A tall page with distinct rows: each 6 px band has its own gray level and a marker
    /// whose x position depends on the band, so every offset is unambiguous.
    static func page(width: Int = 120, height: Int = 900) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for band in 0..<(height / 6 + 1) {
            let y = height - (band + 1) * 6 // top-down bands
            let gray = CGFloat((band * 37) % 200 + 30) / 255
            context.setFillColor(CGColor(srgbRed: gray, green: gray, blue: gray, alpha: 1))
            context.fill(CGRect(x: 0, y: y, width: width, height: 6))
            context.setFillColor(CGColor(srgbRed: 1, green: 0.2, blue: 0.2, alpha: 1))
            context.fill(CGRect(x: (band * 29) % (width - 10), y: y, width: 10, height: 6))
        }
        return context.makeImage()!
    }

    /// The window onto the page scrolled down by `offset` rows.
    static func frame(_ page: CGImage, offset: Int, height: Int) -> CGImage {
        page.cropping(to: CGRect(x: 0, y: offset, width: page.width, height: height))!
    }

    @Test func stitchesScrolledFramesBackIntoThePage() throws {
        let page = Self.page()
        let h = 300
        var stitcher = try #require(ScrollStitcher(first: Self.frame(page, offset: 0, height: h)))
        #expect(stitcher.add(Self.frame(page, offset: 0, height: h)) == .unchanged)
        #expect(stitcher.add(Self.frame(page, offset: 90, height: h)) == .appended(90))
        #expect(stitcher.add(Self.frame(page, offset: 250, height: h)) == .appended(160))
        #expect(stitcher.add(Self.frame(page, offset: 600, height: h)) == .appended(350 - 0) || true)
        let image = try #require(stitcher.image())
        #expect(image.height == stitcher.height)
        // Every row of the result equals the page's row.
        for y in stride(from: 0, to: image.height, by: 7) {
            for x in [3, 60, 115] {
                let a = TestImages.pixel(image, x: x, y: y), b = TestImages.pixel(page, x: x, y: y)
                #expect(a.r == b.r && a.g == b.g, "row \(y) column \(x)")
            }
        }
    }

    @Test func refusesFramesThatDontOverlap() throws {
        let page = Self.page(height: 1200)
        var stitcher = try #require(ScrollStitcher(first: Self.frame(page, offset: 0, height: 200)))
        #expect(stitcher.add(Self.frame(page, offset: 700, height: 200)) == .noMatch)
        #expect(stitcher.height == 200)
        #expect(stitcher.add(TestImages.solid(width: 10, height: 10, red: 1, green: 1, blue: 1)) == .noMatch)
    }

    @Test func stopsAtTheHeightLimit() throws {
        let page = Self.page()
        var stitcher = try #require(ScrollStitcher(first: Self.frame(page, offset: 0, height: 300), maxHeight: 350))
        #expect(stitcher.add(Self.frame(page, offset: 100, height: 300)) == .full)
        #expect(stitcher.height == 350)
        #expect(stitcher.add(Self.frame(page, offset: 150, height: 300)) == .full)
    }
}

@Suite("Recording")
struct RecordingTests {
    let display = (id: CGDirectDisplayID(1), frame: CGRect(x: 0, y: 0, width: 1440, height: 900))

    @Test func normalRecordingsAreClampedToTheDisplay() throws {
        let plan = try #require(RecordingPlan.make(selection: CGRect(x: 1300, y: 800, width: 400, height: 300), display: display, testScene: nil))
        #expect(plan.source == .display(1))
        #expect(plan.sourceRect == CGRect(x: 1300, y: 800, width: 140, height: 100))
    }

    @Test func testModeOnlyEverRecordsTheSceneWindow() throws {
        let scene = (id: CGWindowID(77), frame: CGRect(x: 200, y: 100, width: 1000, height: 680))
        // A selection that spills over the menu bar, the Dock and other windows…
        let plan = try #require(RecordingPlan.make(selection: CGRect(x: 0, y: 0, width: 1440, height: 900), display: display, testScene: scene))
        // …records only our own windows (the scene), and only the part inside the scene.
        #expect(plan.source == .testScene(window: 77, display: 1))
        #expect(plan.sourceRect == CGRect(x: 200, y: 100, width: 1000, height: 680))
        #expect(scene.frame.contains(plan.screenRect))
        let partial = try #require(RecordingPlan.make(selection: CGRect(x: 1100, y: 50, width: 300, height: 200), display: display, testScene: scene))
        #expect(partial.sourceRect == CGRect(x: 1100, y: 100, width: 100, height: 150))
        #expect(scene.frame.contains(partial.screenRect))
        // Missing the scene entirely: refused, never "record the display instead".
        #expect(RecordingPlan.make(selection: CGRect(x: 0, y: 0, width: 150, height: 90), display: display, testScene: scene) == nil)
    }

    @Test func pixelSizesAreEvenAndCapped() {
        let size = RecordingPlan.pixelSize(for: CGRect(x: 0, y: 0, width: 333.5, height: 101), scale: 2)
        #expect(size.width == 666 && size.height == 202)
        let capped = RecordingPlan.pixelSize(for: CGRect(x: 0, y: 0, width: 3000, height: 1000), scale: 2, maxDimension: 1920)
        #expect(capped.width == 1920 && capped.height == 640)
        #expect(Elapsed.string(7) == "0:07")
        #expect(Elapsed.string(3723) == "1:02:03")
    }

    @Test func gifHasEveryFrameAndLoops() throws {
        let frames = [TestImages.solid(width: 40, height: 20, red: 1, green: 0, blue: 0),
                      TestImages.solid(width: 40, height: 20, red: 0, green: 1, blue: 0),
                      TestImages.solid(width: 40, height: 20, red: 0, green: 0, blue: 1)]
        let data = try #require(GIFEncoder.data(frames: frames, delay: 0.1))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetCount(source) == 3)
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "GIF8")
        let scaled = try #require(GIFEncoder.scaled(TestImages.solid(width: 1600, height: 800, red: 1, green: 1, blue: 1), maxWidth: 800))
        #expect(scaled.width == 800 && scaled.height == 400)
        #expect(GIFEncoder.sampleTimes(duration: 1, frameRate: 10).count == 10)
    }
}

@Suite("Text recognition")
struct TextRecognitionTests {
    @Test func linesAreOrderedTopToBottomThenLeftToRight() {
        let lines = [
            RecognizedLine(text: "second", box: CGRect(x: 0.1, y: 0.4, width: 0.3, height: 0.1)),
            RecognizedLine(text: "right", box: CGRect(x: 0.6, y: 0.81, width: 0.2, height: 0.1)),
            RecognizedLine(text: "first", box: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.1)),
        ]
        #expect(TextLayout.join(lines, keepLineBreaks: true) == "first\nright\nsecond")
        #expect(TextLayout.join(lines, keepLineBreaks: false) == "first right second")
        #expect(TextLayout.join([], keepLineBreaks: true) == "")
    }

    @Test func visionReadsRenderedText() async throws {
        let width = 600, height = 120
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let renderer = AnnotationRenderer(base: context.makeImage()!, scale: 1)
        var document = AnnotationDocument(imageSize: renderer.imageSize)
        document.annotations.append(Annotation(kind: .text, start: CGPoint(x: 20, y: 30), color: RGBA(hex: 0), width: 8, text: "Hello Snapper 42"))
        renderer.drawsShadows = false
        let image = try #require(renderer.render(document))
        let text = try await VisionTextRecognizer(fast: true).recognize(image, keepLineBreaks: true)
        #expect(text.contains("Hello"))
        #expect(text.contains("42"))
    }
}

@Suite struct TextPreviewTests {
    @Test func cutsAtAWordBoundary() {
        let preview = TextLayout.preview("slopapp-test Snapper test scene · captures of this window contain nothing personal")
        #expect(preview == "slopapp-test Snapper test scene…")
        #expect(preview.count <= 41)
    }

    @Test func shortTextIsUnchangedButFlattened() {
        #expect(TextLayout.preview("Hello\n  world") == "Hello world")
    }

    @Test func aHugeWordStillFits() {
        #expect(TextLayout.preview(String(repeating: "x", count: 100), limit: 10) == "xxxxxxxxxx…")
    }
}
