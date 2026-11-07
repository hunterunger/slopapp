import CoreGraphics
import Foundation
import Testing
@testable import RulerCore

@Suite("Held distances")
struct PinTests {
    @Test func pHoldsOneLinePerAxis() {
        var board = Board()
        let ids = board.addPins(point: PixelPoint(x: 50, y: 20), spans: PixelRect(minX: 10, minY: 0, maxX: 110, maxY: 40))
        #expect(ids.count == 2)
        #expect(board.pins[0] == PinnedDistance(id: ids[0], axis: .horizontal, at: 20, start: 10, end: 110))
        #expect(board.pins[1] == PinnedDistance(id: ids[1], axis: .vertical, at: 50, start: 0, end: 40))
        #expect(board.reading(of: .pin(ids[1])) == .length(40, axis: .vertical))
    }

    @Test func zeroLengthSpansAreSkipped() {
        var board = Board()
        let ids = board.addPins(point: PixelPoint(x: 5, y: 5), spans: PixelRect(minX: 5, minY: 0, maxX: 5, maxY: 9))
        #expect(ids.count == 1 && board.pins[0].axis == .vertical)
    }

    @Test func measuredBoundsCoverAreasAndPinsNotGuides() {
        var board = Board()
        #expect(board.measuredBounds == nil)
        board.addGuide(.vertical, at: 900)
        #expect(board.measuredBounds == nil)
        board.addArea(PixelRect(x: 100, y: 100, width: 50, height: 50))
        board.addPins(point: PixelPoint(x: 300, y: 20), spans: PixelRect(minX: 250, minY: 0, maxX: 400, maxY: 40), axes: [.horizontal])
        #expect(board.measuredBounds == PixelRect(minX: 100, minY: 20, maxX: 400, maxY: 150))
    }
}

@Suite("Resizing areas and moving guides")
struct ResizeTests {
    let r = PixelRect(x: 100, y: 100, width: 200, height: 100)

    @Test func handlesAreFoundCornersFirst() {
        #expect(AreaHandle.hit(PixelPoint(x: 101, y: 99), rect: r, slop: 4) == .topLeft)
        #expect(AreaHandle.hit(PixelPoint(x: 300, y: 200), rect: r, slop: 4) == .bottomRight)
        #expect(AreaHandle.hit(PixelPoint(x: 200, y: 98), rect: r, slop: 4) == .top)
        #expect(AreaHandle.hit(PixelPoint(x: 302, y: 150), rect: r, slop: 4) == .right)
        #expect(AreaHandle.hit(PixelPoint(x: 200, y: 150), rect: r, slop: 4) == nil) // inside
        #expect(AreaHandle.hit(PixelPoint(x: 400, y: 150), rect: r, slop: 4) == nil) // away
    }

    @Test func dragsMoveOnlyTheirSides() {
        #expect(AreaHandle.right.resize(r, to: PixelPoint(x: 350, y: 0)) == PixelRect(minX: 100, minY: 100, maxX: 350, maxY: 200))
        #expect(AreaHandle.topLeft.resize(r, to: PixelPoint(x: 90, y: 80)) == PixelRect(minX: 90, minY: 80, maxX: 300, maxY: 200))
        // Can't cross the opposite side.
        #expect(AreaHandle.left.resize(r, to: PixelPoint(x: 500, y: 0), minimum: 2) == PixelRect(minX: 298, minY: 100, maxX: 300, maxY: 200))
    }

    @Test func shiftKeepsTheAspectRatio() {
        let corner = AreaHandle.bottomRight.resize(r, to: PixelPoint(x: 500, y: 210), keepAspect: true)
        #expect(corner == PixelRect(minX: 100, minY: 100, maxX: 500, maxY: 300))
        let edge = AreaHandle.right.resize(r, to: PixelPoint(x: 500, y: 0), keepAspect: true)
        #expect(edge.width == 400 && edge.height == 200)
        #expect(edge.minY == 50) // grows around the old center (150)
    }

    @Test func boardResizeAndGuideMove() {
        var board = Board()
        let id = board.addArea(r, settled: false)
        let resized = board.resizeArea(id, to: PixelRect(x: 0, y: 0, width: 10, height: 10))
        #expect(resized)
        #expect(board.area(id)?.isSettled == true)
        let empty = board.resizeArea(id, to: PixelRect(x: 0, y: 0, width: 0, height: 10))
        #expect(!empty)
        #expect(board.handle(at: PixelPoint(x: 10, y: 5), slop: 2)?.handle == .right)
        let g = board.addGuide(.vertical, at: 40)
        let moved = board.moveGuide(g, to: 60)
        #expect(moved)
        #expect(board.guide(g)?.position == 60)
    }

