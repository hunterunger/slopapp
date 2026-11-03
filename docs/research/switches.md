# Switches research (inspired by One Switch)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md) on 2026-11-03.
> Studied: **One Switch** (Fireball Studio; Setapp, 1.35.x per reviews) through its product
> page, Setapp listing and ~20 Setapp reviews, and write-ups by The Sweet Setup, iMore,
> ifun.de and Product Hunt. One Switch is **not installed** on this Mac, so nothing was
> explored live. The open-source **OnlySwitch** (41 switches, README notes on which need
> private APIs or a privileged helper) was used to judge feasibility. Feasibility of our
> chosen switches was checked read-only on this Mac (macOS 27.2): the System Events
> scripting dictionary exposes `dark mode`, Dock `autohide`, `autohide menu bar`,
> `magnification` and `show recents`; `/usr/bin/shortcuts` and `/usr/bin/pmset` are present.
> Nothing was toggled. We never copy its name, icons, artwork, wording, sounds or signature
> visuals.

## The job

A handful of Mac settings get flipped often but live three clicks deep in System Settings
or behind a Terminal `defaults` command: dark mode, desktop icons before a screen share,
hidden files for a dotfile, Dock auto-hide on a small screen, keeping the Mac awake during a
download, muting the mic. Done feels like: click the menu bar icon, flip the switch, it
applies instantly, and flipping it back restores exactly what was there.

**The one interaction that matters: click the menu bar icon → a short list of named
switches with their current state → click one → the setting changes now (and the checkmark
proves it).**

## Who and when

- Before a screen share or recording: hide desktop icons, mute the mic.
- Evening: dark mode on; or toggling to check a UI in both appearances.
- A developer showing hidden files for a moment to find `.env`, then hiding them again.
- On a laptop screen: auto-hide the Dock (and menu bar) for more room.
- Keeping the Mac awake through a long download or presentation.
- Frequency: a few times a day; each use one click.

## Feasibility (the deciding table)

Rule: public API, a documented `defaults` key, or the System Events scripting dictionary,
no admin, every switch reversible to the exact prior value. Private frameworks, privileged
helpers and destructive actions are skipped.

| Switch | Mechanism | Needs | Reversible | Verdict |
|---|---|---|---|---|
| Dark Mode | System Events `appearance preferences` → `dark mode` | Automation (System Events) | yes | **must** |
| Hide Desktop Icons | `com.apple.finder CreateDesktop` = false, then quit + relaunch Finder | none | yes (delete key → default) | **must** |
| Show Hidden Files | `com.apple.finder AppleShowAllFiles` = true, then relaunch Finder | none | yes | **must** |
| Auto-hide Dock | System Events `dock preferences` → `autohide` (applies live) | Automation | yes | **must** |
| Keep Awake | `IOPMAssertionCreateWithName` (same as Awake / `caffeinate`) | none | yes (release) | **must** |
| Mute Microphone | CoreAudio default input `kAudioDevicePropertyMute`; fallback: input volume 0, remember previous | none | yes | **must** |
| Auto-hide Menu Bar | System Events `dock preferences` → `autohide menu bar` | Automation | yes | should |
| Show File Extensions | global `AppleShowAllExtensions`, relaunch Finder | none | yes | should |
| Mute Sound | CoreAudio default output mute | none | yes | should |
| Start Screen Saver | open `/System/Library/CoreServices/ScreenSaverEngine.app` | none | action (n/a) | should |
| Sleep Display | `pmset displaysleepnow` (no sudo) | none | action (n/a) | should |
| Focus / Do Not Disturb | run the user's own Shortcut (`shortcuts run`), one for on, one for off | user's shortcuts | yes, if both set | should |
| Dock magnification, show recents | System Events `dock preferences` | Automation | yes | later |
| Screen resolution | `CGDisplayCopyAllDisplayModes` / `CGConfigureDisplayWithDisplayMode` | none | yes | later |
| Connect AirPods / headphones | IOBluetooth `IOBluetoothDevice.openConnection()` on a paired device | Bluetooth permission | yes | later |
| Eject all disks | `NSWorkspace.unmountAndEjectDevice` | none | no (action) | later |
| Screen cleaning mode | black full-screen window on all displays; full key blocking needs an event tap | Accessibility for full lock | n/a | later |
| Wi-Fi on/off | CoreWLAN `CWInterface.setPower` | none | yes, but can cut connectivity | later |
| Hide desktop widgets | `com.apple.WindowManager StandardHideWidgets` | unverified live apply | yes | later (verify) |
| Night Shift, True Tone | private CoreBrightness | private API | — | **skip** |
| Bluetooth power | private IOBluetooth preference call | private API | — | **skip** |
| Lock Screen (immediate) | private login framework, or synthesized ⌃⌘Q (Accessibility) | private / Accessibility | — | **skip** (Sleep Display covers most uses) |
| Low Power Mode | `pmset lowpowermode` | admin | — | **skip** |
| Natural scrolling | global default needs a private call to apply live | private API | — | **skip** |
| Empty Trash | Finder AppleScript | Automation for Finder, destructive | no | **skip** (not reversible; reviews show the permission loop) |
| Hide notch | replaces the wallpaper with a black-topped copy | changes user wallpaper | fragile | **skip** |
| Lock keyboard | event tap swallowing keys | Accessibility | yes | later |
| Brightness, key backlight | private DisplayServices/CoreBrightness | private API | — | **skip** |

