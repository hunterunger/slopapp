import AppKit
import QuartzCore
import SwiftUI

/// Zoom commands for the preview (View menu, the zoom buttons), and the zoom level to show.
@MainActor
@Observable
final class PreviewController {
    @ObservationIgnored fileprivate weak var scrollView: CompareScrollView?
    /// Whether the image is shown whole (zoom to fit).
    private(set) var isFitted = true
    /// Current zoom, where 1 means one image pixel per screen pixel.
    private(set) var pixelZoom: Double = 1
    /// The visible part of the image, in the preview's coordinates (top-left origin), so
    /// the split handle can span exactly the picture.
    private(set) var imageRect: CGRect = .zero

    var canZoom: Bool { scrollView?.hasImage == true }

    func zoomIn() { scrollView?.zoom(by: 1.5) }
    func zoomOut() { scrollView?.zoom(by: 1 / 1.5) }
    func zoomToFit() { scrollView?.fit() }
    func actualSize() { scrollView?.actualSize() }

    fileprivate func update(fitted: Bool, pixelZoom: Double) {
        if isFitted != fitted { isFitted = fitted }
        if abs(self.pixelZoom - pixelZoom) > 0.001 { self.pixelZoom = pixelZoom }
    }

    fileprivate func update(imageRect rect: CGRect) {
        let changed = abs(rect.minX - imageRect.minX) > 0.25 || abs(rect.minY - imageRect.minY) > 0.25
            || abs(rect.width - imageRect.width) > 0.25 || abs(rect.height - imageRect.height) > 0.25
        if changed { imageRect = rect }
    }
}

/// Before and after, on top of each other: the result shows to the right of the split,
/// the original to the left. Pinch, scroll and the zoom commands move both together.
struct CompareImageView: NSViewRepresentable {
    let before: CGImage?
    let after: CGImage?
    /// The size both are shown at, in image pixels (the original's size).
    let pixelSize: CGSize
    /// 0...1 across the visible width; nil shows the result alone.
    let split: Double?
    let controller: PreviewController
    /// Changes when a different file (or page) is shown, so zoom goes back to fit.
    let identity: String

    func makeNSView(context: Context) -> CompareScrollView {
        let view = CompareScrollView()
        controller.scrollView = view
        view.onZoom = { [weak controller] fitted, zoom in controller?.update(fitted: fitted, pixelZoom: zoom) }
        view.onImageRect = { [weak controller] rect in controller?.update(imageRect: rect) }
        return view
    }

    func updateNSView(_ view: CompareScrollView, context: Context) {
        controller.scrollView = view
        view.show(before: before, after: after, pixelSize: pixelSize, identity: identity)
        view.split = split
    }
}

final class CompareScrollView: NSScrollView {
    private let document = CompareDocumentView()
    private var identity = ""
    private var fitted = true
    var onZoom: ((Bool, Double) -> Void)?
    var onImageRect: ((CGRect) -> Void)?

    var hasImage: Bool { document.pixelSize != .zero }

