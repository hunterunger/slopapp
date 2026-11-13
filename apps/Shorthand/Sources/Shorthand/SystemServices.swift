import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ShorthandCore
import SlopKit

/// What the expander asks the system right before inserting. In test mode
/// (`SHORTHAND_INSERT_ONLY_INTO`) the test target is the front app, whatever is really in front.
@MainActor
final class SystemEnvironment: InsertionEnvironment {
    let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    var frontApp: FrontApp? {
        let app: NSRunningApplication?
        if let only = Diagnostics.insertOnlyInto {
            app = NSRunningApplication.runningApplications(withBundleIdentifier: only).first
        } else {
            app = NSWorkspace.shared.frontmostApplication
        }
        return app.map { FrontApp(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier, name: $0.localizedName) }
    }

    var secureInputActive: Bool { Diagnostics.assumeSecureInput ?? IsSecureEventInputEnabled() }

    /// How long the last password-field check took (ms), for the latency log.
    private(set) var lastFieldCheckMilliseconds = 0.0

    var focusedFieldIsSecure: Bool {
        let start = MonotonicClock.now()
        defer { lastFieldCheckMilliseconds = Double(MonotonicClock.now() - start) / 1_000_000 }
        let element: AXUIElement
        if let front = frontApp, Diagnostics.insertOnlyInto != nil {
            element = AXUIElementCreateApplication(front.pid)
        } else {
            element = AXUIElementCreateSystemWide()
        }
        // Never wait long on a busy app: the insert has a 30 ms budget.
        AXUIElementSetMessagingTimeout(element, 0.02)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSubroleAttribute as CFString, &subrole)
        return (subrole as? String) == (kAXSecureTextFieldSubrole as String)
    }

    /// The first Accessibility message to an app sets up a connection (tens of ms). Do that in
    /// the background when it comes to the front, so the check at insert time is quick.
    func prewarmAccessibility() {
        guard let pid = frontApp?.pid, KeyboardPermissions.canPost else { return }
        DispatchQueue.global(qos: .utility).async {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.5)
            var focused: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused)
        }
    }

    var pasteboardPrivacy: PasteboardAccessState {
        switch Diagnostics.pastePrivacy {
        case "allowed": return .allowed
        case "asks": return .asks
        case "denied": return .denied
        default: break
        }
        switch PasteboardPrivacy.current(for: pasteboard) {
        case .allowed: return .allowed
        case .asks: return .asks
        case .denied: return .denied
        }
    }

    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    func readClipboard() -> ClipboardValue {
        guard pasteboardPrivacy == .allowed else { return .notAllowed }
        if pasteboard.types?.contains(Self.concealedType) == true { return .concealed }
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return .none }
        return .text(text)
    }

    func now() -> UInt64 { MonotonicClock.now() }
    var date: Date { Date() }
}

/// Posts Shorthand's keys with SlopKit's `SyntheticKeyboard` (marked, so the tap skips them)
/// and pastes with `ClipboardPaster`. In test mode every key goes to the test target's
/// process only.
@MainActor
final class SystemPoster: KeyPosting {
    let pasteboard: NSPasteboard
    private let environment: SystemEnvironment
    /// Called when a borrowed clipboard was put back (or not), for the log.
    var onPasteFinished: ((ClipboardPaster.Outcome) -> Void)?
    /// A formatted snippet's text, by id (nil for plain ones).
    var formattedText: (UUID) -> NSAttributedString? = { _ in nil }

    init(pasteboard: NSPasteboard, environment: SystemEnvironment) {
        self.pasteboard = pasteboard
        self.environment = environment
    }

    private var keyboard: SyntheticKeyboard {
        if Diagnostics.insertOnlyInto != nil {
            // Only ever the test target; if it's gone, a process that can't exist.
            return SyntheticKeyboard(destination: .process(environment.frontApp?.pid ?? -1), marker: KeyDecoder.marker)
        }
        return SyntheticKeyboard(destination: .hidEventTap, marker: KeyDecoder.marker)
    }

    func backspace(_ count: Int) { keyboard.press(CGKeyCode(kVK_Delete), count: count) }
    func left(_ count: Int) { keyboard.press(CGKeyCode(kVK_LeftArrow), count: count) }
    func type(_ text: String) { keyboard.typeNow(text) }

    func paste(_ text: String, restore: Bool) async {
        let keyboard = self.keyboard
        let paster = ClipboardPaster(pasteboard: pasteboard, writeDelay: .milliseconds(30), restoreDelay: .milliseconds(450)) {
            keyboard.paste()
        }
        let done = onPasteFinished
        await withCheckedContinuation { continuation in
            paster.paste(text, restore: restore, onPasted: { continuation.resume() }, completion: { done?($0) })
        }
    }

    func pasteFormatted(_ resolved: Resolved, restore: Bool) async {
        let text = RichText.assemble(resolved, formatted: formattedText)
        let types = RichText.pasteboardTypes(text, plain: resolved.text)
        let keyboard = self.keyboard
        let paster = RichClipboardPaster(pasteboard: pasteboard) { keyboard.paste() }
        let done = onPasteFinished
        await withCheckedContinuation { continuation in
            paster.paste(types, restore: restore, onPasted: { continuation.resume() }, completion: { done?($0) })
        }
    }
}

/// Who holds secure input, probably (the session's `kCGSSessionSecureInputPID`; macOS can
/// name the wrong app when a background app holds it).
enum SecureInputHolder {
    static func appName() -> String? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = session["kCGSSessionSecureInputPID"] as? Int32, pid > 0 else { return nil }
        if let app = NSRunningApplication(processIdentifier: pid) { return app.localizedName }
        var name = [UInt8](repeating: 0, count: 256)
        let length = proc_name(pid, &name, UInt32(name.count))
        return length > 0 ? String(decoding: name.prefix(Int(length)), as: UTF8.self) : nil
    }
}

/// The current input source: a plain layout, or an input method (Japanese, Chinese,
/// Korean, Vietnamese...) whose keystrokes are composition, not text.
enum InputSource {
    static var isInputMethod: Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) else { return false }
        let type = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
        return type == (kTISTypeKeyboardInputMode as String) || type == (kTISTypeKeyboardInputMethodModeEnabled as String)
            || type == (kTISTypeKeyboardInputMethodWithoutModes as String)
    }

    static let changedNotification = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
}

/// Accessibility (to type) and Input Monitoring (to listen), as macOS reports them.
enum KeyboardPermissions {
    static var canPost: Bool {
        if let assumed = Diagnostics.assumeTrusted { return assumed }
        return AXIsProcessTrusted()
    }

    static var canListen: Bool {
        if let assumed = Diagnostics.assumeTrusted { return assumed }
        return CGPreflightListenEventAccess()
    }

    /// Input Monitoring's pane.
    static let inputMonitoringURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!

    static func requestListening() {
        _ = CGRequestListenEventAccess()
        NSWorkspace.shared.open(inputMonitoringURL)
    }
}
