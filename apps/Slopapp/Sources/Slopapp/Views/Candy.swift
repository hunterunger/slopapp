import AppKit
import SlopKit
import SwiftUI

// The launcher's candy-glass frame (brand.json `candy`): saturated, translucent colour over
// frosted ice, after the coloured-plastic computers of the late nineties. It's the frame and
// the accents only: the sidebar shell, selection, category flavours, the featured banners
// and the status capsule. Pages, cards and text keep semantic colours.
//
// Every colour here comes from `Brand.Candy`; readable variants are computed per appearance
// against the surface they sit on, so contrast holds in light and dark without new literals.

/// One candy colour.
enum Flavour: CaseIterable, Sendable {
    case strawberry, tangerine, lime, lagoon, blueberry, grape

    /// The launcher's own colour (the icon's top): selection, sidebar symbols, status.
    static let primary: Flavour = .strawberry

    var base: Color {
        switch self {
        case .strawberry: Brand.Candy.strawberry
        case .tangerine: Brand.Candy.tangerine
        case .lime: Brand.Candy.lime
        case .lagoon: Brand.Candy.lagoon
        case .blueberry: Brand.Candy.blueberry
        case .grape: Brand.Candy.grape
        }
    }

    var nsBase: NSColor { NSColor(base).usingColorSpace(.sRGB) ?? NSColor(base) }

    /// The flavour as text or a symbol on the window's own surfaces (the white panel, the
    /// light sidebar; the dark ones in dark mode): darkened in light mode, lightened in
    /// dark mode, by just enough for 4.5:1.
    var ink: Color { Color(nsColor: Self.inkColor(nsBase)) }

    /// The flavour as a sidebar symbol. The candy shell is tinted with this same hue, so the
    /// plain `ink` measured 1.8–3.2:1 there; this one is pushed further (deeper in light mode,
    /// paler in dark) until it clears 3:1 on the selected pill, the shell's strongest tint
    /// (samples measured on screenshots: sRGB 232,160,166 light; 140,78,108 dark).
    var sidebarInk: Color {
        Color(nsColor: Self.readable(nsBase, minimum: 3.3,
                                     light: NSColor(srgbRed: 232 / 255, green: 160 / 255, blue: 166 / 255, alpha: 1), // lint:allow measured sample, not a drawn colour
                                     dark: NSColor(srgbRed: 140 / 255, green: 78 / 255, blue: 108 / 255, alpha: 1))) // lint:allow measured sample, not a drawn colour
    }

    /// Light flavours carry dark text; deep ones carry white (measured, ≥ 4.5:1 on `base`).
    var carriesDarkText: Bool {
        switch self {
        case .tangerine, .lime, .lagoon: true
        // Strawberry is the hero: deepened strawberry → tangerine with white text, like the
        // website's primary button.
        case .strawberry, .blueberry, .grape: false
        }
    }

    /// The category's flavour: one per category, so rows and pages are told apart at a glance.
    static func forCategory(_ name: String) -> Flavour {
        switch name {
        // The website's mapping (web/src/app/globals.css), so a category is the same colour
        // everywhere. Hub is strawberry, the launcher's own colour.
        case "Hub": .strawberry
        case "Utilities": .blueberry
        case "Productivity": .tangerine
        case "Design": .grape
        case "Developer": .lime
        case "Media": .lagoon
        default:
            // Stable for categories added later.
            allCases[Int(name.unicodeScalars.reduce(0) { $0 &+ $1.value } % UInt32(allCases.count))]
        }
    }

    // MARK: Readable variants

    private static func inkColor(_ base: NSColor) -> NSColor {
        // The surfaces this text sits on: the panel (white / near-black).
        readable(base, minimum: 4.5, light: NSColor(white: 1, alpha: 1), dark: NSColor(white: 0.12, alpha: 1))
    }

