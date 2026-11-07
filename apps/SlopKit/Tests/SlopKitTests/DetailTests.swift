import AppKit
import SwiftUI
import Testing
@testable import SlopKit

// The detail rules (design system §4) that are pure numbers.

@Suite struct RadiusTests {
    @Test func nestedIsConcentric() {
        #expect(Radius.nested(in: Radius.xl, padding: Spacing.s) == Radius.m)
        #expect(Radius.nested(in: Radius.xxl, padding: Spacing.m) == 10)
    }

    @Test func nestedNeverGoesBelowTheMinimum() {
        #expect(Radius.nested(in: Radius.l, padding: Spacing.xl) == 2)
        #expect(Radius.nested(in: Radius.l, padding: Spacing.xl, minimum: Radius.xs) == Radius.xs)
    }

    @Test func tokensAscendWithoutRepeats() {
        let tokens = [Radius.xs, Radius.s, Radius.m, Radius.l, Radius.xl, Radius.xxl]
        #expect(tokens == tokens.sorted())
        #expect(Set(tokens).count == tokens.count)
    }
}

@Suite struct DashPatternTests {
    @Test(arguments: [
        (CGSize(width: 600, height: 200), Radius.l),
        (CGSize(width: 480, height: 36), Radius.s),
        (CGSize(width: 333.5, height: 211.25), Radius.xl),
    ])
    func dashesFitTheOutlineAWholeNumberOfTimes(size: CGSize, radius: CGFloat) {
        let pattern = DashPattern.fitted(dash: 6, gap: 5, size: size, cornerRadius: radius, lineWidth: 1.5)
        let perimeter = DashPattern.perimeter(size: size, cornerRadius: radius, inset: 0.75)
        let repeats = perimeter / (pattern[0] + pattern[1])
        #expect(abs(repeats - repeats.rounded()) < 0.0001)
        // Close to the requested look: within half a period of stretch.
        #expect(abs(pattern[0] - 6) < 0.5)
        #expect(abs(pattern[0] / pattern[1] - 6.0 / 5) < 0.0001)
    }

    @Test func tinyShapesKeepThePlainPattern() {
        #expect(DashPattern.fitted(dash: 6, gap: 5, size: CGSize(width: 2, height: 2), cornerRadius: 1, lineWidth: 1) == [6, 5])
    }

    @Test func perimeterOfACircleAndASquare() {
        let circle = DashPattern.perimeter(size: CGSize(width: 20, height: 20), cornerRadius: 10, inset: 0)
        #expect(abs(circle - 2 * .pi * 10) < 0.0001)
        #expect(DashPattern.perimeter(size: CGSize(width: 10, height: 30), cornerRadius: 0, inset: 0) == 80)
    }
}

@MainActor @Suite struct HUDShapeTests {
    @Test func hudIsACapsule() {
        #expect(HUD.cornerRadius(height: 44) == 22)
        #expect(HUD.cornerRadius(height: 41) == 20)
    }
}

@Suite struct OverlayLayoutTests {
    @Test func loupeLeavesAGridGapAboveItsLabel() {
        #expect(LoupeLayer.labelArea - BadgeLayer.height >= Spacing.s)
        #expect(LoupeLayer.labelArea - BadgeLayer.height < Spacing.s + 1)
    }

    @Test func badgeInsetsAreOnTheGrid() {
        #expect(BadgeLayer.insets == CGSize(width: Spacing.s, height: Spacing.xs))
    }
}

@Suite struct ContrastTests {
    /// WCAG contrast of `color` on `background`, both resolved in `appearance`.
    static func contrast(_ color: NSColor, on background: NSColor, in appearance: NSAppearance.Name) -> Double {
        var result = 0.0
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            func luminance(_ c: NSColor) -> Double {
                let s = c.usingColorSpace(.sRGB)!
                func lin(_ v: CGFloat) -> Double { let v = Double(v); return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
                return 0.2126 * lin(s.redComponent) + 0.7152 * lin(s.greenComponent) + 0.0722 * lin(s.blueComponent)
            }
            let a = luminance(color), b = luminance(background)
            result = (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
        return result
    }

    @Test(arguments: [NSColor.systemGreen, .systemOrange, .systemRed])
    func statusTextPassesInBothModes(base: NSColor) {
        let readable = NSColor.readable(base, target: ReadableColor.statusTarget)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for background in [NSColor.windowBackgroundColor, .textBackgroundColor, .controlBackgroundColor] {
                #expect(Self.contrast(readable, on: background, in: appearance) >= 4.5,
                        "\(base) on \(background) in \(appearance.rawValue)")
            }
        }
    }

    @Test func plainGreenTextWouldFailInLightMode() {
        // Why `.textGreen` exists.
        #expect(Self.contrast(.systemGreen, on: .windowBackgroundColor, in: .aqua) < 3)
    }

