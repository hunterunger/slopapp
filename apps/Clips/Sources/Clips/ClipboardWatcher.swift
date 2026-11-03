import AppKit
import ClipsCore

/// Polls the pasteboard's change count (macOS has no change notification) twice a second.
/// Each tick reads one integer: about 0.05% CPU. Stops while the Mac sleeps.
@MainActor
final class ClipboardWatcher {
    var onChange: (() -> Void)?

    private let pasteboard: Pasteboard
    private var timer: Timer?
    private var tracker: ChangeTracker

    static let interval: TimeInterval = 0.5

    init(pasteboard: Pasteboard) {
        self.pasteboard = pasteboard
        tracker = ChangeTracker(startingAt: pasteboard.changeCount)
    }

    func start() {
        schedule()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.schedule()
                self?.check()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Marks a change count as Clips' own write so it isn't recorded as a new copy.
    func noteOwnWrite(changeCount: Int) {
        tracker.noteOwnWrite(changeCount)
    }

    /// Checks right now (e.g. when the panel opens, so a copy from a moment ago is there).
    func check() {
        if tracker.isNewExternalChange(pasteboard.changeCount) { onChange?() }
    }

    private func schedule() {
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = Self.interval * 0.4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
