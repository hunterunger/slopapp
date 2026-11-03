import Foundation

/// When to check the feed in the background: at most once every `interval` (6 hours).
public struct UpdateSchedule: Sendable, Equatable {
    public static let defaultInterval: TimeInterval = 6 * 60 * 60

    public var interval: TimeInterval

    public init(interval: TimeInterval = UpdateSchedule.defaultInterval) {
        self.interval = interval
    }

    public func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        // A clock moved backwards counts as due, so a bad timestamp can't stop checks forever.
        if lastCheck > now { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    /// Seconds until the next check is due (0 if due now).
    public func delay(lastCheck: Date?, now: Date) -> TimeInterval {
        guard let lastCheck, !isDue(lastCheck: lastCheck, now: now) else { return 0 }
        return interval - now.timeIntervalSince(lastCheck)
    }
}