    @Test func guidesSnapToAreaSidesAndMidpoints() {
        var board = Board()
        board.addArea(PixelRect(minX: 100, minY: 10, maxX: 200, maxY: 50))
        board.addGuide(.vertical, at: 400)
        let moving = board.addGuide(.vertical, at: 600)
        #expect(board.nearestGuideSnap(.vertical, to: 203, maxDistance: 8) == 200)
        #expect(board.nearestGuideSnap(.vertical, to: 505, maxDistance: 8) == 500) // midpoint 400–600
        #expect(board.nearestGuideSnap(.vertical, to: 505, maxDistance: 8, excluding: moving) == nil)
        #expect(board.nearestGuideSnap(.horizontal, to: 48, maxDistance: 8) == 50)
        #expect(board.nearestGuideSnap(.vertical, to: 300, maxDistance: 8) == nil)
    }
}

@Suite("Scale, aspect ratio and copy formats")
struct ReadoutParityTests {
    let en = Locale(identifier: "en_US")

    @Test func designScaleDividesValues() {
        let r = Readout(scale: 2, unit: .points, locale: en, designScale: 2)
        #expect(r.length(400) == "100 pt")
        #expect(r.length(402) == "100.5 pt")
        let three = Readout(scale: 1, unit: .points, locale: en, designScale: 3)
        #expect(three.number(100) == "33.33")
        // One Retina pixel is 0.25 pt of an @2x design: keep it, don't round to 50.3.
        #expect(r.length(201) == "50.25 pt")
        #expect(three.number(10) == "3.33")
        let half = Readout(scale: 2, unit: .pixels, locale: en, designScale: 0.5)
        #expect(half.length(100) == "200 px")
        #expect(Readout(scale: 2, unit: .points, locale: en, designScale: 0).designScale == 1)
    }

    @Test func designScaleTitles() {
        #expect(DesignScale.title(1) == "Actual Size")
        #expect(DesignScale.title(2) == "@2x (÷2)")
        #expect(DesignScale.title(0.5) == "50% Zoom (×2)")
        #expect(DesignScale.title(1.5) == "÷1.5")
        #expect(DesignScale.badge(1) == nil)
        #expect(DesignScale.badge(3) == "@3x")
        #expect(DesignScale.badge(0.5) == "×2")
    }

    @Test func labelsCanHideTheUnit() {
        let r = Readout(scale: 2, unit: .points, locale: en, showsUnit: false)
        #expect(r.sizeLabel(width: 400, height: 240) == "200 × 120")
        #expect(r.lengthLabel(201) == "100.5")
        #expect(r.size(width: 400, height: 240) == "200 × 120 pt") // toasts keep it
        let shown = Readout(scale: 2, unit: .points, locale: en)
        #expect(shown.sizeLabel(width: 640, height: 360, ratio: .automatic) == "320 × 180 pt  16:9")
    }

    @Test func aspectRatios() {
        #expect(AspectRatio.text(width: 1920, height: 1080, style: .automatic) == "16:9")
        #expect(AspectRatio.text(width: 1080, height: 1920, style: .automatic) == "9:16")
        #expect(AspectRatio.text(width: 1921, height: 1080, style: .automatic) == "16:9") // within 1%
        #expect(AspectRatio.text(width: 700, height: 500, style: .automatic) == "1.4:1")
        #expect(AspectRatio.text(width: 700, height: 500, style: .fraction) == "7:5")
        #expect(AspectRatio.text(width: 1921, height: 1080, style: .fraction) == "1.78:1")
        #expect(AspectRatio.text(width: 500, height: 700, style: .decimal) == "1:1.4")
        #expect(AspectRatio.text(width: 700, height: 500, style: .commonOnly) == nil)
        #expect(AspectRatio.text(width: 300, height: 300, style: .commonOnly) == "1:1")
        #expect(AspectRatio.text(width: 0, height: 10, style: .automatic) == nil)
    }

