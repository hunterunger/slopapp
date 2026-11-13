import AppKit
import ClipsCore
import Observation
import SlopKit
import SwiftUI

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
            choose: { [weak self] clips, plain in self?.choose(clips, plain: plain) },
            copy: { [weak self] clips in self?.copy(clips) },
            togglePin: { [weak self] clips in self?.model.togglePin(clips) },
            pin: { [weak self] clips, board in self?.model.pin(Set(clips.map(\.id)), to: board) },
            newBoard: { [weak self] clips in self?.newBoard(with: clips) },
            delete: { [weak self] clips in self?.delete(clips) },
            preview: { [weak self] clip in
                self?.state.selectedID = clip.id
                self?.setQuickLook(open: true)
            },
            edit: { [weak self] clip, title in
                self?.state.selectedID = clip.id
                self?.startEditing(clip, inTitle: title)
            },
            open: { [weak self] clip in self?.open(clip) },
            reveal: { [weak self] clip in self?.reveal(clip) },
            copyImageText: { [weak self] clip in
                guard let text = clip.imageText else { return }
                self?.dismiss()
                self?.model.copyText(text)
            },
            pasteStack: { [weak self] clips in self?.togglePasteStack(with: clips) },
            requestBoardDelete: { [weak self] board in self?.requestBoardDelete(board) },
            dismiss: { [weak self] in self?.dismiss() },
            dragMoved: { [weak self] point in self?.dragMoved(to: point) ?? false },
            dragEnded: { [weak self] point, clips in self?.dragEnded(at: point, clips: clips) ?? false }
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
                // Typing in the editor needs the preview to keep the keyboard.
                if self.state.editor == nil { panel.makeKey() }
                return
            }
            if self.state.editor != nil { self.finishEditing(save: true) }
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
            guard let self, event.keyCode == 53, self.isShowing,
                  self.panel?.isKeyWindow == true || self.quickLook?.isKeyWindow == true else { return event }
            let window = self.quickLook?.isKeyWindow == true ? self.quickLook : self.panel
            if let editor = window?.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            // Esc backs out one step at a time: the editor, a board's name, a pending board
            // delete, the preview, a multiple selection, the search; then the strip closes.
            if self.state.editor != nil {
                self.finishEditing(save: false)
                return nil
            }
            if self.state.renaming != nil {
                self.state.cancelRename()
                return nil
            }
            if self.state.pendingBoardDelete != nil || self.state.pendingDelete != nil {
                self.state.pendingBoardDelete = nil
                self.state.pendingDelete = nil
                return nil
            }
            if self.state.quickLookOpen {
                self.setQuickLook(open: false)
                return nil
            }
            if self.state.collapseSelection() { return nil }
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

    /// While editing, clicking another app closes everything (keeping the edit, as any
    /// click-away does; Esc is the way to throw it away). A click on the strip keeps it too.
    private func previewDidResignKey() {
        guard state.editor != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.state.editor != nil, self.quickLook?.isKeyWindow != true else { return }
            self.finishEditing(save: true)
            if self.panel?.isKeyWindow != true { self.dismiss() }
        }
    }

    private func didDismiss() {
        Diagnostics.record("panel closed")
        isShowing = false
        if state.editor != nil {
            finishEditing(save: true)
            // An emptied text can't be saved: drop that edit.
            if state.editor != nil { finishEditing(save: false) }
        }
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
        model.togglePin(state.selectedClips)
    }

    /// Copies the selected clip(s) as Return does with direct paste off (the paste sound plays;
    /// nothing is typed into another app).
    func testCopySelected() {
        copy(state.selectedClips)
    }

    func testDeleteSelected() {
        delete(state.selectedClips)
    }

    func testPin(toBoard index: Int) {
        let boards = model.boards.all
        guard boards.indices.contains(index) else { return }
        model.pin(Set(state.selectedClips.map(\.id)), to: boards[index].id)
    }

    func testNewBoard(named name: String?) {
        newBoard(with: [])
        if let name, var renaming = state.renaming {
            renaming.draft = name
            state.renaming = renaming
            state.commitRename()
        }
    }

    func testRequestBoardDelete(_ index: Int) {
        let boards = model.boards.all
        guard boards.indices.contains(index) else { return }
        requestBoardDelete(boards[index])
    }

    func testConfirmBoardDelete() {
        if let id = state.pendingBoardDelete { confirmBoardDelete(id) }
    }

    func testEdit(inTitle: Bool) {
        if let clip = state.selected { startEditing(clip, inTitle: inTitle) }
    }

    func testSetEditorText(_ text: String) {
        guard let view = state.editor?.textView else { return }
        view.selectAll(nil)
        view.insertText(text, replacementRange: view.selectedRange())
    }

    func testSetEditorTitle(_ title: String) {
        state.editor?.label = title
    }

    func testFinishEditing(save: Bool) {
        finishEditing(save: save)
    }

    func testPasteStack() {
        togglePasteStack(with: state.isMultipleSelection ? state.selectedClips : [])
    }

    func testDropOnTab(_ index: Int) {
        // Past the last tab: the + button.
        let tabs = state.tabs
        let tab = tabs.indices.contains(index) ? tabs[index] : Self.newBoardTab
        guard let frame = state.tabFrames[tab.id], let panel else { return }
        let point = NSPoint(x: panel.frame.minX + frame.midX, y: panel.frame.maxY - frame.midY)
        _ = dragMoved(to: point)
        _ = dragEnded(at: point, clips: state.selectedClips)
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
            QuickLookView(state: state, finishEditing: { [weak self] save in self?.finishEditing(save: save) })
        }
        // Scrolling the preview doesn't need key status, so the strip keeps the keyboard.
        preview.becomesKeyOnlyIfNeeded = true
        preview.dismissesOnResignKey = false
        preview.animationBehavior = .none
        preview.setAccessibilityLabel("Clip Preview")
        preview.keyHandler = { [weak self] event in
            guard let self, self.isShowing else { return false }
            if self.state.editor != nil {
                // The editor has the keyboard: ⌘S and ⌘Return save, the rest is typing.
                let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
                if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "s" || event.keyCode == 36 || event.keyCode == 76 {
                    self.finishEditing(save: true)
                    return true
                }
                return false
            }
            // If a click made the preview key, keys still drive the strip.
            self.panel?.makeKey()
            return self.handleKey(event)
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: preview, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.previewDidResignKey() }
        }
        return preview
    }

    // MARK: - Actions

    private func choose(_ clips: [Clip], plain: Bool) {
        let target = state.target
        dismiss()
        if clips.count > 1 {
            model.use(clips, .paste(target: target))
        } else if let clip = clips.first {
            model.use(clip, .paste(target: target), plainText: plain ? true : nil)
        }
    }

    private func copy(_ clips: [Clip]) {
        dismiss()
        if clips.count > 1 {
            model.use(clips, .copy)
        } else if let clip = clips.first {
            model.use(clip, .copy)
        }
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
    private func delete(_ clips: [Clip]) {
        guard !clips.isEmpty else { return }
        let ids = Set(clips.map(\.id))
        if clips.contains(where: \.isPinned), state.pendingDelete != ids {
            state.pendingDelete = ids
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                if self?.state.pendingDelete == ids { self?.state.pendingDelete = nil }
            }
            return
        }
        state.pendingDelete = nil
        let index = state.results.firstIndex { ids.contains($0.id) } ?? 0
        model.delete(ids)
        state.refresh()
        if !state.results.isEmpty {
            state.select(index: min(index, state.results.count - 1))
        } else {
            setQuickLook(open: false)
        }
    }

    // MARK: - Boards

    /// A new board at the end of the tabs (with `clips` on it), its name ready to type.
    private func newBoard(with clips: [Clip]) {
        let board = model.createBoard(with: Set(clips.map(\.id)))
        state.beginRenaming(board, isNew: clips.isEmpty)
        Diagnostics.record("board created clips=\(clips.count)")
    }

    /// Deletes an empty board at once; one with clips asks first, in the top bar.
    private func requestBoardDelete(_ board: Board) {
        if model.clipCount(onBoard: board.id) == 0 {
            confirmBoardDelete(board.id)
        } else {
            state.pendingBoardDelete = board.id
        }
    }

    func confirmBoardDelete(_ id: UUID) {
        state.pendingBoardDelete = nil
        if state.filter == .board(id) { state.filter = .all }
        model.deleteBoard(id)
        state.refresh()
    }

    /// The board tab (or +) under a point on screen, for a dragged card.
    private func dropTarget(at point: NSPoint) -> ClipFilter? {
        guard let panel, isShowing, panel.frame.contains(point) else { return nil }
        let local = CGPoint(x: point.x - panel.frame.minX, y: panel.frame.maxY - point.y)
        for tab in state.tabs + [Self.newBoardTab] where tab.boardID != nil || tab == Self.newBoardTab {
            if let frame = state.tabFrames[tab.id], frame.insetBy(dx: -2, dy: -4).contains(local) { return tab }
        }
        return nil
    }

    /// Stands for the + button among the drop targets.
    static let newBoardTab = ClipFilter.board(UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!)

    private func dragMoved(to point: NSPoint) -> Bool {
        let target = dropTarget(at: point)
        if state.dropTarget != target { state.dropTarget = target }
        return target != nil
    }

    /// A card dropped on a board tab goes on that board; dropped on +, on a new board.
    private func dragEnded(at point: NSPoint, clips: [Clip]) -> Bool {
        let target = dropTarget(at: point)
        state.dropTarget = nil
        guard let target, !clips.isEmpty else { return false }
        if target == Self.newBoardTab {
            newBoard(with: clips)
        } else if let board = target.boardID {
            model.pin(Set(clips.map(\.id)), to: board)
        }
        return true
    }

    // MARK: - Paste stack

    /// ⇧⌘C: stops a running stack; otherwise starts one with the selected cards (pasting the
    /// first into the app you were in), or an empty one that collects what you copy next.
    private func togglePasteStack(with clips: [Clip]) {
        if model.stack.isActive {
            model.stack.cancel()
            return
        }
        let target = state.target
        dismiss()
        if clips.count > 1 {
            model.stack.start(with: ClipJoin.chronological(clips).map(\.id), pasteFirst: target)
        } else {
            model.stack.start()
        }
    }

    // MARK: - Editing

    /// Whether the preview was open before editing started (it stays open after, if so).
    private var previewWasOpen = false

    /// ⌘E (text) or ⌘R (title): the preview turns into an editor for the clip.
    private func startEditing(_ clip: Clip, inTitle: Bool) {
        guard isShowing, state.editor == nil else { return }
        state.collapseSelection()
        let session = ClipEditSession(clip: clip, startsInTitle: inTitle)
        previewWasOpen = state.quickLookOpen
        state.editor = session
        setQuickLook(open: true)
        quickLook?.makeKey()
        Task { await session.load(model: model, clip: clip) }
        Diagnostics.record("editing started title=\(inTitle)")
    }

    /// Ends editing: saves (unless the text was emptied) or throws the changes away.
    func finishEditing(save: Bool) {
        guard let session = state.editor else { return }
        if save, !session.save(model: model) {
            HUD.show("A clip can't be empty. Change the text or press Esc.", systemImage: "exclamationmark.triangle")
            return
        }
        state.editor = nil
        state.refresh()
        if let id = state.results.first(where: { $0.id == session.clipID })?.id { state.selectedID = id }
        if !previewWasOpen { setQuickLook(open: false) }
        if isShowing { panel?.makeKey() }
        Diagnostics.record("editing ended saved=\(save)")
    }

    // MARK: - Keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        // A board's name field takes every key (Return commits, Esc cancels).
        if state.renaming != nil { return false }
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
            choose(state.selectedClips, plain: plain)
        case .quickPaste(let index, let plain):
            if state.results.indices.contains(index) { choose([state.results[index]], plain: plain) }
        case .move(let delta):
            state.moveSelection(by: delta)
        case .extend(let delta):
            state.extendSelection(by: delta)
        case .extendToFirst:
            state.extendSelection(toEnd: false)
        case .extendToLast:
            state.extendSelection(toEnd: true)
        case .selectAll:
            state.selectAll()
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
            copy(state.selectedClips)
        case .togglePin:
            model.togglePin(state.selectedClips)
        case .pinToBoard(let index):
            let boards = model.boards.all
            guard boards.indices.contains(index) else { return true }
            let board = boards[index]
            let clips = state.selectedClips
            // Already all on it: take them off, like ⌘P.
            model.pin(Set(clips.map(\.id)), to: clips.allSatisfy { $0.boardID == board.id } ? nil : board.id)
        case .newBoard:
            newBoard(with: state.isMultipleSelection ? state.selectedClips : [])
        case .edit:
            if let clip = state.selected { startEditing(clip, inTitle: !ClipEdit.canEditText(clip)) }
        case .rename:
            if let clip = state.selected { startEditing(clip, inTitle: true) }
        case .pasteStack:
            togglePasteStack(with: state.isMultipleSelection ? state.selectedClips : [])
        case .open:
            if let clip = state.selected { open(clip) }
        case .delete:
            delete(state.selectedClips)
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
