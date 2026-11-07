import Foundation

/// What to do with an input in the front app.
public enum Resolution: Equatable, Sendable {
    /// Run this binding's action (and swallow the input where we can).
    case perform(TriggerBinding)
    /// A "Do nothing" binding matched: let the app have the input untouched.
    case passThrough(TriggerBinding)
    /// Nothing bound here.
    case none

    public var binding: TriggerBinding? {
        switch self {
        case .perform(let binding), .passThrough(let binding): binding
        case .none: nil
        }
    }
}

/// An immutable lookup built from the config. Lookups are dictionary reads, so hundreds of
/// bindings cost the same as one. Precedence: the app's own binding, then the Browsers group
/// (for browsers), then All Apps (unless the app turned all-apps triggers off).
public struct RoutingTable: Sendable {
    private let allApps: [Trigger: TriggerBinding]
    private let browsers: [Trigger: TriggerBinding]
    private let apps: [String: [Trigger: TriggerBinding]]
    private let allAppsOff: Set<String>
    /// Any enabled binding of each family, anywhere.
    public let hasGestureBindings: Bool
    public let hasMouseBindings: Bool
    public let hasKeyBindings: Bool

    public init(config: Config) {
        var allApps: [Trigger: TriggerBinding] = [:]
        var browsers: [Trigger: TriggerBinding] = [:]
        var apps: [String: [Trigger: TriggerBinding]] = [:]
        // The first enabled binding for an input in a scope wins; the editor flags the rest.
        for binding in config.bindings where binding.isEnabled && binding.action.isComplete {
            switch binding.scope {
            case .allApps: if allApps[binding.trigger] == nil { allApps[binding.trigger] = binding }
            case .browsers: if browsers[binding.trigger] == nil { browsers[binding.trigger] = binding }
            case .app(let id): if apps[id, default: [:]][binding.trigger] == nil { apps[id, default: [:]][binding.trigger] = binding }
            }
        }
        self.allApps = allApps
        self.browsers = browsers
        self.apps = apps
        self.allAppsOff = Set(config.apps.filter { !$0.usesAllAppsTriggers }.map(\.bundleID))
        let enabled = config.bindings.filter { $0.isEnabled && $0.action.isComplete && $0.action != .passThrough }
        hasGestureBindings = enabled.contains { $0.trigger.family == .trackpad }
        hasMouseBindings = enabled.contains { $0.trigger.family == .mouse }
        hasKeyBindings = enabled.contains { $0.trigger.family == .keyboard }
    }

    public func resolve(_ trigger: Trigger, frontApp bundleID: String?) -> Resolution {
        if let bundleID, let binding = apps[bundleID]?[trigger] { return wrap(binding) }
        if BrowserGroup.contains(bundleID), let binding = browsers[trigger] { return wrap(binding) }
        if let bundleID, allAppsOff.contains(bundleID) { return .none }
        if let binding = allApps[trigger] { return wrap(binding) }
        return .none
    }

    private func wrap(_ binding: TriggerBinding) -> Resolution {
        binding.action == .passThrough ? .passThrough(binding) : .perform(binding)
    }

    /// Every input that does something in this app (pass-throughs left out), with its binding.
    public func effective(frontApp bundleID: String?) -> [Trigger: TriggerBinding] {
        var result: [Trigger: TriggerBinding] = [:]
        let allowsAllApps = bundleID.map { !allAppsOff.contains($0) } ?? true
        if allowsAllApps { result.merge(allApps) { _, new in new } }
        if BrowserGroup.contains(bundleID) { result.merge(browsers) { _, new in new } }
        if let bundleID, let own = apps[bundleID] { result.merge(own) { _, new in new } }
        return result.filter { $0.value.action != .passThrough }
    }

    /// The key combos to register as hotkeys while this app is in front.
    public func hotkeys(frontApp bundleID: String?) -> Set<KeyCombo> {
        Set(effective(frontApp: bundleID).keys.compactMap { trigger in
            if case .keyCombo(let combo) = trigger { return combo }
            return nil
        })
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
