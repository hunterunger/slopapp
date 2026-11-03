import Foundation
import Testing
@testable import DropperCore

func close(_ a: Double, _ b: Double, _ tolerance: Double = 0.001) -> Bool { abs(a - b) <= tolerance }
func close(_ a: RGB, _ b: RGB, _ tolerance: Double = 0.001) -> Bool {
    close(a.red, b.red, tolerance) && close(a.green, b.green, tolerance) && close(a.blue, b.blue, tolerance)
}

@Suite struct ConversionTests {
    // Reference values measured with NSColorSampler + ColorSync on a P3 display (see research doc).
    @Test func sRGBToP3MatchesColorSync() {
        let p3 = ColorMath.sRGBToP3(RGB(red: 0.2, green: 0.4, blue: 0.8))
        #expect(close(p3, RGB(red: 0.24988, green: 0.39526, blue: 0.77344)))
        let red = ColorMath.sRGBToP3(RGB(red: 1, green: 0, blue: 0))
        #expect(close(red, RGB(red: 0.91748, green: 0.20032, blue: 0.13855)))
    }

    @Test func p3RedIsOutsideSRGB() {
        let color = ColorValue(displayP3: RGB(red: 1, green: 0, blue: 0))
        #expect(close(color.sRGB, RGB(red: 1.09309, green: -0.22684, blue: -0.15008)))
        #expect(color.isOutsideSRGB)
        #expect(color.isOutside(.sRGB))
        #expect(!color.isOutside(.displayP3))
    }

    @Test func roundTripIsLossless() {
        for c in [RGB(red: 0.2, green: 0.4, blue: 0.8), RGB(red: 0.07, green: 0.67, blue: 0.5), RGB(red: 1, green: 1, blue: 1)] {
            let back = ColorMath.p3ToSRGB(ColorMath.sRGBToP3(c))
            #expect(close(back, c, 1e-6))
        }
    }

    @Test func grayAndWhiteAreTheSameInBothSpaces() {
        for v in [0.0, 0.5019, 1.0] {
            let p3 = ColorMath.sRGBToP3(RGB(red: v, green: v, blue: v))
            #expect(close(p3, RGB(red: v, green: v, blue: v), 1e-5))
        }
    }

    @Test func samplingNoiseIsNotOutOfGamut() {
        // ColorSync gave (1.00001, -0.00023, 0.0001) for an sRGB red.
        let color = ColorValue(red: 1.00001, green: -0.00023, blue: 0.0001)
        #expect(!color.isOutsideSRGB)
        #expect(ColorFormatter.string(color, as: .hex) == "#FF0000")
    }

    @Test func quantizeRoundsAndClamps() {
        let c = RGB(red: 1.09, green: -0.2, blue: 0.19998)
        #expect(c.bytes == (255, 0, 51))
        #expect(c.quantized == RGB(red: 1, green: 0, blue: 0.2))
    }

    @Test func identityKeySeparatesP3RedFromSRGBRed() {
        let p3Red = ColorValue(displayP3: RGB(red: 1, green: 0, blue: 0))
        let sRed = ColorValue(red: 1, green: 0, blue: 0)
        #expect(p3Red.identityKey != sRed.identityKey)
        #expect(ColorValue(red: 0.2, green: 0.4, blue: 0.8).identityKey == ColorValue(red: 0.20001, green: 0.39999, blue: 0.8).identityKey)
    }

    @Test func hslAndHsb() {
        let c = RGB(red: 0.2, green: 0.4, blue: 0.8)
        #expect(c.hsl == HSL(hue: 220, saturation: 60, lightness: 50))
        #expect(c.hsb == HSB(hue: 220, saturation: 75, brightness: 80))
    }

    @Test func graysHaveNoHueOrSaturation() {
        let gray = RGB(red: 0.5, green: 0.5, blue: 0.5)
        #expect(gray.hsl == HSL(hue: 0, saturation: 0, lightness: 50))
        #expect(gray.hsb == HSB(hue: 0, saturation: 0, brightness: 50))
        #expect(RGB(red: 0, green: 0, blue: 0).hsb == HSB(hue: 0, saturation: 0, brightness: 0))
        #expect(RGB(red: 1, green: 1, blue: 1).hsl == HSL(hue: 0, saturation: 0, lightness: 100))
    }

    @Test func hueNear360WrapsToZero() {
        // Red with a hint of blue: hue 359.8 rounds to 360, which must show as 0.
        let c = RGB(red: 1, green: 0, blue: 0.003)
        #expect(c.hsl.hue == 0)
        #expect(RGB(red: 1, green: 0, blue: 1).hsl.hue == 300)
        #expect(RGB(red: 0, green: 1, blue: 0).hsb.hue == 120)
    }
}
