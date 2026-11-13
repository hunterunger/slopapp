# Triggers

Your own gestures, shortcuts and actions.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to BetterTouchTool.

**Status:** alpha (0.1.0)

## What it does

Triggers makes the inputs you use fifty times a day do the thing you want, in every app or
just one:

- **Trackpad:** taps and double taps with two to five fingers; three-, four- and five-finger
  swipes in four directions; pinch and spread with two to five fingers; two-finger rotate;
  one-finger taps in a corner; two-finger swipes in from an edge; and tip-taps (rest one finger,
  tap another to its left or right). Any of them optionally while holding ⌃ ⌥ ⇧ ⌘. Triggers only
  looks for the gestures you've bound, so single taps stay instant unless you also bind a
  double tap with the same fingers.
- **Mouse:** extra buttons (middle, 4, 5 and up), optionally with modifiers. A button is only
  taken over where a trigger uses it; everywhere else it does what it always did.
- **Keyboard:** key combinations (with ⌘, ⌥ or ⌃, or a function key). Per-app combinations are
  registered only while that app is in front, so they stay the app's own elsewhere. Key
  sequences: a modifier tapped twice (⌘ ⌘), a modifier tapped alone, or up to four presses in a
  row (G then H, ⌃K then ⌃C). Sequences never block keys; the keys still reach the app.
- **Hyper key** (Settings › General, off by default): hold Caps Lock for ⌃⌥⇧⌘, tap it for
  Escape. Hyper combinations then work like any other key combination, in Triggers and in
  other apps.

**Actions.** A trigger runs one action, or a list of steps in order: actions, pauses ("Wait
0.5 s") and "Wait until" steps (until an app is in front, the Mac is on power, and so on, with a
time limit). Drag steps by their header to reorder them, or use Move Up / Move Down. Actions:
press keys, type text, middle-click / right-click / ⌘-click at the pointer, choose a menu item,
open an app, link or file, run a Shortcut, a shell script or an AppleScript, media and hardware
keys (play/pause, next, previous, volume, mute, brightness), Mission Control, App Exposé, Show
Desktop, Launchpad (Apps on macOS 26 and later), sleep display, lock screen, screen saver,
toggle dark mode, and window moves (halves, thirds, two-thirds, quarters, maximize, center,
minimize, full screen, next display, or a custom area in % of the screen). In an app or the
Browsers group, "Do Nothing" lets the app keep an input that an All Apps trigger uses.

**Conditions.** A trigger can run only when all (or any) of its conditions are true: an app
is or isn't running or in front, the Mac is online, offline, on Wi-Fi or Ethernet, an external
(or a particular) display is connected, it's on power or battery, a time of day, days of the
week, modifier keys held, dark mode on or off. Give the same input several triggers with
different conditions and the first one that's true runs; if none is, the next place's trigger
runs, or the input goes to the app as if Triggers weren't there.

**Where triggers work:** All Apps, the built-in Browsers group (Safari, Chrome, Firefox, Arc,
Edge, Brave and others), or one app. An app's own trigger beats Browsers, which beats All
Apps. Any app can turn All Apps triggers off (games, remote desktops, VMs): right-click it in
the sidebar, or use **Turn Off in <App>** in the menu bar menu.

**Record by doing.** In the New Trigger sheet, tap, swipe, pinch, press the mouse button, the
key combination or the keys one after another, and Triggers names it. Nothing runs while the sheet is open, so it's also a safe place to check
that your trackpad is recognized. "Or pick from a list" offers every input for people who'd
rather choose (and for VoiceOver).

**Before it surprises you:** the editor reads (never changes) your macOS trackpad settings and
says when macOS also uses a gesture (Mission Control, full-screen app switching, Look Up,
three-finger drag, pinch to zoom, smart zoom, the thumb-and-three-finger pinch, Notification
Center, tap to click), with a button to the right System Settings pane. It also flags duplicate
triggers, key combinations macOS or another app already uses, and actions that would press
their own trigger.

It starts empty, with three one-click suggestions (three-finger tap to middle-click, four-finger
swipe for Back and Forward in browsers, mouse buttons 4 and 5 for Back and Forward in browsers
and Finder). Nothing is on until you add it.

## Menus and shortcuts

Menu bar: status line, **Edit Triggers… (⌘E)**, **Pause Triggers (⌘P)**, **Turn Off in
<App>**, **Recent** (the last fires; click one to open it), Settings…, About, Report a Problem…, Quit.

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
- **Key-combination triggers** need no permission (Carbon hotkeys, no keyboard event tap; they
  keep working while a password field is focused).
- **Accessibility** is needed to press keys, type, click, choose menu items, move windows, use
  media keys, take over mouse buttons, watch key sequences and for the hyper key. Triggers asks
  only when something you turned on needs it, with a bar in the editor and an item in the menu
  bar menu. Opening apps, links and files, running Shortcuts and scripts, and most system
  actions work without it.
