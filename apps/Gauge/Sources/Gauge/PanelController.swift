import AppKit
import GaugeCore
import SlopKit
import SwiftUI

/// Shows and hides the panel under the status item, and keeps the sampler in step: sampling
/// runs at 1 s with processes only while the panel is open.
@MainActor
final class PanelController {
    private let model: PanelModel
    private let statusItem: StatusItemController
    private let sampler: Sampler
    private weak var controller: AppController?
    private var panel: FloatingPanel?
    private var lastClosed = Date.distantPast
    private var lastOpened = Date.distantPast

    static let width = Metrics.menuBarWindowWidth
    /// Space between the menu bar and the panel, like the system's own menu bar panels.
    static let menuBarGap: CGFloat = Spacing.xs

    init(model: PanelModel, statusItem: StatusItemController, sampler: Sampler, controller: AppController) {
        self.model = model
        self.statusItem = statusItem
        self.sampler = sampler
        self.controller = controller
    }

    var isShown: Bool { panel?.isVisible == true }

    /// The button was pressed: a click on macOS 14–26, an Accessibility press anywhere.
    /// On macOS 27 a click also begins an expanded session, which owns open and close then.
    func buttonPressed() {
        if statusItem.hasSession { return }
        let now = Date()
        if isShown {
            // Just opened by the session or the shortcut: this is the same click.
            if now.timeIntervalSince(lastOpened) < 0.3 { return }
            close()
            return
        }
        // A click on the item while the panel is open first closes it (it loses key), then
        // arrives here: don't reopen it straight away.
        if now.timeIntervalSince(lastClosed) < 0.3 { return }
        show()
    }

    /// macOS 27 began the item's session: show the panel, or keep it if it's already open
    /// (the button's action got there first, or the shortcut opened it).
    func sessionBegan() {
        if !isShown { show() }
    }

    /// macOS 27 ended the session (a click elsewhere, the item clicked again).
    func sessionEnded() {
        guard isShown else { return }
        panel?.dismiss()
    }

    func toggleFromShortcut() {
        if isShown { close() } else { show() }
    }

    func show() {
        guard let controller else { return }
        let panel = self.panel ?? makePanel(controller: controller)
        model.apply(sampler.currentPanelUpdate())
        sampler.setPanelOpen(true)
        place(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
        lastOpened = Date()
    }

    func close() {
        guard isShown else { return }
        panel?.dismiss()
    }

    private func makePanel(controller: AppController) -> FloatingPanel {
        let panel = FloatingPanel {
            PanelView(model: model, store: controller.store, actions: PanelActions(controller: controller))
        }
        panel.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
        panel.onDismiss = { [weak self] in self?.didDismiss() }
        panel.setAccessibilityLabel("Gauge")
        // Over the menu bar's level, like a menu, so it's never under another app's window.
        panel.level = .popUpMenu
        self.panel = panel
        return panel
    }

    private func didDismiss() {
        lastClosed = Date()
        sampler.setPanelOpen(false)
        model.panelClosed()
        if statusItem.hasSession { statusItem.endSession() }
    }

    /// Under the item, centred on it, kept on its screen. When the item can't be seen (a full
    /// menu bar, or hidden in Settings), at the top right of the screen with the pointer.
    private func place(_ panel: FloatingPanel) {
        let size = panel.contentView?.fittingSize ?? NSSize(width: Self.width, height: 560)
        let anchor = statusItem.anchorFrame
        let mouse = NSEvent.mouseLocation
        let screen = anchor.flatMap { frame in NSScreen.screens.first { $0.frame.intersects(frame) } }
            ?? NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin = Spacing.s
        var x = anchor.map { $0.midX - size.width / 2 } ?? (visible.maxX - size.width - margin)
        x = min(max(x, visible.minX + margin), visible.maxX - size.width - margin)
        let top = min(anchor?.minY ?? visible.maxY, visible.maxY) - Self.menuBarGap
        let y = max(visible.minY + margin, top - size.height)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        if ProcessInfo.processInfo.environment["GAUGE_LOG_RENDERS"] != nil {
            FileHandle.standardError.write(Data("panel frame \(panel.frame) anchor \(String(describing: anchor)) screen \(visible)\n".utf8))
        }
    }

    // MARK: Keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags == .command {
            switch key {
            case "q": NSApp.terminate(nil); return true
            case ",": controller?.openSettings(); return true
            case "w": close(); return true
            case "c": copySelection(); return true
            default: return false
            }
        }
        guard flags.isEmpty || flags == .shift else { return false }
        if let digit = event.digit {
            model.selectSection(number: digit)
            return true
        }
        switch event.keyCode {
        case 125: model.moveSelection(by: 1); return true            // down
        case 126: model.moveSelection(by: -1); return true           // up
        case 123: model.moveSection(by: -1); return true             // left
        case 124: model.moveSection(by: 1); return true              // right
        case 48: model.moveSection(by: flags == .shift ? -1 : 1); return true // tab
        case 36, 76: controller?.openActivityMonitor(); return true   // return, enter
        default: return false
        }
    }

    private func copySelection() {
        guard let row = model.selectedRow, model.rows.indices.contains(row), let sort = model.selection.processSort else { return }
        controller?.copy(AppGrouping.copyText(model.rows[row], sort: sort))
    }
}

/// What the panel's buttons do.
@MainActor
struct PanelActions {
    let controller: AppController

    func openActivityMonitor() { controller.openActivityMonitor() }
    func openSettings() { controller.openSettings() }
    func showAbout() { controller.showAbout() }
    func reportProblem() { controller.reportProblem() }
    func quit() { NSApp.terminate(nil) }
    func copy(_ group: ProcessGroup, sort: ProcessSort) { controller.copy(AppGrouping.copyText(group, sort: sort)) }
}
