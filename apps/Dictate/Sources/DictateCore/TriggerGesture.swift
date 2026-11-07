import Foundation

/// Turns presses and releases of the trigger key into start/stop, for each `HotkeyMode`.
/// One per trigger (dictation, Command Mode). Pure, so key repeat and quick taps are tested.
public struct TriggerGesture: Sendable {
    public enum Action: Equatable, Sendable {
        case none
        case start
        case stop
    }

    /// A press shorter than this is a tap: in `holdOrTap` it keeps recording hands-free.
    public static let tapLimit: TimeInterval = 0.3

    public private(set) var isActive = false
    /// Hands-free recording started by a tap (`holdOrTap` only).
    public private(set) var isLocked = false
    private var isDown = false
    private var pressedAt: TimeInterval = 0

    public init() {}

    public mutating func press(mode: HotkeyMode, at time: TimeInterval) -> Action {
        // Key repeat sends more presses while held.
        guard !isDown else { return .none }
        isDown = true
        switch mode {
        case .pushToTalk:
            guard !isActive else { return .none }
            isActive = true
            return .start
        case .toggle:
            isActive.toggle()
            return isActive ? .start : .stop
        case .holdOrTap:
            if isActive {
                // A press while hands-free ends it.
                isActive = false
                isLocked = false
                return .stop
            }
            isActive = true
            isLocked = false
            pressedAt = time
            return .start
        }
    }

    public mutating func release(mode: HotkeyMode, at time: TimeInterval) -> Action {
        guard isDown else { return .none }
        isDown = false
        switch mode {
        case .pushToTalk:
            guard isActive else { return .none }
            isActive = false
            return .stop
        case .toggle:
            return .none
        case .holdOrTap:
            guard isActive, !isLocked else { return .none }
            if time - pressedAt < Self.tapLimit {
                isLocked = true
                return .none
            }
            isActive = false
            return .stop
        }
    }

    /// Forget any recording in progress: the dictation ended some other way (error, Esc,
    /// the menu), or the app didn't accept the start.
    public mutating func reset() {
        isActive = false
        isLocked = false
    }
}
