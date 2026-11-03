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
    /// Bumped when the selection moves by keyboard, so the list scrolls to it.
    private(set) var scrollRequest = 0
    /// Bumped on every show, so the search field takes focus again.
    private(set) var focusRequest = 0
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

/// The search panel: a non-activating floating panel centered on the active screen.
@MainActor
final class PanelController {
    let state: PanelState
    private let model: AppModel
    private var panel: FloatingPanel?
    private var didWarmWithHistory = false
    private var escapeMonitor: Any?

    init(model: AppModel) {
        self.model = model
        state = PanelState(model: model)
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

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(cornerRadius: 18) { [state, model] in
            PanelView(state: state, model: model, actions: PanelActions(
                choose: { [weak self] clip, plain in self?.choose(clip, plain: plain) },
                copy: { [weak self] clip in self?.copy(clip) },
                togglePin: { [weak self] clip in self?.model.togglePin(clip) },
                delete: { [weak self] clip in self?.delete(clip) },
                dismiss: { [weak self] in self?.dismiss() }
            ))
        }
        panel.keyHandler = { [weak self] event in
            // A parked (closed) panel must never act on keys.
            guard let self, self.isShowing else { return false }
            return self.handleKey(event)
        }
        // AppKit may hand key status to the parked panel when another of our windows or an
        // alert closes. It's invisible then, so it would swallow keys: take it off screen.
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isShowing else { return }
                self.panel?.orderOut(nil)
            }
        }
        // However it was dismissed (Esc, click outside, Return), park it for the next show.
        panel.onDismiss = { [weak self] in self?.didDismiss() }
        panel.setAccessibilityLabel("Clips")
        panel.animationBehavior = .none
        // The panel handles Tab itself; recomputing the key-view loop for every new table row
        // is expensive and pointless here.
        panel.autorecalculatesKeyViewLoop = false
        return panel
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
    }

    /// Ordering a window in costs ~40 ms (window server + SwiftUI appearance work), more than
    /// the whole show budget. So between uses the panel stays ordered in: fully transparent,
    /// ignoring the mouse, far off-screen. Showing it is then a move.
    private func park(_ panel: FloatingPanel) {
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.setFrame(NSRect(origin: CGPoint(x: -20_000, y: -20_000), size: PanelMetrics.size), display: false)
        panel.orderFrontRegardless()
    }

    /// Esc clears a search first and only then closes. FloatingPanel closes on Esc before
    /// the panel's key handler runs, so this uses an app-level monitor, which runs earlier.
    private func watchEscape() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, self.isShowing, self.panel?.isKeyWindow == true,
                  !self.state.query.isEmpty else { return event }
            if let editor = self.panel?.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            self.state.query = ""
            return nil
        }
    }

    private func didDismiss() {
        isShowing = false
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        guard let panel else { return }
        // Get the next show ready while nobody is waiting (after a paste has gone out):
        // clear the search, re-park.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.isShowing else { return }
            self.state.prepareForShow(target: nil)
            self.park(panel)
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
            Memory.relieveSoon()
        }
    }

    func toggle(trigger: TimeInterval = Diagnostics.now()) {
        if isShowing { dismiss() } else { show(trigger: trigger) }
    }

    func show(trigger: TimeInterval = Diagnostics.now()) {
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
        // Fixed size, so place it directly (FloatingPanel.show(at:) measures the content first).
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrame(PanelPlacement.center.frame(size: PanelMetrics.size, mouse: mouse, visibleFrame: visible), display: false)
        if !panel.isVisible { panel.orderFrontRegardless() }
        panel.ignoresMouseEvents = false
        panel.alphaValue = 1
        isShowing = true
        watchEscape()
        panel.makeKey()
        panel.displayIfNeeded()
        Diagnostics.record("panel shown clips=\(model.history.clips.count) ms=\(Diagnostics.milliseconds(since: trigger)) prepare=\(String(format: "%.1f", (prepared - trigger) * 1000))")
        // Pick up a copy made in the last half second.
        model.watcher.check()
    }

    func dismiss() {
        guard isShowing else { return }
        panel?.dismiss()
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
        }
    }

    // MARK: - Keyboard

    /// Key codes for 1–9 on the number row and the keypad.
    private static let digitKeys: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
        83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9,
    ]

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let command = flags.contains(.command)
        // Let input methods (Japanese, Chinese…) finish composing before we take Return/arrows.
        if let editor = panel?.firstResponder as? NSTextView, editor.hasMarkedText() { return false }

        if command, let number = Self.digitKeys[event.keyCode] {
            guard state.results.indices.contains(number - 1) else { return true }
            choose(state.results[number - 1], plain: flags.contains(.shift))
            return true
        }
        switch event.keyCode {
        case 36, 76: // Return, Enter
            if let clip = state.selected { choose(clip, plain: flags.contains(.shift)) }
            return true
        case 125: // ↓
            command ? state.moveSelection(by: .max / 2) : state.moveSelection(by: 1)
            return true
        case 126: // ↑
            command ? state.moveSelection(by: -.max / 2) : state.moveSelection(by: -1)
            return true
        case 121: state.moveSelection(by: 10); return true // Page Down
        case 116: state.moveSelection(by: -10); return true // Page Up
        case 48: // Tab / ⇧Tab
            state.cycleFilter(by: flags.contains(.shift) ? -1 : 1)
            return true
        default:
            break
        }
        guard command else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c":
            // Copy the search text if some of it is selected; otherwise copy the clip.
            if let editor = panel?.firstResponder as? NSTextView, editor.selectedRange().length > 0 { return false }
            if let clip = state.selected { copy(clip) }
            return true
        case "p":
            if let clip = state.selected { model.togglePin(clip) }
            return true
        case "z" where flags.subtracting(.shift) == .command && event.charactersIgnoringModifiers == "z":
            if model.canUndoDelete {
                let restored = model.undoDelete()
                state.refresh()
                if let first = restored.first { state.selectedID = first.id }
                return true
            }
            return false
        case "w":
            dismiss()
            return true
        case "y":
            dismiss()
            HistoryOpener.open()
            return true
        case ",":
            dismiss()
            SettingsOpener.open()
            return true
        default:
            break
        }
        if event.keyCode == 51 || event.keyCode == 117 { // ⌘⌫, ⌘⌦
            if let clip = state.selected { delete(clip) }
            return true
        }
        return false
    }
}

/// Opens the Settings window from places that aren't SwiftUI views (the panel's ⌘,).
@MainActor
enum SettingsOpener {
    /// Set by a view that has SwiftUI's `openSettings` action.
    static var action: (() -> Void)?

    static func open() {
        NSApp.activate()
        if let action {
            action()
        } else {
            // The menu hasn't been opened yet, so SwiftUI's action isn't captured: use the
            // responder chain instead.
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        SettingsWindow.bringToFront()
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
