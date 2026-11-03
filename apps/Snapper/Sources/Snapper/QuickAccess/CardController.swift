import AppKit
import SlopKit
import SnapperCore
import SwiftUI

/// The capture cards in the bottom corner: one small floating panel per capture, stacked
/// upward from the corner of the screen the capture came from, newest nearest the corner.
/// Cards never take keyboard focus by themselves (they can linger); click one to use its
/// shortcuts.
@MainActor
final class CardController {
    private unowned let model: AppModel
    private var queue = CardQueue<UUID>()
    private var cards: [UUID: (item: CaptureItem, panel: FloatingPanel)] = [:]
    private var timer: Timer?
    static let width: CGFloat = 220
    static let gap: CGFloat = 10

    init(model: AppModel) {
        self.model = model
    }

    var items: [CaptureItem] { queue.ids.compactMap { cards[$0]?.item } }
    var isEmpty: Bool { cards.isEmpty }
    var newest: CaptureItem? { items.last }

    func contains(_ item: CaptureItem) -> Bool { cards[item.id] != nil }

    /// Window numbers of the card panels (tests read them; captures leave them out).
    var windowNumbers: [Int] { cards.values.map { $0.panel.windowNumber } }

    func add(_ item: CaptureItem) {
        let evicted = queue.add(item.id, now: Date(), autoClose: model.autoClose)
        for id in evicted {
            if let card = cards[id] { close(card.item) }
        }
        let size = Self.thumbnailSize(for: item.size)
        let panel = FloatingPanel(cornerRadius: 14) {
            CardView(item: item, thumbnailSize: size, model: self.model, controller: self)
        }
        panel.dismissesOnResignKey = false
        panel.level = .statusBar
        panel.setAccessibilityLabel("Capture")
        panel.title = "Capture"
        panel.onDismiss = { [weak self, weak item] in
            guard let self, let item else { return }
            self.close(item)
        }
        panel.keyHandler = { [weak self, weak item] event in
            guard let self, let item else { return false }
            return self.handleKey(event, item: item)
        }
        cards[item.id] = (item, panel)
        model.openCards = cards.count
        relayout(appearing: item.id)
        scheduleTimer()
    }

    /// Closes a card. `remember` keeps it for "Reopen Last Capture".
    func close(_ item: CaptureItem, remember: Bool = true) {
        guard let card = cards.removeValue(forKey: item.id) else { return }
        queue.remove(item.id)
        model.openCards = cards.count
        card.panel.onDismiss = nil
        card.panel.orderOut(nil)
        card.panel.close()
        if remember { model.remember(item) }
        relayout()
        scheduleTimer()
    }

    func closeAll() {
        for item in items { close(item) }
    }

    func setHovering(_ item: CaptureItem, _ hovering: Bool) {
        queue.setHovering(item.id, hovering, now: Date(), autoClose: model.autoClose)
        scheduleTimer()
    }

    func autoCloseChanged() {
        queue.reschedule(now: Date(), autoClose: model.autoClose)
        scheduleTimer()
    }

    // MARK: Layout

    static func thumbnailSize(for size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: width, height: 140) }
        let height = min(max(width * size.height / size.width, 90), 240)
        return CGSize(width: width, height: height.rounded())
    }

    /// Stacks the cards on each screen, newest at the corner.
    func relayout(appearing: UUID? = nil) {
        let corner = model.cardCorner
        var nextY: [CGDirectDisplayID: CGFloat] = [:]
        for id in queue.ids.reversed() {
            guard let card = cards[id] else { continue }
            let screen = NSScreen.screens.first { $0.displayID == card.item.displayID } ?? NSScreen.underPointer ?? NSScreen.main
            guard let screen else { continue }
            let visible = screen.visibleFrame.insetBy(dx: 16, dy: 16)
            let size = card.panel.contentView?.fittingSize ?? CGSize(width: Self.width, height: 160)
            let y = nextY[screen.displayID] ?? visible.minY
            let x = corner == .left ? visible.minX : visible.maxX - size.width
            let frame = CGRect(x: x, y: y, width: size.width, height: size.height)
            nextY[screen.displayID] = y + size.height + Self.gap
            if id == appearing {
                card.panel.setFrame(frame, display: true)
                card.panel.alphaValue = 0
                card.panel.orderFrontRegardless()
                card.panel.invalidateShadow()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.12
                    card.panel.animator().alphaValue = 1
                }
            } else if card.panel.frame != frame {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.15
                    card.panel.animator().setFrame(frame, display: true)
                }
            }
        }
    }

    // MARK: Auto-close

    private func scheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard let deadline = queue.nextDeadline else { return }
        let timer = Timer(fire: max(deadline, Date().addingTimeInterval(0.05)), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeDueCards() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func closeDueCards() {
        for id in queue.due(at: Date()) {
            guard let item = cards[id]?.item else { continue }
            if model.autoCloseAction == .saveAndClose, item.savedURL == nil {
                model.save(item)
            } else {
                close(item)
            }
            queue.remove(id)
        }
        scheduleTimer()
    }

    // MARK: Keys (once a card has been clicked)

    private func handleKey(_ event: NSEvent, item: CaptureItem) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased()
        switch (flags, key) {
        case ([.command], "c"): model.copy(item)
        case ([.command], "s"): model.save(item)
        case ([.command, .shift], "s"): model.saveAs(item)
        case ([.command], "e"): model.annotate(item)
        case ([.command, .shift], "p"): model.pin(item)
        case ([.command], "w"): close(item)
        default:
            if flags.isEmpty, event.keyCode == 51 || event.keyCode == 117 { close(item); return true } // Delete
            return false
        }
        return true
    }
}
