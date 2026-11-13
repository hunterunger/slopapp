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
            if !copied { self?.model.lastDismissedLink = link.originalURL ?? link.url }
            self?.showNextWaiting()
            self?.giveFocusBackIfIdle()
        }
    }

    // MARK: - Intake

    /// Entry point for every URL macOS hands us (GetURL events, opened files, our menu).
    ///
    /// - Parameter simulated: test hook (`SWITCHBOARD_INBOX`): the keys "held" and the app the
    ///   link "came from", instead of reading the keyboard and the sender.
    func receive(
        _ url: URL, senderPID: pid_t? = nil, receivedAt: TimeInterval = Diagnostics.now(), forcePicker: Bool = false,
        simulated: (modifiers: Modifiers, source: String?)? = nil
    ) {
        // Read the keyboard first: the user may let go of a modifier any moment now.
        let modifiers = simulated?.modifiers ?? Self.currentModifiers()
        guard deduplicator.accept(url, at: receivedAt) else {
            Diagnostics.record("duplicate dropped url=\(url.absoluteString.prefix(200))")
            return
        }
        let source = simulated.map(\.source) ?? Self.sourceBundleID(pid: senderPID)
        switch LinkParser.intake(url) {
        case .reject(let reason):
            refuse(reason)
        case .readLinkFile(let file):
            // A web location: open the link inside it, like any link.
            guard let inner = Self.linkInside(file), case .route(let link, _) = LinkParser.intake(inner) else {
                refuse("“\(file.lastPathComponent)” has no web link in it.")
                return
            }
            Diagnostics.record("read web location file kind=\(LinkKind.of(link)?.rawValue ?? "app")")
            process(link, forced: forcePicker, modifiers: modifiers, source: source, senderPID: senderPID, receivedAt: receivedAt)
        case .route(let link, let forced):
            process(link, forced: forced || forcePicker, modifiers: modifiers, source: source, senderPID: senderPID, receivedAt: receivedAt)
        }
    }

    private func process(_ link: URL, forced: Bool, modifiers: Modifiers, source: String?, senderPID: pid_t?, receivedAt: TimeInterval) {
        Diagnostics.record("received pid=\(senderPID.map(String.init) ?? "none") kind=\(LinkKind.of(link)?.rawValue ?? "app")")
        if LinkKind.of(link) == .email { model.seedEmailTargetsIfNeeded() }
        let ask = model.config.askModifiers
        let wantsPicker = forced || (!ask.isEmpty && modifiers.isSuperset(of: ask))
        // Tracking removal and rewrites. Not into an app's link when the picker shows anyway
        // (then the point is to choose a browser), nor into one no app on this Mac opens.
        let prepared = LinkPreparation.prepare(link, config: model.config, allowAppLinks: !wantsPicker,
                                               canOpen: Opener.canOpen)
        for step in prepared.steps {
            switch step {
            case .removedTracking: Diagnostics.record("removed tracking parameters")
            case .rewritten(let index, let to): Diagnostics.record("rewrite \(index + 1) url=\(to.absoluteString.prefix(200))")
            case .skippedAppLink(let index, let scheme): Diagnostics.record("rewrite \(index + 1) skipped: no app opens \(scheme): links")
            }
        }
        let incoming = IncomingLink(url: prepared.url, sourceBundleID: source, modifiers: modifiers, forcePicker: forced,
                                    originalURL: prepared.url == link ? nil : link)
        route(incoming, receivedAt: receivedAt)
    }

    private func refuse(_ reason: String) {
        Diagnostics.record("rejected reason=\"\(reason)\"")
        HUD.show(reason, systemImage: "exclamationmark.triangle")
        giveFocusBackIfIdle()
    }

    /// The link in a .webloc/.url file (small files only).
    static func linkInside(_ file: URL) -> URL? {
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 1_000_000,
              let data = try? Data(contentsOf: file) else { return nil }
        return InternetLocation.url(from: data)
    }

    /// Routes a link with app handoffs off (the app failed): rules and browsers only.
    private func routeWithoutApps(_ link: IncomingLink, receivedAt: TimeInterval) {
        handoffsSuspended = true
        defer { handoffsSuspended = false }
        route(link, receivedAt: receivedAt)
    }

    /// True while re-routing a link whose app couldn't open it.
    private var handoffsSuspended = false

    private func route(_ link: IncomingLink, receivedAt: TimeInterval) {
        if picker.isShowing {
            waiting.append((link, receivedAt))
            picker.setWaitingCount(waiting.count)
            Diagnostics.record("queued url=\(link.url.absoluteString.prefix(200)) waiting=\(waiting.count)")
            return
        }
        let decision = Router.route(link, config: model.config, isInstalled: model.isInstalled,
                                    installedApp: handoffsSuspended ? { _ in nil } : HandoffApps.installed)
        let decideMs = Diagnostics.milliseconds(since: receivedAt)
        let source = link.sourceBundleID ?? "unknown"
        switch decision {
        case .openInApp(let app, let reason):
            Diagnostics.record("route decision=app app=\"\(app.appName ?? app.url.scheme ?? "")\" reason=\(reason) source=\(source) decide_ms=\(decideMs)")
            openApp(app, link: link, receivedAt: receivedAt)
            showNextWaiting()
        case .open(let target, let reason):
            Diagnostics.record("route decision=open kind=\(link.kind?.rawValue ?? "app") target=\"\(target.displayName)\" reason=\(reason) source=\(source) modifiers=\(link.modifiers.rawValue) decide_ms=\(decideMs)")
            open(link, in: target, background: false, receivedAt: receivedAt)
            // This may have been a queued link: keep draining the queue.
            showNextWaiting()
        case .pick(let targets, let reason):
            Diagnostics.record("route decision=pick kind=\(link.kind?.rawValue ?? "app") count=\(targets.count) targets=\"\(targets.map(\.displayName).joined(separator: "|"))\" reason=\(reason) source=\(source) modifiers=\(link.modifiers.rawValue) decide_ms=\(decideMs)")
            // Shown anyway (asked for, or a key held): highlight what the rules would pick.
            let preferred = Router.preferredTarget(for: link, config: model.config, isInstalled: model.isInstalled)
            picker.show(link, targets: targets, size: model.config.pickerSize, receivedAt: receivedAt,
                        waitingCount: waiting.count, preselect: preferred?.id)
        case .noTargets:
            Diagnostics.record("route decision=none")
            model.lastDismissedLink = link.originalURL ?? link.url
            let message = link.kind == .email
                ? "No email app to write this in. Add one in Switchboard's Settings › Email."
                : "Nothing to open this in. Add a browser in Switchboard's Settings."
            HUD.show(message, systemImage: "exclamationmark.triangle", duration: .seconds(3))
            showNextWaiting()
            giveFocusBackIfIdle()
        }
    }

    // MARK: - Picker results

    private func choose(link: IncomingLink, target: Target, background: Bool, always: Bool, receivedAt: TimeInterval) {
        if always, let rule = Router.alwaysOpenRule(for: link.url, in: target), let label = Router.alwaysOpenLabel(for: link.url) {
            let replaced = Router.learnedRuleTwin(of: rule, in: model.config.rules).map { model.config.rules[$0] }
            let index = Router.insertLearnedRule(rule, into: &model.config)
            let savedID = model.config.rules[index].id
            let undo = LearnedRuleUndo(ruleID: savedID, previous: replaced, host: label)
            model.learnedRuleUndo = undo
            UndoToast.show("\(label) will always open in \(target.displayName)") { [weak self] in
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
                model.lastDismissedLink = link.originalURL ?? link.url
                let message = (error as? Opener.Failure)?.message ?? Opener.Failure.failed(target.appName).message
                Diagnostics.record("open failed target=\"\(target.displayName)\" error=\(error)")
                HUD.show(message, systemImage: "exclamationmark.triangle", duration: .seconds(4))
                giveFocusBackIfIdle()
            }
        }
    }

    private func openApp(_ app: AppLink, link: IncomingLink, receivedAt: TimeInterval) {
        let started = Diagnostics.now()
        Task { @MainActor in
            do {
                try await Opener.open(app)
                Diagnostics.record("opened app=\"\(app.appName ?? app.url.scheme ?? "")\" open_call_ms=\(Diagnostics.milliseconds(since: started)) event_to_handoff_ms=\(Diagnostics.milliseconds(since: receivedAt))")
            } catch {
                Diagnostics.record("open failed app=\"\(app.appName ?? "")\" error=\(error)")
                // Never lose the link: route what arrived, as a web link, without app links.
                if let original = link.originalURL ?? (app.handoffID != nil ? Optional(link.url) : nil),
                   LinkKind.of(original) != nil {
                    Diagnostics.record("falling back to the link as it arrived")
                    let prepared = LinkPreparation.prepare(original, config: model.config, allowAppLinks: false)
                    var fallback = link
                    fallback.url = prepared.url
                    fallback.originalURL = nil
                    fallback.forcePicker = false
                    routeWithoutApps(fallback, receivedAt: receivedAt)
                } else {
                    let message = (error as? Opener.Failure)?.message ?? "Couldn't open the link in its app."
                    HUD.show(message, systemImage: "exclamationmark.triangle", duration: .seconds(3))
                    giveFocusBackIfIdle()
                }
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