## Feature inventory

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Menu of switches with live state | Menu bar dropdown with switch controls | must | `.menu` style, toggles as checkmark items, each with an SF Symbol. |
| 2 | The six must switches above | ~18–23 switches | must | |
| 3 | Show/hide individual switches | Preferences ▸ Customize | must | Settings ▸ Switches: checkbox per switch. Defaults: the six musts visible. |
| 4 | Reorder switches | Not confirmed | should | Drag in Settings list. |
| 5 | Per-switch global shortcut | Any switch can have a hotkey | should | `ShortcutRow` per switch, all unset. |
| 6 | Changeable menu bar icon | Option | skip | One symbol; state shown in the menu. |
| 7 | Dark mode on a schedule (sunset/sunrise) | Option | skip | macOS has Auto appearance built in. |
| 8 | DND schedule | Option | skip | macOS Focus schedules exist. |
| 9 | Keep Awake "until" options | Basic toggle | should | Off after 1 h / 2 h / until turned off; reuse Awake's approach. |
| 10 | Actions (screen saver, sleep display) | Mixed in with switches | should | Shown in a separate "Actions" group as buttons, not toggles. |
| 11 | "Switch store" / custom scripts | Planned by the developer | skip | Arbitrary scripts conflict with "look, don't touch" safety. |
| 12 | Widgets / Shortcuts actions | OnlySwitch has Shortcuts actions | later | App Intents "Set Switch" later. |

## Key flows

### Flow 1: flip a switch
1. Click the icon (a toggle symbol; `.fill` when any switch is on).
2. The menu reads every switch's state as it opens (no polling): checkmarks for on.
3. Click **Hide Desktop Icons**. Finder relaunches (its windows reopen); the item now has a
   checkmark. Clicking again restores the previous value.
4. External changes (the user flips dark mode in System Settings) are reflected the next
   time the menu opens; dark mode also listens to the distributed appearance notification.

### Flow 2: first time a switch needs Automation
1. First click on Dark Mode / Auto-hide Dock: macOS asks to let Switches control System
   Events (we include `NSAppleEventsUsageDescription`: one sentence).
2. Allowed: the switch applies. Denied: the item shows "Needs permission" and opens a small
   `PermissionGate` sheet with **Open Automation Settings**; status re-checked live via
   `AEDeterminePermissionToAutomateTarget` (no prompt) when the menu opens.

### Flow 3: first run
1. Icon appears; no window. Menu shows the six default switches with current state.
2. First use of a Finder-restart switch shows a one-time note: "Finder restarts to apply
   this. Its windows reopen." with **Continue** / **Cancel**.

## Reversibility and testing (must)

- Each switch implements `read() -> State`, `apply(State)`, and `snapshot()/restore()`.
  For `defaults`-backed switches, the snapshot remembers whether the key existed: restoring
  a key that wasn't there **deletes** it rather than writing the default value.
- All system effects go through a `SystemCommander` protocol (run AppleScript, read/write
  defaults, relaunch app, CoreAudio set/get, power assertion, run process). A
  `DryRunCommander` records the exact commands and changes nothing. Unit tests assert the
  command list per switch and the restore list (e.g. "turn on hidden files then restore
  when the key was absent" → `delete AppleShowAllFiles` + relaunch).
- `--dry-run` launch argument / `SWITCHES_DRY_RUN=1`: full UI, state simulated in memory,
  actions printed to stdout. Smoke tests and blind tests use this.
- Live tests are **opt-in** (`SWITCHES_LIVE_TESTS=1`) because they change the shared Mac
  that other agents use (dark mode and Dock changes affect their screenshots). Each live
  test snapshots in `setUp`, restores in `tearDown` and in a crash-safe way (restore file
  written before applying; a leftover file is restored on next launch of the test runner).
  The safe-by-default live subset: Keep Awake (assertion visible in `pmset -g assertions`),
  Mute Microphone and Mute Sound (restored values compared).
- The app itself also writes a small "applied by Switches" record so it never "restores"
  something the user changed by hand later.

## Settings inventory

| Setting | Default | Options | Keep? |
|---|---|---|---|
| Visible switches | the six musts | checkbox per switch | must |
| Order | as listed | drag | should |
| Per-switch shortcut | unset | recorder | should |
| Keep Awake duration | until turned off | 1 h, 2 h, 4 h | should |
| Focus on / off shortcuts | none | shortcut names | should |
| Launch at login, Show in menu bar | off / on | | v1 (standard) |

## Menus and shortcuts

Status menu (`.menu`): switches group (toggles) → divider → Actions (Start Screen Saver,
Sleep Display; should) → `MenuFooter` (Settings… ⌘, · About · Quit ⌘Q). In-menu number keys
1–9 toggle the first nine switches while the menu is open (should). No global shortcuts by
default.

## Permissions and system integration

- **Automation → System Events** (dark mode, Dock, menu bar): asked on first use of such a
  switch only. Other switches work without it.
- **Bluetooth** (later, AirPods), **Accessibility** (later, keyboard lock): not in v1.
- No admin, no helper tool, no network. Not sandboxed (direct distribution).
- `defaults` writes use `CFPreferencesSetValue` for the target domain (+ synchronize), not
  shelling out, except where a relaunch is needed.

## UX patterns worth adopting

- One flat list, current state visible, one click per change.
- Hiding unused switches keeps the menu short (reviewers like that).
- Separate actions (one-shot) from switches (stateful).

## What we won't copy, and what we'll do better

- Not copying: name, icon, switch artwork, wording, switch store.
- Better: no switch that needs a private API, so updates don't break them (a December 2025
  review says dark mode and Dock toggles stopped working); clear permission status instead
  of the "keeps asking for Automation but isn't listed" loop reviewers hit; exact restore of
  prior values; every switch reads real system state rather than remembering its own.

