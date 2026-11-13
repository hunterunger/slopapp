import Foundation
import os

/// The app in front, cached from workspace notifications (never queried in the input path).
public struct FrontApp: Equatable, Sendable {
    public var bundleID: String?
    public var name: String
    public var pid: Int32

    public init(bundleID: String?, name: String, pid: Int32) {
        self.bundleID = bundleID
        self.name = name
        self.pid = pid
    }
}

/// What happened when an action (or a whole binding) ran.
public enum ActionResult: Equatable, Sendable {
    case done
    /// Deliberately not done (test mode outside the test target, nothing to act on).
    case skipped(String)
    /// Tried and failed; the message says what to do.
    case failed(String)
}

public struct ActionContext: Sendable {
    public var frontApp: FrontApp?
    public var binding: TriggerBinding
    /// The input as it happened (modifiers the person is still holding). For later steps of a
    /// sequence, with the modifiers held when that step runs.
    public var trigger: Trigger

    public init(frontApp: FrontApp?, binding: TriggerBinding, trigger: Trigger) {
        self.frontApp = frontApp
        self.binding = binding
        self.trigger = trigger
    }
}

// MARK: - System boundaries (faked in tests)

/// Runs actions: posts keys and clicks, chooses menu items, moves windows, opens things, runs
/// Shortcuts and scripts. The only production type that posts events.
@MainActor
public protocol ActionPerformer: AnyObject {
    /// Runs the action. Most finish before returning and return their result; ones that take
    /// time (typing a lot of text, scripts, Shortcuts) return nil and call `finished` later.
    func perform(_ action: Action, context: ActionContext, finished: @escaping @MainActor (ActionResult) -> Void) -> ActionResult?
    /// Gives the app an input Triggers swallowed but then didn't use (a mouse button or key
    /// combination whose triggers' conditions didn't hold).
    func deliverOriginal(_ trigger: Trigger, context: ActionContext?)
}

/// Carbon hotkeys for key-combo triggers.
@MainActor
public protocol HotkeyRegistrar: AnyObject {
    var onPress: ((KeyCombo) -> Void)? { get set }
    /// Registers exactly these combos, unregistering the rest. Returns the ones another app holds.
    func sync(_ combos: Set<KeyCombo>) -> Set<KeyCombo>
    /// Unregisters one combo for a moment, so a re-posted press reaches the app.
    func suspend(_ combo: KeyCombo, for seconds: Double)
}

/// The mouse-button event tap.
@MainActor
public protocol MouseButtonSource: AnyObject {
    var isInstalled: Bool { get }
    /// A swallowed press that matched a binding: its id, and the button and modifiers.
    var onFire: ((UUID, Trigger) -> Void)? { get set }
    /// Installs the tap. False if macOS refused (no Accessibility).
    func install() -> Bool
    func remove()
    func update(routes: MouseRoutes)
}

/// The keyboard tap: key sequences and the hyper key. Installed only while one of them is on.
@MainActor
public protocol KeyboardEventSource: AnyObject {
    var isInstalled: Bool { get }
    /// A sequence bound in the front app was just pressed.
    var onSequence: ((KeySequence) -> Void)? { get set }
    /// Installs the tap. False if macOS refused (no Accessibility).
    func install() -> Bool
    func remove()
    /// What to watch for, and whether Caps Lock is the hyper key right now.
    func update(sequences: [KeySequence], hyperKey: Bool)
}

/// Trackpad touch frames → gestures (recognized off the main thread, delivered on it).
@MainActor
public protocol TouchFrameSource: AnyObject {
    /// Nil when gestures work; otherwise one line on why not.
    var unavailableReason: String? { get }
    var onGesture: ((Gesture) -> Void)? { get set }
    /// Live finger count, only while `reportsFingers` is on (the recognize-only pad).
    var onFingers: ((Int) -> Void)? { get set }
    var reportsFingers: Bool { get set }
    var tuning: GestureTuning { get set }
    /// Which gestures to look for (all of them while recording).
    var interests: GestureInterests { get set }
    var isRunning: Bool { get }
    func start()
    func stop()
}

/// The modifier keys held right now (for gestures, which carry none of their own).
public protocol ModifierReader: Sendable {
    func current() -> Modifiers
}

/// Runs work later on the main actor (sequence delays and waits). Faked in tests.
@MainActor
public protocol Scheduler: AnyObject {
    func schedule(after seconds: Double, _ work: @escaping @MainActor () -> Void) -> ScheduledWork
}

@MainActor
public protocol ScheduledWork: AnyObject {
    func cancel()
}

// MARK: - Engine

