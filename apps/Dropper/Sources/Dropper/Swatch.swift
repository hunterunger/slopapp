import AppKit
import DropperCore
import SlopKit
import SwiftUI

extension ColorValue {
    /// The color for drawing. Extended sRGB, so vivid P3 picks draw as picked on P3 screens.
    var nsColor: NSColor {
        NSColor(colorSpace: .extendedSRGB,
                components: [CGFloat(sRGB.red), CGFloat(sRGB.green), CGFloat(sRGB.blue), 1], count: 4)
    }

    var swiftUIColor: Color { Color(nsColor: nsColor) }
}

/// Small rounded swatch images for menu items. Drawn with a hairline border so white and
/// black swatches stay visible in light and dark menus.
@MainActor
enum SwatchImage {
    private static var cache: [[Int]: NSImage] = [:]

    static func image(for color: ColorValue, size: CGFloat = 14) -> NSImage {
        let key = color.identityKey + [Int(size)]
        if let cached = cache[key] { return cached }
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let image = NSImage(size: rect.size, flipped: false) { _ in
            // Inset half a point so the 1 pt stroke lands inside the image; the radius shrinks
            // by the same half point to stay concentric with the image's own corners.
            let radius = Radius.xs - 0.5
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
            color.nsColor.setFill()
            path.fill()
            NSColor.tertiaryLabelColor.setStroke()
            path.lineWidth = 1
            path.stroke()
            return true
        }
        image.isTemplate = false
        if cache.count > 300 { cache.removeAll() }
        cache[key] = image
        return image
    }
}

/// A swatch for SwiftUI views, with the same hairline border.
struct SwatchView: View {
    let color: ColorValue
    var size: CGFloat = 28
    /// Swatches use `Radius.xs`, or the radius nested in their container.
    var cornerRadius: CGFloat = Radius.xs

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(color.swiftUIColor)
            .modifier(SwatchEdge(shape: shape))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
