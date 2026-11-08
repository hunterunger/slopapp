import AppKit
import SlopKit
import SwiftUI
import ZonesCore

/// Owns the model, the status item and the panel, and keeps the clock ticking.
@MainActor
final class AppController: NSObject, NSPopoverDelegate {
    static let shared = AppController()

    let info = AppInfo.current(fallbackName: "Zones")
    let model: ZonesModel
    let panel = PanelState()
    let pasteboard: Pasteboard = SystemPasteboard()
    /// Where places and settings live: `.standard`, or the `ZONES_DEFAULTS_SUITE` test suite.
    let defaults: UserDefaults

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    /// Stands in for the status item when it's hidden (Settings or the notch).
    private var anchorWindow: NSWindow?
    private var eventMonitor: Any?
    private var tickTask: Task<Void, Never>?
    private var lastClosed = Date.distantPast
    private var scrollAccumulator: CGFloat = 0
    private var started = false
    private var closingOnPurpose = false
    private var openingWindow = false
    private var windowKeyMonitor: Any?
    private var appliedIconVisibility = true

    override init() {
        let environment = ProcessInfo.processInfo.environment
        // ZONES_DEFAULTS_SUITE=<name> keeps test runs out of the real settings.
        let defaults = environment["ZONES_DEFAULTS_SUITE"].flatMap(UserDefaults.init(suiteName:)) ?? .standard
        if environment["ZONES_RESET"] == "1" {
            defaults.removeObject(forKey: "places")
            defaults.removeObject(forKey: "preferences")
        }
        self.defaults = defaults
        model = ZonesModel(storage: UserDefaultsStorage(defaults: defaults), clock: LiveClock(environment: environment))
        super.init()
    }

    func start() {
        guard !started else { return }
        started = true
        // ZONES_APPEARANCE=light|dark forces an appearance (screenshots and tests).
        switch ProcessInfo.processInfo.environment["ZONES_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        setUpStatusItem()
        setUpPopover()
        observeSystem()
        startTicking()
        installWindowKeyMonitor()
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            self?.togglePanel()
        }
        Task { @MainActor [weak self] in
            guard let self, await Snapshots.runIfAsked(controller: self) else { return }
            NSApp.terminate(nil)
        }
    }

