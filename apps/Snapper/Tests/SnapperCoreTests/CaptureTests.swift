import CoreGraphics
import Testing
@testable import SnapperCore

@Suite("Remembered area")
struct RememberedAreaTests {
    @Test func rememberedAreaSurvivesOnlyIfItStillFits() {
        let area = RememberedArea(displayID: 1, rect: CGRect(x: 100, y: 100, width: 300, height: 200))
        #expect(area.rect(within: CGRect(x: 0, y: 0, width: 1440, height: 900)) == area.rect)
        #expect(area.rect(within: CGRect(x: 0, y: 0, width: 250, height: 900)) == CGRect(x: 100, y: 100, width: 150, height: 200))
        #expect(area.rect(within: CGRect(x: 0, y: 0, width: 50, height: 50)) == nil)
    }
}
