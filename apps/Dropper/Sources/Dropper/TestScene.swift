import AppKit
import DropperCore
import SlopKit

/// The generated test scene (`DROPPER_TEST_SCENE=1`): swatches of known colors, and a patch
/// of 1-pixel stripes for checking pixel nudging. While it's open, the precise loupe's
/// frozen screen contains only this window (masked by SlopKit's `PrivacyMask`).
@MainActor
enum TestScene {
    struct Swatch {
        let label: String
        let color: NSColor
    }

    static let swatches: [Swatch] = [
        Swatch(label: "sRGB #3366CC", color: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1)),
        Swatch(label: "sRGB #FF0000", color: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)),
        Swatch(label: "Display P3 red", color: NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1)),
        Swatch(label: "sRGB #12AB7F", color: NSColor(srgbRed: 0x12 / 255.0, green: 0xAB / 255.0, blue: 0x7F / 255.0, alpha: 1)),
        Swatch(label: "sRGB #808080", color: NSColor(srgbRed: 128 / 255.0, green: 128 / 255.0, blue: 128 / 255.0, alpha: 1)),
    ]

    static let swatchSize: CGFloat = 110
    static let gap: CGFloat = 24
    static let size = CGSize(width: 3 * swatchSize + 4 * gap, height: 2 * swatchSize + 3 * gap + 60)

    private(set) static var window: NSWindow?

    static var isActive: Bool { Diagnostics.testScene }

    static var windowNumbers: Set<CGWindowID> {
        guard let window, window.isVisible else { return [] }
        return [CGWindowID(window.windowNumber)]
    }

    static func showIfRequested() {
        guard isActive, window == nil else { return }
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(contentRect: CGRect(x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded(),
                                                  width: size.width, height: size.height),
                              styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Dropper Test Scene"
        window.isReleasedWhenClosed = false
        window.contentView = TestSceneView(frame: CGRect(origin: .zero, size: size))
        window.orderFrontRegardless()
        self.window = window
    }

    /// Frame of slot `index` (0...5, the last is the stripes) in the scene view (flipped).
    static func slotFrame(_ index: Int) -> CGRect {
        let row = index / 3, column = index % 3
        return CGRect(x: gap + CGFloat(column) * (swatchSize + gap), y: gap + CGFloat(row) * (swatchSize + gap + 20),
                      width: swatchSize, height: swatchSize)
    }

    /// The middle of a slot in AppKit global coordinates.
    static func globalCenter(of index: Int) -> CGPoint? {
        guard let window, let view = window.contentView else { return nil }
        let frame = slotFrame(index)
        let local = view.convert(CGPoint(x: frame.midX, y: frame.midY), to: nil)
        return window.convertPoint(toScreen: local)
    }
}

final class TestSceneView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Fixed colors on purpose: what's picked must not depend on light or dark mode.
        NSColor(srgbRed: 0.97, green: 0.97, blue: 0.96, alpha: 1).setFill()
        bounds.fill()
        let label: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor(white: 0.35, alpha: 1)]
        for (index, swatch) in TestScene.swatches.enumerated() {
            let frame = TestScene.slotFrame(index)
            swatch.color.setFill()
            frame.fill()
            (swatch.label as NSString).draw(at: CGPoint(x: frame.minX, y: frame.maxY + 4), withAttributes: label)
        }
        drawStripes(in: TestScene.slotFrame(5))
        ("1-pixel stripes: red, blue" as NSString).draw(at: CGPoint(x: TestScene.slotFrame(5).minX, y: TestScene.slotFrame(5).maxY + 4),
                                                        withAttributes: label)
        ("Dropper test scene · the loupe freezes only this window in test mode" as NSString).draw(
            at: CGPoint(x: TestScene.gap, y: bounds.height - 28), withAttributes: label)
    }

    /// Alternating 1-pixel columns of sRGB red and blue, drawn at the backing scale.
    private func drawStripes(in rect: CGRect) {
        let scale = window?.backingScaleFactor ?? 2
        let width = Int(rect.width * scale), height = Int(rect.height * scale)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        for x in 0..<width {
            context.setFillColor(x % 2 == 0 ? CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1) : CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        guard let image = context.makeImage(), let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.saveGState()
        cg.interpolationQuality = .none
        // The view is flipped; the image is symmetric vertically, so no flip needed.
        cg.draw(image, in: rect)
        cg.restoreGState()
    }
}
