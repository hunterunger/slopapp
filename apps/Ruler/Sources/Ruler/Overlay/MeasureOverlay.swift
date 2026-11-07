import AppKit
import QuartzCore
import RulerCore
import SlopKit
import UniformTypeIdentifiers

/// The measuring session: one borderless panel per display over a frozen image of it.
///
/// Shows the panels at once, freezes every display with ScreenCaptureKit in the background
/// and swaps the image in when it arrives, then decodes its pixels (off the main thread) for
/// edge finding. Keys act on the display under the pointer. Esc closes; focus goes back to
/// the app that was in front.
///
/// **Background mode:** the shortcut (with something measured), B, or switching to another
/// app keeps the measurements on screen over the live display, click-through, and gives the
/// Mac back. The shortcut again picks the session up with a fresh freeze.
@MainActor
final class MeasureOverlay {
    enum Phase { case active, background }

    /// The session on screen, if any (only one at a time).
    private(set) static var current: MeasureOverlay?

    let model: AppModel
    private let capturer: ScreenCapturing
    private var exclusions: CaptureExclusions
    private var panels: [MeasurePanel] = []
    private var previousApp: NSRunningApplication?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var finished = false
    private var started: TimeInterval = 0
    private(set) var phase: Phase = .active
    /// Bumped on every freeze, so a late snapshot from an earlier one is dropped.
    private var freezeGeneration = 0
    /// Board states before each change, for ⌘Z.
    private var history: [(displayID: CGDirectDisplayID, board: Board)] = []
    /// Space held during a drag: the box moves instead of resizing.
    private(set) var isSpaceHeld = false
    /// ⌘S: the next box drawn is saved as a screenshot instead of measured.
    private(set) var capturesNextBox = false
    /// Test hook: the view `testHover` pointed at, so keys act there regardless of the real pointer.
    private weak var testPointerView: MeasureView?

    var onClose: ((Error?) -> Void)?

    init(model: AppModel, capturer: ScreenCapturing, exclusions: CaptureExclusions) {
        self.model = model
        self.capturer = capturer
        self.exclusions = exclusions
    }

    var views: [MeasureView] { panels.map(\.measureView) }
    var hasMeasurements: Bool { views.contains { !$0.board.isEmpty } }

    /// The view under the pointer (keys act there).
    var pointerView: MeasureView? {
        if let testPointerView { return testPointerView }
        let mouse = NSEvent.mouseLocation
        return (panels.first { NSMouseInRect(mouse, $0.frame, false) } ?? panels.first)?.measureView
    }

    // MARK: Showing

