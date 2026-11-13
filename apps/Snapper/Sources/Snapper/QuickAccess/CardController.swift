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
    /// The screen each card shows on (the pointer's screen when it appeared, or the capture's).
    private var screens: [UUID: CGDirectDisplayID] = [:]
    private var builtWidth: [UUID: CGFloat] = [:]
    /// The QR codes each card shows (read after it appears).
    private var shownCodes: [UUID: [ScannedCode]] = [:]
    private var timer: Timer?
    static let gap: CGFloat = Spacing.m
    /// The card's corners. The round corner buttons sit `controlInset` in, and their radius
    /// (`controlSide / 2`) equals `cornerRadius − controlInset`, so they're concentric with
    /// the card's corners.
    static let cornerRadius: CGFloat = Radius.xl
    static let controlInset: CGFloat = Spacing.xs
    static let controlSide: CGFloat = 2 * Radius.nested(in: cornerRadius, padding: controlInset)
    var width: CGFloat { CGFloat(model.cardWidth) }

    init(model: AppModel) {
        self.model = model
    }

    var items: [CaptureItem] { queue.ids.compactMap { cards[$0]?.item } }
    var isEmpty: Bool { cards.isEmpty }
    var newest: CaptureItem? { items.last }

    func contains(_ item: CaptureItem) -> Bool { cards[item.id] != nil }

    /// The capture whose card is `window`.
    func item(for window: NSWindow?) -> CaptureItem? {
        guard let window else { return nil }
        return cards.values.first { $0.panel === window }?.item
    }

    /// Window numbers of the card panels (tests read them; captures leave them out).
    var windowNumbers: [Int] { cards.values.map { $0.panel.windowNumber } }

    func add(_ item: CaptureItem) {
        let evicted = queue.add(item.id, now: Date(), autoClose: model.autoClose)
        for id in evicted {
            if let card = cards[id] { close(card.item) }
        }
        let panel = FloatingPanel(cornerRadius: Self.cornerRadius) { self.content(for: item) }
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
        builtWidth[item.id] = width
        if model.cardFollowsPointer, let screen = NSScreen.underPointer {
            screens[item.id] = screen.displayID
        } else if let displayID = item.displayID {
            screens[item.id] = displayID
        }
        model.openCards = cards.count
        relayout(appearing: item.id)
        scheduleTimer()
        scanCodes(item)
    }

    private func content(for item: CaptureItem) -> CardView {
        CardView(item: item, thumbnailSize: Self.thumbnailSize(for: item.size, width: width),
                 codes: shownCodes[item.id] ?? [], model: model, controller: self, revision: item.revision)
    }

    /// Redraws a card whose capture changed (a trimmed video's new poster and length).
    func refresh(_ item: CaptureItem) {
        guard let card = cards[item.id] else { return }
        card.panel.setContent { content(for: item) }
        relayout()
    }

    // MARK: QR codes

    /// Reads the QR codes in a card's capture once it's on screen (so the card never waits
    /// for it), then grows the card to show them underneath.
    private func scanCodes(_ item: CaptureItem) {
        guard model.showsCodes, !item.isMedia, cards[item.id] != nil, item.codesScanned !== item.image else { return }
        let image = item.image
        item.codesScanned = image
        let reader = model.codeReader
        let started = Diagnostics.now()
        Task { [weak self, weak item] in
            let codes = (try? await reader.codes(in: image)) ?? []
            guard let self, let item, item.image === image else { return }
            Diagnostics.record("codes scanned found=\(codes.count) ms=\(Diagnostics.milliseconds(since: started))")
            item.codes = codes
            self.show(codes, on: item)
        }
    }

    private func show(_ codes: [ScannedCode], on item: CaptureItem) {
        guard let card = cards[item.id] else { return }
        let codes = model.showsCodes ? codes : []
        guard codes != (shownCodes[item.id] ?? []) else { return }
        shownCodes[item.id] = codes
        card.panel.setContent { content(for: item) }
        relayout()
    }

    /// Settings → Quick Access → "Show QR code contents" changed.
    func showsCodesChanged() {
        for item in items {
            if model.showsCodes {
                if item.codesScanned === item.image { show(item.codes, on: item) } else { scanCodes(item) }
            } else {
                show([], on: item)
            }
        }
    }

    /// Closes a card. `remember` keeps it for "Reopen Last Capture".
    func close(_ item: CaptureItem, remember: Bool = true) {
        guard let card = cards.removeValue(forKey: item.id) else { return }
        screens[item.id] = nil
        builtWidth[item.id] = nil
        shownCodes[item.id] = nil
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

    /// Room for the corner buttons above and below and a row of pills between them.
    static let minimumHeight: CGFloat = 2 * (controlInset + controlSide + Spacing.xs) + 28

    static func thumbnailSize(for size: CGSize, width: CGFloat) -> CGSize {
        CardLayout.thumbnailSize(for: size, width: width, minHeight: minimumHeight)
    }

    /// Shows the share menu for a card.
    func share(_ item: CaptureItem) {
        guard let card = cards[item.id], let view = card.panel.contentView,
              let url = item.temporaryFile(format: model.format) else { return }
        Output.share(url, from: view, edge: model.cardCorner == .left ? .maxX : .minX)
    }

    /// Stacks the cards on each screen: the oldest stays in the corner and newer ones stack
    /// above it, so a card never jumps while you're reaching for it.
    func relayout(appearing: UUID? = nil) {
        let corner = model.cardCorner
        var nextY: [CGDirectDisplayID: CGFloat] = [:]
        for id in queue.ids {
            guard let card = cards[id] else { continue }
            if builtWidth[id] != width {
                // Size changes (Settings) apply to every card.
                card.panel.setContent { content(for: card.item) }
                builtWidth[id] = width
            }
            let screen = NSScreen.screens.first { $0.displayID == (screens[id] ?? card.item.displayID) } ?? NSScreen.underPointer ?? NSScreen.main
            guard let screen else { continue }
            let visible = screen.visibleFrame.insetBy(dx: Spacing.l, dy: Spacing.l)
            let size = card.panel.contentView?.fittingSize ?? CGSize(width: width, height: 160)
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
