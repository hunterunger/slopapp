import AppKit
import ClipsCore
import Observation
import SlopKit
import SwiftUI

/// What the panel shows. Updated in place, so the panel is built once and stays warm.
@MainActor
@Observable
final class PanelState {
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            let started = Diagnostics.now()
            // Typing always goes back to the search.
            if cardsFocused { cardsFocused = false }
            refresh(resetSelection: true)
            Diagnostics.recordWhenIdle("panel search settled results=\(results.count)", since: started)
        }
    }

    var filter: ClipFilter = .all {
        didSet { if filter != oldValue { refresh(resetSelection: true) } }
    }

    private(set) var results: [Clip] = []
    /// Bumped whenever `results` is recomputed (cheaper to compare than the array).
    private(set) var resultsVersion = 0
    /// The history revision `results` was computed from.
    @ObservationIgnored private var resultsRevision = -1
    var selectedID: UUID? {
        didSet { if selectedID != oldValue, pendingPinnedDelete != nil { pendingPinnedDelete = nil } }
    }
    /// A pinned clip waiting for a second ⌘⌫.
    var pendingPinnedDelete: UUID?
    /// Bumped when the selection moves by keyboard, so the strip scrolls to it.
    private(set) var scrollRequest = 0
    /// Bumped on every show, so the search field takes focus again.
    private(set) var focusRequest = 0
    /// ⌘ is held: the first nine cards show their number.
    var commandHeld = false
    /// Tab moved the keyboard to the cards (Space previews; typing goes back to search).
    var cardsFocused = false {
        didSet { if cardsFocused != oldValue { onCardsFocusChange?(cardsFocused) } }
    }
    @ObservationIgnored var onCardsFocusChange: ((Bool) -> Void)?
    var quickLookOpen = false
    /// Whole cards visible at once (the strip reports it), for Page Up / Page Down.
    @ObservationIgnored var pageSize = 5
    /// The app Return pastes into.
    @ObservationIgnored var target: NSRunningApplication?
    private(set) var targetName: String?
    /// "Now" for relative times, fixed while the panel is open.
    private(set) var now = Date()

    @ObservationIgnored private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return results.firstIndex { $0.id == selectedID }
    }

    var selected: Clip? {
        selectedIndex.map { results[$0] }
    }

    /// Resets to "newest clip selected, no search". Only touches what changed: every
    /// assignment to observed state costs a redraw, and this runs on the hot path.
    func prepareForShow(target: NSRunningApplication?) {
        self.target = target
        let name = target?.localizedName
        if targetName != name { targetName = name }
        if Date().timeIntervalSince(now) > 30 { now = Date() }
        if !query.isEmpty { query = "" }
        if filter != .all { filter = .all }
        if pendingPinnedDelete != nil { pendingPinnedDelete = nil }
        if cardsFocused { cardsFocused = false }
        if commandHeld { commandHeld = false }
        if quickLookOpen { quickLookOpen = false }
        if resultsRevision != model.revision { refresh() }
        if selectedID != results.first?.id || selectedIndex != 0 {
            selectedID = results.first?.id
            scrollRequest &+= 1
        }
        focusRequest &+= 1
    }

    /// Re-runs the search. Keeps the selection if it's still listed.
    func refresh(resetSelection: Bool = false) {
        let started = Diagnostics.now()
        results = ClipSearch.run(model.history.clips, query: query, filter: filter)
        resultsRevision = model.revision
        resultsVersion &+= 1
        if resetSelection || selectedIndex == nil {
            if selectedID != results.first?.id { selectedID = results.first?.id }
            scrollRequest &+= 1
        }
        if Diagnostics.isLogging, !query.isEmpty {
            Diagnostics.record("search results=\(results.count) of=\(model.history.clips.count) ms=\(Diagnostics.milliseconds(since: started))")
        }
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let current = selectedIndex ?? 0
        let next = min(max(current + delta, 0), results.count - 1)
        selectedID = results[next].id
        scrollRequest &+= 1
    }

    func select(index: Int) {
        guard results.indices.contains(index) else { return }
        selectedID = results[index].id
        scrollRequest &+= 1
    }

    func cycleFilter(by delta: Int) {
        let all = ClipFilter.allCases
        let index = all.firstIndex(of: filter) ?? 0
        filter = all[(index + delta + all.count) % all.count]
    }
}

