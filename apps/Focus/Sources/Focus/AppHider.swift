import AppKit
import FocusCore
import SlopKit

/// Hides the apps on the block list while a focus session runs: those already open are hidden
/// when the session starts, and one brought forward (or launched) during it is hidden again
/// with a short note. Nothing is quit and no app is changed; after the session, switching to
/// the app shows it as usual.
///
/// Test safety: with `FOCUS_TEST_LOG` set, apps are only logged, not hidden, unless
/// `FOCUS_HIDE_REAL=1` is also set (then only bundle ids listed in the test data dir's
/// settings are touched).
@MainActor
final class WorkspaceAppHider: AppHiding {
    private var bundleIDs: Set<String>?
    private var observers: [NSObjectProtocol] = []
    private let performs: Bool
    private let ownID = Bundle.main.bundleIdentifier

    init(performs: Bool) {
        self.performs = performs
    }

    func block(_ ids: Set<String>?) {
        bundleIDs = ids?.subtracting([ownID ?? ""])
        TestHooks.log("hide apps \(ids.map { $0.sorted().joined(separator: ",") } ?? "off")")
        if bundleIDs == nil || bundleIDs?.isEmpty == true {
            stopObserving()
            return
        }
        startObserving()
        for app in NSWorkspace.shared.runningApplications where matches(app) {
            hide(app, announce: false)
        }
    }

    private func matches(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier, let bundleIDs else { return false }
        return bundleIDs.contains(id)
    }

    private func hide(_ app: NSRunningApplication, announce: Bool) {
        TestHooks.log("hide \(app.bundleIdentifier ?? "?")")
        guard performs, !app.isHidden || app.isActive else { return }
        app.hide()
        if announce {
            let name = app.localizedName ?? "That app"
            HUD.show("\(name) is hidden until your session ends", systemImage: "eye.slash", duration: .seconds(1.8))
        }
    }

    private func startObserving() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let running = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated {
                    guard let self, let running, self.matches(running) else { return }
                    self.hide(running, announce: true)
                }
            })
        }
    }

    private func stopObserving() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
    }
}
