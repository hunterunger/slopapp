import Foundation
@testable import TriggersCore

@MainActor
final class FakeTouchSource: TouchFrameSource {
    var unavailableReason: String?
    var onGesture: ((Gesture) -> Void)?
    var onFingers: ((Int) -> Void)?
    var reportsFingers = false
    var tuning = GestureTuning()
    var interests = GestureInterests.immediate { didSet { recognizer.interests = interests } }
    private(set) var isRunning = false
    private(set) var starts = 0

    func start() { isRunning = true; starts += 1 }
    func stop() { isRunning = false }

    /// Feeds frames through a real recognizer, like the real source does.
    var recognizer = GestureRecognizer()
    func feed(_ frames: [TouchFrame], device: Int = 1) {
        guard isRunning else { return }
        for frame in frames {
            for gesture in recognizer.process(device: device, timestamp: frame.timestamp, contacts: frame.touches).gestures {
                onGesture?(gesture)
            }
        }
    }

    /// Time passes with no fingers on the pad (a held-back single tap is let go).
    func idle(until time: Double) {
        for gesture in recognizer.flush(now: time) { onGesture?(gesture) }
    }
}

@MainActor
final class FakeMouseSource: MouseButtonSource {
    private(set) var isInstalled = false
    var onFire: ((UUID, Trigger) -> Void)?
    var allowsInstall = true
    private(set) var routes = MouseRoutes.empty
    private(set) var installs = 0
    private var decider = MouseTapDecider()

    func install() -> Bool {
        guard allowsInstall else { return false }
        isInstalled = true
        installs += 1
        return true
    }

    func remove() { isInstalled = false; routes = .empty; decider.reset() }
    func update(routes: MouseRoutes) { self.routes = routes }

    /// A press as the real tap would see it. Returns whether it was swallowed.
    @discardableResult
    func press(_ button: Int, modifiers: Modifiers = []) -> (down: MouseTapDecider.Decision, up: MouseTapDecider.Decision) {
        guard isInstalled else { return (.pass, .pass) }
        let down = decider.decide(phase: .down, button: button, modifiers: modifiers, routes: routes, isOwnEvent: false)
        if case .swallowAndFire(let id) = down { onFire?(id, .mouseButton(button, modifiers: modifiers)) }
        let up = decider.decide(phase: .up, button: button, modifiers: modifiers, routes: routes, isOwnEvent: false)
        return (down, up)
    }
}

@MainActor
final class FakeHotkeys: HotkeyRegistrar {
    var onPress: ((KeyCombo) -> Void)?
    private(set) var registered: Set<KeyCombo> = []
    var takenByOthers: Set<KeyCombo> = []

    func sync(_ combos: Set<KeyCombo>) -> Set<KeyCombo> {
        registered = combos.subtracting(takenByOthers)
        return combos.intersection(takenByOthers)
    }

    /// The person presses a combo: fires only if registered (as Carbon does).
    func press(_ combo: KeyCombo) { if registered.contains(combo) { onPress?(combo) } }

    private(set) var suspended: [KeyCombo] = []
    func suspend(_ combo: KeyCombo, for seconds: Double) { suspended.append(combo) }
}

@MainActor
final class FakeKeyboard: KeyboardEventSource {
    private(set) var isInstalled = false
    var onSequence: ((KeySequence) -> Void)?
    var allowsInstall = true
    private(set) var sequences: [KeySequence] = []
    private(set) var hyperKey = false
    private(set) var installs = 0
    /// The real matcher, as the tap uses it.
    private var matcher = KeySequenceMatcher()

    func install() -> Bool {
        guard allowsInstall else { return false }
        isInstalled = true
        installs += 1
        return true
    }

    func remove() {
        isInstalled = false
        sequences = []
    }

    func update(sequences: [KeySequence], hyperKey: Bool) {
        self.sequences = sequences
        self.hyperKey = hyperKey
        matcher.set(sequences)
    }

    func key(_ keyCode: Int, _ modifiers: Modifiers = [], at time: Double) {
        guard isInstalled, let sequence = matcher.keyDown(keyCode: keyCode, modifiers: modifiers, isRepeat: false, time: time) else { return }
        onSequence?(sequence)
    }

    func tapModifier(_ modifier: Modifiers, at time: Double) {
        guard isInstalled else { return }
        _ = matcher.flagsChanged(modifier, time: time)
        if let sequence = matcher.flagsChanged([], time: time + 0.05) { onSequence?(sequence) }
    }
}