/// The panel: a non-activating strip along the bottom of the active screen, with a larger
/// preview (Space) floating above it.
@MainActor
final class PanelController {
    let state: PanelState
    private let model: AppModel
    private var panel: FloatingPanel?
    private var quickLook: FloatingPanel?
    private var didWarmWithHistory = false
    private var monitors: [Any] = []
    /// Where the strip is while showing (its frame may still be sliding into place).
    private var shownFrame: CGRect = .zero

    init(model: AppModel) {
        self.model = model
        state = PanelState(model: model)
        state.onCardsFocusChange = { [weak self] focused in
            // No blinking caret in the search while the cards have the keyboard.
            (self?.panel?.firstResponder as? NSTextView)?.insertionPointColor = focused ? .clear : .controlTextColor
        }
        model.onHistoryChange = { [weak self] in
            guard let self else { return }
            if self.isShowing {
                self.state.refresh()
            } else if !self.didWarmWithHistory, model.isLoaded {
                // Draw once more with the real history so the first show is as fast as later ones.
                self.didWarmWithHistory = true
                self.prewarm()
            }
        }
    }

    /// True while the user can see the panel. (Between uses the panel stays ordered in,
    /// invisible and off-screen, so `isVisible` isn't the answer.)
    private(set) var isShowing = false

