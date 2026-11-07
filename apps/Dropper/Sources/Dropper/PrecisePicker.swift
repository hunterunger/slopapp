import AppKit
import DropperCore
import QuartzCore
import SlopKit

/// The precise picker: a round loupe over a frozen image of every display, with a pixel
/// grid, the center pixel outlined and its value in the copy format. Arrow keys move one
/// physical pixel (Shift: 10), + / − change the size, ⌥+ / ⌥− the zoom, the scroll wheel
/// resizes (⌥: zooms). Click, Return or Space picks; Esc or a right-click cancels.
///
/// Needs Screen Recording (it reads pixels from a ScreenCaptureKit snapshot via SlopKit's
/// capture service). The real pointer is hidden while it's up and never warped.
@MainActor
final class PreciseSampler: ColorSampling {
    let settings: AppSettings
    /// The value shown in the loupe ("#3366CC").
    var describe: (ColorValue) -> String = { _ in "" }
    private let capturer: ScreenCapturing
    private var session: LoupeSession?

    init(settings: AppSettings, capturer: ScreenCapturing = ScreenCaptureKitCapturer()) {
        self.settings = settings
        self.capturer = capturer
    }

    func sample(prompt: String?) async -> ColorValue? {
        guard session == nil else { return nil }
        let exclusions = TestScene.isActive ? CaptureExclusions(onlyWindows: TestScene.windowNumbers) : CaptureExclusions()
        let session = LoupeSession(capturer: capturer, exclusions: exclusions, settings: settings, describe: describe, prompt: prompt)
        self.session = session
        defer { self.session = nil }
        return await session.run()
    }

    /// Test hook: move the loupe to a test-scene slot.
    func testJump(to slot: Int) {
        session?.jump(toSceneSlot: slot)
    }
}

@MainActor
final class LoupeSession {
    private let capturer: ScreenCapturing
    private let exclusions: CaptureExclusions
    private let settings: AppSettings
    private let describe: (ColorValue) -> String
    private let prompt: String?
    private var panels: [LoupePanel] = []
    private var continuation: CheckedContinuation<ColorValue?, Never>?
    private var previousApp: NSRunningApplication?
    private var finished = false
    private var cursorHidden = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var scrollAccumulator: CGFloat = 0
    private var started = CACurrentMediaTime()

    init(capturer: ScreenCapturing, exclusions: CaptureExclusions, settings: AppSettings, describe: @escaping (ColorValue) -> String,
         prompt: String?) {
        self.capturer = capturer
        self.exclusions = exclusions
        self.settings = settings
        self.describe = describe
        self.prompt = prompt
    }

    var geometry: LoupeGeometry { settings.loupe }

