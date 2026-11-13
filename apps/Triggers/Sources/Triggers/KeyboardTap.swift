import AppKit
import CoreGraphics
import IOKit
import os
import TriggersCore

/// The keyboard tap: key sequences and the hyper key. It exists only while an enabled key
/// sequence is bound or the hyper key is on (and Triggers isn't paused and has Accessibility),
/// so for everyone else typing never passes through Triggers. It watches key down, key up and
/// flags changed only, at the HID level (so the hyper key's modifiers reach every app's
/// shortcuts), on its own thread. The callback does a few comparisons under an uncontended
/// lock and returns; sequences never swallow keys. Like every event tap, it's blind while a
/// password field holds secure input.
@MainActor
final class KeyboardTap: KeyboardEventSource {
    var onSequence: ((KeySequence) -> Void)?
    var isInstalled: Bool { port != nil }
    /// One line for Settings when the hyper key couldn't be turned on.
    var hyperProblem: String? { hyper.problem }
    var isHyperActive: Bool { hyper.isActive }
    var onChange: (() -> Void)?

    private var port: CFMachPort?
    private var thread: Thread?
    private let shared = KeyboardTapShared()
    let hyper: HyperKeyController
    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var wakeObserver: NSObjectProtocol?
    private var reapplyPending = false

    init() {
        let remapper: KeyRemapper = Diagnostics.mayRemapKeys ? HIDUtilRemapper() : LoggingRemapper()
        hyper = HyperKeyController(remapper: remapper)
        shared.fire = { [weak self] sequence in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.onSequence?(sequence) } }
        }
        shared.gaveUp = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.remove() } }
        }
    }

    /// At launch: a remap left over from a crash whose watchdog didn't run (rare) is undone.
    func cleanUpLeftovers() {
        guard Diagnostics.defaults.bool(forKey: HIDUtilRemapper.appliedKey) else { return }
        hyper.cleanUpLeftovers()
    }

    func install() -> Bool {
        guard port == nil, !Diagnostics.noInput else { return port != nil }
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: KeyboardTapShared.eventMask, callback: keyboardTapCallback,
                                          userInfo: Unmanaged.passUnretained(shared).toOpaque())
        else {
            Diagnostics.record("keyboard tap refused (no Accessibility?)")
            return false
        }
        port = tap
        shared.begin(port: tap)
        let ready = DispatchSemaphore(value: 0)
        let box = RunLoopBox()
        box.port = tap
        let thread = Thread {
            guard let tap = box.port, let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else { ready.signal(); return }
            box.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "Triggers keyboard tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        shared.runLoopBox = box
        self.thread = thread
        Diagnostics.record("keyboard tap installed")
        return true
    }

    func remove() {
        // The remap goes first: without the tap, Caps Lock would type nothing at all.
        setHyper(false)
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        if let runLoop = shared.runLoopBox?.runLoop { CFRunLoopStop(runLoop) }
        shared.end()
        self.port = nil
        thread = nil
        Diagnostics.record("keyboard tap removed")
    }

    func update(sequences: [KeySequence], hyperKey: Bool) {
        shared.setSequences(sequences)
        setHyper(hyperKey && isInstalled)
    }

    private func setHyper(_ on: Bool) {
        guard on != hyper.isActive || (on && hyper.problem != nil) else { return }
        hyper.setActive(on)
        shared.setHyper(hyper.isActive)
        if hyper.isActive { watchKeyboards() } else { unwatchKeyboards() }
        Diagnostics.record("hyper key \(hyper.isActive ? "on" : "off")\(hyper.problem.map { ": \($0)" } ?? "")")
        onChange?()
    }

    // MARK: New keyboards and wake: they don't have the remap yet

    private func watchKeyboards() {
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.scheduleReapply() }
            }
        }
        guard notifyPort == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        let context = Unmanaged.passUnretained(self).toOpaque()
        var iterator: io_iterator_t = 0
        let callback: IOServiceMatchingCallback = { context, iterator in
            while case let object = IOIteratorNext(iterator), object != 0 { IOObjectRelease(object) }
            guard let context else { return }
            let tap = Unmanaged<KeyboardTap>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { tap.scheduleReapply() }
        }
        let matching = IOServiceMatching("IOHIDEventService") as NSMutableDictionary
        matching["PrimaryUsagePage"] = 1
        matching["PrimaryUsage"] = 6   // keyboards
        if IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, matching, callback, context, &iterator) == KERN_SUCCESS {
            while case let object = IOIteratorNext(iterator), object != 0 { IOObjectRelease(object) }
            iterators.append(iterator)
        }
    }

    private func unwatchKeyboards() {
        for iterator in iterators { IOObjectRelease(iterator) }
        iterators.removeAll()
        if let port = notifyPort { IONotificationPortDestroy(port) }
        notifyPort = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    /// Keyboards arrive in bursts (wake, a dock): remap once, a second later.
    private func scheduleReapply() {
        guard hyper.isActive, !reapplyPending else { return }
        reapplyPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            MainActor.assumeIsolated {
                self.reapplyPending = false
                self.hyper.reapply()
                Diagnostics.record("hyper key remap re-applied")
            }
        }
    }

    var callbackLatency: LatencyStats { shared.latency() }
}

