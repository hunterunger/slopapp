import AppKit
import SwiftUI

/// A one-device-pixel separator in `separatorColor` (design system §4: hairlines are 0.5 pt on
/// Retina). Use it instead of SwiftUI's `Divider`, which draws a full point on macOS.
/// Horizontal by default; `.vertical` for a rule between items in a row.
///
/// It always takes up exactly 1 pt (whole points, whatever the display scale) and draws the
/// line along the top (or leading) edge of that point: 1 px on Retina, 1 pt at 1x. The layout
/// never depends on `displayScale`, so it's safe in windows that size themselves to their
/// content (`MenuBarExtra(.window)`, `NSHostingController` with `.preferredContentSize`), where
/// a line that changed its layout height with the scale made AppKit's constraint pass throw.
public struct Hairline: View {
    public var axis: Axis

    public init(axis: Axis = .horizontal) { self.axis = axis }

    /// The space a hairline takes in layout, in points. Fixed on purpose.
    public static let layoutThickness: CGFloat = 1

    public var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let pixel = 1 / max(context.environment.displayScale, 1)
            let line = axis == .horizontal
                ? CGRect(x: 0, y: 0, width: size.width, height: pixel)
                : CGRect(x: 0, y: 0, width: pixel, height: size.height)
            context.fill(Path(line), with: .color(Color(nsColor: .separatorColor)))
        }
        .frame(width: axis == .vertical ? Self.layoutThickness : nil,
               height: axis == .horizontal ? Self.layoutThickness : nil)
        .frame(maxWidth: axis == .horizontal ? .infinity : nil, maxHeight: axis == .vertical ? .infinity : nil)
        .accessibilityHidden(true)
    }
}

public extension View {
    /// A one-device-pixel `separatorColor` border inside `shape`'s edge (no blurry
    /// half-point stroke straddling two pixels).
    func hairlineBorder<S: Shape>(_ shape: S, color: Color = Color(nsColor: .separatorColor)) -> some View {
        modifier(HairlineBorder(shape: shape, color: color))
    }
}

private struct HairlineBorder<S: Shape>: ViewModifier {
    let shape: S
    let color: Color
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        // An overlay: it's drawn in the content's frame and never feeds back into layout, so
        // reading the display scale here is safe in self-sizing windows.
        content.overlay {
            // A stroke twice the pixel width, centred on the edge and clipped to the inside,
            // leaves exactly one device pixel.
            shape.stroke(color, lineWidth: 2 / max(displayScale, 1))
                .clipShape(shape)
                .allowsHitTesting(false)
        }
    }
}
