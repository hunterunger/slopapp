import Foundation

/// How a manual session ends.
public enum SessionKind: Hashable, Sendable {
    /// A preset or custom length; `.indefinitely` never ends on its own.
    case duration(AwakeDuration)
    /// At a clock time ("Until 5:30 PM").
    case until(Date)
    /// When this app quits.
    case whileRunning(AppRef)
}

/// An active keep-awake session the person started.
public struct AwakeSession: Equatable, Sendable {
    public let kind: SessionKind
    public let startedAt: Date
    /// When it ends on its own, or nil (indefinitely, or while an app runs). Moves with "Add 30 Minutes".
    public internal(set) var endsAt: Date?

    public init(kind: SessionKind, startedAt: Date) {
        self.kind = kind
        self.startedAt = startedAt
        switch kind {
        case .duration(let duration): endsAt = duration.seconds.map { startedAt.addingTimeInterval($0) }
        case .until(let date): endsAt = date
        case .whileRunning: endsAt = nil
        }
    }

    /// The preset this session was started from, for the menu's checkmark.
    public var duration: AwakeDuration? {
        if case .duration(let duration) = kind { return duration }
        return nil
    }

    public func remaining(at now: Date) -> TimeInterval? {
        endsAt.map { max(0, $0.timeIntervalSince(now)) }
    }

    public func isExpired(at now: Date) -> Bool {
        guard let endsAt else { return false }
        return now >= endsAt
    }
}

/// Why a trigger is keeping the Mac awake.
public enum TriggerReason: Hashable, Sendable {
    case app(AppRef)
    case powerAdapter
    case externalDisplay

    public var phrase: String {
        switch self {
        case .app(let app): "\(app.name) is running"
        case .powerAdapter: "connected to power"
        case .externalDisplay: "an external display is connected"
        }
    }
}

/// Why Awake turned itself off (shown in the menu until the next session).
public enum EndReason: Equatable, Sendable {
    case lowBattery(Int)
    case switchedToBattery
    case appQuit(String)

    public var text: String {
        switch self {
        case .lowBattery(let percent): "Turned off: battery at \(percent)%"
        case .switchedToBattery: "Turned off: switched to battery"
        case .appQuit(let name): "Turned off: \(name) quit"
        }
    }
}
