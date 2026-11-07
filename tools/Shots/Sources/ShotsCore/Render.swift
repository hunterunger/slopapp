import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Drawing for the composed shots and the capture backdrop. Every function takes a context
/// whose user space is top-left origin, y down, in pixels (`Render.canvas` makes one).
public enum Render {
    public static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// An RGBA canvas flipped so (0, 0) is the top-left pixel.
    public static func canvas(_ size: CGSize) -> CGContext? {
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: sRGB,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        flip(context, height: size.height)
        context.interpolationQuality = .high
        return context
    }

    public static func flip(_ context: CGContext, height: CGFloat) {
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
    }

    /// Draws `image` upright into `rect` of a flipped context.
    public static func draw(_ image: CGImage, in rect: CGRect, of context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    // MARK: Backdrop

    /// The soft category-colour backdrop: a vertical wash, a light from above and a pool of
    /// the flavour low on the trailing side. Proportional, so the capture backdrop on a big
    /// screen and the composed canvas look the same.
    public static func backdrop(_ palette: BackdropPalette, in context: CGContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        context.saveGState()
        let wash = CGGradient(colorsSpace: sRGB, colors: [palette.top.cgColor(), palette.bottom.cgColor()] as CFArray,
                              locations: [0, 1])!
        context.clip(to: rect)
        context.drawLinearGradient(wash, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
        radial(context, colour: palette.glow, alpha: palette.glowAlpha,
               centre: CGPoint(x: size.width * 0.38, y: -size.height * 0.18), radius: max(size.width, size.height) * 0.75)
        radial(context, colour: palette.accent, alpha: palette.accentAlpha,
               centre: CGPoint(x: size.width * 0.92, y: size.height * 1.08), radius: max(size.width, size.height) * 0.6)
        context.restoreGState()
    }

    private static func radial(_ context: CGContext, colour: RGB, alpha: Double, centre: CGPoint, radius: CGFloat) {
        // Eased falloff: no visible ring where it ends.
        let stops: [Double] = [0, 0.25, 0.5, 0.75, 1]
        let colours = stops.map { t in colour.cgColor(alpha: alpha * pow(1 - t, 2)) }
        let gradient = CGGradient(colorsSpace: sRGB, colors: colours as CFArray, locations: stops.map { CGFloat($0) })!
        context.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: radius, options: [])
    }

    // MARK: Windows

    public struct Shadow: Sendable {
        public var blur: CGFloat
        public var offset: CGFloat
        public var alpha: Double
    }

    /// A rendered window shadow: a wide soft one and a tight contact one, in points. The same
    /// for every shot, so the set looks like one family (real shadows differ between windows,
    /// panels, and active and inactive states).
    public static func shadows(for kind: ReadyFile.Window.Kind, dark: Bool) -> [Shadow] {
        switch kind {
        case .window, .statusItem:
            dark ? [Shadow(blur: 64, offset: 24, alpha: 0.55), Shadow(blur: 6, offset: 1, alpha: 0.45)]
                : [Shadow(blur: 64, offset: 24, alpha: 0.26), Shadow(blur: 6, offset: 1, alpha: 0.16)]
        case .panel:
            dark ? [Shadow(blur: 40, offset: 14, alpha: 0.5), Shadow(blur: 4, offset: 1, alpha: 0.4)]
                : [Shadow(blur: 40, offset: 14, alpha: 0.22), Shadow(blur: 4, offset: 1, alpha: 0.14)]
        }
    }

    /// Draws a captured window with its shadow. `pointScale` turns the shadow's points into pixels.
    public static func window(_ image: CGImage, in rect: CGRect, kind: ReadyFile.Window.Kind, palette: BackdropPalette,
                              pointScale: CGFloat, context: CGContext) {
        let shadowColour = palette.bottom.mixed(with: .black, by: palette.isDark ? 0.85 : 0.72)
        // Each shadow is cast by a copy drawn far off the canvas, so only the shadow lands
        // (two stacked copies would darken the window's antialiased corners).
        let away: CGFloat = 100_000
        for shadow in shadows(for: kind, dark: palette.isDark) {
            context.saveGState()
            // Shadow offsets are in device space (y up); the context is flipped, so "down" is -y.
            context.setShadow(offset: CGSize(width: away, height: -shadow.offset * pointScale),
                              blur: shadow.blur * pointScale, color: shadowColour.cgColor(alpha: shadow.alpha))
            draw(image, in: rect.offsetBy(dx: -away, dy: 0), of: context)
            context.restoreGState()
        }
        draw(image, in: rect, of: context)
    }

    // MARK: Menu bar

    /// A frosted menu bar strip across the top, with the app's icon (tinted for the strip, from
    /// the captured icon's shape) and, when its panel hangs from it, the pressed capsule.
    public static func menuBar(height: CGFloat, icon: CGImage?, iconRect: CGRect?, pressed: Bool,
                               palette: BackdropPalette, pointScale: CGFloat, size: CGSize, context: CGContext) {
        guard height > 0 else { return }
        let strip = CGRect(x: 0, y: 0, width: size.width, height: height)
        let (fill, fillAlpha) = palette.stripFill
        context.setFillColor(fill.cgColor(alpha: fillAlpha))
        context.fill(strip)
        let (line, lineAlpha) = palette.stripHairline
        context.setFillColor(line.cgColor(alpha: lineAlpha))
        context.fill(CGRect(x: 0, y: height - 1, width: size.width, height: 1))

        guard let icon, let iconRect else { return }
        if pressed {
            let (colour, alpha) = palette.itemHighlight
            let capsule = iconRect.insetBy(dx: -4 * pointScale, dy: 0)
                .insetBy(dx: 0, dy: max(0, (iconRect.height - (height - 6 * pointScale)) / 2))
            let path = CGPath(roundedRect: capsule, cornerWidth: 6 * pointScale, cornerHeight: 6 * pointScale, transform: nil)
            context.addPath(path)
            context.setFillColor(colour.cgColor(alpha: alpha))
            context.fillPath()
        }
        // Keep the icon's shape, paint it in the strip's ink.
        let (ink, inkAlpha) = palette.menuBarInk
        context.saveGState()
        context.beginTransparencyLayer(in: iconRect, auxiliaryInfo: nil)
        draw(icon, in: iconRect, of: context)
        context.setBlendMode(.sourceIn)
        context.setFillColor(ink.cgColor(alpha: inkAlpha))
        context.fill(iconRect)
        context.endTransparencyLayer()
        context.restoreGState()
    }

    // MARK: Callout

    /// A magnified crop of a detail: a ring around the detail, and the crop in a rounded card
    /// with the window shadow.
    public static func callout(_ placement: Composition.CalloutPlacement, from window: CGImage, palette: BackdropPalette,
                               pointScale: CGFloat, context: CGContext) {
        guard let crop = window.cropping(to: placement.crop.integral) else { return }
        let ringColour = palette.isDark ? RGB.white.cgColor(alpha: 0.32) : RGB.white.cgColor(alpha: 0.95)
        let shadowColour = palette.bottom.mixed(with: .black, by: palette.isDark ? 0.85 : 0.72)

        // Ring around the detail in the window.
        let sourceRadius = 6 * pointScale
        let source = placement.source.insetBy(dx: -2 * pointScale, dy: -2 * pointScale)
        context.saveGState()
        context.setShadow(offset: .zero, blur: 6 * pointScale, color: shadowColour.cgColor(alpha: 0.35))
        context.addPath(CGPath(roundedRect: source, cornerWidth: sourceRadius, cornerHeight: sourceRadius, transform: nil))
        context.setStrokeColor(ringColour)
        context.setLineWidth(2 * pointScale)
        context.strokePath()
        context.restoreGState()

        // The magnified card.
        let radius = 16 * pointScale
        let card = CGPath(roundedRect: placement.target, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -18 * pointScale), blur: 48 * pointScale,
                          color: shadowColour.cgColor(alpha: palette.isDark ? 0.6 : 0.3))
        context.addPath(card)
        context.setFillColor(palette.top.cgColor())
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(card)
        context.clip()
        context.interpolationQuality = .high
        draw(crop, in: placement.target, of: context)
        context.restoreGState()

        context.saveGState()
        context.addPath(card)
        context.setStrokeColor(ringColour)
        context.setLineWidth(2 * pointScale)
        context.strokePath()
        context.restoreGState()
    }

    // MARK: Whole shot

    /// Draws a full shot. `captures` maps window ids to their captured images.
    public static func compose(_ composition: Composition, captures: [UInt32: CGImage], palette: BackdropPalette) -> CGImage? {
        guard let context = canvas(composition.size) else { return nil }
        backdrop(palette, in: context, size: composition.size)
        menuBar(height: composition.stripHeight,
                icon: composition.statusItem.flatMap { captures[$0.window.id] },
                iconRect: composition.statusItem?.rect, pressed: composition.statusItemPressed,
                palette: palette, pointScale: composition.pointScale, size: composition.size, context: context)
        for placed in composition.windows {
            guard let image = captures[placed.window.id] else { continue }
            window(image, in: placed.rect, kind: placed.window.kind, palette: palette,
                   pointScale: composition.pointScale, context: context)
        }
        if let callout = composition.callout, let first = composition.windows.first, let image = captures[first.window.id] {
            Render.callout(callout, from: image, palette: palette, pointScale: composition.pointScale, context: context)
        }
        return context.makeImage()
    }

    // MARK: Files

    public static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    public static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ShowcaseFile.Invalid(description: "can't write \(url.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ShowcaseFile.Invalid(description: "can't write \(url.path)") }
    }
}
