import AppKit
import ClipsCore

/// A colour per source app, taken from its icon, so cards from the same app are easy to
/// pick out. Clips fills the card header with it (see HeaderColor for the contrast), and
/// a neutral tint when there's no app. Computed once per app from a 16×16 render.
@MainActor
enum AppTint {
    private static var cache: [String: NSColor] = [:]

    static func color(for bundleID: String?) -> NSColor? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let icon = AppIcons.icon(for: bundleID) else { return nil }
        let color = dominantColor(of: icon).map(vivid) ?? .systemGray
        cache[bundleID] = color
        return color
    }

    /// A stable system colour for a link's site, for the monogram tile.
    static func color(forHost host: String) -> NSColor {
        let palette: [NSColor] = [.systemBlue, .systemPurple, .systemPink, .systemRed, .systemOrange,
                                  .systemYellow, .systemGreen, .systemMint, .systemTeal, .systemCyan, .systemIndigo]
        return palette[Int(ClipText.stableHash(host) % UInt64(palette.count))]
    }

    /// An icon's average colour is paler than the colour people know it by (gradients,
    /// highlights, white glyphs): keep the hue, lift the saturation. `HeaderColor` then darkens
    /// it only as far as white type needs.
    static func vivid(_ color: NSColor) -> NSColor {
        guard let srgb = color.usingColorSpace(.sRGB) else { return color }
        return NSColor(hue: srgb.hueComponent, saturation: max(srgb.saturationComponent, 0.7),
                       brightness: max(srgb.brightnessComponent, 0.75), alpha: 1)
    }

    /// The most saturated common hue in the icon (ignores near-white, near-black and
    /// transparent pixels), or nil for a grey icon.
    static func dominantColor(of image: NSImage) -> NSColor? {
        let side = 16
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        // 12 hue buckets, weighted by saturation.
        var weights = [Double](repeating: 0, count: 12)
        var sums = [(r: Double, g: Double, b: Double)](repeating: (0, 0, 0), count: 12)
        for index in 0..<(side * side) {
            let alpha = Double(pixels[index * 4 + 3]) / 255
            guard alpha > 0.5 else { continue }
            let r = Double(pixels[index * 4]) / 255 / alpha
            let g = Double(pixels[index * 4 + 1]) / 255 / alpha
            let b = Double(pixels[index * 4 + 2]) / 255 / alpha
            let color = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
            let saturation = color.saturationComponent
            let brightness = color.brightnessComponent
            guard saturation > 0.25, brightness > 0.2 else { continue }
            let bucket = min(11, Int(color.hueComponent * 12))
            let weight = saturation * brightness
            weights[bucket] += weight
            sums[bucket].r += r * weight
            sums[bucket].g += g * weight
            sums[bucket].b += b * weight
        }
        guard let best = weights.indices.max(by: { weights[$0] < weights[$1] }), weights[best] > 1.5 else { return nil }
        let total = weights[best]
        return NSColor(srgbRed: sums[best].r / total, green: sums[best].g / total, blue: sums[best].b / total, alpha: 1)
    }
}