    var split: Double? {
        get { document.split }
        set { document.split = newValue }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        contentView = CenteringClipView()
        documentView = document
        drawsBackground = false
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        allowsMagnification = true
        // A fitted image sits between the badges' band on top and the zoom bar's below.
        automaticallyAdjustsContentInsets = false
        contentInsets = NSEdgeInsets(top: PreviewMetrics.topBand, left: 0, bottom: PreviewMetrics.bottomBand, right: 0)
        minMagnification = 0.02
        maxMagnification = 16
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged), name: NSView.boundsDidChangeNotification, object: contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(magnificationEnded), name: NSScrollView.didEndLiveMagnifyNotification, object: self)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Preview")
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func boundsChanged() {
        refresh()
    }

    /// Moves the split mask and tells the handle where the image is now.
    private func refresh() {
        document.updateMask()
        guard let onImageRect else { return }
        let inView = convert(document.bounds, from: document).intersection(contentView.frame)
        let rect = inView.isNull ? CGRect.zero
            : CGRect(x: inView.minX, y: isFlipped ? inView.minY : bounds.height - inView.maxY,
                     width: inView.width, height: inView.height)
        // Not during AppKit's layout pass, which can run inside a SwiftUI update.
        DispatchQueue.main.async { onImageRect(rect) }
    }

    @objc private func magnificationEnded() {
        fitted = false
        refresh()
        report()
    }

    func show(before: CGImage?, after: CGImage?, pixelSize: CGSize, identity: String) {
        let changed = identity != self.identity
        self.identity = identity
        document.setImages(before: before, after: after, pixelSize: pixelSize, scale: window?.backingScaleFactor ?? 2)
        if changed || fitted { fit() }
    }

    /// Image points: one image pixel per screen pixel at magnification 1.
    private var imagePointSize: CGSize { document.frame.size }

    private var fitMagnification: CGFloat {
        let size = imagePointSize
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return 1 }
        let width = bounds.width - 2 * PreviewMetrics.sideMargin
        let height = bounds.height - contentInsets.top - contentInsets.bottom
        guard width > 0, height > 0 else { return 1 }
        return min(width / size.width, height / size.height)
    }

    func fit() {
        fitted = true
        magnification = max(minMagnification, fitMagnification)
        refresh()
        report()
    }

    func actualSize() {
        fitted = false
        setMagnification(1, centeredAt: visibleCenter)
        refresh()
        report()
    }

    func zoom(by factor: CGFloat) {
        fitted = false
        let target = min(maxMagnification, max(min(fitMagnification, 1), magnification * factor))
        setMagnification(target, centeredAt: visibleCenter)
        refresh()
        report()
    }

    private var visibleCenter: NSPoint {
        let r = contentView.bounds
        return NSPoint(x: r.midX, y: r.midY)
    }

    private func report() {
        onZoom?(fitted, Double(magnification))
    }

    override func layout() {
        super.layout()
        if fitted { magnification = max(minMagnification, fitMagnification) }
        refresh()
    }

    override func smartMagnify(with event: NSEvent) {
        // Double-tap: toggle between fit and actual size.
        if fitted { actualSize() } else { fit() }
    }
}

/// Keeps a small document centered instead of pinned to the bottom-left corner.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        if rect.width > document.frame.width { rect.origin.x = (document.frame.width - rect.width) / 2 }
        // Centered between the badges' and the zoom bar's bands (the document is flipped,
        // so the bottom inset is at the high end). The bounds are in document units, the
        // insets in points: scale them by the zoom.
        let insets = enclosingScrollView?.contentInsets ?? NSEdgeInsets()
        let zoom = max(enclosingScrollView?.magnification ?? 1, 0.0001)
        let top = insets.top / zoom, bottom = insets.bottom / zoom
        let usable = rect.height - top - bottom
        if usable > document.frame.height { rect.origin.y = (document.frame.height - usable) / 2 - top }
        return rect
    }
}

final class CompareDocumentView: NSView {
    private let beforeLayer = CALayer()
    private let afterLayer = CALayer()
    private let mask = CALayer()
    private(set) var pixelSize: CGSize = .zero
    private var beforeImage: CGImage?
    private var afterImage: CGImage?

    var split: Double? {
        didSet { if split != oldValue { updateMask() } }
    }

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(beforeLayer)
        layer?.addSublayer(afterLayer)
        for l in [beforeLayer, afterLayer] {
            l.contentsGravity = .resize
            l.magnificationFilter = .nearest
            l.minificationFilter = .trilinear
        }
        mask.backgroundColor = NSColor.black.cgColor
        afterLayer.mask = mask
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -2)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func accessibilityIsIgnored() -> Bool { true }

    func setImages(before: CGImage?, after: CGImage?, pixelSize: CGSize, scale: CGFloat) {
        let size = CGSize(width: pixelSize.width / scale, height: pixelSize.height / scale)
        if frame.size != size { setFrameSize(size) }
        self.pixelSize = pixelSize
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if before !== beforeImage { beforeLayer.contents = before; beforeImage = before }
        if after !== afterImage { afterLayer.contents = after; afterImage = after }
        beforeLayer.frame = bounds
        afterLayer.frame = bounds
        CATransaction.commit()
        updateMask()
    }

    /// The result shows right of the split line, which sits at `split` across the
    /// visible part of the image (so it stays put while zooming and scrolling, and stays
    /// on the picture when the picture is narrower than the preview).
    func updateMask() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard afterImage != nil else {
            afterLayer.isHidden = true
            return
        }
        afterLayer.isHidden = false
        guard let split else {
            mask.frame = afterLayer.bounds
            return
        }
        let visible = visibleRect.isEmpty ? bounds : visibleRect
        let x = visible.minX + CGFloat(split) * visible.width
        let clamped = min(max(x, 0), bounds.width)
        mask.frame = CGRect(x: clamped, y: 0, width: max(0, bounds.width - clamped), height: bounds.height)
    }
}
