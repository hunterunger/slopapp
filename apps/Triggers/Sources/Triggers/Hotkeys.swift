import AppKit
import Carbon.HIToolbox
import SlopKit
import TriggersCore

/// Key-combo triggers as Carbon hotkeys: no keyboard event tap, no Input Monitoring, nothing in
/// the typing path. They keep firing while a password field holds secure input (verified on
/// macOS 27.2, docs/research/triggers.md spikes). Per-app bindings are registered only while
/// their app is in front, so the combo stays the app's own everywhere else.
@MainActor
final class CarbonHotkeys: HotkeyRegistrar {
    var onPress: ((KeyCombo) -> Void)?
    private var registered: [KeyCombo: EventHotKeyRef] = [:]
    private var ids: [UInt32: KeyCombo] = [:]
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x5452_4753 // "TRGS"

    /// What the engine wants registered (a suspended combo comes back to this).
    private var wanted: Set<KeyCombo> = []

    func sync(_ combos: Set<KeyCombo>) -> Set<KeyCombo> {
        wanted = combos
        guard !Diagnostics.noInput else { return [] }
        installHandlerIfNeeded()
        for (combo, ref) in registered where !combos.contains(combo) {
            UnregisterEventHotKey(ref)
            registered[combo] = nil
            ids = ids.filter { $0.value != combo }
        }
        var failed: Set<KeyCombo> = []
        for combo in combos where registered[combo] == nil {
            var ref: EventHotKeyRef?
            let id = nextID
            nextID &+= 1
            let status = RegisterEventHotKey(UInt32(combo.keyCode), combo.modifiers.carbonFlags,
                                             EventHotKeyID(signature: Self.signature, id: id),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                registered[combo] = ref
                ids[id] = combo
            } else {
                failed.insert(combo)
            }
        }
        return failed
    }

    /// Lets one press through: unregistered now, registered again after `seconds` (the posted
    /// copy must reach the app first, or the hotkey would catch it again).
    func suspend(_ combo: KeyCombo, for seconds: Double) {
        guard let ref = registered[combo] else { return }
        UnregisterEventHotKey(ref)
        registered[combo] = nil
        ids = ids.filter { $0.value != combo }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            MainActor.assumeIsolated { _ = self.sync(self.wanted) }
        }
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == CarbonHotkeys.signature else { return OSStatus(eventNotHandledErr) }
            let hotkeys = Unmanaged<CarbonHotkeys>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                if let combo = hotkeys.ids[hotKeyID.id] { hotkeys.onPress?(combo) }
            }
            return noErr
        }, 1, &spec, context, &handler)
    }
}

/// Key combos macOS itself uses (System Settings › Keyboard › Keyboard Shortcuts), read with
/// the public `CopySymbolicHotKeys`. Read-only.
enum SystemShortcuts {
    static func current() -> Set<KeyCombo> {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr, let array = unmanaged?.takeRetainedValue() as? [[String: Any]] else { return [] }
        var result: Set<KeyCombo> = []
        for entry in array {
            guard (entry[kHISymbolicHotKeyEnabled] as? Bool) == true,
                  let code = entry[kHISymbolicHotKeyCode] as? Int,
                  let carbon = entry[kHISymbolicHotKeyModifiers] as? Int else { continue }
            var modifiers: Modifiers = []
            if carbon & cmdKey != 0 { modifiers.insert(.command) }
            if carbon & optionKey != 0 { modifiers.insert(.option) }
            if carbon & controlKey != 0 { modifiers.insert(.control) }
            if carbon & shiftKey != 0 { modifiers.insert(.shift) }
            result.insert(KeyCombo(keyCode: code, modifiers: modifiers))
        }
        return result
    }
}

/// Names key combos with the current keyboard layout ("⌃⌥K" on QWERTY, "⌃⌥K" or other on AZERTY).
enum KeyDisplay {
    static func name(_ combo: KeyCombo) -> String {
        let shortcut = KeyboardShortcuts.Shortcut(carbonKeyCode: combo.keyCode, carbonModifiers: Int(combo.modifiers.carbonFlags))
        let text = shortcut.description
        return text.isEmpty ? combo.fallbackDisplay : text
    }

    static func title(_ trigger: Trigger) -> String { trigger.title(keys: name) }

    static func title(_ action: Action) -> String { action.title(keys: name) }

    static func title(_ step: ActionStep) -> String { step.title(keys: name) }

    /// "Press ⌘[", or "Open Notes → Wait 1 s → Press ⌘N".
    static func summary(_ binding: TriggerBinding) -> String { binding.summary(keys: name) }

    /// For VoiceOver: "Control-Option-K".
    static func spoken(_ combo: KeyCombo) -> String {
        let key = KeyNames.name(for: combo.keyCode)
        return combo.modifiers.isEmpty ? key : "\(combo.modifiers.spokenNames)-\(key)"
    }
}
