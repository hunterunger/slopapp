import AppKit
import SlopKit
import SnapperCore

/// The camera in a floating bubble over the recorded area. It's our own window on screen, so
/// the recording picks it up exactly where it's shown (the recorder keeps it in the stream).
///
/// Drag it to move it; drag its rim, pinch, or scroll over it to resize; right-click for
/// sizes, the shape, and Hide Camera. It snaps to nothing and remembers the corner it ends up
/// nearest to, and its size, for the next recording.
@MainActor
final class CameraBubbleController {
    private var panel: BubblePanel?
    private var source: CameraSource?
    private var area: CGRect = .zero
    private(set) var shape: BubbleShape = .circle
    /// Size or corner changed by the person (to remember them).
    var onChange: ((_ width: CGFloat, _ corner: BubbleCorner) -> Void)?
    var onShapeChange: ((BubbleShape) -> Void)?
    var onHide: (() -> Void)?

    var isShown: Bool { panel?.isVisible == true }
    var windowNumber: CGWindowID? { panel.map { CGWindowID($0.windowNumber) } }
    var frame: CGRect? { panel?.frame }

    /// Shows the camera in `corner` of `area` (AppKit global points).
    func show(deviceID: String?, shape: BubbleShape, width: CGFloat, corner: BubbleCorner, in area: CGRect) throws {
        hide()
        let source = MediaEnvironment.makeCamera()
        let layer = try source.start(deviceID: deviceID)
        self.source = source
        self.area = area
        self.shape = shape
        let frame = BubbleGeometry.frame(corner: corner, width: width, shape: shape, in: area)
        let panel = BubblePanel(contentRect: frame)
        let view = BubbleView(frame: CGRect(origin: .zero, size: frame.size), camera: layer, shape: shape)
        view.controller = self
        panel.contentView = view
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        Diagnostics.record("camera shown shape=\(shape.rawValue) width=\(Int(frame.width)) synthetic=\(MediaEnvironment.isSynthetic)")
    }

    func hide() {
        guard let panel else { return }
        source?.stop()
        source = nil
        panel.orderOut(nil)
        panel.close()
        self.panel = nil
        Diagnostics.record("camera hidden")
    }

    /// The recorded area changed (the bubble stays where it is, moved inside the screen).
    func setArea(_ area: CGRect) { self.area = area }

    func setShape(_ shape: BubbleShape) {
        guard let panel, shape != self.shape else { return }
        self.shape = shape
        (panel.contentView as? BubbleView)?.shape = shape
        resize(to: panel.frame.width)
        onShapeChange?(shape)
    }

    func resize(to width: CGFloat) {
        guard let panel else { return }
        let bounds = panel.screen?.frame ?? NSScreen.screens.first?.frame ?? area
        let frame = BubbleGeometry.resized(panel.frame, toWidth: width, shape: shape, area: area, bounds: bounds)
        panel.setFrame(frame, display: true)
        changed()
    }

    fileprivate func moved() {
        guard let panel else { return }
        let bounds = panel.screen?.frame ?? area
        let kept = BubbleGeometry.kept(panel.frame, inside: bounds)
        if kept != panel.frame { panel.setFrame(kept, display: true) }
        changed()
    }

    private func changed() {
        guard let panel else { return }
        onChange?(panel.frame.width, BubbleGeometry.nearestCorner(of: panel.frame, in: area))
    }

    fileprivate func menu() -> NSMenu {
        let menu = NSMenu()
        for preset in BubbleGeometry.presets {
            let item = ClosureMenuItem(title: preset.title) { [weak self] in self?.resize(to: preset.width) }
            item.state = abs((panel?.frame.width ?? 0) - BubbleGeometry.clampedWidth(preset.width, shape: shape, in: area)) < 1 ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for option in BubbleShape.allCases {
            let item = ClosureMenuItem(title: option.title) { [weak self] in self?.setShape(option) }
            item.state = option == shape ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Hide Camera") { [weak self] in
            self?.hide()
            self?.onHide?()
        })
        return menu
    }
}

