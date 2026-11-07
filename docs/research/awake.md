# Awake research (inspired by Lungo and Amphetamine)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md), after the fact:
> Awake was the pipeline's reference app and predates the research step. Studied on
> 2026-11-03: Lungo 2.8.x (sindresorhus, Setapp + Mac App Store) and Amphetamine 5.x
> (William Gustafson, free on the Mac App Store). Neither is installed on this Mac, so this
> comes from their websites, App Store listings, the Setapp listing and its screenshots
> (downloaded to `/tmp/awake-parity/`, not committed). We study how they work so we don't
> reinvent the wheel. We never copy their names, icons, artwork, wording, sounds or
> signature visuals.

## The job

Stop the Mac from sleeping (and usually the screen from dimming) for a while: during a long
download, a build, a presentation, a video call, or while reading without touching the
keyboard. People reach for it several times a day for a second or two. "Done" is the cup
filling in the menu bar and the Mac staying up until they turn it off, the time runs out, or
the reason goes away (the app quits, the charger is unplugged).

The one interaction that matters most: **click the menu bar icon; it's on. Click again; it's
off.** Everything else (durations, until a time, triggers) is one right-click away.

## Who and when

- Starting a long download or `brew upgrade`, then walking away: on indefinitely, display
  allowed to sleep.
- Presenting or screen-sharing: on for an hour, display kept on.
- Reading or watching something on a second display: a trigger (external display connected)
  does it without thinking.
- A build machine or a Mac running a long render: a trigger (while Xcode / Final Cut runs).
- On a laptop away from power: turn off automatically when the battery gets low.

Frequency: a few times a day, one click each. Settings are visited once.

## How the originals work

**Lungo** (the simple one). A cup icon in the menu bar. Out of the box a *left* click opens the
menu and a *right* click activates; the "Activate on left-click" setting swaps them, which is
how most people use it. The menu: a greyed header, Indefinitely, 10 and 30 minutes, 1, 2, 4,
8 and 12 hours, then Preferences…, a More submenu (links) and Quit. While active, the top
shows the time remaining (greyed) and Deactivate, and the running duration has a checkmark.
Settings has three tabs: General (Launch at login, Activate at launch, Activate on
left-click), Shortcuts (one recorder: activate/deactivate, no default, a suggested combo) and
Advanced (Default duration, Dim icon while deactivated, Allow display to sleep, Pause while
screen is locked, Deactivate when switching to battery). Recent versions add a choice of
active icon style (coloured, or a badge dot). Shortcuts app actions ("Set Enabled State",
"Adjust Time"), a URL scheme (`activate`/`deactivate`/`toggle` with `hours`/`minutes`), a CLI.
No app triggers, no "until a time" in the app (the site offers a Shortcut for it), no
closed-lid mode (Mac App Store limits).

**Amphetamine** (the power tool). A pill icon; by default a left click opens a large menu
and a right-click starts a session with the defaults. Sessions: indefinitely, minutes or hours
(submenus), until a specific time, while an app is running, while a file is downloading. Quick
options per session: allow display sleep, allow the screen saver, allow system sleep when the
display is closed, move the cursor. **Triggers** start sessions automatically while criteria
hold: an app running (optionally frontmost), external display connected or mirroring, USB or
Bluetooth device, power adapter connected/disconnected, battery charging or above a
threshold, Wi-Fi network / IP / DNS / VPN, audio output, a mounted volume, CPU above a
threshold, idle time. Also: end sessions on low battery, closed-display mode (needs a helper
script and admin rights on Apple Silicon), Drive Alive (keeps external drives spinning),
session statistics, custom menu bar icons with time remaining, hot keys for most actions,
AppleScript, notification sounds, extend a running session.

## Feature inventory

Priority: **must**, **should**, **later**, **skip**. "v1 now" is what Awake ships after the
parity pass.

