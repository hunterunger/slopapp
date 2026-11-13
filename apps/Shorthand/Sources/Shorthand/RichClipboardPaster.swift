import AppKit
import SlopKit

/// SlopKit candidate (next to `ClipboardPaster`): pastes several types at once (RTFD, RTF,
/// HTML, plain text, an image) by borrowing the clipboard, the same way `ClipboardPaster`
/// pastes text: saves everything on it, writes ours (marked transient so clipboard managers
/// skip it), sends ⌘V, and puts the old clipboard back once the app has read it, unless
/// someone copied something else meanwhile. The target app takes the richest type it
/// understands, so formatting falls back to plain text by itself.
@MainActor
struct RichClipboardPaster {
    var pasteboard: NSPasteboard
    var writeDelay: Duration = .milliseconds(30)
    /// A little longer than for text: some apps read big rich data lazily.
    var restoreDelay: Duration = .milliseconds(500)
    var sendPaste: @MainActor () -> Void

    @discardableResult
    func paste(_ types: [(NSPasteboard.PasteboardType, Data)], restore: Bool, onPasted: (@MainActor () -> Void)? = nil,
               completion: (@MainActor (ClipboardPaster.Outcome) -> Void)? = nil) -> Task<ClipboardPaster.Outcome, Never> {
        let saved = restore ? ClipboardSnapshot.capture(pasteboard) : ClipboardSnapshot(items: [])
        let ours = Self.write(types, to: pasteboard, transient: !saved.isEmpty)
        let pasteboard = self.pasteboard
        let sendPaste = self.sendPaste
        let writeDelay = self.writeDelay
        let restoreDelay = self.restoreDelay
        let token = UUID()
        if !saved.isEmpty { Self.pending[token] = (pasteboard, saved, ours) }
        return Task { @MainActor in
            try? await Task.sleep(for: writeDelay)
            sendPaste()
            onPasted?()
            guard !saved.isEmpty else {
                completion?(.leftCopied)
                return .leftCopied
            }
            try? await Task.sleep(for: restoreDelay)
            guard Self.pending.removeValue(forKey: token) != nil else {
                completion?(.restored)
                return .restored
            }
            guard pasteboard.changeCount == ours else {
                completion?(.keptNewerCopy)
                return .keptNewerCopy
            }
            saved.restore(to: pasteboard)
            completion?(.restored)
            return .restored
        }
    }

    /// One item with every type. Returns the change count.
    @discardableResult
    static func write(_ types: [(NSPasteboard.PasteboardType, Data)], to pasteboard: NSPasteboard, transient: Bool) -> Int {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        for (type, data) in types { item.setData(data, forType: type) }
        if transient { for type in ClipboardSnapshot.transientTypes { item.setString("", forType: type) } }
        pasteboard.writeObjects([item])
        return pasteboard.changeCount
    }

    private static var pending: [UUID: (NSPasteboard, ClipboardSnapshot, Int)] = [:]

    /// Puts back every clipboard still waiting (call when quitting).
    static func restorePendingNow() {
        for (token, entry) in pending {
            if entry.0.changeCount == entry.2 { entry.1.restore(to: entry.0) }
            pending.removeValue(forKey: token)
        }
    }
}
