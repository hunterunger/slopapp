# Awake

Keep your Mac awake, from the menu bar.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to Lungo and Amphetamine.

**Status:** alpha. This is also the reference app for the Slopapp pipeline: copy its
patterns when building a new app.

## What it does

- **Click the cup** in the menu bar to turn Awake on (for the default duration) or off. The
  cup fills while it's on. **Right-click** (or Control/Option-click) opens the menu. Settings
  can swap the two.
- **The menu:** time left, Turn On/Off, Add 30 Minutes, then Keep Awake: Indefinitely,
  10 and 30 minutes, 1, 2, 4, 8 and 12 hours, **Custom Duration…**, **Until…** a clock time,
  and **While App Is Running** (ends when that app quits). Then Allow Display Sleep and
  Use Triggers.
- **Triggers** (Settings › Triggers) keep the Mac awake automatically while a chosen app is
  running, while on the power adapter, or while an external display is connected. Turning
  Awake off while a trigger holds pauses triggers until their conditions change.
- **Battery:** turn off when switching to battery, or when the battery drops to a level you
  pick (5–50%). Triggers wait until the Mac is plugged in again.
- **Allow display to sleep** keeps the Mac awake but lets the screen turn off (good for
  downloads and builds). **Allow sleep while the screen is locked** pauses Awake while locked.
- **Global shortcut** to turn Awake on or off (Settings › Shortcuts, unset by default). A
  small HUD confirms, so it works with the icon hidden.
- Turn on when Awake opens, default duration, show time left next to the icon, dim the icon
  while off, launch at login, hide the menu bar icon. **Open Awake again** (Finder, Spotlight,
  a launcher) to bring the icon back and show Settings: the way in when the icon is out of
  sight, for example in a full menu bar or with Awake switched off in System Settings ›
  Menu Bar.

Under the hood it holds an `IOPMAssertion`, the same mechanism `caffeinate` uses. Check it
with `pmset -g assertions` (look for "Awake is keeping this Mac awake"). Nothing is polled:
power, displays, apps and the lock screen are all watched through system notifications.

## Scripting

The `slopawake:` URL scheme works from Terminal, Shortcuts ("Open URL") and launchers:

```sh
open "slopawake://activate"                  # default duration
open "slopawake://activate?minutes=45"       # also hours=2, hours=1&minutes=30, indefinitely
open "slopawake://activate?until=17:30"      # 24-hour clock, next time it comes round
open "slopawake://toggle"
open "slopawake://deactivate"
```

## Develop

```sh
scripts/test.sh Awake        # unit tests (AwakeCore)
scripts/run.sh Awake         # build a debug .app and open it
scripts/check.sh Awake       # tests, release bundle, launch smoke test
```

Environment variables for testing (none are needed in normal use):

| Variable | What |
|---|---|
| `AWAKE_ACTIVATE=15m` | Start a session at launch (also `90s`, `2h`, `forever`). |
| `AWAKE_DEFAULTS_SUITE=name` | Keep settings in a separate defaults domain (a path like `/tmp/awake-test/prefs` keeps it out of `~/Library/Preferences`). |
| `AWAKE_SNAPSHOT_DIR=/tmp/x` | Render Settings, the Keep Awake window and the icon to PNGs (light and dark) plus the menu as text, with fake system state, then quit. |
| `AWAKE_DEMO=1` | Fake system state (on battery at 64%, Safari/TextEdit/Terminal running) and a power assertion that holds nothing, for screenshots that never show your apps or change how the Mac sleeps. `AWAKE_DEMO_BATTERY=15` (or `none` for a desktop Mac), `AWAKE_DEMO_AC=1`. |
| `AWAKE_SHOW=menu` | Open a surface at launch: `menu` (pops the status item's menu up under the menu bar, for when the icon is hidden), `until`, `duration`, `settings`, `settings:triggers` (any tab), `about`, `hud`. Comma-separate several; the last ends up in front. |
| `AWAKE_SELFTEST=1` | Exercise the real status item, menu, Settings and Keep Awake window without a mouse; prints PASS/FAIL and quits. |

## Layout

| Path | What |
|---|---|
| `Sources/AwakeCore/AwakeController.swift` | All state: session, triggers, battery and lock rules, the assertion |
| `Sources/AwakeCore/AwakeSession.swift` | Session kinds (duration, until, while an app runs), trigger and end reasons |
| `Sources/AwakeCore/AwakePreferences.swift` | Every setting, persisted in `UserDefaults` |
| `Sources/AwakeCore/Monitors.swift`, `RealMonitors.swift` | `Monitor` protocol + IOKit power, CoreGraphics displays, NSWorkspace apps, screen lock |
| `Sources/AwakeCore/PowerAssertion.swift`, `Scheduler.swift` | `PowerAssertion` (IOKit) and `Scheduler` (Timer) protocols |
| `Sources/AwakeCore/MenuContent.swift` | The status item menu as data (tested, and dumped by the snapshot hook) |
| `Sources/AwakeCore/URLCommand.swift` | URL scheme parsing |
| `Sources/Awake/StatusItem.swift` | Status item: click to toggle, right-click menu, icon |
| `Sources/Awake/SettingsView.swift` | General, Triggers, Shortcuts, Advanced, About |
| `Sources/Awake/CustomSessionWindow.swift` | The Keep Awake window (custom duration, until a time) |
| `Sources/Awake/ReviewHooks.swift`, `Snapshots.swift`, `SelfTest.swift` | Diagnostics: demo state, open-a-surface, offscreen renders, self-test |
| `Tests/AwakeCoreTests/` | Tests with fake monitors, a fake assertion and a manual clock |
