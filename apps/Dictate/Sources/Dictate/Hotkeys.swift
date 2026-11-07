import AppKit
import Carbon.HIToolbox
import DictateCore
import SlopKit

extension KeyboardShortcuts.Name {
    /// Start/stop dictation when the trigger is a keyboard shortcut. No default: the
    /// default trigger is the Fn key, and any combination could collide with someone's own.
    static let record = Self("record")
    /// Command Mode: rewrite the selected text by voice.
    static let commandMode = Self("commandMode")
    /// Paste the last transcript again.
    static let pasteLast = Self("pasteLast")
}

/// Wires the triggers (Fn key or a shortcut, Command Mode's shortcut, Esc) to the
/// dictation controller, through `TriggerGesture` for hold, toggle and hold-or-tap.
final class Hotkeys {
    private let settings: DictateSettings
    private let controller: DictationController
    var onPasteLast: () -> Void = {}

    private var dictation = TriggerGesture()
    private var command = TriggerGesture()
    private let fnMonitor = FunctionKeyMonitor()
    private let escape = EscapeHotKey()
    private var observing = false

    init(settings: DictateSettings, controller: DictationController) {
        self.settings = settings
        self.controller = controller
    }

    func start() {
        KeyboardShortcuts.onKeyDown(for: .record) { [weak self] in self?.press(.dictation) }
        KeyboardShortcuts.onKeyUp(for: .record) { [weak self] in self?.release(.dictation) }
        KeyboardShortcuts.onKeyDown(for: .commandMode) { [weak self] in self?.press(.command) }
        KeyboardShortcuts.onKeyUp(for: .commandMode) { [weak self] in self?.release(.command) }
        KeyboardShortcuts.onKeyUp(for: .pasteLast) { [weak self] in self?.onPasteLast() }
        fnMonitor.onDown = { [weak self] in self?.press(.dictation) }
        fnMonitor.onUp = { [weak self] in self?.release(.dictation) }
        escape.onPress = { [weak self] in self?.controller.cancel() }
        controller.onEnded = { [weak self] in
            self?.dictation.reset()
            self?.command.reset()
        }
        applyTrigger()
        observe()
    }

    /// Follows the settings and the controller (Esc only while a dictation is in progress).
    private func observe() {
        withObservationTracking {
            _ = settings.triggerKind
            _ = controller.isBusy
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyTrigger()
                self?.observe()
            }
        }
    }

    private func applyTrigger() {
        switch settings.triggerKind {
        case .function:
            KeyboardShortcuts.disable(.record)
            fnMonitor.start()
        case .custom:
            fnMonitor.stop()
            KeyboardShortcuts.enable(.record)
        }
        escape.isRegistered = controller.isBusy
    }

    /// Restarts the Fn monitor (after Accessibility is granted, global monitors need a fresh start).
    func refreshMonitor() {
        guard settings.triggerKind == .function else { return }
        fnMonitor.stop()
        fnMonitor.start()
    }

    private func press(_ mode: DictationMode) {
        let now = ProcessInfo.processInfo.systemUptime
        var gesture = mode == .dictation ? dictation : command
        let action = gesture.press(mode: settings.hotkeyMode, at: now)
        if action == .start, !controller.begin(mode) { gesture.reset() }
        if action == .stop { controller.end() }
        store(gesture, for: mode)
    }

    private func release(_ mode: DictationMode) {
        let now = ProcessInfo.processInfo.systemUptime
        var gesture = mode == .dictation ? dictation : command
        if gesture.release(mode: settings.hotkeyMode, at: now) == .stop { controller.end() }
        store(gesture, for: mode)
    }

    private func store(_ gesture: TriggerGesture, for mode: DictationMode) {
        if mode == .dictation { dictation = gesture } else { command = gesture }
    }
}

/// Watches the Fn (Globe) key, which Carbon hotkeys can't bind. The global monitor needs
/// Accessibility; the local one covers Dictate's own windows. Monitors only observe, so
/// people should set "Press Globe key to: Do Nothing" in System Settings › Keyboard.
final class FunctionKeyMonitor {
    var onDown: () -> Void = {}
    var onUp: () -> Void = {}
    private var global: Any?
    private var local: Any?
    private var isDown = false

    func start() {
        guard global == nil else { return }
        global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    func stop() {
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        global = nil
        local = nil
        if isDown {
            isDown = false
            onUp()
        }
    }

    private func handle(_ event: NSEvent) {
        // Only the Fn key itself; arrows and F-keys also carry the .function flag.
        guard event.keyCode == UInt16(kVK_Function) else { return }
        let down = event.modifierFlags.contains(.function)
        if down, !isDown {
            isDown = true
            onDown()
        } else if !down, isDown {
            isDown = false
            onUp()
        }
    }
}

/// Esc as a global hotkey, only while a dictation is in progress, so it cancels the
/// dictation instead of reaching the app in front. Never registered otherwise.
final class EscapeHotKey {
    var onPress: () -> Void = {}
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x4443_5445   // "DCTE"
    /// The live instance for the C callback (there's only ever one).
    nonisolated(unsafe) private static weak var current: EscapeHotKey?

    var isRegistered: Bool = false {
        didSet {
            guard isRegistered != oldValue else { return }
            isRegistered ? register() : unregister()
        }
    }

    private func register() {
        installHandlerIfNeeded()
        Self.current = self
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        if RegisterEventHotKey(UInt32(kVK_Escape), 0, id, GetEventDispatcherTarget(), 0, &ref) == noErr {
            hotKey = ref
        }
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == EscapeHotKey.signature else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { EscapeHotKey.current?.onPress() }
            }
            return noErr
        }, 1, &type, nil, &handler)
    }
}
