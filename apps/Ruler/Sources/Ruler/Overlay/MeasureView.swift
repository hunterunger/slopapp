import AppKit
import QuartzCore
import RulerCore
import SlopKit

/// One display's measuring surface, drawn with Core Animation layers so it can update on
/// every mouse move: the frozen screen, placed measurements, the live hover distance, the
/// box being dragged, the crosshair, the magnifier, a key hint and toasts.
///
/// Coordinates: the view is in AppKit points (origin bottom-left). Measurements live in the
/// frozen image's pixels (origin top-left); `pixelPoint`/`localRect` convert.
@MainActor
final class MeasureView: NSView {
    let displayID: CGDirectDisplayID
    private unowned let overlay: MeasureOverlay
    private let testMode: Bool
    private let backingScale: CGFloat
    private let safeTop: CGFloat

    /// The frozen screen, once it arrives.
    var snapshot: CGImage? {
        didSet {
            imageLayer.contents = snapshot
            refresh(force: true)
        }
    }

    /// Its pixels, once decoded (a moment after the snapshot).
    var edges: EdgeImage? {
        didSet { refresh(force: true) }
    }

    var board = Board()
    /// The pointer in view coordinates, or nil when it's on another display.
    var pointer: CGPoint?
    private var drag: SelectionDrag?
    private var dragIsFree = false
    private var dragIsRightButton = false
    private var modifiers: NSEvent.ModifierFlags = []
    private(set) var hoveredItem: BoardItem?
    private(set) var hoverSpans: PixelRect?
    var isDragging: Bool { drag != nil }

    // MARK: Layers

    private let backdrop = CALayer()
    private let imageLayer = CALayer()
    private let boardLayer = CALayer()
    private let hoverHalo = CAShapeLayer()
    private let hoverLine = CAShapeLayer()
    private let hoverWidthBadge = BadgeLayer()
    private let hoverHeightBadge = BadgeLayer()
    private let crossHalo = CAShapeLayer()
    private let crossLine = CAShapeLayer()
    private let dragFill = CAShapeLayer()
    private let dragOutline = CAShapeLayer()
    private let dragBadge = BadgeLayer()
    private let loupe = LoupeLayer()
    private let hintBadge = BadgeLayer()
    private let toastBadge = BadgeLayer()
    private var toastGeneration = 0
    private var drawnBoard: BoardSignature?

    private struct BoardSignature: Equatable {
        var board: Board
        var hovered: BoardItem?
        var unit: MeasureUnit
        var scale: CGFloat
        var accent: NSColor
    }

    static let hint = "Drag to measure   Click: element   ⌘: free box   H V: guides   P: pin   ⇧: crosshair   Return: copy   Right-click: more   Esc: done"

    init(frame: CGRect, screen: NSScreen, overlay: MeasureOverlay, testMode: Bool) {
        displayID = screen.displayID
        self.overlay = overlay
        self.testMode = testMode
        backingScale = screen.backingScaleFactor
        safeTop = max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY)
        super.init(frame: frame)
        wantsLayer = true
        let root = CALayer()
        layer = root
        root.contentsScale = backingScale

