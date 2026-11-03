import Foundation
import Testing
@testable import DropperCore

@Suite struct ColorParserTests {
    let blue = RGB(red: 0.2, green: 0.4, blue: 0.8)

    @Test(arguments: [
        "#3366CC", "36c", "rgb(51, 102, 204)", "rgb(51 102 204)", "RGB(51,102,204)",
        "rgba(51, 102, 204, 1)", "rgb(51 102 204 / 100%)", "rgb(20%, 40%, 80%)",
        "hsl(220, 60%, 50%)", "hsl(220 60% 50%)", "hsla(220deg, 60%, 50%, 1)", "hsl(580, 60%, 50%)",
        "  rgb(51, 102, 204)\n",
    ])
    func readsCommonSyntaxes(text: String) throws {
        let color = try #require(ColorParser.color(text, in: .sRGB))
        #expect(close(color.sRGB, blue, 0.002), "\(text) -> \(color.sRGB)")
    }

    @Test(arguments: [
        "", "rgb(51, 102)", "rgb(300, 0, 0)", "rgba(51, 102, 204, 0.5)", "hsl(220, 60, 50)",
        "hsl(220, 60%, 150%)", "lab(50 20 30)", "rgb(a, b, c)", "rgb 51 102 204", "color(srgb 1 0 0)",
    ])
    func rejectsTheRest(text: String) {
        #expect(ColorParser.color(text, in: .sRGB) == nil)
    }

    @Test func displayP3FunctionIsAlwaysP3() throws {
        let color = try #require(ColorParser.color("color(display-p3 1 0 0)", in: .sRGB))
        #expect(color.isOutsideSRGB)
        #expect(ColorFormatter.string(color, as: .cssDisplayP3) == "color(display-p3 1 0 0)")
    }

    @Test func rgbIsReadInTheChosenSpace() throws {
        let color = try #require(ColorParser.color("rgb(255, 0, 0)", in: .displayP3))
        #expect(color.isOutsideSRGB)
    }

    @Test func hslRoundTripsThroughTheFormatter() throws {
        for hex in ["#3366CC", "#12AB7F", "#808080", "#FF00FF", "#000000", "#FFFFFF"] {
            let c = try #require(HexParser.color(hex, in: .sRGB))
            let hsl = ColorFormatter.string(c, as: .cssHSL)
            let back = try #require(ColorParser.color(hsl, in: .sRGB))
            // HSL is rounded to whole numbers, so allow a couple of 8-bit steps.
            #expect(close(back.sRGB, c.sRGB, 3.0 / 255), "\(hex) -> \(hsl)")
        }
    }
}
