import CoreGraphics
import Foundation

/// What a screen recording records: the stream source and the rect within it.
///
/// Test mode (`SNAPPER_TEST_SCENE`) records only Snapper's own windows: the test scene and
/// the recording's overlays (camera bubble, clicks, keystrokes), as a display stream that
/// *includes* just those windows, clipped to the part of the selection inside the scene. No
/// other app's window, and no surface no app owns, can reach a test recording. A selection
/// that misses the scene is refused.
public struct RecordingPlan: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case display(CGDirectDisplayID)
        /// Test mode: only our own windows (the scene `window` and the overlays) on `display`.
        case testScene(window: CGWindowID, display: CGDirectDisplayID)
    }

    public var source: Source
    /// The recorded rect in display-local points, top-left origin.
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
            return RecordingPlan(source: .testScene(window: scene.id, display: display.id),
                                 sourceRect: rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY),
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
    public var audio: RecordingAudio

    public init(frameRate: Int = 30, showsCursor: Bool = true, scaleToOneX: Bool = false, audio: RecordingAudio = .none) {
        self.frameRate = frameRate
        self.showsCursor = showsCursor
        self.scaleToOneX = scaleToOneX
        self.audio = audio
    }

    public static let frameRates = [15, 24, 30, 60]

    /// What a recording actually uses: a GIF has no sound, so it never opens the microphone.
    public func forRecording(gif: Bool) -> RecordingOptions {
        var options = self
        if gif { options.audio = .none }
        return options
    }

    /// Video keyframes once a second, so a trim without re-encoding starts close to where
    /// it was asked to (the few frames before it stay in the file, hidden by an edit list).
    public var keyframeInterval: Int { max(1, frameRate) }
}

/// Which sounds a recording keeps. Each one is its own AAC track while recording; with both,
/// they're mixed into one track when the recording stops (players and chat apps play only the
/// first track).
public struct RecordingAudio: Equatable, Sendable {
    /// The Mac's own sound (apps, alerts), through ScreenCaptureKit. Snapper's own sounds are
    /// left out.
    public var computer: Bool
    public var microphone: Bool

    public init(computer: Bool = false, microphone: Bool = false) {
        self.computer = computer
        self.microphone = microphone
    }

    public static let none = RecordingAudio()
    public var isSilent: Bool { !computer && !microphone }
    public var trackCount: Int { (computer ? 1 : 0) + (microphone ? 1 : 0) }
    public var needsMixing: Bool { trackCount > 1 }
}

/// Elapsed recording time as "0:07" / "1:02:03".
public enum Elapsed {
    public static func string(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
