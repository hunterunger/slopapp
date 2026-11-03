import AppKit
import QuartzCore

/// What the region overlay produced.
public enum RegionSelection {
    /// An area of one display: screen-local AppKit points and the matching pixels cut from
    /// the frozen screen image.
    case area(displayID: CGDirectDisplayID, rect: CGRect, image: CGImage)
    /// A window to capture on its own.
    case window(WindowInfo)
    case cancelled
    case failed(Error)
}

/// The full-screen crosshair overlay for picking an area or a window.
///
/// Shows one borderless panel per display right away (dimming the live screen), freezes each
/// display with a screenshot in the background and swaps it in when it arrives, so the
/// magnifier and the result read the same pixels the user saw. Keys:
/// Esc cancels, Space toggles area/window (or moves the selection while dragging), Shift
/// squares, Option grows from the center, arrows nudge the pointer (Shift: 10 pt), Return
/// takes the whole screen (area mode) or the highlighted window.
///
/// Usage (needs Screen Recording; check `Permission.screenRecording` first):
///
///     let overlay = RegionOverlay(capturer: ScreenCaptureKitCapturer(), mode: .area, options: .init())
///     switch await overlay.run(started: CACurrentMediaTime()) {
///     case .area(let displayID, let rect, let image): …   // image = the frozen pixels
///     case .window(let window): …                         // capture it with captureWindow
///     case .cancelled, .failed: …
///     }
@MainActor
public final class RegionOverlay {
    public enum Mode: Sendable { case area, window }

    public struct Options {
        public var showsMagnifier: Bool
        public var exclusions: CaptureExclusions
        /// Called with timing lines ("overlay shown ms=…").
        public var log: (String) -> Void

        public init(showsMagnifier: Bool = true, exclusions: CaptureExclusions = .init(), log: @escaping (String) -> Void = { _ in }) {
            self.showsMagnifier = showsMagnifier
            self.exclusions = exclusions
            self.log = log
        }
    }

    /// The overlay on screen, if any (only one at a time).
    public private(set) static var current: RegionOverlay?

    public private(set) var mode: Mode
    public let options: Options
    private let capturer: ScreenCapturing
    private var panels: [OverlayPanel] = []
    private var snapshots: [CGDirectDisplayID: CGImage] = [:]
    private var snapshotTask: Task<[CGDirectDisplayID: CGImage], Error>?
    private var continuation: CheckedContinuation<RegionSelection, Never>?
    private var previousApp: NSRunningApplication?
    private var finished = false
    /// When the selection was made (`CACurrentMediaTime`), for latency measurements.
    public private(set) var finishedAt: TimeInterval?
    private(set) var windowList: [WindowInfo] = []
    /// Space held during a drag: the selection moves instead of resizing.
    private(set) var isSpaceHeld = false

    public init(capturer: ScreenCapturing, mode: Mode, options: Options) {
        self.capturer = capturer
        self.mode = mode
        self.options = options
    }

