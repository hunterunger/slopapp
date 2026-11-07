import AppKit
import AwakeCore
import SlopKit
import SwiftUI

/// The menu bar icon.
///
/// - Left click: turns Awake on (default duration) or off. Settings can swap this so a left
///   click opens the menu instead.
/// - Right-click, Control-click or Option-click: the other one (normally the menu).
/// - An Accessibility press (VoiceOver, scripts) opens the menu, where every action lives.
///
/// The cup fills while Awake is on. Optional: dim while off, time left beside the cup.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private unowned let app: AppController
    private var item: NSStatusItem?
    private var appliedIconVisibility = true

    init(app: AppController) {
        self.app = app
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "AwakeStatusItem"
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.imagePosition = .imageLeading
        // The menu bar's own font, with fixed-width digits so "1h 09m" → "1h 08m" doesn't wobble.
        item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        self.item = item
        appliedIconVisibility = MenuBarIcon.isVisible
        item.isVisible = appliedIconVisibility
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, MenuBarIcon.isVisible != self.appliedIconVisibility else { return }
                self.appliedIconVisibility = MenuBarIcon.isVisible
                DispatchQueue.main.async { self.item?.isVisible = self.appliedIconVisibility }
            }
        }
        updateButton()
    }

    /// Redraws the icon whenever what it shows changes.
    private func updateButton() {
        let controller = app.controller
        let preferences = app.preferences
        let state = withObservationTracking {
            StatusIcon.State(
                isActive: controller.isActive,
                dimmed: preferences.dimIconWhenOff && !controller.isActive,
                time: preferences.showTimeInMenuBar ? controller.menuBarText : nil,
                status: controller.statusText,
                leftClick: preferences.leftClick
            )
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateButton() }
        }
        guard let button = item?.button else { return }
        button.image = StatusIcon.image(active: state.isActive)
        button.appearsDisabled = state.dimmed
        button.title = state.time.map { " \($0)" } ?? ""
        button.imagePosition = state.time == nil ? .imageOnly : .imageLeading
        button.setAccessibilityLabel(app.info.name)
        button.setAccessibilityValue(state.isActive ? "On" : "Off")
        button.setAccessibilityHelp("Opens the \(app.info.name) menu.")
        button.toolTip = StatusIcon.toolTip(state, appName: app.info.name)
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent, event.type == .leftMouseUp || event.type == .rightMouseUp else {
            showMenu()
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        perform(whatClickDoes(right: event.type == .rightMouseUp, option: flags.contains(.option),
                              control: flags.contains(.control)))
    }

    /// Left click does the chosen action; right-click, Control- or Option-click the other.
    func whatClickDoes(right: Bool, option: Bool = false, control: Bool = false) -> ClickAction {
        let leftClick = app.preferences.leftClick
        guard right || option || control else { return leftClick }
        return leftClick == .toggle ? .openMenu : .toggle
    }

    private func perform(_ action: ClickAction) {
        switch action {
        case .toggle: app.controller.toggle()
        case .openMenu: showMenu()
        }
    }

    // MARK: Self-test hooks

    var button: NSStatusBarButton? { item?.button }

    /// What a click does, minus the menu's modal tracking (self-test only).
    func simulateClick(right: Bool) {
        let action = whatClickDoes(right: right)
        if action == .toggle { perform(action) }
    }

    func showMenu() {
        guard let item, let button = item.button else { return }
        let menu = makeMenu()
        item.menu = menu
        button.performClick(nil)
    }

    /// The menu as it stands now (its status line keeps itself current while open).
    private func makeMenu() -> NSMenu {
        let menu = StatusMenuBuilder(app: app).build(MenuContent.entries(for: app.controller, appName: app.info.name))
        menu.delegate = self
        return menu
    }

    /// Pops the status item's menu up under the right end of the menu bar, without the
    /// status item (`AWAKE_SHOW=menu`, for screenshots when the icon is hidden).
    func popUpMenuForReview() {
        guard let screen = NSScreen.main else { return }
        let menu = makeMenu()
        // A menu popped up by a background app closes at once; come forward first.
        AppActivation.activate()
        menu.popUp(positioning: nil, at: NSPoint(x: screen.frame.maxX - 360, y: screen.visibleFrame.maxY - 4), in: nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        // Detach so the next left click reaches `clicked` again.
        DispatchQueue.main.async { [weak self] in self?.item?.menu = nil }
    }
}

