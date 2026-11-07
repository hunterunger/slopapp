import SwiftUI

/// Corner radii from docs/design-system.md §4. Use these instead of literals, and
/// `nested(in:padding:)` for anything inside a rounded container.
public enum Radius {
    /// Badges, color swatches, key caps, tiny chips.
    public static let xs: CGFloat = 4
    /// Small controls you draw yourself: tags, segmented pills, thumbnails under 48 pt.
    public static let s: CGFloat = 6
    /// Rows, list selections, text fields you draw yourself, small cards.
    public static let m: CGFloat = 8
    /// Cards, tiles, drop zones, popover content blocks.
    public static let l: CGFloat = 12
    /// Large panels and banners.
    public static let xl: CGFloat = 16
    /// Hero banners and full-width feature cards.
    public static let xxl: CGFloat = 22

    /// macOS 14 and 15 round window corners at 10 pt. macOS 26+ uses larger, variable radii:
    /// read them with `windowConcentric` rather than hardcoding a number.
    public static let legacyWindow: CGFloat = 10

    /// The radius for a shape inset `padding` points inside a container of radius `outer`,
    /// so the two curves stay parallel (concentric). Never below `minimum`.
    public static func nested(in outer: CGFloat, padding: CGFloat, minimum: CGFloat = 2) -> CGFloat {
        max(outer - padding, minimum)
    }

    /// The corner of an app-icon-like tile (a rounded square), proportional to its side.
    public static func iconTile(side: CGFloat) -> CGFloat { side * 0.2237 }
}

public extension View {
    /// Backs and clips this view with a rounded shape whose corners follow the window's,
    /// for a panel inset `inset` points from the window's edges. On macOS 26+ SwiftUI reads
    /// the window's real radius (`ConcentricRectangle`); before that it's the 10 pt window
    /// radius minus `inset`. `hairline` draws a one-device-pixel border in that colour.
    func windowConcentric<S: ShapeStyle>(
        fill: S,
        inset: CGFloat,
        minimum: CGFloat = Radius.xs,
        hairline: Color? = nil
    ) -> some View {
        modifier(WindowConcentric(fill: fill, inset: inset, minimum: minimum, hairline: hairline))
    }
}

private struct WindowConcentric<S: ShapeStyle>: ViewModifier {
    let fill: S
    let inset: CGFloat
    let minimum: CGFloat
    let hairline: Color?
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            apply(ConcentricRectangle(corners: .concentric(minimum: .fixed(minimum)), isUniform: true), to: content)
        } else {
            apply(
                RoundedRectangle(cornerRadius: Radius.nested(in: Radius.legacyWindow, padding: inset, minimum: minimum),
                                 style: .continuous),
                to: content
            )
        }
    }

    private func apply<Sh: Shape>(_ shape: Sh, to content: Content) -> some View {
        content
            .background(fill, in: shape)
            .clipShape(shape)
            .overlay {
                // A stroke two pixels wide centred on the edge, clipped to the inside: exactly
                // one device pixel. (A 0.5 pt centred stroke straddles two pixels and reads as
                // a blurry grey line.) An overlay, so it never affects layout.
                if let hairline { shape.stroke(hairline, lineWidth: 2 / max(displayScale, 1)).clipShape(shape).allowsHitTesting(false) }
            }
    }
}
