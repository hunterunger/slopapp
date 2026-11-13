import Foundation

/// What to do with an input in the front app.
public enum Resolution: Equatable, Sendable {
    /// Run this binding's steps (and swallow the input where we can).
    case perform(TriggerBinding)
    /// A "Do nothing" binding matched: let the app have the input untouched.
    case passThrough(TriggerBinding)
    /// Triggers exist for this input here, but none of their conditions hold right now.
    case blocked
    /// Nothing bound here.
    case none

    public var binding: TriggerBinding? {
        switch self {
        case .perform(let binding), .passThrough(let binding): binding
        case .blocked, .none: nil
        }
    }
}

/// An immutable lookup built from the config. Lookups are dictionary reads, so hundreds of
/// bindings cost the same as one. Precedence: the app's own bindings, then the Browsers group
/// (for browsers), then All Apps (unless the app turned all-apps triggers off). Within a place,
/// bindings for the same input are tried in order; the first whose conditions hold wins.
public struct RoutingTable: Sendable {
    private let allApps: [Trigger: [TriggerBinding]]
    private let browsers: [Trigger: [TriggerBinding]]
    private let apps: [String: [Trigger: [TriggerBinding]]]
    private let allAppsOff: Set<String>
    /// Any enabled binding of each family, anywhere.
    public let hasGestureBindings: Bool
    public let hasMouseBindings: Bool
    public let hasKeyBindings: Bool
    public let hasKeySequenceBindings: Bool
    /// Every gesture that does something somewhere (the recognizer only looks for these).
    public let gestures: Set<Gesture>

    public init(config: Config) {
        var allApps: [Trigger: [TriggerBinding]] = [:]
        var browsers: [Trigger: [TriggerBinding]] = [:]
        var apps: [String: [Trigger: [TriggerBinding]]] = [:]
        for binding in config.bindings where binding.isEnabled && binding.isComplete {
            switch binding.scope {
            case .allApps: allApps[binding.trigger, default: []].append(binding)
            case .browsers: browsers[binding.trigger, default: []].append(binding)
            case .app(let id): apps[id, default: [:]][binding.trigger, default: []].append(binding)
            }
        }
        self.allApps = allApps
        self.browsers = browsers
        self.apps = apps
        self.allAppsOff = Set(config.apps.filter { !$0.usesAllAppsTriggers }.map(\.bundleID))
        let enabled = config.bindings.filter { $0.isEnabled && $0.isComplete && !$0.isPassThrough }
        hasGestureBindings = enabled.contains { $0.trigger.family == .trackpad }
        hasMouseBindings = enabled.contains { $0.trigger.family == .mouse }
        hasKeyBindings = enabled.contains { if case .keyCombo = $0.trigger { return true }; return false }
        hasKeySequenceBindings = enabled.contains { if case .keySequence = $0.trigger { return true }; return false }
        gestures = Set(enabled.compactMap { binding in
            if case .gesture(let gesture, _) = binding.trigger { return gesture }
            return nil
        })
    }

    /// The bindings that could answer this input in this app, best first.
    public func candidates(_ trigger: Trigger, frontApp bundleID: String?) -> [TriggerBinding] {
        var result: [TriggerBinding] = []
        if let bundleID, let own = apps[bundleID]?[trigger] { result += own }
        if BrowserGroup.contains(bundleID), let group = browsers[trigger] { result += group }
        if bundleID.map({ !allAppsOff.contains($0) }) ?? true, let all = allApps[trigger] { result += all }
        return result
    }

    /// The binding to run. `conditionsHold` is asked only about bindings that have conditions.
    public func resolve(_ trigger: Trigger, frontApp bundleID: String?,
                        conditionsHold: (TriggerBinding) -> Bool = { _ in true }) -> Resolution {
        var blocked = false
        for binding in candidates(trigger, frontApp: bundleID) {
            if binding.conditions.isEmpty || conditionsHold(binding) {
                return binding.isPassThrough ? .passThrough(binding) : .perform(binding)
            }
            blocked = true
        }
        return blocked ? .blocked : .none
    }

    /// Every input that might do something in this app, with the first binding that could run.
    /// An unconditional "Do nothing" hides what's below it; one with conditions doesn't.
    public func effective(frontApp bundleID: String?) -> [Trigger: TriggerBinding] {
        var triggers = Set(allApps.keys)
        triggers.formUnion(browsers.keys)
        if let bundleID, let own = apps[bundleID] { triggers.formUnion(own.keys) }
        var result: [Trigger: TriggerBinding] = [:]
        for trigger in triggers {
            for binding in candidates(trigger, frontApp: bundleID) {
                if !binding.isPassThrough {
                    result[trigger] = binding
                    break
                }
                if binding.conditions.isEmpty { break }
            }
        }
        return result
    }

    /// The key combos to register as hotkeys while this app is in front.
    public func hotkeys(frontApp bundleID: String?) -> Set<KeyCombo> {
        Set(effective(frontApp: bundleID).keys.compactMap { trigger in
            if case .keyCombo(let combo) = trigger { return combo }
            return nil
        })
    }

    /// The key sequences to watch for while this app is in front.
    public func keySequences(frontApp bundleID: String?) -> [KeySequence] {
        effective(frontApp: bundleID).keys.compactMap { trigger in
            if case .keySequence(let sequence) = trigger { return sequence }
            return nil
        }
    }

    /// The mouse buttons to swallow while this app is in front.
    public func mouseRoutes(frontApp bundleID: String?) -> MouseRoutes {
        var routes: [Int: UUID] = [:]
        for (trigger, binding) in effective(frontApp: bundleID) {
            if case .mouseButton(let button, let modifiers) = trigger {
                routes[MouseRoutes.key(button: button, modifiers: modifiers)] = binding.id
            }
        }
        return MouseRoutes(routes)
    }
}

/// The event tap's view of the bindings: which (button, modifiers) to swallow in the front
/// app. A value type swapped as a whole when the front app or the bindings change.
public struct MouseRoutes: Sendable, Equatable {
    private let routes: [Int: UUID]

    public init(_ routes: [Int: UUID] = [:]) { self.routes = routes }

    public static let empty = MouseRoutes()

    public static func key(button: Int, modifiers: Modifiers) -> Int { button << 4 | modifiers.rawValue }

    public func binding(button: Int, modifiers: Modifiers) -> UUID? {
        routes[MouseRoutes.key(button: button, modifiers: modifiers)]
    }

    public var isEmpty: Bool { routes.isEmpty }
    public var count: Int { routes.count }
}
