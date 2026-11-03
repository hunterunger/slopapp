# Quit research (inspired by QuitAll)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md) on 2026-11-03.
> Studied: **QuitAll 1.3.6** (Setapp listing) through its Setapp page, Setapp reviews,
> AlternativeTo and a third-party menu bar app directory. QuitAll is **not installed** on
> this Mac and has no public help center, so nothing was explored live; its exact menu and
> settings are unverified. Same-job apps used for patterns: Quit All Apps (App Store), MacQuit
> (never-quit list, ⌥ = force quit), Quitter (per-app idle timers). We study how it works so
> we don't reinvent the wheel. We never copy its name, icons, artwork, wording, sounds or
> signature visuals.

## The job

Before a screen share, a presentation, a game, a heavy build, or at the end of the day,
someone wants a clean slate: every app closed except the few they always keep (their
browser, their terminal), with nothing lost. Doing it by hand is ⌘Tab-⌘Q twenty times.
Done feels like: one click, the Dock empties down to the keepers, and any app with unsaved
work asks about it instead of losing it.

**The one interaction that matters: click the menu bar icon → the list of running apps is
already ticked (minus the keepers) → Return → they quit; anything waiting on a save dialog
is named so you can deal with it.**

## Who and when

- Starting a screen share or recording: close everything personal.
- Freeing memory before a big build, a game or video export.
- End of day, before closing the lid.
- Quitting one stuck app (force quit) without opening the system Force Quit window.
- Frequency: once or twice a day, a few seconds each.

## Feature inventory

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Quit all running apps | One click in the menu bar helper | must | Regular (Dock) apps only, minus keepers and the hard denylist. |
| 2 | Select which apps to quit | Pick apps in the list | must | Checklist; keepers start unticked. |
| 3 | Keep list (never quit) | Pin apps to keep (per Setapp how-to; others call it a never-quit list) | must | Per-app "Always Keep" toggle; stored by bundle ID. |
| 4 | Respect unsaved work | Apps ask to save before quitting | must | Polite quit only (`NSRunningApplication.terminate()`); report apps still running after a wait. Never auto-force. |
| 5 | Force quit | Switch Quit → Force Quit; one or several | should | Per-app only, explicit, with a confirmation that names the app and warns about unsaved work. Not in bulk in v1. |
| 6 | Background / menu bar apps | "View background apps", quit or keep them | should | Separate section, off by default ("Include menu bar apps"). |
| 7 | Live CPU / memory per app | Shown in the list (directory listing) | later | Needs `proc_pid_rusage` sampling; costs CPU while open. |
| 8 | Auto-quit inactive apps after N minutes | Configurable timer (e.g. 15 min) | later | Off-by-default feature with real risk; v1.1 at the earliest. |
| 9 | Global shortcut | Customizable | should | "Quit All" and "Show Menu". Unset by default. |
| 10 | Default quit behaviour | Setting | skip | We always quit politely; force is per-app. |
| 11 | Sound effects | Optional sounds | skip | Quiet by default. |
| 12 | Dark mode | Follows system | must (free) | System materials. |
| 13 | Hide instead of quit | Asked for on Reddit (unanswered) | should | "Hide Others" (⌥ alternative). Cheap and reversible. |
| 14 | Reopen what was just quit | Not offered | should | "Reopen 7 Apps" after a Quit All: our undo. |
| 15 | Quit Others (all but frontmost) | Not confirmed | should | Common need while presenting. |

## Safety model (must, unit-tested)

**Candidates** = `NSWorkspace.shared.runningApplications` where:
- `activationPolicy == .regular` (or `.accessory` only when "Include menu bar apps" is on);
- `processIdentifier != getpid()` and bundle ID is not Quit's own;
- the app is **not** on the hard denylist: `com.apple.finder`, `com.apple.loginwindow`,
  `com.apple.dock`, `com.apple.systemuiserver`, `com.apple.controlcenter`,
  `com.apple.notificationcenterui`, `com.apple.WindowManager`, `com.apple.Spotlight`;
