# Focus

A calm focus timer that lives in your menu bar.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to Session.

**Status:** alpha

## What it does

Click the stopwatch in the menu bar. The panel shows a small dial, today's total and your
daily goal. Type what you're working on and press Return (or **Start Focus**). The icon turns
into a countdown ("18m"). When time is up you get a notification, the break starts by itself
(with a leaf icon), and Focus asks how it went.

**The Focus window** (⌘0, or **Open Focus Window** in the panel) is the full view: a big
round timer with your category and intention on the left, and on the right either notes for
the running session or today's timeline, each session drawn where it happened. Drag around
the dial to set the length, or use −5 / +5. **Stats** (⌘2) shows a day, week or month:
totals, most focused hour, moods, a chart by category, and every session with its notes.

- **Intentions and categories.** "Draft intro @work 45m" sets the intention, picks the Work
  category and makes this one session 45 minutes. Past intentions are suggested as you type.
  Categories have colours and are edited in Settings ▸ Categories.
- **Reflection.** After a session: Focused, Neutral or Distracted, plus a note. Shown in the
  window, the panel and the break screen; ⌘↩ saves it. Can be turned off.
- **Finish or stop.** Finish counts the session now and starts the break; Stop just stops
  (it still counts if 80% ran). Pause, Resume, Skip Break, ±5 minutes.
- **Break screen** (optional, Settings ▸ Timer): covers the screen during breaks with the
  time left. Esc or **Hide** dismisses it straight away.
- **Hide apps** (optional, Settings ▸ Hide Apps): apps on your list are hidden while a focus
  session runs, and hidden again if you switch to one. Nothing is quit.
- **Export** every session and break as CSV (File ▸ Export Sessions as CSV…, ⇧⌘E).
- Focus lengths of 15, 25, 45 or 50 minutes, or anything from 1 to 180. Short break after
  each session, a long break after every fourth (both adjustable or off).
- Optional: run one of your own shortcuts when a session starts and another when it ends,
  for example to turn a Focus mode on and off (Settings ▸ Automation).
- The timer is based on when the phase ends, not on counting ticks, so it stays right
  across sleep, quitting and relaunching, and clock changes.

## Permissions

- **Notifications**: asked the first time you start a session. Without them Focus still
  plays the sound and briefly flashes a bell in the menu bar.
- **Shortcuts**: only if you turn on Automation.
- Hiding apps needs no permission (it's the same as ⌘H).

No network access, no accounts. History is a small file in
`~/Library/Application Support/app.slopapp.focus/`.

## Keyboard shortcuts

In the Focus window (Timer menu): Start Focus or Save Reflection ⌘↩, Pause/Resume ⌘P,
Finish Session ⇧⌘↩, Stop ⌘., Skip Break ⌥⌘→, Add/Remove 5 Minutes ⇧⌘. / ⇧⌘,,
Edit Intention ⌘L, Timer ⌘1, Stats ⌘2, Export ⇧⌘E. In the intention field: ↑ ↓ and Return
pick a suggestion.

Global: **Start or pause** and **Show the Focus window** can be set in Settings ▸ Shortcuts.
Both are unset by default.

## Not there yet

- Overtime (counting up past zero) and a warning before the end.
- Calendar logging, a URL scheme, background sounds, widgets.
- Shortcuts actions (App Intents): SwiftPM builds can't generate the metadata macOS needs.
- Website blocking: needs a browser extension; use a Focus mode through Automation instead.

## Develop

```sh
scripts/test.sh Focus     # unit tests
scripts/run.sh Focus      # build a debug .app and open it
scripts/check.sh Focus    # the full gate: tests, release bundle, launch smoke test
```

Logic lives in `Sources/FocusCore` (tested): `TimerMachine` is the pure timer,
`FocusController` applies its events through injected services, `StatsReport`,
`IntentionParser` and `CSVExport` are pure. Views and wiring live in `Sources/Focus`.

Test hooks (environment variables, see `Sources/Focus/TestHooks.swift`):

| Variable | Effect |
|---|---|
| `FOCUS_DATA_DIR=/tmp/focus-test/data` | Keep state, settings and history there |
| `FOCUS_TEST_LOG=/tmp/focus-test/effects.log` | Log notifications, sounds, shortcut runs, break screen and app hiding instead of doing them |
| `FOCUS_HIDE_REAL=1` | With the test log: really hide the apps on the test settings' list |
| `FOCUS_TEST_PERMISSION=denied` | Notification permission the logged notifier reports |
| `FOCUS_TEST_SHORTCUTS="Work On,Work Off"` | Shortcut names offered in Automation (a name with "fail" fails) |
| `FOCUS_SECONDS_PER_MINUTE=1` | A "minute" lasts one second |
| `FOCUS_APPEARANCE=light\|dark` | Force an appearance for windows |
| `FOCUS_START=1` | Start a session at launch |
| `FOCUS_OPEN_WINDOW=1` | Open the Focus window at launch |
| `FOCUS_SNAPSHOT_DIR=/tmp/x` | Render every view offscreen to PNGs (made-up data), then quit |
| `FOCUS_SAMPLE_HISTORY=1` | With `FOCUS_DATA_DIR`: fill an empty test history with five weeks of made-up sessions |
| `FOCUS_BREAK_WINDOW=1` | Show the break screen as one opaque window instead of covering every display |
| `FOCUS_PANEL_WINDOW=1` | Also show the menu bar panel's content in a plain window (driving, screenshots) |

Design follows [`docs/design-system.md`](../../docs/design-system.md). Shared pieces
(Settings, About, shortcuts, HUD) come from SlopKit.