| # | Feature | Original | Priority | v1 now |
|---|---|---|---|---|
| 1 | Click the icon to turn on/off | Lungo (opt-in), Amphetamine right-click | must | ✅ left click toggles, right/⌃/⌥-click opens the menu; swappable |
| 2 | Icon shows state | both | must | ✅ empty cup / full cup (template SF Symbol) |
| 3 | Preset durations | both | must | ✅ Indefinitely, 10m, 30m, 1h, 2h, 4h, 8h, 12h |
| 4 | Time remaining in the menu | both | must | ✅ greyed status line at the top |
| 5 | Checkmark on the running duration | Lungo | should | ✅ |
| 6 | Default duration (click, shortcut, launch) | both | must | ✅ General › Default duration |
| 7 | Allow display to sleep | both | must | ✅ menu checkbox + Advanced |
| 8 | Activate at launch | Lungo | should | ✅ "Turn on when Awake opens" |
| 9 | Global shortcut on/off | both | must | ✅ unset by default; HUD confirms |
| 10 | Until a specific time | Amphetamine (Lungo via Shortcuts) | should | ✅ "Until…" window, next occurrence |
| 11 | Custom duration | Amphetamine | should | ✅ "Custom Duration…" (same window, For tab) |
| 12 | While an app is running (session) | Amphetamine | should | ✅ submenu of running apps; ends when it quits |
| 13 | Extend a timed session | Amphetamine, Lungo (Shortcuts) | later | ✅ "Add 30 Minutes" |
| 14 | Deactivate when switching to battery | Lungo | should | ✅ |
| 15 | End session on low battery | Amphetamine | should | ✅ threshold 5–50% |
| 16 | Pause while the screen is locked | Lungo | should | ✅ "Allow sleep while the screen is locked" |
| 17 | Dim icon while off | Lungo | later | ✅ |
| 18 | Time remaining next to the icon | Amphetamine | later | ✅ "1h 05m", monospaced |
| 19 | Trigger: app running | Amphetamine | should | ✅ list + Add App (running apps or /Applications) |
| 20 | Trigger: power adapter connected | Amphetamine | should | ✅ |
| 21 | Trigger: external display connected (incl. mirroring) | Amphetamine | should | ✅ (online non-built-in displays) |
| 22 | Triggers on/off from the menu | Amphetamine | should | ✅ "Use Triggers" / "Set Up Triggers…" |
| 23 | URL scheme | Lungo | should | ✅ `slopawake://activate?minutes=…`, `until=`, `toggle`, `deactivate` |
| 24 | Launch at login, hide icon | both | must | ✅ (SlopKit) |
| 25 | Shortcuts app actions (App Intents) | Lungo | later | ❌ deferred (see below); URL scheme covers "Open URL" |
| 26 | Trigger: app frontmost only | Amphetamine | later | ❌ deferred |
| 27 | Trigger: USB / Bluetooth device | Amphetamine | later | ❌ deferred |
| 28 | Trigger: Wi-Fi network | Amphetamine | later | ❌ deferred |
| 29 | Trigger: battery charging / above level, CPU, idle, audio, volume, VPN, IP/DNS | Amphetamine | later | ❌ deferred |
| 30 | While a file is downloading | Amphetamine | later | ❌ deferred |
| 31 | Allow screen saver | Amphetamine | later | ❌ deferred |
| 32 | Session statistics | Amphetamine | later | ❌ deferred |
| 33 | Drive Alive | Amphetamine | later | ❌ deferred |
| 34 | Notification / sound when a session ends | Amphetamine | later | ❌ deferred |
| 35 | Closed-display (clamshell) mode on battery | Amphetamine | skip | needs admin rights and a root helper (`pmset disablesleep`); against "no sudo, quiet by default" |
| 36 | Move the cursor periodically | Amphetamine | skip | needs Accessibility, fakes user activity; Awake's assertion already prevents idle sleep |
| 37 | Lock screen after inactivity | Amphetamine | skip | not this app's job |
| 38 | Custom menu bar icon sets, padding | both | skip | signature visuals; one honest template icon follows the system |
| 39 | CLI tool | Lungo | skip | `open "slopawake://…"` does the same with nothing to install |
| 40 | AppleScript dictionary | Amphetamine | skip | URL scheme covers scripting |

## Key flows

### Flow 1: quick on/off
1. Click the cup. It fills; the Mac now holds `PreventUserIdleDisplaySleep` for the default
   duration (Indefinitely unless changed).
2. Click again. It empties; the assertion is released.
3. Hover for a tooltip: status ("2 hr left") and "Click to turn off. Right-click for options."

### Flow 2: a specific length or time
1. Right-click the cup. The menu shows the status line, Turn On (with the shortcut if set),
   the Keep Awake presets, Custom Duration…, Until…, While App Is Running ▸.