/// Routes every input to its steps. Owns no system resources itself: it tells the sources
/// when to run (touch source only with gesture bindings, the taps only with mouse or keyboard
/// bindings and Accessibility, hotkeys only for the front app) and asks the performer to act.
@MainActor
public final class TriggerEngine {
    public private(set) var config = Config()
    public private(set) var table = RoutingTable(config: Config())
    public private(set) var unavailableShortcuts: Set<KeyCombo> = []

    public var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            if isPaused { cancelRunning() }
            apply()
        }
    }
    public var frontApp: FrontApp? { didSet { if frontApp != oldValue { applyFrontApp() } } }
    public var isAccessibilityTrusted = false { didSet { if isAccessibilityTrusted != oldValue { apply() } } }
    /// Settings › Caps Lock as hyper key.
    public var hyperKeyEnabled = false { didSet { if hyperKeyEnabled != oldValue { apply() } } }

    /// While recording, inputs name themselves to `onRecord` and nothing is performed.
    public private(set) var isRecording = false
    public var onRecord: ((Trigger) -> Void)?
    /// After every fire, once all its steps ran: the binding, the app, what happened.
    public var onFired: ((TriggerBinding, FrontApp?, ActionResult) -> Void)?

    public let touch: TouchFrameSource
    public let mouse: MouseButtonSource
    public let keyboard: KeyboardEventSource
    public let hotkeys: HotkeyRegistrar
    public let performer: ActionPerformer
    public let state: SystemStateReader
    private let modifiers: ModifierReader
    private let scheduler: Scheduler
    private let clock: () -> Double

    public private(set) var dispatchLatency = LatencyStats()
    private var bindingsByID: [UUID: TriggerBinding] = [:]
    private var lastPosted: (combo: KeyCombo, time: Double)?
    /// Sequences in progress, by binding.
    private var running: [UUID: Run] = [:]

    /// How often a "wait until" step checks its condition.
    public static let waitPollInterval = 0.1

    private static let signposter = OSSignposter(subsystem: "app.slopapp.triggers", category: "input")

    public init(touch: TouchFrameSource, mouse: MouseButtonSource, keyboard: KeyboardEventSource, hotkeys: HotkeyRegistrar,
                performer: ActionPerformer, state: SystemStateReader, modifiers: ModifierReader, scheduler: Scheduler,
                clock: @escaping () -> Double) {
        self.touch = touch
        self.mouse = mouse
        self.keyboard = keyboard
        self.hotkeys = hotkeys
        self.performer = performer
        self.state = state
        self.modifiers = modifiers
        self.scheduler = scheduler
        self.clock = clock
        touch.onGesture = { [weak self] gesture in self?.receive(gesture: gesture) }
        mouse.onFire = { [weak self] id, trigger in self?.receive(mouseBinding: id, trigger: trigger) }
        hotkeys.onPress = { [weak self] combo in self?.receive(.keyCombo(combo)) }
        keyboard.onSequence = { [weak self] sequence in self?.receive(.keySequence(sequence)) }
    }

    public func update(config: Config) {
        self.config = config
        table = RoutingTable(config: config)
        bindingsByID = Dictionary(config.bindings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        apply()
    }

    public func startRecording() {
        isRecording = true
        apply()
    }

    public func stopRecording() {
        isRecording = false
        apply()
    }

    /// Whether the touch source should run.
    public var wantsTouch: Bool { isRecording || (!isPaused && table.hasGestureBindings) }
    /// Whether the mouse tap should be installed.
    public var wantsMouseTap: Bool { !isPaused && table.hasMouseBindings && isAccessibilityTrusted }
    /// Whether Caps Lock should be the hyper key right now.
    public var wantsHyperKey: Bool { hyperKeyEnabled && !isPaused && isAccessibilityTrusted }
    /// Whether the keyboard tap should be installed (sequences or the hyper key). Recording
    /// keeps the hyper key working, so a hyper combination can be recorded.
    public var wantsKeyboardTap: Bool { wantsHyperKey || (!isPaused && table.hasKeySequenceBindings && isAccessibilityTrusted) }

    /// Brings every source in line with the current state.
    public func apply() {
        touch.interests = isRecording ? .all : GestureInterests(table.gestures)
        if wantsTouch, touch.unavailableReason == nil {
            if !touch.isRunning { touch.start() }
        } else if touch.isRunning {
            touch.stop()
        }
        if wantsMouseTap {
            if !mouse.isInstalled { _ = mouse.install() }
        } else if mouse.isInstalled {
            mouse.remove()
        }
        if wantsKeyboardTap {
            if !keyboard.isInstalled { _ = keyboard.install() }
        } else if keyboard.isInstalled {
            keyboard.update(sequences: [], hyperKey: false)
            keyboard.remove()
        }
        applyFrontApp()
    }

    /// The parts that depend on the front app: hotkeys, the tap's routes, sequences.
    private func applyFrontApp() {
        let active = !isPaused && !isRecording
        let bundleID = frontApp?.bundleID
        unavailableShortcuts = hotkeys.sync(active ? table.hotkeys(frontApp: bundleID) : [])
        if mouse.isInstalled {
            mouse.update(routes: active ? table.mouseRoutes(frontApp: bundleID) : .empty)
        }
        if keyboard.isInstalled {
            keyboard.update(sequences: active ? table.keySequences(frontApp: bundleID) : [], hyperKey: wantsHyperKey)
        }
    }

    /// Accessibility went away: drop the taps now (an active tap without trust can freeze input,
    /// and the hyper key's remap must not outlive its tap).
    public func accessibilityRevoked() {
        if keyboard.isInstalled {
            keyboard.update(sequences: [], hyperKey: false)
            keyboard.remove()
        }
        if mouse.isInstalled { mouse.remove() }
        isAccessibilityTrusted = false
    }

    /// Quitting: undo everything that outlives the process (the hyper key's remap).
    public func shutDown() {
        cancelRunning()
        if keyboard.isInstalled {
            keyboard.update(sequences: [], hyperKey: false)
            keyboard.remove()
        }
        if mouse.isInstalled { mouse.remove() }
        if touch.isRunning { touch.stop() }
    }

    // MARK: Inputs

    public func receive(gesture: Gesture) {
        receive(.gesture(gesture, modifiers: modifiers.current()))
    }

    /// Any input, from any source (replays use this too).
    public func receive(_ trigger: Trigger) {
        let start = clock()
        if isRecording {
            onRecord?(trigger)
            return
        }
        guard !isPaused else { return }
        if case .keyCombo(let combo) = trigger, let posted = lastPosted, posted.combo == combo, start - posted.time < 0.3 {
            return // our own posted keys came back as a hotkey: don't loop
        }
        switch resolve(trigger) {
        case .perform(let binding):
            perform(binding, trigger: trigger, start: start)
        case .blocked:
            // A hotkey consumed the press, but nothing wanted it right now: give it to the app.
            if case .keyCombo(let combo) = trigger {
                hotkeys.suspend(combo, for: 0.15)
                performer.deliverOriginal(trigger, context: nil)
            }
        case .passThrough, .none:
            break
        }
    }

    /// A press the tap already swallowed. Its conditions are checked now; if nothing runs,
    /// the press goes to the app after all.
    public func receive(mouseBinding id: UUID, trigger: Trigger) {
        let start = clock()
        guard !isPaused, !isRecording else {
            performer.deliverOriginal(trigger, context: nil)
            return
        }
        switch resolve(trigger) {
        case .perform(let binding): perform(binding, trigger: trigger, start: start)
        case .passThrough, .blocked, .none: performer.deliverOriginal(trigger, context: nil)
        }
    }

    /// The binding to run for this input in the front app, conditions checked.
    public func resolve(_ trigger: Trigger) -> Resolution {
        let environment = ConditionEnvironment(state: state, frontBundleID: frontApp?.bundleID)
        return table.resolve(trigger, frontApp: frontApp?.bundleID) { $0.conditions.holds(in: environment) }
    }

    /// Whether a binding's conditions hold right now (the editor's live check).
    public func conditionsHold(_ conditions: ConditionSet) -> Bool {
        conditions.holds(in: ConditionEnvironment(state: state, frontBundleID: frontApp?.bundleID))
    }

    /// Runs a binding's steps once, as a test (Trigger › Run Action Now). Conditions aren't
    /// checked: the person asked for it.
    @discardableResult
    public func runNow(_ binding: TriggerBinding) -> ActionResult {
        perform(binding, trigger: binding.trigger, start: clock())
    }

    /// Whether this binding's steps are still running (a sequence with delays or waits).
    public func isRunning(_ id: UUID) -> Bool { running[id] != nil }

    // MARK: Running steps

    /// One fire of a binding, while its steps run.
    private final class Run {
        let binding: TriggerBinding
        let trigger: Trigger
        let frontAtFire: FrontApp?
        var index = 0
        var work: ScheduledWork?
        var lastSkip: String?
        var isFinished = false

        init(binding: TriggerBinding, trigger: Trigger, frontAtFire: FrontApp?) {
            self.binding = binding
            self.trigger = trigger
            self.frontAtFire = frontAtFire
        }
    }

    @discardableResult
    private func perform(_ binding: TriggerBinding, trigger: Trigger, start: Double) -> ActionResult {
        let state = Self.signposter.beginInterval("dispatch")
        defer { Self.signposter.endInterval("dispatch", state) }
        guard running[binding.id] == nil else { return .skipped("Still running from the last time.") }
        dispatchLatency.record(seconds: clock() - start)
        let run = Run(binding: binding, trigger: trigger, frontAtFire: frontApp)
        running[binding.id] = run
        return advance(run) ?? .done
    }

    /// Runs steps until one has to wait. Returns the final result if the run finished now.
    @discardableResult
    private func advance(_ run: Run) -> ActionResult? {
        let steps = run.binding.steps
        while run.index < steps.count {
            guard !run.isFinished else { return nil }
            let step = steps[run.index]
            let isFirst = run.index == 0
            run.index += 1
            switch step.kind {
            case .action(let action):
                if case .pressKeys(let combo) = action { lastPosted = (combo, clock()) }
                let trigger = isFirst ? run.trigger : run.trigger.with(modifiers: modifiers.current())
                let context = ActionContext(frontApp: frontApp, binding: run.binding, trigger: trigger)
                guard let result = performer.perform(action, context: context, finished: { [weak self, weak run] result in
                    guard let self, let run, !run.isFinished else { return }
                    if let final = self.handle(result, in: run) { self.finish(run, final) } else { self.advance(run) }
                }) else { return nil }
                if let final = handle(result, in: run) { return finish(run, final) }
            case .delay(let seconds):
                run.work = scheduler.schedule(after: seconds) { [weak self, weak run] in
                    guard let self, let run else { return }
                    self.advance(run)
                }
                return nil
            case .waitUntil(let condition, let timeout):
                if holds(condition) { continue }
                wait(run, for: condition, until: clock() + timeout)
                return nil
            }
        }
        return finish(run, run.lastSkip.map { .skipped($0) } ?? .done)
    }

    /// A step's result: nil to carry on, or the run's final result (a failure stops it).
    private func handle(_ result: ActionResult, in run: Run) -> ActionResult? {
        switch result {
        case .done: return nil
        case .skipped(let reason):
            run.lastSkip = reason
            return nil
        case .failed: return result
        }
    }

    private func wait(_ run: Run, for condition: Condition, until deadline: Double) {
        run.work = scheduler.schedule(after: Self.waitPollInterval) { [weak self, weak run] in
            guard let self, let run, !run.isFinished else { return }
            if self.holds(condition) {
                self.advance(run)
            } else if self.clock() >= deadline {
                self.finish(run, .failed("Stopped waiting: \(condition.phrase) didn't happen in time."))
            } else {
                self.wait(run, for: condition, until: deadline)
            }
        }
    }

    private func holds(_ condition: Condition) -> Bool {
        condition.holds(in: ConditionEnvironment(state: state, frontBundleID: frontApp?.bundleID))
    }

    @discardableResult
    private func finish(_ run: Run, _ result: ActionResult) -> ActionResult {
        guard !run.isFinished else { return result }
        run.isFinished = true
        run.work?.cancel()
        run.work = nil
        running[run.binding.id] = nil
        onFired?(run.binding, run.frontAtFire, result)
        return result
    }

    /// Pause stops sequences where they are.
    private func cancelRunning() {
        for run in running.values {
            run.isFinished = true
            run.work?.cancel()
        }
        running.removeAll()
    }
}