/// State shared between the main thread and the keyboard tap's thread.
final class KeyboardTapShared: @unchecked Sendable {
    private struct State {
        var hyper = HyperKeyDecider()
        var hyperOn = false
        var matcher = KeySequenceMatcher()
        var latency = LatencyStats()
        var timeouts: [Double] = []
    }

    static let eventMask: CGEventMask =
        (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

    private let lock = OSAllocatedUnfairLock(initialState: State())
    nonisolated(unsafe) var port: CFMachPort?
    nonisolated(unsafe) var runLoopBox: RunLoopBox?
    nonisolated(unsafe) var fire: (@Sendable (KeySequence) -> Void)?
    nonisolated(unsafe) var gaveUp: (@Sendable () -> Void)?
    private let source = CGEventSource(stateID: .privateState)

    func begin(port: CFMachPort) {
        self.port = port
        lock.withLock { $0.hyper.reset() }
    }

    func end() {
        port = nil
        lock.withLock { $0.hyper.reset() }
    }

    func setSequences(_ sequences: [KeySequence]) { lock.withLock { $0.matcher.set(sequences) } }

    func setHyper(_ on: Bool) {
        lock.withLock { state in
            state.hyperOn = on
            if !on { state.hyper.reset() }
        }
    }

    func latency() -> LatencyStats { lock.withLock { $0.latency } }

    /// Whether a mouse button went down since `time` (seconds since boot).
    private static func clicked(since time: Double, now: Double) -> Bool {
        let elapsed = now - time
        let left = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)
        let right = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .rightMouseDown)
        return min(left, right) < elapsed
    }

    /// The whole decision for one event. Returns nil to drop it.
    func handle(_ type: CGEventType, _ event: CGEvent, start: UInt64) -> Unmanaged<CGEvent>? {
        let isOwn = event.getIntegerValueField(.eventSourceUserData) == MouseTapDecider.ownEventMarker
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let time = Double(event.timestamp) / 1_000_000_000
        let kind: HyperKeyDecider.EventKind = type == .keyDown ? .keyDown : type == .keyUp ? .keyUp : .flagsChanged
        var toPost: [KeyPostPlan.Event] = []
        var sequence: KeySequence?
        let keep: Bool = lock.withLockUnchecked { state in
            defer { state.latency.record(seconds: MouseTapShared.seconds(since: start)) }
            var flags = event.flags.rawValue
            if state.hyperOn {
                switch state.hyper.decide(kind, keyCode: keyCode, flags: flags, isRepeat: isRepeat, time: time, isOwnEvent: isOwn,
                                          clickedSince: { Self.clicked(since: $0, now: time) }) {
                case .pass: break
                case .passWithFlags(let new):
                    flags = new
                    event.flags = CGEventFlags(rawValue: new)
                case .replace(let events):
                    toPost = events
                    return false
                }
            }
            guard !isOwn, !state.matcher.isEmpty else { return true }
            let modifiers = Modifiers(cgFlags: flags)
            switch kind {
            case .keyDown:
                sequence = state.matcher.keyDown(keyCode: keyCode, modifiers: modifiers, isRepeat: isRepeat, time: time)
            case .flagsChanged where !state.hyper.isHeld:
                sequence = state.matcher.flagsChanged(modifiers, time: time) { Self.clicked(since: $0, now: time) }
            default:
                break
            }
            return true
        }
        for planned in toPost { post(planned) }
        if let sequence { fire?(sequence) }
        return keep ? Unmanaged.passUnretained(event) : nil
    }

    private func post(_ planned: KeyPostPlan.Event) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(planned.keyCode), keyDown: planned.kind != .keyUp) else { return }
        if planned.kind == .flagsChanged { event.type = .flagsChanged }
        event.flags = CGEventFlags(rawValue: planned.flags)
        event.setIntegerValueField(.eventSourceUserData, value: MouseTapDecider.ownEventMarker)
        event.post(tap: .cghidEventTap)
    }

    func timedOut() {
        let now = CFAbsoluteTimeGetCurrent()
        let tooMany = lock.withLock { state -> Bool in
            state.timeouts = state.timeouts.filter { now - $0 < 60 } + [now]
            return state.timeouts.count >= 3
        }
        if tooMany { gaveUp?() } else if let port { CGEvent.tapEnable(tap: port, enable: true) }
    }
}