    @Test func singleLengthsCopyTheirOwnProperty() {
        let r = Readout(scale: 2, unit: .points, locale: en)
        let w = Reading.length(201, axis: .horizontal), h = Reading.length(88, axis: .vertical)
        #expect(CopyFormat.plain.text(w, readout: r) == "100.5")
        #expect(CopyFormat.css.text(w, readout: r) == "width: 100.5px;")
        #expect(CopyFormat.css.text(h, readout: r) == "height: 44px;")
        #expect(CopyFormat.sass.text(h, readout: r) == "$height: 44px;")
        #expect(CopyFormat.tailwind.text(w, readout: r) == "w-[100.5px]")
        #expect(CopyFormat.swiftUI.text(h, readout: r) == ".frame(height: 44)")
        let size = Reading.size(width: 400, height: 88)
        #expect(CopyFormat.sass.text(size, readout: r) == "$width: 200px;\n$height: 44px;")
        #expect(CopyFormat.tailwind.text(size, readout: r) == "w-[200px] h-[44px]")
        #expect(r.spoken(h) == "height 44 points")
    }

    @Test func toleranceCycles() {
        #expect(Tolerance.normal.cycled == .loose)
        #expect(Tolerance.loose.cycled == .strict)
    }
}

@Suite("Label layout")
struct LabelLayoutTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let pill = CGSize(width: 90, height: 24)

    @Test func cursorPillSitsDownRightAndFlipsAtEdges() {
        let f = LabelLayout.cursorPill(size: pill, pointer: CGPoint(x: 500, y: 400), bounds: bounds)
        #expect(f.minX > 500 && f.maxY < 400)
        let corner = LabelLayout.cursorPill(size: pill, pointer: CGPoint(x: 990, y: 5), bounds: bounds)
        #expect(corner.maxX < 990 && corner.minY > 5)
        #expect(bounds.contains(corner))
    }

    @Test func areaLabelCentersInsideOrGoesBelow() {
        let big = CGRect(x: 100, y: 100, width: 300, height: 200)
        let inside = LabelLayout.areaLabel(size: pill, box: big, bounds: bounds)
        #expect(inside.midX == big.midX && inside.midY == big.midY)
        let small = CGRect(x: 100, y: 100, width: 40, height: 20)
        let below = LabelLayout.areaLabel(size: pill, box: small, bounds: bounds)
        #expect(below.maxY <= small.minY)
        let atBottom = CGRect(x: 100, y: 2, width: 40, height: 20)
        #expect(LabelLayout.areaLabel(size: pill, box: atBottom, bounds: bounds).minY >= atBottom.maxY)
    }

    @Test func magnifierNeverCoversTheReadout() {
        let pointer = CGPoint(x: 500, y: 400)
        let readout = LabelLayout.cursorPill(size: pill, pointer: pointer, bounds: bounds)
        let loupe = LabelLayout.magnifier(size: CGSize(width: 126, height: 156), pointer: pointer, bounds: bounds, avoiding: [readout])
        #expect(!loupe.intersects(readout))
        #expect(bounds.contains(loupe))
        // Near the top-left corner it still finds a clear, on-screen spot.
        let p2 = CGPoint(x: 20, y: 780)
        let r2 = LabelLayout.cursorPill(size: pill, pointer: p2, bounds: bounds)
        let l2 = LabelLayout.magnifier(size: CGSize(width: 126, height: 156), pointer: p2, bounds: bounds, avoiding: [r2])
        #expect(!l2.intersects(r2) && bounds.contains(l2))
    }

    @Test func separatedLabelsDontOverlap() {
        let a = CGRect(x: 100, y: 100, width: 80, height: 24)
        let frames = LabelLayout.separate([a, a, a.offsetBy(dx: 10, dy: 5)], bounds: bounds)
        #expect(frames[0] == a)
        for i in 0..<frames.count {
            for j in 0..<frames.count where i != j { #expect(!frames[i].intersects(frames[j])) }
        }
    }
}

@Suite("Screenshots and sessions")
struct ScreenshotTests {
    let image = PixelRect(x: 0, y: 0, width: 3000, height: 2000)

