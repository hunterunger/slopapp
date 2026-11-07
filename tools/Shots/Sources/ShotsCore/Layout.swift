import CoreGraphics

/// Where everything goes on the canvas. Canvas coordinates are pixels, origin top-left;
/// the canvas is `size` pixels and `pointScale` pixels per point (2880 × 1800 at 2 = a
/// 1440 × 900 point "screen").
public struct Composition: Equatable, Sendable {
    public struct Placed: Equatable, Sendable {
        public var window: ReadyFile.Window
        /// Pixel rect on the canvas.
        public var rect: CGRect
    }

    public struct CalloutPlacement: Equatable, Sendable {
        /// The detail's rect on the canvas (inside the window).
        public var source: CGRect
        /// The magnified copy's rect on the canvas.
        public var target: CGRect
        /// The detail's rect in the first window's capture, in capture pixels.
        public var crop: CGRect
    }

    public var size: CGSize
    public var pointScale: CGFloat
    /// Windows (and panels), back to front.
    public var windows: [Placed]
    /// Menu bar strip height in pixels (0 = none).
    public var stripHeight: CGFloat
    public var statusItem: Placed?
    /// Whether the status item looks pressed (its panel hangs from it).
    public var statusItemPressed: Bool
    public var callout: CalloutPlacement?
    /// Window points → canvas points.
    public var zoom: CGFloat

    public static let canvas = CGSize(width: 2880, height: 1800)
    /// Share of the canvas the windows may use when fitting (shadows need the rest).
    public static let fitWidth: CGFloat = 0.88
    public static let fitHeight: CGFloat = 0.84
    /// Standard menu bar height when the status item doesn't say.
    public static let menuBarHeight: CGFloat = 24
    /// Windows sit a little above centre: their shadow falls below.
    public static let lift: CGFloat = 8

    /// Lays out the ready file's windows for one shot.
    /// - Parameters:
    ///   - captureScale: pixels per point in the captures (the screen's backing scale).
    public static func layout(ready: ReadyFile, shot: Shot, menuBar defaultMenuBar: Bool,
                              size: CGSize = canvas, pointScale: CGFloat = 2) -> Composition {
        let canvasPoints = CGSize(width: size.width / pointScale, height: size.height / pointScale)
        let windows = ready.windows.filter { $0.kind != .statusItem }
        let item = ready.windows.first { $0.kind == .statusItem }
        let wantsStrip = shot.menuBar ?? defaultMenuBar
        let baseStrip: CGFloat = wantsStrip ? max(menuBarHeight, (item?.frame.height).map { CGFloat($0) } ?? 0) : 0

        let group = windows.map(\.frame.cgRect).reduce(CGRect.null) { $0.union($1) }
        let fitArea = CGSize(width: canvasPoints.width, height: canvasPoints.height - baseStrip)
        let fit = group.isNull ? 1 : min(fitArea.width * fitWidth / group.width, fitArea.height * fitHeight / group.height)
        let zoom = CGFloat(shot.zoom.map { min($0, fit * 1.0001) } ?? min(1, fit))
        // A zoomed-in panel gets a zoomed-in menu bar, so they read as one screen.
        let stripScale = min(max(zoom, 1), 2)
        let stripPoints = (baseStrip * stripScale).rounded()
        let available = CGSize(width: canvasPoints.width, height: canvasPoints.height - stripPoints)

        // Centre the group in the space under the strip, nudged up for the shadow.
        let origin = CGPoint(
            x: ((canvasPoints.width - group.width * zoom) / 2).rounded(),
            y: (stripPoints + (available.height - group.height * zoom) / 2 - lift).rounded()
        )
        func place(_ frame: CGRect) -> CGRect {
            CGRect(
                x: ((origin.x + (frame.minX - group.minX) * zoom) * pointScale).rounded(),
                y: ((origin.y + (frame.minY - group.minY) * zoom) * pointScale).rounded(),
                width: (frame.width * zoom * pointScale).rounded(),
                height: (frame.height * zoom * pointScale).rounded()
            )
        }
        let placed = group.isNull ? [] : windows.map { Placed(window: $0, rect: place($0.frame.cgRect)) }

        // The icon sits in the strip; above the front panel when that panel hangs from the
        // menu bar, else where status items usually are (right of centre).
        var statusItem: Placed?
        var pressed = false
        if wantsStrip, let item {
            let itemSize = CGSize(width: (item.frame.width * stripScale * pointScale).rounded(),
                                  height: (item.frame.height * stripScale * pointScale).rounded())
            let stripPixels = stripPoints * pointScale
            let front = placed.last
            let hangs = front.map { $0.rect.minY - stripPixels < 48 * pointScale } ?? false
            let centreX = hangs && front != nil ? front!.rect.midX : size.width * 0.8
            statusItem = Placed(window: item, rect: CGRect(
                x: (centreX - itemSize.width / 2).rounded(),
                y: ((stripPixels - itemSize.height) / 2).rounded(),
                width: itemSize.width, height: itemSize.height
            ))
            pressed = hangs
        }

        var callout: CalloutPlacement?
        if let spec = shot.callout, let first = placed.first {
            callout = placeCallout(spec, in: first, zoom: zoom, captureScale: CGFloat(ready.scale),
                                   pointScale: pointScale, canvas: size, top: stripPoints * pointScale)
        }

        return Composition(size: size, pointScale: pointScale, windows: placed, stripHeight: stripPoints * pointScale,
                           statusItem: statusItem, statusItemPressed: pressed, callout: callout, zoom: zoom)
    }

