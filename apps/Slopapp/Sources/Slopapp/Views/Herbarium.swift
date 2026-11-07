import AppKit
import SlopKit
import SwiftUI

// The launcher's Nordic herbarium frame (brand/BRAND.md, brand.json `nordic`): matte, muted
// natural colour on warm birch, with botanical prints from Köhler's Medizinal-Pflanzen clipped
// into crisp panels. It's the frame only: the sidebar shell and its selection, the category
// colours, the featured banners and the update capsule. Cards, app pages and text keep semantic
// colours, and controls keep the user's accent.
//
// Every colour comes from `Brand.Nordic`; the dark versions are derived (the tile sinks toward
// night, as the icons' dark mode does) and anything shown as text or a symbol is pushed to a
// measured contrast with SlopKit's `readable`, so no hex literals live here.

enum Herbarium {
    static func color(_ hex: UInt32) -> NSColor {
        let c = rgbComponents(hex)
        return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1) // lint:allow brand palette (Brand.Nordic hex)
    }

    static let birch = color(Brand.Nordic.Hex.birch)
    static let oat = color(Brand.Nordic.Hex.oat)
    static let charcoal = color(Brand.Nordic.Hex.charcoal)
    static let night = color(Brand.Nordic.Hex.night)
    static let pine = color(Brand.Nordic.Hex.pine)
    static let sage = color(Brand.Nordic.Hex.sage)
    static let white = NSColor(white: 1, alpha: 1)
    static let black = NSColor(white: 0, alpha: 1)

    /// The content panel: birch lifted toward white (the website's card), or night deepened
    /// a little (the website's dark page), so the shell around it reads as the frame.
    static let paper = NSColor.dynamic(light: birch.mixed(white, 0.6), dark: night.mixed(black, 0.18))

    /// Washed over the sidebar's system material: warm birch, or night.
    static let shellWash = NSColor.dynamic(light: birch, dark: night)

    /// Pine: the selection, the update capsule, "Up to Date". In dark mode pine is too deep to
    /// see on night, so it becomes sage lifted toward birch (the website's dark primary).
    static let action = NSColor.dynamic(light: pine, dark: sage.mixed(birch, 0.3))
    /// Text on `action`: 7:1 or better both ways.
    static let onAction = NSColor.dynamic(light: birch.mixed(white, 0.6), dark: night.mixed(black, 0.18))

    /// Text on the banners' cards (which are `paper`): charcoal, or birch toward oat.
    static let text = NSColor.dynamic(light: charcoal, dark: birch.mixed(oat, 0.5))
    /// Supporting text on the cards, measured to 4.5:1 on `paper` (the system's secondary
    /// label is lighter than that in light mode on macOS 27).
    static let muted = NSColor.readable(NSColor.dynamic(light: charcoal.mixed(birch, 0.5), dark: birch.mixed(night, 0.42)),
                                        on: paper, target: 4.6)
}

/// One Nordic colour, as a category or a print panel.
struct Tone: Hashable, Sendable {
    let hex: UInt32

    var base: NSColor { Herbarium.color(hex) }

    /// A category's colour: its Nordic tone, a little lighter in dark mode so it holds on night.
    static func category(_ name: String) -> Tone { Tone(hex: Brand.Nordic.category(name)) }

    /// A small fill next to a label (the category dot): deepened just enough for 3:1 on the
    /// birch shell (ochre and sage are about 2:1 as they are), a little lighter on night.
    var dot: Color {
        Color(nsColor: .readable(.dynamic(light: base, dark: base.mixed(Herbarium.birch, 0.12)),
                                 on: Herbarium.shellWash, target: 3.2))
    }

    /// The tone as text on the content panel: same hue, deepened (light) or lifted (dark) only
    /// as far as 4.5:1 needs.
    var ink: Color { Color(nsColor: .readable(base, on: Herbarium.paper)) }

    /// A print panel's ground: the tone itself, or 66% toward night in dark mode (the icons'
    /// rule, and the website's).
    var panel: NSColor { .dynamic(light: base, dark: base.mixed(Herbarium.night, 0.66)) }

