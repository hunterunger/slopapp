import CoreGraphics
import Foundation

/// The mouse event tap's whole decision, kept free of system calls so tests can drive it with
/// constructed `CGEvent`s (nothing is posted). Runs on the tap's thread: constant time, no
/// allocation, no Accessibility or workspace calls.
public struct MouseTapDecider: Sendable {
    public enum Decision: Equatable, Sendable {
        /// Let the event through untouched.
        case pass
        /// Drop it (the up or drag of a press we swallowed).
        case swallow
        /// Drop it and run this binding.
        case swallowAndFire(UUID)
    }

    /// Marks events Triggers posts itself (its own middle clicks), so the tap never acts on them.
    public static let ownEventMarker: Int64 = 0x5452_4753 // "TRGS"

    /// Buttons whose down we swallowed: their up and drags are swallowed too, even if the front
    /// app changed in between, so no app sees a stray up.
    private var swallowedButtons: UInt64 = 0

    public init() {}

    public enum Phase: Sendable { case down, dragged, up }

    public mutating func decide(phase: Phase, button: Int, modifiers: Modifiers, routes: MouseRoutes, isOwnEvent: Bool) -> Decision {
        guard !isOwnEvent, (0..<64).contains(button) else { return .pass }
        let bit: UInt64 = 1 << UInt64(button)
        switch phase {
        case .down:
            if let id = routes.binding(button: button, modifiers: modifiers) {
                swallowedButtons |= bit
                return .swallowAndFire(id)
            }
            // A fresh down for a button that's no longer bound clears any stale state.
            swallowedButtons &= ~bit
            return .pass
        case .dragged:
            return swallowedButtons & bit != 0 ? .swallow : .pass
        case .up:
            if swallowedButtons & bit != 0 {
                swallowedButtons &= ~bit
                return .swallow
            }
            return .pass
        }
    }

    /// Forget held buttons (tap re-created, Mac woke).
    public mutating func reset() { swallowedButtons = 0 }

    /// Decides for a real event. Unknown event types pass.
    public mutating func decide(_ event: CGEvent, routes: MouseRoutes) -> Decision {
        let phase: Phase
        switch event.type {
        case .otherMouseDown: phase = .down
        case .otherMouseDragged: phase = .dragged
        case .otherMouseUp: phase = .up
        default: return .pass
        }
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let isOwn = event.getIntegerValueField(.eventSourceUserData) == Self.ownEventMarker
        return decide(phase: phase, button: button, modifiers: Modifiers(cgFlags: event.flags.rawValue),
                      routes: routes, isOwnEvent: isOwn)
    }

    /// The only events the tap asks for: other-mouse down, up and dragged (buttons 3 and up in
    /// CoreGraphics' numbering 2+). Never left/right clicks, moves, scrolls or keys.
    public static let eventMask: CGEventMask =
        (1 << CGEventType.otherMouseDown.rawValue)
        | (1 << CGEventType.otherMouseUp.rawValue)
        | (1 << CGEventType.otherMouseDragged.rawValue)

    /// Whether a tap mask (from `CGGetEventTapList`) asks for anything beyond other-mouse events.
    public static func maskIsMinimal(_ mask: CGEventMask) -> Bool { mask & ~eventMask == 0 }
}
