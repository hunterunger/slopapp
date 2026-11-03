import Foundation

/// Something that can run an action later. Injected so tests can control time.
@MainActor
public protocol Scheduler {
    func schedule(after interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any Cancellable
}

@MainActor
public protocol Cancellable {
    func cancel()
}

/// Production scheduler backed by a main-run-loop Timer.
@MainActor
public final class TimerScheduler: Scheduler {
    public init() {}

    public func schedule(after interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any Cancellable {
        let timer = Timer(timeInterval: max(interval, 0), repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        return TimerHandle(timer: timer)
    }

    private final class TimerHandle: Cancellable {
        let timer: Timer
        init(timer: Timer) { self.timer = timer }
        func cancel() { timer.invalidate() }
    }
}
