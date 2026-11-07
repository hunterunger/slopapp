import Foundation

/// A colour as sRGB components, 0–1. Pure maths for the card header (no AppKit).
public struct RGB: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let white = RGB(1, 1, 1)
    public static let black = RGB(0, 0, 0)
    /// The system grey (light appearance), for clips with no known app.
    public static let neutral = RGB(142 / 255, 142 / 255, 147 / 255)

    /// Hue, 0–1 (red 0, yellow ~0.17, green ~0.33, blue ~0.67).
    public var hue: Double {
        let maxC = max(red, green, blue), minC = min(red, green, blue), delta = maxC - minC
        guard delta > 0 else { return 0 }
        var h: Double
        if maxC == red { h = (green - blue) / delta } else if maxC == green { h = 2 + (blue - red) / delta } else { h = 4 + (red - green) / delta }
        h /= 6
        return h < 0 ? h + 1 : h
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio, 1–21.
    public func contrast(with other: RGB) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// `self` mixed with `other`: 0 is `self`, 1 is `other`.
    public func mixed(with other: RGB, _ fraction: Double) -> RGB {
        RGB(red + (other.red - red) * fraction, green + (other.green - green) * fraction, blue + (other.blue - blue) * fraction)
    }
}

/// The colour band at the top of a card: the source app's colour, with type that stays
/// readable on it.
///
/// White type is preferred (it's what makes the colours read as confident). The colour is
/// darkened only as far as white needs for 4.5:1, which the small time line needs (the type
/// word is bold and larger). Both lines are pure white and differ by size and weight, so the
/// colours stay as bright as contrast allows. Only colours so light that darkening would turn
/// them muddy (yellows, very pale icons) keep their colour and get dark type instead.
public struct HeaderColor: Equatable, Sendable {
    public enum Ink: Equatable, Sendable { case light, dark }

    public var fill: RGB
    public var ink: Ink

    /// Opacity of dark type's time line (light type is pure white on both lines).
    public static let darkSecondaryOpacity = 0.7
    public static let minimumContrast = 4.5
    /// Colours lighter than this (relative luminance) get dark type: yellow is ~0.6.
    public static let darkInkLuminance = 0.55
    /// Oranges and yellows turn brown when darkened: past this much darkening they keep their
    /// colour and get dark type instead.
    public static let warmDarkeningLimit = 0.3
    public static let warmHues = 0.07...0.2
    /// Dark mode sits a little deeper (white type only).
    public static let darkModeDepth = 0.12

    public static func resolve(base: RGB, darkMode: Bool) -> HeaderColor {
        let start = darkMode ? base.mixed(with: .black, darkModeDepth) : base
        // Dark type sits on the bright colour itself, in dark mode too (deepened, it goes muddy).
        if base.luminance > darkInkLuminance { return HeaderColor(fill: base, ink: .dark) }
        var darkening = 0.0
        while darkening < 1 {
            let fill = start.mixed(with: .black, darkening)
            if contrast(of: .light, on: fill) >= minimumContrast {
                // Count dark mode's depth too: the total is what turns an orange brown.
                let total = 1 - (1 - (darkMode ? darkModeDepth : 0)) * (1 - darkening)
                if total > warmDarkeningLimit, warmHues.contains(base.hue) { return HeaderColor(fill: base, ink: .dark) }
                return HeaderColor(fill: fill, ink: .light)
            }
            darkening += 0.02
        }
        return HeaderColor(fill: .black, ink: .light)
    }

    /// Contrast of the (weaker) time line on `fill`.
    public static func contrast(of ink: Ink, on fill: RGB) -> Double {
        let type: RGB = ink == .light ? .white : .black
        let opacity = ink == .light ? 1 : darkSecondaryOpacity
        return fill.mixed(with: type, opacity).contrast(with: fill)
    }
}