- the bundle URL is **not** under `/System/Library/CoreServices/` or `/usr/` or
  `/System/Library/` (catches Finder and anything system-level we didn't name);
- the app has a bundle identifier (no anonymous processes) and belongs to this user
  session (NSWorkspace guarantees this);
- **not** on the user's keep list.

**Quitting**
1. Call `terminate()` on each target (in parallel). This is the same polite quit as ⌘Q: apps
   with unsaved changes show their own save prompt; apps with autosave/Versions keep their
   documents.
2. Watch `NSWorkspace.didTerminateApplicationNotification` (no polling) for up to 10 s.
3. Apps still running after 10 s are listed in the menu: "Pages is waiting (maybe for a save
   dialog)" with **Show** (activates it) and **Force Quit…** (confirmation).
4. Never call `forceTerminate()` without an explicit per-app confirmation.
5. Record what was quit (bundle URLs) for **Reopen**; cleared after an hour or the next
   Quit All.

**Dry-run and test mode (must)**
- An `AppTerminator` protocol: `RealTerminator` (NSRunningApplication) and
  `DryRunTerminator` (records targets, terminates nothing). Unit tests use the fake and a
  fake app list covering every denylist rule.
- `--dry-run` launch argument (and `QUIT_DRY_RUN=1`): the full UI works; the result line says
  "Dry run: would quit 7 apps" and logs the names to stdout. Smoke tests always use it.
- `SLOPAPP_TEST_MODE=1`: candidates are restricted to bundle IDs starting with
  `dev.slopapp.quit.fixture.` regardless of anything else, so even a real (non-dry) run in
  tests can only touch fixture apps. Integration tests build 2–3 tiny fixture apps: one that
  quits normally, one whose `applicationShouldTerminate` returns `.terminateCancel` (stands
  in for "unsaved document"), one that hangs (for the Force Quit path, confirmed by the test).
- Tests never target TextEdit, Finder or any real app.

## Key flows

### Flow 1: quit everything but the keepers
1. Click the menu bar icon. A `.window`-style panel (320 pt) shows "7 apps running", then a
   list: app icon, name, checkbox (ticked unless kept; kept apps show a pin and are
   unticked). Focus starts on **Quit 6 Apps**.
2. Return (or click). Checked apps quit politely. The button turns into a progress line.
3. Within ~1 s most are gone. If any remain after 10 s: a row per app with Show / Force
   Quit…. Otherwise: "Quit 6 apps" + **Reopen** for an hour.

### Flow 2: keep an app forever
1. Right-click (or ⌘K on the focused row) → **Always Keep**. The row gets a pin and stays
   unticked in future. Settings ▸ Keep lists them with remove buttons.

### Flow 3: first run
1. Icon appears; no window, no tour. First open of the panel shows the list with nothing
   kept and a one-line hint: "Pin apps you never want to quit."
2. No permission is asked (polite quit of other apps needs none; verify on macOS 14–27 during
   build; if an Automation prompt does appear, the app must handle denial with a clear
   message).

## Settings inventory

| Setting | Default | Options | Keep? |
|---|---|---|---|
| Keep list | empty | add/remove apps (+ "Choose App…") | must |
| Include menu bar apps | off | | should |
| Keep the frontmost app | off | | should |
| Wait before reporting stuck apps | 10 s | 5–60 s | v1 (fixed) |
| Global shortcuts (Quit All, Show) | unset | recorder | should |
| Launch at login, Show in menu bar | off / on | | v1 (standard) |

## Menus and shortcuts

Panel: arrows move, Space toggles a row, Return = Quit Selected, ⌘A select all, ⌘K Always
Keep, ⌥ changes the main button to "Hide Selected", Esc closes. Footer: Settings… ⌘, ·
About · Quit ⌘Q. `MenuFooter` labels its last item "Quit <app name>", which would read
"Quit Quit"; see decision 6.

## Permissions and system integration

