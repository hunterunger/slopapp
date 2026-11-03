import CoreGraphics

/// The 8 pt spacing grid from docs/design-system.md. Use these instead of literals.
public enum Spacing {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 20
    public static let xxl: CGFloat = 24

    /// Margin between a window's edge and its content.
    public static let windowMargin: CGFloat = 20
}

/// Standard sizes shared across apps.
public enum Metrics {
    /// Width of a `.window`-style menu bar popover.
    public static let menuBarWindowWidth: CGFloat = 320
    /// Width of every Settings tab.
    public static let settingsWidth: CGFloat = 480
    /// Default size of a drop-in utility window.
    public static let utilityWindowSize = CGSize(width: 520, height: 420)
}
