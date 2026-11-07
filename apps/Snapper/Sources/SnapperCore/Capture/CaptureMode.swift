import SlopKit
import CoreGraphics

/// What kind of capture to take.
public enum CaptureMode: String, Sendable, CaseIterable {
    case allInOne
    case area
    case previousArea
    case fullScreen
    case window
    case scrolling
    case selfTimer
    case text
    case recording

    public var title: String {
        switch self {
        case .allInOne: "All-in-One"
        case .area: "Capture Area"
        case .previousArea: "Capture Previous Area"
        case .fullScreen: "Capture Full Screen"
        case .window: "Capture Window"
        case .scrolling: "Scrolling Capture"
        case .selfTimer: "Self-Timer"
        case .text: "Capture Text"
        case .recording: "Record Screen"
        }
    }

    /// Short label for the All-in-One bar.
    public var shortTitle: String {
        switch self {
        case .allInOne: "All-in-One"
        case .area: "Area"
        case .previousArea: "Previous"
        case .fullScreen: "Full Screen"
        case .window: "Window"
        case .scrolling: "Scrolling"
        case .selfTimer: "Timer"
        case .text: "Text"
        case .recording: "Record"
        }
    }

    /// SF Symbol (in-app UI only).
    public var systemImage: String {
        switch self {
        case .allInOne: "square.grid.2x2"
        case .area: "viewfinder"
        case .previousArea: "arrow.counterclockwise.square"
        case .fullScreen: "display"
        case .window: "macwindow"
        case .scrolling: "scroll"
        case .selfTimer: "timer"
        case .text: "text.viewfinder"
        case .recording: "record.circle"
        }
    }

    /// The modes the All-in-One bar offers, in order.
    public static let allInOneModes: [CaptureMode] = [.area, .fullScreen, .window, .scrolling, .selfTimer, .text, .recording]
}

/// Self-timer delays offered in Settings.
public enum SelfTimer {
    public static let intervals = [3, 5, 10]
    public static let defaultInterval = 5
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