    // MARK: Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "ZonesStatusItem"
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.imagePosition = .imageLeading
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        statusItem = item
        if let window = item.button?.window {
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window,
                                                   queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshStatusItemVisibility() }
            }
        }
        appliedIconVisibility = MenuBarIcon.isVisible
        item.isVisible = appliedIconVisibility
        updateStatusItem()
        // Setting `isVisible` itself writes to UserDefaults (the autosave), so only react to
        // a real change of the setting, and apply it outside the notification.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, MenuBarIcon.isVisible != self.appliedIconVisibility else { return }
                self.appliedIconVisibility = MenuBarIcon.isVisible
                DispatchQueue.main.async { self.statusItem?.isVisible = self.appliedIconVisibility }
            }
        }
    }

    /// Redraws the status item whenever what it shows changes.
    private func updateStatusItem() {
        let title = withObservationTracking {
            (model.menuBarTitle, model.preferences.menuBarDisplay, model.menuBarWidestTitles)
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateStatusItem() }
        }
        guard let item = statusItem, let button = item.button else { return }
        let (text, display, widest) = title
        if display == .timeOnly, text != nil {
            button.image = nil
        } else {
            let image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
            image?.isTemplate = true
            button.image = image
        }
        let shown: (String) -> String = { display == .timeOnly ? $0 : " " + $0 }
        if text != nil, !widest.isEmpty {
            // One width for every time it can show (two-digit hours, either day period), so
            // the item and everything left of it in the menu bar never shift as it ticks.
            let width = widest.map { variant -> CGFloat in
                button.title = shown(variant)
                return button.fittingSize.width
            }.max() ?? NSStatusItem.variableLength
            item.length = ceil(width)
        } else {
            item.length = NSStatusItem.variableLength
        }
        button.title = text.map(shown) ?? ""
        button.setAccessibilityLabel(text.map { "Zones, \($0)" } ?? "Zones")
        button.toolTip = "Zones"
        // macOS lays the item out a moment later; check where it ended up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.refreshStatusItemVisibility() }
    }

    @objc private func statusItemClicked() {
        // A click on the icon while the panel is open first closes it (transient popover),
        // then arrives here: don't reopen it straight away.
        if Date().timeIntervalSince(lastClosed) < 0.3 { return }
        togglePanel()
    }

    // MARK: Settings and About windows

    /// Esc closes Settings and About, like other utility windows (⌘W works already).
    /// Text fields and the shortcut recorder keep Esc for themselves.
    private func installWindowKeyMonitor() {
        windowKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            nonisolated(unsafe) let event = event
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard event.keyCode == KeyCode.escape,
                      event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                      let window = event.window, window.level == .normal, window.styleMask.contains(.titled),
                      window.identifier != PlannerWindow.identifier,
                      !(window.firstResponder is NSText) else { return false }
                window.performClose(nil)
                return true
            }
            return handled ? nil : event
        }
    }

    // MARK: Menu bar item visibility

    /// Whether macOS is showing our menu bar item. On a full menu bar (notched MacBooks)
    /// it silently hides items that don't fit; Settings explains that.
    func refreshStatusItemVisibility() {
        guard let item = statusItem, item.isVisible, let window = item.button?.window else {
            panel.statusItemHiddenBySystem = false
            return
        }
        let onScreen = NSScreen.screens.contains { screen in
            let menuBar = NSRect(x: screen.frame.minX, y: screen.frame.maxY - 40, width: screen.frame.width, height: 40)
            return menuBar.intersects(window.frame) && screen.frame.contains(NSPoint(x: window.frame.midX, y: window.frame.midY))
        }
        panel.statusItemHiddenBySystem = !onScreen || !window.occlusionState.contains(.visible)
            || Self.isUnderNotch(window.frame)
    }

    /// True when any of the item is in the camera housing's dead zone.
    private static func isUnderNotch(_ frame: NSRect) -> Bool {
        for screen in NSScreen.screens {
            guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { continue }
            let notch = NSRect(x: left.maxX, y: screen.frame.maxY - 40, width: right.minX - left.maxX, height: 40)
            if notch.width > 0, notch.intersects(frame) { return true }
        }
        return false
    }

    // MARK: Panel

    private func setUpPopover() {
        let root = PanelView(model: model, panel: panel, controller: self)
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.delegate = self
    }

    var isPanelShown: Bool { popover.isShown }

    func togglePanel() {
        if popover.isShown { closePanel() } else { showPanel() }
    }

    func showPanel(search: Bool = false) {
        model.refresh()
        if search { panel.beginSearch() }
        guard !popover.isShown else { return }
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.appearance = NSApp.appearance
        AppActivation.activate()
        if let button = statusItem?.button, let window = button.window, statusItem?.isVisible == true,
           window.occlusionState.contains(.visible), NSScreen.screens.contains(where: { $0.frame.intersects(window.frame) }) {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        } else {
            let anchor = makeAnchorWindow()
            popover.show(relativeTo: anchor.contentView?.bounds ?? .zero, of: anchor.contentView!, preferredEdge: .minY)
        }
        installEventMonitor()
        focusPanel()
    }

    /// Makes the panel the key window so typing and arrows reach it. Activation of a menu bar
    /// app can land a moment after the panel appears (especially right after we handed focus
    /// back on close), so retry briefly.
    private func focusPanel(attempts: Int = 12) {
        guard popover.isShown, let window = popover.contentViewController?.view.window else { return }
        if !NSApp.isActive { AppActivation.activate() }
        window.makeKey()
        if !window.isKeyWindow, attempts > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                self?.focusPanel(attempts: attempts - 1)
            }
        }
    }

    func closePanel() {
        guard popover.isShown else { return }
        // Close at once: a fading panel still counts as shown, so a quick reopen would
        // toggle it closed instead.
        popover.animates = false
        closingOnPurpose = true
        popover.performClose(nil)
        closingOnPurpose = false
    }

    /// Only a click outside the panel, the app losing focus, or our own close (Esc, ⌘W,
    /// the icon) closes it. Focus moving between Zones' own windows (the "Copied" HUD, a
    /// menu) doesn't.
    nonisolated func popoverShouldClose(_ popover: NSPopover) -> Bool {
        MainActor.assumeIsolated {
            if closingOnPurpose || !NSApp.isActive { return true }
            switch NSApp.currentEvent?.type {
            case .leftMouseDown, .rightMouseDown, .otherMouseDown: return true
            default: return false
            }
        }
    }

    nonisolated func popoverWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            // Closed by a click outside (possibly on our own icon): remember when, so that
            // same click doesn't reopen it. Keyboard closes don't count.
            let type = NSApp.currentEvent?.type
            if type == .leftMouseDown || type == .rightMouseDown { lastClosed = Date() }
        }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            removeEventMonitor()
            anchorWindow?.orderOut(nil)
            model.panelDidClose()
            panel.reset()
            panel.releaseSearchSoon()
            // Hand focus back to the app the user was in, unless one of ours is open or
            // about to open (Settings, About).
            let ourWindowVisible = NSApp.windows.contains { $0.isVisible && $0.level == .normal && $0.canBecomeKey }
            if !ourWindowVisible && !openingWindow { NSApp.deactivate() }
            openingWindow = false
        }
    }

    /// A tiny invisible window under the menu bar of the screen with the mouse, used to
    /// position the panel when the status item can't be seen.
    private func makeAnchorWindow() -> NSWindow {
        let window = anchorWindow ?? {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            // Normal level on purpose: SlopAppDelegate treats "activated with no normal
            // window" as a relaunch and brings a hidden icon back.
            window.level = .normal
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .transient]
            anchorWindow = window
            return window
        }()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        window.setFrameOrigin(NSPoint(x: visible.maxX - 200, y: visible.maxY - 1))
        window.orderFrontRegardless()
        return window
    }

    // MARK: Actions

    func copyTimes() {
        pasteboard.write(model.timesText)
        HUD.show("Copied", systemImage: "doc.on.doc")
    }

    func copyTime(forRow id: UUID) {
        guard let text = model.timeText(forRow: id) else { return }
        pasteboard.write(text)
        HUD.show("Copied", systemImage: "doc.on.doc")
    }

    func openSettings() {
        openingWindow = popover.isShown
        closePanel()
        SettingsWindow.open()
    }

    func beginEditingTime(_ id: UUID) {
        model.selection = id
        panel.beginEditingTime(id)
    }

    /// Settings → Places, with the place's hours open (local time: the default hours).
    func editWorkingHours(_ id: UUID) {
        panel.settingsTab = .places
        panel.hoursEditingID = id == ClockRow.localID ? nil : id
        openSettings()
    }

    func openPlanner() {
        openingWindow = popover.isShown
        let instant = model.isScrubbed ? model.instant : nil
        closePanel()
        PlannerWindow.show(model: model, controller: self, at: instant)
    }

    /// The share menu (Messages, Mail, Notes…) with the shown time in every place.
    func showSharePicker() {
        guard let host = popover.contentViewController?.view, !model.isEmpty else { return }
        let frame = panel.shareButtonFrame
        let rect = NSRect(x: frame.minX, y: host.isFlipped ? frame.minY : host.bounds.height - frame.maxY,
                          width: frame.width, height: frame.height)
        let picker = NSSharingServicePicker(items: [model.timesText as NSString])
        picker.show(relativeTo: rect, of: host, preferredEdge: .minY)
    }

    /// Hands an hour-long event at `instant` to the calendar app as an .ics file, with the
    /// time in every place in its notes. No calendar access needed: the calendar app asks
    /// where to add it. `ZONES_EXPORT_DIR` writes the file there without opening it (tests).
    func addToCalendar(at instant: Date? = nil) {
        let start = instant ?? model.instant
        let text = CalendarFile.ics(start: start, duration: 3600, title: "Meeting", notes: model.timesText(at: start))
        let environment = ProcessInfo.processInfo.environment
        let directory = environment["ZONES_EXPORT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Zones", isDirectory: true)
        let url = directory.appendingPathComponent("Meeting.ics")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            HUD.show("Couldn't create the event file", systemImage: "exclamationmark.triangle")
            return
        }
        if environment["ZONES_EXPORT_DIR"] != nil {
            HUD.show("Saved Meeting.ics", systemImage: "calendar.badge.plus")
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func showAbout() {
        openingWindow = popover.isShown
        closePanel()
        CreditedAboutWindow.show(info: info)
    }

    func reportProblem() {
        closePanel()
        IssueReport.open(.problem, info: info)
    }

    /// Adds a search result, or, when that place is already listed, shows the existing row.
    func addPlace(_ result: SearchResult) {
        if let existing = model.existingID(for: result.place) {
            model.highlight(existing)
        } else {
            model.add(result.place)
        }
        panel.cancel()
    }

    /// Applies the time typed on a row; on a bad entry keeps the field open with a hint.
    func commitEdit() {
        switch panel.mode {
        case .editingTime(let id):
            if model.setTime(panel.editText, forRow: id) == .applied {
                panel.cancel()
            } else {
                panel.editError = "Type a time like 3pm, 9:30 am or 15:30."
            }
        case .renaming(let id):
            model.rename(id, to: panel.editText)
            panel.cancel()
        default:
            break
        }
    }

    // MARK: More menu

    /// Every panel action with its shortcut, so they're all discoverable. An AppKit menu,
    /// because SwiftUI hides ⌘C, ⌘Z and ⌘Q in a popover's menu (they clash with the app's
    /// own Edit and app menus).
    func showMoreMenu() {
        guard let host = popover.contentViewController?.view else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        func item(_ title: String, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = [.command],
                  enabled: Bool = true, action: @escaping @MainActor () -> Void) {
            let item = ClosureMenuItem(title: title, keyEquivalent: key, action: action)
            item.keyEquivalentModifierMask = modifiers
            item.isEnabled = enabled
            menu.addItem(item)
        }
        let arrowRight = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        let arrowLeft = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        let hasRows = !model.isEmpty
        item("Add Place…", "n") { [weak self] in self?.panel.beginSearch() }
        item("Copy Times", "c", enabled: hasRows) { [weak self] in self?.copyTimes() }
        item("Type a Time…", "\r", [], enabled: hasRows) { [weak self] in self?.beginEditingSelectedTime() }
        menu.addItem(.separator())
        item("15 Minutes Later", arrowRight, []) { [weak self] in self?.model.step(.quarterHour, by: 1) }
        item("15 Minutes Earlier", arrowLeft, []) { [weak self] in self?.model.step(.quarterHour, by: -1) }
        item("1 Hour Later", arrowRight, [.shift]) { [weak self] in self?.model.step(.hour, by: 1) }
        item("1 Hour Earlier", arrowLeft, [.shift]) { [weak self] in self?.model.step(.hour, by: -1) }
        item("Next Day", arrowRight, [.option]) { [weak self] in self?.model.step(.day, by: 1) }
        item("Previous Day", arrowLeft, [.option]) { [weak self] in self?.model.step(.day, by: -1) }
        item("Back to Now", "\u{1b}", [], enabled: model.isScrubbed) { [weak self] in self?.model.resetToNow() }
        item("Go to Date…", "d") { [weak self] in self?.panel.showsCalendar = true }
        menu.addItem(.separator())
        item("Open Planner", "0") { [weak self] in self?.openPlanner() }
        item("Add to Calendar…", enabled: hasRows) { [weak self] in self?.addToCalendar() }
        menu.addItem(.separator())
        let selected = model.selection.flatMap { id in model.places.first { $0.id == id } }
        item(selected.map { "Remove \($0.label)" } ?? "Remove", "\u{8}", [], enabled: selected != nil) { [weak self] in
            if let id = selected?.id { self?.model.remove(id) }
        }
        item("Move Up", String(UnicodeScalar(NSUpArrowFunctionKey)!), [.command, .option],
             enabled: selected.map { model.canMove($0.id, by: -1) } ?? false) { [weak self] in
            if let id = selected?.id { self?.model.move(id, by: -1) }
        }
        item("Move Down", String(UnicodeScalar(NSDownArrowFunctionKey)!), [.command, .option],
             enabled: selected.map { model.canMove($0.id, by: 1) } ?? false) { [weak self] in
            if let id = selected?.id { self?.model.move(id, by: 1) }
        }
        item("Sort by Time Difference", enabled: model.places.count > 1) { [weak self] in self?.model.sortByTimeDifference() }
        item("Sort by Name", enabled: model.places.count > 1) { [weak self] in self?.model.sortByName() }
        item(model.pendingUndo?.menuTitle ?? "Undo", "z", enabled: model.canUndo) { [weak self] in
            self?.model.undo()
        }
        menu.addItem(.separator())
        let styles = NSMenu(title: "Row Style")
        for style in RowStyle.allCases {
            let entry = ClosureMenuItem(title: style.title, keyEquivalent: "") { [weak self] in
                self?.model.preferences.rowStyle = style
            }
            entry.state = model.preferences.rowStyle == style ? .on : .off
            styles.addItem(entry)
        }
        let stylesItem = NSMenuItem(title: "Row Style", action: nil, keyEquivalent: "")
        stylesItem.submenu = styles
        menu.addItem(stylesItem)
        item("Settings…", ",") { [weak self] in self?.openSettings() }
        item("About Zones") { [weak self] in self?.showAbout() }
        item(IssueReport.Kind.problem.title) { [weak self] in self?.reportProblem() }
        menu.addItem(.separator())
        item("Quit Zones", "q") { NSApp.terminate(nil) }

        let frame = panel.moreButtonFrame
        let point = NSPoint(x: frame.minX, y: host.isFlipped ? frame.maxY + 4 : host.bounds.height - frame.maxY - 4)
        menu.popUp(positioning: nil, at: point, in: host)
    }

    // MARK: Keyboard and scroll

    private func installEventMonitor() {
        removeEventMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel, .leftMouseDown]) { [weak self] event in
            nonisolated(unsafe) let event = event
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.popover.isShown,
                      event.window === self.popover.contentViewController?.view.window else { return false }
                switch event.type {
                case .scrollWheel: return self.handleScroll(event)
                case .leftMouseDown: return self.handleMouseDown(event)
                default: return self.handleKey(event)
                }
            }
            return handled ? nil : event
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    private var isEditingText: Bool {
        popover.contentViewController?.view.window?.firstResponder is NSText
    }

    /// Returns true when the key was handled.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let editing = isEditingText

        if event.keyCode == KeyCode.escape {
            if panel.mode != .list {
                panel.cancel()
            } else if panel.showsCalendar {
                panel.showsCalendar = false
            } else if !model.escape() {
                closePanel()
            }
            return true
        }

        if flags == .command {
            switch key {
            case "w": closePanel(); return true
            case "q": NSApp.terminate(nil); return true
            case ",": openSettings(); return true
            case "n": panel.beginSearch(); return true
            case "d": panel.showsCalendar.toggle(); return true
            case "0": openPlanner(); return true
            case "c" where !editing: copyTimes(); return true
            case "z" where !editing:
                if model.canUndo { model.undo() }
                return true
            default: break
            }
        }

        switch panel.mode {
        case .search:
            switch event.keyCode {
            case KeyCode.down: panel.moveResultSelection(by: 1); return true
            case KeyCode.up: panel.moveResultSelection(by: -1); return true
            case KeyCode.returnKey, KeyCode.enter:
                if let result = panel.selectedResult { addPlace(result) }
                return true
            default: return false
            }
        case .editingTime, .renaming:
            return false
        case .list:
            break
        }
        if editing { return false }

        let unitFlags = flags.subtracting(.function)
        switch event.keyCode {
        case KeyCode.left, KeyCode.right:
            let direction = event.keyCode == KeyCode.right ? 1 : -1
            switch unitFlags {
            case []: model.step(.quarterHour, by: direction)
            case .shift: model.step(.hour, by: direction)
            case .option: model.step(.day, by: direction)
            default: return false
            }
            return true
        case KeyCode.up, KeyCode.down:
            let delta = event.keyCode == KeyCode.down ? 1 : -1
            if unitFlags == [.command, .option] {
                if let id = model.selection { model.move(id, by: delta) }
            } else {
                model.moveSelection(by: delta)
            }
            return true
        case KeyCode.returnKey, KeyCode.enter:
            beginEditingSelectedTime()
            return true
        case KeyCode.delete, KeyCode.forwardDelete:
            if let id = model.selection, id != ClockRow.localID { model.remove(id) }
            return true
        default:
            break
        }
        // Typing a digit on the list starts typing a time on the selected (or first) row.
        if flags.isEmpty || flags == .shift, let first = event.characters?.first, first.isNumber {
            beginEditingSelectedTime(initialText: String(first))
            return true
        }
        return false
    }

    func beginEditingSelectedTime(initialText: String = "") {
        guard let id = model.selection ?? model.rows.first?.id else { return }
        model.selection = id
        panel.beginEditingTime(id, initialText: initialText)
    }

    /// Sideways two-finger swipes (or Shift + wheel) move the time; vertical scrolling is
    /// left to the list.
    private func handleScroll(_ event: NSEvent) -> Bool {
        guard panel.mode == .list else { return false }
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return false }
        if !event.momentumPhase.isEmpty { return true }
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 14 : 1
        scrollAccumulator += event.scrollingDeltaX
        while abs(scrollAccumulator) >= threshold {
            let direction = scrollAccumulator > 0 ? 1 : -1
            model.step(.quarterHour, by: direction)
            scrollAccumulator -= CGFloat(direction) * threshold
        }
        if event.phase == .ended || event.phase == .cancelled { scrollAccumulator = 0 }
        return true
    }

    // MARK: Mouse on rows

    /// Rows track the mouse themselves: drag sideways to move the time, drag up or down to
    /// reorder, click to select, click the time to type one. Done in AppKit because SwiftUI
    /// gestures on rows that also have context menus don't reliably see drags in a popover.
    private func handleMouseDown(_ event: NSEvent) -> Bool {
        guard panel.mode == .list, event.clickCount == 1, let window = event.window,
              let host = popover.contentViewController?.view else { return false }
        let start = host.convert(event.locationInWindow, from: nil)
        if panel.datePillFrame.contains(start) { return false }
        guard let (id, _) = panel.rowFrames.first(where: { $0.value.contains(start) }) else { return false }

        var axis: Axis?
        let startInstant = model.instant
        var reorderBaseline: CGFloat = 0
        var lastHour = TimeMath.wallTime(of: startInstant, in: model.localTimeZone).hour
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            let point = host.convert(next.locationInWindow, from: nil)
            let dx = point.x - start.x
            let dy = point.y - start.y
            if axis == nil, max(abs(dx), abs(dy)) >= 4 {
                axis = abs(dx) >= abs(dy) ? .horizontal : .vertical
            }
            switch axis {
            case .horizontal:
                model.drag(from: startInstant, points: Double(dx))
                // The line follows the pointer over strips that stay put; at the edge of
                // the list the strips scroll instead.
                let limit = TimeInterval(PanelMetrics.stripHalfWidth) * Scrubbing.secondsPerPoint
                var anchor = panel.stripAnchor ?? startInstant
                let ahead = model.instant.timeIntervalSince(anchor)
                if ahead > limit { anchor = model.instant.addingTimeInterval(-limit) }
                if ahead < -limit { anchor = model.instant.addingTimeInterval(limit) }
                if panel.stripAnchor != anchor { panel.stripAnchor = anchor }
                let hour = TimeMath.wallTime(of: model.instant, in: model.localTimeZone).hour
                if hour != lastHour {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    lastHour = hour
                }
            case .vertical:
                guard id != ClockRow.localID else { break }
                let height = panel.rowFrames[id]?.height ?? 46
                let travel = dy - reorderBaseline
                if travel > height / 2, model.canMove(id, by: 1) {
                    model.move(id, by: 1)
                    reorderBaseline += height
                } else if travel < -height / 2, model.canMove(id, by: -1) {
                    model.move(id, by: -1)
                    reorderBaseline -= height
                }
            case nil:
                break
            }
        }
        panel.stripAnchor = nil
        if axis == nil {
            if panel.timeFrames[id]?.insetBy(dx: -6, dy: -6).contains(start) == true {
                beginEditingTime(id)
            } else {
                model.selection = id
            }
        }
        return true
    }

    // MARK: Clock

    /// Wakes on each minute boundary to refresh the times (no per-second work).
    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                let now = Date()
                let next = (now.timeIntervalSince1970 / 60).rounded(.down) * 60 + 60
                let wait = max(0.05, next - now.timeIntervalSince1970 + 0.05)
                try? await Task.sleep(for: .seconds(wait), tolerance: .milliseconds(500))
                guard !Task.isCancelled else { return }
                self?.model.refresh()
            }
        }
    }

    private func observeSystem() {
        let center = NotificationCenter.default
        for name in [Notification.Name.NSSystemTimeZoneDidChange, .NSSystemClockDidChange, .NSCalendarDayChanged] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.model.refresh()
                    self?.startTicking()
                }
            }
        }
        center.addObserver(forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.localeChanged() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.refresh()
                self?.startTicking()
            }
        }
    }
}

enum KeyCode {
    static let returnKey: UInt16 = 36
    static let enter: UInt16 = 76
    static let delete: UInt16 = 51
    static let forwardDelete: UInt16 = 117
    static let escape: UInt16 = 53
    static let left: UInt16 = 123
    static let right: UInt16 = 124
    static let down: UInt16 = 125
    static let up: UInt16 = 126
}

/// The clipboard, behind a protocol so it can be faked.
@MainActor
protocol Pasteboard {
    func write(_ text: String)
}

@MainActor
struct SystemPasteboard: Pasteboard {
    func write(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// An NSMenuItem that runs a closure.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, keyEquivalent: String, action: @escaping @MainActor () -> Void) {
        handler = action
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() {
        handler()
    }
}
