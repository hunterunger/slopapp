import AppKit
import CoreGraphics
import os
import ShorthandCore

/// The keyboard tap: listen-only (it can never delay, change or swallow anyone's typing),
/// key-down and modifier changes only, on its own thread with its own run loop. The callback
/// decodes the key, runs the engine under an uncontended lock in constant time, and hands a
/// match to the main actor. No allocation, no Accessibility, workspace or pasteboard calls.
@MainActor
final class KeyTap {
    nonisolated static let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

    let shared: TapShared
    private var port: CFMachPort?
    private var thread: Thread?
    private var runLoopBox: RunLoopBox?

    var isInstalled: Bool { port != nil }

    init(shared: TapShared) {
        self.shared = shared
    }

    /// Nil when macOS refused (no permission).
    func install() -> Bool {
        guard port == nil else { return true }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                          eventsOfInterest: Self.eventMask, callback: keyTapCallback,
                                          userInfo: Unmanaged.passUnretained(shared).toOpaque())
        else {
            Diagnostics.record("tap refused")
            return false
        }
        port = tap
        shared.port = tap
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
        thread.name = "Shorthand keyboard tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        runLoopBox = box
        self.thread = thread
        shared.reset()
        Diagnostics.record("tap installed (listen-only, keyDown+flagsChanged)")
        return true
    }

    func remove() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        if let runLoop = runLoopBox?.runLoop { CFRunLoopStop(runLoop) }
        shared.port = nil
        shared.reset()
        self.port = nil
        thread = nil
        runLoopBox = nil
        Diagnostics.record("tap removed")
    }
}

/// Holds the run loop of the tap thread (set on that thread before `ready` is signalled).
final class RunLoopBox: @unchecked Sendable {
    var runLoop: CFRunLoop?
    var port: CFMachPort?
}

/// State shared by the tap thread and the main actor: the engine and its latency histogram,
/// behind one lock. The main actor only holds it for a few microseconds at a time.
final class TapShared: @unchecked Sendable {
    private struct State {
        var engine = TapEngine()
        var latency = LatencyStats()
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())
    nonisolated(unsafe) var port: CFMachPort?
    /// Called on the tap thread with a decision that isn't `.none`.
    nonisolated(unsafe) var onDecision: (@Sendable (TapDecision) -> Void)?
    nonisolated(unsafe) var onDisabledByTimeout: (@Sendable () -> Void)?

    /// Runs one key through the engine; records how long the whole callback took.
    @inline(__always)
    func handle(_ input: KeyInput, start: UInt64) -> TapDecision {
        lock.withLockUnchecked { state in
            let decision = state.engine.handle(input, now: start)
            state.latency.record(microseconds: Double(MonotonicClock.now() &- start) / 1_000)
            return decision
        }
    }

    func update(_ body: (inout TapEngine) -> Void) {
        lock.withLockUnchecked { body(&$0.engine) }
    }

    func read<T>(_ body: (TapEngine) -> T) -> T {
        lock.withLockUnchecked { body($0.engine) }
    }

    var latency: LatencyStats { lock.withLock { $0.latency } }

    func resetLatency() { lock.withLock { $0.latency = LatencyStats() } }

    func reset() { update { $0.reset() } }

    // MARK: For the main actor (see TapController)

    func beginInsert(_ id: UInt64) -> TapEngine.InsertStart? {
        let now = MonotonicClock.now()
        return lock.withLockUnchecked { $0.engine.beginInsert(id, now: now) }
    }

    func finishInsert(_ id: UInt64, tail: String, undoable: Bool) {
        let now = MonotonicClock.now()
        update { $0.finishInsert(id, tail: tail, undoable: undoable, now: now) }
    }

    func cancel(_ id: UInt64) { update { $0.cancel(id) } }
    func beginUndo() { update { $0.beginUndo() } }
    func finishUndo(abbreviation: String) { update { $0.finishUndo(abbreviation: abbreviation) } }
    func inserted(tail: String) { update { $0.inserted(tail: tail) } }
}

private let keyTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let shared = Unmanaged<TapShared>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout:
        // Listen-only taps aren't in anyone's way, but macOS can still switch one off.
        shared.onDisabledByTimeout?()
        return Unmanaged.passUnretained(event)
    case .tapDisabledByUserInput:
        return Unmanaged.passUnretained(event)
    default:
        break
    }
    let start = MonotonicClock.now()
    let signpost = Diagnostics.signposter.isEnabled ? Diagnostics.signposter.beginInterval("key") : nil
    let decision = shared.handle(KeyDecoder.decode(event, type: type), start: start)
    if let signpost { Diagnostics.signposter.endInterval("key", signpost) }
    if decision != .none { shared.onDecision?(decision) }
    return Unmanaged.passUnretained(event)
}

/// The window server's statistics for Shorthand's own tap (`CGGetEventTapList`): latency the
/// system measured, the mask and whether it's listen-only, for the performance gate.
enum EventTapStats {
    struct Entry {
        var mask: CGEventMask
        var listenOnly: Bool
        var enabled: Bool
        var minMicroseconds: Float
        var avgMicroseconds: Float
        var maxMicroseconds: Float
    }

    static func ours() -> [Entry] {
        var count: UInt32 = 0
        guard CGGetEventTapList(0, nil, &count) == .success, count > 0 else { return [] }
        var list = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
        guard CGGetEventTapList(count, &list, &count) == .success else { return [] }
        let pid = getpid()
        return list.prefix(Int(count)).filter { $0.tappingProcess == pid }.map {
            Entry(mask: $0.eventsOfInterest, listenOnly: $0.options == .listenOnly, enabled: $0.enabled,
                  minMicroseconds: $0.minUsecLatency, avgMicroseconds: $0.avgUsecLatency, maxMicroseconds: $0.maxUsecLatency)
        }
    }

    static func summary() -> String {
        let entries = ours()
        if entries.isEmpty { return "taps=0" }
        return entries.enumerated().map { index, entry in
            String(format: "tap%d mask=0x%llx minimal=%@ listenOnly=%@ enabled=%@ min_us=%.1f avg_us=%.1f max_us=%.1f", index, entry.mask,
                   entry.mask == KeyTap.eventMask ? "yes" : "NO", entry.listenOnly ? "yes" : "NO", entry.enabled ? "yes" : "no",
                   entry.minMicroseconds, entry.avgMicroseconds, entry.maxMicroseconds)
        }.joined(separator: "; ")
    }
}

/// The main actor's side of the tap (the expander's `TapControl`).
@MainActor
final class TapController: TapControl {
    let shared: TapShared
    init(shared: TapShared) { self.shared = shared }
    func beginInsert(_ id: UInt64) -> TapEngine.InsertStart? { shared.beginInsert(id) }
    func finishInsert(_ id: UInt64, tail: String, undoable: Bool) { shared.finishInsert(id, tail: tail, undoable: undoable) }
    func cancel(_ id: UInt64) { shared.cancel(id) }
    func beginUndo() { shared.beginUndo() }
    func finishUndo(abbreviation: String) { shared.finishUndo(abbreviation: abbreviation) }
    func inserted(tail: String) { shared.inserted(tail: tail) }
}
