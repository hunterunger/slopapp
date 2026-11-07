import Foundation
@testable import FocusCore

/// A fixed UTC Gregorian calendar so day boundaries are predictable.
let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// 2026-11-03 10:00 UTC.
let t0 = utc.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 10))!

func minutes(_ m: Double) -> TimeInterval { m * 60 }

/// A scheduler driven by a fake clock. `advance(by:)` moves time and fires due actions;
/// `jump(by:)` moves time without firing anything, like the Mac sleeping.
@MainActor
final class ManualScheduler: Scheduler {
    var now: Date
    private var tasks: [Item] = []
    private(set) var scheduledCount = 0
    private(set) var tolerances: [TimeInterval] = []

    init(now: Date = t0) { self.now = now }

    final class Item: Cancellable {
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
    var nextFireDate: Date? { tasks.filter { !$0.isCancelled }.map(\.fireAt).min() }

    func schedule(after interval: TimeInterval, tolerance: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any Cancellable {
        let item = Item(fireAt: now.addingTimeInterval(interval), action: action)
        tasks.append(item)
        scheduledCount += 1
        tolerances.append(tolerance)
        return item
    }

    func jump(by seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }

    /// Drops everything scheduled, as when the app quits.
    func cancelAll() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    func advance(by seconds: TimeInterval) {
        let target = now.addingTimeInterval(seconds)
        while let next = tasks.filter({ !$0.isCancelled && $0.fireAt <= target }).min(by: { $0.fireAt < $1.fireAt }) {
            now = max(now, next.fireAt)
            next.isCancelled = true
            next.action()
        }
        tasks.removeAll { $0.isCancelled }
        now = target
    }
}

@MainActor
final class FakeNotifier: Notifier {
    var onAction: ((AlertAction) -> Void)?
    var current: NotificationPermission
    var answer: NotificationPermission
    private(set) var posted: [AlertContent] = []
    private(set) var requests = 0

    init(permission: NotificationPermission = .authorized, answer: NotificationPermission = .denied) {
        current = permission
        self.answer = answer
    }

    func permission() async -> NotificationPermission { current }
    func requestPermission() async -> NotificationPermission {
        requests += 1
        current = answer
        return answer
    }
    private(set) var clears = 0
    func post(_ content: AlertContent) { posted.append(content) }
    func clearDelivered() { clears += 1 }
    func press(_ action: AlertAction) { onAction?(action) }
}

@MainActor
final class FakeSound: SoundPlayer {
    var availableSounds = ["Glass", "Ping"]
    private(set) var played: [String] = []
    func play(_ name: String) { played.append(name) }
}

@MainActor
final class FakeActivity: ActivityToken {
    private(set) var isActive = false
    private(set) var begins = 0
    func begin() {
        if !isActive { begins += 1 }
        isActive = true
    }
    func end() { isActive = false }
}

actor FakeShortcuts: ShortcutRunner {
    private(set) var runs: [String] = []
    var failing: Set<String> = []
    var names = ["Focus On", "Focus Off"]

    func setFailing(_ names: Set<String>) { failing = names }
    func list() async throws -> [String] { names }
    func run(_ name: String) async throws {
        runs.append(name)
        if failing.contains(name) { throw ShortcutError.couldntRun(name) }
    }
}

@MainActor
final class FakeBlocker: AppHiding {
    private(set) var calls: [Set<String>?] = []
    var current: Set<String>? { calls.last ?? nil }
    func block(_ bundleIDs: Set<String>?) { calls.append(bundleIDs) }
}

/// Everything a controller test needs, wired together.
@MainActor
struct Rig {
    let storage: MemoryStorage
    let notifier: FakeNotifier
    let sound = FakeSound()
    let shortcuts: FakeShortcuts
    let scheduler: ManualScheduler
    let activity = FakeActivity()
    let blocker = FakeBlocker()
    var reduceMotion = false
    let controller: FocusController

    init(
        settings: TimerSettings? = nil,
        storage: MemoryStorage = MemoryStorage(),
        scheduler: ManualScheduler = ManualScheduler(),
        permission: NotificationPermission = .authorized,
        shortcuts: FakeShortcuts = FakeShortcuts(),
        reduceMotion: Bool = false
    ) {
        if let settings { storage.settings = settings }
        self.storage = storage
        self.notifier = FakeNotifier(permission: permission)
        self.scheduler = scheduler
        self.shortcuts = shortcuts
        self.reduceMotion = reduceMotion
        let s = scheduler
        controller = FocusController(
            storage: storage, notifier: notifier, sound: sound, shortcuts: shortcuts,
            scheduler: scheduler, activity: activity, blocker: blocker, clock: { s.now }, calendar: utc,
            reduceMotion: { reduceMotion }
        )
    }

    /// A second controller on the same storage and clock, as after quitting and relaunching.
    func relaunched() -> Rig {
        scheduler.cancelAll()
        return Rig(storage: storage, scheduler: scheduler, permission: notifier.current, shortcuts: shortcuts)
    }
}