    /// `base`, darkened (light mode) or lightened (dark mode) in 5 % steps until it measures
    /// `minimum` against that appearance's surface.
    private static func readable(_ base: NSColor, minimum: CGFloat, light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let surface = isDark ? dark : light
            let toward: NSColor = isDark ? .white : .black
            var color = base
            var fraction: CGFloat = 0
            while Contrast.ratio(color, surface) < minimum, fraction < 0.9 {
                fraction += 0.05
                color = base.blended(withFraction: fraction, of: toward) ?? base
            }
            return color
        }
    }
}

/// WCAG contrast between two opaque sRGB colours.
enum Contrast {
    static func luminance(_ color: NSColor) -> CGFloat {
        let c = color.usingColorSpace(.sRGB) ?? color
        func channel(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent) + 0.0722 * channel(c.blueComponent)
    }

    static func ratio(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

extension Color {
    /// `self` mixed with `other` (0 = self, 1 = other), in sRGB.
    func mixed(with other: Color, by fraction: CGFloat) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let b = NSColor(other).usingColorSpace(.sRGB) ?? NSColor(other)
        return Color(nsColor: a.blended(withFraction: fraction, of: b) ?? a)
    }
}

// MARK: - The shell

/// The window's candy shell: the system's sidebar material (so the desktop shows through and
/// the clear / tinted setting still applies) washed with the icon's strawberry → tangerine,
/// plus a soft plastic highlight along the top. The white content panel sits on it like the
/// frosted inner panel of a coloured case. Calmer when the window isn't key.
struct CandyShell: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        let dark = colorScheme == .dark
        let active = activeState != .inactive
        ZStack {
            SidebarBackground()
            // Light: the icon's strawberry → tangerine. Dark: strawberry → grape, a berry jewel
            // (tangerine over graphite turns brown).
            LinearGradient(colors: [Brand.Candy.strawberry, dark ? Brand.Candy.grape : Brand.Candy.tangerine],
                           startPoint: .top, endPoint: .bottom)
                .opacity((dark ? 0.24 : 0.28) * (active ? 1 : 0.45))
            // The light catching the top of the plastic.
            LinearGradient(colors: [Color.white.opacity(dark ? 0.07 : 0.30), .clear],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.35))
        }
        .animation(.easeOut(duration: 0.2), value: active)
    }
}

/// A candy-glass fill for small shapes (selection, the status capsule): the flavour as a
/// translucent tint with a highlight along its top edge and a light rim.
struct CandyGlass<S: InsettableShape>: View {
    let shape: S
    var flavour: Flavour = .primary
    /// 0…1: how much colour (the selection is a light tint; the status capsule is solid).
    var strength: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        // Solid candy is a shade deeper in dark mode (a jewel, not neon); graphite text on
        // tangerine still measures over 4.5:1 there.
        let base = dark && strength >= 1 ? flavour.base.mixed(with: .black, by: 0.15) : flavour.base
        shape
            .fill(LinearGradient(colors: [base.opacity(strength), Brand.Candy.tangerine.mixed(with: base, by: 0.5).opacity(strength)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                shape.fill(LinearGradient(colors: [Color.white.opacity(dark ? 0.16 : 0.38), .clear],
                                          startPoint: .top, endPoint: .center))
            }
            .overlay {
                // 1 pt clipped to the inside: a 0.5 pt rim.
                shape.stroke(Color.white.opacity(dark ? 0.14 : 0.45), lineWidth: 1).clipShape(shape)
            }
    }
}

/// A category's colour, as a small sweet in front of its name.
struct FlavourDot: View {
    let flavour: Flavour
    var size: CGFloat = 10
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        Circle()
            .fill(activeState == .inactive ? AnyShapeStyle(.tertiary) : AnyShapeStyle(flavour.base.gradient))
            .overlay {
                Circle().fill(LinearGradient(colors: [Color.white.opacity(0.5), .clear], startPoint: .top, endPoint: .center))
                    .padding(size * 0.12)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
