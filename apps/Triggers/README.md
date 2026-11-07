# Triggers

Your own gestures, shortcuts and actions.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to BetterTouchTool.

**Status:** alpha (0.1.0)

## What it does

Triggers makes the inputs you use fifty times a day do the thing you want, in every app or
just one:

- **Trackpad:** three- and four-finger taps, and three- and four-finger swipes left, right, up
  and down, optionally while holding ⌃ ⌥ ⇧ ⌘.
- **Mouse:** extra buttons (middle, 4, 5 and up), optionally with modifiers. A button is only
  taken over where a trigger uses it; everywhere else it does what it always did.
- **Keyboard:** key combinations (with ⌘, ⌥ or ⌃, or a function key). Per-app combinations are
  registered only while that app is in front, so they stay the app's own elsewhere.

Each trigger runs one action: press keys, middle-click / right-click / ⌘-click at the pointer,
choose a menu item, open an app, link or file, run a Shortcut, or move the front window (left,
right, top or bottom half, maximize, center, minimize, next display). In an app or the
Browsers group, "Do Nothing" lets the app keep an input that an All Apps trigger uses.

**Where triggers work:** All Apps, the built-in Browsers group (Safari, Chrome, Firefox, Arc,
Edge, Brave and others), or one app. An app's own trigger beats Browsers, which beats All
Apps. Any app can turn All Apps triggers off (games, remote desktops, VMs): right-click it in
the sidebar, or use **Turn Off in <App>** in the menu bar menu.

**Record by doing.** In the New Trigger sheet, tap, swipe, press the mouse button or the keys
and Triggers names it. Nothing runs while the sheet is open, so it's also a safe place to check
that your trackpad is recognized. "Or pick from a list" offers every input for people who'd
rather choose (and for VoiceOver).

**Before it surprises you:** the editor reads (never changes) your macOS trackpad settings and
says when macOS also uses a gesture (Mission Control, full-screen app switching, Look Up,
three-finger drag), with a button to the right System Settings pane. It also flags duplicate
triggers, key combinations macOS or another app already uses, and actions that would press
their own trigger.

It starts empty, with three one-click suggestions (three-finger tap to middle-click, four-finger
swipe for Back and Forward in browsers, mouse buttons 4 and 5 for Back and Forward in browsers
and Finder). Nothing is on until you add it.

## Menus and shortcuts

Menu bar: status line, **Edit Triggers… (⌘E)**, **Pause Triggers (⌘P)**, **Turn Off in
<App>**, **Recent** (the last fires; click one to open it), Settings…, About, Quit.

Editor: **New Trigger ⌘N**, **Add App… ⇧⌘N**, **Duplicate ⌘D**, Import…, Export…, **Delete ⌫**,
**Undo ⌘Z**, **Find ⌘F**, Trigger › **Turn On/Off ⌘T**, **Edit Trigger… ⌘↩** (or double-click),
**Run Action Now ⌘R**, **Pause Triggers ⇧⌘P**.

Settings › Shortcuts can set global shortcuts to pause/resume and to open the editor. None are
set by default, so they can't collide with your own triggers.

## Permissions

- **Trackpad gestures** need no permission. They're read with `MultitouchSupport`, a private
  macOS framework every gesture tool uses (there's no public API). It's loaded at runtime; if a
  macOS update changes it, gestures switch off with a note in the editor, and mouse buttons and
  key combinations keep working.
- **Key-combination triggers** need no permission (Carbon hotkeys, no keyboard event tap, so
  typing is never in Triggers' path; they keep working while a password field is focused).
- **Accessibility** is needed to press keys, click, choose menu items, move windows and take
  over mouse buttons. Triggers asks only when an enabled trigger needs it, with a bar in the
  editor and an item in the menu bar menu. Opening apps, links and files and running Shortcuts
  work without it.

The only event tap Triggers installs watches extra mouse buttons (other-mouse down, up and
dragged). It exists only while an enabled mouse-button trigger exists and Triggers isn't
paused, and it's removed the moment Accessibility is turned off. No network access, no
accounts, no analytics. Triggers live in
`~/Library/Application Support/app.slopapp.triggers/Triggers.json` (plain JSON; File › Export
and Import move them between Macs).

## Not there yet

Five-finger and two-finger gestures, double taps, tip-taps, corner taps, pinch and rotate, the
three-finger physical click, Magic Mouse gestures, long presses and multi-clicks, key sequences
and modifier-only taps (hyper key), shell or AppleScript actions (use a Shortcut that runs
one), action sequences, conditions beyond "which app", media/volume/system actions, and
custom app groups.

## Develop

```sh
scripts/test.sh Triggers     # unit tests
scripts/run.sh Triggers      # build a debug .app and open it
scripts/check.sh Triggers    # the full gate: tests, release bundle, launch smoke test
```

Logic lives in `Sources/TriggersCore` (tested, no system calls): the gesture recognizer
(`GestureRecognizer`), routing and precedence (`RoutingTable`), the event tap's decision
(`MouseTapDecider`, tested with constructed `CGEvent`s), conflicts, the JSON store, window
layout math (`WindowLayout.swift`, written to move into SlopKit) and the engine that ties
sources to actions. `Sources/TriggersTouchShim` declares the private framework's contact struct
in C so the compiler checks its layout. Views and system wiring live in `Sources/Triggers`:
`TouchSource.swift` (the only file that knows MultitouchSupport exists), `MouseTap.swift`,
`Hotkeys.swift` and `Performer.swift` (the only production code that posts events).

### Test mode

Tests and walkthroughs never send input to your real apps. Environment variables (see
`Diagnostics.swift`):

| Variable | Effect |
|---|---|
| `TRIGGERS_DATA_DIR=/tmp/triggers-test/data` | Triggers and settings in a throwaway place |
| `TRIGGERS_NO_INPUT=1` | No trackpad source, event tap or hotkeys: only replays |
| `TRIGGERS_REPLAY=/path/timeline.json` | Feed taps, swipes, raw frames, mouse buttons and key combos into the real recognizer and router, in-process |
| `TRIGGERS_ACT_ONLY_IN=<bundle id>` | Act only while that app is in front; keys and clicks go only to its process |
| `TRIGGERS_FRONT_APP=<same bundle id>` | Treat that app as in front (replays while the screen is locked) |
| `TRIGGERS_FAKE_APPS=1` | Made-up apps and Shortcuts in pickers; Open and Run Shortcut only log |
| `TRIGGERS_TEST_HOOKS=1` | Distributed notifications `app.slopapp.triggers.test.<hook>` (see `TestHooks.swift`) |
| `TRIGGERS_SNAPSHOT_DIR=/path` | Render the editor, sheet and Settings offscreen in light and dark, then quit |
| `TRIGGERS_ASSUME_TRUSTED=0/1`, `TRIGGERS_GESTURES_UNAVAILABLE=1` | Show the permission and degraded states |
| `TRIGGERS_LOG`, `TRIGGERS_PERF_LOG` | Decisions and timings; the perf log has numbers only |

A replay timeline looks like
`{"steps": [{"tap": 3}, {"after": 0.3, "swipe": {"fingers": 4, "direction": "left"}}, {"mouseButton": 3}, {"keyCode": 40, "modifiers": 3}, {"scrollSeconds": 10}]}`.