    private var actions: PanelActions {
        PanelActions(
            choose: { [weak self] clip, plain in self?.choose(clip, plain: plain) },
            copy: { [weak self] clip in self?.copy(clip) },
            togglePin: { [weak self] clip in self?.model.togglePin(clip) },
            delete: { [weak self] clip in self?.delete(clip) },
            preview: { [weak self] clip in
                self?.state.selectedID = clip.id
                self?.setQuickLook(open: true)
            },
            open: { [weak self] clip in self?.open(clip) },
            reveal: { [weak self] clip in self?.reveal(clip) },
            dismiss: { [weak self] in self?.dismiss() }
        )
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(cornerRadius: PanelMetrics.cornerRadius) { [state, model, actions] in
            PanelView(state: state, model: model, actions: actions)
        }
        panel.keyHandler = { [weak self] event in
            // A parked (closed) panel must never act on keys.
            guard let self, self.isShowing else { return false }
            return self.handleKey(event)
        }
        // Clicking another app closes the strip, but clicking the preview above it must not:
        // so the panel doesn't close itself on losing key status; this decides.
        panel.dismissesOnResignKey = false
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelDidResignKey() }
        }
        // AppKit may hand key status to the parked panel when another of our windows or an
        // alert closes. It's invisible then, so it would swallow keys: take it off screen.
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isShowing else { return }
                self.panel?.orderOut(nil)
            }
        }
        // However it was dismissed (Esc, click outside, Return), park it for the next show.
        panel.onDismiss = { [weak self] in self?.didDismiss() }
        panel.setAccessibilityLabel("Clips")
        panel.animationBehavior = .none
        // The panel handles Tab itself; recomputing the key-view loop for every new card
        // is expensive and pointless here.
        panel.autorecalculatesKeyViewLoop = false
        return panel
    }

    private func panelDidResignKey() {
        guard isShowing else { return }
        // Let AppKit settle who's key now (a click on the preview, an open menu…).
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isShowing, let panel = self.panel, !panel.isKeyWindow else { return }
            if let quickLook = self.quickLook, quickLook.isKeyWindow {
                panel.makeKey()
                return
            }
            Diagnostics.record("panel lost key; closing (key window: \(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "none"))")
            self.dismiss()
        }
    }

    /// Builds and draws the panel once, then parks it.
    func prewarm() {
        guard !isShowing else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        state.prepareForShow(target: nil)
        park(panel)
        panel.displayIfNeeded()
        // The search field's editor is otherwise created on the first real show.
        _ = panel.fieldEditor(true, for: nil)
        warmAppColors()
    }

    /// Loads the icon and header colour of every app in the history now, while nobody is
    /// waiting: done on the first search instead, a dozen cold icon loads cost ~50 ms.
    private func warmAppColors() {
        guard model.isLoaded else { return }
        var seen = Set<String>()
        for clip in model.history.clips {
            guard let id = clip.sourceBundleID, seen.insert(id).inserted else { continue }
            _ = AppTint.color(for: id)
            if seen.count >= 64 { break }
        }
    }

    /// The strip's frame on a screen: the full width of the usable area, at the bottom.
    private func stripFrame(on screen: NSScreen?) -> CGRect {
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let margin = PanelMetrics.margin
        return CGRect(x: visible.minX + margin, y: visible.minY + margin,
                      width: visible.width - margin * 2, height: PanelMetrics.height)
    }

    /// Ordering a window in costs ~40 ms (window server + SwiftUI appearance work), more than
    /// the whole show budget. So between uses the panel stays ordered in: fully transparent,
    /// ignoring the mouse, far off-screen. It parks narrow, because a screen-wide window
    /// keeps a screen-wide backing store (11 MB on a 5K display); widening it on show costs
    /// a few milliseconds of layout.
    private func park(_ panel: FloatingPanel) {
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        let size = CGSize(width: PanelMetrics.parkedWidth, height: PanelMetrics.height)
        panel.setFrame(NSRect(origin: CGPoint(x: -20_000, y: -20_000), size: size), display: false)
        panel.orderFrontRegardless()
    }

    /// Key presses AppKit would otherwise send straight to the search field: Esc (clears a
    /// search or closes the preview first; FloatingPanel closes on Esc before its key handler
    /// runs) and ⌘ held down (shows the cards' numbers).
    private func startMonitors() {
        guard monitors.isEmpty else { return }
        if let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, event.keyCode == 53, self.isShowing, self.panel?.isKeyWindow == true else { return event }
            if let editor = self.panel?.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            if self.state.quickLookOpen {
                self.setQuickLook(open: false)
                return nil
            }
            guard !self.state.query.isEmpty else { return event }
            self.state.query = ""
            return nil
        }) {
            monitors.append(escape)
        }
        if let flags = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            guard let self, self.isShowing else { return event }
            let held = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.shift, .capsLock, .function, .numericPad]) == .command
            if self.state.commandHeld != held { self.state.commandHeld = held }
            return event
        }) {
            monitors.append(flags)
        }
    }

    private func stopMonitors() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }

    private func didDismiss() {
        Diagnostics.record("panel closed")
        isShowing = false
        stopMonitors()
        setQuickLook(open: false)
        if backdrop != nil { testSetBackdrop(false) }
        guard let panel else { return }
        // Get the next show ready while nobody is waiting (after a paste has gone out):
        // clear the search, re-park.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.isShowing else { return }
            self.state.prepareForShow(target: nil)
            self.park(panel)
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
            ImageCache.shared.trim()
            Memory.relieveSoon()
        }
    }

    func toggle(trigger: TimeInterval = Diagnostics.now()) {
        if isShowing { dismiss() } else { show(trigger: trigger) }
    }

    /// `takesKeyboard: false` is for test hooks only: the strip shows without becoming key,
    /// so a person typing elsewhere is never interrupted by a scripted screenshot.
    func show(trigger: TimeInterval = Diagnostics.now(), takesKeyboard: Bool = true) {
        guard !isShowing else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let frontmost = NSWorkspace.shared.frontmostApplication
        let target = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
        model.refreshPermissions()
        // Keep clipboard history out of screen sharing and recordings (a Privacy setting).
        panel.sharingType = model.windowSharingType
        state.prepareForShow(target: target)
        let prepared = Diagnostics.now()
        // The screen the user is working on: where the mouse is.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let frame = stripFrame(on: screen)
        shownFrame = frame
        let slides = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(slides ? frame.offsetBy(dx: 0, dy: -18) : frame, display: false)
        if !panel.isVisible { panel.orderFrontRegardless() }
        panel.ignoresMouseEvents = false
        isShowing = true
        startMonitors()
        if takesKeyboard { panel.makeKey() }
        if slides {
            panel.alphaValue = 0
            panel.displayIfNeeded()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
            panel.displayIfNeeded()
        }
        Diagnostics.record("panel shown clips=\(model.history.clips.count) ms=\(Diagnostics.milliseconds(since: trigger)) prepare=\(String(format: "%.1f", (prepared - trigger) * 1000))")
        // Pick up a copy made in the last half second.
        model.watcher.check()
    }

    func dismiss() {
        guard isShowing else { return }
        panel?.dismiss()
    }

    // MARK: - Test hooks (CLIPS_TEST_HOOKS=1)

    func testSetQuickLook(_ open: Bool) { setQuickLook(open: open) }

    func testTogglePinSelected() {
        if let clip = state.selected { model.togglePin(clip) }
    }

    func testDeleteSelected() {
        if let clip = state.selected { delete(clip) }
    }

    private var backdrop: NSWindow?

    /// A plain window of our own behind the strip and the preview, so a screenshot of that
    /// rectangle shows the glass composited over something real, and nothing of anyone else's.
    func testSetBackdrop(_ on: Bool) {
        backdrop?.orderOut(nil)
        backdrop = nil
        guard on, let panel, isShowing else { return }
        let strip = shownFrame
        let height = strip.height + QuickLookMetrics.gap + QuickLookMetrics.size.height + PanelMetrics.margin * 2
        let frame = CGRect(x: strip.minX - PanelMetrics.margin, y: strip.minY - PanelMetrics.margin,
                           width: strip.width + PanelMetrics.margin * 2, height: height)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        // CLIPS_TEST_BACKDROP=/path/image: a wallpaper-like picture, so the glass reads.
        if let path = ProcessInfo.processInfo.environment["CLIPS_TEST_BACKDROP"], let image = NSImage(contentsOfFile: path) {
            let view = NSImageView(image: image)
            view.imageScaling = .scaleAxesIndependently
            window.contentView = view
        }
        window.level = panel.level
        window.ignoresMouseEvents = true
        window.sharingType = .readOnly
        window.order(.below, relativeTo: panel.windowNumber)
        backdrop = window
    }

    // MARK: - Quick Look

    private func setQuickLook(open: Bool) {
        if open {
            guard isShowing, state.selected != nil, let panel else { return }
            let preview = quickLook ?? makeQuickLook()
            quickLook = preview
            preview.sharingType = model.windowSharingType
            let strip = shownFrame
            let screen = NSScreen.screens.first { $0.frame.intersects(strip) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? strip
            let size = QuickLookMetrics.size
            let y = min(strip.maxY + QuickLookMetrics.gap, visible.maxY - size.height)
            let frame = CGRect(x: strip.midX - size.width / 2, y: max(y, visible.minY), width: size.width, height: size.height)
            preview.setFrame(frame, display: false)
            if preview.parent == nil { panel.addChildWindow(preview, ordered: .above) }
            preview.orderFrontRegardless()
            if !state.quickLookOpen { state.quickLookOpen = true }
        } else {
            if let quickLook {
                quickLook.parent?.removeChildWindow(quickLook)
                quickLook.orderOut(nil)
            }
            if state.quickLookOpen { state.quickLookOpen = false }
        }
    }

    private func makeQuickLook() -> FloatingPanel {
        let preview = FloatingPanel(cornerRadius: PanelMetrics.cornerRadius) { [state] in
            QuickLookView(state: state)
        }
        // Scrolling the preview doesn't need key status, so the strip keeps the keyboard.
        preview.becomesKeyOnlyIfNeeded = true
        preview.dismissesOnResignKey = false
        preview.animationBehavior = .none
        preview.setAccessibilityLabel("Clip Preview")
        preview.keyHandler = { [weak self] event in
            // If a click made the preview key, keys still drive the strip.
            guard let self, self.isShowing else { return false }
            self.panel?.makeKey()
            return self.handleKey(event)
        }
        return preview
    }

    // MARK: - Actions

    private func choose(_ clip: Clip, plain: Bool) {
        let target = state.target
        dismiss()
        model.use(clip, .paste(target: target), plainText: plain ? true : nil)
    }

    private func copy(_ clip: Clip) {
        dismiss()
        model.use(clip, .copy)
    }

    private func open(_ clip: Clip) {
        let url: URL?
        switch clip.kind {
        case .link:
            let text = clip.text.trimmingCharacters(in: .whitespacesAndNewlines)
            url = URL(string: text.lowercased().hasPrefix("www.") ? "https://" + text : text)
        case .file:
            url = clip.filePaths.first.map { URL(fileURLWithPath: $0) }
        default:
            url = nil
        }
        guard let url else { return }
        dismiss()
        NSWorkspace.shared.open(url)
    }

    private func reveal(_ clip: Clip) {
        let urls = clip.filePaths.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return }
        dismiss()
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Pinned clips take a second ⌘⌫ (within a few seconds) so a favourite isn't lost to a
    /// stray key. Any delete can be undone with ⌘Z.
    private func delete(_ clip: Clip) {
        if clip.isPinned, state.pendingPinnedDelete != clip.id {
            state.pendingPinnedDelete = clip.id
            let id = clip.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                if self?.state.pendingPinnedDelete == id { self?.state.pendingPinnedDelete = nil }
            }
            return
        }
        state.pendingPinnedDelete = nil
        let index = state.selectedIndex ?? 0
        model.delete([clip.id])
        state.refresh()
        if !state.results.isEmpty {
            state.select(index: min(index, state.results.count - 1))
        } else {
            setQuickLook(open: false)
        }
    }

    // MARK: - Keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        // Let input methods (Japanese, Chinese…) finish composing before we take Return/arrows.
        let editor = panel?.firstResponder as? NSTextView
        if let editor, editor.hasMarkedText() { return false }
        let flags = event.modifierFlags
        var modifiers: PanelKeys.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        let context = PanelKeys.Context(queryIsEmpty: state.query.isEmpty, cardsFocused: state.cardsFocused,
                                        quickLookOpen: state.quickLookOpen,
                                        searchHasSelection: (editor?.selectedRange().length ?? 0) > 0)
        guard let command = PanelKeys.command(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers,
                                              modifiers: modifiers, context: context) else { return false }
        switch command {
        case .choose(let plain):
            if let clip = state.selected { choose(clip, plain: plain) }
        case .quickPaste(let index, let plain):
            if state.results.indices.contains(index) { choose(state.results[index], plain: plain) }
        case .move(let delta):
            state.moveSelection(by: delta)
        case .first:
            state.select(index: 0)
        case .last:
            state.select(index: state.results.count - 1)
        case .pageBack:
            state.moveSelection(by: -state.pageSize)
        case .pageForward:
            state.moveSelection(by: state.pageSize)
        case .previousTab:
            state.cycleFilter(by: -1)
        case .nextTab:
            state.cycleFilter(by: 1)
        case .toggleFocus:
            state.cardsFocused.toggle()
        case .quickLook:
            setQuickLook(open: !state.quickLookOpen)
        case .copy:
            if let clip = state.selected { copy(clip) }
        case .togglePin:
            if let clip = state.selected { model.togglePin(clip) }
        case .open:
            if let clip = state.selected { open(clip) }
        case .delete:
            if let clip = state.selected { delete(clip) }
        case .undo:
            guard model.canUndoDelete else { return false }
            let restored = model.undoDelete()
            state.refresh()
            if let first = restored.first { state.selectedID = first.id }
        case .togglePause:
            if model.isPaused { model.resume() } else { model.pause(for: nil) }
        case .focusSearch:
            state.cardsFocused = false
        case .close:
            dismiss()
        case .openHistory:
            dismiss()
            HistoryOpener.open()
        case .openSettings:
            dismiss()
            SettingsOpener.open()
        }
        return true
    }
}

/// Opens the Settings window from places that aren't SwiftUI views (the panel's ⌘,).
@MainActor
enum SettingsOpener {
    /// Set by a view that has SwiftUI's `openSettings` action.
    static var action: (() -> Void)?

    /// `activate: false` is for test hooks (opens it behind whatever is in front).
    static func open(activate: Bool = true) {
        if activate { NSApp.activate() }
        if let action {
            action()
        } else {
            // The menu hasn't been opened yet, so SwiftUI's action isn't captured: use the
            // responder chain instead.
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        if activate { SettingsWindow.bringToFront() }
    }
}

/// Hands memory freed by the panel (images, text layout) back to the system, so the idle
/// footprint stays low between uses.
@MainActor
enum Memory {
    private static var task: Task<Void, Never>?

    static func relieveSoon() {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            malloc_zone_pressure_relief(nil, 0)
        }
    }
}
