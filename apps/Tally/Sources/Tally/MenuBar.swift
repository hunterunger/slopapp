import AppKit
import SlopKit
import SwiftUI
import TallyCore

/// The optional menu bar icon. Clicking it drops down the current sheet in a panel (the
/// same sheet as the window, live); right-clicking shows a short menu. With the Dock icon
/// hidden, Tally lives only here.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    static let shared = MenuBarController()

    private var item: NSStatusItem?
    private var popover: NSPopover?
    var model: SheetModel { .shared }

    static let panelSize = NSSize(width: 380, height: 340)

    /// Applies the menu bar and Dock settings.
    func update() {
        if Pref.isMenuBarIconShown { install() } else { remove() }
        let policy: NSApplication.ActivationPolicy = Pref.isDockIconShown ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
            if policy == .regular { NSApp.activate(ignoringOtherApps: true) }
        }
    }

    var isShown: Bool { item != nil }

    private func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "plus.forwardslash.minus", accessibilityDescription: "Tally")
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Tally"
        }
        self.item = item
    }

    private func remove() {
        popover?.close()
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            togglePanel()
        }
    }

    func togglePanel() {
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = item?.button else {
            WindowToggler.show()
            return
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = Self.panelSize
        popover.contentViewController = NSHostingController(rootView: QuickPanel(model: model, close: { [weak popover] in
            popover?.performClose(nil)
        }))
        self.popover = popover
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func popoverDidClose(_ notification: Notification) {
        model.saveNow()
        // Release the panel's editor so only the window's stays live.
        popover?.contentViewController = nil
        popover = nil
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Tally", action: #selector(openWindow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "New Sheet", action: #selector(newSheet), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit Tally", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item?.menu = menu
        item?.button?.performClick(nil)
        item?.menu = nil
    }

    @objc private func openWindow() { WindowToggler.show() }

    @objc private func newSheet() {
        model.newSheet()
        togglePanel()
    }

    @objc private func openSettings() {
        if let action = model.openSettingsAction {
            action()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}

/// The panel under the menu bar icon: the current sheet and its total.
struct QuickPanel: View {
    let model: SheetModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.currentTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(Color(nsColor: model.theme.text))
                Spacer()
                Menu {
                    ForEach(model.rows) { row in
                        Button(row.title) { model.select(row.id) }
                    }
                    Divider()
                    Button("New Sheet") { model.newSheet() }
                } label: {
                    Image(systemName: "list.bullet")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color(nsColor: model.theme.opaqueComment))
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Sheets")
                .accessibilityLabel("Sheets")
            }
            // Title and the sheets menu line up with the sheet's text and results edges (the
            // menu draws its symbol `menuInset` in from its frame).
            .padding(.leading, SheetTextView.margin)
            .padding(.trailing, SheetTextView.margin - BottomBar.menuInset)
            .padding(.top, Spacing.s)
            .padding(.bottom, 2)
            SheetDetail(model: model, compact: true, openWindow: {
                close()
                WindowToggler.show()
            })
        }
        .frame(width: MenuBarController.panelSize.width, height: MenuBarController.panelSize.height)
        .background(model.theme.swiftUIBackground)
        .preferredColorScheme(model.theme.colorScheme)
    }
}
