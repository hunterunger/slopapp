import Foundation

/// When a trigger may run, beyond "which app": checked the moment the input happens. If a
/// trigger's conditions don't hold, it's as if it weren't there: the next trigger for the same
/// input runs (the app's own, then Browsers, then All Apps), or the input goes to the app.
public enum Condition: Hashable, Codable, Sendable {
    case appRunning(bundleID: String, name: String, running: Bool)
    case frontApp(bundleID: String, name: String, isFront: Bool)
    case network(NetworkCondition)
    case display(DisplayCondition)
    case power(PowerCondition)
    /// Minutes after midnight, `from` up to (not including) `to`. Wraps past midnight when
    /// `from` is later than `to` (22:00–06:00).
    case time(from: Int, to: Int)
    /// Calendar weekdays, 1 = Sunday … 7 = Saturday.
    case days([Int])
    /// These modifier keys are held (others may be too).
    case modifiersHeld(Modifiers)
    case appearance(dark: Bool)

    public enum NetworkCondition: String, Hashable, Codable, Sendable, CaseIterable {
        case online, offline, wifi, wired

        public var title: String {
            switch self {
            case .online: "Connected to a network"
            case .offline: "Not connected to a network"
            case .wifi: "Connected over Wi-Fi"
            case .wired: "Connected over Ethernet"
            }
        }
    }

    public enum DisplayCondition: Hashable, Codable, Sendable {
        case externalConnected
        case noExternal
        /// A display with this name (`NSScreen.localizedName`) is connected.
        case named(String)
    }

    public enum PowerCondition: String, Hashable, Codable, Sendable, CaseIterable {
        case charger, battery

        public var title: String { self == .charger ? "On power adapter" : "On battery" }
    }

    /// Kinds, for the Add Condition menu.
    public enum Kind: String, CaseIterable, Sendable {
        case appRunning, frontApp, network, display, power, time, days, modifiersHeld, appearance

        public var title: String {
            switch self {
            case .appRunning: "App Is Running"
            case .frontApp: "App Is in Front"
            case .network: "Network"
            case .display: "Display"
            case .power: "Power Source"
            case .time: "Time of Day"
            case .days: "Day of the Week"
            case .modifiersHeld: "Modifier Keys Held"
            case .appearance: "Dark Mode"
            }
        }

        /// A starting condition of this kind.
        public var defaultCondition: Condition {
            switch self {
            case .appRunning: .appRunning(bundleID: "", name: "", running: true)
            case .frontApp: .frontApp(bundleID: "", name: "", isFront: true)
            case .network: .network(.online)
            case .display: .display(.externalConnected)
            case .power: .power(.charger)
            case .time: .time(from: 9 * 60, to: 17 * 60)
            case .days: .days([2, 3, 4, 5, 6])
            case .modifiersHeld: .modifiersHeld(.option)
            case .appearance: .appearance(dark: true)
            }
        }
    }

    public var kind: Kind {
        switch self {
        case .appRunning: .appRunning
        case .frontApp: .frontApp
        case .network: .network
        case .display: .display
        case .power: .power
        case .time: .time
        case .days: .days
        case .modifiersHeld: .modifiersHeld
        case .appearance: .appearance
        }
    }

    /// Filled in enough to check.
    public var isComplete: Bool {
        switch self {
        case .appRunning(let id, _, _), .frontApp(let id, _, _): !id.isEmpty
        case .display(.named(let name)): !name.isEmpty
        case .time(let from, let to): (0..<1440).contains(from) && (0..<1440).contains(to)
        case .days(let days): !days.isEmpty && days.allSatisfy { (1...7).contains($0) }
        case .modifiersHeld(let modifiers): !modifiers.isEmpty
        default: true
        }
    }

