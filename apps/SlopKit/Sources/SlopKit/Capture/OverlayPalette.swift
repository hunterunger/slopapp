import AppKit

/// Colours for drawing over arbitrary screen content (the capture overlay, magnifier, size
/// badges, measuring guides). They don't follow light and dark mode on purpose: an overlay sits
/// on whatever's on screen, so it always uses the dark appearance's system colours (a dark
/// badge with light text reads over both a white page and a dark photo). Semantic colours
/// resolved once, never pure black or white (design system §4, Golden Gate).
public enum OverlayPalette {
    /// The dark appearance's window background (about #1E1E1E), the base of every dark shape.
    public static var ink: NSColor { resolvedDark(.windowBackgroundColor) }
    /// The dark appearance's label colour (white at about 85%), for outlines, rings and text.
    public static var paper: NSColor { resolvedDark(.labelColor) }

    /// Dims everything outside a selection.
    public static var scrim: CGColor { ink.withAlphaComponent(0.4).cgColor }
    /// Badge and label backgrounds.
    public static var badgeFill: CGColor { ink.withAlphaComponent(0.8).cgColor }
    /// Text on a badge.
    public static var badgeText: CGColor { paper.cgColor }
    /// Selection outlines, the magnifier's ring and pixel marker.
    public static var ring: CGColor { paper.cgColor }
    /// The shadow that keeps a ring visible over light content.
    public static var ringShadow: CGColor { ink.cgColor }

    private static func resolvedDark(_ color: NSColor) -> NSColor { resolved(color, in: .darkAqua) }

    private static func resolved(_ color: NSColor, in name: NSAppearance.Name) -> NSColor {
        var result = color
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            result = color.usingColorSpace(.sRGB) ?? color
        }
        return result
    }
}
