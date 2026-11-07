/// Where the overlay's lines go so every edge lands on a whole device pixel: crisp at 1×,
/// 2× and 3×, never smeared across two half-covered rows. All in image pixels (top-left
/// origin), like the rest of RulerCore; the view only converts pixel rects to points.
///
/// Two kinds of line:
/// - A line *at a pixel* (the hover distance at the pointer's row, a held distance, a gap
///   between guides) is one point thick: the point-wide band of pixels that holds that row,
///   so it also stays on whole pixels when a screenshot is scaled to 1×.
/// - A line *on a boundary* (a guide sits between two pixels) is an even number of pixels
///   centred exactly on it, so neither side wins.
public enum CrispStroke {
    /// Device pixels in one point: 1 at 1×, 2 on Retina, 3 at 3×.
    public static func pointWidth(scale: Double) -> Int {
        max(1, Int(scale.rounded()))
    }

    /// The point-wide band of rows (or columns) holding pixel `index`.
    public static func band(holding index: Int, scale: Double) -> Range<Int> {
        let w = pointWidth(scale: scale)
        let start = floorDiv(index, w) * w
        return start..<(start + w)
    }

    /// An even band centred on `boundary`, at least one point (two pixels at 1×).
    public static func band(straddling boundary: Int, scale: Double) -> Range<Int> {
        let half = max(1, (pointWidth(scale: scale) + 1) / 2)
        return (boundary - half)..<(boundary + half)
    }

    /// How far a T end reaches past its line on each side (about 3.5 pt).
    public static func tickReach(scale: Double) -> Int {
        max(3, Int((3.5 * scale).rounded()))
    }

    /// A dimension line with T ends, as filled pixel rects: the line along `axis` through
    /// pixel `at`, from boundary `start` to boundary `end`, and a tick just inside each end
    /// (its outer edge is the measured edge). `emphasized` (hovered) is a pixel bolder on
    /// each side. `halo` is the same shapes grown by one pixel, drawn underneath.
    public static func dimension(axis: GuideAxis, at: Int, start: Int, end: Int, scale: Double,
                                 emphasized: Bool = false) -> (line: [PixelRect], halo: [PixelRect]) {
        let w = pointWidth(scale: scale)
        var band = band(holding: at, scale: scale)
        if emphasized { band = (band.lowerBound - 1)..<(band.upperBound + 1) }
        let reach = tickReach(scale: scale)
        let lo = min(start, end), hi = max(start, end)
        let tick = min(w, max(hi - lo, 1))
        // Along the line, then across it, as (along, across) pairs; flipped for vertical lines.
        func rect(_ along: Range<Int>, _ across: Range<Int>) -> PixelRect {
            axis == .horizontal
                ? PixelRect(minX: along.lowerBound, minY: across.lowerBound, maxX: along.upperBound, maxY: across.upperBound)
                : PixelRect(minX: across.lowerBound, minY: along.lowerBound, maxX: across.upperBound, maxY: along.upperBound)
        }
        let across = (band.lowerBound - reach)..<(band.upperBound + reach)
        let line = [
            rect(lo..<max(hi, lo + 1), band),
            rect(lo..<(lo + tick), across),
            rect((hi - tick)..<max(hi, lo + 1), across),
        ]
        return (line, line.map { $0.outsetBy(1) })
    }

    private static func floorDiv(_ a: Int, _ b: Int) -> Int {
        a >= 0 ? a / b : -((-a + b - 1) / b)
    }
}