    func show(started: TimeInterval, restoring session: SavedSession? = nil) {
        Self.current?.close()
        Self.current = self
        self.started = started
        previousApp = NSWorkspace.shared.frontmostApplication
        for screen in NSScreen.screens {
            let panel = MeasurePanel(screen: screen, overlay: self, testMode: TestScene.isActive)
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        if let session { apply(session, undoable: false) }
        takeFocus()
        CATransaction.flush()
        Diagnostics.record("overlay shown ms=\(Diagnostics.milliseconds(since: started)) screens=\(panels.count) testMode=\(TestScene.isActive) restored=\(session != nil)")
        observeSystem()
        freeze()
    }

    private func takeFocus() {
        AppActivation.activate()
        let pointerScreen = NSScreen.underPointer
        (panels.first { $0.screen == pointerScreen } ?? panels.first)?.makeKeyAndOrderFront(nil)
        refreshPointer()
    }

    /// Snapshots every display and hands each view its image, then its pixels.
    private func freeze() {
        freezeGeneration += 1
        let generation = freezeGeneration
        let ids = views.map(\.displayID)
        let capturer = self.capturer
        let exclusions = self.exclusions
        let started = self.started
        Task { @MainActor [weak self] in
            do {
                let images = try await capturer.snapshot(displays: ids, excluding: exclusions)
                guard let self, self.isCurrent(generation) else { return }
                for view in self.views { view.snapshot = images[view.displayID] }
                Diagnostics.record("snapshot ready ms=\(Diagnostics.milliseconds(since: started))")
                await self.decode(images, generation: generation)
            } catch {
                guard let self, self.isCurrent(generation) else { return }
                self.close(error: error)
            }
        }
    }

    private func isCurrent(_ generation: Int) -> Bool {
        !finished && phase == .active && generation == freezeGeneration
    }

    /// Decodes each frozen image into pixels for edge finding, off the main thread.
    private func decode(_ images: [CGDirectDisplayID: CGImage], generation: Int) async {
        for view in views {
            guard let image = images[view.displayID] else { continue }
            let frozen = FrozenDisplay(displayID: view.displayID, frame: .zero, image: image)
            let edges = await Task.detached(priority: .userInitiated) { Self.decode(frozen.image) }.value
            guard isCurrent(generation) else { return }
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
        // Screen parameters also change when only the Dock or menu bar resizes (the visible
        // frame): the frozen images still fit then. Close only when a display itself changed.
        let layout = Self.displayLayout()
        observers.append((center, center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard Self.displayLayout() != layout else {
                    Diagnostics.record("screen parameters changed, displays unchanged: kept")
                    return
                }
                Diagnostics.record("overlay closed by system event=displays changed")
                self?.close()
            }
        }))
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main, using: close)))
        }
        // Another app coming forward (⌘Tab, a notification, Dock): step back and keep the
        // measurements on screen rather than lose them.
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, self.phase == .active, pid != ProcessInfo.processInfo.processIdentifier else { return }
                Diagnostics.record("another app activated pid=\(pid ?? 0)")
                if self.hasMeasurements { self.enterBackground(returnFocus: false) } else { self.close() }
            }
        }))
    }

    /// Each display's id, frame and scale: what the panels and frozen images depend on.
    private static func displayLayout() -> [String] {
        NSScreen.screens.map { "\($0.displayID) \($0.frame) \($0.backingScaleFactor)" }
    }

    /// Re-reads the pointer for every display (after showing, or a settings change).
    func refreshPointer() {
        let mouse = NSEvent.mouseLocation
        for panel in panels {
            let view = panel.measureView
            view.pointer = NSMouseInRect(mouse, panel.frame, false) && phase == .active ? panel.convertPoint(fromScreen: mouse) : nil
            view.refresh()
        }
    }

    func settingsChanged() {
        for view in views { view.refresh(force: true) }
    }

    // MARK: Background mode

    /// Keeps the measurements on screen, click-through, over the live display.
    func enterBackground(returnFocus: Bool) {
        guard phase == .active, !finished else { return }
        phase = .background
        freezeGeneration += 1
        isSpaceHeld = false
        testPointerView = nil
        for panel in panels {
            panel.ignoresMouseEvents = true
            panel.measureView.enterBackground()
        }
        if returnFocus, NSApp.isActive, let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate()
        }
        model.overlayPhaseChanged(.background)
        Diagnostics.record("overlay background items=\(views.map(\.board.count).reduce(0, +))")
        Memory.relieveSoon()
    }

    /// Picks the session back up: a fresh freeze, the same measurements.
    func resume(started: TimeInterval) {
        guard phase == .background, !finished else { return }
        phase = .active
        self.started = started
        previousApp = NSWorkspace.shared.frontmostApplication
        exclusions = model.exclusions
        for panel in panels {
            panel.ignoresMouseEvents = false
            panel.measureView.leaveBackground()
            panel.orderFrontRegardless()
        }
        takeFocus()
        model.overlayPhaseChanged(.active)
        Diagnostics.record("overlay resumed ms=\(Diagnostics.milliseconds(since: started))")
        freeze()
    }

    // MARK: Closing

    func close(error: Error? = nil) {
        guard !finished else { return }
        finished = true
        if error == nil { model.saveSession(session) }
        for panel in panels { panel.orderOut(nil) }
        if phase == .active, NSApp.isActive, let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
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

    // MARK: Sessions

    /// What's on screen now, per display.
    var session: SavedSession {
        SavedSession(displays: views.map {
            .init(key: Self.displayKey($0.displayID), width: $0.imageBounds.width, height: $0.imageBounds.height, board: $0.board)
        })
    }

    func restore(_ saved: SavedSession) {
        let restored = apply(saved, undoable: true)
        toast(restored ? "Restored Last Session" : "Nothing to restore on these displays")
    }

    @discardableResult
    private func apply(_ saved: SavedSession, undoable: Bool) -> Bool {
        var any = false
        for view in views {
            let bounds = view.imageBounds
            guard let board = saved.board(for: Self.displayKey(view.displayID), width: bounds.width, height: bounds.height) else { continue }
            any = true
            if undoable { change(view) { $0 = board } } else { view.board = board; view.refresh(force: true) }
        }
        Diagnostics.record("session restored=\(any)")
        return any
    }

    /// A display id that survives reboots and reconnecting.
    static func displayKey(_ id: CGDirectDisplayID) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) as String? else { return "display-\(id)" }
        return string
    }

    // MARK: Board changes (undoable)

    func recordUndo(_ view: MeasureView) {
        history.append((view.displayID, view.board))
        if history.count > 200 { history.removeFirst() }
    }

    func change(_ view: MeasureView, _ body: (inout Board) -> Void) {
        recordUndo(view)
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
        guard phase == .active else { return false }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch event.keyCode {
        case 53: // Esc
            if view.isDragging {
                view.cancelDrag()
            } else if capturesNextBox {
                capturesNextBox = false
                toast("Screenshot canceled")
            } else {
                close()
            }
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
            case "s": beginAreaScreenshot(); return true
            default: return false
            }
        }
        guard !event.isARepeat || key == "=" || key == "-" else { return true }
        switch key {
        case "h": addGuide(.horizontal, in: view)
        case "v": addGuide(.vertical, in: view)
        case "p": holdDistance(in: view, axes: [.horizontal, .vertical])
        case "x": holdDistance(in: view, axes: [.horizontal])
        case "y": holdDistance(in: view, axes: [.vertical])
        case "s": takeScreenshot(copy: false, in: view, flipPadding: flags.contains(.option))
        case "c": takeScreenshot(copy: true, in: view, flipPadding: flags.contains(.option))
        case "b": hasMeasurements ? enterBackground(returnFocus: true) : toast("Nothing to keep on screen")
        case "u": model.unit = model.unit.toggled; toast("Units: \(model.unit.title)")
        case "z": model.showMagnifier.toggle(); toast(model.showMagnifier ? "Magnifier On" : "Magnifier Off")
        case "t": model.tolerance = model.tolerance.cycled; toast("Edge tolerance: \(model.tolerance.title)")
        case "?", "/": model.showHints.toggle()
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
        guard let reading = view.copyableReading() else {
            NSSound.beep()
            return
        }
        let readout = view.readout
        model.copy(model.copyFormat.text(reading, readout: readout))
        toast("Copied \(readout.text(reading))")
        Diagnostics.record("copied format=\(model.copyFormat.rawValue) value=\(readout.text(reading))")
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

    /// Where a guide on `axis` near `position` lands: the nearest image edge, placed area
    /// side or midpoint between guides within 4 pt; else where it is.
    func snappedGuidePosition(_ axis: GuideAxis, _ position: Int, in view: MeasureView, excluding: Int? = nil) -> Int {
        let reach = Int((4 * view.scale).rounded())
        let probe = axis == .vertical
            ? PixelPoint(x: min(position, view.imageBounds.maxX - 1), y: view.pointerPixel?.y ?? view.imageBounds.height / 2)
            : PixelPoint(x: view.pointerPixel?.x ?? view.imageBounds.width / 2, y: min(position, view.imageBounds.maxY - 1))
        let edge = view.edges?.nearestEdge(to: probe, axis: axis, tolerance: model.tolerance, maxDistance: reach)
        let board = view.board.nearestGuideSnap(axis, to: position, maxDistance: reach, excluding: excluding)
        let candidates = [edge, board].compactMap { $0 }
        return candidates.min { abs($0 - position) < abs($1 - position) } ?? position
    }

    func addGuide(_ axis: GuideAxis, in view: MeasureView) {
        guard let pixel = view.pointerPixel else { return }
        let position = snappedGuidePosition(axis, axis == .vertical ? pixel.x : pixel.y, in: view)
        change(view) { $0.addGuide(axis, at: position) }
        Diagnostics.record("guide added axis=\(axis.rawValue) at=\(view.readout.length(position))")
    }

    /// Holds the hover distance on screen: both axes (P), or just the width (X) or height (Y).
    func holdDistance(in view: MeasureView, axes: [GuideAxis]) {
        guard let pixel = view.pointerPixel, let spans = view.hoverSpans else {
            NSSound.beep()
            return
        }
        change(view) { $0.addPins(point: pixel, spans: spans, axes: axes) }
        let readout = view.readout
        let text = axes.count == 2
            ? readout.spokenSize(width: spans.width, height: spans.height)
            : readout.spoken(.length(axes[0] == .horizontal ? spans.width : spans.height, axis: axes[0]))
        announce(text)
        Diagnostics.record("held axes=\(axes.map(\.rawValue).joined(separator: "+")) size=\(readout.size(width: spans.width, height: spans.height))")
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

    // MARK: Screenshots

    /// In test mode, the test scene's pixels on this display: the only thing a screenshot
    /// may show. `.some(nil)`: test mode, but the scene isn't on this display.
    private func testSceneLimit(in view: MeasureView) -> PixelRect?? {
        guard TestScene.isActive else { return .none }
        guard let window = TestScene.window, window.isVisible, let panel = view.window else { return .some(nil) }
        let local = panel.convertFromScreen(window.frame)
        return .some(view.pixelRect(local: local).insetBy(1).intersection(view.imageBounds))
    }

    /// The pixels a screenshot of `subject` may show. In test mode: only ever inside the test
    /// scene, and nothing at all on a display without it.
    func screenshotCrop(subject: PixelRect?, padding: Int, in view: MeasureView) -> PixelRect? {
        let limit = testSceneLimit(in: view)
        if case .some(nil) = limit { return nil }
        return ScreenshotPlan.crop(subject: subject, padding: padding, image: view.imageBounds, allowed: limit ?? nil)
    }

    func beginAreaScreenshot() {
        capturesNextBox = true
        toast("Drag over the area to save")
    }

    /// The box drawn after ⌘S: saved as drawn (no snapping, no padding).
    func captureBox(_ rect: PixelRect, in view: MeasureView) {
        capturesNextBox = false
        guard let crop = screenshotCrop(subject: rect, padding: 0, in: view),
              let image = view.renderScreenshot(crop: crop, at1x: model.screenshotAt1x) else {
            NSSound.beep()
            toast("Nothing to capture here")
            return
        }
        Diagnostics.record("screenshot area crop=\(crop) image=\(image.width)x\(image.height)")
        save(image, scale: view.scale)
    }

    private func save(_ image: CGImage, scale: CGFloat) {
        do {
            let url = try ScreenshotWriter.save(image, format: model.screenshotFormat, to: model.screenshotFolder,
                                                pixelsPerPoint: model.screenshotAt1x ? 1 : scale)
            toast("Saved \(url.lastPathComponent)")
            Diagnostics.record("screenshot saved name=\(url.lastPathComponent)")
        } catch {
            NSSound.beep()
            toast("Couldn't save the screenshot")
            Diagnostics.record("screenshot save failed error=\(error)")
        }
    }

    /// S saves, C copies: the hovered area (else everything measured, else the display) with
    /// padding, the measurements drawn in. ⌥ flips the padding on or off.
    func takeScreenshot(copy: Bool, in view: MeasureView, flipPadding: Bool) {
        guard view.snapshot != nil else {
            toast("Still freezing the screen")
            return
        }
        var padding = model.screenshotPadding
        if flipPadding { padding = padding > 0 ? 0 : 24 }
        guard let crop = screenshotCrop(subject: view.screenshotSubject(), padding: Int((padding * view.scale).rounded()), in: view),
              let image = view.renderScreenshot(crop: crop, at1x: model.screenshotAt1x) else {
            NSSound.beep()
            toast("Nothing to capture here")
            return
        }
        let allowed: PixelRect? = testSceneLimit(in: view) ?? nil
        Diagnostics.record("screenshot copy=\(copy) crop=\(crop) image=\(image.width)x\(image.height) withinScene=\(allowed.map { $0.contains(crop) }.map(String.init) ?? "n/a")")
        let pointSize = CGSize(width: CGFloat(crop.width) / view.scale, height: CGFloat(crop.height) / view.scale)
        if copy {
            model.pasteboard.write(image: image, pointSize: pointSize)
            toast("Screenshot Copied")
            return
        }
        save(image, scale: view.scale)
    }

    // MARK: Context menu

    func showContextMenu(at point: CGPoint, in view: MeasureView) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let reading = view.copyableReading()
        let readout = view.readout
        let copyTitle = reading.map { "Copy \(readout.text($0))" } ?? "Copy"
        menu.addItem(ClosureMenuItem(copyTitle, key: "\r", enabled: reading != nil) { [weak self, weak view] in
            if let view { self?.copyMeasurement(from: view) }
        })
        let copyAs = NSMenuItem(title: "Copy As", action: nil, keyEquivalent: "")
        let copyAsMenu = NSMenu()
        copyAsMenu.autoenablesItems = false
        for format in CopyFormat.allCases {
            copyAsMenu.addItem(ClosureMenuItem(format.shortTitle, enabled: reading != nil) { [weak self, weak view] in
                if let view { self?.copy(format, from: view) }
            })
        }
        copyAs.submenu = copyAsMenu
        copyAs.isEnabled = reading != nil
        menu.addItem(copyAs)
        menu.addItem(ClosureMenuItem("Copy Screenshot", key: "c") { [weak self, weak view] in
            if let view { self?.takeScreenshot(copy: true, in: view, flipPadding: false) }
        })
        menu.addItem(ClosureMenuItem("Save Screenshot", key: "s") { [weak self, weak view] in
            if let view { self?.takeScreenshot(copy: false, in: view, flipPadding: false) }
        })
        menu.addItem(ClosureMenuItem("Save Screenshot of Area…", key: "s", modifiers: .command) { [weak self] in
            self?.beginAreaScreenshot()
        })
        menu.addItem(ClosureMenuItem("Delete", key: "\u{8}", enabled: view.hoveredItem != nil) { [weak self, weak view] in
            if let view { self?.deleteHovered(in: view) }
        })
        menu.addItem(.separator())
        let canHold = view.hoverSpans != nil
        menu.addItem(ClosureMenuItem("Hold Distance", key: "p", enabled: canHold) { [weak self, weak view] in
            if let view { self?.holdDistance(in: view, axes: [.horizontal, .vertical]) }
        })
        menu.addItem(ClosureMenuItem("Hold Width", key: "x", enabled: canHold) { [weak self, weak view] in
            if let view { self?.holdDistance(in: view, axes: [.horizontal]) }
        })
        menu.addItem(ClosureMenuItem("Hold Height", key: "y", enabled: canHold) { [weak self, weak view] in
            if let view { self?.holdDistance(in: view, axes: [.vertical]) }
        })
        menu.addItem(ClosureMenuItem("Add Horizontal Guide", key: "h") { [weak self, weak view] in
            if let view { self?.addGuide(.horizontal, in: view) }
        })
        menu.addItem(ClosureMenuItem("Add Vertical Guide", key: "v") { [weak self, weak view] in
            if let view { self?.addGuide(.vertical, in: view) }
        })
        menu.addItem(.separator())
        menu.addItem(submenu("Edge Tolerance", Tolerance.allCases.map { level in
            (level.title, level == model.tolerance, { [weak self] in self?.model.tolerance = level })
        }))
        menu.addItem(submenu("Units", MeasureUnit.allCases.map { unit in
            (unit.title, unit == model.unit, { [weak self] in self?.model.unit = unit })
        }))
        menu.addItem(submenu("Scale", DesignScale.presets.map { value in
            (DesignScale.title(value), value == model.designScale, { [weak self] in self?.model.designScale = value })
        }))
        let magnifier = ClosureMenuItem("Show Magnifier", key: "z") { [weak self] in self?.model.showMagnifier.toggle() }
        magnifier.state = model.showMagnifier ? .on : .off
        menu.addItem(magnifier)
        let hints = ClosureMenuItem("Show Key Hints", key: "?") { [weak self] in self?.model.showHints.toggle() }
        hints.state = model.showHints ? .on : .off
        menu.addItem(hints)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Undo", key: "z", modifiers: .command, enabled: !history.isEmpty) { [weak self] in self?.undo() })
        menu.addItem(ClosureMenuItem("Clear All", key: "\u{8}", modifiers: .command, enabled: hasMeasurements) { [weak self] in
            self?.clearAll()
        })
        menu.addItem(ClosureMenuItem("Restore Last Session", enabled: model.hasSavedSession) { [weak self] in
            if let saved = self?.model.savedSession { self?.restore(saved) }
        })
        menu.addItem(ClosureMenuItem("Keep on Screen", key: "b", enabled: hasMeasurements) { [weak self] in
            self?.enterBackground(returnFocus: true)
        })
        menu.addItem(ClosureMenuItem("Done Measuring", key: "\u{1b}") { [weak self] in self?.close() })

        Diagnostics.record("context menu open")
        menu.popUp(positioning: nil, at: point, in: view)
        // A right-click outside the menu only closes it; the same click should open the
        // next one, as context menus do elsewhere.
        let rightHeld = NSEvent.pressedMouseButtons & 0b10 != 0
        let closer = NSApp.currentEvent
        let closedByRightClick = closer.map { $0.type == .rightMouseDown || ($0.type == .leftMouseDown && $0.modifierFlags.contains(.control)) } ?? false
        Diagnostics.record("context menu closed rightHeld=\(rightHeld) closer=\(closer.map { String(describing: $0.type) } ?? "none")")
        guard !finished, phase == .active, rightHeld || closedByRightClick else { return }
        let mouse = NSEvent.mouseLocation
        guard let target = panels.first(where: { NSMouseInRect(mouse, $0.frame, false) })?.measureView else { return }
        if rightHeld {
            target.beginRightPressAtPointer()
        } else if let window = target.window {
            let local = target.convert(window.convertPoint(fromScreen: mouse), from: nil)
            DispatchQueue.main.async { [weak self, weak target] in
                guard let self, let target, !self.finished else { return }
                self.showContextMenu(at: local, in: target)
            }
        }
    }

    private func submenu(_ title: String, _ items: [(String, Bool, () -> Void)]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (name, on, action) in items {
            let entry = ClosureMenuItem(name, handler: action)
            entry.state = on ? .on : .off
            sub.addItem(entry)
        }
        item.submenu = sub
        return item
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

    /// Privacy check (test mode): every screenshot crop stays inside the test scene, and
    /// every frozen pixel outside the scene is masked (fully transparent).
    func screenshotLeakCheck() {
        guard TestScene.isActive else { return }
        var failures = 0, checked = 0
        for view in views {
            guard let edges = view.edges else { continue }
            let limit = testSceneLimit(in: view)
            guard case .some(let scene) = limit else { continue }
            // 1. The production crop for the whole display, each area, everything measured
            //    and the hovered subject, at several paddings.
            var subjects: [PixelRect?] = [nil, view.board.measuredBounds, view.imageBounds, view.screenshotSubject()]
            subjects += view.board.areas.map { Optional($0.rect) }
            for subject in subjects {
                for padding in [0, 48, 4000] {
                    let crop = screenshotCrop(subject: subject, padding: padding, in: view)
                    checked += 1
                    switch (scene, crop) {
                    case (nil, nil): break
                    case (let scene?, let crop?) where scene.contains(crop): break
                    case (_?, nil) where subject.map({ $0.outsetBy(padding).intersection(scene!) == nil }) == true: break
                    default: failures += 1
                    }
                }
            }
            // 2. Nothing but the scene in the frozen pixels (a grid of samples).
            let step = max(8, edges.width / 200)
            var leaked = 0
            for y in stride(from: 0, to: edges.height, by: step) {
                for x in stride(from: 0, to: edges.width, by: step) {
                    let p = PixelPoint(x: x, y: y)
                    if let scene, scene.insetBy(-2).contains(p) { continue }
                    if edges.alpha(at: p) != 0 { leaked += 1 }
                }
            }
            if leaked > 0 { failures += 1 }
            Diagnostics.record("leakcheck display=\(view.displayID) scene=\(scene.map(String.init(describing:)) ?? "none") unmaskedOutside=\(leaked)")
        }
        Diagnostics.record("leakcheck done crops=\(checked) failures=\(failures)")
        toast("Leak check: \(failures == 0 ? "clean" : "\(failures) failures")")
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

    /// Test hook: a left-button drag from one scene point to another, delivered straight to
    /// the view (the real pointer doesn't move). `shift` holds ⇧ throughout.
    func testMouseDrag(from a: CGPoint, to b: CGPoint, shift: Bool, release: Bool = true) {
        guard let window = TestScene.window, let sceneView = TestScene.view else { return }
        let ga = window.convertPoint(toScreen: sceneView.convert(a, to: nil))
        let gb = window.convertPoint(toScreen: sceneView.convert(b, to: nil))
        guard let view = views.first(where: { $0.window.map { NSMouseInRect(ga, $0.frame, false) } ?? false }), let panel = view.window else { return }
        testPointerView = view
        let flags: NSEvent.ModifierFlags = shift ? .shift : []
        func event(_ type: NSEvent.EventType, _ global: CGPoint) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: panel.convertPoint(fromScreen: global), modifierFlags: flags, timestamp: 0,
                               windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        }
        view.pointerMoved(to: panel.convertPoint(fromScreen: ga), modifiers: flags)
        if let e = event(.leftMouseDown, ga) { view.mouseDown(with: e) }
        for i in 1...8 {
            let t = CGFloat(i) / 8
            let p = CGPoint(x: ga.x + (gb.x - ga.x) * t, y: ga.y + (gb.y - ga.y) * t)
            if let e = event(.leftMouseDragged, p) { view.mouseDragged(with: e) }
        }
        guard release else { return }
        if let e = event(.leftMouseUp, gb) { view.mouseUp(with: e) }
        Diagnostics.record("test drag done areas=\(view.board.areas.map { "\($0.rect.width)x\($0.rect.height)" }) guides=\(view.board.guides.map(\.position))")
    }

    /// Test hook: modifier keys as if held ("shift", "command", "none"), for the crosshair
    /// and free-box states.
    func testFlags(_ name: String) {
        let flags: NSEvent.ModifierFlags = switch name {
        case "shift": .shift
        case "command": .command
        default: []
        }
        pointerView?.modifiersChanged(flags)
    }

    /// Test hook (test scene only): writes the overlay of the display under the test pointer,
    /// everything as drawn, at 1×, to a PNG.
    func dump(to path: String) {
        guard TestScene.isActive, let view = pointerView, let image = view.renderOverlay() else { return }
        let url = URL(fileURLWithPath: path)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        let ok = CGImageDestinationFinalize(destination)
        Diagnostics.record("dump ok=\(ok) size=\(image.width)x\(image.height)")
    }

    /// Test hook: a key as if typed on the overlay at the test pointer: a letter, or
    /// "return", "delete", "escape", "cmd-z", "cmd-c", "cmd-delete", "opt-s", "opt-c".
    func testKey(_ name: String) {
        guard let view = pointerView, let window = view.window else { return }
        var flags: NSEvent.ModifierFlags = []
        var key = name
        if key.hasPrefix("cmd-") { flags.insert(.command); key.removeFirst(4) }
        if key.hasPrefix("opt-") { flags.insert(.option); key.removeFirst(4) }
        let named: [String: (UInt16, String)] = ["return": (36, "\r"), "delete": (51, "\u{8}"), "escape": (53, "\u{1b}")]
        let (code, characters) = named[key] ?? (0, key)
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, characters: characters,
                                           charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { return }
        _ = handleKeyDown(event, in: view)
    }
}

/// Writes measurement screenshots to disk.
enum ScreenshotWriter {
    struct Failure: Error {}

    static func save(_ image: CGImage, format: ScreenshotFormat, to folder: URL, pixelsPerPoint: CGFloat) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        let base = ScreenshotPlan.fileName(date: parts, ext: format.fileExtension)
        var url = folder.appendingPathComponent(base)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(base.replacingOccurrences(of: ".\(format.fileExtension)", with: " \(n).\(format.fileExtension)"))
            n += 1
        }
        let type = (format == .png ? UTType.png : UTType.jpeg).identifier as CFString
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else { throw Failure() }
        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: 72 * pixelsPerPoint,
            kCGImagePropertyDPIHeight: 72 * pixelsPerPoint,
        ]
        if format == .jpeg { properties[kCGImageDestinationLossyCompressionQuality] = 0.9 }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure() }
        return url
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

    override var canBecomeKey: Bool { !ignoresMouseEvents }
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
