import AppKit
import ScreenCaptureKit
import ShotsCore

/// Captures a scene's windows with their translucent materials over our backdrop.
///
/// `screencapture -l<id> -o` captures a window alone, but its glass and vibrancy are then
/// drawn over nothing (grey). So each window is captured twice:
/// 1. composited by ScreenCaptureKit from **only our own windows** (the backdrop and the
///    scene's windows; nothing else on screen is in the filter), cropped to the window, so the
///    glass shows what it really sits on;
/// 2. alone (`<id>-mask.png`, from screencapture -o, taken by the script), for its exact shape.
/// The result (`<id>.png`) is the composite's pixels inside the window's own alpha.
enum Capture {
    static func run(ready: ReadyFile, backdrop: UInt32, directory: URL) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ours = Set([backdrop] + ready.windows.map(\.id))
        let windows = content.windows.filter { ours.contains($0.windowID) }
        guard windows.contains(where: { $0.windowID == backdrop }) else { throw Failure("the backdrop window isn't on screen") }
        // The primary display (origin 0,0), where the backdrop and the scene are.
        guard let display = content.displays.first(where: { $0.frame.origin == .zero }) ?? content.displays.first else {
            throw Failure("no display")
        }
        let filter = SCContentFilter(display: display, including: windows)
        for window in ready.windows where window.kind != .statusItem {
            let frame = window.frame.cgRect
            let config = SCStreamConfiguration()
            config.sourceRect = frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            config.width = Int((frame.width * ready.scale).rounded())
            config.height = Int((frame.height * ready.scale).rounded())
            config.showsCursor = false
            config.colorSpaceName = CGColorSpace.sRGB
            config.scalesToFit = false
            let composite = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let maskURL = directory.appendingPathComponent("\(window.id)-mask.png")
            guard let mask = Render.loadImage(maskURL) else { throw Failure("missing \(maskURL.path)") }
            guard let merged = merge(composite, alpha: mask) else { throw Failure("couldn't merge window \(window.id)") }
            try Render.writePNG(merged, to: directory.appendingPathComponent("\(window.id).png"))
        }
    }

    /// `pixels` kept only where `alpha` (the window alone) is opaque, with its soft edges.
    static func merge(_ pixels: CGImage, alpha: CGImage) -> CGImage? {
        let size = CGSize(width: alpha.width, height: alpha.height)
        guard let context = CGContext(data: nil, width: alpha.width, height: alpha.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: Render.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(origin: .zero, size: size)
        context.interpolationQuality = .none
        context.draw(pixels, in: rect)
        context.setBlendMode(.destinationIn)
        context.draw(alpha, in: rect)
        return context.makeImage()
    }
}
