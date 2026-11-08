import Foundation
import Testing
@testable import GaugeCore

@Suite struct RingTests {
    @Test func keepsTheNewestInOrder() {
        var ring = Ring<Int>(capacity: 3)
        #expect(ring.isEmpty)
        #expect(ring.last == nil)
        for value in 1...5 { ring.append(value) }
        #expect(ring.elements == [3, 4, 5])
        #expect(ring.last == 5)
        #expect(ring.count == 3)
        ring.removeAll()
        #expect(ring.elements.isEmpty)
        ring.append(9)
        #expect(ring.elements == [9])
    }

    @Test func lastBeforeAndAfterWrapping() {
        var ring = Ring<Int>(capacity: 2)
        ring.append(1)
        #expect(ring.last == 1)
        ring.append(2)
        ring.append(3)
        #expect(ring.last == 3)
        ring.append(4)
        #expect(ring.last == 4)
        #expect(ring.elements == [3, 4])
    }
}

@Suite struct TimeSeriesTests {
    @Test func tenMinutesKeepsEverySampleInTheSpan() {
        var series = TimeSeries()
        for second in stride(from: 0, through: 900, by: 2) { series.append(Double(second), at: Double(second)) }
        let points = series.points(span: .tenMinutes, now: 900)
        #expect(points.first?.time == 300)
        #expect(points.last?.time == 900)
        #expect(points.count == 301)
        #expect(series.latest == 900)
    }

    @Test func hourUsesThirtySecondAveragesPlusTheLiveBucket() {
        var series = TimeSeries()
        for second in 0..<75 { series.append(second < 30 ? 1 : 3, at: Double(second)) }
        let points = series.points(span: .hour, now: 75)
        // Two closed buckets (0–30 → 1, 30–60 → 3) and the one filling (60–75 → 3).
        #expect(points.map(\.value) == [1, 3, 3])
        #expect(points.map(\.time) == [15, 45, 75])
    }

    @Test func sleepIsAGapNotALine() {
        var series = TimeSeries()
        series.append(0.5, at: 10)
        series.appendGap(at: 12)
        series.appendGap(at: 13) // a second gap in a row is ignored
        series.append(0.9, at: 500)
        let points = series.points(span: .tenMinutes, now: 500)
        #expect(points.count == 3)
        #expect(points[1].isGap)
        #expect(series.points(span: .hour, now: 500).contains { $0.isGap })
        #expect(series.latest == Double(Float(0.9)))
    }

    @Test func gapOnEmptyHistoryIsIgnored() {
        var series = TimeSeries()
        series.appendGap(at: 1)
        #expect(series.isEmpty)
    }

    @Test func peakIgnoresGapsAndNonFiniteValues() {
        var series = TimeSeries()
        series.append(0.2, at: 1)
        series.append(.infinity, at: 2)
        series.append(.nan, at: 3)
        series.append(0.7, at: 4)
        series.appendGap(at: 5)
        series.append(0.4, at: 6)
        #expect(series.peak(span: .tenMinutes, now: 6) == Double(Float(0.7)))
        #expect(TimeSeries().peak(span: .tenMinutes, now: 6) == nil)
    }

    @Test func decimateKeepsPeaksAndGaps() {
        var points = (0..<600).map { TimeSeries.Point(time: Double($0), value: 0.1) }
        points[123].value = 0.9
        points[400] = TimeSeries.Point(time: 400, value: .nan)
        let thinned = TimeSeries.decimate(points, to: 300)
        #expect(thinned.count <= 302)
        #expect(thinned.contains { $0.value == 0.9 })
        #expect(thinned.contains { $0.isGap })
        #expect(TimeSeries.decimate(Array(points.prefix(10)), to: 300).count == 10)
        #expect(thinned.map(\.time) == thinned.map(\.time).sorted())
    }

    @Test func capacityBoundsMemory() {
        var series = TimeSeries(fineCapacity: 10, coarseCapacity: 4)
        for second in 0..<1000 { series.append(1, at: Double(second)) }
        #expect(series.points(span: .tenMinutes, now: 999).count == 10)
        #expect(series.points(span: .hour, now: 999).count == 5) // 4 closed + the live one
    }
}
