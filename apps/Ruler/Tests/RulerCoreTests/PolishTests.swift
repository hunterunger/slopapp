import CoreGraphics
import Foundation
import Testing
@testable import RulerCore

@Suite("Crisp strokes")
struct CrispStrokeTests {
    @Test func pointWidthIsWholePixels() {
        #expect(CrispStroke.pointWidth(scale: 1) == 1)
        #expect(CrispStroke.pointWidth(scale: 2) == 2)
        #expect(CrispStroke.pointWidth(scale: 3) == 3)
        #expect(CrispStroke.pointWidth(scale: 0.5) == 1)
    }

    @Test func aLineAtAPixelFillsThePointHoldingIt() {
        #expect(CrispStroke.band(holding: 7, scale: 1) == 7..<8)
        #expect(CrispStroke.band(holding: 7, scale: 2) == 6..<8)
        #expect(CrispStroke.band(holding: 8, scale: 2) == 8..<10)
        #expect(CrispStroke.band(holding: 7, scale: 3) == 6..<9)
        #expect(CrispStroke.band(holding: 0, scale: 2) == 0..<2)
        #expect(CrispStroke.band(holding: -1, scale: 2) == -2..<0)
    }

    @Test func aLineOnABoundaryIsCentredOnIt() {
        for scale in [1.0, 2, 3] {
            let band = CrispStroke.band(straddling: 100, scale: scale)
            #expect(100 - band.lowerBound == band.upperBound - 100)
            #expect(band.count >= CrispStroke.pointWidth(scale: scale))
        }
        #expect(CrispStroke.band(straddling: 100, scale: 2) == 99..<101)
    }

    @Test func dimensionTicksSitInsideTheMeasuredEdges() {
        let (line, halo) = CrispStroke.dimension(axis: .horizontal, at: 51, start: 10, end: 210, scale: 2)
        #expect(line[0] == PixelRect(minX: 10, minY: 50, maxX: 210, maxY: 52))
        // Ticks: outer edge on the measured edge, one point wide, 7 px past the line each way.
        #expect(line[1] == PixelRect(minX: 10, minY: 43, maxX: 12, maxY: 59))
        #expect(line[2] == PixelRect(minX: 208, minY: 43, maxX: 210, maxY: 59))
        #expect(halo == line.map { $0.outsetBy(1) })
        let vertical = CrispStroke.dimension(axis: .vertical, at: 5, start: 0, end: 40, scale: 1)
        #expect(vertical.line[0] == PixelRect(minX: 5, minY: 0, maxX: 6, maxY: 40))
        #expect(vertical.line[1] == PixelRect(minX: 1, minY: 0, maxX: 10, maxY: 1))
    }

    @Test func emphasizedLinesGrowAPixelEachSide() {
        let plain = CrispStroke.dimension(axis: .horizontal, at: 20, start: 0, end: 100, scale: 2).line[0]
        let bold = CrispStroke.dimension(axis: .horizontal, at: 20, start: 0, end: 100, scale: 2, emphasized: true).line[0]
        #expect(bold.minY == plain.minY - 1 && bold.maxY == plain.maxY + 1 && bold.minX == plain.minX)
    }

    @Test func tinySpansStillDrawInsideThemselves() {
        let (line, _) = CrispStroke.dimension(axis: .horizontal, at: 0, start: 4, end: 5, scale: 2)
        #expect(line.allSatisfy { $0.minX >= 4 && $0.maxX <= 5 })
    }
}

@Suite("Label placement, short lines")
struct ShortLineLabelTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let pill = CGSize(width: 48, height: 24)

    @Test func longLinesThreadTheirLabel() {
        let f = LabelLayout.lineLabel(size: pill, from: CGPoint(x: 100, y: 300), to: CGPoint(x: 300, y: 300), bounds: bounds)
        #expect(f.midX == 200 && f.midY == 300)
    }

    @Test func shortLinesPutTheLabelBesideNotOnTheEnds() {
        let a = CGPoint(x: 100, y: 300), b = CGPoint(x: 124, y: 300)
        let f = LabelLayout.lineLabel(size: pill, from: a, to: b, bounds: bounds)
        #expect(f.minY >= 300 + 4 + 6)
        #expect(f.midX == 112)
        let v = LabelLayout.lineLabel(size: pill, from: CGPoint(x: 500, y: 300), to: CGPoint(x: 500, y: 316), bounds: bounds)
        #expect(v.minX >= 500 + 4 + 6 && v.midY == 308)
    }

    @Test func besideFlipsAtTheDisplayEdge() {
        let f = LabelLayout.lineLabel(size: pill, from: CGPoint(x: 100, y: 790), to: CGPoint(x: 110, y: 790), bounds: bounds)
        #expect(f.maxY <= 790 - 4 - 6)
        let v = LabelLayout.lineLabel(size: pill, from: CGPoint(x: 990, y: 300), to: CGPoint(x: 990, y: 310), bounds: bounds)
        #expect(v.maxX <= 990 - 4 - 6)
    }

    @Test func exactlyEnoughRoomStillThreads() {
        let f = LabelLayout.lineLabel(size: pill, from: CGPoint(x: 0, y: 300), to: CGPoint(x: 60, y: 300), bounds: bounds)
        #expect(f.midY == 300)
    }
}