        backdrop.frame = bounds
        backdrop.isHidden = !testMode
        imageLayer.frame = bounds
        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .nearest
        boardLayer.frame = bounds
        for halo in [hoverHalo, crossHalo] {
            halo.fillColor = nil
            halo.lineWidth = 3 / backingScale
        }
        for line in [hoverLine, crossLine] {
            line.fillColor = nil
            line.lineWidth = 1 / backingScale
        }
        dragFill.strokeColor = nil
        dragOutline.fillColor = nil
        dragOutline.lineWidth = 1 / backingScale
        dragOutline.lineDashPattern = [4, 3]
        toastBadge.opacity = 0
        hintBadge.text = Self.hint
        let layers: [CALayer] = [backdrop, imageLayer, boardLayer, hoverHalo, hoverLine, crossHalo, crossLine,
                                 dragFill, dragOutline, hoverWidthBadge, hoverHeightBadge, dragBadge, loupe, hintBadge, toastBadge]
        for layer in layers {
            layer.contentsScale = backingScale
            root.addSublayer(layer)
        }
        for badge in [hoverWidthBadge, hoverHeightBadge, dragBadge, hintBadge, toastBadge] { badge.setScale(backingScale) }
        loupe.setScale(backingScale)
        updateColors()

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Measuring overlay")
        setAccessibilityHelp(Self.hint)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
        refresh(force: true)
    }

    private var accent: NSColor { NSColor.controlAccentColor }

    private func cg(_ color: NSColor) -> CGColor {
        var result = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }

    private func updateColors() {
        backdrop.backgroundColor = cg(.underPageBackgroundColor)
        let halo = cg(NSColor.white.withAlphaComponent(0.85))
        let line = cg(accent)
        hoverHalo.strokeColor = halo
        crossHalo.strokeColor = halo
        hoverLine.strokeColor = line
        crossLine.strokeColor = line
        dragOutline.strokeColor = line
        dragFill.fillColor = cg(accent.withAlphaComponent(0.12))
    }

    func releaseImages() {
        snapshot = nil
        edges = nil
        loupe.isHidden = true
        loupe.removeFromSuperlayer()
    }

    // MARK: Geometry

    /// Pixels per point of the frozen image (2 on Retina).
    var scale: CGFloat {
        guard let snapshot, bounds.width > 0 else { return backingScale }
        return CGFloat(snapshot.width) / bounds.width
    }

    var readout: Readout { Readout(scale: Double(scale), unit: overlay.model.unit) }

    private var imageBounds: PixelRect {
        edges?.bounds ?? PixelRect(x: 0, y: 0, width: Int((bounds.width * scale).rounded()), height: Int((bounds.height * scale).rounded()))
    }

    func pixelPoint(local point: CGPoint) -> PixelPoint {
        let b = imageBounds
        let x = Int((point.x * scale).rounded(.down)), y = Int(((bounds.height - point.y) * scale).rounded(.down))
        return PixelPoint(x: min(max(x, 0), b.maxX - 1), y: min(max(y, 0), b.maxY - 1))
    }

    var pointerPixel: PixelPoint? { pointer.map(pixelPoint(local:)) }

    func pixelRect(local rect: CGRect) -> PixelRect {
        PixelRect(minX: Int((rect.minX * scale).rounded()), minY: Int(((bounds.height - rect.maxY) * scale).rounded()),
                  maxX: Int((rect.maxX * scale).rounded()), maxY: Int(((bounds.height - rect.minY) * scale).rounded()))
    }

    private func localX(_ x: Int) -> CGFloat { CGFloat(x) / scale }
    private func localY(_ y: Int) -> CGFloat { bounds.height - CGFloat(y) / scale }

    private func localRect(_ r: PixelRect) -> CGRect {
        CGRect(x: localX(r.minX), y: localY(r.maxY), width: CGFloat(r.width) / scale, height: CGFloat(r.height) / scale)
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
                                       owner: self, userInfo: nil))
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

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
        modifiers = flags
        if drag != nil { drag?.update(to: point, moving: overlay.isSpaceHeld) }
        refresh()
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
            return
        }
        beginDrag(at: convert(event.locationInWindow, from: nil), event: event, right: false)
    }

    override func mouseDragged(with event: NSEvent) {
        pointerMoved(to: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    override func mouseUp(with event: NSEvent) {
        endDrag(at: convert(event.locationInWindow, from: nil))
    }

    override func rightMouseDown(with event: NSEvent) {
        beginDrag(at: convert(event.locationInWindow, from: nil), event: event, right: true)
    }

    override func rightMouseDragged(with event: NSEvent) {
        pointerMoved(to: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    override func rightMouseUp(with event: NSEvent) {
        endDrag(at: convert(event.locationInWindow, from: nil))
    }

    private func beginDrag(at point: CGPoint, event: NSEvent, right: Bool) {
        window?.makeKey()
        pointer = point
        modifiers = event.modifierFlags
        drag = SelectionDrag(anchor: point)
        dragIsRightButton = right
        dragIsFree = right
        refresh()
    }

    private func endDrag(at point: CGPoint) {
        guard var drag else { return }
        drag.update(to: point, moving: overlay.isSpaceHeld)
        let rect = drag.rect(modifiers: selectionModifiers, bounds: bounds)
        let free = dragIsFree || modifiers.contains(.command)
        let right = dragIsRightButton
        self.drag = nil
        pointer = point
        if SelectionGeometry.isUsable(rect) {
            placeArea(drawn: rect, free: free)
        } else if right {
            refresh()
            overlay.showContextMenu(at: point, in: self)
        } else {
            refresh()
            measureElementUnderPointer()
        }
    }

    func cancelDrag() {
        drag = nil
        refresh()
    }

    private var selectionModifiers: SelectionModifiers {
        var result: SelectionModifiers = []
        if modifiers.contains(.shift) { result.insert(.square) }
        if modifiers.contains(.option) { result.insert(.fromCenter) }
        return result
    }

    // MARK: Placing measurements

    /// A box was dragged: snap it to what's inside (unless free) and keep it.
    func placeArea(drawn: CGRect, free: Bool) {
        guard let drawnPixels = pixelRect(local: drawn).intersection(imageBounds) else { return }
        guard !free, let edges else {
            var id = 0
            overlay.change(self) { id = $0.addArea(drawnPixels) }
            areaPlaced(id, snapped: false)
            return
        }
        var id = 0
        overlay.change(self) { id = $0.addArea(drawnPixels, settled: false) }
        let tolerance = overlay.model.tolerance
        let started = Diagnostics.now()
        Task { @MainActor [weak self] in
            let found = await Task.detached(priority: .userInitiated) {
                edges.contentBounds(in: drawnPixels, tolerance: tolerance)
            }.value
            guard let self else { return }
            Diagnostics.record("snap ms=\(Diagnostics.milliseconds(since: started)) pixels=\(drawnPixels.width * drawnPixels.height)")
            guard self.board.settleArea(id, rect: found ?? drawnPixels) else { return }
            self.refresh(force: true)
            self.areaPlaced(id, snapped: found != nil)
        }
    }

    /// A click without dragging: keep the edge-to-edge box under the pointer.
    private func measureElementUnderPointer() {
        if case .area = hoveredItem { return }
        guard let spans = hoverSpans, spans != imageBounds else { return }
        var id = 0
        overlay.change(self) { id = $0.addArea(spans) }
        areaPlaced(id, snapped: true)
    }

    private func areaPlaced(_ id: Int, snapped: Bool) {
        guard let area = board.area(id) else { return }
        let r = area.rect
        Diagnostics.record("area size=\(readout.size(width: r.width, height: r.height)) pixels=\(r.width)x\(r.height) snapped=\(snapped)")
        overlay.announce(readout.spokenSize(width: r.width, height: r.height))
    }

    /// What Return copies: the hovered area or pin, else the last one placed, else the
    /// live hover distance.
    func copyableSize() -> (width: Int, height: Int)? {
        if let hoveredItem, let size = board.size(of: hoveredItem) { return size }
        if let last = board.lastMeasured, let size = board.size(of: last) { return size }
        return hoverSpans.map { ($0.width, $0.height) }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        if !overlay.handleKeyDown(event, in: overlay.pointerView ?? self) { super.keyDown(with: event) }
    }

    override func keyUp(with event: NSEvent) {
        overlay.handleKeyUp(event)
    }

    override func flagsChanged(with event: NSEvent) {
        modifiers = event.modifierFlags
        overlay.pointerView?.modifiersChanged(event.modifierFlags)
        refresh()
    }

    func modifiersChanged(_ flags: NSEvent.ModifierFlags) {
        modifiers = flags
        refresh()
    }

    override func cancelOperation(_ sender: Any?) {
        if isDragging { cancelDrag() } else { overlay.close() }
    }

    // MARK: Toast

    func showToast(_ message: String) {
        toastGeneration += 1
        let generation = toastGeneration
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        toastBadge.text = message
        let size = toastBadge.preferredFrameSize()
        let hintTop = hintBadge.isHidden ? bounds.minY + 24 : hintBadge.frame.maxY
        let y = hintBadge.frame.minY > bounds.midY ? hintBadge.frame.minY - 12 - size.height : hintTop + 12
        toastBadge.frame = CGRect(x: (bounds.midX - size.width / 2).rounded(), y: y.rounded(), width: size.width, height: size.height)
        toastBadge.removeAllAnimations()
        toastBadge.opacity = 1
        CATransaction.commit()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard let self, self.toastGeneration == generation else { return }
            self.toastBadge.opacity = 0 // implicit fade
        }
    }

    // MARK: Drawing

    /// Re-lays out the layers for the current state. `force` also redraws placed items.
    func refresh(force: Bool = false) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let model = overlay.model
        let pixel = pointerPixel
        let slop = Int((3 * scale).rounded())
        hoveredItem = drag == nil ? pixel.flatMap { board.item(at: $0, slop: slop) } : nil
        if let pixel, let edges {
            hoverSpans = edges.spans(at: pixel, tolerance: model.tolerance, limits: board.limits(for: pixel, in: edges.bounds))
        } else {
            hoverSpans = nil
        }

        let signature = BoardSignature(board: board, hovered: hoveredItem, unit: model.unit, scale: scale, accent: accent)
        if force || signature != drawnBoard {
            drawBoard()
            drawnBoard = signature
        }

        let showCrosshair = drag == nil && modifiers.contains(.shift) && pixel != nil && edges != nil
        drawCrosshair(showCrosshair ? pixel : nil)
        drawHover(showCrosshair || drag != nil ? nil : hoverSpans, at: pixel)
        drawDrag()
        updateLoupe(pixel)
        layoutHint()
        updateAccessibility()
    }

    private func dimensionPath(_ spans: PixelRect, at point: PixelPoint, horizontal: Bool, vertical: Bool) -> CGPath {
        let path = CGMutablePath()
        let half = 0.5 / scale
        let tick: CGFloat = 4
        let cy = localY(point.y) - half, cx = localX(point.x) + half
        if horizontal {
            let x0 = localX(spans.minX) + half, x1 = localX(spans.maxX) - half
            path.move(to: CGPoint(x: x0, y: cy)); path.addLine(to: CGPoint(x: x1, y: cy))
            for x in [x0, x1] { path.move(to: CGPoint(x: x, y: cy - tick)); path.addLine(to: CGPoint(x: x, y: cy + tick)) }
        }
        if vertical {
            let y0 = localY(spans.minY) - half, y1 = localY(spans.maxY) + half
            path.move(to: CGPoint(x: cx, y: y0)); path.addLine(to: CGPoint(x: cx, y: y1))
            for y in [y0, y1] { path.move(to: CGPoint(x: cx - tick, y: y)); path.addLine(to: CGPoint(x: cx + tick, y: y)) }
        }
        return path
    }

    private func spanText(_ length: Int, start: Int, end: Int, limit: Int) -> String {
        let touchesEdge = (start == 0) != (end == limit)
        return readout.length(length) + (touchesEdge ? " to edge" : "")
    }

    /// Puts the width label above the horizontal line and the height label beside the
    /// vertical one, keeping both on screen and off each other.
    private func placeSpanLabels(_ spans: PixelRect, at point: PixelPoint, width: BadgeLayer, height: BadgeLayer) {
        let limits = imageBounds
        width.text = spanText(spans.width, start: spans.minX, end: spans.maxX, limit: limits.maxX)
        height.text = spanText(spans.height, start: spans.minY, end: spans.maxY, limit: limits.maxY)
        let cy = localY(point.y), cx = localX(point.x)
        let area = bounds.insetBy(dx: 4, dy: 4).divided(atDistance: safeTop, from: .maxYEdge).remainder
        let ws = width.preferredFrameSize(), hs = height.preferredFrameSize()
        let midX = (localX(spans.minX) + localX(spans.maxX)) / 2
        var wf = CGRect(x: midX - ws.width / 2, y: cy + 6, width: ws.width, height: ws.height)
        if wf.maxY > area.maxY { wf.origin.y = cy - 6 - ws.height }
        let midY = (localY(spans.minY) + localY(spans.maxY)) / 2
        var hf = CGRect(x: cx + 8, y: midY - hs.height / 2, width: hs.width, height: hs.height)
        if hf.maxX > area.maxX { hf.origin.x = cx - 8 - hs.width }
        wf = clamp(wf, to: area)
        hf = clamp(hf, to: area)
        if wf.intersects(hf) {
            hf.origin.y = wf.minY > cy ? cy - 8 - hs.height : cy + 8
            hf = clamp(hf, to: area)
        }
        width.frame = wf.integral
        height.frame = hf.integral
    }

    private func clamp(_ rect: CGRect, to area: CGRect) -> CGRect {
        var r = rect
        r.origin.x = min(max(r.minX, area.minX), area.maxX - r.width)
        r.origin.y = min(max(r.minY, area.minY), area.maxY - r.height)
        return r
    }

    private func drawHover(_ spans: PixelRect?, at point: PixelPoint?) {
        guard let spans, let point else {
            hoverHalo.path = nil
            hoverLine.path = nil
            hoverWidthBadge.isHidden = true
            hoverHeightBadge.isHidden = true
            return
        }
        let path = dimensionPath(spans, at: point, horizontal: true, vertical: true)
        hoverHalo.path = path
        hoverLine.path = path
        hoverWidthBadge.isHidden = false
        hoverHeightBadge.isHidden = false
        placeSpanLabels(spans, at: point, width: hoverWidthBadge, height: hoverHeightBadge)
    }

    private func drawCrosshair(_ point: PixelPoint?) {
        guard let point else {
            crossHalo.path = nil
            crossLine.path = nil
            return
        }
        let path = CGMutablePath()
        let half = 0.5 / scale
        path.move(to: CGPoint(x: 0, y: localY(point.y) - half)); path.addLine(to: CGPoint(x: bounds.maxX, y: localY(point.y) - half))
        path.move(to: CGPoint(x: localX(point.x) + half, y: 0)); path.addLine(to: CGPoint(x: localX(point.x) + half, y: bounds.maxY))
        crossHalo.path = path
        crossLine.path = path
    }

    private func drawDrag() {
        guard let drag else {
            dragFill.path = nil
            dragOutline.path = nil
            dragBadge.isHidden = true
            return
        }
        let rect = drag.rect(modifiers: selectionModifiers, bounds: bounds)
        dragFill.path = CGPath(rect: rect, transform: nil)
        dragOutline.path = CGPath(rect: rect.insetBy(dx: -0.5 / scale, dy: -0.5 / scale), transform: nil)
        let pixels = pixelRect(local: rect)
        let free = dragIsFree || modifiers.contains(.command)
        dragBadge.text = readout.size(width: pixels.width, height: pixels.height) + (free ? "" : "  ·  snaps on release")
        let size = dragBadge.preferredFrameSize()
        dragBadge.frame = CGRect(origin: SelectionGeometry.labelOrigin(size: size, for: rect, bounds: bounds), size: size).integral
        dragBadge.isHidden = false
    }

    private func drawBoard() {
        boardLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        let halo = cg(NSColor.white.withAlphaComponent(0.85))
        let line = cg(accent)
        let px = 1 / scale

        func stroke(_ path: CGPath, width: CGFloat, color: CGColor, dash: [NSNumber]? = nil) {
            let layer = CAShapeLayer()
            layer.contentsScale = backingScale
            layer.path = path
            layer.fillColor = nil
            layer.strokeColor = color
            layer.lineWidth = width
            layer.lineDashPattern = dash
            boardLayer.addSublayer(layer)
        }
        func badge(_ text: String) -> BadgeLayer {
            let b = BadgeLayer()
            b.setScale(backingScale)
            b.text = text
            boardLayer.addSublayer(b)
            return b
        }

        // Guides, then the gaps between neighbouring guides.
        for guide in board.guides {
            let hovered = hoveredItem == .guide(guide.id)
            let path = CGMutablePath()
            switch guide.axis {
            case .vertical:
                let x = localX(guide.position)
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: bounds.maxY))
            case .horizontal:
                let y = localY(guide.position)
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: bounds.maxX, y: y))
            }
            stroke(path, width: 3 * px, color: halo)
            stroke(path, width: (hovered ? 2 : 1) * px, color: line, dash: hovered ? nil : [6, 3])
        }
        for axis in [GuideAxis.vertical, .horizontal] {
            for gap in board.guideGaps(axis) {
                let path = CGMutablePath()
                let b: BadgeLayer
                if axis == .vertical {
                    let y = bounds.maxY - safeTop - 28
                    path.move(to: CGPoint(x: localX(gap.start), y: y)); path.addLine(to: CGPoint(x: localX(gap.end), y: y))
                    b = badge(readout.length(gap.end - gap.start))
                    let s = b.preferredFrameSize()
                    b.frame = CGRect(x: (localX(gap.start) + localX(gap.end)) / 2 - s.width / 2, y: y - s.height - 4, width: s.width, height: s.height).integral
                } else {
                    let x: CGFloat = 28
                    path.move(to: CGPoint(x: x, y: localY(gap.start))); path.addLine(to: CGPoint(x: x, y: localY(gap.end)))
                    b = badge(readout.length(gap.end - gap.start))
                    let s = b.preferredFrameSize()
                    b.frame = CGRect(x: x + 6, y: (localY(gap.start) + localY(gap.end)) / 2 - s.height / 2, width: s.width, height: s.height).integral
                }
                stroke(path, width: 3 * px, color: halo)
                stroke(path, width: px, color: line)
                boardLayer.addSublayer(b) // above its line
            }
        }

        // Areas: a tinted box with a crisp outline just outside it, and its size.
        for area in board.areas {
            let hovered = hoveredItem == .area(area.id)
            let rect = localRect(area.rect)
            let fill = CAShapeLayer()
            fill.path = CGPath(rect: rect, transform: nil)
            fill.fillColor = cg(accent.withAlphaComponent(hovered ? 0.22 : 0.12))
            boardLayer.addSublayer(fill)
            let outline = (hovered ? 2 : 1) * px
            stroke(CGPath(rect: rect.insetBy(dx: -outline - px / 2 - px, dy: -outline - px / 2 - px), transform: nil), width: px, color: halo)
            stroke(CGPath(rect: rect.insetBy(dx: -outline / 2, dy: -outline / 2), transform: nil), width: outline,
                   color: line, dash: area.isSettled ? nil : [4, 3])
            let b = badge(readout.size(width: area.rect.width, height: area.rect.height))
            let s = b.preferredFrameSize()
            b.frame = CGRect(origin: SelectionGeometry.labelOrigin(size: s, for: rect, bounds: bounds), size: s).integral
        }

        // Pinned distances look like the live one.
        for pin in board.pins {
            let hovered = hoveredItem == .pin(pin.id)
            let path = dimensionPath(pin.spans, at: pin.point, horizontal: true, vertical: true)
            stroke(path, width: 3 * px, color: halo)
            stroke(path, width: (hovered ? 2 : 1) * px, color: line)
            let w = badge(""), h = badge("")
            placeSpanLabels(pin.spans, at: pin.point, width: w, height: h)
        }
    }

    private func updateLoupe(_ pixel: PixelPoint?) {
        guard overlay.model.showMagnifier, let pixel, let pointer, let snapshot, drag == nil else {
            loupe.isHidden = true
            return
        }
        if loupe.superlayer == nil { layer?.insertSublayer(loupe, below: hintBadge) }
        loupe.isHidden = false
        loupe.show(image: snapshot, centerPixel: CGPoint(x: pixel.x, y: pixel.y),
                   pointLabel: "\(readout.number(pixel.x)), \(readout.number(pixel.y))")
        let size = loupe.preferredFrameSize()
        loupe.frame = CGRect(origin: SelectionGeometry.magnifierOrigin(size: size, pointer: pointer, bounds: bounds, offset: 40), size: size)
    }

    private func layoutHint() {
        hintBadge.isHidden = pointer == nil || drag != nil
        let size = hintBadge.preferredFrameSize()
        var y: CGFloat = 28
        if let pointer, pointer.y < y + size.height + 90 { y = bounds.maxY - safeTop - 36 - size.height }
        hintBadge.frame = CGRect(x: (bounds.midX - size.width / 2).rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    private func updateAccessibility() {
        guard pointer != nil else { return }
        var parts: [String] = []
        if edges == nil {
            parts.append("Freezing the screen")
        } else if let s = hoverSpans {
            parts.append("Horizontal \(readout.length(s.width)), vertical \(readout.length(s.height))")
        }
        if !board.areas.isEmpty {
            parts.append("Areas: " + board.areas.map { readout.size(width: $0.rect.width, height: $0.rect.height) }.joined(separator: ", "))
        }
        if !board.pins.isEmpty {
            parts.append("Pinned: " + board.pins.map { readout.size(width: $0.spans.width, height: $0.spans.height) }.joined(separator: ", "))
        }
        if !board.guides.isEmpty { parts.append("\(board.guides.count) guides") }
        parts.append("Edge tolerance \(overlay.model.tolerance.title)")
        setAccessibilityValue(parts.joined(separator: ". "))
    }
}