## Edge cases

- User changes the setting elsewhere: menu reads live state on open.
- Finder relaunch while a Finder copy is running: verify during build whether a polite quit
  waits; if not, warn before relaunching when Finder has an active copy window, or document.
- Multiple input devices: mute applies to the current default input; switching default
  device updates the state.
- Devices without mute support: fallback to volume 0 and restore exact previous volume.
- Keep Awake across sleep/lid close (assertion doesn't prevent lid-close sleep; say so).
- Automation revoked mid-session: next toggle shows "Needs permission".
- Quit while switches are on: they stay as set (they're system settings), except Keep Awake
  which ends with the app (stated in its subtitle).
- Dark/light menu rendering, VoiceOver "Dark Mode, on".

## Our v1 scope

- [ ] Menu bar menu lists the six switches with live state: Dark Mode, Hide Desktop Icons,
      Show Hidden Files, Auto-hide Dock, Keep Awake, Mute Microphone.
- [ ] Each switch applies instantly and restores the exact previous value (deleting keys
      that didn't exist).
- [ ] Automation permission asked only on first use of a System Events switch; denial
      handled with a working System Settings link and live re-check.
- [ ] One-time note before the first Finder relaunch.
- [ ] Settings: General (launch at login, show in menu bar), Switches (show/hide), About.
- [ ] `SystemCommander` + `DryRunCommander`; unit tests per switch for apply and restore
      commands; `--dry-run` mode for smoke/blind tests; live tests opt-in and self-restoring.

Should: Auto-hide Menu Bar, Show File Extensions, Mute Sound, Keep Awake durations,
Focus via Shortcuts, Start Screen Saver / Sleep Display actions, reorder, per-switch
shortcuts, number keys in menu.

## Open questions → owner-default decisions (2026-11-03)

1. **Private APIs**: none. Night Shift, True Tone, Bluetooth power, immediate lock,
   brightness are skipped even though rivals have them.
2. **Hide Desktop Icons method**: Finder `CreateDesktop` + relaunch (reliable, matches
   System Settings behaviour), not a wallpaper-covering overlay window (breaks with
   per-Space and dynamic wallpapers and covers desktop widgets).
3. **Keep Awake overlap with Awake**: include it (it's the most-praised One Switch toggle);
   move Awake's `PowerAssertion` into SlopKit so both apps share one implementation.
4. **Destructive/irreversible actions** (Empty Trash, Eject): not in v1.
5. **Live tests**: opt-in only, because the test Mac is shared with other agents.

## Sources

- [One Switch product page](https://fireball.studio/oneswitch)
- [One Switch on Setapp](https://setapp.com/apps/one-switch) and [reviews](https://setapp.com/apps/one-switch/customer-reviews)
- [The Sweet Setup: One Switch](https://thesweetsetup.com/one-switch-is-the-menu-bar-app-for-quickly-toggling-tedious-settings/)
- [iMore: One Switch](https://www.imore.com/one-switch-makes-it-quicker-toggle-just-about-any-setting-your-mac)
- [ifun.de: One Switch mutes the mic](https://www.ifun.de/mac-multischalter-one-switch-schaltet-auch-das-mikro-stumm-157507/)
- [One Switch on a menu bar app directory](https://onmymenubar-app.pages.dev/one-switch)
- [Product Hunt: One Switch](https://producthunt.com/posts/one-switch)
- [OnlySwitch README (open source, feasibility notes)](https://cdn.jsdelivr.net/gh/jacklandrin/onlyswitch@main/README.md)

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.
