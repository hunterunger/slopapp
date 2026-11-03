import Foundation
import Testing
@testable import RulerCore

@Suite("Units and copy formats")
struct UnitTests {
    let en = Locale(identifier: "en_US")

    @Test func pointsOnRetinaShowHalfPoints() {
        let r = Readout(scale: 2, unit: .points, locale: en)
        #expect(r.length(400) == "200 pt")
        #expect(r.length(201) == "100.5 pt")
        #expect(r.length(1) == "0.5 pt")
        #expect(r.size(width: 201, height: 101) == "100.5 × 50.5 pt")
    }

    @Test func pixelsAreBackingPixels() {
        let r = Readout(scale: 2, unit: .pixels, locale: en)
        #expect(r.length(201) == "201 px")
        #expect(r.size(width: 400, height: 240) == "400 × 240 px")
    }

    @Test func oneXDisplayPointsEqualPixels() {
        #expect(Readout(scale: 1, unit: .points, locale: en).length(37) == "37 pt")
    }

    @Test func usesTheLocaleDecimalSeparator() {
        let r = Readout(scale: 2, unit: .points, locale: Locale(identifier: "de_DE"))
        #expect(r.length(201) == "100,5 pt")
        #expect(r.length(4000) == "2000 pt") // no grouping
    }

    @Test func spokenSize() {
        #expect(Readout(scale: 2, unit: .points, locale: en).spokenSize(width: 400, height: 240) == "200 by 120 points")
    }

    @Test func copyFormats() {
        let r = Readout(scale: 2, unit: .points, locale: Locale(identifier: "de_DE"))
        #expect(CopyFormat.plain.text(width: 400, height: 201, readout: r) == "200 × 100,5")
        #expect(CopyFormat.css.text(width: 400, height: 201, readout: r) == "width: 200px;\nheight: 100.5px;")
        #expect(CopyFormat.swiftUI.text(width: 400, height: 201, readout: r) == ".frame(width: 200, height: 100.5)")
    }

    @Test func nudgeSteps() {
        #expect(MeasureUnit.points.nudgeStep(scale: 2, large: false) == 1)
        #expect(MeasureUnit.points.nudgeStep(scale: 2, large: true) == 10)
        #expect(MeasureUnit.pixels.nudgeStep(scale: 2, large: false) == 0.5)
        #expect(MeasureUnit.pixels.nudgeStep(scale: 2, large: true) == 5)
        #expect(MeasureUnit.pixels.nudgeStep(scale: 1, large: false) == 1)
    }

    @Test func toleranceSteps() {
        #expect(Tolerance.default == .normal)
        #expect(Tolerance.normal.looser == .loose)
        #expect(Tolerance.loose.looser == nil)
        #expect(Tolerance.strict.stricter == nil)
        #expect(Tolerance.allCases.map(\.threshold) == Tolerance.allCases.map(\.threshold).sorted())
    }
}

@Suite("Board")
struct BoardTests {
    let bounds = PixelRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func hoverInsideAnAreaStopsAtItsEdges() {
        var board = Board()
        board.addArea(PixelRect(x: 100, y: 100, width: 200, height: 100))
        let l = board.limits(for: PixelPoint(x: 150, y: 150), in: bounds)
        #expect(l == PixelRect(x: 100, y: 100, width: 200, height: 100))
    }

    @Test func hoverBetweenAreasMeasuresTheGap() {
        var board = Board()
        board.addArea(PixelRect(x: 100, y: 100, width: 50, height: 50))
        board.addArea(PixelRect(x: 200, y: 100, width: 50, height: 50))
        let l = board.limits(for: PixelPoint(x: 170, y: 120), in: bounds)
        #expect(l.minX == 150 && l.maxX == 200)
        // Areas that don't share the row or column don't limit it.
        #expect(l.minY == 0 && l.maxY == 800)
    }

    @Test func guidesLimitHover() {
        var board = Board()
        board.addGuide(.vertical, at: 300)
        board.addGuide(.horizontal, at: 50)
        let l = board.limits(for: PixelPoint(x: 100, y: 100), in: bounds)
        #expect(l == PixelRect(minX: 0, minY: 50, maxX: 300, maxY: 800))
        // On the guide's own boundary pixel the guide is on the left.
        #expect(board.limits(for: PixelPoint(x: 300, y: 10), in: bounds).minX == 300)
    }

