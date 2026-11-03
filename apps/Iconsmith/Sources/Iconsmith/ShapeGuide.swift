import IconsmithCore
import SwiftUI

/// The outline a shape clips to, drawn faintly behind a transparent preview so the shape
/// is visible even when the icon has no background.
struct ShapeGuide: Shape {
    let shape: IconShape

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        guard let clip = IconGeometry.clipPath(for: shape, pixels: side) else { return Path() }
        // The shapes are symmetric top to bottom, so Core Graphics' y-up path fits as is.
        var transform = CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2)
        return Path(clip.copy(using: &transform) ?? clip)
    }

    /// Whether to draw the guide: the shape has an outline but nothing fills it.
    @MainActor static func isVisible(for shape: IconShape, model: AppModel) -> Bool {
        guard [.macOSApp, .square, .circle].contains(shape), let renderer = model.renderer else { return false }
        var style = model.style
        style.shape = shape
        return renderer.background(for: style) == nil
    }
}

extension View {
    /// Draws the shape guide behind this view when the shape would otherwise be invisible.
    /// `outlineAlways`: also draw a faint solid hairline when the shape is filled, so a white
    /// tile still reads as a tile on a light background (thumbnails).
    @MainActor func shapeGuide(_ shape: IconShape, model: AppModel, lineWidth: CGFloat = 1, outlineAlways: Bool = false) -> some View {
        overlay {
            if outlineAlways, [.macOSApp, .square, .circle].contains(shape), !ShapeGuide.isVisible(for: shape, model: model) {
                ShapeGuide(shape: shape)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                    .accessibilityHidden(true)
            }
        }
        .background {
            if ShapeGuide.isVisible(for: shape, model: model) {
                ShapeGuide(shape: shape)
                    .fill(Color.primary.opacity(0.05))
                    .overlay {
                        ShapeGuide(shape: shape)
                            .stroke(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: lineWidth, dash: [4, 3]))
                    }
                    .accessibilityHidden(true)
            }
        }
    }
}
