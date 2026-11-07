import AppKit
import SlopKit
import SwitchboardCore

/// Receives links from macOS, decides where they go, and opens them or shows the picker.
@MainActor
final class LinkRouter {
    static let shared = LinkRouter()

    private let model = AppModel.shared
    let picker = PickerController()
    private var deduplicator = Deduplicator()
    /// Links that arrived while the picker was showing another one.
    private var waiting: [(link: IncomingLink, receivedAt: TimeInterval)] = []

    private init() {
        picker.onChoose = { [weak self] link, target, background, always, receivedAt in
            self?.choose(link: link, target: target, background: background, always: always, receivedAt: receivedAt)
        }
        picker.onDismiss = { [weak self] link, copied in
            if !copied { self?.model.lastDismissedLink = link.url }
            self?.showNextWaiting()
            self?.giveFocusBackIfIdle()
        }
    }

    // MARK: - Intake

    /// Entry point for every URL macOS hands us (GetURL events, opened HTML files, our menu).
    func receive(_ url: URL, senderPID: pid_t? = nil, receivedAt: TimeInterval = Diagnostics.now(), forcePicker: Bool = false) {
        // Read the keyboard first: the user may let go of a modifier any moment now.
        let modifiers = Self.currentModifiers()
        guard deduplicator.accept(url, at: receivedAt) else {
            Diagnostics.record("duplicate dropped url=\(url.absoluteString.prefix(200))")
            return
        }
        switch LinkParser.intake(url) {
        case .reject(let reason):
            Diagnostics.record("rejected reason=\"\(reason)\"")
            HUD.show(reason, systemImage: "exclamationmark.triangle")
            giveFocusBackIfIdle()
        case .route(let link, let forced):
            Diagnostics.record("received pid=\(senderPID.map(String.init) ?? "none")")
            let cleaned = model.config.stripsTrackingParameters ? TrackingParameters.strip(link) : link
            if cleaned != link { Diagnostics.record("removed tracking parameters") }
            let incoming = IncomingLink(
                url: cleaned,
                sourceBundleID: Self.sourceBundleID(pid: senderPID),
                modifiers: modifiers,
                forcePicker: forced || forcePicker
            )
            route(incoming, receivedAt: receivedAt)
        }
    }

    private func route(_ link: IncomingLink, receivedAt: TimeInterval) {
        if picker.isShowing {
            waiting.append((link, receivedAt))
            picker.setWaitingCount(waiting.count)
            Diagnostics.record("queued url=\(link.url.absoluteString.prefix(200)) waiting=\(waiting.count)")
            return
        }
        let decision = Router.route(link, config: model.config, isInstalled: model.isInstalled)
        let decideMs = Diagnostics.milliseconds(since: receivedAt)
        let source = link.sourceBundleID ?? "unknown"
        switch decision {
        case .open(let target, let reason):
            Diagnostics.record("route decision=open target=\"\(target.displayName)\" reason=\(reason) source=\(source) modifiers=\(link.modifiers.rawValue) decide_ms=\(decideMs)")
            open(link, in: target, background: false, receivedAt: receivedAt)
            // This may have been a queued link: keep draining the queue.
            showNextWaiting()
        case .pick(let targets, let reason):
            Diagnostics.record("route decision=pick count=\(targets.count) reason=\(reason) source=\(source) modifiers=\(link.modifiers.rawValue) decide_ms=\(decideMs)")
            // Shown anyway (asked for, or a key held): highlight what the rules would pick.
            let preferred = Router.preferredTarget(for: link, config: model.config, isInstalled: model.isInstalled)
            picker.show(link, targets: targets, size: model.config.pickerSize, receivedAt: receivedAt,
                        waitingCount: waiting.count, preselect: preferred?.id)
        case .noTargets:
            Diagnostics.record("route decision=none")
            model.lastDismissedLink = link.url
            HUD.show("No browser to open this in. Add one in Switchboard's Settings.", systemImage: "exclamationmark.triangle", duration: .seconds(3))
            showNextWaiting()
            giveFocusBackIfIdle()
        }
    }

