# Focus

A calm focus timer that lives in your menu bar.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to Session.

**Status:** alpha

## What it does

Click the stopwatch in the menu bar and choose **Start Focus**. The icon turns into a
countdown ("18m"). When time is up you get a notification and the break starts by itself,
counting down with a leaf icon. The menu keeps a tally: "Today: 3 sessions · 1 hr 15 min".

- Focus lengths of 15, 25, 45 or 50 minutes, or any length from 1 to 180 (Settings ▸ Timer).
- Short break after each session, a long break after every fourth (both adjustable or off).
- Pause, Resume, Stop, Skip Break and Add 5 Minutes, from the menu or the notification.
- An optional label ("Write the intro") shown in the menu and saved with each session.
- Optional: run one of your own shortcuts when a session starts and another when it ends,
  for example to turn a Focus mode on and off (Settings ▸ Automation).
- The timer is based on when the phase ends, not on counting ticks, so it stays right
  across sleep, quitting and relaunching, and clock changes. If a session ends while the Mac
  is asleep you get one quiet notification when it wakes, never a pile of them.

A session counts toward today's total when at least 80% of it ran. Every minute focused
adds to today's time, even from sessions you stopped early. A session belongs to the day it
ended.

## Permissions

- **Notifications**: asked the first time you start a session, to tell you when time is
  up. If you don't allow them, Focus still plays the sound and briefly flashes a bell in
  the menu bar (not with Reduce Motion on), and the menu offers **Open Notification
  Settings…**.
- **Shortcuts**: only if you turn on Automation. Focus runs your shortcuts with the
  built-in `shortcuts` command; a shortcut may ask for its own permissions the first time.

No network access, no accounts. History is a small file in
`~/Library/Application Support/app.slopapp.focus/`.

## Keyboard shortcuts

In the menu: Start Focus ⌘↩, Pause/Resume ⌘P, Stop ⌘., Skip Break ⌘→, Add 5 Minutes ⌘+,
Add Label ⌘L, Settings ⌘,, Quit ⌘Q.

Global: **Start or pause** can be set in Settings ▸ Shortcuts. It's unset by default.

## Not there yet

- Charts and history beyond today (the history is stored, there's no view for it yet).
- Overtime (counting up past zero), a 2-minute warning, reflection prompts.
- Calendar sync and export.
- Shortcuts actions (App Intents): SwiftPM builds can't generate the metadata macOS needs to
  discover them. Until then, drive Focus with its global shortcut.
- App and website blocking: deliberately left out (intrusive and fragile). Use a Focus
  mode through Automation instead.

## Develop

```sh
scripts/test.sh Focus     # unit tests
scripts/run.sh Focus      # build a debug .app and open it
scripts/check.sh Focus    # the full gate: tests, release bundle, launch smoke test
```

Logic lives in `Sources/FocusCore` (tested): `TimerMachine` is the pure timer,
`FocusController` applies its events through injected services. Views and wiring live in
`Sources/Focus`.

Test hooks (environment variables, see `Sources/Focus/TestHooks.swift`):

| Variable | Effect |
|---|---|
| `FOCUS_DATA_DIR=/tmp/focus-test/data` | Keep state, settings and history there |
| `FOCUS_TEST_LOG=/tmp/focus-test/effects.log` | Log notifications, sounds and shortcut runs instead of doing them |
| `FOCUS_TEST_PERMISSION=denied` | Notification permission the logged notifier reports |
| `FOCUS_TEST_SHORTCUTS="Work On,Work Off"` | Shortcut names offered in Automation (a name with "fail" fails) |
| `FOCUS_SECONDS_PER_MINUTE=1` | A "minute" lasts one second |
| `FOCUS_APPEARANCE=light\|dark` | Force an appearance for windows |
| `FOCUS_START=1` | Start a session at launch |

Design follows [`docs/design-system.md`](../../docs/design-system.md). Shared pieces
(Settings, About, shortcuts) come from SlopKit.