- **Automation** (macOS asks once): AppleScript actions, and Toggle Dark Mode (System Events).

Event taps: one for extra mouse buttons (other-mouse down, up and dragged), only while an
enabled mouse-button trigger exists; and one for keys (down, up, modifiers), only while an
enabled key sequence exists or the hyper key is on. Neither exists while Triggers is paused, and
both go the moment Accessibility is turned off. The key tap only ever lets keys through (the
hyper key adds its modifiers), and like every event tap it can't see password fields.

The hyper key remaps Caps Lock to F18 at the keyboard level (`hidutil`, as Apple documents in
TN2450) and turns F18 into ⌃⌥⇧⌘. The remap is undone when you turn it off, pause, quit, or
take away Accessibility, and a tiny watchdog process undoes it if Triggers crashes. If another
tool already remaps keys with `hidutil`, Triggers leaves it alone and says so in Settings. No network access, no
accounts, no analytics. Conditions read the network's state with
`NWPathMonitor`, which sends nothing. Triggers live in
`~/Library/Application Support/app.slopapp.triggers/Triggers.json` (plain JSON; File › Export
and Import move them between Macs). Files from 0.1 load as they are.

## Not there yet

Magic Mouse gestures (the only way to read its touches is the private framework, and Triggers
doesn't add new uses of it), the three-finger physical click and force click, long presses and
multi-clicks of mouse buttons, drawn gestures, Focus / Do Not Disturb and Wi-Fi network names as
conditions (macOS doesn't let a utility read them), if/else in step lists, left- versus
right-side modifier keys in sequences, and custom app groups.

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
`Hotkeys.swift`, `KeyboardTap.swift` (key sequences, the hyper key and its remap watchdog),
`SystemState.swift` (what conditions read) and `Performer.swift` / `SystemActions.swift` (the
only production code that posts events or runs things). Also in the core: conditions
(`Conditions.swift`), key sequence matching and recording (`KeySequences.swift`) and the hyper
key's decision and remap controller (`HyperKey.swift`), each with a fake for tests.

### Test mode

Tests and walkthroughs never send input to your real apps. Environment variables (see
`Diagnostics.swift`):

| Variable | Effect |
|---|---|
| `TRIGGERS_DATA_DIR=/tmp/triggers-test/data` | Triggers and settings in a throwaway place |
| `TRIGGERS_NO_INPUT=1` | No trackpad source, event taps or hotkeys: only replays. The default in test mode |
| `TRIGGERS_LIVE_INPUT=1` | In test mode, install the real sources anyway (the hyper key's remap never happens in test mode) |
| `TRIGGERS_DRY_RUN=1` | Every action is logged, never performed |
| `TRIGGERS_RUN_SCRIPTS=1` | In test mode, really run shell scripts and AppleScripts (otherwise logged) |
| `TRIGGERS_REPLAY=/path/timeline.json` | Feed taps, swipes, raw frames, mouse buttons and key combos into the real recognizer and router, in-process |
| `TRIGGERS_ACT_ONLY_IN=<bundle id>` | Act only while that app is in front; keys and clicks go only to its process |
| `TRIGGERS_FRONT_APP=<same bundle id>` | Treat that app as in front (replays while the screen is locked) |
| `TRIGGERS_FAKE_APPS=1` | Made-up apps, Shortcuts and displays in pickers; Open and Run Shortcut only log |
| `TRIGGERS_TEST_HOOKS=1` | Distributed notifications `app.slopapp.triggers.test.<hook>` (see `TestHooks.swift`) |
| `TRIGGERS_SNAPSHOT_DIR=/path` | Render the editor, sheet and Settings offscreen in light and dark, then quit |
| `TRIGGERS_ASSUME_TRUSTED=0/1`, `TRIGGERS_GESTURES_UNAVAILABLE=1` | Show the permission and degraded states |
| `TRIGGERS_LOG`, `TRIGGERS_PERF_LOG` | Decisions and timings; the perf log has numbers only |

A replay timeline looks like
`{"steps": [{"tap": 3}, {"after": 0.3, "swipe": {"fingers": 4, "direction": "left"}}, {"mouseButton": 3}, {"keyCode": 40, "modifiers": 3}, {"scrollSeconds": 10}, {"gesture": {"kind": "pinchOut", "fingers": 2}},
{"keys": [{"modifierTap": 8}, {"modifierTap": 8, "after": 0.25}]}]}`.

In test mode, media keys, volume, brightness, sleeping or locking the screen, Mission Control
and dark mode are only ever logged, whatever else is set. The smoke test
(`SLOPAPP_SMOKE_TEST=1`) is a dry run with no input sources and no remap.
