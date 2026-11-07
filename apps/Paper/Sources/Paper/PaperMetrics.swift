import CoreGraphics
import SlopKit

/// Paper's shared layout numbers, so the bars under the toolbar line up across the sidebar,
/// the canvas and the inspector, and the canvas and its overlays agree.
enum PaperMetrics {
    /// Height of every bar directly under the toolbar (sidebar picker, editing bar, inspector
    /// picker, panel headers, info bars). Equal heights put their hairlines on one line.
    static let barHeight: CGFloat = 36
    /// Gap between the canvas edges and the pages, and between pages.
    static let pageGap: CGFloat = Spacing.m
    /// The selection outline sits this far outside an annotation; handles sit on its corners.
    static let selectionOutset: CGFloat = 2
    /// Page thumbnails in the sidebar.
    static let thumbnailWidth: CGFloat = 110
    /// The selection ring around a thumbnail: a gap, then the ring. The page has square
    /// corners, so the ring's inner radius equals the gap and its outer radius gap + width.
    static let thumbnailRingGap: CGFloat = 3
    static let thumbnailRingWidth: CGFloat = 3
    static var thumbnailRingRadius: CGFloat { thumbnailRingGap + thumbnailRingWidth }
}