2. Pick "2 Hours": on, "2 hr left" at the top next time, checkmark on 2 Hours.
3. Or "Until…": a small Keep Awake window opens with For | Until; the time defaults to the next
   half hour at least an hour away and says "Today, in 1 hr 19 min". Return starts, Esc cancels.

### Flow 3: triggers
1. Menu › Set Up Triggers… opens Settings on the Triggers tab.
2. Add App › pick a running app (or "Choose from Applications…"). If it's running, Awake turns
   on at once; the footer says "On now, because Xcode is running."
3. Quitting that app turns Awake off. Clicking the cup while a trigger holds turns it off and
   pauses triggers until their condition clears (quit/relaunch, unplug/replug).

### Flow 4: first run
1. Launch: a cup appears; nothing else. No onboarding, no permission prompts (none needed).

## Settings inventory

| Tab | Setting | Default | Notes |
|---|---|---|---|
| General | Launch at login | off | SlopKit |
| General | Show in menu bar | on | SlopKit; reopening the app brings it back |
| General | Turn on when Awake opens | off | Lungo "Activate at launch" |
| General | Default duration | Indefinitely | Lungo |
| General | Clicking the menu bar icon | Turns Awake on or off | the brief's choice; Lungo's opt-in, Amphetamine's right-click |
| Triggers | Keep awake automatically | on | master switch; nothing happens until a trigger is set up |
| Triggers | While an app is running | none | list with remove buttons, Add App menu |
| Triggers | While connected to a power adapter | off | |
| Triggers | While an external display is connected | off | |
| Shortcuts | Turn Awake on or off | unset | like Lungo; avoids collisions |
| Advanced | Allow display to sleep | off | same as the menu checkbox |
| Advanced | Allow sleep while the screen is locked | off | Lungo "Pause while screen is locked" |
| Advanced | Turn off when switching to battery | off | disabled on desktops |
| Advanced | Turn off when the battery is low / level | off / 20% | disabled on desktops |
| Advanced | Show time left next to the icon | off | |
| Advanced | Dim the icon while off | off | |

## Menus and shortcuts

```
[status: "2 hr left" / "On until 5:30 PM, 3 hr left" / "On while Xcode is running" /
         "Turned off: battery at 15%"]
Turn On (for <default>) | Turn Off        (shows the global shortcut when set)
Add 30 Minutes                            (timed sessions only)
----
KEEP AWAKE
Indefinitely · 10 Minutes · 30 Minutes · 1 Hour · 2 Hours · 4 Hours · 8 Hours · 12 Hours
Custom Duration… · Until… · While App Is Running ▸
----
Allow Display Sleep
Use Triggers | Set Up Triggers…
----
Settings… ⌘,   About Awake
----
Quit Awake ⌘Q
```

No default global shortcut. Keep Awake window: Return = Start, Esc = Cancel.

## Permissions and system integration

- None needed. `IOPMAssertionCreateWithName` needs no entitlement; the power-source, display,
  workspace and lock-screen notifications need no permission.
- URL scheme `slopawake:` (via `app.json` `infoPlist`). New scheme only; no default handler changes.
- Login item via SlopKit's `LaunchAtLogin` (SMAppService), only when the user turns it on.

## UX patterns worth adopting

- One click does the common thing; everything else is a right-click away (both originals).
- The status line at the top of the menu answers "how long?" before anything else.
- Triggers that stay out of the way: they hold the Mac awake while true and let go after.
- Respect a manual "off": a trigger shouldn't immediately fight the person.

## What we won't copy, and what we'll do better

- Not copying: names, icons (Lungo's cup artwork, Amphetamine's pill), wording, the More
  submenu's links, icon sets, upsells, sounds.
- Better than Lungo: triggers, Until…, custom durations, While App Is Running and a low-battery
  rule built in, no Shortcuts workarounds needed; a HUD confirms the global shortcut.
- Better than Amphetamine: a short menu with no nested Minutes/Hours submenus; settings in
  four small tabs instead of a large preferences window; triggers resume on their own after
  battery rules; nothing to install for closed-lid tricks; no polling.

## Edge cases

