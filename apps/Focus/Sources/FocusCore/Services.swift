import Foundation

// Everything Focus asks of the system, behind protocols so tests use fakes.

/// Something that can run an action later.
@MainActor
public protocol Scheduler {
    /// `tolerance`: how late the system may run it to save power.
    func schedule(after interval: TimeInterval, tolerance: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any Cancellable
}

@MainActor
public protocol Cancellable {
    func cancel()
}

/// Production scheduler backed by a main-run-loop Timer.
@MainActor
public final class TimerScheduler: Scheduler {
    public init() {}

    public func schedule(after interval: TimeInterval, tolerance: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any Cancellable {
        let timer = Timer(timeInterval: max(interval, 0), repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        timer.tolerance = max(0, tolerance)
        RunLoop.main.add(timer, forMode: .common)
        return TimerHandle(timer: timer)
    }

    private final class TimerHandle: Cancellable {
        let timer: Timer
        init(timer: Timer) { self.timer = timer }
        func cancel() { timer.invalidate() }
    }
}

public enum NotificationPermission: String, Sendable {
    case authorized, denied, notDetermined
}

/// Posts end-of-phase notifications and reports the buttons people press on them.
@MainActor
public protocol Notifier: AnyObject {
    var onAction: ((AlertAction) -> Void)? { get set }
    func permission() async -> NotificationPermission
    /// Shows the system prompt (once) and returns the answer.
    func requestPermission() async -> NotificationPermission
    func post(_ content: AlertContent)
    /// Removes Focus's notifications from Notification Center (they're stale once the
    /// next phase starts).
    func clearDelivered()
}

/// Plays the end-of-phase sound.
@MainActor
public protocol SoundPlayer {
    var availableSounds: [String] { get }
    func play(_ name: String)
}

/// Runs the user's own shortcuts (the Shortcuts app) at the start and end of a session.
public protocol ShortcutRunner: Sendable {
    func list() async throws -> [String]
    func run(_ name: String) async throws
}

/// Keeps macOS from napping the app while a phase runs, so the end isn't late.
/// Doesn't keep the Mac awake.
@MainActor
public protocol ActivityToken {
    func begin()
    func end()
}

@MainActor
public final class ProcessActivity: ActivityToken {
    private var token: (any NSObjectProtocol)?

    public init() {}

    public func begin() {
        guard token == nil else { return }
        token = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "A focus timer is running"
        )
    }

    public func end() {
        guard let token else { return }
        ProcessInfo.processInfo.endActivity(token)
        self.token = nil
    }
}