    func run() async -> ColorValue? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            show()
        }
    }

    private func show() {
        started = CACurrentMediaTime()
        previousApp = NSWorkspace.shared.frontmostApplication
        let pointerScreen = NSScreen.underPointer
        for screen in NSScreen.screens {
            let panel = LoupePanel(screen: screen, session: self)
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        AppActivation.activate()
        (panels.first { $0.screen == pointerScreen } ?? panels.first)?.makeKeyAndOrderFront(nil)
        NSCursor.hide()
        cursorHidden = true
        followPointer()
        observeSystem()
        Diagnostics.record("loupe shown ms=\(ms()) testMode=\(TestScene.isActive)")

        let ids = NSScreen.screens.map(\.displayID)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let images = try await capturer.snapshot(displays: ids, excluding: exclusions)
                guard !finished else { return }
                for panel in panels { panel.loupeView.snapshot = images[panel.loupeView.displayID] }
                Diagnostics.record("loupe snapshot ready ms=\(ms())")
                if TestScene.isActive { jump(toSceneSlot: 0) } else { followPointer() }
            } catch {
                Diagnostics.record("loupe snapshot failed: \(error.localizedDescription)")
                finish(nil)
            }
        }
    }

    private func ms() -> String { String(format: "%.0f", (CACurrentMediaTime() - started) * 1000) }

    private var views: [LoupeView] { panels.map(\.loupeView) }

    /// The view showing the loupe (where keys act).
    private var activeView: LoupeView? { views.first { $0.pixel != nil } }

    func followPointer() {
        let mouse = NSEvent.mouseLocation
        for panel in panels {
            let view = panel.loupeView
            if NSMouseInRect(mouse, panel.frame, false) {
                view.point(at: panel.convertPoint(fromScreen: mouse))
            } else {
                view.clearPointer()
            }
        }
    }

    func jump(toSceneSlot slot: Int) {
        guard let global = TestScene.globalCenter(of: slot) else { return }
        for panel in panels {
            let view = panel.loupeView
            if NSMouseInRect(global, panel.frame, false) {
                view.point(at: panel.convertPoint(fromScreen: global))
            } else {
                view.clearPointer()
            }
        }
    }

    // MARK: Input

    func keyDown(_ event: NSEvent) {
        let option = event.modifierFlags.contains(.option)
        switch event.keyCode {
        case 53: finish(nil) // Esc
        case 36, 76, 49: pick() // Return, Enter, Space
        default:
            if let delta = PickerNudge.delta(keyCode: event.keyCode, shift: event.modifierFlags.contains(.shift)) {
                activeView?.nudge(dx: delta.dx, dy: delta.dy)
                return
            }
            switch event.charactersIgnoringModifiers {
            case "+", "=": change { option ? $0.zoomIn() : $0.grow() }
            case "-", "_": change { option ? $0.zoomOut() : $0.shrink() }
            default: NSSound.beep()
            }
        }
    }

    func scroll(_ event: NSEvent) {
        scrollAccumulator += event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 10)
        guard abs(scrollAccumulator) >= 24 else { return }
        let up = scrollAccumulator > 0
        scrollAccumulator = 0
        let option = event.modifierFlags.contains(.option)
        change { option ? (up ? $0.zoomIn() : $0.zoomOut()) : (up ? $0.grow() : $0.shrink()) }
    }

    private func change(_ edit: (inout LoupeGeometry) -> Void) {
        var g = settings.loupe
        edit(&g)
        settings.loupe = g
        for view in views { view.refresh() }
    }

    func pick() {
        guard let view = activeView, let color = view.currentColor else {
            NSSound.beep()
            return
        }
        Diagnostics.record("loupe picked pixel=\(view.pixel.map { "\($0.x),\($0.y)" } ?? "-") ms=\(ms())")
        finish(color)
    }

    func cancel() { finish(nil) }

    private func observeSystem() {
        let cancel: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(nil) }
        }
        let center = NotificationCenter.default
        observers.append((center, center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: cancel)))
        observers.append((center, center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main, using: cancel)))
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main, using: cancel)))
        }
    }

    private func finish(_ color: ColorValue?) {
        guard !finished else { return }
        finished = true
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
        for panel in panels {
            panel.loupeView.snapshot = nil
            panel.orderOut(nil)
            panel.close()
        }
        panels = []
        if cursorHidden {
            NSCursor.unhide()
            cursorHidden = false
        }
        if let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate()
        }
        continuation?.resume(returning: color)
        continuation = nil
    }

    fileprivate func describeColor(_ color: ColorValue) -> String { describe(color) }
    fileprivate var promptText: String? { prompt }
}

/// One display's borderless, full-screen panel.
@MainActor
final class LoupePanel: NSPanel {
    let loupeView: LoupeView