    /// The print on that ground: 30% toward charcoal, or 16% toward white in dark mode.
    var print: NSColor {
        .dynamic(light: base.mixed(Herbarium.charcoal, 0.3),
                 dark: base.mixed(Herbarium.night, 0.66).mixed(Herbarium.white, 0.16))
    }
}

extension NSColor {
    /// A colour that resolves per appearance.
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    /// `self` mixed with `other` in sRGB (0 = self, 1 = other).
    func mixed(_ other: NSColor, _ fraction: CGFloat) -> NSColor {
        let a = usingColorSpace(.sRGB) ?? self
        let b = other.usingColorSpace(.sRGB) ?? other
        return a.blended(withFraction: fraction, of: b) ?? a
    }
}

// MARK: - Prints

/// A botanical plate the launcher ships (the website's prints, `web/public/prints/`: white on
/// transparent, used as a mask), paired with the panel colour the website prints it on.
struct Plate: Hashable, Sendable {
    /// The file in Resources/Prints, without `.webp`.
    let name: String
    let tone: Tone
    /// Which part of the plate shows when it covers a wide panel (like CSS `mask-position`).
    let anchor: UnitPoint

    /// The featured banners' plates, in turn: hops, peppermint, fern, coffee, oak, mallow.
    static let banners: [Plate] = [
        Plate(name: "switchboard", tone: Tone(hex: Brand.Nordic.Hex.sage), anchor: UnitPoint(x: 0.5, y: 0.55)),
        Plate(name: "clips", tone: Tone(hex: Brand.Nordic.Hex.ochre), anchor: UnitPoint(x: 0.5, y: 0.45)),
        Plate(name: "tidy", tone: Tone(hex: Brand.Nordic.Hex.fjord), anchor: UnitPoint(x: 0.5, y: 0.5)),
        Plate(name: "awake", tone: Tone(hex: Brand.Nordic.Hex.rosewood), anchor: UnitPoint(x: 0.5, y: 0.35)),
        Plate(name: "commit", tone: Tone(hex: Brand.Nordic.Hex.heather), anchor: UnitPoint(x: 0.5, y: 0.5)),
        Plate(name: "snapper", tone: Tone(hex: Brand.Nordic.Hex.clay), anchor: UnitPoint(x: 0.5, y: 0.4)),
    ]

    static func forBanner(_ index: Int) -> Plate { banners[index % banners.count] }
}

/// Loads the shipped plates once each.
@MainActor
enum PlateImages {
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard let url = PrintResources.url(name), let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }
}

/// Where the SwiftPM resource bundle is: next to the app's other resources in a bundled .app
/// (scripts/bundle.sh copies it to Contents/Resources), beside the binary in a debug build.
enum PrintResources {
    static let bundleName = "Slopapp_Slopapp.bundle"