    @Test func cropIsTheSubjectPlusPadding() {
        let subject = PixelRect(x: 100, y: 100, width: 200, height: 100)
        #expect(ScreenshotPlan.crop(subject: subject, padding: 48, image: image, allowed: nil) == PixelRect(minX: 52, minY: 52, maxX: 348, maxY: 248))
        #expect(ScreenshotPlan.crop(subject: subject, padding: 0, image: image, allowed: nil) == subject)
        #expect(ScreenshotPlan.crop(subject: PixelRect(x: 0, y: 0, width: 10, height: 10), padding: 48, image: image, allowed: nil)
            == PixelRect(x: 0, y: 0, width: 58, height: 58))
        #expect(ScreenshotPlan.crop(subject: nil, padding: 48, image: image, allowed: nil) == image)
    }

    /// Privacy: in test mode a measurement screenshot can only ever contain the test scene.
    @Test func testModeCropsNeverLeaveTheScene() {
        let scene = PixelRect(x: 1000, y: 500, width: 1800, height: 1120)
        let subjects: [PixelRect?] = [
            nil,
            PixelRect(x: 1100, y: 600, width: 100, height: 100),
            PixelRect(x: 900, y: 400, width: 400, height: 400), // straddles the scene's corner
            PixelRect(x: 0, y: 0, width: 3000, height: 2000),
            PixelRect(x: 2790, y: 1610, width: 10, height: 10),
        ]
        for subject in subjects {
            for padding in [0, 48, 500] {
                let crop = ScreenshotPlan.crop(subject: subject, padding: padding, image: image, allowed: scene)
                #expect(crop != nil)
                if let crop { #expect(scene.contains(crop), "\(String(describing: subject)) +\(padding) → \(crop)") }
            }
        }
        // Entirely outside the scene: nothing to capture rather than something else.
        #expect(ScreenshotPlan.crop(subject: PixelRect(x: 0, y: 0, width: 100, height: 100), padding: 10, image: image, allowed: scene) == nil)
        // A scene that's off this display: nothing at all.
        #expect(ScreenshotPlan.crop(subject: nil, padding: 0, image: image, allowed: PixelRect(x: 4000, y: 0, width: 10, height: 10)) == nil)
    }

    @Test func fileNamesLookLikeScreenshots() {
        let date = DateComponents(year: 2026, month: 11, day: 3, hour: 7, minute: 5, second: 9)
        #expect(ScreenshotPlan.fileName(date: date, ext: "png") == "Ruler 2026-11-03 at 07.05.09.png")
    }

    @Test func sessionsRoundTripAndMatchDisplays() throws {
        var board = Board()
        board.addArea(PixelRect(x: 1, y: 2, width: 3, height: 4))
        board.addGuide(.horizontal, at: 9)
        board.addPins(point: PixelPoint(x: 5, y: 5), spans: PixelRect(x: 0, y: 0, width: 10, height: 10))
        let session = SavedSession(displays: [
            .init(key: "A", width: 3000, height: 2000, board: board),
            .init(key: "B", width: 100, height: 100, board: Board()), // empty: dropped
        ])
        #expect(session.displays.count == 1)
        let decoded = try #require(SavedSession.decode(session.encoded()))
        #expect(decoded == session)
        #expect(decoded.board(for: "A", width: 3000, height: 2000) == board)
        #expect(decoded.board(for: "A", width: 1500, height: 1000) == nil) // resolution changed
        #expect(decoded.board(for: "C", width: 3000, height: 2000) == nil)
        #expect(SavedSession.decode(SavedSession(displays: []).encoded()) == nil)
        #expect(SavedSession.decode(Data("junk".utf8)) == nil)
        // IDs keep counting after a restore, so new items don't collide.
        var restored = decoded.board(for: "A", width: 3000, height: 2000)!
        let next = restored.addArea(PixelRect(x: 0, y: 0, width: 1, height: 1))
        #expect(!board.areas.map(\.id).contains(next) && !board.pins.map(\.id).contains(next))
    }
}

@Suite("Masked pixels")
struct MaskedPixelTests {
    @Test func alphaReadsMaskedPixels() {
        var bytes = [UInt8](repeating: 0, count: 2 * 1 * 4)
        bytes[4...7] = [10, 20, 30, 255]
        let image = EdgeImage(width: 2, height: 1, bytes: bytes)!
        #expect(image.alpha(at: PixelPoint(x: 0, y: 0)) == 0)
        #expect(image.alpha(at: PixelPoint(x: 1, y: 0)) == 255)
        #expect(image.alpha(at: PixelPoint(x: 2, y: 0)) == nil)
    }
}
