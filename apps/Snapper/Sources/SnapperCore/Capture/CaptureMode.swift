import SlopKit
import CoreGraphics

/// What kind of capture to take.
public enum CaptureMode: String, Sendable, CaseIterable {
    case area
    case window
    case fullScreen
    case previousArea

    public var title: String {
        switch self {
        case .area: "Capture Area"
        case .window: "Capture Window"
        case .fullScreen: "Capture Full Screen"
        case .previousArea: "Capture Previous Area"
        }
    }
}

/// The last area captured, so "Capture Previous Area" can take it again.
public struct RememberedArea: Codable, Sendable, Equatable {
    /// The display it was on (`CGDirectDisplayID`).
    public var displayID: UInt32
    /// Screen-local AppKit points.
    public var rect: CGRect

    public init(displayID: UInt32, rect: CGRect) {
        self.displayID = displayID
        self.rect = rect
    }

    /// The rect to use on a screen of `bounds` (screen-local), or nil if it no longer fits
    /// (the display shrank or was replaced).
    public func rect(within bounds: CGRect) -> CGRect? {
        let clipped = rect.intersection(bounds)
        guard !clipped.isNull, SelectionGeometry.isUsable(clipped) else { return nil }
        return clipped
    }
}
