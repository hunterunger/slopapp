import Foundation
import Testing
@testable import PaperCore

@Suite struct PageOrderTests {
    @Test func movingToTheEnd() {
        #expect(PageOrder.moving([0], to: 3, count: 3) == [1, 2, 0])
    }

    @Test func movingSeveralKeepsTheirOrder() {
        #expect(PageOrder.moving([0, 2], to: 4, count: 5) == [1, 3, 0, 2, 4])
    }

    @Test func movingToTheStart() {
        #expect(PageOrder.moving([3, 4], to: 0, count: 5) == [3, 4, 0, 1, 2])
    }

    @Test func movingOntoItselfChangesNothing() {
        #expect(PageOrder.moving([1], to: 1, count: 3) == [0, 1, 2])
        #expect(PageOrder.moving([1], to: 2, count: 3) == [0, 1, 2])
    }

    @Test func moveUpAndDown() {
        #expect(PageOrder.movingUp([2], count: 4) == [0, 2, 1, 3])
        #expect(PageOrder.movingUp([0], count: 4) == nil)
        #expect(PageOrder.movingDown([1, 2], count: 4) == [0, 3, 1, 2])
        #expect(PageOrder.movingDown([3], count: 4) == nil)
    }

    @Test func inverseUndoes() {
        let order = PageOrder.moving([0, 2], to: 4, count: 5)
        let inverse = PageOrder.inverse(order)
        let applied = order.map { $0 }
        #expect(inverse.map { applied[$0] } == [0, 1, 2, 3, 4])
    }

    @Test func newIndexesFollowThePages() {
        let order = PageOrder.moving([0], to: 3, count: 3)
        #expect(PageOrder.newIndexes(of: [0], in: order) == [2])
    }

    @Test func interleaveReversesTheBackScans() {
        let order = PageOrder.interleave(frontCount: 3, backCount: 3)
        #expect(order.map { "\($0.document)\($0.page)" } == ["00", "12", "01", "11", "02", "10"])
    }

    @Test func interleaveWithUnevenCounts() {
        let order = PageOrder.interleave(frontCount: 3, backCount: 1, reverseBack: false)
        #expect(order.count == 4)
        #expect(order.last!.document == 0)
    }

    @Test func chunks() {
        #expect(PageOrder.chunks(pageCount: 10, every: 4) == [0..<4, 4..<8, 8..<10])
        #expect(PageOrder.chunks(pageCount: 0, every: 4).isEmpty)
        #expect(PageOrder.chunks(pageCount: 3, every: 1).count == 3)
    }

    @Test func rangesFromOutlineStarts() {
        #expect(PageOrder.ranges(pageCount: 10, starts: [2, 5]) == [0..<2, 2..<5, 5..<10])
        #expect(PageOrder.ranges(pageCount: 6, starts: [0, 2, 4, 4]) == [0..<2, 2..<4, 4..<6])
    }

    @Test func labels() {
        #expect(PageOrder.label(0..<4) == "1–4")
        #expect(PageOrder.label(6..<7) == "7")
    }
}
