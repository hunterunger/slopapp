import AppKit
import QuartzCore
import RulerCore
import SlopKit

/// The measuring session: one borderless panel per display over a frozen image of it.
///
/// Shows the panels at once, freezes every display with ScreenCaptureKit in the background
/// and swaps the image in when it arrives, then decodes its pixels (off the main thread) for
/// edge finding. Keys act on the display under the pointer. Esc (or the shortcut again)
/// closes; focus goes back to the app that was in front.
@MainActor
final class MeasureOverlay {
    /// The session on screen, if any (only one at a time).
    private(set) static var current: MeasureOverlay?

    let model: AppModel
    private let capturer: ScreenCapturing
    private let exclusions: CaptureExclusions
    private var panels: [MeasurePanel] = []
    private var previousApp: NSRunningApplication?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var finished = false
    private var started: TimeInterval = 0
    /// Board states before each change, for ⌘Z.
    private var history: [(displayID: CGDirectDisplayID, board: Board)] = []
    /// Space held during a drag: the box moves instead of resizing.
    private(set) var isSpaceHeld = false
    /// Test hook: the view `testHover` pointed at, so keys act there regardless of the real pointer.
    private weak var testPointerView: MeasureView?

    var onClose: ((Error?) -> Void)?

    init(model: AppModel, capturer: ScreenCapturing, exclusions: CaptureExclusions) {
        self.model = model
        self.capturer = capturer
        self.exclusions = exclusions
    }

    var views: [MeasureView] { panels.map(\.measureView) }

    /// The view under the pointer (keys act there).
    var pointerView: MeasureView? {
        if let testPointerView { return testPointerView }
        let mouse = NSEvent.mouseLocation
        return (panels.first { NSMouseInRect(mouse, $0.frame, false) } ?? panels.first)?.measureView
    }

    // MARK: Showing

