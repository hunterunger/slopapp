# SlopDrive

Drives any running Mac app through Accessibility, so agents can use and test apps the way
a person would: read the UI tree, press buttons, pick menus, type, take screenshots.

Use it through `scripts/drive` (builds this package on first use, then forwards the
arguments). `scripts/drive help` prints every command. The dev cycle that uses it is in
[`docs/dev-cycle.md`](../../docs/dev-cycle.md).

Design choices:

- **Nothing lands in the user's apps.** Clicks are `AXPress` (no mouse movement); keys and
  typing are posted to the target app's process. Mouse commands and system-wide keys are
  opt-in flags.
- **Modifiers are never left held.** A key press posts each modifier as its own
  flagsChanged event (down before the key, up after it, in reverse), not just flags on the
  key event, which could leave ⌘/⌥/⌃ registered as held system-wide after `key --global`.
  A stroke runs under a lock and SIGINT/SIGTERM/SIGHUP/SIGQUIT wait for it to finish, so
  Ctrl-C never cuts one off mid-way. After a `--global` press the session's modifier state
  is checked, and anything still held is released again (with a warning).
  `release-modifiers` releases them all by hand (e.g. after a `kill -9`).
- **Mouse commands are fenced to the target app.** `clickxy <app> x y` and
  `drag <app> x1 y1 x2 y2` need `--allow-mouse` and the target app. Before acting, every point
  they click or pass over (start, end, 19 samples along a drag) must be on one of the app's
  own windows: the topmost window at the point comes from `CGWindowListCopyWindowInfo`
  (on-screen, front to back, layer >= 0, alpha > 0; full-screen click-through overlays of
  the Dock and Notification Center are skipped), and Accessibility's hit test confirms who
  would get the click (it catches the Dock and anything the window list misses). The window
  server check runs again right before each press; during a drag, each step re-checks for
  system prompts and, if one appeared, releases the button at the last safe point and stops. Otherwise it refuses
  with the blocking window's owner, title, pid and frame.
  `--allow-over <Owner>` (owner name as printed, or bundle id; repeatable) allows a
  deliberate cross-app drag, e.g. dropping onto Finder (which also allows the desktop).
  `--menubar` lets a click land in the system menu bar, and Accessibility must still put
  the point on the target's own status item. `--check` runs only the check.
  Windows of system permission and security agents (UserNotificationCenter,
  CoreServicesUIAgent, SecurityAgent, universalAccessAuthWarn, System Settings, tcc,
  keychain, authorization and login agents) and any window whose owner or title reads like a
  permission or password prompt always refuse, and can't be named in `--allow-over`.
  Code: `MouseGuard.swift`.
- **Compact text for LLMs.** One line per element: ref, role, label, value, state,
  shortcut, frame. Unlabeled layout groups are folded away; unlabeled controls are flagged.
- **Refs that survive small changes.** `tree` saves each ref's path in
  `/tmp/slopdrive/refs-<pid>.json`; if the path no longer matches, the element is re-found
  by role and label.
- **Status items.** Menu bar icons are drawn by the system, so they're found through
  Accessibility (`menubar`, `shot --status-item`), not window lists.

Needs Accessibility and Screen Recording permission for the terminal that runs it.

Files: `Drive.swift` (commands), `Tree.swift` (tree printing, refs, search), `AX.swift`
(element snapshots), `Apps.swift` (find/launch/quit, window server), `Input.swift`
(keys, mouse, CPU/memory usage), `MouseGuard.swift` (where mouse commands may act).
Tests (pure logic: key parsing, stroke order): `swift test --package-path tools/SlopDrive`.