    @Test func darkModeKeepsAColourThatAlreadyPasses() {
        var same = false
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            same = NSColor.readable(.systemGreen).usingColorSpace(.sRGB) == NSColor.systemGreen.usingColorSpace(.sRGB)
        }
        #expect(same)
    }

    @Test func darkensOnlyAsMuchAsNeeded() {
        let white = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let yellow = NSColor(srgbRed: 1, green: 0.8, blue: 0, alpha: 1)
        let fixed = ReadableColor.adjusted(yellow, toReach: 4.5, on: white, towards: .black)
        #expect(ReadableColor.ratio(fixed, white) >= 4.5)
        // One 2% step less would fail: it isn't darker than it has to be.
        var fraction: CGFloat = 0
        while ReadableColor.ratio(yellow.blended(withFraction: fraction, of: .black)!, white) < 4.5 { fraction += 0.02 }
        #expect(fraction > 0.02)
        #expect(ReadableColor.ratio(yellow.blended(withFraction: fraction - 0.02, of: .black)!, white) < 4.5)
        #expect(abs(ReadableColor.luminance(fixed) - ReadableColor.luminance(yellow.blended(withFraction: fraction, of: .black)!)) < 0.001)
        let ink = NSColor(srgbRed: 0.1, green: 0.1, blue: 0.3, alpha: 1)
        #expect(ReadableColor.adjusted(ink, toReach: 4.5, on: white, towards: .black) == ink)
    }

    @Test func lightensDarkColoursInDarkMode() {
        let ink = NSColor(srgbRed: 0.05, green: 0.05, blue: 0.15, alpha: 1)
        #expect(Self.contrast(.readable(ink, on: .windowBackgroundColor, target: ReadableColor.symbolTarget),
                              on: .windowBackgroundColor, in: .darkAqua) >= 3)
    }

    @Test func accentTextPassesForEveryAccent() {
        // A yellow accent is the worst case for light mode.
        let yellow = NSColor.readable(.systemYellow)
        #expect(Self.contrast(yellow, on: .textBackgroundColor, in: .aqua) >= 4.5)
        #expect(Self.contrast(.readable(.controlAccentColor), on: .textBackgroundColor, in: .aqua) >= 4.5)
    }

    @Test func translucentColoursAreJudgedAsDrawn() {
        let white = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let faint = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.2)
        #expect(ReadableColor.ratio(ReadableColor.adjusted(faint, toReach: 4.5, on: white, towards: .black), white) >= 4.5)
    }
}

@Suite struct OverlayPaletteTests {
    static func components(_ color: CGColor) -> [CGFloat] {
        NSColor(cgColor: color)!.usingColorSpace(.sRGB)!.cgColor.components ?? []
    }

    @Test func neverPureBlackOrWhite() {
        for color in [OverlayPalette.scrim, OverlayPalette.badgeFill, OverlayPalette.badgeText, OverlayPalette.ring,
                      OverlayPalette.ringShadow, OverlayPalette.ink.cgColor] {
            let c = Self.components(color)
            let rgb = Array(c.prefix(3)), alpha = c.last ?? 1
            let pureBlack = rgb.allSatisfy { $0 == 0 } && alpha == 1
            let pureWhite = rgb.allSatisfy { $0 == 1 } && alpha == 1
            #expect(!pureBlack && !pureWhite, "\(c)")
        }
    }

    @Test(arguments: [NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
                      NSColor(srgbRed: 1, green: 0.8, blue: 0, alpha: 1)])
    func badgeTextReadsOverAnyScreenContent(content: NSColor) {
        let fill = ReadableColor.flattened(NSColor(cgColor: OverlayPalette.badgeFill)!, over: content)
        let text = ReadableColor.flattened(NSColor(cgColor: OverlayPalette.badgeText)!, over: fill)
        #expect(ReadableColor.ratio(text, fill) >= 4.5)
    }
}

@Suite struct WindowStateTests {
    @Test func onlyInactiveCountsAsInactive() {
        #expect(ControlActiveState.key.isActiveWindow)
        #expect(ControlActiveState.active.isActiveWindow)
        #expect(!ControlActiveState.inactive.isActiveWindow)
    }

    @Test func inactiveWindowsUseGreys() {
        #expect(Color.windowAccent(.inactive) == Color(nsColor: .secondaryLabelColor))
        #expect(Color.selectionFill(.inactive) == Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
        #expect(Color.selectionRing(.inactive) == Color(nsColor: .systemGray))
        #expect(Color.windowAccent(.key) == .accentColor)
        #expect(Color.selectionTint(active: true, opacity: 0.2) == Color.accentColor.opacity(0.2))
    }
}