/// A small latency histogram: numbers only, never what was pressed or where.
public struct LatencyStats: Sendable, Equatable {
    /// Microsecond buckets: 0–1, 1–2, 2–5, 5–10, … up to 1 s, then everything slower.
    public static let bounds: [Double] = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1_000, 2_000, 5_000, 10_000, 20_000, 50_000, 100_000, 1_000_000]
    public private(set) var buckets = [Int](repeating: 0, count: LatencyStats.bounds.count + 1)
    public private(set) var count = 0
    public private(set) var maxMicroseconds: Double = 0
    public private(set) var totalMicroseconds: Double = 0

    public init() {}

    public mutating func record(seconds: Double) { record(microseconds: seconds * 1_000_000) }

    public mutating func record(microseconds value: Double) {
        let index = Self.bounds.firstIndex { value < $0 } ?? Self.bounds.count
        buckets[index] += 1
        count += 1
        maxMicroseconds = max(maxMicroseconds, value)
        totalMicroseconds += value
    }

    /// The bucket bound under which `fraction` of samples fall (an upper estimate).
    public func percentile(_ fraction: Double) -> Double {
        guard count > 0 else { return 0 }
        let wanted = Int((Double(count) * fraction).rounded(.up))
        var seen = 0
        for (index, bucket) in buckets.enumerated() {
            seen += bucket
            if seen >= wanted { return index < Self.bounds.count ? Self.bounds[index] : maxMicroseconds }
        }
        return maxMicroseconds
    }

    public var mean: Double { count > 0 ? totalMicroseconds / Double(count) : 0 }

    public var summary: String {
        String(format: "n=%d mean_us=%.1f p50_us<=%.0f p99_us<=%.0f max_us=%.1f", count, mean, percentile(0.5), percentile(0.99), maxMicroseconds)
    }
}