    func show(started: TimeInterval) {
        Self.current?.close()
        Self.current = self
        self.started = started
        previousApp = NSWorkspace.shared.frontmostApplication
        let pointerScreen = NSScreen.underPointer
        for screen in NSScreen.screens {
            let panel = MeasurePanel(screen: screen, overlay: self, testMode: TestScene.isActive)
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        AppActivation.activate()
        (panels.first { $0.screen == pointerScreen } ?? panels.first)?.makeKeyAndOrderFront(nil)
        refreshPointer()
        CATransaction.flush()
        Diagnostics.record("overlay shown ms=\(Diagnostics.milliseconds(since: started)) screens=\(panels.count) testMode=\(TestScene.isActive)")
        observeSystem()

        let ids = NSScreen.screens.map(\.displayID)
        let capturer = self.capturer
        let exclusions = self.exclusions
        Task { @MainActor [weak self] in
            do {
                let images = try await capturer.snapshot(displays: ids, excluding: exclusions)
                guard let self, !self.finished else { return }
                for view in self.views { view.snapshot = images[view.displayID] }
                Diagnostics.record("snapshot ready ms=\(Diagnostics.milliseconds(since: started))")
                await self.decode(images)
            } catch {
                self?.close(error: error)
            }
        }
    }

    /// Decodes each frozen image into pixels for edge finding, off the main thread.
    private func decode(_ images: [CGDirectDisplayID: CGImage]) async {
        for view in views {
            guard let image = images[view.displayID] else { continue }
            let frozen = FrozenDisplay(displayID: view.displayID, frame: .zero, image: image)
            let edges = await Task.detached(priority: .userInitiated) { Self.decode(frozen.image) }.value
            guard !finished else { return }
            view.edges = edges
        }
        Diagnostics.record("pixels ready ms=\(Diagnostics.milliseconds(since: started))")
    }

    /// Draws a frozen image into 8-bit RGBA, the layout SlopKit's `PixelBuffer` uses, but
    /// into mapped memory that goes straight back to the system when the overlay closes.
    nonisolated private static func decode(_ image: CGImage) -> EdgeImage? {
        let width = image.width, height = image.height
        guard let storage = EdgeImage.storage(width: width, height: height),
              // The capture's own color space: converting (e.g. P3 → sRGB) dithers flat fills.
              let space = image.colorSpace.flatMap({ $0.supportsOutput && $0.model == .rgb ? $0 : nil }) ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: storage.pointer, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return EdgeImage(width: width, height: height, storage: storage)
    }

    private func observeSystem() {
        let close: @Sendable (Notification) -> Void = { [weak self] note in
            let name = note.name.rawValue
            MainActor.assumeIsolated {
                Diagnostics.record("overlay closed by system event=\(name)")
                self?.close()
            }
        }
        let center = NotificationCenter.default
        observers.append((center, center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: close)))
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main, using: close)))
        }
    }

    /// Re-reads the pointer for every display (after showing, or a settings change).
    func refreshPointer() {
        let mouse = NSEvent.mouseLocation
        for panel in panels {
            let view = panel.measureView
            view.pointer = NSMouseInRect(mouse, panel.frame, false) ? panel.convertPoint(fromScreen: mouse) : nil
            view.refresh()
        }
    }

    func settingsChanged() {
        for view in views { view.refresh(force: true) }
    }

    // MARK: Closing

    func close(error: Error? = nil) {
        guard !finished else { return }
        finished = true
        for panel in panels { panel.orderOut(nil) }
        if NSApp.isActive, let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate()
        }
        for (center, observer) in observers { center.removeObserver(observer) }
        observers = []
        // Drop the frozen screens right away: they can be tens of megabytes each.
        for view in views { view.releaseImages() }
        for panel in panels { panel.close() }
        panels = []
        history = []
        if Self.current === self { Self.current = nil }
        Diagnostics.record("overlay closed")
        onClose?(error)
        onClose = nil
        Memory.relieveSoon()
    }

    // MARK: Board changes (undoable)

    func change(_ view: MeasureView, _ body: (inout Board) -> Void) {
        history.append((view.displayID, view.board))
        if history.count > 200 { history.removeFirst() }
        body(&view.board)
        view.refresh(force: true)
    }

    func undo() {
        guard let last = history.popLast(), let view = views.first(where: { $0.displayID == last.displayID }) else {
            NSSound.beep()
            return
        }
        view.board = last.board
        view.refresh(force: true)
    }

    func clearAll() {
        for view in views where !view.board.isEmpty {
            change(view) { $0.clear() }
        }
    }

    // MARK: Keys

    /// Returns true if handled.
    func handleKeyDown(_ event: NSEvent, in view: MeasureView) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch event.keyCode {
        case 53: // Esc
            if view.isDragging { view.cancelDrag() } else { close() }
            return true
        case 36, 76: // Return, Enter
            copyMeasurement(from: view)
            return true
        case 51, 117: // Delete, Forward Delete
            if flags.contains(.command) { clearAll() } else { deleteHovered(in: view) }
            return true
        case 49: // Space
            if view.isDragging { isSpaceHeld = true }
            return true
        default:
            break
        }
        if let arrow = ArrowKey(keyCode: event.keyCode) {
            nudgePointer(arrow, large: flags.contains(.shift))
            return true
        }
        if flags.contains(.command) {
            switch key {
            case "c": copyMeasurement(from: view); return true
            case "z": undo(); return true
            default: return false
            }
        }
        guard !event.isARepeat || key == "=" || key == "-" else { return true }
        switch key {
        case "h": addGuide(.horizontal, in: view)
        case "v": addGuide(.vertical, in: view)
        case "p": pinDistance(in: view)
        case "u": model.unit = model.unit.toggled; toast("Units: \(model.unit.title)")
        case "z": model.showMagnifier.toggle(); toast(model.showMagnifier ? "Magnifier On" : "Magnifier Off")
        case "=", "+": changeTolerance(looser: true)
        case "-", "_": changeTolerance(looser: false)
        default: return false
        }
        return true
    }

    func handleKeyUp(_ event: NSEvent) {
        if event.keyCode == 49 { isSpaceHeld = false }
    }

    // MARK: Actions

    func copyMeasurement(from view: MeasureView) {
        guard let size = view.copyableSize() else {
            NSSound.beep()
            return
        }
        let readout = view.readout
        let text = model.copyFormat.text(width: size.width, height: size.height, readout: readout)
        model.copy(text)
        toast("Copied \(readout.size(width: size.width, height: size.height))")
        Diagnostics.record("copied format=\(model.copyFormat.rawValue) size=\(readout.size(width: size.width, height: size.height))")
    }

    func copy(_ format: CopyFormat, from view: MeasureView) {
        let previous = model.copyFormat
        model.copyFormat = format
        copyMeasurement(from: view)
        model.copyFormat = previous
    }

    func deleteHovered(in view: MeasureView) {
        guard let item = view.hoveredItem else {
            NSSound.beep()
            return
        }
        change(view) { $0.remove(item) }
    }

    func addGuide(_ axis: GuideAxis, in view: MeasureView) {
        guard let pixel = view.pointerPixel else { return }
        let position = view.edges?.nearestEdge(to: pixel, axis: axis, tolerance: model.tolerance,
                                               maxDistance: Int((4 * view.scale).rounded()))
            ?? (axis == .vertical ? pixel.x : pixel.y)
        change(view) { $0.addGuide(axis, at: position) }
        Diagnostics.record("guide added axis=\(axis.rawValue) at=\(view.readout.length(position))")
    }

    func pinDistance(in view: MeasureView) {
        guard let pixel = view.pointerPixel, let spans = view.hoverSpans else { return }
        change(view) { $0.addPin(point: pixel, spans: spans) }
        announce(view.readout.spokenSize(width: spans.width, height: spans.height))
        Diagnostics.record("pinned size=\(view.readout.size(width: spans.width, height: spans.height))")
    }

    private func changeTolerance(looser: Bool) {
        if let next = looser ? model.tolerance.looser : model.tolerance.stricter {
            model.tolerance = next
        } else {
            NSSound.beep()
        }
        toast("Edge tolerance: \(model.tolerance.title)")
    }

    /// Moves the real pointer one unit (Shift: ten) and the measurement with it.
    private func nudgePointer(_ arrow: ArrowKey, large: Bool) {
        guard let view = pointerView, let window = view.window, let current = view.pointer else { return }
        let step = model.unit.nudgeStep(scale: view.scale, large: large)
        let unit = SelectionGeometry.nudge(for: arrow, large: false)
        let local = CGPoint(x: current.x + unit.dx * step, y: current.y + unit.dy * step)
        let global = window.convertPoint(toScreen: local)
        guard NSScreen.screens.contains(where: { NSMouseInRect(global, $0.frame, false) }) else { return }
        CGWarpMouseCursorPosition(ScreenCoordinates.flip(global, primaryHeight: NSScreen.primaryHeight))
        CGAssociateMouseAndMouseCursorPosition(1)
        for other in views {
            guard let otherWindow = other.window else { continue }
            if NSMouseInRect(global, otherWindow.frame, false) {
                other.pointerMoved(to: otherWindow.convertPoint(fromScreen: global), modifiers: NSEvent.modifierFlags)
            } else if other.pointer != nil {
                other.pointer = nil
                other.refresh()
            }
        }
    }

    func toast(_ message: String) {
        pointerView?.showToast(message)
        announce(message)
    }

    func announce(_ message: String) {
        guard let window = pointerView?.window else { return }
        NSAccessibility.post(element: window, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    // MARK: Context menu

    func showContextMenu(at point: CGPoint, in view: MeasureView) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let size = view.copyableSize()
        let readout = view.readout
        let copyTitle = size.map { "Copy \(readout.size(width: $0.width, height: $0.height))" } ?? "Copy"
        menu.addItem(ClosureMenuItem(copyTitle, key: "\r", enabled: size != nil) { [weak self, weak view] in
            if let view { self?.copyMeasurement(from: view) }
        })
        let copyAs = NSMenuItem(title: "Copy As", action: nil, keyEquivalent: "")
        let copyAsMenu = NSMenu()
        copyAsMenu.autoenablesItems = false
        for format in CopyFormat.allCases {
            copyAsMenu.addItem(ClosureMenuItem(format.shortTitle, enabled: size != nil) { [weak self, weak view] in
                if let view { self?.copy(format, from: view) }
            })
        }
        copyAs.submenu = copyAsMenu
        copyAs.isEnabled = size != nil
        menu.addItem(copyAs)
        menu.addItem(ClosureMenuItem("Delete", key: "\u{8}", enabled: view.hoveredItem != nil) { [weak self, weak view] in
            if let view { self?.deleteHovered(in: view) }
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Pin Distance", key: "p", enabled: view.hoverSpans != nil) { [weak self, weak view] in
            if let view { self?.pinDistance(in: view) }
        })
        menu.addItem(ClosureMenuItem("Add Horizontal Guide", key: "h") { [weak self, weak view] in
            if let view { self?.addGuide(.horizontal, in: view) }
        })
        menu.addItem(ClosureMenuItem("Add Vertical Guide", key: "v") { [weak self, weak view] in
            if let view { self?.addGuide(.vertical, in: view) }
        })
        menu.addItem(.separator())
        let tolerance = NSMenuItem(title: "Edge Tolerance", action: nil, keyEquivalent: "")
        let toleranceMenu = NSMenu()
        for level in Tolerance.allCases {
            let item = ClosureMenuItem(level.title) { [weak self] in self?.model.tolerance = level }
            item.state = level == model.tolerance ? .on : .off
            toleranceMenu.addItem(item)
        }
        tolerance.submenu = toleranceMenu
        menu.addItem(tolerance)
        let units = NSMenuItem(title: "Units", action: nil, keyEquivalent: "")
        let unitsMenu = NSMenu()
        for unit in MeasureUnit.allCases {
            let item = ClosureMenuItem(unit.title) { [weak self] in self?.model.unit = unit }
            item.state = unit == model.unit ? .on : .off
            unitsMenu.addItem(item)
        }
        units.submenu = unitsMenu
        menu.addItem(units)
        let magnifier = ClosureMenuItem("Show Magnifier", key: "z") { [weak self] in self?.model.showMagnifier.toggle() }
        magnifier.state = model.showMagnifier ? .on : .off
        menu.addItem(magnifier)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Undo", key: "z", modifiers: .command, enabled: !history.isEmpty) { [weak self] in self?.undo() })
        menu.addItem(ClosureMenuItem("Clear All", key: "\u{8}", modifiers: .command, enabled: views.contains { !$0.board.isEmpty }) { [weak self] in
            self?.clearAll()
        })
        menu.addItem(ClosureMenuItem("Done Measuring", key: "\u{1b}") { [weak self] in self?.close() })
        menu.popUp(positioning: nil, at: point, in: view)
    }

    // MARK: Test hooks

    /// Measures every test-scene shape on the real frozen image and logs expected vs found.
    func selfCheck() {
        guard TestScene.isActive else { return }
        var passed = 0, failed = 0
        for shape in TestSceneLayout.shapes {
            guard let global = TestScene.globalFrame(of: shape),
                  let view = views.first(where: { $0.window.map { NSMouseInRect(CGPoint(x: global.midX, y: global.midY), $0.frame, false) } ?? false }),
                  let window = view.window, let edges = view.edges else {
                Diagnostics.record("selfcheck shape=\(shape.id) skipped (no pixels yet)")
                continue
            }
            let local = window.convertFromScreen(global)
            let expected = view.pixelRect(local: local)
            let readout = view.readout
            // Hover from inside the shape (the outline is hollow: its inside is 1 pt smaller).
            let probe = shape.kind == .darkPanel
                ? PixelPoint(x: expected.minX + 10, y: expected.minY + 10)
                : PixelPoint(x: (expected.minX + expected.maxX) / 2, y: (expected.minY + expected.maxY) / 2)
            let hover = edges.spans(at: probe, tolerance: model.tolerance)
            let expectedHover = shape.kind == .outline ? expected.insetBy(Int(view.scale.rounded())) : expected
            let margin = Int((8 * view.scale).rounded())
            let area = edges.contentBounds(in: expected.insetBy(-margin), tolerance: model.tolerance)
            let hoverOK = hover == expectedHover || shape.kind == .darkPanel && hover.map { $0.minX == expected.minX && $0.minY == expected.minY } == true
            let areaOK = area == expected
            let describe: (PixelRect?) -> String = { $0.map { "\(readout.size(width: $0.width, height: $0.height))@\($0.minX),\($0.minY)" } ?? "none" }
            let ok = !shape.isExact || (hoverOK && areaOK)
            if shape.isExact { if ok { passed += 1 } else { failed += 1 } }
            Diagnostics.record("selfcheck shape=\(shape.id) expected=\(describe(expected)) hover=\(describe(hover)) area=\(describe(area)) noise=\(shape.kind == .gradient || shape.kind == .text ? -1 : edges.noise(in: expected.insetBy(4))) \(shape.isExact ? (ok ? "ok" : "MISMATCH") : "info")")
        }
        Diagnostics.record("selfcheck done passed=\(passed) failed=\(failed) tolerance=\(model.tolerance.title)")
        toast("Self-check: \(passed) passed, \(failed) failed")
    }

    /// Test hook: measure a scene shape as if it had been dragged around loosely.
    func testDrag(sceneRect: CGRect, free: Bool) {
        guard let window = TestScene.window, let sceneView = TestScene.view else { return }
        let global = window.convertToScreen(sceneView.convert(sceneRect, to: nil))
        guard let view = views.first(where: { $0.window.map { NSMouseInRect(CGPoint(x: global.midX, y: global.midY), $0.frame, false) } ?? false }),
              let panel = view.window else { return }
        view.placeArea(drawn: panel.convertFromScreen(global), free: free)
    }

    /// Test hook: point the measurement at a spot in the scene without moving the real pointer.
    func testHover(scenePoint: CGPoint) {
        guard let window = TestScene.window, let sceneView = TestScene.view else { return }
        let global = window.convertPoint(toScreen: sceneView.convert(scenePoint, to: nil))
        for view in views {
            guard let panel = view.window else { continue }
            view.pointer = NSMouseInRect(global, panel.frame, false) ? panel.convertPoint(fromScreen: global) : nil
            if view.pointer != nil { testPointerView = view }
            view.refresh()
        }
    }
}

/// One display's overlay window: borderless, above the menu bar and Dock, key without
/// activating. It sits just below pop-up menus so the context menu can show over it.
@MainActor
final class MeasurePanel: NSPanel {
    let measureView: MeasureView

    init(screen: NSScreen, overlay: MeasureOverlay, testMode: Bool) {
        measureView = MeasureView(frame: CGRect(origin: .zero, size: screen.frame.size), screen: screen, overlay: overlay, testMode: testMode)
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        // Catch clicks everywhere, even where nothing is drawn yet.
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        isMovable = false
        contentView = measureView
        initialFirstResponder = measureView
        title = "Ruler"
        setAccessibilityLabel("Measuring overlay")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = [], enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        keyEquivalentModifierMask = modifiers
        target = self
        isEnabled = enabled
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}

/// Hands freed snapshot memory back to the system soon after the overlay closes.
@MainActor
enum Memory {
    private static var task: Task<Void, Never>?

    static func relieveSoon() {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            malloc_zone_pressure_relief(nil, 0)
        }
    }
}
