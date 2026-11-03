import Foundation
import Testing
@testable import RulerCore

/// A synthetic RGBA image to draw test shapes into.
struct Canvas {
    let width: Int
    let height: Int
    var bytes: [UInt8]

    init(width: Int, height: Int, gray: UInt8 = 255) {
        self.width = width
        self.height = height
        bytes = [UInt8](repeating: 0, count: width * height * 4)
        fill(PixelRect(x: 0, y: 0, width: width, height: height), gray: gray)
    }

    mutating func set(_ x: Int, _ y: Int, r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        let i = (y * width + x) * 4
        bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b; bytes[i + 3] = a
    }

    mutating func fill(_ rect: PixelRect, r: UInt8, g: UInt8, b: UInt8) {
        for y in rect.minY..<rect.maxY { for x in rect.minX..<rect.maxX { set(x, y, r: r, g: g, b: b) } }
    }

    mutating func fill(_ rect: PixelRect, gray: UInt8) { fill(rect, r: gray, g: gray, b: gray) }

    var image: EdgeImage { EdgeImage(width: width, height: height, bytes: bytes)! }
}

@Suite("Hover spans")
struct SpanTests {
    @Test func insideASolidRectReadsItsSize() {
        var c = Canvas(width: 200, height: 100)
        c.fill(PixelRect(x: 20, y: 10, width: 80, height: 40), r: 0, g: 100, b: 255)
        let s = c.image.spans(at: PixelPoint(x: 50, y: 30), tolerance: .normal)!
        #expect(s == PixelRect(x: 20, y: 10, width: 80, height: 40))
    }

    @Test func betweenTwoRectsReadsTheGap() {
        var c = Canvas(width: 200, height: 100)
        c.fill(PixelRect(x: 10, y: 10, width: 30, height: 30), gray: 0)
        c.fill(PixelRect(x: 64, y: 10, width: 30, height: 30), gray: 0)
        let s = c.image.spans(at: PixelPoint(x: 50, y: 20), tolerance: .normal)!
        #expect(s.minX == 40 && s.maxX == 64)
        #expect(s.width == 24)
    }

    @Test func noEdgeRunsToTheImageBorder() {
        let c = Canvas(width: 120, height: 80)
        let s = c.image.spans(at: PixelPoint(x: 10, y: 10), tolerance: .normal)!
        #expect(s == c.image.bounds)
    }

    @Test func pointerOnAOnePixelLineReadsOnePixel() {
        var c = Canvas(width: 100, height: 100)
        c.fill(PixelRect(x: 0, y: 50, width: 100, height: 1), gray: 0)
        let s = c.image.spans(at: PixelPoint(x: 30, y: 50), tolerance: .normal)!
        #expect(s.height == 1)
        #expect(s.width == 100)
    }

    @Test func lowContrastEdgeNeedsAStricterTolerance() {
        var c = Canvas(width: 100, height: 50)
        c.fill(PixelRect(x: 60, y: 0, width: 40, height: 50), gray: 245) // 10 levels darker
        let normal = c.image.spans(at: PixelPoint(x: 10, y: 10), tolerance: .normal)!
        let fine = c.image.spans(at: PixelPoint(x: 10, y: 10), tolerance: .fine)!
        #expect(normal.maxX == 100)
        #expect(fine.maxX == 60)
    }

    @Test func strictToleranceStopsAtSmallChangesButNotCaptureNoise() {
        var c = Canvas(width: 50, height: 10)
        c.set(20, 5, r: 253, g: 255, b: 254) // capture noise
        c.set(30, 5, r: 250, g: 255, b: 255)
        #expect(c.image.spans(at: PixelPoint(x: 10, y: 5), tolerance: .strict)!.maxX == 30)
        #expect(c.image.spans(at: PixelPoint(x: 10, y: 5), tolerance: .fine)!.maxX == 50)
    }

    @Test func gradientIsNotAnEdge() {
        var c = Canvas(width: 400, height: 40)
        // A 300 px gradient from white to black between x 50 and 350, rows 10..<30.
        for x in 50..<350 {
            let v = UInt8(255 - (x - 50) * 255 / 299)
            c.fill(PixelRect(x: x, y: 10, width: 1, height: 20), gray: v)
        }
        let s = c.image.spans(at: PixelPoint(x: 200, y: 20), tolerance: .normal)!
        #expect(s.minY == 10 && s.maxY == 30)
        // The white end blends into the white background, so the left side runs out; the
        // dark end meets white with a hard edge.
        #expect(s.maxX == 350)
    }

    @Test func antiAliasedFringeCountsAsTheShapeAtNormal() {
        var c = Canvas(width: 100, height: 20)
        c.fill(PixelRect(x: 40, y: 0, width: 20, height: 20), gray: 0)
        c.fill(PixelRect(x: 39, y: 0, width: 1, height: 20), gray: 128) // 50% coverage
        let s = c.image.spans(at: PixelPoint(x: 10, y: 10), tolerance: .normal)!
        #expect(s.maxX == 39)
        // A very faint fringe (5%) is ignored.
        var faint = Canvas(width: 100, height: 20)
        faint.fill(PixelRect(x: 40, y: 0, width: 20, height: 20), gray: 0)
        faint.fill(PixelRect(x: 39, y: 0, width: 1, height: 20), gray: 243)
        #expect(faint.image.spans(at: PixelPoint(x: 10, y: 10), tolerance: .normal)!.maxX == 40)
    }

