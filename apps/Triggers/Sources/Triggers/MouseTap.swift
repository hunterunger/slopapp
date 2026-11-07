import AppKit
import CoreGraphics
import os
import TriggersCore

/// The only event tap Triggers installs: other-mouse down, up and dragged (extra buttons). It
/// exists only while an enabled mouse binding exists, Triggers isn't paused and Accessibility
/// is granted, and runs on its own thread so a busy main thread never stalls anyone's input.
/// The callback reads the routes under an uncontended lock, decides in constant time and hands
/// the action to the main thread. No allocation, no Accessibility or workspace calls inside.
@MainActor
final class MouseTap: MouseButtonSource {
    var onFire: ((UUID, Trigger) -> Void)?
    /// Called when macOS keeps disabling the tap (it was too slow too often) and Triggers gave up.
    var onGaveUp: (() -> Void)?
    var isInstalled: Bool { port != nil }

    private var port: CFMachPort?
    private var thread: Thread?
    private let shared = MouseTapShared()

    init() {
        shared.fire = { [weak self] id, trigger in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.onFire?(id, trigger) } }
        }
        shared.gaveUp = { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.remove()
                    self?.onGaveUp?()
                }
            }
        }
    }

    func install() -> Bool {
        guard port == nil, !Diagnostics.noInput else { return port != nil }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: MouseTapDecider.eventMask, callback: mouseTapCallback,
                                          userInfo: Unmanaged.passUnretained(shared).toOpaque())
        else {
            Diagnostics.record("mouse tap refused (no Accessibility?)")
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
        thread.name = "Triggers mouse tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        shared.runLoopBox = box
        self.thread = thread
        Diagnostics.record("mouse tap installed")
        return true
    }

    func remove() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        if let runLoop = shared.runLoopBox?.runLoop { CFRunLoopStop(runLoop) }
        shared.end()
        self.port = nil
        thread = nil
        Diagnostics.record("mouse tap removed")
    }

    func update(routes: MouseRoutes) { shared.setRoutes(routes) }

    var callbackLatency: LatencyStats { shared.latency() }
}

/// Holds the run loop of the tap thread (set on that thread before `ready` is signalled).
final class RunLoopBox: @unchecked Sendable {
    var runLoop: CFRunLoop?
    var port: CFMachPort?
}

/// State shared between the main thread and the tap thread.
final class MouseTapShared: @unchecked Sendable {
    private struct State {
        var decider = MouseTapDecider()
        var routes = MouseRoutes.empty
        var latency = LatencyStats()
        var timeouts: [Double] = []
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())
    nonisolated(unsafe) var port: CFMachPort?
    nonisolated(unsafe) var runLoopBox: RunLoopBox?
    nonisolated(unsafe) var fire: (@Sendable (UUID, Trigger) -> Void)?
    nonisolated(unsafe) var gaveUp: (@Sendable () -> Void)?
    static let signposter = OSSignposter(subsystem: "app.slopapp.triggers", category: "tap")

    func begin(port: CFMachPort) {
        self.port = port
        lock.withLock { $0.decider.reset() }
    }

    func end() {
        port = nil
        lock.withLock { $0.decider.reset() }
    }

    func setRoutes(_ routes: MouseRoutes) { lock.withLock { $0.routes = routes } }

    func latency() -> LatencyStats { lock.withLock { $0.latency } }

    func decide(_ event: CGEvent, start: UInt64) -> MouseTapDecider.Decision {
        lock.withLockUnchecked { state in
            let decision = state.decider.decide(event, routes: state.routes)
            state.latency.record(seconds: Self.seconds(since: start))
            return decision
        }
    }

    /// macOS disabled the tap for being slow. Re-enable; three times in a minute means
    /// something is wrong: give up rather than fight the system.
    func timedOut() {
        let now = CFAbsoluteTimeGetCurrent()
        let tooMany = lock.withLock { state -> Bool in
            state.timeouts = state.timeouts.filter { now - $0 < 60 } + [now]
            return state.timeouts.count >= 3
        }
        if tooMany {
            gaveUp?()
        } else if let port {
            CGEvent.tapEnable(tap: port, enable: true)
        }
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func seconds(since start: UInt64) -> Double {
        Double(mach_absolute_time() &- start) * Double(timebase.numer) / Double(timebase.denom) / 1e9
    }
}

private let mouseTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let shared = Unmanaged<MouseTapShared>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout:
        Diagnostics.record("mouse tap disabled by timeout")
        shared.timedOut()
        return Unmanaged.passUnretained(event)
    case .tapDisabledByUserInput:
        return Unmanaged.passUnretained(event)
    default:
        break
    }
    let start = mach_absolute_time()
    let signpost = MouseTapShared.signposter.isEnabled ? MouseTapShared.signposter.beginInterval("callback") : nil
    defer { if let signpost { MouseTapShared.signposter.endInterval("callback", signpost) } }
    switch shared.decide(event, start: start) {
    case .pass:
        return Unmanaged.passUnretained(event)
    case .swallow:
        return nil
    case .swallowAndFire(let id):
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        shared.fire?(id, .mouseButton(button, modifiers: Modifiers(cgFlags: event.flags.rawValue)))
        return nil
    }
}

/// Reads the window server's statistics for Triggers' own taps (`CGGetEventTapList`):
/// latency the system measured and the event mask, for the performance gate.
enum EventTapStats {
    struct Entry {
        var mask: CGEventMask
        var minMicroseconds: Float
        var avgMicroseconds: Float
        var maxMicroseconds: Float
        var enabled: Bool
        var isActive: Bool
    }

    static func ours() -> [Entry] {
        var count: UInt32 = 0
        guard CGGetEventTapList(0, nil, &count) == .success, count > 0 else { return [] }
        var list = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
        guard CGGetEventTapList(count, &list, &count) == .success else { return [] }
        let pid = getpid()
        return list.prefix(Int(count)).filter { $0.tappingProcess == pid }.map {
            Entry(mask: $0.eventsOfInterest, minMicroseconds: $0.minUsecLatency, avgMicroseconds: $0.avgUsecLatency,
                  maxMicroseconds: $0.maxUsecLatency, enabled: $0.enabled, isActive: $0.options == .defaultTap)
        }
    }

    static func summary() -> String {
        let entries = ours()
        if entries.isEmpty { return "taps=0" }
        return entries.enumerated().map { index, entry in
            String(format: "tap%d mask=0x%llx minimal=%@ enabled=%@ min_us=%.1f avg_us=%.1f max_us=%.1f", index, entry.mask,
                   MouseTapDecider.maskIsMinimal(entry.mask) ? "yes" : "NO", entry.enabled ? "yes" : "no",
                   entry.minMicroseconds, entry.avgMicroseconds, entry.maxMicroseconds)
        }.joined(separator: "; ")
    }
}
