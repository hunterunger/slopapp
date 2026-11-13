import Foundation

/// Where a binding applies.
public enum Scope: Hashable, Codable, Sendable {
    case allApps
    /// The built-in group of web browsers.
    case browsers
    case app(bundleID: String)

    public var bundleID: String? {
        if case .app(let id) = self { return id }
        return nil
    }
}

/// One step of what a binding does: an action, a pause, or a wait for something to be true.
public struct ActionStep: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: Hashable, Codable, Sendable {
        case action(Action)
        case delay(seconds: Double)
        /// Wait until the condition holds, at most `timeout` seconds; then stop the sequence.
        case waitUntil(Condition, timeout: Double)
    }

    public var id: UUID
    public var kind: Kind

    public init(id: UUID = UUID(), _ kind: Kind) {
        self.id = id
        self.kind = kind
    }

    public static func action(_ action: Action) -> ActionStep { ActionStep(.action(action)) }
    public static func delay(_ seconds: Double) -> ActionStep { ActionStep(.delay(seconds: seconds)) }
    public static func waitUntil(_ condition: Condition, timeout: Double = ActionStep.defaultWaitTimeout) -> ActionStep {
        ActionStep(.waitUntil(condition, timeout: timeout))
    }

    public static let defaultDelay = 0.5
    public static let defaultWaitTimeout = 5.0
    public static let delayRange = 0.05...60.0
    public static let waitRange = 0.5...120.0

    public var action: Action? {
        if case .action(let action) = kind { return action }
        return nil
    }

    public var isComplete: Bool {
        switch kind {
        case .action(let action): action.isComplete
        case .delay(let seconds): ActionStep.delayRange.contains(seconds)
        case .waitUntil(let condition, let timeout): condition.isComplete && ActionStep.waitRange.contains(timeout)
        }
    }

    /// "Press ⌘[", "Wait 0.5 s", "Wait until Notes is in front".
    public func title(keys: (KeyCombo) -> String) -> String {
        switch kind {
        case .action(let action): action.title(keys: keys)
        case .delay(let seconds): "Wait \(ActionStep.seconds(seconds))"
        case .waitUntil(let condition, _): "Wait until \(condition.phrase)"
        }
    }

    /// "0.5 s", "2 s".
    public static func seconds(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded() ? "\(Int(rounded)) s" : "\(rounded.formatted(.number.precision(.fractionLength(0...2)))) s"
    }
}

/// One input mapped to what it does, in one scope: a list of steps run in order, when its
/// conditions hold.
public struct TriggerBinding: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var trigger: Trigger
    public var steps: [ActionStep]
    public var conditions: ConditionSet
    public var scope: Scope
    public var isEnabled: Bool

    public init(id: UUID = UUID(), trigger: Trigger, steps: [ActionStep], conditions: ConditionSet = .always,
                scope: Scope, isEnabled: Bool = true) {
        self.id = id
        self.trigger = trigger
        self.steps = steps
        self.conditions = conditions
        self.scope = scope
        self.isEnabled = isEnabled
    }

    /// A one-action binding (the common case).
    public init(id: UUID = UUID(), trigger: Trigger, action: Action, conditions: ConditionSet = .always,
                scope: Scope, isEnabled: Bool = true) {
        self.init(id: id, trigger: trigger, steps: [.action(action)], conditions: conditions, scope: scope, isEnabled: isEnabled)
    }

    /// Every action, in order (delays and waits left out).
    public var actions: [Action] { steps.compactMap(\.action) }

    /// The first action, for icons and one-line summaries.
    public var firstAction: Action? { actions.first }

    /// A "Do nothing here" binding: lets the app have the input.
    public var isPassThrough: Bool { steps.count == 1 && steps[0].action == .passThrough }

    /// Runs as one synchronous action (no delays, waits or follow-ups).
    public var isSingleAction: Bool { steps.count == 1 && steps[0].action != nil }

    public var isComplete: Bool {
        guard !steps.isEmpty, steps.allSatisfy(\.isComplete), conditions.isComplete else { return false }
        // "Do nothing" only makes sense on its own.
        return isPassThrough || !actions.contains(.passThrough)
    }

    public var needsAccessibility: Bool { actions.contains(where: \.needsAccessibility) || trigger.family == .mouse }

    /// The same steps, ignoring their ids (for duplicate checks).
    public var stepKinds: [ActionStep.Kind] { steps.map(\.kind) }

    /// "Press ⌘[", or "Open Notes → Wait 1 s → Press ⌘N".
    public func summary(keys: (KeyCombo) -> String) -> String {
        if steps.isEmpty { return "Nothing" }
        return steps.map { $0.title(keys: keys) }.joined(separator: " → ")
    }

    public var fallbackSummary: String { summary(keys: { $0.fallbackDisplay }) }

    private enum CodingKeys: String, CodingKey { case id, trigger, steps, conditions, scope, isEnabled, action }

    /// Files from 0.1 have one `action`; it becomes the only step.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        trigger = try container.decode(Trigger.self, forKey: .trigger)
        if let steps = try container.decodeIfPresent([ActionStep].self, forKey: .steps) {
            self.steps = steps
        } else {
            steps = [.action(try container.decode(Action.self, forKey: .action))]
        }
        conditions = try container.decodeIfPresent(ConditionSet.self, forKey: .conditions) ?? .always
        scope = try container.decode(Scope.self, forKey: .scope)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(trigger, forKey: .trigger)
        try container.encode(steps, forKey: .steps)
        if !conditions.isEmpty { try container.encode(conditions, forKey: .conditions) }
        try container.encode(scope, forKey: .scope)
        try container.encode(isEnabled, forKey: .isEnabled)
    }
}

