import Foundation
import Observation

/// An active keep-awake session.
public struct AwakeSession: Equatable, Sendable {
    public let duration: AwakeDuration
    public let startedAt: Date

    public init(duration: AwakeDuration, startedAt: Date) {
        self.duration = duration
        self.startedAt = startedAt
    }

    public var endsAt: Date? { duration.seconds.map { startedAt.addingTimeInterval($0) } }

    public func remaining(at now: Date) -> TimeInterval? {
        endsAt.map { max(0, $0.timeIntervalSince(now)) }
    }

    public func isExpired(at now: Date) -> Bool {
        guard let endsAt else { return false }
        return now >= endsAt
    }
}

/// The whole app's state: is the Mac being kept awake, until when, and with the display on?
@MainActor
@Observable
public final class AwakeController {
    /// How often the remaining-time text refreshes while a timed session runs.
    public static let refreshInterval: TimeInterval = 30
    static let keepDisplayOnKey = "keepDisplayOn"
    static let reason = "Awake is keeping this Mac awake"

    public private(set) var session: AwakeSession?
    public private(set) var lastError: String?
    /// Updated on every tick so views showing remaining time re-render.
    public private(set) var now: Date

    public var keepDisplayOn: Bool {
        didSet {
            defaults.set(keepDisplayOn, forKey: Self.keepDisplayOnKey)
            if session != nil { acquire() }
        }
    }

    public var isActive: Bool { session != nil }

    @ObservationIgnored private let assertion: any PowerAssertion
    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var pendingTick: (any Cancellable)?

    public init(
        assertion: any PowerAssertion,
        scheduler: any Scheduler,
        defaults: UserDefaults = .standard,
        clock: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.assertion = assertion
        self.scheduler = scheduler
        self.defaults = defaults
        self.clock = clock
        self.now = clock()
        self.keepDisplayOn = defaults.object(forKey: Self.keepDisplayOnKey) as? Bool ?? true
    }

    public func start(_ duration: AwakeDuration) {
        now = clock()
        session = AwakeSession(duration: duration, startedAt: now)
        acquire()
        scheduleTick()
    }

    public func stop() {
        pendingTick?.cancel()
        pendingTick = nil
        assertion.release()
        session = nil
    }

    /// Re-checks the clock: ends an expired session and refreshes `now`.
    /// Call after the Mac wakes, since timers don't count time spent asleep.
    public func refresh() {
        now = clock()
        guard let session else { return }
        if session.isExpired(at: now) {
            stop()
        } else {
            scheduleTick()
        }
    }

    /// "15 min left", "Until turned off", or nil when idle.
    public var statusText: String? {
        guard let session else { return nil }
        guard let remaining = session.remaining(at: now) else { return "On until turned off" }
        return RemainingTime.string(remaining)
    }

    private func acquire() {
        do {
            try assertion.hold(keepDisplayOn: keepDisplayOn, reason: Self.reason)
            lastError = nil
        } catch {
            lastError = String(describing: error)
            pendingTick?.cancel()
            pendingTick = nil
            session = nil
        }
    }

    private func scheduleTick() {
        pendingTick?.cancel()
        pendingTick = nil
        guard let remaining = session?.remaining(at: now) else { return }
        let delay = min(remaining, Self.refreshInterval)
        pendingTick = scheduler.schedule(after: delay) { [weak self] in
            self?.refresh()
        }
    }
}
