import AppKit
import QuartzCore
import RulerCore
import SlopKit

/// One display's measuring surface, drawn with Core Animation layers so it can update on
/// every mouse move: the frozen screen, placed measurements, the live hover distance, the
/// box being dragged, the crosshair, the magnifier, a key hint and toasts.
///
/// Labels follow one rule each, so they never pile up: the live readout is a single
/// "W × H" pill down-right of the pointer; an area's size sits in its middle; a held
/// distance's number sits on its line; the magnifier takes a corner clear of all of them.
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
    /// In the background the measurements stay on screen over the live display; nothing
    /// else is drawn.
    private(set) var isBackground = false

    private enum Gesture {
        /// Drawing a new box.
        case box(SelectionDrag, free: Bool, right: Bool)
        /// Dragging a placed area's side or corner.
        case resize(id: Int, handle: AreaHandle, original: PixelRect)
        /// Dragging a guide.
        case guide(id: Int, axis: GuideAxis, original: Int)
    }

    private var gesture: Gesture?
    private var modifiers: NSEvent.ModifierFlags = []
    private(set) var hoveredItem: BoardItem?
    private(set) var hoveredHandle: (id: Int, handle: AreaHandle)?
    private(set) var hoverSpans: PixelRect?
    var isDragging: Bool { gesture != nil }
    private var isBoxDrag: Bool { if case .box = gesture { true } else { false } }

    // MARK: Layers

    private let backdrop = CALayer()
    private let imageLayer = CALayer()
    private let boardLayer = CALayer()
    /// The board's labels, above every line (the live hover lines included) so no line ever
    /// runs through a number; below the live pill and the magnifier.
    private let boardLabelLayer = CALayer()
    private let hoverHalo = CAShapeLayer()
    private let hoverLine = CAShapeLayer()
    private let hoverPill = BadgeLayer()
    private let crossHalo = CAShapeLayer()
    private let crossLine = CAShapeLayer()
    private let dragFill = CAShapeLayer()
    private let dragOutline = CAShapeLayer()
    private let dragBadge = BadgeLayer()
    private let loupe = LoupeLayer()
    private let hintBadge = BadgeLayer()
    private let statusBadge = BadgeLayer()
    private let toastBadge = BadgeLayer()
    private var toastGeneration = 0
    private var accentObserver: NSObjectProtocol?
    private var drawnBoard: BoardSignature?
    /// Frames of the board's labels, so the magnifier can stay clear of them.
    private var boardLabelFrames: [CGRect] = []
    /// Set while drawing a screenshot: no hover highlight.
    private var isRenderingScreenshot = false

    private struct BoardSignature: Equatable {
        var board: Board
        var hovered: BoardItem?
        var unit: MeasureUnit
        var scale: CGFloat
        var color: NSColor
        var designScale: Double
        var showUnits: Bool
        var ratio: AspectRatioStyle?
        var hasPixels: Bool
    }

    static let hint = "Drag: measure   Click: element   H V: guides   P: hold   ⇧: crosshair   S C: screenshot   Return: copy   Right-click: more   ?: hide   Esc: done"

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
        boardLabelLayer.frame = bounds
        // Hover lines are filled pixel rects (CrispStroke), so they're crisp at any scale.
        hoverHalo.strokeColor = nil
        hoverLine.strokeColor = nil
        crossHalo.fillColor = nil
        crossLine.fillColor = nil
        crossLine.lineWidth = 1 / backingScale
        crossHalo.lineWidth = 3 / backingScale
        dragFill.strokeColor = nil
        dragOutline.fillColor = nil
        dragOutline.lineWidth = 1
        dragOutline.lineDashPattern = [4, 3]
        toastBadge.opacity = 0
        hintBadge.text = Self.hint
        let layers: [CALayer] = [backdrop, imageLayer, boardLayer, crossHalo, crossLine, hoverHalo, hoverLine,
                                 dragFill, dragOutline, boardLabelLayer, hoverPill, dragBadge, loupe, statusBadge, hintBadge, toastBadge]
        for layer in layers {
            layer.contentsScale = backingScale
            root.addSublayer(layer)
        }
        for badge in [hoverPill, dragBadge, hintBadge, statusBadge, toastBadge] { badge.outlined(scale: backingScale) }
        loupe.setScale(backingScale)
        updateColors()

        // The accent (and system colours) can change while measuring; redraw in the new ones.
        accentObserver = NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateColors()
                self?.refresh(force: true)
            }
        }

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

    private var model: AppModel { overlay.model }
    private var lineColor: NSColor { model.lineColor.color }

    /// A colour for this view's own appearance (the test-mode backdrop only).
    private func cg(_ color: NSColor) -> CGColor {
        var result = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }

    /// A colour for the measuring chrome. It sits on arbitrary screen content, so like
    /// SlopKit's `OverlayPalette` it uses the dark appearance's system colours and looks the
    /// same in light and dark mode.
    private func overlay(_ color: NSColor) -> CGColor {
        var result = color.cgColor
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }

    private func updateColors() {
        backdrop.backgroundColor = cg(.underPageBackgroundColor)
        let line = overlay(lineColor)
        hoverLine.fillColor = line
        crossLine.strokeColor = line
        dragOutline.strokeColor = line
        dragFill.fillColor = overlay(lineColor.withAlphaComponent(0.12))
    }

    /// A halo that separates lines from what's under them: light on light pixels, dark on
    /// dark ones (where the line color already stands out). From `OverlayPalette`, never
    /// pure white or black.
    private func halo(at pixel: PixelPoint?) -> CGColor {
        let light = OverlayPalette.paper.cgColor
        guard let pixel, let c = edges?.color(at: pixel) else { return light }
        let luminance = 0.299 * Double(c.r) + 0.587 * Double(c.g) + 0.114 * Double(c.b)
        return luminance < 60 ? OverlayPalette.ink.withAlphaComponent(0.5).cgColor : light
    }

    func releaseImages() {
        if let accentObserver { NotificationCenter.default.removeObserver(accentObserver) }
        accentObserver = nil
        snapshot = nil
        edges = nil
        loupe.isHidden = true
        loupe.removeFromSuperlayer()
    }

    // MARK: Background mode

    /// Keeps only the measurements, over the live screen, and lets clicks through.
    func enterBackground() {
        gesture = nil
        pointer = nil
        isBackground = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.isHidden = true
        imageLayer.isHidden = true
        CATransaction.commit()
        snapshot = nil
        edges = nil
        refresh(force: true)
    }

    func leaveBackground() {
        isBackground = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.isHidden = !testMode
        imageLayer.isHidden = false
        CATransaction.commit()
        refresh(force: true)
    }

    // MARK: Geometry

    /// Pixels per point of the frozen image (2 on Retina).
    var scale: CGFloat {
        guard let snapshot, bounds.width > 0 else { return backingScale }
        return CGFloat(snapshot.width) / bounds.width
    }

    var readout: Readout {
        Readout(scale: Double(scale), unit: model.unit, designScale: model.designScale, showsUnit: model.showUnits)
    }

    var imageBounds: PixelRect {
        edges?.bounds ?? PixelRect(x: 0, y: 0, width: Int((bounds.width * scale).rounded()), height: Int((bounds.height * scale).rounded()))
    }

    func pixelPoint(local point: CGPoint) -> PixelPoint {
        let b = imageBounds
        let x = Int((point.x * scale).rounded(.down)), y = Int(((bounds.height - point.y) * scale).rounded(.down))
        return PixelPoint(x: min(max(x, 0), b.maxX - 1), y: min(max(y, 0), b.maxY - 1))
    }

    /// The pixel boundary nearest a point (for dragging sides and guides).
    private func boundary(local point: CGPoint) -> PixelPoint {
        let b = imageBounds
        let x = Int((point.x * scale).rounded()), y = Int(((bounds.height - point.y) * scale).rounded())
        return PixelPoint(x: min(max(x, 0), b.maxX), y: min(max(y, 0), b.maxY))
    }

    var pointerPixel: PixelPoint? { pointer.map(pixelPoint(local:)) }

    func pixelRect(local rect: CGRect) -> PixelRect {
        PixelRect(minX: Int((rect.minX * scale).rounded()), minY: Int(((bounds.height - rect.maxY) * scale).rounded()),
                  maxX: Int((rect.maxX * scale).rounded()), maxY: Int(((bounds.height - rect.minY) * scale).rounded()))
    }

    private func localX(_ x: Int) -> CGFloat { CGFloat(x) / scale }
    private func localY(_ y: Int) -> CGFloat { bounds.height - CGFloat(y) / scale }

    func localRect(_ r: PixelRect) -> CGRect {
        CGRect(x: localX(r.minX), y: localY(r.maxY), width: CGFloat(r.width) / scale, height: CGFloat(r.height) / scale)
    }

    /// Where labels may go: the display minus the menu bar / notch strip.
    private var labelArea: CGRect {
        bounds.insetBy(dx: 4, dy: 4).divided(atDistance: safeTop, from: .maxYEdge).remainder
    }

    private var slop: Int { Int((4 * scale).rounded()) }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
                                       owner: self, userInfo: nil))
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func cursorUpdate(with event: NSEvent) { currentCursor.set() }

    /// Crosshair, or a resize cursor over an area's side or corner and over guides.
    private var currentCursor: NSCursor {
        if isBackground { return .arrow }
        let handle: AreaHandle?
        switch gesture {
        case .resize(_, let h, _): handle = h
        case .guide(_, let axis, _): return axis == .vertical ? .resizeLeftRight : .resizeUpDown
        case .box: return .crosshair
        case nil:
            if modifiers.contains(.command) { return .crosshair }
            if case .guide(let id) = hoveredItem, let guide = board.guide(id) {
                return guide.axis == .vertical ? .resizeLeftRight : .resizeUpDown
            }
            handle = hoveredHandle?.handle
        }
        guard let handle else { return .crosshair }
        if !handle.isCorner { return handle.movesLeft || handle.movesRight ? .resizeLeftRight : .resizeUpDown }
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition = switch handle {
            case .topLeft: .topLeft
            case .topRight: .topRight
            case .bottomLeft: .bottomLeft
            default: .bottomRight
            }
            return .frameResize(position: position, directions: .all)
        }
        return .crosshair
    }

    override func mouseMoved(with event: NSEvent) {
        pointerMoved(to: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    override func mouseEntered(with event: NSEvent) {
        window?.makeKey()
        pointerMoved(to: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    override func mouseExited(with event: NSEvent) {
        guard gesture == nil else { return }
        pointer = nil
        refresh()
    }

    func pointerMoved(to point: CGPoint, modifiers flags: NSEvent.ModifierFlags) {
        pointer = point
        modifiers = flags
        switch gesture {
        case .box(var drag, let free, let right):
            drag.update(to: point, moving: overlay.isSpaceHeld)
            gesture = .box(drag, free: free, right: right)
        case .resize(let id, let handle, let original):
            let rect = handle.resize(original, to: boundary(local: point), keepAspect: flags.contains(.shift), minimum: max(1, Int(scale.rounded())))
            board.resizeArea(id, to: rect)
            refresh(force: true)
        case .guide(let id, let axis, _):
            let b = boundary(local: point)
            board.moveGuide(id, to: axis == .vertical ? b.x : b.y)
            refresh(force: true)
        case nil:
            break
        }
        refresh()
        currentCursor.set()
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        window?.makeKey()
        pointer = point
        modifiers = event.modifierFlags
        let pixel = pixelPoint(local: point)
        if !modifiers.contains(.command) {
            if let (id, handle) = board.handle(at: pixel, slop: slop), let area = board.area(id) {
                overlay.recordUndo(self)
                gesture = .resize(id: id, handle: handle, original: area.rect)
                refresh()
                return
            }
            if case .guide(let id) = board.item(at: pixel, slop: slop), let guide = board.guide(id) {
                overlay.recordUndo(self)
                gesture = .guide(id: id, axis: guide.axis, original: guide.position)
                refresh()
                return
            }
        }
        beginBox(at: point, right: false)
    }

    override func mouseDragged(with event: NSEvent) {
        pointerMoved(to: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    override func mouseUp(with event: NSEvent) {
        endGesture(at: convert(event.locationInWindow, from: nil))
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        window?.makeKey()
        pointer = point
        modifiers = event.modifierFlags
        Diagnostics.record("right down")
        beginBox(at: point, right: true)
    }

    override func rightMouseDragged(with event: NSEvent) {
        pointerMoved(to: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    override func rightMouseUp(with event: NSEvent) {
        Diagnostics.record("right up gesture=\(gesture != nil)")
        endGesture(at: convert(event.locationInWindow, from: nil))
    }

    /// Starts a right-button press at the pointer, as if it had just gone down here (used
    /// when a right-click closed the context menu, so the next menu still opens).
    func beginRightPressAtPointer() {
        guard let window else { return }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        guard bounds.contains(point) else { return }
        pointer = point
        beginBox(at: point, right: true)
    }

    private func beginBox(at point: CGPoint, right: Bool) {
        gesture = .box(SelectionDrag(anchor: point), free: right, right: right)
        refresh()
    }

    private func endGesture(at point: CGPoint) {
        guard let gesture else { return }
        self.gesture = nil
        pointer = point
        switch gesture {
        case .resize(let id, _, _):
            refresh(force: true)
            if let area = board.area(id) { areaPlaced(area.id, snapped: false) }
        case .guide(let id, let axis, _):
            if let guide = board.guide(id) { board.moveGuide(id, to: overlay.snappedGuidePosition(axis, guide.position, in: self, excluding: id)) }
            refresh(force: true)
        case .box(var drag, let free, let right):
            drag.update(to: point, moving: overlay.isSpaceHeld)
            let rect = drag.rect(modifiers: selectionModifiers, bounds: bounds)
            if SelectionGeometry.isUsable(rect), overlay.capturesNextBox, let pixels = pixelRect(local: rect).intersection(imageBounds) {
                refresh()
                overlay.captureBox(pixels, in: self)
            } else if SelectionGeometry.isUsable(rect) {
                placeArea(drawn: rect, free: free || modifiers.contains(.command))
            } else if right {
                refresh()
                overlay.showContextMenu(at: point, in: self)
            } else {
                refresh()
                measureElementUnderPointer()
            }
        }
        currentCursor.set()
    }

    func cancelDrag() {
        switch gesture {
        case .resize(let id, _, let original): board.resizeArea(id, to: original)
        case .guide(let id, _, let original): board.moveGuide(id, to: original)
        default: break
        }
        gesture = nil
        refresh(force: true)
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
        let tolerance = model.tolerance
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

    /// What Return copies: the hovered area or held distance, else the last one placed, else
    /// the live hover distance.
    func copyableReading() -> Reading? {
        if let hoveredItem, let reading = board.reading(of: hoveredItem) { return reading }
        if let last = board.lastMeasured, let reading = board.reading(of: last) { return reading }
        return hoverSpans.map { .size(width: $0.width, height: $0.height) }
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
        if pointer != nil { currentCursor.set() }
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
        // Just above the hint (or where it would be), below it when the hint is at the top.
        let hintAtTop = !hintBadge.isHidden && hintBadge.frame.minY > bounds.midY
        let y = hintAtTop ? hintBadge.frame.minY - Spacing.m - size.height
            : (hintBadge.isHidden ? Self.chromeInset : hintBadge.frame.maxY + Spacing.m)
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

        let pixel = isBackground ? nil : pointerPixel
        if gesture == nil, let pixel {
            hoveredItem = board.item(at: pixel, slop: Int((3 * scale).rounded()))
            hoveredHandle = modifiers.contains(.command) ? nil : board.handle(at: pixel, slop: slop)
            if let handle = hoveredHandle { hoveredItem = .area(handle.id) }
        } else if gesture == nil {
            hoveredItem = nil
            hoveredHandle = nil
        }
        if let pixel, let edges {
            hoverSpans = edges.spans(at: pixel, tolerance: model.tolerance, limits: board.limits(for: pixel, in: edges.bounds))
        } else {
            hoverSpans = nil
        }

        let signature = BoardSignature(board: board, hovered: hoveredItem, unit: model.unit, scale: scale, color: lineColor,
                                       designScale: model.designScale, showUnits: model.showUnits,
                                       ratio: model.readoutRatioStyle.areas, hasPixels: edges != nil)
        if force || signature != drawnBoard {
            updateColors()
            drawBoard()
            drawnBoard = signature
        }

        let showCrosshair = gesture == nil && modifiers.contains(.shift) && pixel != nil && edges != nil
        drawCrosshair(showCrosshair ? pixel : nil)
        // Inside an area whose edges are the span, the area's own label already says it.
        var redundant = false
        if case .area(let id) = hoveredItem, let area = board.area(id), area.rect == hoverSpans { redundant = true }
        drawHover(showCrosshair || gesture != nil || redundant ? nil : hoverSpans, at: pixel)
        drawDrag()
        updateLoupe(pixel)
        layoutHint()
        layoutStatus()
        updateAccessibility()
    }

    /// A dimension line with T ends along one axis, as filled pixel rects (see `CrispStroke`):
    /// the line into `line`, its one-pixel halo into `halo`.
    private func addDimension(line: CGMutablePath, halo: CGMutablePath, axis: GuideAxis, at: Int, start: Int, end: Int,
                              emphasized: Bool = false) {
        let shape = CrispStroke.dimension(axis: axis, at: at, start: start, end: end, scale: Double(scale), emphasized: emphasized)
        for r in shape.line { line.addRect(localRect(r)) }
        for r in shape.halo { halo.addRect(localRect(r)) }
    }

    /// The centre (in view points) and thickness of a pixel band, for stroking a straight
    /// line exactly over it: rows for a horizontal line, columns for a vertical one.
    private func strokeGeometry(_ band: Range<Int>, axis: GuideAxis) -> (center: CGFloat, width: CGFloat) {
        let mid = (CGFloat(band.lowerBound) + CGFloat(band.count) / 2) / scale
        return (axis == .horizontal ? bounds.height - mid : mid, CGFloat(band.count) / scale)
    }

    private func drawHover(_ spans: PixelRect?, at point: PixelPoint?) {
        guard let spans, let point, !isBackground else {
            hoverHalo.path = nil
            hoverLine.path = nil
            hoverPill.isHidden = true
            return
        }
        let line = CGMutablePath(), haloPath = CGMutablePath()
        addDimension(line: line, halo: haloPath, axis: .horizontal, at: point.y, start: spans.minX, end: spans.maxX)
        addDimension(line: line, halo: haloPath, axis: .vertical, at: point.x, start: spans.minY, end: spans.maxY)
        hoverHalo.fillColor = halo(at: point)
        hoverHalo.path = haloPath
        hoverLine.path = line
        hoverPill.isHidden = false
        hoverPill.text = readout.sizeLabel(width: spans.width, height: spans.height, ratio: model.readoutRatioStyle.distances)
        if let pointer {
            hoverPill.frame = LabelLayout.cursorPill(size: hoverPill.preferredFrameSize(), pointer: pointer, bounds: labelArea).integral
        }
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
        crossHalo.strokeColor = halo(at: point)
        crossHalo.path = path
        crossLine.path = path
    }

    private func drawDrag() {
        guard case .box(let drag, let free, _) = gesture else {
            dragFill.path = nil
            dragOutline.path = nil
            dragBadge.isHidden = true
            return
        }
        // Outline the whole pixels the box will measure, not the raw pointer rect (which can
        // sit between pixels and draw soft edges).
        let pixels = pixelRect(local: drag.rect(modifiers: selectionModifiers, bounds: bounds))
        let rect = localRect(pixels)
        dragFill.path = CGPath(rect: rect, transform: nil)
        dragOutline.path = CGPath(rect: rect.insetBy(dx: -0.5, dy: -0.5), transform: nil)
        let isFree = free || modifiers.contains(.command)
        let note = overlay.capturesNextBox ? "  ·  screenshot" : isFree ? "" : "  ·  snaps on release"
        dragBadge.text = readout.sizeLabel(width: pixels.width, height: pixels.height) + note
        let size = dragBadge.preferredFrameSize()
        dragBadge.frame = CGRect(origin: SelectionGeometry.labelOrigin(size: size, for: rect, bounds: bounds), size: size).integral
        dragBadge.isHidden = false
    }

    private func drawBoard() {
        boardLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        boardLabelLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        let line = overlay(lineColor)
        let px = 1 / scale
        let hovered = isRenderingScreenshot ? nil : hoveredItem
        var labels: [(BadgeLayer, CGRect)] = []

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
        func fill(_ path: CGPath, color: CGColor) {
            let layer = CAShapeLayer()
            layer.contentsScale = backingScale
            layer.path = path
            layer.fillColor = color
            boardLayer.addSublayer(layer)
        }
        func badge(_ text: String) -> BadgeLayer {
            let b = BadgeLayer()
            b.outlined(scale: backingScale)
            b.text = text
            return b
        }

        // Guides: an even band of pixels centred on the boundary they mark, dashed; solid and
        // a pixel bolder each side when hovered (it can be dragged).
        let guideWidth = CGFloat(CrispStroke.band(straddling: 0, scale: Double(scale)).count) * px
        for guide in board.guides {
            let isHovered = hovered == .guide(guide.id)
            let path = CGMutablePath()
            let probe: PixelPoint
            switch guide.axis {
            case .vertical:
                let x = localX(guide.position)
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: bounds.maxY))
                probe = PixelPoint(x: min(guide.position, imageBounds.maxX - 1), y: imageBounds.height / 2)
            case .horizontal:
                let y = localY(guide.position)
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: bounds.maxX, y: y))
                probe = PixelPoint(x: imageBounds.width / 2, y: min(guide.position, imageBounds.maxY - 1))
            }
            let width = guideWidth + (isHovered ? 2 * px : 0)
            stroke(path, width: width + 2 * px, color: halo(at: probe))
            stroke(path, width: width, color: line, dash: isHovered ? nil : [6, 3])
        }

        // Gaps between neighbouring guides (and to the display edges, dotted): vertical guides'
        // gaps in a row under the menu bar, horizontal guides' in a column at the left edge,
        // each on a point-wide pixel band, with its number threaded on it.
        let limits = imageBounds
        for axis in [GuideAxis.vertical, .horizontal] {
            let gaps = board.guideGaps(axis, limit: axis == .vertical ? limits.maxX : limits.maxY)
            guard !gaps.isEmpty else { continue }
            let badges = gaps.map { badge(readout.lengthLabel($0.length)) }
            let sizes = badges.map { $0.preferredFrameSize() }
            // Placed so the labels start `chromeInset` below the menu bar / from the left edge.
            let lineAxis: GuideAxis = axis == .vertical ? .horizontal : .vertical
            let offset = Self.chromeInset + (axis == .vertical ? (sizes.map(\.height).max() ?? 0) : (sizes.map(\.width).max() ?? 0)) / 2
            let pixel = axis == .vertical
                ? Int(((safeTop + offset) * scale).rounded(.down))
                : Int((offset * scale).rounded(.down))
            let (center, width) = strokeGeometry(CrispStroke.band(holding: pixel, scale: Double(scale)), axis: lineAxis)
            for (gap, (b, s)) in zip(gaps, zip(badges, sizes)) {
                let path = CGMutablePath()
                let a: CGPoint, z: CGPoint, probe: PixelPoint
                if axis == .vertical {
                    a = CGPoint(x: localX(gap.start), y: center); z = CGPoint(x: localX(gap.end), y: center)
                    probe = PixelPoint(x: min((gap.start + gap.end) / 2, limits.maxX - 1), y: min(pixel, limits.maxY - 1))
                } else {
                    a = CGPoint(x: center, y: localY(gap.start)); z = CGPoint(x: center, y: localY(gap.end))
                    probe = PixelPoint(x: min(pixel, limits.maxX - 1), y: min((gap.start + gap.end) / 2, limits.maxY - 1))
                }
                path.move(to: a); path.addLine(to: z)
                let dash: [NSNumber]? = gap.touchesEdge ? [2, 3] : nil
                stroke(path, width: width + 2 * px, color: halo(at: probe), dash: dash)
                stroke(path, width: width, color: line, dash: dash)
                labels.append((b, LabelLayout.lineLabel(size: s, from: a, to: z, bounds: labelArea)))
            }
        }

        // Areas: a crisp one-point outline just outside the box (its inner edge is the
        // measured edge), the size in its middle. Hovered: tinted, with corner knobs on the
        // outline (drag a side or corner to resize).
        for area in board.areas {
            let isHovered = hovered == .area(area.id)
            let rect = localRect(area.rect)
            if isHovered { fill(CGPath(rect: rect, transform: nil), color: overlay(lineColor.withAlphaComponent(0.15))) }
            let probe = PixelPoint(x: max(area.rect.minX - 1, 0), y: max(area.rect.minY - 1, 0))
            stroke(CGPath(rect: rect.insetBy(dx: -1 - px, dy: -1 - px), transform: nil), width: px * 2, color: halo(at: probe))
            let outline = rect.insetBy(dx: -0.5, dy: -0.5)
            stroke(CGPath(rect: outline, transform: nil), width: 1, color: line, dash: area.isSettled ? nil : [4, 3])
            if isHovered && rect.width >= 16 && rect.height >= 16 {
                for corner in [CGPoint(x: outline.minX, y: outline.minY), CGPoint(x: outline.maxX, y: outline.minY),
                               CGPoint(x: outline.minX, y: outline.maxY), CGPoint(x: outline.maxX, y: outline.maxY)] {
                    let knob = CAShapeLayer()
                    knob.contentsScale = backingScale
                    knob.path = CGPath(ellipseIn: CGRect(x: corner.x - 3.5, y: corner.y - 3.5, width: 7, height: 7), transform: nil)
                    knob.fillColor = OverlayPalette.paper.cgColor // a light handle reads on any line colour
                    knob.strokeColor = line
                    knob.lineWidth = 1
                    boardLayer.addSublayer(knob)
                }
            }
            let b = badge(readout.sizeLabel(width: area.rect.width, height: area.rect.height, ratio: model.readoutRatioStyle.areas))
            labels.append((b, LabelLayout.areaLabel(size: b.preferredFrameSize(), box: rect, bounds: labelArea)))
        }

        // Held distances: the line with T ends on whole pixels, its number threaded on it
        // (beside it when the line is too short to show its ends past the number).
        for pin in board.pins {
            let isHovered = hovered == .pin(pin.id)
            let linePath = CGMutablePath(), haloPath = CGMutablePath()
            addDimension(line: linePath, halo: haloPath, axis: pin.axis, at: pin.at, start: pin.start, end: pin.end, emphasized: isHovered)
            let probe = pin.axis == .horizontal ? PixelPoint(x: (pin.start + pin.end) / 2, y: pin.at) : PixelPoint(x: pin.at, y: (pin.start + pin.end) / 2)
            fill(haloPath, color: halo(at: probe))
            fill(linePath, color: line)
            let b = badge(readout.lengthLabel(pin.length))
            let mid = strokeGeometry(CrispStroke.band(holding: pin.at, scale: Double(scale)), axis: pin.axis).center
            let (a, z): (CGPoint, CGPoint) = pin.axis == .horizontal
                ? (CGPoint(x: localX(pin.start), y: mid), CGPoint(x: localX(pin.end), y: mid))
                : (CGPoint(x: mid, y: localY(pin.start)), CGPoint(x: mid, y: localY(pin.end)))
            labels.append((b, LabelLayout.lineLabel(size: b.preferredFrameSize(), from: a, to: z, bounds: labelArea)))
        }

        // Labels last, above every line, moved off each other.
        let frames = LabelLayout.separate(labels.map(\.1), bounds: labelArea)
        for ((b, _), frame) in zip(labels, frames) {
            b.frame = frame.integral
            boardLabelLayer.addSublayer(b)
        }
        boardLabelFrames = frames
    }

    private func updateLoupe(_ pixel: PixelPoint?) {
        guard model.showMagnifier, let pixel, let pointer, let snapshot, gesture == nil, !isBackground else {
            loupe.isHidden = true
            return
        }
        if loupe.superlayer == nil { layer?.insertSublayer(loupe, below: statusBadge) }
        loupe.isHidden = false
        loupe.show(image: snapshot, centerPixel: CGPoint(x: pixel.x, y: pixel.y),
                   pointLabel: "\(readout.number(pixel.x)), \(readout.number(pixel.y))")
        var avoid = boardLabelFrames
        if !hoverPill.isHidden { avoid.append(hoverPill.frame.insetBy(dx: -6, dy: -6)) }
        // On whole device pixels: a fractional origin would resample every zoomed cell.
        let frame = LabelLayout.magnifier(size: loupe.preferredFrameSize(), pointer: pointer, bounds: labelArea, avoiding: avoid)
        loupe.frame = CGRect(origin: CGPoint(x: (frame.minX * backingScale).rounded() / backingScale,
                                             y: (frame.minY * backingScale).rounded() / backingScale), size: frame.size)
    }

    /// How far the overlay's own chrome (key hint, scale badge, guide gap rows) sits from
    /// the display edges and the menu bar.
    static let chromeInset = Spacing.l

    /// Room the vertical guides' gap row takes under the menu bar, so the hint moved to the
    /// top goes below it rather than over it.
    private var gapRowHeight: CGFloat {
        board.guides.contains { $0.axis == .vertical } ? hintBadge.preferredFrameSize().height + Spacing.s : 0
    }

    private func layoutHint() {
        hintBadge.isHidden = !model.showHints || pointer == nil || gesture != nil || isBackground
        guard !hintBadge.isHidden else { return }
        let size = hintBadge.preferredFrameSize()
        var y = Self.chromeInset
        // Near the bottom, the hint moves to the top so it's never under the pointer.
        if let pointer, pointer.y < y + size.height + 90 { y = bounds.maxY - safeTop - Self.chromeInset - gapRowHeight - size.height }
        hintBadge.frame = CGRect(x: (bounds.midX - size.width / 2).rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    /// A corner badge while a design scale is on, so numbers are never silently divided.
    /// Bottom right (the left edge has the horizontal guides' gaps), the other corner when
    /// the pointer comes near.
    private func layoutStatus() {
        guard let text = DesignScale.badge(model.designScale), !isBackground, pointer != nil else {
            statusBadge.isHidden = true
            return
        }
        statusBadge.isHidden = false
        statusBadge.text = "Scale \(text)"
        let size = statusBadge.preferredFrameSize()
        let inset = Self.chromeInset
        var frame = CGRect(x: bounds.maxX - inset - size.width, y: inset, width: size.width, height: size.height)
        if let pointer, frame.insetBy(dx: -60, dy: -60).contains(pointer) { frame.origin.x = inset }
        statusBadge.frame = frame
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
            parts.append("Held: " + board.pins.map { readout.length($0.length) }.joined(separator: ", "))
        }
        if !board.guides.isEmpty { parts.append(board.guides.count == 1 ? "1 guide" : "\(board.guides.count) guides") }
        parts.append("Edge tolerance \(model.tolerance.title)")
        if let badge = DesignScale.badge(model.designScale) { parts.append("Scale \(badge)") }
        setAccessibilityValue(parts.joined(separator: ". "))
    }

    // MARK: Screenshots

    /// The subject of a screenshot: the hovered area (with its label), else everything
    /// measured (with labels), else nil (the whole display).
    func screenshotSubject() -> PixelRect? {
        if case .area(let id) = hoveredItem, let area = board.area(id) {
            let label = boardLabelFrames.first { localRect(area.rect).insetBy(dx: -40, dy: -40).contains($0) }
            return label.map { area.rect.union(pixelRect(local: $0)) } ?? area.rect
        }
        guard let measured = board.measuredBounds else { return nil }
        return boardLabelFrames.reduce(measured) { $0.union(pixelRect(local: $1)) }
    }

    /// Everything on this overlay as drawn, at the display's own pixels (test dumps), so
    /// pixel-grid alignment can be checked on the image.
    func renderOverlay() -> CGImage? {
        let s = backingScale
        guard let root = layer, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(bounds.width * s), height: Int(bounds.height * s), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        context.scaleBy(x: s, y: s)
        root.render(in: context)
        return context.makeImage()
    }

    /// Draws the frozen screen with the placed measurements (not the live hover, hint or
    /// magnifier) for `crop`, at the display's pixels or at 1×.
    func renderScreenshot(crop: PixelRect, at1x: Bool) -> CGImage? {
        guard let snapshot, let root = layer else { return nil }
        let outScale = at1x ? 1 : scale
        let local = localRect(crop)
        let width = Int((local.width * outScale).rounded()), height = Int((local.height * outScale).rounded())
        let space = snapshot.colorSpace.flatMap { $0.supportsOutput && $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let transient: [CALayer] = [hoverHalo, hoverLine, hoverPill, crossHalo, crossLine, dragFill, dragOutline, dragBadge,
                                    loupe, hintBadge, statusBadge, toastBadge]
        let wasHidden = transient.map(\.isHidden)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        transient.forEach { $0.isHidden = true }
        isRenderingScreenshot = true
        drawBoard()
        CATransaction.commit()

        context.interpolationQuality = at1x ? .high : .none
        context.scaleBy(x: outScale, y: outScale)
        context.translateBy(x: -local.minX, y: -local.minY)
        root.render(in: context)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, hidden) in zip(transient, wasHidden) { layer.isHidden = hidden }
        isRenderingScreenshot = false
        CATransaction.commit()
        refresh(force: true)
        return context.makeImage()
    }
}

extension BadgeLayer {
    /// SlopKit's badge in `OverlayPalette` colours, a little more opaque (90% ink rather than
    /// 80%: measurement labels sit on busy content all the time, and text under them otherwise
    /// ghosts through), with a one-pixel light edge so the pill keeps its shape over dark
    /// content.
    func outlined(scale: CGFloat) {
        setScale(scale)
        backgroundColor = OverlayPalette.ink.withAlphaComponent(0.9).cgColor
        borderWidth = 1 / scale
        borderColor = OverlayPalette.paper.withAlphaComponent(0.2).cgColor
    }
}
