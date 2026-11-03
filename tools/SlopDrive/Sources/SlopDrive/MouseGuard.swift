import AppKit
import ApplicationServices

/// Keeps real-cursor commands (`clickxy`, `drag`) inside the target app.
///
/// Before (and while) the mouse acts, every point it clicks or passes over must be on one of
/// the target app's windows. The topmost window at a point comes from the window server
/// (on-screen, front to back, layer >= 0, alpha > 0); Accessibility's hit test then confirms
/// who would actually receive the click (it sees through click-through overlays and catches
/// the Dock). Windows of system permission/security agents are never acted on, whatever the
/// flags say: a stray drag once crossed a permission dialog.
enum MouseGuard {
    struct Policy {
        let target: NSRunningApplication
        /// Owner names (or bundle ids) the user allowed acting over, lowercased.
        var allowOver: Set<String> = []
        /// The point is meant for the system menu bar (e.g. the target's status item).
        var menuBar = false
    }

    /// Owner names of processes that show permission, password and security prompts.
    /// Matched case-insensitively as substrings of the window's owner name.
    static let systemAgents = [
        "usernotificationcenter", "coreservicesuiagent", "securityagent", "universalaccessauthwarn",
        "system settings", "system preferences", "tccd", "tcc", "coreauth", "localauthentication",
        "authenticationservices", "authorization", "keychain", "single sign-on", "appssoagent",
        "backgroundtaskmanagement", "loginwindow", "screensharingagent", "installer", "softwareupdate",
    ]
    /// Words in a window title or owner name that suggest a permission or security prompt.
    static let promptWords = [
        "permission", "would like to", "wants to", "allow ", "privacy", "password",
        "authenticat", "authoriz", "approve", "grant access", "access to", "security", "credential",
    ]
    /// Owners whose full-screen windows are click-through overlays (Accessibility still
    /// catches the visible parts, like the Dock itself).
    static let clickThroughOverlays: Set<String> = ["dock", "notification center", "notification centre", "windowmanager"]
    /// Owners that draw the menu bar; their windows are skipped only with --menubar, and the
    /// Accessibility hit test must still land on the target (its status item).
    static let menuBarOwners: Set<String> = [
        "window server", "dock", "menubaragent", "systemuiserver", "control center", "control centre",
        "notification center", "notification centre",
    ]

    struct ScreenWindow {
        let pid: pid_t
        let owner: String
        let title: String
        let layer: Int
        let bounds: CGRect

        var described: String {
            "\(quote(owner)) window \(title.isEmpty ? "(untitled)" : quote(title)) (pid \(pid), layer \(layer), " +
                "\(Int(bounds.minX)),\(Int(bounds.minY)) \(Int(bounds.width))x\(Int(bounds.height)))"
        }
    }

