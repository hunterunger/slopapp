import Foundation
import Testing
@testable import DropperCore

@Suite struct FormatTests {
    let blue = ColorValue(red: 0.2, green: 0.4, blue: 0.8)

    @Test(arguments: [
        (ColorFormat.hex, "#3366CC"),
        (.cssRGB, "rgb(51, 102, 204)"),
        (.cssHSL, "hsl(220, 60%, 50%)"),
        (.hsb, "hsb(220, 75%, 80%)"),
        (.swiftUI, "Color(red: 0.2, green: 0.4, blue: 0.8)"),
        (.nsColor, "NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1)"),
        (.uiColor, "UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)"),
    ])
    func sRGBFormats(format: ColorFormat, expected: String) {
        #expect(ColorFormatter.string(blue, as: format) == expected)
    }

    @Test(arguments: [
        (ColorFormat.hex, "#3366CC"),
        (.cssRGB, "rgb(51, 102, 204)"),
        (.swiftUI, "Color(.displayP3, red: 0.2, green: 0.4, blue: 0.8)"),
        (.nsColor, "NSColor(displayP3Red: 0.2, green: 0.4, blue: 0.8, alpha: 1)"),
        (.uiColor, "UIColor(displayP3Red: 0.2, green: 0.4, blue: 0.8, alpha: 1)"),
        (.cssDisplayP3, "color(display-p3 0.2 0.4 0.8)"),
    ])
    func p3Formats(format: ColorFormat, expected: String) {
        let p3Blue = ColorValue(displayP3: RGB(red: 0.2, green: 0.4, blue: 0.8))
        #expect(ColorFormatter.string(p3Blue, as: format, options: FormatOptions(space: .displayP3)) == expected)
    }

    @Test func cssDisplayP3IsAlwaysP3() {
        // sRGB #3366CC in P3 is about (0.25, 0.395, 0.773).
        #expect(ColorFormatter.string(blue, as: .cssDisplayP3) == "color(display-p3 0.251 0.396 0.773)")
    }

    @Test func sColorValueReportedInP3() {
        let red = ColorValue(red: 1, green: 0, blue: 0)
        #expect(ColorFormatter.string(red, as: .hex, options: FormatOptions(space: .displayP3)) == "#EA3323")
    }

    @Test func outOfGamutClampsInSRGB() {
        let p3Red = ColorValue(displayP3: RGB(red: 1, green: 0, blue: 0))
        #expect(ColorFormatter.string(p3Red, as: .hex) == "#FF0000")
        #expect(ColorFormatter.string(p3Red, as: .swiftUI) == "Color(red: 1, green: 0, blue: 0)")
        #expect(ColorFormatter.string(p3Red, as: .hex, options: FormatOptions(space: .displayP3)) == "#FF0000")
    }

    @Test func hexOptions() {
        #expect(ColorFormatter.string(blue, as: .hex, options: FormatOptions(hexUppercase: false)) == "#3366cc")
        #expect(ColorFormatter.string(blue, as: .hex, options: FormatOptions(hexPrefix: false)) == "3366CC")
        #expect(ColorFormatter.string(blue, as: .hex, options: FormatOptions(hexUppercase: false, hexPrefix: false)) == "3366cc")
    }

    @Test func unitComponents() {
        #expect(ColorFormatter.unit(0) == "0")
        #expect(ColorFormatter.unit(1) == "1")
        #expect(ColorFormatter.unit(0.2) == "0.2")
        #expect(ColorFormatter.unit(1.0 / 3) == "0.333")
        #expect(ColorFormatter.unit(0.0004) == "0")
        #expect(ColorFormatter.unit(0.9996) == "1")
        #expect(ColorFormatter.unit(-0.1) == "0")
        #expect(ColorFormatter.unit(18.0 / 255) == "0.071")
    }

    @Test func formatsUseQuantizedValues() {
        // A sample a hair off #12AB7F still writes the same color in every format.
        let sample = ColorValue(red: 0.07079, green: 0.67063, blue: 0.49792)
        #expect(ColorFormatter.string(sample, as: .hex) == "#12AB7F")
        #expect(ColorFormatter.string(sample, as: .swiftUI) == "Color(red: 0.071, green: 0.671, blue: 0.498)")
    }

    @Test func numbersIgnoreTheLocale() async {
        // String(format:) without a locale is already POSIX, but make sure nothing reads the
        // current locale: run formatting while a decimal-comma locale is the default.
        let saved = UserDefaults.standard.object(forKey: "AppleLocale")
        UserDefaults.standard.set("de_DE", forKey: "AppleLocale")
        defer { UserDefaults.standard.set(saved, forKey: "AppleLocale") }
        for format in ColorFormat.allCases {
            let text = ColorFormatter.string(ColorValue(red: 0.25, green: 0.5, blue: 0.75), as: format)
            #expect(text.range(of: #"\d,\d"#, options: .regularExpression) == nil, "\(format) wrote a decimal comma: \(text)")
        }
    }

    @Test func blackAndWhite() {
        #expect(ColorFormatter.string(ColorValue(red: 0, green: 0, blue: 0), as: .cssHSL) == "hsl(0, 0%, 0%)")
        #expect(ColorFormatter.string(ColorValue(red: 1, green: 1, blue: 1), as: .nsColor) == "NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)")
    }
}

@Suite struct HexParserTests {
    @Test(arguments: ["#3366CC", "3366cc", "#36c", "36C", "  #3366CC \n"])
    func parsesValidHex(text: String) {
        #expect(HexParser.parse(text) == RGB(red: 0.2, green: 0.4, blue: 0.8))
    }

    @Test(arguments: ["", "#", "#12", "#1234", "#GGGGGG", "3366CCFF", "#3366CC80", "rgb(1,2,3)", "# 3366CC"])
    func rejectsInvalidHex(text: String) {
        #expect(HexParser.parse(text) == nil)
    }

    @Test func hexInP3() {
        let color = HexParser.color("#FF0000", in: .displayP3)
        #expect(color?.isOutsideSRGB == true)
        #expect(color.map { ColorFormatter.string($0, as: .hex, options: FormatOptions(space: .displayP3)) } == "#FF0000")
    }
}
