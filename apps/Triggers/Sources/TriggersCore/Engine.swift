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

/// What happened when an action ran.
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
    /// The input as it happened (modifiers the person is still holding).
    public var trigger: Trigger
}

// MARK: - System boundaries (faked in tests)

/// Runs actions: posts keys and clicks, chooses menu items, moves windows, opens things, runs
/// Shortcuts. The only production type that posts events.
@MainActor
public protocol ActionPerformer: AnyObject {
    func perform(_ action: Action, context: ActionContext) -> ActionResult
}

/// Carbon hotkeys for key-combo triggers.
@MainActor
public protocol HotkeyRegistrar: AnyObject {
    var onPress: ((KeyCombo) -> Void)? { get set }
    /// Registers exactly these combos, unregistering the rest. Returns the ones another app holds.
    func sync(_ combos: Set<KeyCombo>) -> Set<KeyCombo>
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
    var isRunning: Bool { get }
    func start()
    func stop()
}

/// The modifier keys held right now (for gestures, which carry none of their own).
public protocol ModifierReader: Sendable {
    func current() -> Modifiers
}

// MARK: - Engine

/// Routes every input to its action. Owns no system resources itself: it tells the sources
/// when to run (touch source only with gesture bindings, the tap only with mouse bindings and
/// Accessibility, hotkeys only for the front app) and asks the performer to act.
@MainActor
public final class TriggerEngine {
    public private(set) var config = Config()
    public private(set) var table = RoutingTable(config: Config())
    public private(set) var unavailableShortcuts: Set<KeyCombo> = []

    public var isPaused = false { didSet { if isPaused != oldValue { apply() } } }
    public var frontApp: FrontApp? { didSet { if frontApp != oldValue { applyFrontApp() } } }
    public var isAccessibilityTrusted = false { didSet { if isAccessibilityTrusted != oldValue { apply() } } }

    /// While recording, inputs name themselves to `onRecord` and nothing is performed.
    public private(set) var isRecording = false
    public var onRecord: ((Trigger) -> Void)?
    /// After every fire: the binding, the app, what happened.
    public var onFired: ((TriggerBinding, FrontApp?, ActionResult) -> Void)?

    public let touch: TouchFrameSource
    public let mouse: MouseButtonSource
    public let hotkeys: HotkeyRegistrar
    public let performer: ActionPerformer
    private let modifiers: ModifierReader
    private let clock: () -> Double

    public private(set) var dispatchLatency = LatencyStats()
    private var bindingsByID: [UUID: TriggerBinding] = [:]
    private var lastPosted: (combo: KeyCombo, time: Double)?

    private static let signposter = OSSignposter(subsystem: "app.slopapp.triggers", category: "input")

    public init(touch: TouchFrameSource, mouse: MouseButtonSource, hotkeys: HotkeyRegistrar, performer: ActionPerformer,
                modifiers: ModifierReader, clock: @escaping () -> Double) {
        self.touch = touch
        self.mouse = mouse
        self.hotkeys = hotkeys
        self.performer = performer
        self.modifiers = modifiers
        self.clock = clock
        touch.onGesture = { [weak self] gesture in self?.receive(gesture: gesture) }
        mouse.onFire = { [weak self] id, trigger in self?.receive(mouseBinding: id, trigger: trigger) }
        hotkeys.onPress = { [weak self] combo in self?.receive(.keyCombo(combo)) }
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

    /// Brings every source in line with the current state.
    public func apply() {
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
        applyFrontApp()
    }

    /// The parts that depend on the front app: hotkeys and the tap's routes.
    private func applyFrontApp() {
        let active = !isPaused && !isRecording
        unavailableShortcuts = hotkeys.sync(active ? table.hotkeys(frontApp: frontApp?.bundleID) : [])
        if mouse.isInstalled {
            mouse.update(routes: active ? table.mouseRoutes(frontApp: frontApp?.bundleID) : .empty)
        }
    }

    /// Accessibility went away: drop the tap now (an active tap without trust can freeze input).
    public func accessibilityRevoked() {
        if mouse.isInstalled { mouse.remove() }
        isAccessibilityTrusted = false
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
        switch table.resolve(trigger, frontApp: frontApp?.bundleID) {
        case .perform(let binding): perform(binding, trigger: trigger, start: start)
        case .passThrough, .none: break
        }
    }

    /// A press the tap already swallowed for this binding.
    public func receive(mouseBinding id: UUID, trigger: Trigger) {
        let start = clock()
        guard !isPaused, !isRecording, let binding = bindingsByID[id] else { return }
        perform(binding, trigger: trigger, start: start)
    }

    /// Runs a binding's action once, as a test (Trigger › Run Action Now).
    @discardableResult
    public func runNow(_ binding: TriggerBinding) -> ActionResult {
        perform(binding, trigger: binding.trigger, start: clock())
    }

    @discardableResult
    private func perform(_ binding: TriggerBinding, trigger: Trigger, start: Double) -> ActionResult {
        let state = Self.signposter.beginInterval("dispatch")
        if case .pressKeys(let combo) = binding.action { lastPosted = (combo, start) }
        dispatchLatency.record(seconds: clock() - start)
        let result = performer.perform(binding.action, context: ActionContext(frontApp: frontApp, binding: binding, trigger: trigger))
        Self.signposter.endInterval("dispatch", state)
        onFired?(binding, frontApp, result)
        return result
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
