import AppKit
import ClipsCore
import Observation
import SlopKit

/// The paste stack, wired to the clipboard. While it's on, every recorded copy joins it, and
/// the clip that's next sits on the clipboard as a promise: Clips hands its data over only
/// when an app asks for it, which is what pasting does. That ask is how the stack knows a
/// paste happened, by ⌘V, Edit › Paste or a right click, with no permission and no key
/// watching. Then the next clip goes on the clipboard, until the last one is pasted.
///
/// The promised item is marked transient (nspasteboard.org), so other clipboard managers
/// leave it alone instead of reading it, which would look like a paste.
@MainActor
@Observable
final class PasteStackController {
    /// The stack, or nil when there isn't one.
    private(set) var stack: PasteStack? {
        didSet {
            // After SwiftUI has redrawn the list for it.
            DispatchQueue.main.async { [weak self] in self?.pill?.relayout() }
        }
    }

    var isActive: Bool { stack != nil }

    @ObservationIgnored private unowned let model: AppModel
    @ObservationIgnored private var tracker = PasteReadTracker()
    /// Waits a moment after a paste's first read (it may ask for more types) before moving on.
    @ObservationIgnored private var advanceTask: Task<Void, Never>?
    @ObservationIgnored private var armTask: Task<Void, Never>?
    @ObservationIgnored private var pill: PasteStackPill?
    /// A paste reads the promised data once per type it wants, within a few milliseconds.
    static let settle: Duration = .milliseconds(300)

    init(model: AppModel) {
        self.model = model
    }

    // MARK: - Starting and stopping

    /// Starts a stack with `ids` lined up (in paste order), or empty to collect copies.
    /// `pasteFirst`: paste the first clip into that app right away (Paste One by One).
    func start(with ids: [UUID] = [], pasteFirst target: NSRunningApplication? = nil) {
        advanceTask?.cancel()
        stack = PasteStack(items: ids)
        showPill()
        Diagnostics.record("stack started count=\(ids.count)")
        guard !ids.isEmpty else {
            tracker.disarm()
            return
        }
        arm { [weak self] in
            guard let self, let target, self.model.willPasteDirectly(into: target) else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(60))
                Paster.sendPaste()
            }
        }
    }

    /// Stops the stack. What's on the clipboard stays there (as plain, settled data).
    func cancel() {
        guard stack != nil else { return }
        end(finished: false)
    }

    private func end(finished: Bool) {
        advanceTask?.cancel()
        armTask?.cancel()
        tracker.disarm()
        stack = nil
        pill?.close()
        pill = nil
        Diagnostics.record("stack ended finished=\(finished)")
        if finished { HUD.show("Paste stack done", systemImage: "checkmark.circle") }
    }

    // MARK: - Events from the model

    /// A copy was recorded: it joins the end, and the next clip goes back on the clipboard
    /// (the copy replaced it).
    func copyRecorded(_ id: UUID) {
        guard var stack else { return }
        stack.add(id)
        self.stack = stack
        Diagnostics.record("stack added count=\(stack.items.count)")
        arm()
    }

    /// Clips put something else on the clipboard (you pasted another clip from the strip).
    /// The stack carries on: its next clip goes back a moment later.
    func clipboardReplaced() {
        guard stack != nil else { return }
        tracker.disarm()
        armTask?.cancel()
        armTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.arm()
        }
    }

    func removed(_ ids: Set<UUID>) {
        guard var stack, !ids.isEmpty, !Set(stack.items).isDisjoint(with: ids) else { return }
        let wasNext = stack.next
        stack.remove(ids)
        self.stack = stack
        if stack.next != wasNext { arm() }
    }

    /// Makes the clip at `index` the next one (a click in the stack's list).
    func move(to index: Int) {
        guard var stack else { return }
        stack.move(to: index)
        self.stack = stack
        arm()
    }

    // MARK: - The clipboard

    /// Puts the next clip on the clipboard as a promise.
    private func arm(then done: (() -> Void)? = nil) {
        armTask?.cancel()
        guard let id = stack?.next else {
            tracker.disarm()
            return
        }
        let plain = model.alwaysPlainText
        armTask = Task { [weak self] in
            // A copy that just joined may still be on its way into the history file.
            var loaded: ClipPayload?
            for _ in 0..<10 {
                guard let self, !Task.isCancelled else { return }
                loaded = await self.model.payload(for: id)
                if loaded != nil { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard let self, var payload = loaded, !Task.isCancelled, self.stack?.next == id else { return }
            if plain, let text = payload.plainText() { payload = text }
            let serial = self.tracker.arm()
            let count = self.model.pasteboard.writePromised(payload) { [weak self] in
                self?.dataRequested(serial: serial)
            }
            self.model.watcher.noteOwnWrite(changeCount: count)
            Diagnostics.record("stack armed position=\(self.stack?.pastedCount ?? 0)")
            done?()
        }
    }

    /// An app asked for the promised data.
    private func dataRequested(serial: Int) {
        guard tracker.read(serial: serial) else { return }
        Diagnostics.record("stack paste detected")
        model.clipDelivered()
        advanceTask?.cancel()
        advanceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.settle)
            guard !Task.isCancelled else { return }
            self?.advance()
        }
    }

    private func advance() {
        guard var stack else { return }
        stack.advance()
        self.stack = stack
        if stack.isFinished {
            end(finished: true)
        } else {
            arm()
        }
    }

    // MARK: - The floating list

    private func showPill() {
        if pill == nil { pill = PasteStackPill(controller: self, model: model) }
        pill?.show()
    }

    /// The clips in the stack (the ones still in the history).
    func clips() -> [(index: Int, clip: Clip)] {
        guard let stack else { return [] }
        return stack.items.enumerated().compactMap { index, id in model.history.clip(id: id).map { (index, $0) } }
    }
}

/// Provides a promised pasteboard item's data when an app asks for it.
final class PromisedPasteboardData: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    private let data: [String: Data]
    private let onRead: @MainActor () -> Void

    init(reps: [Representation], onRead: @escaping @MainActor () -> Void) {
        var data: [String: Data] = [:]
        for rep in reps where data[rep.type] == nil { data[rep.type] = rep.data }
        self.data = data
        self.onRead = onRead
    }

    var types: [NSPasteboard.PasteboardType] { data.keys.map { NSPasteboard.PasteboardType($0) } }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard let value = data[type.rawValue] else { return }
        item.setData(value, forType: type)
        let onRead = onRead
        if Thread.isMainThread {
            MainActor.assumeIsolated { onRead() }
        } else {
            DispatchQueue.main.async { onRead() }
        }
    }
}