    /// Margin kept between a callout and the canvas edge, in points.
    public static let calloutMargin: CGFloat = 28
    /// How far a callout reaches past the window's edge, in points.
    public static let calloutOverhang: CGFloat = 56

    static func placeCallout(_ spec: Callout, in window: Placed, zoom: CGFloat, captureScale: CGFloat,
                             pointScale: CGFloat, canvas: CGSize, top: CGFloat) -> CalloutPlacement {
        let toCanvas = zoom * pointScale
        let source = CGRect(
            x: window.rect.minX + spec.rect.minX * toCanvas, y: window.rect.minY + spec.rect.minY * toCanvas,
            width: spec.rect.width * toCanvas, height: spec.rect.height * toCanvas
        )
        let magnification = CGFloat(spec.zoom ?? 2)
        let size = CGSize(width: (source.width * magnification).rounded(), height: (source.height * magnification).rounded())
        let side = spec.side ?? {
            let relX = (source.midX - window.rect.minX) / window.rect.width
            let relY = (source.midY - window.rect.minY) / window.rect.height
            let horizontal = abs(relX - 0.5), vertical = abs(relY - 0.5)
            if horizontal >= vertical { return relX >= 0.5 ? .right : .left }
            return relY >= 0.5 ? .bottom : .top
        }()
        let overhang = calloutOverhang * pointScale
        var x: CGFloat, y: CGFloat
        switch side {
        case .right: x = window.rect.maxX + overhang - size.width; y = source.midY - size.height / 2
        case .left: x = window.rect.minX - overhang; y = source.midY - size.height / 2
        case .bottom: x = source.midX - size.width / 2; y = window.rect.maxY + overhang - size.height
        case .top: x = source.midX - size.width / 2; y = window.rect.minY - overhang
        }
        let margin = calloutMargin * pointScale
        x = min(max(x, margin), canvas.width - margin - size.width)
        y = min(max(y, top + margin), canvas.height - margin - size.height)
        let crop = CGRect(x: spec.rect.minX * captureScale, y: spec.rect.minY * captureScale,
                          width: spec.rect.width * captureScale, height: spec.rect.height * captureScale)
        return CalloutPlacement(source: source, target: CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height), crop: crop)
    }
}