- None expected. `NSRunningApplication.terminate()` / `hide()` and NSWorkspace
  notifications are public and unprivileged. Not sandboxed (direct distribution).
- App Intents (later): "Quit All Apps", "Quit Apps Except…".

## UX patterns worth adopting

- The list is pre-ticked: the common case is one keystroke.
- Separate, deliberately harder Force Quit (QuitAll marks it distinctly).
- Showing background apps separately keeps menu bar utilities safe by default.

## What we won't copy, and what we'll do better

- Not copying: name, icon, sounds, wording.
- Better: explicit keep list and hard system denylist; reports apps that are waiting on a
  save dialog instead of leaving the user guessing; **Reopen** as undo; Hide as a
  non-destructive alternative; no admin-permission prompts (a noted QuitAll behavior when
  it reaches system apps).

## Edge cases

- App launches or quits while the panel is open: list updates live (notifications).
- Apps in full-screen Spaces; apps on another user session (not visible, never touched).
- Apps that ignore quit (hung): reported, not forced.
- Terminal/iTerm with running processes ask on their own; reported as waiting.
- Apps with the same name (two Xcode versions): show path on hover; keep list by bundle
  ID, plus path for duplicates.
- Quit itself, Finder, system UI never listed even in "include menu bar apps".
- Login items that relaunch themselves after quit: shown again; not our problem, no loop.
- Empty state: "Only Finder is running" with nothing to quit.
- VoiceOver: each row "Safari, will quit" / "Music, kept".

## Our v1 scope

- [ ] Status item opens the panel listing regular running apps with icons and checkboxes.
- [ ] Quit Selected (Return) quits politely; progress and result line.
- [ ] Keep list (Always Keep, Settings list) persisted by bundle ID; kept apps unticked.
- [ ] Hard denylist + CoreServices/system path rule; Quit never lists itself or Finder.
- [ ] Apps still running after 10 s are reported with Show and Force Quit… (confirmed).
- [ ] `--dry-run` mode and `SLOPAPP_TEST_MODE` fixture-only restriction; unit tests for
      every candidate rule; integration tests on fixture apps only.
- [ ] Live list updates; keyboard: arrows, Space, Return, Esc, ⌘A.
- [ ] Settings: General (launch at login, show in menu bar), Keep, About.

Should: Reopen (undo), Hide Selected (⌥), Quit Others, include menu bar apps, global
shortcuts.

## Open questions → owner-default decisions (2026-11-03)

1. **Confirmation before Quit All**: none; polite quit lets apps protect unsaved work, and
   Reopen covers regret. Force Quit always confirms.
2. **Menu bar apps**: excluded by default; opt-in section.
3. **Auto-quit inactive apps**: later (off by default when it comes).
4. **Force Quit in bulk**: no; per-app only.
5. **Panel style**: `.window` style (rich checklist), 320 pt wide, as the design system
   allows for rich content.
6. **Footer label**: "Quit Quit" reads like a bug. Default: add an optional title override
   to `MenuFooter` and label the item plain "Quit" (⌘Q). The main action is always worded
   "Quit N Apps", so the two never look alike.

## Sources

- [QuitAll on Setapp](https://setapp.com/apps/quit-all-mac) and [reviews](https://setapp.com/apps/quit-all-mac/customer-reviews)
- [QuitAll on AlternativeTo](https://alternativeto.net/software/quitall/about)
- [QuitAll in a menu bar app directory](https://onmymenubar-app.pages.dev/quitall)
- [Reddit: can QuitAll hide apps?](https://reddit.birdcat.cafe/r/macapps/comments/1jtfslo/quitall_app_can_it_also_hide_apps/mltzpli/?context=3)
- [Quit All Apps (App Store)](https://apps.apple.com/app/quit-all-apps/id6752781428)
- [MacQuit on Product Hunt](https://www.producthunt.com/posts/macquit)
- [Make Tech Easier: auto-quit after inactivity](https://maketecheasier.com/automatically-quit-hide-apps-mac)

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.
