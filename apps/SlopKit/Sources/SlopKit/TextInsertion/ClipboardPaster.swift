import AppKit

/// Pastes text by borrowing the clipboard: saves everything on it, writes the text (marked
/// transient so clipboard managers skip it), sends ⌘V, then puts the old clipboard back once
/// the app has read it, unless someone copied something else in the meantime.
@MainActor
public struct ClipboardPaster {
    public var pasteboard: NSPasteboard
    /// Sends the paste shortcut (normally `SyntheticKeyboard.paste()`).
    public var sendPaste: @MainActor () -> Void
    /// Between the write and ⌘V, so the write lands first.
    public var writeDelay: Duration
    /// Between ⌘V and the restore, so the app has read the text.
    public var restoreDelay: Duration

    public init(pasteboard: NSPasteboard, writeDelay: Duration = .milliseconds(60), restoreDelay: Duration = .milliseconds(450),
                sendPaste: @escaping @MainActor () -> Void) {
        self.pasteboard = pasteboard
        self.writeDelay = writeDelay
        self.restoreDelay = restoreDelay
        self.sendPaste = sendPaste
    }

    /// What happened to the clipboard.
    public enum Outcome: Equatable, Sendable {
        /// The old clipboard is back.
        case restored
        /// Nothing to put back (it was empty, or restoring was off): the text stays copied.
        case leftCopied
        /// Someone copied something after our write: theirs is kept.
        case keptNewerCopy
    }

    /// Pastes `text`. With `restore: false` (the app may not read the clipboard without macOS
    /// asking) nothing is read, and the text is left on the clipboard as a normal copy.
    /// Returns once ⌘V is sent; the restore happens later (`completion` reports it).
    @discardableResult
    public func paste(_ text: String, restore: Bool = true, onPasted: (@MainActor () -> Void)? = nil,
                      completion: (@MainActor (Outcome) -> Void)? = nil) -> Task<Outcome, Never> {
        let saved = restore ? ClipboardSnapshot.capture(pasteboard) : ClipboardSnapshot(items: [])
        let ours = ClipboardSnapshot.write(text, to: pasteboard, transient: !saved.isEmpty)
        let pasteboard = self.pasteboard
        let sendPaste = self.sendPaste
        let writeDelay = self.writeDelay
        let restoreDelay = self.restoreDelay
        // Registered before anything waits, so quitting at any point after our write (even
        // before ⌘V goes out) still puts the user's clipboard back.
        let token = UUID()
        if !saved.isEmpty { Self.pending[token] = (pasteboard, saved, ours) }
        return Task { @MainActor in
            try? await Task.sleep(for: writeDelay)
            sendPaste()
            onPasted?()
            guard !saved.isEmpty else {   // nothing to restore: the text stays copied
                completion?(.leftCopied)
                return .leftCopied
            }
            try? await Task.sleep(for: restoreDelay)
            guard Self.pending.removeValue(forKey: token) != nil else {
                completion?(.restored)   // already put back by `restorePendingNow()`
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

    /// Restores still waiting for their delay.
    private static var pending: [UUID: (NSPasteboard, ClipboardSnapshot, Int)] = [:]

    /// Puts back every clipboard still waiting to be restored (on `pasteboard`, or all), right
    /// now: call from `applicationWillTerminate`, so quitting never leaves borrowed text behind.
    public static func restorePendingNow(on pasteboard: NSPasteboard? = nil) {
        for (token, entry) in pending where pasteboard == nil || entry.0 === pasteboard {
            if entry.0.changeCount == entry.2 { entry.1.restore(to: entry.0) }
            pending.removeValue(forKey: token)
        }
    }
}
