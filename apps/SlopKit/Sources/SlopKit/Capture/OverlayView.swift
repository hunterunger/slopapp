import AppKit
import QuartzCore

/// Draws one display's overlay with Core Animation layers (cheap to update on every mouse
/// move): the frozen screen, the dimming with a hole for the selection, the selection
/// outline, the size readout, the magnifier and a one-line hint.
@MainActor
final class OverlayView: NSView {
    let displayID: CGDirectDisplayID
    private unowned let overlay: RegionOverlay

    /// The frozen screen, once it arrives.
    var snapshot: CGImage? {
        didSet {
            imageLayer.contents = snapshot
            refresh()
        }
    }

    /// The pointer in view coordinates, or nil when it's on another display.
    var pointer: CGPoint?
    private(set) var drag: SelectionDrag?
    private var modifiers: SelectionModifiers = []
    private(set) var hoveredWindow: WindowInfo?
    var isDragging: Bool { drag != nil }

    private let imageLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let outlineLayer = CAShapeLayer()
    private let highlightLayer = CAShapeLayer()
    private let sizeBadge = BadgeLayer()
    private let hintBadge = BadgeLayer()
    private let loupe = LoupeLayer()

    init(frame: CGRect, screen: NSScreen, overlay: RegionOverlay) {
        displayID = screen.displayID
        self.overlay = overlay
        super.init(frame: frame)
        wantsLayer = true
        let root = CALayer()
        layer = root
        let scale = screen.backingScaleFactor
        root.contentsScale = scale

        imageLayer.frame = bounds
        imageLayer.contentsGravity = .resize
        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.35).cgColor
        outlineLayer.fillColor = nil
        outlineLayer.strokeColor = NSColor.white.cgColor
        outlineLayer.lineWidth = 1
        outlineLayer.shadowColor = NSColor.black.cgColor
        outlineLayer.shadowOpacity = 0.6
        outlineLayer.shadowRadius = 1
        outlineLayer.shadowOffset = .zero
        highlightLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        highlightLayer.strokeColor = NSColor.controlAccentColor.cgColor
        highlightLayer.lineWidth = 3
        for layer in [imageLayer, dimLayer, highlightLayer, outlineLayer, sizeBadge, hintBadge, loupe] as [CALayer] {
            layer.contentsScale = scale
            root.addSublayer(layer)
        }
        sizeBadge.setScale(scale)
        hintBadge.setScale(scale)
        loupe.setScale(scale)
        modeChanged()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Capture overlay")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
                                       owner: self, userInfo: nil))
    }

    private var cursor: NSCursor { overlay.mode == .area ? .crosshair : .arrow }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor.set()
    }

    func modeChanged() {
        drag = nil
        hintBadge.text = overlay.mode == .area
            ? "Drag to capture   Shift: square   Option: from center   Space: window   Return: whole screen   Esc: cancel"
            : "Click a window to capture it   Return: highlighted window   Space: drag an area instead   Esc: cancel"
        window?.invalidateCursorRects(for: self)
        cursor.set()
    }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) {
        pointerMoved(to: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    override func mouseEntered(with event: NSEvent) {
        window?.makeKey()
        pointerMoved(to: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    override func mouseExited(with event: NSEvent) {
        guard drag == nil else { return }
        pointer = nil
        refresh()
    }

    func pointerMoved(to point: CGPoint, modifiers flags: NSEvent.ModifierFlags) {
        pointer = point
        cursor.set()
        if drag != nil {
            drag?.update(to: point, moving: overlay.isSpaceHeld)
            modifiers = Self.selectionModifiers(flags)
        }
        refresh()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch overlay.mode {
        case .area:
            drag = SelectionDrag(anchor: point)
            modifiers = Self.selectionModifiers(event.modifierFlags)
            refresh()
        case .window:
            // Pick at the click itself: the pointer may jump here without any mouse-moved
            // event (scripted input, a warp), so don't rely on the last hover.
            pointer = point
            refresh()
            if let window = hoveredWindow { overlay.completeWindow(window) }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        pointerMoved(to: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    override func mouseUp(with event: NSEvent) {
        guard let drag else { return }
        let rect = drag.rect(modifiers: modifiers, bounds: bounds)
        self.drag = nil
        if SelectionGeometry.isUsable(rect) {
            overlay.completeArea(rect, in: self)
        } else {
            refresh()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        overlay.cancel()
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        if !overlay.handleKeyDown(event) { super.keyDown(with: event) }
    }

    override func keyUp(with event: NSEvent) {
        overlay.handleKeyUp(event)
    }

    override func flagsChanged(with event: NSEvent) {
        modifiers = Self.selectionModifiers(event.modifierFlags)
        refresh()
    }

    override func cancelOperation(_ sender: Any?) {
        overlay.cancel()
    }

    static func selectionModifiers(_ flags: NSEvent.ModifierFlags) -> SelectionModifiers {
        var result: SelectionModifiers = []
        if flags.contains(.shift) { result.insert(.square) }
        if flags.contains(.option) { result.insert(.fromCenter) }
        return result
    }

    // MARK: Drawing

    /// Re-lays out every layer for the current state.
    func refresh() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        var hole: CGRect?
        hoveredWindow = nil
        highlightLayer.path = nil
        outlineLayer.path = nil
        switch overlay.mode {
        case .area:
            if let drag {
                let rect = drag.rect(modifiers: modifiers, bounds: bounds)
                hole = rect
                outlineLayer.path = CGPath(rect: rect.insetBy(dx: -0.5, dy: -0.5), transform: nil)
            }
        case .window:
            if let pointer, let window = window, let found = overlay.window(atGlobal: window.convertPoint(toScreen: pointer)) {
                hoveredWindow = found
                let local = ScreenCoordinates.local(fromQuartz: found.frame, screenFrame: window.frame, primaryHeight: NSScreen.primaryHeight)
                    .intersection(bounds)
                hole = local
                highlightLayer.path = CGPath(rect: local.insetBy(dx: 1.5, dy: 1.5), transform: nil)
            }
        }

        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let hole, !hole.isEmpty { dim.addRect(hole) }
        dimLayer.path = dim

        // Size readout: the selection, or the highlighted window.
        if let hole, !hole.isEmpty {
            sizeBadge.text = SelectionGeometry.sizeLabel(hole)
            let size = sizeBadge.preferredFrameSize()
            sizeBadge.frame = CGRect(origin: SelectionGeometry.labelOrigin(size: size, for: hole, bounds: bounds), size: size)
            sizeBadge.isHidden = false
        } else {
            sizeBadge.isHidden = true
        }

        // Key hint near the top of the screen (below the menu bar area), hidden while dragging
        // so it never covers what you aim at.
        hintBadge.isHidden = pointer == nil || drag != nil
        let hintSize = hintBadge.preferredFrameSize()
        hintBadge.frame = CGRect(x: (bounds.midX - hintSize.width / 2).rounded(), y: bounds.maxY - 64 - hintSize.height,
                                 width: hintSize.width, height: hintSize.height)

        updateLoupe()
    }

    private func updateLoupe() {
        guard overlay.options.showsMagnifier, overlay.mode == .area, let pointer, let snapshot else {
            loupe.isHidden = true
            return
        }
        loupe.isHidden = false
        let scale = CGFloat(snapshot.width) / max(bounds.width, 1)
        let pixel = ScreenCoordinates.pixelPoint(local: pointer, screenSize: bounds.size, scale: scale)
        loupe.show(image: snapshot, centerPixel: pixel, pointLabel: "\(Int(pointer.x)), \(Int(bounds.height - pointer.y))")
        let size = loupe.preferredFrameSize()
        loupe.frame = CGRect(origin: SelectionGeometry.magnifierOrigin(size: size, pointer: pointer, bounds: bounds), size: size)
    }
}

/// A small dark rounded label (size readout, hint). Reusable in other overlays.
public final class BadgeLayer: CALayer {
    private let textLayer = CATextLayer()
    private let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .callout).pointSize, weight: .medium)

    override public init() {
        super.init()
        backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        cornerRadius = 7
        cornerCurve = .continuous
        textLayer.font = font
        textLayer.fontSize = font.pointSize
        textLayer.foregroundColor = NSColor.white.cgColor
        textLayer.alignmentMode = .center
        addSublayer(textLayer)
    }

    override public init(layer: Any) { super.init(layer: layer) }
    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public func setScale(_ scale: CGFloat) {
        contentsScale = scale
        textLayer.contentsScale = scale
    }

    public var text: String = "" {
        didSet { textLayer.string = text }
    }

    override public func preferredFrameSize() -> CGSize {
        let size = (text as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(size.width) + 16, height: ceil(size.height) + 8)
    }

    override public func layoutSublayers() {
        super.layoutSublayers()
        textLayer.frame = bounds.insetBy(dx: 8, dy: 4)
    }
}

/// The magnifier: a zoomed, pixel-sharp view of the frozen screen around the pointer, with
/// the pixel under it outlined and its position (points from the top-left) below.
public final class LoupeLayer: CALayer {
    public static let cells = 21
    public static let cellSize: CGFloat = 6
    private let zoomed = CALayer()
    private let marker = CALayer()
    private let label = BadgeLayer()

    override public init() {
        super.init()
        let side = CGFloat(Self.cells) * Self.cellSize
        zoomed.frame = CGRect(x: 0, y: 30, width: side, height: side)
        zoomed.magnificationFilter = .nearest
        zoomed.cornerRadius = 12
        zoomed.cornerCurve = .continuous
        zoomed.masksToBounds = true
        zoomed.borderWidth = 2
        zoomed.borderColor = NSColor.white.cgColor
        zoomed.backgroundColor = NSColor.black.cgColor
        marker.borderWidth = 1.5
        marker.borderColor = NSColor.white.cgColor
        marker.shadowColor = NSColor.black.cgColor
        marker.shadowOpacity = 0.8
        marker.shadowRadius = 1
        marker.shadowOffset = .zero
        shadowColor = NSColor.black.cgColor
        shadowOpacity = 0.35
        shadowRadius = 6
        shadowOffset = CGSize(width: 0, height: -2)
        addSublayer(zoomed)
        zoomed.addSublayer(marker)
        addSublayer(label)
    }

    override public init(layer: Any) { super.init(layer: layer) }
    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public func setScale(_ scale: CGFloat) {
        contentsScale = scale
        zoomed.contentsScale = scale
        marker.contentsScale = scale
        label.setScale(scale)
    }

    override public func preferredFrameSize() -> CGSize {
        CGSize(width: CGFloat(Self.cells) * Self.cellSize, height: CGFloat(Self.cells) * Self.cellSize + 30)
    }

    /// Shows the pixels around `centerPixel` (image pixels, top-left origin).
    public func show(image: CGImage, centerPixel: CGPoint, pointLabel: String) {
        let n = Self.cells
        let half = n / 2
        var originX = Int(centerPixel.x) - half, originY = Int(centerPixel.y) - half
        originX = min(max(originX, 0), max(image.width - n, 0))
        originY = min(max(originY, 0), max(image.height - n, 0))
        let sample = CGRect(x: originX, y: originY, width: min(n, image.width), height: min(n, image.height))
        zoomed.contents = image.cropping(to: sample)
        // The marker sits on the pointer's pixel even when the sample is clamped at an edge.
        let column = Int(centerPixel.x) - originX, row = Int(centerPixel.y) - originY
        let cell = Self.cellSize
        let side = CGFloat(n) * cell
        marker.frame = CGRect(x: CGFloat(column) * cell, y: side - CGFloat(row + 1) * cell, width: cell, height: cell)
        label.text = pointLabel
        let size = label.preferredFrameSize()
        label.frame = CGRect(x: (side - size.width) / 2, y: 0, width: size.width, height: size.height)
    }
}
