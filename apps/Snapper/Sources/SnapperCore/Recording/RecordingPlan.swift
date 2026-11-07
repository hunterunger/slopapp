import CoreGraphics
import Foundation

/// What a screen recording records: the stream source and the rect within it.
///
/// Test mode (`SNAPPER_TEST_SCENE`) records the test scene *window* on its own (a
/// desktop-independent window stream), clipped to the part of the selection inside it, so
/// nothing else on screen can reach a test recording, even surfaces no app owns. A
/// selection that misses the scene is refused.
public struct RecordingPlan: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case display(CGDirectDisplayID)
        case window(CGWindowID)
    }

    public var source: Source
    /// The recorded rect in the source's own points, top-left origin (display-local or
    /// window-local).
    public var sourceRect: CGRect
    /// The same rect on screen (Quartz global points, top-left origin), for the frame drawn
    /// around it while recording.
    public var screenRect: CGRect

    /// - Parameters:
    ///   - selection: what the user picked, Quartz global points.
    ///   - display: the display it's on (id and Quartz frame).
    ///   - testScene: the only window test mode may record (id and Quartz frame), or nil.
    public static func make(selection: CGRect, display: (id: CGDirectDisplayID, frame: CGRect),
                            testScene: (id: CGWindowID, frame: CGRect)?) -> RecordingPlan? {
        let selection = selection.standardized
        if let scene = testScene {
            let inside = selection.intersection(scene.frame).intersection(display.frame)
            guard let rect = usable(inside) else { return nil }
            return RecordingPlan(source: .window(scene.id),
                                 sourceRect: rect.offsetBy(dx: -scene.frame.minX, dy: -scene.frame.minY),
                                 screenRect: rect)
        }
        guard let rect = usable(selection.intersection(display.frame)) else { return nil }
        return RecordingPlan(source: .display(display.id),
                             sourceRect: rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY),
                             screenRect: rect)
    }

    /// Whole points, at least 16 × 16.
    private static func usable(_ rect: CGRect) -> CGRect? {
        guard !rect.isNull, !rect.isEmpty else { return nil }
        let snapped = CGRect(x: rect.minX.rounded(.up), y: rect.minY.rounded(.up),
                             width: rect.maxX.rounded(.down) - rect.minX.rounded(.up),
                             height: rect.maxY.rounded(.down) - rect.minY.rounded(.up))
        return snapped.width >= 16 && snapped.height >= 16 ? snapped : nil
    }

    /// Output pixel size for a rect at `scale`, rounded down to even numbers (H.264 needs them).
    public static func pixelSize(for rect: CGRect, scale: CGFloat, maxDimension: Int? = nil) -> (width: Int, height: Int) {
        var w = rect.width * scale, h = rect.height * scale
        if let maxDimension, max(w, h) > CGFloat(maxDimension) {
            let factor = CGFloat(maxDimension) / max(w, h)
            w *= factor
            h *= factor
        }
        let even = { (v: CGFloat) in max(2, Int(v) / 2 * 2) }
        return (even(w), even(h))
    }
}

/// Recording options from Settings.
public struct RecordingOptions: Equatable, Sendable {
    public var frameRate: Int
    public var showsCursor: Bool
    public var scaleToOneX: Bool

    public init(frameRate: Int = 30, showsCursor: Bool = true, scaleToOneX: Bool = false) {
        self.frameRate = frameRate
        self.showsCursor = showsCursor
        self.scaleToOneX = scaleToOneX
    }

    public static let frameRates = [15, 24, 30, 60]
}

/// Elapsed recording time as "0:07" / "1:02:03".
public enum Elapsed {
    public static func string(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