private let keyboardTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let shared = Unmanaged<KeyboardTapShared>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout:
        Diagnostics.record("keyboard tap disabled by timeout")
        shared.timedOut()
        return Unmanaged.passUnretained(event)
    case .tapDisabledByUserInput:
        return Unmanaged.passUnretained(event)
    case .keyDown, .keyUp, .flagsChanged:
        return shared.handle(type, event, start: mach_absolute_time())
    default:
        return Unmanaged.passUnretained(event)
    }
}

// MARK: - The Caps Lock remap

/// Remaps Caps Lock to F18 with `/usr/bin/hidutil` (Apple TN2450). Such a remap lasts until the
/// Mac restarts, so a watchdog undoes it if Triggers dies: a tiny `sh` that blocks reading a
/// pipe only Triggers holds open. When Triggers exits for any reason (quit, crash, kill -9)
/// the pipe closes, `cat` returns, and the watchdog clears the mapping. It ignores the
/// terminal's interrupt signals, so stopping a test run with ⌃C still cleans up.
@MainActor
final class HIDUtilRemapper: KeyRemapper {
    static let appliedKey = "hyperRemapApplied"
    private static let hidutil = "/usr/bin/hidutil"
    private var watchdog: Process?
    private var lifeline: FileHandle?

    func currentMapping() -> KeyRemapState {
        guard let output = Self.run(["property", "--get", "UserKeyMapping"]) else { return .other }
        return UserKeyMappingText.state(of: output)
    }

    func applyHyper() -> Bool {
        startWatchdog()
        guard Self.run(["property", "--set", UserKeyMappingText.hyperJSON]) != nil else {
            stopWatchdog()
            return false
        }
        Diagnostics.defaults.set(true, forKey: Self.appliedKey)
        return true
    }

    func removeHyper() {
        stopWatchdog()
        _ = Self.run(["property", "--set", UserKeyMappingText.clearJSON])
        Diagnostics.defaults.set(false, forKey: Self.appliedKey)
    }

    private func startWatchdog() {
        guard watchdog == nil else { return }
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "trap '' INT TERM HUP; cat >/dev/null; \(Self.hidutil) property --set \"$0\" >/dev/null 2>&1",
                             UserKeyMappingText.clearJSON]
        process.standardInput = pipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // Only Triggers may hold the pipe open: no other child process inherits it.
        _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETFD, FD_CLOEXEC)
        do {
            try process.run()
            watchdog = process
            lifeline = pipe.fileHandleForWriting
        } catch {
            Diagnostics.record("hyper key watchdog didn't start: \(error)")
        }
    }

    private func stopWatchdog() {
        if let watchdog, watchdog.isRunning { kill(watchdog.processIdentifier, SIGKILL) }
        try? lifeline?.close()   // lets its `cat` finish
        watchdog = nil
        lifeline = nil
    }

    /// Runs hidutil and returns its output, or nil if it failed.
    private static func run(_ arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: hidutil)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
        } catch {
            return nil
        }
    }
}

/// Test mode and dry runs: the remap is only logged, so a test never changes the keyboard.
@MainActor
final class LoggingRemapper: KeyRemapper {
    private var applied = false

    func currentMapping() -> KeyRemapState { applied ? .ours : .none }

    func applyHyper() -> Bool {
        applied = true
        Diagnostics.record("test mode: would remap Caps Lock to F18 (hyper key)")
        return true
    }

    func removeHyper() {
        if applied { Diagnostics.record("test mode: would clear the Caps Lock remap") }
        applied = false
    }
}
