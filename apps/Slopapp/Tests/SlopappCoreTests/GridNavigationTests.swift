import Testing
@testable import SlopappCore

@Suite struct GridNavigationTests {
    // Section A: 3 cards in 2 columns (rows: [0,1] [2]); section B: 4 cards ([3,4] [5,6]).
    let grid = GridNavigation(sections: [3, 4], columns: 2)

    @Test func startsAtTheFirstCard() {
        #expect(grid.move(from: nil, .down) == 0)
        #expect(GridNavigation(sections: [], columns: 2).move(from: nil, .down) == nil)
    }

    @Test func leftAndRightWalkTheList() {
        #expect(grid.move(from: 0, .left) == 0)
        #expect(grid.move(from: 2, .right) == 3)
        #expect(grid.move(from: 6, .right) == 6)
    }

    @Test func downStaysInTheColumnAndCrossesSections() {
        #expect(grid.move(from: 0, .down) == 2)
        #expect(grid.move(from: 1, .down) == 2)   // short last row: closest card
        #expect(grid.move(from: 2, .down) == 3)   // into section B, same column
        #expect(grid.move(from: 4, .down) == 6)
        #expect(grid.move(from: 6, .down) == 6)
    }

    @Test func upMirrorsDown() {
        #expect(grid.move(from: 2, .up) == 0)
        #expect(grid.move(from: 4, .up) == 2)     // column 1 of A's last row doesn't exist: closest
        #expect(grid.move(from: 3, .up) == 2)
        #expect(grid.move(from: 0, .up) == 0)
    }

    @Test func columnsThatFit() {
        #expect(GridNavigation.columns(width: 731, minimum: 300, spacing: 24) == 2)
        #expect(GridNavigation.columns(width: 299, minimum: 300, spacing: 24) == 1)
        #expect(GridNavigation.columns(width: 1000, minimum: 300, spacing: 24) == 3)
    }
}