    @Test func duplicateGuidesAreIgnored() {
        var board = Board()
        let a = board.addGuide(.vertical, at: 10)
        let b = board.addGuide(.vertical, at: 10)
        #expect(a == b)
        #expect(board.guides.count == 1)
    }

    @Test func guideGaps() {
        var board = Board()
        for x in [300, 100, 160] { board.addGuide(.vertical, at: x) }
        board.addGuide(.horizontal, at: 5)
        let gaps = board.guideGaps(.vertical)
        #expect(gaps.map(\.start) == [100, 160])
        #expect(gaps.map(\.end) == [160, 300])
        #expect(board.guideGaps(.horizontal).isEmpty)
    }

    @Test func hitTestingPrefersGuidesThenPinsThenSmallestArea() {
        var board = Board()
        let big = board.addArea(PixelRect(x: 0, y: 0, width: 500, height: 500))
        let small = board.addArea(PixelRect(x: 100, y: 100, width: 50, height: 50))
        #expect(board.item(at: PixelPoint(x: 120, y: 120), slop: 4) == .area(small))
        #expect(board.item(at: PixelPoint(x: 300, y: 300), slop: 4) == .area(big))
        let pin = board.addPin(point: PixelPoint(x: 400, y: 400), spans: PixelRect(minX: 350, minY: 380, maxX: 450, maxY: 420))
        #expect(board.item(at: PixelPoint(x: 360, y: 402), slop: 4) == .pin(pin))
        let guide = board.addGuide(.horizontal, at: 121)
        #expect(board.item(at: PixelPoint(x: 120, y: 119), slop: 4) == .guide(guide))
        #expect(board.item(at: PixelPoint(x: 700, y: 700), slop: 4) == nil)
    }

    @Test func lastMeasuredFollowsAddsAndRemoves() {
        var board = Board()
        let a = board.addArea(PixelRect(x: 0, y: 0, width: 10, height: 10))
        let p = board.addPin(point: PixelPoint(x: 1, y: 1), spans: PixelRect(x: 0, y: 0, width: 4, height: 6))
        #expect(board.lastMeasured == .pin(p))
        #expect(board.size(of: .pin(p))! == (4, 6))
        board.remove(.pin(p))
        #expect(board.lastMeasured == .area(a))
        board.addGuide(.vertical, at: 3)
        #expect(board.lastMeasured == .area(a)) // guides aren't measurements
        board.clear()
        #expect(board.isEmpty && board.lastMeasured == nil)
    }

    @Test func settlingAPendingArea() {
        var board = Board()
        let id = board.addArea(PixelRect(x: 0, y: 0, width: 100, height: 100), settled: false)
        #expect(board.area(id)?.isSettled == false)
        let settled = board.settleArea(id, rect: PixelRect(x: 10, y: 10, width: 20, height: 20))
        #expect(settled)
        #expect(board.area(id)?.rect.width == 20)
        #expect(board.area(id)?.isSettled == true)
        board.remove(.area(id))
        let again = board.settleArea(id, rect: PixelRect(x: 0, y: 0, width: 1, height: 1))
        #expect(!again)
    }

    @Test func undoIsAValueCopy() {
        var board = Board()
        board.addArea(PixelRect(x: 0, y: 0, width: 10, height: 10))
        let before = board
        board.clear()
        #expect(before.count == 1 && board.count == 0)
    }
}

@Suite("Test scene layout")
struct TestSceneLayoutTests {
    @Test func shapesFitTheSceneAndHaveUniqueIDs() {
        let bounds = CGRect(origin: .zero, size: TestSceneLayout.size)
        #expect(Set(TestSceneLayout.shapes.map(\.id)).count == TestSceneLayout.shapes.count)
        for shape in TestSceneLayout.shapes { #expect(bounds.contains(shape.frame), "\(shape.id)") }
    }

    @Test func pairGapIs24() {
        let l = TestSceneLayout.shape("pairLeft")!.frame, r = TestSceneLayout.shape("pairRight")!.frame
        #expect(r.minX - l.maxX == 24)
    }
}