/// Turns `MenuEntry` rows into an `NSMenu`.
@MainActor
struct StatusMenuBuilder {
    let app: AppController
    /// Whether the menu being built shows checkmarks: AppKit indents every title to make room
    /// for them, and the status line has to follow.
    private var hasStateColumn = false

    func build(_ entries: [MenuEntry]) -> NSMenu {
        var builder = self
        builder.hasStateColumn = entries.contains { if case .item(_, _, true, _, _) = $0 { true } else { false } }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in entries { menu.addItem(builder.item(for: entry)) }
        return menu
    }

    private func item(for entry: MenuEntry) -> NSMenuItem {
        switch entry {
        case .separator:
            return .separator()
        case .status:
            // A custom view, not a disabled item: AppKit draws disabled titles at about 2.7:1,
            // and this line is the one people open the menu to read. The view watches the
            // controller, so "25 min left" counts down while the menu stays open.
            let controller = app.controller
            return MenuStatusLine.item(hasStateColumn: hasStateColumn) { controller.statusText ?? "Off" }
        case .error(let text):
            return MenuStatusLine.item(hasStateColumn: hasStateColumn) { text }
        case .text(let text):
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        case .header(let title):
            return .sectionHeader(title: title)
        case .submenu(let title, let children):
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = build(children)
            return item
        case .item(let title, let command, let checked, let key, let showsShortcut):
            let item = CommandMenuItem(title: title, command: command, app: app)
            if let key { item.keyEquivalent = key }
            item.state = checked ? .on : .off
            if showsShortcut { item.setShortcut(for: .toggleAwake) }
            if case .whileRunning(let ref) = command { item.image = AppIcons.icon(for: ref.bundleID) }
            return item
        }
    }
}

/// A menu item that runs a `MenuCommand`.
@MainActor
final class CommandMenuItem: NSMenuItem {
    let command: MenuCommand
    private unowned let app: AppController

    init(title: String, command: MenuCommand, app: AppController) {
        self.command = command
        self.app = app
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() {
        app.perform(command)
    }
}

/// App icons for menus and the Triggers list.
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String, size: CGFloat = 16) -> NSImage? {
        let key = "\(bundleID)@\(size)"
        if let cached = cache[key] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: size, height: size)
        cache[key] = icon
        return icon
    }
}

/// The menu bar glyph: an empty cup while off, a full one while on. Template images, so
/// macOS tints them for the menu bar.
@MainActor
enum StatusIcon {
    struct State: Equatable {
        var isActive: Bool
        var dimmed: Bool
        var time: String?
        var status: String?
        var leftClick: ClickAction
    }

    static func image(active: Bool) -> NSImage? {
        let image = NSImage(systemSymbolName: active ? "cup.and.saucer.fill" : "cup.and.saucer",
                            accessibilityDescription: active ? "Awake: on" : "Awake: off")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
        image?.isTemplate = true
        return image
    }

    static func toolTip(_ state: State, appName: String) -> String {
        let first = state.isActive ? (state.status ?? "\(appName) is on") : "\(appName) is off"
        let hint = state.leftClick == .toggle
            ? "Click to turn \(state.isActive ? "off" : "on"). Right-click for options."
            : "Click for options. Right-click to turn \(state.isActive ? "off" : "on")."
        return "\(first)\n\(hint)"
    }
}

/// The status line at the top of the menu ("25 min left"), drawn like a menu title in the
/// secondary label colour, with digits that keep their width as it counts down.
struct MenuStatusLine: View {
    /// NSMenu's text row on macOS 26 and later (measured on screenshots).
    static let rowHeight: CGFloat = 24
    /// Where AppKit starts item titles, from the menu's edge, with and without a checkmark
    /// column (measured on screenshots).
    static let titleInset = (withState: CGFloat(30), withoutState: CGFloat(16))

    let leading: CGFloat
    let text: @MainActor () -> String

    var body: some View {
        Text(text())
            .font(Font(NSFont.menuFont(ofSize: 0)))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.leading, leading)
            .padding(.trailing, Spacing.l)
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
    }

    static func item(hasStateColumn: Bool, text: @escaping @MainActor () -> String) -> NSMenuItem {
        let line = MenuStatusLine(leading: hasStateColumn ? titleInset.withState : titleInset.withoutState, text: text)
        let host = NSHostingView(rootView: line)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.autoresizingMask = [.width]
        // The title isn't drawn (the view is), but type-select and scripts read it.
        let item = NSMenuItem(title: text(), action: nil, keyEquivalent: "")
        item.view = host
        item.isEnabled = false
        return item
    }
}