    @MainActor
    public func holds(in environment: ConditionEnvironment) -> Bool {
        let state = environment.state
        switch self {
        case .appRunning(let id, _, let running):
            return state.isRunning(bundleID: id) == running
        case .frontApp(let id, _, let isFront):
            return (environment.frontBundleID == id) == isFront
        case .network(let wanted):
            let network = state.network
            switch wanted {
            case .online: return network.isOnline
            case .offline: return !network.isOnline
            case .wifi: return network.isOnline && network.usesWiFi
            case .wired: return network.isOnline && network.usesWired
            }
        case .display(let wanted):
            let displays = state.displays
            switch wanted {
            case .externalConnected: return displays.contains { !$0.isBuiltIn }
            case .noExternal: return !displays.contains { !$0.isBuiltIn }
            case .named(let name): return displays.contains { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
            }
        case .power(let wanted):
            switch (wanted, state.power) {
            case (.charger, .charger), (.battery, .battery): return true
            default: return false
            }
        case .time(let from, let to):
            let parts = state.calendar.dateComponents([.hour, .minute], from: state.now)
            let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            return Condition.minute(minute, isIn: from, to)
        case .days(let days):
            return days.contains(state.calendar.component(.weekday, from: state.now))
        case .modifiersHeld(let modifiers):
            return state.modifiers.isSuperset(of: modifiers)
        case .appearance(let dark):
            return state.isDarkMode == dark
        }
    }

    static func minute(_ minute: Int, isIn from: Int, _ to: Int) -> Bool {
        if from == to { return true }
        return from < to ? (minute >= from && minute < to) : (minute >= from || minute < to)
    }

    /// "Notes is running", "On battery", "9:00–17:00".
    public var title: String {
        switch self {
        case .appRunning(_, let name, let running):
            return "\(name.isEmpty ? "An app" : name) is \(running ? "" : "not ")running"
        case .frontApp(_, let name, let isFront):
            return "\(name.isEmpty ? "An app" : name) is \(isFront ? "" : "not ")in front"
        case .network(let network): return network.title
        case .display(.externalConnected): return "An external display is connected"
        case .display(.noExternal): return "No external display is connected"
        case .display(.named(let name)): return "\(name.isEmpty ? "A display" : name) is connected"
        case .power(let power): return power.title
        case .time(let from, let to): return "Between \(Condition.clock(from)) and \(Condition.clock(to))"
        case .days(let days): return Condition.daysTitle(days)
        case .modifiersHeld(let modifiers): return "Holding \(modifiers.symbols)"
        case .appearance(let dark): return dark ? "Dark mode is on" : "Dark mode is off"
        }
    }

    /// The title as a phrase inside a sentence ("Wait until on battery"); app names keep
    /// their capitals.
    public var phrase: String {
        switch self {
        case .appRunning, .frontApp, .display(.named): return title
        default: return title.prefix(1).lowercased() + title.dropFirst()
        }
    }

    /// "9:05", "17:30" (24-hour, as minutes are stored; the editor uses the system's format).
    public static func clock(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    public static let weekdaySymbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    static func daysTitle(_ days: [Int]) -> String {
        let set = Set(days)
        if set == [2, 3, 4, 5, 6] { return "On weekdays" }
        if set == [1, 7] { return "At the weekend" }
        if set.count == 7 { return "Every day" }
        let names = (1...7).filter(set.contains).map { weekdaySymbols[$0 - 1] }
        return "On " + names.joined(separator: ", ")
    }
}

/// A trigger's conditions: all of them, or any one.
public struct ConditionSet: Hashable, Codable, Sendable {
    public enum Match: String, Hashable, Codable, Sendable { case all, any }

    public var match: Match
    public var conditions: [Condition]

    public init(match: Match = .all, _ conditions: [Condition] = []) {
        self.match = match
        self.conditions = conditions
    }

    public static let always = ConditionSet()

    public var isEmpty: Bool { conditions.isEmpty }

    public var isComplete: Bool { conditions.allSatisfy(\.isComplete) }

    @MainActor
    public func holds(in environment: ConditionEnvironment) -> Bool {
        guard !conditions.isEmpty else { return true }
        switch match {
        case .all: return conditions.allSatisfy { $0.holds(in: environment) }
        case .any: return conditions.contains { $0.holds(in: environment) }
        }
    }

    /// "On battery and Notes is running".
    public var summary: String {
        let titles = conditions.map(\.title)
        guard titles.count > 1 else { return titles.first ?? "" }
        let joiner = match == .all ? " and " : " or "
        return titles.dropLast().joined(separator: ", ") + joiner + titles.last!
    }
}

// MARK: - What conditions read (faked in tests)

public struct NetworkState: Equatable, Sendable {
    public var isOnline: Bool
    public var usesWiFi: Bool
    public var usesWired: Bool

    public init(isOnline: Bool, usesWiFi: Bool = false, usesWired: Bool = false) {
        self.isOnline = isOnline
        self.usesWiFi = usesWiFi
        self.usesWired = usesWired
    }
}

public struct DisplayInfo: Equatable, Sendable {
    public var name: String
    public var isBuiltIn: Bool

    public init(name: String, isBuiltIn: Bool) {
        self.name = name
        self.isBuiltIn = isBuiltIn
    }
}

public enum PowerSourceKind: Equatable, Sendable { case charger, battery, unknown }

/// The Mac's state, for conditions. Read only when a trigger with conditions fires (or a
/// sequence waits), never in the input path.
@MainActor
public protocol SystemStateReader: AnyObject {
    func isRunning(bundleID: String) -> Bool
    var network: NetworkState { get }
    var displays: [DisplayInfo] { get }
    var power: PowerSourceKind { get }
    var now: Date { get }
    var calendar: Calendar { get }
    var modifiers: Modifiers { get }
    var isDarkMode: Bool { get }
}

/// What a condition is checked against: the Mac's state and the app in front.
@MainActor
public struct ConditionEnvironment {
    public let state: SystemStateReader
    public let frontBundleID: String?

    public init(state: SystemStateReader, frontBundleID: String?) {
        self.state = state
        self.frontBundleID = frontBundleID
    }
}