    @Test func limitsStopTheScan() {
        let c = Canvas(width: 100, height: 100)
        let s = c.image.spans(at: PixelPoint(x: 50, y: 50), tolerance: .normal,
                              limits: PixelRect(minX: 20, minY: 0, maxX: 70, maxY: 100))!
        #expect(s.minX == 20 && s.maxX == 70)
    }

    @Test func pointOutsideLimitsGivesNothing() {
        let c = Canvas(width: 10, height: 10)
        #expect(c.image.spans(at: PixelPoint(x: 20, y: 2), tolerance: .normal) == nil)
    }

    @Test func maskedTransparentPixelsReadAsBlack() {
        var c = Canvas(width: 60, height: 10)
        for x in 40..<60 { for y in 0..<10 { c.set(x, y, r: 0, g: 0, b: 0, a: 0) } }
        #expect(c.image.spans(at: PixelPoint(x: 5, y: 5), tolerance: .normal)!.maxX == 40)
    }

    @Test func nearestEdgeSnapsWithinDistance() {
        var c = Canvas(width: 100, height: 100)
        c.fill(PixelRect(x: 0, y: 60, width: 100, height: 40), gray: 0)
        let image = c.image
        #expect(image.nearestEdge(to: PixelPoint(x: 10, y: 55), axis: .horizontal, tolerance: .normal, maxDistance: 8) == 60)
        #expect(image.nearestEdge(to: PixelPoint(x: 10, y: 30), axis: .horizontal, tolerance: .normal, maxDistance: 8) == nil)
    }

    @Test func rejectsShortBuffers() {
        #expect(EdgeImage(width: 10, height: 10, bytes: [0, 0, 0]) == nil)
    }
}

@Suite("Element bounds")
struct ContentBoundsTests {
    @Test func shrinksToTheElement() {
        var c = Canvas(width: 200, height: 120)
        c.fill(PixelRect(x: 50, y: 30, width: 61, height: 21), r: 255, g: 59, b: 48)
        let r = c.image.contentBounds(in: PixelRect(x: 20, y: 10, width: 140, height: 90), tolerance: .normal)
        #expect(r == PixelRect(x: 50, y: 30, width: 61, height: 21))
    }

    @Test func groupsSeveralElements() {
        var c = Canvas(width: 200, height: 120)
        c.fill(PixelRect(x: 30, y: 30, width: 10, height: 10), gray: 0)
        c.fill(PixelRect(x: 100, y: 60, width: 20, height: 5), gray: 0)
        let r = c.image.contentBounds(in: PixelRect(x: 0, y: 0, width: 200, height: 120), tolerance: .normal)
        #expect(r == PixelRect(minX: 30, minY: 30, maxX: 120, maxY: 65))
    }

    @Test func uniformAreaGivesNothing() {
        let c = Canvas(width: 100, height: 100)
        #expect(c.image.contentBounds(in: PixelRect(x: 10, y: 10, width: 50, height: 50), tolerance: .normal) == nil)
    }