    static func url(_ name: String) -> URL? {
        var directories: [URL] = []
        if let resources = Bundle.main.resourceURL { directories.append(resources.appendingPathComponent(bundleName)) }
        if let executable = Bundle.main.executableURL?.deletingLastPathComponent() {
            directories.append(executable.appendingPathComponent(bundleName))
        }
        for directory in directories {
            for candidate in [directory.appendingPathComponent("Prints/\(name).webp"),
                              directory.appendingPathComponent("Contents/Resources/Prints/\(name).webp")]
            where FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

/// A shape on a print that keeps a clear (unprinted) margin around it.
struct ClearZone: Equatable {
    var rect: CGRect
    var radius: CGFloat
}

/// A crisp panel with one botanical print in it: the panel's tone, the plate printed 30% darker
/// over it, and unprinted clear zones around whatever sits on the print. Nothing else in the
/// launcher is textured (brand/BRAND.md: prints only inside panels). Drawn once per size and
/// appearance into one bitmap (`PrintRenderer`), not as stacked masks.
struct PrintPanel<S: Shape>: View {
    let plate: Plate
    let shape: S
    var clearZones: [ClearZone] = []
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geometry in
            if let image = PrintRenderer.image(plate: plate, size: geometry.size, scale: displayScale,
                                               dark: colorScheme == .dark, clearZones: clearZones) {
                Image(decorative: image, scale: displayScale)
                    .resizable()
            } else {
                Color(nsColor: plate.tone.panel)
            }
        }
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

/// Draws a print panel into a bitmap: the ground, the plate covering it (scaled to fill, placed
/// by its anchor, like CSS `mask-size: cover`) in the print tone, then the clear zones in the
/// ground again, on crisp edges. Keeps the last few, so scrolling and paging don't redraw.
@MainActor
enum PrintRenderer {
    private struct Key: Hashable {
        let plate: String
        let width: Int, height: Int
        let scale: CGFloat
        let dark: Bool
        let zones: [CGRect]
    }

    private static var cache: [Key: CGImage] = [:]
    private static var order: [Key] = []
    private static let keep = 8

    static func image(plate: Plate, size: CGSize, scale: CGFloat, dark: Bool, clearZones: [ClearZone]) -> CGImage? {
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        guard width > 0, height > 0 else { return nil }
        let key = Key(plate: plate.name, width: width, height: height, scale: scale, dark: dark, zones: clearZones.map(\.rect))
        if let cached = cache[key] { return cached }
        guard let mask = PlateImages.image(plate.name)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
        var ground = CGColor(gray: 0.5, alpha: 1), ink = CGColor(gray: 0.4, alpha: 1)
        appearance.performAsCurrentDrawingAppearance {
            ground = plate.tone.panel.usingColorSpace(.sRGB)?.cgColor ?? ground
            ink = plate.tone.print.usingColorSpace(.sRGB)?.cgColor ?? ink
        }
        // Top-left origin, in points.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.interpolationQuality = .high
        let bounds = CGRect(origin: .zero, size: size)
        context.setFillColor(ground)
        context.fill(bounds)

        // The plate in the print tone: draw its alpha, then paint the tone into it.
        let side = max(size.width, size.height)
        let plateRect = CGRect(x: (size.width - side) * plate.anchor.x, y: (size.height - side) * plate.anchor.y,
                               width: side, height: side)
        context.saveGState()
        context.beginTransparencyLayer(in: bounds, auxiliaryInfo: nil)
        context.saveGState()
        // CGContext draws images bottom-up; flip just the plate back.
        context.translateBy(x: 0, y: plateRect.maxY + plateRect.minY)
        context.scaleBy(x: 1, y: -1)
        context.draw(mask, in: plateRect)
        context.restoreGState()
        context.setBlendMode(.sourceIn)
        context.setFillColor(ink)
        context.fill(bounds)
        context.endTransparencyLayer()
        context.restoreGState()

        context.setFillColor(ground)
        for zone in clearZones {
            let radius = min(zone.radius, zone.rect.width / 2, zone.rect.height / 2)
            context.addPath(CGPath(roundedRect: zone.rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
        }

        guard let image = context.makeImage() else { return nil }
        cache[key] = image
        order.append(key)
        if order.count > keep { cache[order.removeFirst()] = nil }
        return image
    }
}

// MARK: - The shell

/// The window's shell: the system's sidebar material (so the desktop shows through and the
/// clear / tinted glass setting still applies) washed with warm birch, or night in dark mode.
/// The paper content panel sits on it like a sheet on a mount. Greyer when the window isn't key.
struct NordicShell: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        let dark = colorScheme == .dark
        let active = activeState != .inactive
        ZStack {
            SidebarBackground()
            Color(nsColor: Herbarium.shellWash)
                .opacity((dark ? 0.42 : 0.62) * (active ? 1 : 0.55))
        }
        .animation(.easeOut(duration: 0.2), value: active)
    }
}

/// A category's colour, as a small flat dot in front of its name. Grey behind other windows.
struct CategoryDot: View {
    let tone: Tone
    var size: CGFloat = 10
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        Circle()
            .fill(activeState == .inactive ? AnyShapeStyle(.tertiary) : AnyShapeStyle(tone.dot))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The waiting-updates capsule (the sidebar count, the header status): pine with paper text in
/// the key window, grey behind it.
struct ActionCapsule: View {
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        Capsule().fill(activeState == .inactive ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color(nsColor: Herbarium.action)))
    }
}

extension ShapeStyle where Self == AnyShapeStyle {
    /// Text on `ActionCapsule`.
    static func onActionCapsule(active: Bool) -> AnyShapeStyle {
        active ? AnyShapeStyle(Color(nsColor: Herbarium.onAction)) : AnyShapeStyle(.primary)
    }
}
