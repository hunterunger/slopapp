import Foundation

/// Decides which pasteboard change counts are new copies worth reading: not the one we
/// started with, not a repeat, and not one Clips wrote itself (pasting from history).
public struct ChangeTracker: Sendable {
    private var lastSeen: Int
    private var ownWrites: [Int] = []

    public init(startingAt changeCount: Int) {
        lastSeen = changeCount
    }

    /// Remembers a change count produced by Clips' own write.
    public mutating func noteOwnWrite(_ changeCount: Int) {
        ownWrites.append(changeCount)
        if ownWrites.count > 20 { ownWrites.removeFirst() }
    }

    /// True when `changeCount` is a change someone else made since the last call.
    public mutating func isNewExternalChange(_ changeCount: Int) -> Bool {
        guard changeCount != lastSeen else { return false }
        lastSeen = changeCount
        return !ownWrites.contains(changeCount)
    }
}