    @Test func tinyElementsDontCollapse() {
        var c = Canvas(width: 50, height: 50)
        c.fill(PixelRect(x: 20, y: 20, width: 1, height: 1), gray: 0)
        #expect(c.image.contentBounds(in: PixelRect(x: 5, y: 5, width: 40, height: 40), tolerance: .normal)
                == PixelRect(x: 20, y: 20, width: 1, height: 1))
    }

    @Test func softShadowIsBackground() {
        var c = Canvas(width: 200, height: 200)
        // A soft shadow: darkest (−48) under the card, fading out over 16 px in every direction,
        // offset 6 px down and right.
        let shadow = PixelRect(x: 56, y: 56, width: 110, height: 90)
        for y in 0..<200 {
            for x in 0..<200 {
                let dx = max(shadow.minX - x, 0, x - (shadow.maxX - 1)), dy = max(shadow.minY - y, 0, y - (shadow.maxY - 1))
                let distance = (Double(dx * dx + dy * dy)).squareRoot()
                let v = 255 - 48 * max(0, 1 - distance / 16)
                c.set(x, y, r: UInt8(v), g: UInt8(v), b: UInt8(v))
            }
        }
        c.fill(PixelRect(x: 50, y: 50, width: 110, height: 90), r: 250, g: 250, b: 250)
        c.fill(PixelRect(x: 50, y: 50, width: 110, height: 1), gray: 160) // card border
        c.fill(PixelRect(x: 50, y: 50, width: 1, height: 90), gray: 160)
        c.fill(PixelRect(x: 159, y: 50, width: 1, height: 90), gray: 160)
        c.fill(PixelRect(x: 50, y: 139, width: 110, height: 1), gray: 160)
        let r = c.image.contentBounds(in: PixelRect(x: 20, y: 20, width: 175, height: 175), tolerance: .normal)
        #expect(r == PixelRect(x: 50, y: 50, width: 110, height: 90))
    }

    @Test func whiteCardOnNearWhiteWithSoftShadow() {
        // The card is barely different from the background (8 levels); only its shadow, which
        // fades out toward the corners, sets it apart.
        var c = Canvas(width: 200, height: 160, gray: 247)
        for d in 0..<4 {
            let v = UInt8(229 + d * 6) // 229 next to the card, fading to the background
            c.fill(PixelRect(minX: 60, minY: 46 - d, maxX: 140, maxY: 47 - d), gray: v)
            c.fill(PixelRect(minX: 60, minY: 110 + d, maxX: 140, maxY: 111 + d), gray: v)
            c.fill(PixelRect(minX: 46 - d, minY: 60, maxX: 47 - d, maxY: 100), gray: v)
            c.fill(PixelRect(minX: 150 + d, minY: 60, maxX: 151 + d, maxY: 100), gray: v)
        }
        c.fill(PixelRect(minX: 47, minY: 47, maxX: 150, maxY: 110), gray: 255)
        let r = c.image.contentBounds(in: PixelRect(x: 20, y: 20, width: 160, height: 120), tolerance: .normal)
        #expect(r == PixelRect(minX: 47, minY: 47, maxX: 150, maxY: 110))
    }

    @Test func gradientBackgroundIsBackground() {
        var c = Canvas(width: 300, height: 100)
        for x in 0..<300 { c.fill(PixelRect(x: x, y: 0, width: 1, height: 100), gray: UInt8(40 + x * 200 / 299)) }
        c.fill(PixelRect(x: 120, y: 30, width: 40, height: 30), r: 255, g: 0, b: 0)
        let r = c.image.contentBounds(in: PixelRect(x: 60, y: 5, width: 180, height: 90), tolerance: .normal)
        #expect(r == PixelRect(x: 120, y: 30, width: 40, height: 30))
    }

    @Test func elementCutByTheBoxKeepsTheCut() {
        var c = Canvas(width: 100, height: 100)
        c.fill(PixelRect(x: 0, y: 40, width: 100, height: 20), gray: 0) // a bar crossing the box
        let r = c.image.contentBounds(in: PixelRect(x: 20, y: 20, width: 60, height: 60), tolerance: .normal)
        #expect(r == PixelRect(minX: 20, minY: 40, maxX: 80, maxY: 60))
    }

    @Test func boxCuttingAnElementKeepsTheElementSide() {
        var c = Canvas(width: 200, height: 200)
        c.fill(PixelRect(x: 80, y: 80, width: 60, height: 60), r: 240, g: 160, b: 20)
        // Box covers the element's left and top edges but stops inside it.
        let r = c.image.contentBounds(in: PixelRect(minX: 60, minY: 60, maxX: 120, maxY: 120), tolerance: .normal)
        #expect(r == PixelRect(minX: 80, minY: 80, maxX: 120, maxY: 120))
        // And the other way round: right and bottom edges inside the box.
        let s = c.image.contentBounds(in: PixelRect(minX: 100, minY: 100, maxX: 170, maxY: 170), tolerance: .normal)
        #expect(s == PixelRect(minX: 100, minY: 100, maxX: 140, maxY: 140))
    }

    @Test func clampsToTheImage() {
        var c = Canvas(width: 40, height: 40)
        c.fill(PixelRect(x: 10, y: 10, width: 5, height: 5), gray: 0)
        #expect(c.image.contentBounds(in: PixelRect(x: -20, y: -20, width: 100, height: 100), tolerance: .normal)
                == PixelRect(x: 10, y: 10, width: 5, height: 5))
    }

    @Test func outlineOnlyShapeKeepsItsOuterBounds() {
        var c = Canvas(width: 120, height: 120)
        let box = PixelRect(x: 20, y: 20, width: 80, height: 60)
        c.fill(PixelRect(x: 20, y: 20, width: 80, height: 2), gray: 0)
        c.fill(PixelRect(x: 20, y: 78, width: 80, height: 2), gray: 0)
        c.fill(PixelRect(x: 20, y: 20, width: 2, height: 60), gray: 0)
        c.fill(PixelRect(x: 98, y: 20, width: 2, height: 60), gray: 0)
        #expect(c.image.contentBounds(in: PixelRect(x: 5, y: 5, width: 110, height: 110), tolerance: .normal) == box)
    }

    @Test func fullDisplayIsFastEnough() {
        // 5K display; a debug build is far slower than release, so the bound is generous.
        var c = Canvas(width: 2560, height: 1440)
        c.fill(PixelRect(x: 1000, y: 600, width: 300, height: 200), gray: 0)
        let image = c.image
        let start = Date()
        let r = image.contentBounds(in: image.bounds, tolerance: .normal)
        #expect(r == PixelRect(x: 1000, y: 600, width: 300, height: 200))
        #expect(Date().timeIntervalSince(start) < 5)
        let hoverStart = Date()
        for i in 0..<200 { _ = image.spans(at: PixelPoint(x: 100 + i, y: 100), tolerance: .normal) }
        #expect(Date().timeIntervalSince(hoverStart) < 2)
    }
}
