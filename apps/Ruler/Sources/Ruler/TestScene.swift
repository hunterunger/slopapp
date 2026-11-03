import AppKit
import RulerCore
import SlopKit

/// The generated test scene (`RULER_TEST_SCENE=1`): shapes at known sizes from
/// `TestSceneLayout`. While it's open, every freeze contains only this window.
@MainActor
enum TestScene {
    private(set) static var window: NSWindow?

    /// Test mode: the frozen screen contains only the scene, never anything else on screen.
    static var isActive: Bool { Diagnostics.testScene }

    static var windowNumbers: Set<CGWindowID> {
        guard let window, window.isVisible else { return [] }
        return [CGWindowID(window.windowNumber)]
    }

    static var view: TestSceneView? { window?.contentView as? TestSceneView }

    static func showIfRequested() {
        guard Diagnostics.testScene, window == nil else { return }
        let screen = NSScreen.underPointer ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = TestSceneLayout.size
        let window = NSWindow(contentRect: CGRect(x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded(),
                                                  width: size.width, height: size.height),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Ruler Test Scene"
        window.isReleasedWhenClosed = false
        window.contentView = TestSceneView(frame: CGRect(origin: .zero, size: size))
        window.orderFrontRegardless()
        self.window = window
    }

    /// A shape's frame in AppKit global points, for the self-check.
    static func globalFrame(of shape: TestSceneLayout.Shape) -> CGRect? {
        guard let window, let view else { return nil }
        return window.convertToScreen(view.convert(shape.frame, to: nil))
    }
}

/// Draws `TestSceneLayout` on a light background. Sizes are exact in points; nothing is
/// scaled, so a 200 × 120 shape is 400 × 240 pixels on Retina.
final class TestSceneView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Fixed colors on purpose: measurements must not depend on light or dark mode.
        let background = NSColor(srgbRed: 0.97, green: 0.97, blue: 0.96, alpha: 1)
        background.setFill()
        bounds.fill()
        for shape in TestSceneLayout.shapes {
            draw(shape)
            if let caption = shape.caption {
                // Clear of the shadow below the shadowed card.
                let gap: CGFloat = shape.kind == .shadowed ? 26 : 10
                (caption as NSString).draw(at: CGPoint(x: shape.frame.minX, y: shape.frame.maxY + gap),
                                           withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor(white: 0.45, alpha: 1)])
            }
        }
        ("Ruler test scene · freezes in test mode contain only this window" as NSString).draw(
            at: CGPoint(x: 40, y: bounds.height - 40),
            withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(white: 0.45, alpha: 1)])
    }

    private func draw(_ shape: TestSceneLayout.Shape) {
        let f = shape.frame
        switch shape.kind {
        case .solid:
            NSColor(srgbRed: 0.0, green: 0.45, blue: 0.9, alpha: 1).setFill()
            f.fill()
        case .outline:
            NSColor.white.setFill()
            f.fill()
            NSColor(srgbRed: 0.2, green: 0.2, blue: 0.25, alpha: 1).setFill()
            f.frame(withWidth: 1)
        case .rounded:
            NSColor(srgbRed: 0.2, green: 0.7, blue: 0.35, alpha: 1).setFill()
            NSBezierPath(roundedRect: f, xRadius: 16, yRadius: 16).fill()
        case .halfPoint:
            NSColor(srgbRed: 0.85, green: 0.3, blue: 0.2, alpha: 1).setFill()
            f.fill()
        case .gradient:
            NSGradient(starting: NSColor(srgbRed: 0.55, green: 0.2, blue: 0.85, alpha: 1),
                       ending: NSColor(srgbRed: 0.95, green: 0.6, blue: 0.2, alpha: 1))?.draw(in: f, angle: 0)
        case .shadowed:
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
            shadow.shadowBlurRadius = 12
            shadow.shadowOffset = CGSize(width: 0, height: -4)
            shadow.set()
            NSColor.white.setFill()
            f.fill()
            NSGraphicsContext.restoreGraphicsState()
        case .hairline, .tiny:
            NSColor.black.setFill()
            f.fill()
        case .pair:
            NSColor(srgbRed: 0.95, green: 0.65, blue: 0.1, alpha: 1).setFill()
            f.fill()
        case .darkPanel:
            NSColor(srgbRed: 0.12, green: 0.12, blue: 0.14, alpha: 1).setFill()
            f.fill()
        case .onDark:
            NSColor(srgbRed: 0.92, green: 0.92, blue: 0.95, alpha: 1).setFill()
            f.fill()
        case .text:
            ("Measure 123" as NSString).draw(at: f.origin, withAttributes: [
                .font: NSFont.systemFont(ofSize: 32, weight: .semibold), .foregroundColor: NSColor.black,
            ])
        }
    }
}