    // MARK: - Picker results

    private func choose(link: IncomingLink, target: Target, background: Bool, always: Bool, receivedAt: TimeInterval) {
        if always, let rule = Router.alwaysOpenRule(for: link.url, in: target) {
            let replaced = model.config.rules.first {
                $0.host.caseInsensitiveCompare(rule.host) == .orderedSame
                    && PathPrefix($0.path) == nil && $0.sourceApp == nil && $0.modifiers.isEmpty
            }
            let index = Router.insertLearnedRule(rule, into: &model.config)
            let savedID = model.config.rules[index].id
            let undo = LearnedRuleUndo(ruleID: savedID, previous: replaced, host: rule.host)
            model.learnedRuleUndo = undo
            UndoToast.show("\(rule.host) will always open in \(target.displayName)") { [weak self] in
                self?.model.undoLearnedRule(undo)
            }
        }
        open(link, in: target, background: background, receivedAt: nil)
        showNextWaiting()
    }

    private func showNextWaiting() {
        guard !picker.isShowing, !waiting.isEmpty else { return }
        let next = waiting.removeFirst()
        route(next.link, receivedAt: next.receivedAt)
    }

    // MARK: - Opening

    private func open(_ link: IncomingLink, in target: Target, background: Bool, receivedAt: TimeInterval?) {
        let started = Diagnostics.now()
        Task { @MainActor in
            do {
                try await Opener.open(link.url, in: target, background: background)
                if background || target.opensInBackground { giveFocusBackIfIdle() }
                let handoff = receivedAt.map { " event_to_handoff_ms=\(Diagnostics.milliseconds(since: $0))" } ?? ""
                Diagnostics.record("opened target=\"\(target.displayName)\" open_call_ms=\(Diagnostics.milliseconds(since: started))\(handoff)")
            } catch {
                model.lastDismissedLink = link.url
                let message = if case Opener.Failure.appMissing(let name) = error {
                    "\(name) isn't installed anymore. Choose another browser in Switchboard's Settings."
                } else {
                    "Couldn't open the link in \(target.appName). Try again, or pick another browser."
                }
                Diagnostics.record("open failed target=\"\(target.displayName)\" error=\(error)")
                HUD.show(message, systemImage: "exclamationmark.triangle", duration: .seconds(3))
                giveFocusBackIfIdle()
            }
        }
    }

    /// macOS activates the default browser (us) when a link is clicked. If no browser took
    /// over (the picker was dismissed, the link opened in the background, or it was refused),
    /// go back to the app the user was in, even if our Settings window is open behind it.
    private func giveFocusBackIfIdle() {
        guard NSApp.isActive, !picker.isShowing else { return }
        if let previous = lastOtherApp, !previous.isTerminated {
            NSApp.yieldActivation(to: previous)
            previous.activate()
            return
        }
        let hasWindow = NSApp.windows.contains { $0.isVisible && $0.level == .normal && !($0 is NSPanel) }
        if !hasWindow { NSApp.hide(nil) }
    }

    /// The most recently active app other than us: where focus goes back to.
    private var lastOtherApp: NSRunningApplication?

    /// Call once at launch. Event-driven, no polling.
    func startTrackingActiveApp() {
        let own = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != own { lastOtherApp = front }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let app, app.processIdentifier != own else { return }
                self?.lastOtherApp = app
            }
        }
    }

    // MARK: - Helpers

    static func currentModifiers() -> Modifiers {
        let flags = NSEvent.modifierFlags
        var result: Modifiers = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.function) { result.insert(.function) }
        return result
    }

    /// The app a link came from, with helper processes mapped to their main app.
    static func sourceBundleID(pid: pid_t?) -> String? {
        guard let pid, pid > 0, pid != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        if let bundleURL = app.bundleURL, let outer = SourceApp.outermostAppPath(bundleURL.path),
           let id = Bundle(path: outer)?.bundleIdentifier {
            return id
        }
        return app.bundleIdentifier
    }
}