@MainActor
final class FakeState: SystemStateReader {
    var running: Set<String> = []
    var network = NetworkState(isOnline: true, usesWiFi: true)
    var displays = [DisplayInfo(name: "Built-in Display", isBuiltIn: true)]
    var power = PowerSourceKind.charger
    var now = Date(timeIntervalSince1970: 1_800_000_000)   // a Friday, 08:00 UTC
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    var modifiers: Modifiers = []
    var isDarkMode = false

    func isRunning(bundleID: String) -> Bool { running.contains(bundleID) }
}

/// Runs scheduled work only when the test advances time.
@MainActor
final class FakeScheduler: Scheduler {
    final class Work: ScheduledWork {
        let due: Double
        let work: @MainActor () -> Void
        var cancelled = false
        init(due: Double, work: @escaping @MainActor () -> Void) { self.due = due; self.work = work }
        func cancel() { cancelled = true }
    }

    let clock: ManualClock
    private(set) var pending: [Work] = []

    init(clock: ManualClock) { self.clock = clock }

    func schedule(after seconds: Double, _ work: @escaping @MainActor () -> Void) -> ScheduledWork {
        let item = Work(due: clock.now + seconds, work: work)
        pending.append(item)
        return item
    }

    /// Moves the clock forward, running whatever comes due, in order.
    func advance(_ seconds: Double) {
        let end = clock.now + seconds
        while let next = pending.filter({ !$0.cancelled && $0.due <= end }).min(by: { $0.due < $1.due }) {
            pending.removeAll { $0 === next }
            clock.now = max(clock.now, next.due)
            next.work()
        }
        pending.removeAll { $0.cancelled }
        clock.now = end
    }

    var hasPending: Bool { pending.contains { !$0.cancelled } }
}

@MainActor
final class RecordingPerformer: ActionPerformer {
    struct Call: Equatable { var action: Action; var app: String?; var trigger: Trigger }
    private(set) var calls: [Call] = []
    var result: ActionResult = .done
    /// Per-action results, overriding `result`.
    var results: [Action: ActionResult] = [:]
    /// Actions that finish later: their `finished` callbacks wait here.
    var slow: Set<Action> = []
    private(set) var waiting: [(Action, @MainActor (ActionResult) -> Void)] = []
    private(set) var delivered: [Trigger] = []

    func perform(_ action: Action, context: ActionContext, finished: @escaping @MainActor (ActionResult) -> Void) -> ActionResult? {
        calls.append(Call(action: action, app: context.frontApp?.bundleID, trigger: context.trigger))
        if slow.contains(action) {
            waiting.append((action, finished))
            return nil
        }
        return results[action] ?? result
    }

    func deliverOriginal(_ trigger: Trigger, context: ActionContext?) { delivered.append(trigger) }

    /// The slow action finishes.
    func finishWaiting(_ result: ActionResult = .done) {
        let pending = waiting
        waiting = []
        for (_, finished) in pending { finished(result) }
    }
}

struct FixedModifiers: ModifierReader {
    var value: Modifiers = []
    func current() -> Modifiers { value }
}

final class ManualClock: @unchecked Sendable {
    var now = 100.0
}

@MainActor
struct EngineRig {
    let touch = FakeTouchSource()
    let mouse = FakeMouseSource()
    let keyboard = FakeKeyboard()
    let hotkeys = FakeHotkeys()
    let performer = RecordingPerformer()
    let state = FakeState()
    let clock = ManualClock()
    let scheduler: FakeScheduler
    let engine: TriggerEngine

    init(modifiers: Modifiers = []) {
        let clock = self.clock
        scheduler = FakeScheduler(clock: clock)
        engine = TriggerEngine(touch: touch, mouse: mouse, keyboard: keyboard, hotkeys: hotkeys, performer: performer,
                               state: state, modifiers: FixedModifiers(value: modifiers), scheduler: scheduler, clock: { clock.now })
        engine.isAccessibilityTrusted = true
    }
}

let safari = FrontApp(bundleID: "com.apple.Safari", name: "Safari", pid: 10)
let notes = FrontApp(bundleID: "com.apple.Notes", name: "Notes", pid: 11)
let game = FrontApp(bundleID: "com.example.game", name: "Game", pid: 12)
let cmdLeftBracket = KeyCombo(keyCode: KeyNames.leftBracket, modifiers: .command)
let ctrlOptK = KeyCombo(keyCode: 40, modifiers: [.control, .option])