/// An app in the editor's sidebar.
public struct AppEntry: Identifiable, Hashable, Codable, Sendable {
    public var bundleID: String
    public var name: String
    /// "Use all-apps triggers here". Off for games, remote desktops and VMs.
    public var usesAllAppsTriggers: Bool

    public var id: String { bundleID }

    public init(bundleID: String, name: String, usesAllAppsTriggers: Bool = true) {
        self.bundleID = bundleID
        self.name = name
        self.usesAllAppsTriggers = usesAllAppsTriggers
    }
}

/// Everything Triggers stores. Plain JSON with a schema version.
public struct Config: Hashable, Codable, Sendable {
    /// 1: one action per binding (0.1). 2: steps and conditions; key sequences, more gestures
    /// and actions. Version 1 files load unchanged (each action becomes a one-step list).
    public static let currentSchema = 2

    public var schemaVersion: Int
    public var bindings: [TriggerBinding]
    public var apps: [AppEntry]

    public init(bindings: [TriggerBinding] = [], apps: [AppEntry] = []) {
        self.schemaVersion = Config.currentSchema
        self.bindings = bindings
        self.apps = apps
    }

    public func app(_ bundleID: String) -> AppEntry? { apps.first { $0.bundleID == bundleID } }

    /// Adds the app to the sidebar if it isn't there yet.
    public mutating func addApp(bundleID: String, name: String) {
        guard app(bundleID) == nil else { return }
        apps.append(AppEntry(bundleID: bundleID, name: name))
        apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Whether all-apps (and Browsers) bindings apply in this app.
    public func usesAllAppsTriggers(in bundleID: String?) -> Bool {
        guard let bundleID else { return true }
        return app(bundleID)?.usesAllAppsTriggers ?? true
    }

    public mutating func setUsesAllAppsTriggers(_ value: Bool, in bundleID: String, name: String) {
        if let index = apps.firstIndex(where: { $0.bundleID == bundleID }) {
            apps[index].usesAllAppsTriggers = value
        } else {
            addApp(bundleID: bundleID, name: name)
            setUsesAllAppsTriggers(value, in: bundleID, name: name)
        }
    }

    public func bindings(in scope: Scope) -> [TriggerBinding] { bindings.filter { $0.scope == scope } }

    public var enabledBindings: [TriggerBinding] { bindings.filter(\.isEnabled) }
}

/// The built-in Browsers group.
public enum BrowserGroup {
    public static let bundleIDs: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
        "company.thebrowser.Browser", "company.thebrowser.dia",
        "com.microsoft.edgemac", "com.brave.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
        "com.kagi.kagimacOS", "app.zen-browser.zen", "com.duckduckgo.macos.browser",
        "org.chromium.Chromium", "com.openai.atlas", "net.imput.helium",
    ]

    public static func contains(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleIDs.contains(bundleID)
    }
}