    /// On-screen windows, front to back, that could take a click: layer >= 0, alpha > 0.
    static func screenWindows() -> [ScreenWindow] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { w in
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            let layer = w[kCGWindowLayer as String] as? Int ?? 0
            let alpha = w[kCGWindowAlpha as String] as? Double ?? 1
            guard layer >= 0, alpha > 0 else { return nil }
            return ScreenWindow(
                pid: w[kCGWindowOwnerPID as String] as? pid_t ?? 0,
                owner: w[kCGWindowOwnerName as String] as? String ?? "?",
                title: w[kCGWindowName as String] as? String ?? "",
                layer: layer,
                bounds: CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0))
        }
    }

    /// The re-check during a drag, after the button is down: only system prompts stop it,
    /// since the drag itself adds windows (drag images) that the full check would trip over.
    static func promptRefusal(at p: CGPoint, policy: Policy) -> String? {
        for w in screenWindows() where w.bounds.contains(p) {
            if w.pid == policy.target.processIdentifier { return nil }
            if isSystemAgent(owner: w.owner, title: w.title) {
                return "\(Int(p.x)),\(Int(p.y)) is now covered by a system permission/security prompt: \(w.described). Released the button at the last safe point. Leave the prompt for a human."
            }
        }
        return nil
    }

    static func isSystemAgent(owner: String, title: String) -> Bool {
        let o = owner.lowercased(), t = title.lowercased()
        return systemAgents.contains { o.contains($0) } || promptWords.contains { o.contains($0) || t.contains($0) }
    }

    static func isFullDisplay(_ r: CGRect) -> Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)
        return ids.prefix(Int(count)).contains { CGDisplayBounds($0).insetBy(dx: -2, dy: -2).contains(r) && r.width >= CGDisplayBounds($0).width - 2 }
    }

    /// Why the mouse must not act at `p`, or nil when the point is on the target app.
    /// `accessibility: false` skips the (slower, ~50 ms) Accessibility hit test.
    static func refusal(at p: CGPoint, policy: Policy, windows: [ScreenWindow]? = nil, accessibility: Bool = true) -> String? {
        let pid = policy.target.processIdentifier
        let name = policy.target.localizedName ?? "the app"
        let all = windows ?? screenWindows()
        let at = "\(Int(p.x)),\(Int(p.y))"

        if systemAgents.contains(where: { name.lowercased().contains($0) }) {
            return "\(name) is a system permission/security agent: SlopDrive never moves the mouse over it. Ask a human."
        }
        var onTarget = false
        for w in all where w.bounds.contains(p) {
            if isSystemAgent(owner: w.owner, title: w.title) {
                return "\(at) is covered by a system permission/security prompt: \(w.described). SlopDrive never clicks these, even with --allow-over. Leave it for a human."
            }
            if w.pid == pid { onTarget = true; break }
            let owner = w.owner.lowercased()
            if owner == "window server", w.title == "Cursor" { continue }   // the pointer itself
            if clickThroughOverlays.contains(owner), isFullDisplay(w.bounds) { continue }
            if policy.menuBar, menuBarOwners.contains(owner) { continue }
            if allowed(owner: w.owner, pid: w.pid, policy) { onTarget = true; break }
            if owner == "window server", w.title == "Menubar" {
                return "\(at) is in the system menu bar. To click \(name)'s status item there, add --menubar (prefer `menubar \(name)`, which needs no mouse)."
            }
            return "\(at) is covered by \(w.described), not \(name). Bring \(name) to the front (`activate`), pick a point inside its window, " +
                "or, if you really mean to act over that app (e.g. drop onto Finder), add --allow-over \(quote(w.owner))."
        }
        if !onTarget {
            if policy.menuBar {
                guard all.contains(where: { $0.owner == "Window Server" && $0.title == "Menubar" && $0.bounds.contains(p) }) else {
                    return "\(at) is not in the menu bar (--menubar is for status items)."
                }
            } else if !policy.allowOver.contains("finder") {
                return "\(at) is on the desktop, not on a window of \(name). Pick a point inside its window (see `windows`)."
            }
        }
        guard accessibility else { return nil }

        // Who would really get the click: sees through click-through overlays, catches the Dock.
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &hit) == .success,
              let hit else { return nil }
        var hitPid: pid_t = 0
        AXUIElementGetPid(hit, &hitPid)
        guard hitPid != 0, hitPid != pid else { return nil }
        let hitName = NSRunningApplication(processIdentifier: hitPid)?.localizedName ?? "pid \(hitPid)"
        let role = Node(hit).shortRole
        if isSystemAgent(owner: hitName, title: "") {
            return "Accessibility says \(at) is on \(quote(hitName)) (\(role)), a system permission/security agent. SlopDrive never clicks these. Leave it for a human."
        }
        if allowed(owner: hitName, pid: hitPid, policy) { return nil }
        return "Accessibility says \(at) is on \(quote(hitName)) (\(role)), not \(name). Pick a point inside \(name)'s window" +
            (hitName == "Dock" ? " (away from the Dock)." : ", or add --allow-over \(quote(hitName)) if you mean it.")
    }

    private static func allowed(owner: String, pid: pid_t, _ policy: Policy) -> Bool {
        if policy.allowOver.contains(owner.lowercased()) { return true }
        if let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier?.lowercased(), policy.allowOver.contains(id) { return true }
        return false
    }

    /// Checks every point up front (with Accessibility). Throws the first refusal.
    static func check(_ points: [CGPoint], policy: Policy, verb: String) throws {
        for name in policy.allowOver where systemAgents.contains(where: { name.contains($0) }) {
            throw DriveError("--allow-over \(quote(name)) is never allowed: it's a system permission/security agent.")
        }
        let windows = screenWindows()
        for (i, p) in points.enumerated() {
            if let why = refusal(at: p, policy: policy, windows: windows) {
                let which = points.count > 1 ? " (point \(i + 1) of \(points.count) on the path)" : ""
                throw DriveError("refusing to \(verb)\(which): \(why)")
            }
        }
    }
}
