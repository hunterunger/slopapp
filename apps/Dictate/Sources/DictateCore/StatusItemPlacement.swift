import CoreGraphics

/// Whether the menu bar icon can actually be seen. macOS hides status items that don't fit
/// (a crowded menu bar, worst next to the camera notch) and those turned off in System
/// Settings › Menu Bar, without telling the app. This is a best-effort reading of where the
/// icon's window ended up; it errs on the side of "visible" so it never nags by mistake.
public enum StatusItemPlacement {
    public struct Screen: Equatable, Sendable {
        /// The whole screen, in global (AppKit) coordinates.
        public var frame: CGRect
        /// The camera housing's span in the menu bar, if the screen has one.
        public var notch: CGRect?

        public init(frame: CGRect, notch: CGRect? = nil) {
            self.frame = frame
            self.notch = notch
        }

        /// The notch from the two usable areas either side of it (`NSScreen.auxiliaryTopLeftArea`
        /// and `auxiliaryTopRightArea`).
        public init(frame: CGRect, topLeftArea: CGRect?, topRightArea: CGRect?) {
            self.frame = frame
            if let left = topLeftArea, let right = topRightArea, right.minX > left.maxX {
                notch = CGRect(x: left.maxX, y: min(left.minY, right.minY),
                               width: right.minX - left.maxX, height: max(left.height, right.height))
            } else {
                notch = nil
            }
        }
    }

    /// `frame` is the status item's window; `isOnScreen` whether its window is ordered in.
    public static func isHidden(itemFrame frame: CGRect?, isOnScreen: Bool, screens: [Screen]) -> Bool {
        guard let frame, isOnScreen, frame.width > 1, frame.height > 1 else { return true }
        guard !screens.isEmpty else { return false }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard let screen = screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(center) }) else {
            // Parked off every screen.
            return true
        }
        if let notch = screen.notch, frame.midX > notch.minX, frame.midX < notch.maxX {
            // Under the camera housing: there, but nobody can see or click it.
            return true
        }
        return false
    }
}