    init(screen: NSScreen, session: LoupeSession) {
        loupeView = LoupeView(frame: CGRect(origin: .zero, size: screen.frame.size), screen: screen, session: session)
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        isMovable = false
        contentView = loupeView
        initialFirstResponder = loupeView
        title = "Dropper loupe"
        setAccessibilityLabel("Color picker loupe")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Draws the loupe with Core Animation layers (cheap to move on every mouse event).
@MainActor
final class LoupeView: NSView {
    let displayID: CGDirectDisplayID
    private unowned let session: LoupeSession
    private let backingScale: CGFloat

    var snapshot: CGImage? {
        didSet { refresh() }
    }

    /// The pixel the loupe is centered on, in the snapshot (nil when the pointer is on
    /// another display).
    private(set) var pixel: PixelPoint?
    private(set) var currentColor: ColorValue?

    private let loupe = CALayer()
    private let zoomed = CALayer()
    private let grid = CAShapeLayer()
    private let center = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let pill = CALayer()
    private let pillSwatch = CALayer()
    private let pillText = CATextLayer()
    private let promptBadge = BadgeLayer()
    private let hintBadge = BadgeLayer()
    private let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)

    init(frame: CGRect, screen: NSScreen, session: LoupeSession) {
        displayID = screen.displayID
        self.session = session
        backingScale = screen.backingScaleFactor
        super.init(frame: frame)
        wantsLayer = true
        let root = CALayer()
        layer = root
        root.contentsScale = backingScale

        loupe.masksToBounds = true
        // Chrome over arbitrary screen content: SlopKit's overlay palette (the dark
        // appearance's system colours, never pure black or white), the same in both modes.
        loupe.backgroundColor = OverlayPalette.ink.cgColor
        zoomed.magnificationFilter = .nearest
        zoomed.anchorPoint = .zero
        // One device pixel, like every hairline: the cells read as a grid without hiding
        // the pixels' own edges.
        grid.strokeColor = OverlayPalette.ink.withAlphaComponent(0.25).cgColor
        grid.lineWidth = 1 / backingScale
        grid.fillColor = nil
        center.fillColor = nil
        center.strokeColor = OverlayPalette.ring
        center.lineWidth = 1.5
        center.shadowColor = OverlayPalette.ringShadow
        center.shadowOpacity = 0.9
        center.shadowRadius = 0.8
        center.shadowOffset = .zero
        ring.fillColor = nil
        ring.strokeColor = OverlayPalette.ring
        ring.lineWidth = Self.ringWidth
        ring.shadowColor = OverlayPalette.ringShadow
        ring.shadowOpacity = 0.35
        ring.shadowRadius = 6
        ring.shadowOffset = CGSize(width: 0, height: -2)
        // The readout matches SlopKit's BadgeLayer (the hint and prompt badges beside it).
        pill.backgroundColor = OverlayPalette.badgeFill
        pill.cornerCurve = .continuous
        pill.shadowColor = OverlayPalette.ringShadow
        pill.shadowOpacity = 0.25
        pill.shadowRadius = 3
        pill.shadowOffset = CGSize(width: 0, height: -1)
        // A light edge, so a swatch as dark as the badge still shows its outline.
        pillSwatch.borderColor = OverlayPalette.paper.withAlphaComponent(0.4).cgColor
        pillSwatch.borderWidth = 1 / backingScale
        pillText.font = font
        pillText.fontSize = font.pointSize
        pillText.foregroundColor = OverlayPalette.badgeText
        pillText.alignmentMode = .left
        pill.addSublayer(pillSwatch)
        pill.addSublayer(pillText)
        loupe.addSublayer(zoomed)
        loupe.addSublayer(grid)
        loupe.addSublayer(center)
        for l in [loupe, zoomed, grid, center, ring, pill, pillSwatch, pillText, promptBadge, hintBadge] as [CALayer] {
            l.contentsScale = backingScale
        }
        promptBadge.setScale(backingScale)
        hintBadge.setScale(backingScale)
        hintBadge.text = "Click or Return to pick   Arrows: 1 pixel (Shift: 10)   + −: size   ⌥ + −: zoom   Esc: cancel"
        for l in [loupe, ring, pill, promptBadge, hintBadge] as [CALayer] { root.addSublayer(l) }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Color picker loupe")
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    // MARK: Pointer

    private var scale: CGFloat {
        guard let snapshot else { return backingScale }
        return CGFloat(snapshot.width) / max(bounds.width, 1)
    }

    func point(at local: CGPoint) {
        pixel = PixelPoint.under(local: local, height: bounds.height, scale: scale)
        refresh()
    }

    func clearPointer() {
        pixel = nil
        refresh()
    }

    func nudge(dx: Int, dy: Int) {
        guard let pixel, let snapshot else { return }
        self.pixel = pixel.nudged(dx: dx, dy: dy, width: snapshot.width, height: snapshot.height)
        refresh()
    }

    override func mouseMoved(with event: NSEvent) { session.followPointer() }
    override func mouseDragged(with event: NSEvent) { session.followPointer() }
    override func mouseEntered(with event: NSEvent) {
        window?.makeKey()
        session.followPointer()
    }

    override func mouseDown(with event: NSEvent) {
        point(at: convert(event.locationInWindow, from: nil))
        session.pick()
    }

    override func rightMouseDown(with event: NSEvent) { session.cancel() }
    override func keyDown(with event: NSEvent) { session.keyDown(event) }
    override func scrollWheel(with event: NSEvent) { session.scroll(event) }
    override func cancelOperation(_ sender: Any?) { session.cancel() }

    // MARK: Drawing

    func refresh() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let showing = pixel != nil && snapshot != nil
        for l in [loupe, ring, pill] as [CALayer] { l.isHidden = !showing }
        hintBadge.isHidden = !showing
        promptBadge.isHidden = !showing || session.promptText == nil
        guard let pixel, let snapshot else {
            currentColor = nil
            return
        }

        let g = session.geometry
        let d = g.diameter, cell = g.cellSize, n = g.cells
        let centerPoint = pixel.localCenter(height: bounds.height, scale: scale)
        let frame = CGRect(x: (centerPoint.x - d / 2).rounded(), y: (centerPoint.y - d / 2).rounded(), width: d, height: d)
        loupe.frame = frame
        loupe.cornerRadius = d / 2
        ring.frame = frame
        ring.path = CGPath(ellipseIn: CGRect(origin: .zero, size: frame.size).insetBy(dx: Self.ringWidth / 2, dy: Self.ringWidth / 2), transform: nil)

        // n×n cells centered in the circle; the middle cell sits on the circle's center.
        let side = CGFloat(n) * cell
        let origin = CGPoint(x: (d - side) / 2, y: (d - side) / 2)
        let sample = g.sampleRect(around: pixel)
        let wanted = CGRect(x: sample.x, y: sample.y, width: sample.side, height: sample.side)
        let available = wanted.intersection(CGRect(x: 0, y: 0, width: snapshot.width, height: snapshot.height))
        if !available.isNull, !available.isEmpty, let crop = snapshot.cropping(to: available) {
            zoomed.contents = crop
            // Image rows go down; layer y goes up.
            let left = CGFloat(Int(available.minX) - sample.x)
            let top = CGFloat(Int(available.minY) - sample.y)
            zoomed.frame = CGRect(x: origin.x + left * cell, y: origin.y + side - (top + available.height) * cell,
                                  width: available.width * cell, height: available.height * cell)
        } else {
            zoomed.contents = nil
        }
        grid.frame = loupe.bounds
        let path = CGMutablePath()
        for i in 0...n {
            let offset = CGFloat(i) * cell
            path.move(to: CGPoint(x: origin.x + offset, y: 0)); path.addLine(to: CGPoint(x: origin.x + offset, y: d))
            path.move(to: CGPoint(x: 0, y: origin.y + offset)); path.addLine(to: CGPoint(x: d, y: origin.y + offset))
        }
        grid.path = cell >= 8 ? path : nil
        center.frame = loupe.bounds
        let middle = CGRect(x: origin.x + CGFloat(n / 2) * cell, y: origin.y + CGFloat(n / 2) * cell, width: cell, height: cell)
        center.path = CGPath(rect: middle.insetBy(dx: -0.5, dy: -0.5), transform: nil)

        // Readout: inside the circle when it fits (hex), under it for long code formats.
        currentColor = Self.color(at: pixel, in: snapshot)
        let text = currentColor.map(session.describeColor) ?? "–"
        pillText.string = text
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let readout = Self.pillLayout(textWidth: ceil(textSize.width), diameter: d)
        let pillY = readout.inside ? frame.minY + readout.insideBottom : frame.minY - Self.pillHeight - Spacing.s
        pill.frame = CGRect(x: (frame.midX - readout.width / 2).rounded(), y: pillY.rounded(), width: readout.width, height: Self.pillHeight)
        pill.cornerRadius = Self.pillHeight / 2
        // The swatch is concentric with the pill's round end.
        let swatchSide = Self.pillHeight - 2 * Self.pillSwatchInset
        pillSwatch.frame = CGRect(x: Self.pillSwatchInset, y: Self.pillSwatchInset, width: swatchSide, height: swatchSide)
        pillSwatch.cornerRadius = swatchSide / 2
        pillSwatch.backgroundColor = currentColor?.nsColor.cgColor ?? NSColor.clear.cgColor
        // Text frames add a little leading; the −1 centres the caps optically.
        pillText.frame = CGRect(x: Self.pillHeight, y: (Self.pillHeight - ceil(textSize.height)) / 2 - 1, width: ceil(textSize.width) + 4,
                                height: ceil(textSize.height) + 2)

        if let prompt = session.promptText {
            promptBadge.text = prompt
            let size = promptBadge.preferredFrameSize()
            promptBadge.frame = CGRect(x: (frame.midX - size.width / 2).rounded(), y: frame.maxY + Spacing.s, width: size.width, height: size.height)
        }
        let hint = hintBadge.preferredFrameSize()
        hintBadge.frame = CGRect(x: (bounds.midX - hint.width / 2).rounded(), y: bounds.maxY - 64 - hint.height,
                                 width: hint.width, height: hint.height)
        setAccessibilityValue(text)
    }

    static let pillHeight: CGFloat = 24
    static let pillSwatchInset = Spacing.xs
    /// Room between the text and the pill's trailing round end.
    static let pillTrailing = Spacing.m
    static let ringWidth: CGFloat = 3

    /// Where the readout goes: inside the circle near the bottom when the whole capsule
    /// (both round ends) clears the ring by `Spacing.xs`, otherwise under the loupe.
    static func pillLayout(textWidth: CGFloat, diameter d: CGFloat) -> (width: CGFloat, inside: Bool, insideBottom: CGFloat) {
        let width = textWidth + pillHeight + pillTrailing
        let bottom = (d * 0.16).rounded()
        let r = d / 2, end = pillHeight / 2
        // The centres of the capsule's round ends, relative to the circle's centre.
        let dx = width / 2 - end, dy = r - (bottom + end)
        let inside = (dx * dx + dy * dy).squareRoot() + end + ringWidth + Spacing.xs <= r
        return (width, inside, bottom)
    }

    /// The pixel's color, converted with ColorSync from the capture's color space to
    /// extended sRGB (keeps colors more vivid than sRGB). Nil for transparent pixels (parts
    /// masked out in test mode).
    static func color(at p: PixelPoint, in image: CGImage) -> ColorValue? {
        guard p.x >= 0, p.y >= 0, p.x < image.width, p.y < image.height,
              let crop = image.cropping(to: CGRect(x: p.x, y: p.y, width: 1, height: 1)),
              let space = CGColorSpace(name: CGColorSpace.extendedSRGB) else { return nil }
        var px = [Float](repeating: 0, count: 4)
        let drawn = px.withUnsafeMutableBytes { raw -> Bool in
            let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
            guard let context = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 32, bytesPerRow: 16,
                                          space: space, bitmapInfo: info) else { return false }
            context.interpolationQuality = .none
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn, px[3] > 0.5 else { return nil }
        let a = Double(px[3])
        return ColorValue(red: Double(px[0]) / a, green: Double(px[1]) / a, blue: Double(px[2]) / a)
    }
}