- Sleep/wake: timers don't count sleep; Awake re-checks on `didWakeNotification` (tested).
- Assertion fails: error shown in the menu, session cleared, triggers paused (no retry loop; tested).
- Desktop Macs: battery options disabled with a note; power trigger is effectively "always".
- Screen locked with "Allow sleep while locked": assertion released, session keeps its clock
  and resumes on unlock (tested; verified live with the screen locked).
- App quits during "While App Is Running": "Turned off: Xcode quit" until the next session.
- Until a time already past: picks tomorrow (next occurrence; tested).
- Icon hidden: the global shortcut and HUD still work; reopening Awake shows the icon.
- Many running apps: the While App Is Running submenu is sorted by name.

## Our v1 scope (after the parity pass)

- [x] Click to toggle, right/⌃/⌥-click for the menu, swappable
- [x] Presets, Custom Duration…, Until…, While App Is Running, Add 30 Minutes
- [x] Default duration, turn on when Awake opens
- [x] Allow display sleep (menu + Settings), allow sleep while locked
- [x] Global shortcut with HUD
- [x] Triggers: app running, power adapter, external display; master switch; manual-off pause
- [x] Battery: switch-to-battery and low-battery rules
- [x] Time left next to the icon, dim icon while off
- [x] URL scheme
- [x] Settings: General, Triggers, Shortcuts, Advanced, About

## Decisions (made autonomously)

1. **Left click toggles by default** (the owner's brief; Lungo's most-used setting). Right-click,
   Control-click and Option-click open the menu; a tooltip says so; Settings swaps them. An
   Accessibility press opens the menu so VoiceOver users reach every action.
2. **AppKit `NSStatusItem` instead of `MenuBarExtra`**: SwiftUI's can't tell left from right
   clicks. The menu is an `NSMenu` built from a tested, AppKit-free `MenuContent` model and
   ends with the same Settings…/About/Quit footer as SlopKit's `MenuFooter`.
3. **Preset list** follows Lungo's spread (Indefinitely first, 10 min to 12 hours) instead of
   Amphetamine's nested Minutes/Hours submenus: one level, one click.
4. **One "Keep Awake" window for Custom Duration… and Until…** (For | Until), not two dialogs.
5. **Triggers are state-based** and a manual Turn Off pauses them until every active condition
   clears. Battery rules block triggers while they apply and lift by themselves when plugged in.
6. **Low battery fires on crossing the threshold**; starting a session again while low is
   treated as an override and isn't ended until the next crossing.
7. **No default global shortcut** (like Lungo): every obvious combo is taken somewhere.
8. **URL scheme instead of App Intents** for now: SwiftPM bundles don't get the App Intents
   metadata `bundle.sh` would need to generate; `open "slopawake://…"` works from Shortcuts.
9. **Scheme name `slopawake`**, not `awake`, to avoid colliding with other apps.

## Open questions

None blocking. Owner may want a default global shortcut (Lungo suggests ⌃⌘L).

## Sources

- https://sindresorhus.com/lungo (features, FAQ, URL scheme, screenshot)
- https://apps.apple.com/app/id1263070803 (Lungo App Store: settings, release notes)
- https://setapp.com/apps/lungo (Setapp listing and three screenshots: idle menu, active menu, settings tabs)
- https://apps.apple.com/us/app/amphetamine/id937984704 (Amphetamine features, triggers, options)
- https://mac.softpedia.com/get/Utilities/Amphetamine.shtml (click behaviour)

## Parity pass (2026-11-03)