    /// Shows the overlay and waits for a selection. `started` is the trigger time
    /// (`CACurrentMediaTime`) for the latency log.
    public func run(started: TimeInterval) async -> RegionSelection {
        Self.current?.cancel()
        Self.current = self
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            show(started: started)
        }
    }

    public func cancel() {
        finish { .cancelled }
    }

    /// The frozen image of a display, once it has arrived (nil before, and after finishing).
    public func frozenDisplay(_ displayID: CGDirectDisplayID) -> FrozenDisplay? {
        guard let image = snapshots[displayID], let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else { return nil }
        return FrozenDisplay(displayID: displayID, frame: screen.frame, image: image)
    }

    // MARK: Showing

    private func show(started: TimeInterval) {
        // Our own windows can't be picked, except the ones the caller keeps (pins).
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let keep = options.exclusions.keepOwnWindows
        windowList = WindowList.onScreen().filter {
            if let only = options.exclusions.onlyWindows { return only.contains($0.id) }
            return $0.ownerPID != ownPID || keep.contains($0.id)
        }
        previousApp = NSWorkspace.shared.frontmostApplication
        let pointerScreen = NSScreen.underPointer
        for screen in NSScreen.screens {
            let panel = OverlayPanel(screen: screen, overlay: self)
            panels.append(panel)
            panel.orderFrontRegardless()
            if screen == pointerScreen { panel.makeKey() }
        }
        NSApp.activate()
        (panels.first { $0.screen == pointerScreen } ?? panels.first)?.makeKeyAndOrderFront(nil)
        refreshAll()
        CATransaction.flush()
        options.log("overlay shown ms=\(Self.ms(since: started)) screens=\(panels.count)")

        let ids = NSScreen.screens.map(\.displayID)
        let capturer = self.capturer
        let exclusions = options.exclusions
        let task = Task { @MainActor in
            try await capturer.snapshot(displays: ids, excluding: exclusions)
        }
        snapshotTask = task
        Task { @MainActor [weak self] in
            do {
                let images = try await task.value
                guard let self, !self.finished else { return }
                self.snapshots = images
                for panel in self.panels { panel.overlayView.snapshot = images[panel.overlayView.displayID] }
                self.options.log("snapshot ready ms=\(Self.ms(since: started))")
            } catch {
                self?.finish { .failed(error) }
            }
        }
    }

    private static func ms(since start: TimeInterval) -> String {
        String(format: "%.1f", (CACurrentMediaTime() - start) * 1000)
    }

    // MARK: State shared by the panels

    public func setMode(_ newMode: Mode) {
        guard mode != newMode else { return }
        mode = newMode
        for panel in panels { panel.overlayView.modeChanged() }
        refreshAll()
    }

    private func refreshAll() {
        let mouse = NSEvent.mouseLocation
        for panel in panels {
            let view = panel.overlayView
            view.pointer = NSMouseInRect(mouse, panel.frame, false) ? panel.convertPoint(fromScreen: mouse) : nil
            view.refresh()
        }
    }

    /// The panel whose view is under the pointer (keys act there).
    private var pointerView: OverlayView? {
        let mouse = NSEvent.mouseLocation
        return (panels.first { NSMouseInRect(mouse, $0.frame, false) } ?? panels.first)?.overlayView
    }

    /// The front-most window under a screen point (AppKit global).
    func window(atGlobal point: CGPoint) -> WindowInfo? {
        let quartz = ScreenCoordinates.flip(point, primaryHeight: NSScreen.primaryHeight)
        return WindowPicker.window(at: quartz, in: windowList, excludingPID: nil)
    }

    // MARK: Keys

    /// Returns true if handled.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Esc
            cancel()
        case 49: // Space
            if event.isARepeat { return true }
            if panels.contains(where: { $0.overlayView.isDragging }) {
                isSpaceHeld = true
            } else {
                setMode(mode == .area ? .window : .area)
            }
        case 36, 76: // Return, Enter
            guard let view = pointerView else { return true }
            switch mode {
            case .area: completeArea(view.bounds, in: view)
            case .window: if let window = view.hoveredWindow { completeWindow(window) }
            }
        default:
            if let arrow = ArrowKey(keyCode: event.keyCode) {
                nudgePointer(SelectionGeometry.nudge(for: arrow, large: event.modifierFlags.contains(.shift)))
            } else {
                return false
            }
        }
        return true
    }

    func handleKeyUp(_ event: NSEvent) {
        if event.keyCode == 49 { isSpaceHeld = false }
    }

    func modifiersChanged() {
        pointerView?.refresh()
    }

    /// Moves the real pointer (and the selection being dragged) by `delta` points.
    private func nudgePointer(_ delta: CGVector) {
        let mouse = NSEvent.mouseLocation
        let target = CGPoint(x: mouse.x + delta.dx, y: mouse.y + delta.dy)
        guard NSScreen.screens.contains(where: { NSMouseInRect(target, $0.frame, false) }) else { return }
        CGWarpMouseCursorPosition(ScreenCoordinates.flip(target, primaryHeight: NSScreen.primaryHeight))
        CGAssociateMouseAndMouseCursorPosition(1)
        for panel in panels {
            let view = panel.overlayView
            if NSMouseInRect(target, panel.frame, false) {
                view.pointerMoved(to: panel.convertPoint(fromScreen: target), modifiers: NSEvent.modifierFlags)
            } else if view.pointer != nil {
                view.pointer = nil
                view.refresh()
            }
        }
    }

    // MARK: Finishing

    func completeArea(_ rect: CGRect, in view: OverlayView) {
        let displayID = view.displayID
        let screenSize = view.bounds.size
        finish { [snapshotTask] in
            guard let images = try await snapshotTask?.value, let full = images[displayID] else {
                throw CaptureError.displayNotFound
            }
            let scale = CGFloat(full.width) / max(screenSize.width, 1)
            let pixels = ScreenCoordinates.pixelRect(local: rect, screenSize: screenSize, scale: scale)
            guard let cropped = full.cropping(to: pixels) else { throw CaptureError.displayNotFound }
            return .area(displayID: displayID, rect: rect, image: cropped)
        }
    }

    func completeWindow(_ window: WindowInfo) {
        finish { .window(window) }
    }

    /// Takes the overlay down at once, then resolves the result (which may still wait for
    /// the frozen image) and hands it back.
    private func finish(_ result: @escaping @MainActor () async throws -> RegionSelection) {
        guard !finished else { return }
        finished = true
        finishedAt = CACurrentMediaTime()
        for panel in panels { panel.orderOut(nil) }
        if NSApp.isActive, let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate()
        }
        Task { @MainActor in
            let selection: RegionSelection
            do { selection = try await result() } catch { selection = .failed(error) }
            // Drop the frozen screens before handing over: they can be tens of megabytes.
            self.snapshotTask?.cancel()
            self.snapshotTask = nil
            self.snapshots = [:]
            for panel in self.panels { panel.close() }
            self.panels = []
            if Self.current === self { Self.current = nil }
            self.continuation?.resume(returning: selection)
            self.continuation = nil
        }
    }
}

/// One display's overlay window: borderless, above everything, key without activating.
@MainActor
final class OverlayPanel: NSPanel {
    let overlayView: OverlayView

    init(screen: NSScreen, overlay: RegionOverlay) {
        overlayView = OverlayView(frame: CGRect(origin: .zero, size: screen.frame.size), screen: screen, overlay: overlay)
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
        contentView = overlayView
        initialFirstResponder = overlayView
        setAccessibilityLabel("Capture overlay")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