/// A borderless, non-activating panel above the recording frame and its dimming.
private final class BubblePanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        title = "Camera"
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The camera picture, clipped to the bubble's shape with a hairline edge. Handles moving,
/// resizing and the menu.
private final class BubbleView: NSView {
    weak var controller: CameraBubbleController?
    private let camera: CALayer
    private let clip = CALayer()
    private let edge = CAShapeLayer()
    var shape: BubbleShape { didSet { needsLayout = true } }
    private var dragStart: (mouse: CGPoint, frame: CGRect, resizing: Bool)?
    /// How close to the rim a drag resizes instead of moving.
    private let rim: CGFloat = 14

    init(frame: CGRect, camera: CALayer, shape: BubbleShape) {
        self.camera = camera
        self.shape = shape
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        clip.masksToBounds = true
        clip.cornerCurve = .continuous
        clip.addSublayer(camera)
        layer?.addSublayer(clip)
        edge.fillColor = nil
        edge.lineWidth = 0.5
        layer?.addSublayer(edge)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Camera")
        setAccessibilityHelp("Your camera, shown in the recording. Drag to move it, drag its edge to resize it.")
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "Make Larger") { [weak self] in self?.step(1.25); return true },
            NSAccessibilityCustomAction(name: "Make Smaller") { [weak self] in self?.step(0.8); return true },
            NSAccessibilityCustomAction(name: "Hide Camera") { [weak self] in
                self?.controller?.hide()
                self?.controller?.onHide?()
                return true
            },
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let radius = BubbleGeometry.cornerRadius(for: bounds.size, shape: shape)
        clip.frame = bounds
        clip.cornerRadius = radius
        camera.frame = bounds
        let inset = bounds.insetBy(dx: 0.25, dy: 0.25)
        edge.path = CGPath(roundedRect: inset, cornerWidth: max(0, radius - 0.25), cornerHeight: max(0, radius - 0.25), transform: nil)
        CATransaction.commit()
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            edge.strokeColor = NSColor.separatorColor.cgColor
        }
    }

    private func isOnRim(_ point: CGPoint) -> Bool {
        switch shape {
        case .circle:
            let r = bounds.width / 2
            return hypot(point.x - bounds.midX, point.y - bounds.midY) > r - rim
        case .roundedRectangle:
            return !bounds.insetBy(dx: rim, dy: rim).contains(point)
        }
    }

    override func resetCursorRects() {
        // The whole bubble moves; the rim resizes.
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let local = convert(event.locationInWindow, from: nil)
        dragStart = (NSEvent.mouseLocation, window.frame, isOnRim(local))
        (dragStart?.resizing == true ? NSCursor.crosshair : NSCursor.closedHand).push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let window else { return }
        let now = NSEvent.mouseLocation
        if start.resizing {
            // Away from the center grows it, toward it shrinks it.
            let center = CGPoint(x: start.frame.midX, y: start.frame.midY)
            let before = hypot(start.mouse.x - center.x, start.mouse.y - center.y)
            let after = hypot(now.x - center.x, now.y - center.y)
            controller?.resize(to: start.frame.width + 2 * (after - before))
        } else {
            window.setFrameOrigin(CGPoint(x: (start.frame.minX + now.x - start.mouse.x).rounded(),
                                          y: (start.frame.minY + now.y - start.mouse.y).rounded()))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if dragStart != nil { NSCursor.pop() }
        if dragStart?.resizing == false { controller?.moved() }
        dragStart = nil
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
        guard delta != 0, let window else { return }
        controller?.resize(to: window.frame.width + delta)
    }

    override func magnify(with event: NSEvent) {
        guard let window else { return }
        controller?.resize(to: window.frame.width * (1 + event.magnification))
    }

    override func menu(for event: NSEvent) -> NSMenu? { controller?.menu() }

    private func step(_ factor: CGFloat) {
        guard let window else { return }
        controller?.resize(to: window.frame.width * factor)
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func run() { handler() }
}
