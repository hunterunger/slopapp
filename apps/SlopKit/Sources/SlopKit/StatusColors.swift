import AppKit
import SwiftUI

// Readable colours for text and small symbols (design system §4, Contrast).
//
// A colour picked for its hue (system green, the user's accent, a highlighter yellow, a
// syntax colour) often doesn't read as text: system green on a light window is about 2:1,
// well under the 4.5:1 body text needs. `readable` keeps the hue and mixes in just enough
// black (light mode) or white (dark mode) to reach a contrast target against a background,
// and leaves it alone if it already passes. It's resolved when drawn, so it follows the
// appearance, the accent colour and Increase Contrast.
//
//     Text(result).foregroundStyle(.readable(.controlAccentColor))           // 4.5:1 text
//     Image(systemName: "circle.fill").foregroundStyle(.readable(ink, on: .windowBackgroundColor, target: 3))
//     NSColor.readable(.systemPink)                                          // AppKit
//
// Status text has ready-made versions:
//
//     Text("−74%").foregroundStyle(.textGreen)
//     Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.textOrange)
//
// Large fills (badges, progress, dots) can keep the plain `.green` / `.orange` / `.red`.

public extension ShapeStyle where Self == Color {
    /// System green, readable as text in light and dark mode.
    static var textGreen: Color { Color(nsColor: .readable(.systemGreen, target: ReadableColor.statusTarget)) }
    /// System orange, readable as text in light and dark mode.
    static var textOrange: Color { Color(nsColor: .readable(.systemOrange, target: ReadableColor.statusTarget)) }
    /// System red, readable as text in light and dark mode.
    static var textRed: Color { Color(nsColor: .readable(.systemRed, target: ReadableColor.statusTarget)) }
    /// The user's accent colour, readable as text (a yellow or graphite accent needs help).
    static var textAccent: Color { Color(nsColor: .readable(.controlAccentColor)) }

    /// `base`, adjusted only as much as it needs to reach `target` contrast on `background`
    /// in the current appearance (4.5:1 for text; 3:1 for symbols and large text).
    static func readable(_ base: NSColor, on background: NSColor = .textBackgroundColor,
                         target: CGFloat = ReadableColor.textTarget) -> Color {
        Color(nsColor: .readable(base, on: background, target: target))
    }
}

public extension NSColor {
    /// `base`, mixed with just enough black (light mode) or white (dark mode) to reach
    /// `target` contrast against `background`; unchanged if it already does. A dynamic
    /// colour: resolved per appearance when drawn, so it follows the accent colour and
    /// Increase Contrast. Translucent colours are judged as drawn over `background`.
    static func readable(_ base: NSColor, on background: NSColor = .textBackgroundColor,
                         target: CGFloat = ReadableColor.textTarget) -> NSColor {
        NSColor(name: nil) { appearance in
            var resolvedBase = base
            var resolvedBackground = background
            appearance.performAsCurrentDrawingAppearance {
                resolvedBase = base.usingColorSpace(.sRGB) ?? base
                resolvedBackground = background.usingColorSpace(.sRGB) ?? background
            }
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return ReadableColor.adjusted(resolvedBase, toReach: target, on: resolvedBackground,
                                          towards: isDark ? .white : .black)
        }
    }
}

/// The contrast maths behind `readable` (WCAG 2), for tests and custom checks.
public enum ReadableColor {
    /// Body text: 4.5:1.
    public static let textTarget: CGFloat = 4.5
    /// Large text, symbols and meaningful UI: 3:1.
    public static let symbolTarget: CGFloat = 3
    /// `.textGreen` / `.textOrange` / `.textRed` aim a little higher than 4.5:1 against the
    /// text background, so they still pass on the slightly darker greys of grouped forms,
    /// sidebars and selected-but-inactive rows.
    public static let statusTarget: CGFloat = 5

    /// WCAG relative luminance of a colour (converted to sRGB; alpha ignored).
    public static func luminance(_ color: NSColor) -> CGFloat {
        guard let c = color.usingColorSpace(.sRGB) else { return 0 }
        func channel(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent) + 0.0722 * channel(c.blueComponent)
    }

    /// WCAG contrast ratio (1...21) of two opaque colours.
    public static func ratio(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// `color` composited over `background` (resolves translucent system colours such as
    /// `secondaryLabelColor` to what's actually drawn).
    public static func flattened(_ color: NSColor, over background: NSColor) -> NSColor {
        guard let c = color.usingColorSpace(.sRGB), let bg = background.usingColorSpace(.sRGB) else { return color }
        let a = c.alphaComponent
        return NSColor(srgbRed: c.redComponent * a + bg.redComponent * (1 - a),
                       green: c.greenComponent * a + bg.greenComponent * (1 - a),
                       blue: c.blueComponent * a + bg.blueComponent * (1 - a), alpha: 1)
    }

    /// The least of `towards` mixed into `color` (in 2% steps) that reaches `target` on
    /// `background`. Pass resolved (sRGB) colours.
    public static func adjusted(_ color: NSColor, toReach target: CGFloat, on background: NSColor, towards: NSColor) -> NSColor {
        let opaque = flattened(color, over: background)
        var fraction: CGFloat = 0
        var candidate = opaque
        while ratio(candidate, background) < target, fraction < 1 {
            fraction += 0.02
            candidate = opaque.blended(withFraction: fraction, of: towards) ?? opaque
        }
        return candidate
    }
}
