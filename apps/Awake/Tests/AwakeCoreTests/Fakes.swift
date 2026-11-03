import Foundation
@testable import AwakeCore

@MainActor
final class FakeAssertion: PowerAssertion {
    var isHeld = false
    var keepDisplayOn: Bool?
    var holdCount = 0
    var failNextHold = false

    func hold(keepDisplayOn: Bool, reason: String) throws {
        if failNextHold {
            failNextHold = false
            throw PowerAssertionError(code: -1)
        }
        isHeld = true
        self.keepDisplayOn = keepDisplayOn
        holdCount += 1
    }

    func release() {
        isHeld = false
        keepDisplayOn = nil
    }
}

/// A scheduler driven by a fake clock. `advance(by:)` moves time and fires due actions.
@MainActor
final class ManualScheduler: Scheduler {
    private(set) var now = Date(timeIntervalSince1970: 1_000_000)
    private var tasks: [Task] = []

    final class Task: Cancellable {
        let fireAt: Date
        let action: @MainActor () -> Void
        var isCancelled = false
        init(fireAt: Date, action: @escaping @MainActor () -> Void) {
            self.fireAt = fireAt
            self.action = action
        }
        func cancel() { isCancelled = true }
    }

    var pendingCount: Int { tasks.filter { !$0.isCancelled }.count }

    func schedule(after interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any Cancellable {
        let task = Task(fireAt: now.addingTimeInterval(interval), action: action)
        tasks.append(task)
        return task
    }

    /// Moves the clock forward without firing anything (like the Mac sleeping).
    func jump(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }

    func advance(by seconds: TimeInterval) {
        let target = now.addingTimeInterval(seconds)
        while let next = tasks.filter({ !$0.isCancelled && $0.fireAt <= target }).min(by: { $0.fireAt < $1.fireAt }) {
            now = next.fireAt
            next.isCancelled = true
            next.action()
        }
        tasks.removeAll { $0.isCancelled }
        now = target
    }
}
