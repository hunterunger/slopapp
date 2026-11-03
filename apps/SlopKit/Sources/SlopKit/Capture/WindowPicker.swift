import CoreGraphics

/// One on-screen window, as the window server reports it (`CGWindowListCopyWindowInfo`).
public struct WindowInfo: Sendable, Equatable, Identifiable {
    public var id: UInt32
    public var ownerPID: Int32
    public var ownerName: String
    public var bundleID: String?
    public var layer: Int
    public var alpha: Double
    /// Quartz global coordinates (top-left origin, points).
    public var frame: CGRect

    public init(id: UInt32, ownerPID: Int32, ownerName: String, bundleID: String? = nil, layer: Int, alpha: Double, frame: CGRect) {
        self.id = id
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.bundleID = bundleID
        self.layer = layer
        self.alpha = alpha
        self.frame = frame
    }
}

/// Picks the window under the pointer for window capture.
public enum WindowPicker {
    /// Windows narrower or shorter than this are skipped (tooltips, slivers, hidden helpers).
    public static let minimumSide: CGFloat = 40

    /// Whether a window can be picked: a normal app window (layer 0), visible, reasonably
    /// big, not ours and not the window server's.
    public static func isPickable(_ window: WindowInfo, excludingPID: Int32?) -> Bool {
        window.layer == 0
            && window.alpha > 0.01
            && window.frame.width >= minimumSide && window.frame.height >= minimumSide
            && window.ownerPID != excludingPID
            && window.ownerName != "Window Server"
    }

    /// The front-most pickable window containing `point` (Quartz global). `windows` must be
    /// ordered front to back, as `CGWindowListCopyWindowInfo` returns them.
    public static func window(at point: CGPoint, in windows: [WindowInfo], excludingPID: Int32?) -> WindowInfo? {
        windows.first { isPickable($0, excludingPID: excludingPID) && $0.frame.contains(point) }
    }
}

/// Which windows to leave out of a capture so desktop icons don't show up in it.
public enum DesktopIcons {
    /// Finder draws desktop icons in its own windows below normal windows (negative layers,
    /// `kCGDesktopIconWindowLevel`). Leaving those out of the capture hides the icons without
    /// touching Finder's preferences.
    public static func isDesktopIconWindow(bundleID: String?, layer: Int) -> Bool {
        bundleID == "com.apple.finder" && layer < 0
    }
}
