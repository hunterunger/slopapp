import Foundation
import Testing
@testable import DropperCore

@Suite struct ContrastTests {
    let black = ColorValue(red: 0, green: 0, blue: 0)
    let white = ColorValue(red: 1, green: 1, blue: 1)

    @Test func extremes() {
        #expect(close(Contrast.ratio(black, white), 21))
        #expect(close(Contrast.ratio(white, black), 21))
        #expect(Contrast.ratio(white, white) == 1)
        #expect(Contrast.formatted(21) == "21.00:1")
        #expect(Contrast.formatted(1) == "1.00:1")
    }

    @Test func knownPair() {
        // #767676 on white is the classic "just passes AA" gray: 4.54:1.
        let gray = HexParser.color("#767676", in: .sRGB)!
        let report = ContrastReport(text: gray, background: white)
        #expect(report.formattedRatio == "4.54:1")
        #expect(report.checks.first { $0.kind == .normalText && $0.level == .aa }?.passes == true)
        #expect(report.checks.first { $0.kind == .normalText && $0.level == .aaa }?.passes == false)
    }

    @Test func justUnderAThresholdFailsAndShowsTruncated() {
        // #777777 on white is 4.48:1: fails AA for normal text.
        let gray = HexParser.color("#777777", in: .sRGB)!
        let report = ContrastReport(text: gray, background: white)
        #expect(report.ratio < 4.5)
        #expect(report.formattedRatio == "4.47:1" || report.formattedRatio == "4.48:1")
        #expect(report.checks.first { $0.kind == .normalText && $0.level == .aa }?.passes == false)
        #expect(report.checks.first { $0.kind == .largeText && $0.level == .aa }?.passes == true)
    }

    @Test func truncatesNeverRoundsUp() {
        #expect(Contrast.formatted(4.499) == "4.49:1")
        #expect(Contrast.formatted(6.999999) == "6.99:1")
        #expect(Contrast.formatted(7.0) == "7.00:1")
    }

    @Test func thresholdsAreInclusive() {
        let report = ContrastReport(text: black, background: white)
        #expect(report.checks.count == 5)
        #expect(report.checks.allSatisfy { $0.passes })
        let same = ContrastReport(text: white, background: white)
        #expect(same.checks.allSatisfy { !$0.passes })
    }

    @Test func p3ColorsAreComparedInSRGB() {
        let p3Red = ColorValue(displayP3: RGB(red: 1, green: 0, blue: 0))
        let sRed = ColorValue(red: 1, green: 0, blue: 0)
        #expect(Contrast.ratio(p3Red, white) == Contrast.ratio(sRed, white))
    }

    @Test func summary() {
        let report = ContrastReport(text: black, background: white)
        let text = report.summary(text: "#000000", background: "#FFFFFF")
        #expect(text.hasPrefix("Contrast 21.00:1 (#000000 on #FFFFFF)"))
        #expect(text.contains("Normal text AA: Pass"))
        #expect(text.contains("Interface elements AA: Pass"))
    }
}
