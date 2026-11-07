import SlopKit
import AppKit
import SnapperCore

/// A generated test pattern for scripted and blind tests (`SNAPPER_TEST_SCENE`), so test
/// captures only ever record this window, never the owner's screen.
@MainActor
enum TestScene {
    private static var window: NSWindow?
    private static var scrollView: NSScrollView?

    /// Test mode: captures contain only the scene (and pins), never anything else on screen.
    static var isActive: Bool { window != nil }

    /// The scene is our own window, and captures normally leave our windows out: keep it in.
    static var windowNumbers: Set<CGWindowID> {
        guard let window, window.isVisible else { return [] }
        return [CGWindowID(window.windowNumber)]
    }

    static func owns(_ window: NSWindow) -> Bool { window === self.window }

    /// The scene window for recordings (id and Quartz frame), if it's on screen.
    static var recordingTarget: (id: CGWindowID, frame: CGRect)? {
        guard let window, window.isVisible else { return nil }
        return (CGWindowID(window.windowNumber), ScreenCoordinates.flip(window.frame, primaryHeight: NSScreen.primaryHeight))
    }

    /// The scene's content area as a picked region, for scripted scrolling-capture and
    /// recording tests (no real mouse needed). `inset` trims the edges.
    static func region(inset: CGFloat = 0) -> PickedRegion? {
        guard let window, let screen = window.screen, let content = window.contentView else { return nil }
        let global = window.convertToScreen(content.convert(content.bounds, to: nil)).insetBy(dx: inset, dy: inset)
        return PickedRegion(screen: screen, local: global.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY), frozen: nil, window: nil)
    }

    /// Scrolls the scene's content (for scrolling-capture tests; no real input needed).
    static func scroll(by points: CGFloat) {
        guard let scrollView, let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let maxY = max(0, document.frame.height - clip.bounds.height)
        clip.scroll(to: CGPoint(x: 0, y: min(max(clip.bounds.origin.y + points, 0), maxY)))
        scrollView.reflectScrolledClipView(clip)
    }

    static func showIfRequested() {
        guard let mode = Diagnostics.testScene else { return }
        let screen = NSScreen.underPointer ?? NSScreen.main
        let window: NSWindow
        if mode == "full", let screen {
            window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.setFrame(screen.frame, display: false)
            // Above the Dock and menu bar so a full-screen capture shows only the pattern.
            window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        } else {
            let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            let size = CGSize(width: min(1000, visible.width - 80), height: min(680, visible.height - 80))
            window = NSWindow(contentRect: CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                                                  width: size.width, height: size.height),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Snapper Test Scene"
        }
        window.isReleasedWhenClosed = false
        // The pattern is four screens tall inside a scroll view, so scrolling capture has
        // something to scroll. No scrollers: they'd flash into the frames.
        let scroll = NSScrollView(frame: window.contentLayoutRect)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.drawsBackground = false
        let pattern = TestPatternView(frame: CGRect(x: 0, y: 0, width: window.contentLayoutRect.width, height: window.contentLayoutRect.height * 4))
        pattern.autoresizingMask = [.width]
        scroll.documentView = pattern
        window.contentView = scroll
        scrollView = scroll
        window.orderFrontRegardless()
        self.window = window
    }
}

/// Grid, color bars, gradient, shapes and "slopapp-test" text: easy to recognize in a
/// capture and full of edges for the magnifier and redaction tools.
final class TestPatternView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.96, green: 0.96, blue: 0.94, alpha: 1).setFill()
        bounds.fill()
        // Grid every 20 pt, darker every 100 pt.
        for x in stride(from: 0, through: bounds.width, by: 20) {
            (Int(x) % 100 == 0 ? NSColor(white: 0.6, alpha: 1) : NSColor(white: 0.85, alpha: 1)).setFill()
            CGRect(x: x, y: 0, width: 1, height: bounds.height).fill()
        }
        for y in stride(from: 0, through: bounds.height, by: 20) {
            (Int(y) % 100 == 0 ? NSColor(white: 0.6, alpha: 1) : NSColor(white: 0.85, alpha: 1)).setFill()
            CGRect(x: 0, y: y, width: bounds.width, height: 1).fill()
        }
        // Color bars.
        let bars: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue, .systemPurple, .black]
        let barWidth = min(80, (bounds.width - 80) / CGFloat(bars.count))
        for (i, color) in bars.enumerated() {
            color.setFill()
            CGRect(x: 40 + CGFloat(i) * barWidth, y: 40, width: barWidth, height: 80).fill()
        }
        // Gradient strip.
        NSGradient(colors: [.white, .systemBlue, .black])?.draw(in: CGRect(x: 40, y: 140, width: barWidth * CGFloat(bars.count), height: 40), angle: 0)
        // Big label.
        let title = "slopapp-test" as NSString
        title.draw(at: CGPoint(x: 40, y: 200), withAttributes: [
            .font: NSFont.systemFont(ofSize: 64, weight: .heavy), .foregroundColor: NSColor.black,
        ])
        ("Snapper test scene · captures of this window contain nothing personal" as NSString).draw(
            at: CGPoint(x: 42, y: 285),
            withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.darkGray])
        // Shapes.
        NSColor.systemRed.setStroke()
        let circle = NSBezierPath(ovalIn: CGRect(x: 60, y: 330, width: 140, height: 140))
        circle.lineWidth = 6
        circle.stroke()
        NSColor.systemBlue.setFill()
        NSBezierPath(roundedRect: CGRect(x: 240, y: 330, width: 200, height: 140), xRadius: 18, yRadius: 18).fill()
        NSColor.systemGreen.setFill()
        let triangle = NSBezierPath()
        triangle.move(to: CGPoint(x: 480, y: 470))
        triangle.line(to: CGPoint(x: 560, y: 330))
        triangle.line(to: CGPoint(x: 640, y: 470))
        triangle.close()
        triangle.fill()
        // Fine checkerboard for pixel checks.
        for row in 0..<16 {
            for col in 0..<16 where (row + col) % 2 == 0 {
                NSColor.black.setFill()
                CGRect(x: 680 + CGFloat(col) * 4, y: 340 + CGFloat(row) * 4, width: 4, height: 4).fill()
            }
        }
        ("fake@example.com  ·  555-0100  ·  4111 1111 1111 1111" as NSString).draw(
            at: CGPoint(x: 42, y: 500),
            withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 20, weight: .regular), .foregroundColor: NSColor.black])
        // Below the fold: numbered rows with their own colors and offsets, so scrolled
        // frames line up in exactly one place.
        let palette: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue, .systemPurple, .systemPink]
        var row = 1
        for y in stride(from: 560.0, to: bounds.height - 40, by: 44.0) {
            let color = palette[row % palette.count]
            color.withAlphaComponent(0.25).setFill()
            CGRect(x: 40, y: y, width: bounds.width - 80, height: 36).fill()
            color.setFill()
            CGRect(x: 40 + CGFloat((row * 53) % 400), y: y + 6, width: 60, height: 24).fill()
            ("Row \(row) · scrolling capture test line" as NSString).draw(
                at: CGPoint(x: 520, y: y + 8),
                withAttributes: [.font: NSFont.systemFont(ofSize: 17, weight: .medium), .foregroundColor: NSColor.black])
            row += 1
        }
    }
}