Brief: make Awake work like the originals (Lungo's click-to-toggle + right-click menu,
Amphetamine's richer menu) and add the missing everyday features.

### Gap table

| Item | Before | After |
|---|---|---|
| Click icon toggles; right/⌥-click menu | menu only (`MenuBarExtra`) | done (`NSStatusItem`) |
| Presets | 15m, 1h, 2h, 4h, until off | Indefinitely, 10m, 30m, 1h, 2h, 4h, 8h, 12h |
| Until a time | missing | done (Keep Awake window) |
| Custom duration | env var only | done (Keep Awake window) |
| While App Is Running | missing | done (submenu, ends on quit, reason shown) |
| Add time to a session | missing | done ("Add 30 Minutes") |
| Default duration | missing | done |
| Activate at launch | env var only | done (setting) |
| Global shortcut | missing | done (+ HUD; shown on the Turn On/Off item) |
| Allow display sleep | menu toggle "Keep Display On" | menu "Allow Display Sleep" + Settings (same key, migrated) |
| Allow sleep while locked | missing | done |
| Switch-to-battery / low-battery rules | missing | done |
| Triggers: app, power adapter, external display | missing | done, with master switch and manual-off pause |
| Dim icon / time next to icon | missing | done |
| URL scheme | missing | done |
| Settings tabs | General, About | General, Triggers, Shortcuts, Advanced, About |
| App Intents (Shortcuts actions) | — | deferred: ~0.5 day, needs `bundle.sh` to run the App Intents metadata processor (outside this app's files) |
| App trigger "frontmost only" | — | deferred: ~1 hr (NSWorkspace activation notifications + a per-app toggle) |
| USB/Bluetooth device trigger | — | deferred: ~0.5 day (IOKit matching notifications, a device picker) |
| Wi-Fi network trigger | — | deferred: ~0.5 day, and reading the SSID needs Location Services permission on macOS 14+ |
| Battery charging/above-level, CPU, idle, audio, volume, VPN triggers | — | deferred: ~1–2 hr each; low everyday value |
| While a file is downloading | — | deferred: ~0.5 day (watch a file/folder until its size settles) |
| Allow screen saver | — | deferred: ~2 hr, needs research into which assertion lets the screen saver start |
| Session statistics | — | deferred: ~0.5 day, low value |
| Drive Alive | — | deferred: ~0.5 day (periodic tiny writes to chosen volumes) |
| End-of-session notification/sound | — | deferred: ~2 hr; needs notification permission, against "quiet by default" |
| Closed-display mode, cursor mover, lock-after-idle, icon sets, CLI, AppleScript | — | skipped (reasons in the inventory) |

### Deviations from the design system

- `NSStatusItem` + `NSMenu` instead of `MenuBarExtra` + SlopKit `MenuFooter` (the footer is
  rebuilt as identical NSMenu items) so left and right clicks can differ.
- Settings uses its own `TabView` built from SlopKit pieces (`GeneralSettingsTab`,
  `SettingsForm`, `ShortcutRow`, `AboutSettingsTab`) because `SlopSettings` has no slot for a
  Triggers tab. Order: General, Triggers, Shortcuts, Advanced, About.
- `SettingsOpener` (also in Dropper and Zones) opens Settings from AppKit code; it falls back
  to SwiftUI's own Settings menu item before any SwiftUI view has appeared. Candidate for SlopKit.

### Build notes and gates (2026-11-03)

- `scripts/check.sh Awake --perf`: all green. 71 tests in 9 suites. Launch 121 ms, first
  status item 229 ms, idle CPU 0.002% (lowest) / 0.021% (median), footprint 22.3 MB.
- Real effects with `pmset -g assertions` on the release build (on AC, external 5K display
  attached, screen locked):
  - `AWAKE_ACTIVATE=10m` → `PreventUserIdleDisplaySleep "Awake is keeping this Mac awake"`.
  - URL scheme on the running instance (same pid): deactivate → gone; activate?minutes=5 → back;
    toggle → gone; activate?until=23:59 → back.
  - Allow display sleep → `PreventUserIdleSystemSleep` instead.
  - Power adapter trigger with no session → held; `slopawake://deactivate` → released (paused).
  - App trigger (Finder) → held; same with triggers switched off → none.
  - External display trigger → held.
  - Turn on when Awake opens (default 1 h) → held.
  - Allow sleep while locked, screen locked → none; without the option → held.
  - Quit → released.
- `AWAKE_SELFTEST=1` on the release build: 26/26 PASS (status button label and tooltip, left
  click toggles with the default duration, right/Option-click → menu, swap setting, the real
  NSMenu's items and actions: 30 Minutes, time left, checkmark, Add 30 Minutes, Allow Display
  Sleep, Turn Off; Set Up Triggers… opens Settings on Triggers; Until… opens the Keep Awake
  window; time next to the icon appears and clears).
- Offscreen renders (`AWAKE_SNAPSHOT_DIR`), looked at: `/tmp/awake-parity/renders/`
  `settings-{general,triggers,shortcuts,advanced,about}-{light,dark}.png`,
  `keep-awake-{for,until}-{light,dark}.png`, `menubar-icons-{light,dark}.png`, `menus.txt`
  (menu text for idle, 2 hours, until, while TextEdit runs, trigger holding, low battery).
  Fixed from review: section footers were trailing-aligned. The dark renders show the tab
  strip blank: an offscreen artifact of the segmented `TabView` (the real Settings window
  uses toolbar tabs); check on screen.
- Tests no longer leave preference files: suites use path-based defaults under
  `/tmp/awake-test/defaults` and delete them.

### Owed on-screen checks (screen was locked during this pass)

1. `scripts/drive` walkthrough of the release build: left click toggles (icon fills/empties),
   right-click and Control/Option-click open the menu, menu looks right in light and dark.
2. `scripts/drive tree`: no `[unlabeled]` controls in the menu, Settings tabs and the Keep
   Awake window.
3. Settings window: toolbar tabs in dark mode, Triggers tab Add App menu and "Choose from
   Applications…" panel, remove buttons.
4. Global shortcut: record one in Settings › Shortcuts, press it from another app (owner-idle
   gate), HUD appears, icon changes.
5. Keep Awake window: focus, Return/Esc, stepper and time field editing.
6. Time next to the icon in the real menu bar (spacing, monospaced digits), dimmed icon.

## Polish pass (2026-11-05)

Brief: `docs/polish-pass.md` (plus the mid-pass Golden Gate / light-dark addition). Shots in
`/tmp/slopapp-polish/awake/` (`before/`, `after/`, offscreen `render-before/`, `render-after/`).
All on-screen shots use `AWAKE_DEMO=1` (fake apps and battery, no-op power assertion) and a
throwaway `AWAKE_DEFAULTS_SUITE`; the owner's `app.slopapp.awake` domain was backed up to
`defaults-backup.plist` first and restored at the end.

### Environment finding

On this Mac (macOS 27.2, built-in 1728 pt display) the system hides Awake's status item: the
menu bar is full and `NSStatusItem VisibleCC Item-0` is 0 (macOS rewrites it to 0 if changed).
`scripts/drive menubar` can't reach it, so menu shots use a new review hook that pops the real
status-item menu up under the menu bar (`AWAKE_SHOW=menu`), and the icon is checked on the
offscreen renders. The same situation made Awake unreachable for a real user, fixed below (13).

### Defects and fixes (before → after)

| # | Surface | Before | After |
|---|---|---|---|
| 1 | Lint | 1 corner literal (`Snapshots.swift:131`, radius 5), 2 spacing literals (4, 8) | 0: `Radius.s`, `Spacing.xs`, `Spacing.s` |
| 2 | Menu status line ("2 hr left") | disabled item, `#6A6A6A` on `#2A2A2A` = 2.7:1 (AppKit dims disabled titles whatever their attributed colour) | custom view in `.secondary`: `#A8A8A8` = 6.0:1 dark, `#555555` ≈ 6:1 light; leading edge on the title column (30 pt inset with checkmarks, 16 without), 24 pt row like the items |
| 3 | Menu status line | built once at open; stale while open | observes the controller: one open menu went "2 min left" → "Less than a minute left" (`after/menu-live-t3.png`, `menu-live-t33.png`); `.monospacedDigit()` |
| 4 | Menu error line (IOKit failure) | same 2.7:1 disabled grey | same readable view (new `MenuEntry.error`, tested) |
| 5 | Menu bar time | `systemFontSize` | `NSFont.menuBarFont` size with fixed-width digits (13 pt on 27.2, follows the OS) |
| 6 | Shortcut HUD | "Awake: On until turned off", "Awake: On until 9:30 PM, 1 hr 17 min left" | "Awake is on", "Awake is on until 9:30 PM", "Awake is on while Xcode is running", "Awake is off" (`confirmationText`, tested) |
| 7 | Keep Awake window | caption → buttons 21 pt (a `minHeight: 52` slot) vs 16 pt elsewhere; 204 pt tall | 16 pt, every gap on `Spacing` (20 top, 16, 8, 16, 20 bottom); 199 pt |
| 8 | Keep Awake window | caption 4 pt higher in Until than in For (date field is shorter) | rows share one slot (`ZStack`), caption at the same y in both (127 pt); hidden row disabled so Tab can't reach it |
| 9 | Keep Awake window | "Ends at…" / "Today, in…" frozen at open | `TimelineView(.everyMinute)` |
| 10 | Keep Awake window | re-centred on every open | centred the first time only |
| 11 | Settings › General | click explanation as a separate caption row | subtitle under its picker; tab 372 → 340 pt tall |
| 12 | Settings › Advanced | display-sleep explanation as a section footer | subtitles under "Allow display to sleep" and "Allow sleep while the screen is locked" |
| 13 | Opening Awake again | only set `showMenuBarIcon` (already true): with the icon hidden by macOS there was no way in | also opens Settings (`applicationShouldHandleReopen`), README says so |
| 14 | Settings › Advanced (desktop Mac) | "no battery" note inside the disabled section, dimmed | section footer outside the disabled group, full secondary contrast (`after/settings-advanced-desktop-*.png`) |
| 15 | Settings › Triggers | "Running" baseline 1.5 pt above the app name's | shared baseline (both 15.0 pt down the row); long names truncate, "Running" never does |
| 16 | Settings › Triggers | "Add App" borderless menu indented to 42 pt while row content starts at 30 pt | trailing pop-down button like every other trailing control (chevron lines up with the pickers') |
| 17 | Offscreen icon strip | "Off, dim…" truncated; system font | full caption; menu bar font |

### Golden Gate + light/dark

- **Menus are text only.** The status menu's only images are the app icons in While App Is
  Running (information) and state checkmarks. No decorative symbols to remove.
- **No custom sidebars, toolbars or glass**: Settings uses the system's toolbar tabs; the menu
  and HUD are system materials (NSMenu, SlopKit `HUD`). No hex colours, no pure black/white,
  no layers, no images other than template SF Symbols and app icons.
- **Inactive windows**: Settings' selected tab and the Keep Awake window's segment and default
  button go grey when not key (`after/inactive-settings-*.png`, `after/inactive-until-*-1.png`).
- **Light and dark**: every surface shot in both (`after/*-light.png` / `*-dark.png`):
  menu (on, trigger holding), Keep Awake (For, Until, inactive), Settings (every tab, empty
  triggers, desktop Advanced), HUD; icon states offscreen (`render-after/menubar-icons-*.png`,
  template image, off/on/dimmed/time). The new status line resolves `.secondary` per
  appearance (measured in both).

### Gates

- `scripts/lint.sh Awake`: clean. `scripts/check.sh Awake --perf`: all green, 73 tests in
  9 suites; launch 148 ms, first status item 266 ms, idle CPU 0.014% (lowest), 22.5 MB.
- `scripts/drive tree`: 0 `[unlabeled]` on every Settings tab and both Keep Awake modes;
  close buttons 16×16.
- `AWAKE_SELFTEST=1`: 26/26 PASS.
- Real effect: `AWAKE_ACTIVATE=2m` → `PreventUserIdleDisplaySleep "Awake is keeping this Mac
  awake"`; `slopawake://deactivate` → gone; `slopawake://activate?minutes=1` → back; quit →
  gone. `pmset -g assertions` shows nothing from Awake at the end.

### Not done

- **Real status item on screen** (click to toggle, right-click, icon in a real light/dark/tinted
  menu bar, time beside it): macOS hides the item here (menu bar full, `VisibleCC` 0). Checked on
  offscreen renders and with the popped-up menu instead. Owed when the menu bar has room.
- **"macOS is hiding the icon" note in Settings**: deferred. The status window's
  `occlusionState` reports hidden here, but the visible case can't be confirmed on this Mac, and
  a false warning would be worse than none. Reopen → Settings (13) covers the way back in.
- **Hover/pressed** on menu items and the remove buttons: system-drawn, not checkable without
  the real pointer (owner present). **While App Is Running submenu** not shot (needs keyboard
  navigation inside a popped-up menu while the owner is active).
- **Global shortcut pressed for real**: not tested (recording one writes the owner's defaults
  and pressing it needs `key --global` with the owner away); the HUD was checked with
  `AWAKE_SHOW=hud`.

### New review hooks

`AWAKE_DEMO=1` (+ `AWAKE_DEMO_BATTERY=15|none`, `AWAKE_DEMO_AC=1`) and
`AWAKE_SHOW=menu|until|duration|settings[:tab]|about|hud` (comma-separated), in
`Sources/Awake/ReviewHooks.swift`, documented in the README.

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.
