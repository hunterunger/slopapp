import Foundation
@testable import TriggersCore

@MainActor
final class FakeTouchSource: TouchFrameSource {
    var unavailableReason: String?
    var onGesture: ((Gesture) -> Void)?
    var onFingers: ((Int) -> Void)?
    var reportsFingers = false
    var tuning = GestureTuning()
    private(set) var isRunning = false
    private(set) var starts = 0

    func start() { isRunning = true; starts += 1 }
    func stop() { isRunning = false }

    /// Feeds frames through a real recognizer, like the real source does.
    var recognizer = GestureRecognizer()
    func feed(_ frames: [TouchFrame], device: Int = 1) {
        guard isRunning else { return }
        for frame in frames {
            if let gesture = recognizer.process(device: device, timestamp: frame.timestamp, contacts: frame.touches).gesture {
                onGesture?(gesture)
            }
        }
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
}

@MainActor
final class RecordingPerformer: ActionPerformer {
    struct Call: Equatable { var action: Action; var app: String?; var trigger: Trigger }
    private(set) var calls: [Call] = []
    var result: ActionResult = .done

    func perform(_ action: Action, context: ActionContext) -> ActionResult {
        calls.append(Call(action: action, app: context.frontApp?.bundleID, trigger: context.trigger))
        return result
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
    let hotkeys = FakeHotkeys()
    let performer = RecordingPerformer()
    let clock = ManualClock()
    let engine: TriggerEngine

    init(modifiers: Modifiers = []) {
        let clock = self.clock
        engine = TriggerEngine(touch: touch, mouse: mouse, hotkeys: hotkeys, performer: performer,
                               modifiers: FixedModifiers(value: modifiers), clock: { clock.now })
        engine.isAccessibilityTrusted = true
    }
}

let safari = FrontApp(bundleID: "com.apple.Safari", name: "Safari", pid: 10)
let notes = FrontApp(bundleID: "com.apple.Notes", name: "Notes", pid: 11)
let game = FrontApp(bundleID: "com.example.game", name: "Game", pid: 12)
let cmdLeftBracket = KeyCombo(keyCode: KeyNames.leftBracket, modifiers: .command)
let ctrlOptK = KeyCombo(keyCode: 40, modifiers: [.control, .option])
