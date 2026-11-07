# Focus research (inspired by Session)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md) on 2026-11-03.
> Studied: **Session** (Setapp listing shows 2.13.48) through its website, help index
> ("Learn"), App Store and Setapp listings, What's New notes, user reviews and Pomodoro
> round-ups. Session is **not installed** on this Mac, so nothing was explored live; menu
> structure and defaults below come from public sources and are marked where unverified.
> Open-source menu bar timers (TomatoBar, Pomosh) were used for implementation patterns.
> We study how it works so we don't reinvent the wheel. We never copy its name, icons,
> artwork, wording, sounds or signature visuals.

## The job

Someone wants to work on one thing for a fixed stretch without drifting, then take a real
break, and see at the end of the day that they actually did it. They reach for the timer
when they sit down to a task they've been avoiding, or when the day is fragmenting into
Slack and email. Done feels like: one click starts the clock, the menu bar quietly shows how
much is left, a gentle notification says "time for a break", and the menu shows "4 sessions
today".

**The one interaction that matters: click the menu bar icon (or press a shortcut) → Start →
the icon turns into a countdown → at zero a notification announces the break → the break
counts down the same way → the day's count goes up by one.**

## Who and when

- A developer starts a 25-minute block before tackling a bug, ignoring chat until it ends.
- A student alternates 50/10 study blocks for an afternoon, with a longer break every fourth.
- A writer wants proof of effort: "3 h 20 m focused today" matters more than the timer.
- Someone who uses macOS Focus wants Do Not Disturb on only while a session runs.
- Frequency: several times a day; each interaction is 1–3 seconds (start, skip, stop). The
  timer itself runs for 15–60 minutes in the background.

## Feature inventory

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Work timer with set length | Default 25 min; 45 offered as a preset; custom lengths (paid tier) | must | Presets 15/25/45/50 + custom in Settings. Default 25. |
| 2 | Break timer | Short break after each session, prompts to rest | must | Default 5 min. |
| 3 | Remaining time in the menu bar | Small status bar timer (praised in reviews) | must | Text next to the symbol: "18m" by default, "17:42" with *Show seconds*. Idle: symbol only. |
| 4 | Start / pause / resume / stop | From the app window and menu bar | must | All in the status menu with shortcuts. |
| 5 | End-of-phase notification | Notification + sound when a session or break ends | must | `UserNotifications`; system sound; action buttons "Start Break" / "Skip Break". |
| 6 | Daily session count | Daily/weekly analytics, charts, "most productive times" | must (count) / later (charts) | Status line: "Today: 3 sessions · 1 h 15 m". A session counts if ≥ 80% of the planned length ran (configurable later). |
| 7 | Long break every N sessions | Not confirmed on Session; standard in rivals | should | Default 15 min after every 4th session. |
| 8 | Auto-start next phase | Toggle praised in reviews | should | Two toggles: auto-start breaks (on), auto-start next session (off). |
| 9 | Skip break / extend +5 min | End early, extend, keep working past zero | should | "Skip Break", "Add 5 Minutes". |
| 10 | Overtime (keep going past zero) | Reviews mention working past the timer | later | Counting up after zero, adds to the day's total. |
| 11 | Intention/label for the session | "State your focus" text before starting | should | Optional one-line label, shown in the menu, stored in the log. |
| 12 | Categories with colors, per-category calendars | Paid tier limits categories | later | Labels are enough for v1. |
| 13 | Reflection after a session (rating, mood, notes) | Rate distracted/neutral/focused + note | later | Adds a prompt; conflicts with "quiet by default". |
| 14 | Turn on macOS Focus / DND during sessions | Help docs: Apple Focus via Shortcuts, DND automation | should | Run a user-chosen Shortcut at start and at end via `/usr/bin/shortcuts run`. No private Focus API. Off by default. |
| 15 | App/website blocking | Blocks chosen apps and sites (Safari/Chrome/Brave/Edge) during a session | skip | Needs browser automation or a network filter; heavy, intrusive, fragile. |
| 16 | Slack status / mute | Pro: sets Slack status, mutes teams | skip | Network + account. |
| 17 | Calendar sync | Writes sessions to an Apple Calendar | later | EventKit permission; nice for "proof of effort". |
| 18 | Sync across Mac/iPhone/iPad, server backup | Own server sync | skip | No network, no accounts. |
| 19 | Export CSV/JSON | Export for time logging | later | Log is already JSON on disk; add Export… later. |
| 20 | URL scheme / AppleScript automation | Documented URL scheme and AppleScript | later (App Intents) | App Intents "Start Focus Session", "Stop", "Get Remaining Time" so Shortcuts can drive it. No URL scheme in v1. |
| 21 | Breathing prompt before start | Short breathing animation before each session | skip | Friction; not our tone. |
| 22 | Music / smart lights per phase | AppleScript hooks at start/end | skip | Covered by #14 (a Shortcut can do anything). |
| 23 | 2-minute warning | Toggle praised in reviews | later | Optional notification before the end. |
| 24 | Global shortcut | Customizable keyboard shortcuts | should | One recorder: Start/Pause. Unset by default. |
| 25 | Resizable UI font, to-dos | Recent Session updates | skip | Not part of a menu bar timer. |

## Key flows

### Flow 1: a focus session
1. Click the menu bar icon (an outline timer symbol). The menu shows: status line ("Ready ·
   Today: 2 sessions"), **Start Focus** (25 min), a *Length* submenu (15/25/45/50/Custom),
   label field (should), then footer.
2. Choose **Start Focus** (or the global shortcut). The icon fills and shows "25m"; the
   menu's first item becomes "Focusing · 25 min left" with **Pause**, **Stop**, **Add 5
   Minutes**.
3. At zero: a notification "Focus session done. Take a 5-minute break." with **Start
   Break** / **Skip Break** buttons and the system sound (if on). With auto-start breaks on
   (default), the break starts immediately and the notification says so.
4. During a break the icon shows a different symbol (e.g. a cup) and "4m".
5. Break ends: notification "Break's over." With auto-start next off (default), the icon
   returns to idle showing the updated day's count in the menu.
6. **Stop** mid-session asks nothing: the partial session is logged as incomplete and
   doesn't count. (Undo isn't needed: it's not destructive.)

### Flow 2: first run
1. Launch: icon appears in the menu bar; no window, no tour.
2. The first time the user presses Start, macOS asks for notification permission (we ask
   then, not at launch). If denied, the timer still works: at zero the icon blinks briefly
   (honoring Reduce Motion: no blink, just text change) and the system sound plays; the menu
   shows a one-line hint with **Open Notification Settings…**.

### Flow 3: Focus mode via Shortcuts (should)
1. Settings ▸ Automation: toggle "Run a shortcut when a session starts/ends".
2. Two pickers list the user's shortcuts (from `shortcuts list`); a help line explains making
   one with the "Set Focus" action. A **Test** button runs the start shortcut.
3. On start/end we run `shortcuts run "<name>"` in the background with a timeout; a failure
   shows one line in the menu ("Couldn't run “Work Focus On”. Check it in Shortcuts.") and
   never blocks the timer.

## Settings inventory

| Setting | Default | Options | Keep? |
|---|---|---|---|
| Focus length | 25 min | 15/25/45/50, custom 1–180 | v1 |
| Short break | 5 min | 1–60 | v1 |
| Long break | 15 min, after every 4 sessions | off, 2–8 sessions | should |
| Auto-start breaks | on | | should |
| Auto-start next session | off | | should |
| Show seconds in menu bar | off | | v1 |
| Play sound at end | on | system sounds list | v1 |
| Run shortcut at start/end | off | shortcut names | should |
| Launch at login, Show in menu bar | off / on | | v1 (standard) |
| Start/Pause shortcut | unset | recorder | should |
| Daily count resets at | midnight local | | v1 (not configurable) |

## Menus and shortcuts

Status menu (`.menu` style), in order: status line → Start Focus / Pause ⌘P / Resume ⌘P /
Stop ⌘. / Skip Break ⌘→ / Add 5 Minutes ⌘+ → Length ▸ → Label… (should) → `MenuFooter`
(Settings… ⌘, · About · Quit ⌘Q). In-menu shortcuts only work while the menu is open; the
global shortcut is the recorder in Settings ▸ Shortcuts.

## Permissions and system integration

- **Notifications**: asked on first Start. Fallback described in Flow 2.
- **Shortcuts CLI** (`/usr/bin/shortcuts`, macOS 12+): no extra permission for running a
  user's own shortcut; the shortcut itself may ask for its own permissions when first run.
- **App Intents** (should): Start/Stop/Remaining, discoverable in Shortcuts and Spotlight.
- No Accessibility, no network, no calendar in v1.

## UX patterns worth adopting

- The menu bar text *is* the app: most uses never open anything.
- Notification action buttons let the user decide break/skip without opening the menu.
- Separate toggles for auto-starting breaks vs. the next session (reviews single out this
  granularity).
- Daily total as time, not just count, rewards partial days.

## What we won't copy, and what we'll do better

- Not copying: name, icon, sounds, breathing animation, wording, paid tiers, account/sync.
- Better: everything free and local (no category limits behind a subscription); no account
  or server backup; no activation problems across devices (a recurring complaint); a
  menu bar–only footprint instead of a 160 MB app; Focus integration through the user's own
  Shortcuts instead of an intrusive blocker; timer survives sleep correctly.

## Edge cases

- **Sleep/wake mid-session**: timer is based on an end `Date`, not tick counting. On wake,
  if the end passed, log the session and post one notification ("ended while your Mac was
  asleep"); never fire a burst of stale notifications.
- **Clock/time zone change**: use monotonic-ish logic: store start + planned duration; a
  manual clock jump shouldn't produce negative times (clamp).
- **Midnight crossing**: a session counts for the day it *ended*.
- **Quit/relaunch mid-session**: persist the running state; on relaunch resume if still
  inside the window, else log as finished/expired.
- **Notifications denied / Focus mode silencing us**: fallback indicator.
- **Shortcut missing or renamed**: one-line error, timer unaffected.
- **Menu bar crowded / notch**: idle text is empty so the item stays narrow.
- **Multiple displays**: nothing special (status item).
- **Reduce Motion**, VoiceOver label "Focus timer, 18 minutes left".
- **Idle CPU**: when idle no timers at all; while running, update the title once a minute
  (once a second only when *Show seconds* is on).

## Our v1 scope

- [x] Start a 25-minute focus session from the status menu; the icon shows remaining minutes.
- [x] Pause, Resume, Stop work and are reflected in the icon and menu.
- [x] Focus length presets (15/25/45/50) and custom length; break length setting.
- [x] At zero: notification with Start Break / Skip Break, plus system sound (toggle).
- [x] Break countdown with its own symbol; ends with a notification.
- [x] "Today: N sessions · total time" status line; resets at local midnight; persisted.
- [x] Notification permission asked on first Start; working fallback if denied.
- [x] Correct behaviour across sleep/wake and app relaunch mid-session.
- [x] Show seconds toggle; idle CPU within budget.
- [x] Settings: General (launch at login, show in menu bar), Timer, About.

Should (v1 if cheap): long break every 4, auto-start toggles, Add 5 Minutes, label, run a
Shortcut at start/end, global Start/Pause shortcut, App Intents.

## Open questions → owner-default decisions (2026-11-03)

1. **Menu bar format**: minutes only ("18m") by default, seconds opt-in. Calmer, lighter.
2. **What counts as a session**: ≥ 80% of planned length; Stop before that logs it as
   incomplete (kept in the log, not in the count).
3. **macOS Focus**: only through the user's own Shortcuts (public `shortcuts` CLI). No
   private Focus/DND APIs. Off by default.
4. **Blocking apps/sites, Slack, sync, calendar**: not in v1 (network, accounts or
   intrusive). Calendar is the only "later" candidate.
5. **History beyond today**: stored (JSON lines in Application Support, a few KB a year);
   no charts in v1.
6. **Overlap with Awake**: none needed; Focus does not keep the Mac awake.

## Build notes (step 3–4, 2026-11-03)

### Architecture

- `TimerMachine` (FocusCore) is a pure value type: start/pause/resume/stop/skip/extend and
  `advance(now:)` return events (`started`, `ended`, `recorded`, `alert`). A running phase is
  stored as an **end date**; a paused one as time left. `lastSeen` detects the clock being set
  back (the run shifts with it, so no time is added and remaining never exceeds planned).
- `FocusController` (FocusCore, `@Observable`) owns the machine, persists it, schedules the
  next look at the clock and turns events into notifications, sounds, history lines and
  shortcut runs. Every system call is behind a protocol with a fake: `Scheduler`, `Notifier`,
  `SoundPlayer`, `ShortcutRunner`, `ActivityToken`, `FocusStorage`, and an injected clock.
- Ticks only when the shown value changes (once a minute; once a second with *Show seconds*),
  and the final tick lands on the end date. Idle: no timers at all. While a phase runs, a
  `userInitiatedAllowingIdleSystemSleep` activity stops App Nap from delaying the end (it does
  not keep the Mac awake: no `pmset` assertion).
- Re-checks the clock on wake, clock/time-zone change, `NSCalendarDayChanged` and menu open.
- Status item: `MenuBarExtra(.menu)` whose label is one template image (symbol + monospaced
  digits) drawn by `StatusImage`, so the item doesn't jitter and tints correctly.
- Storage: `state.json`, `settings.json`, `history.jsonl` in Application Support (or
  `FOCUS_DATA_DIR`). Only yesterday+today are read at launch (history read from the end).

### Decisions made while building

| Decision | Why |
|---|---|
| Sleep/relaunch catch-up: the phase is logged at the time it really ended; a break that would still be running carries on; nothing else auto-starts | A night asleep must not invent a chain of sessions or burst notifications |
| One notification on wake ("It ended while your Mac was asleep."), **no sound**; relaunch catch-up is silent | Opening a laptop in a meeting shouldn't chime; quitting/relaunching isn't news |
| "Late" = more than one minute overdue (one unit in accelerated tests) | Normal timers fire within ~1 s; sleep is the only way to be a minute late |
| Skip Break starts the next focus session right away | The intent of skipping a break is getting back to work; Stop is there to just stop |
| Notification buttons: auto-started break → **Skip Break**; offered break → **Start Break** / **Start Focus**; break over → **Start Focus** | Explicit verbs; "Skip Break" with nothing running would be ambiguous |
| Today's time counts every focused minute (incl. sessions stopped early); the tally counts sessions ≥ 80% | Research: "time, not just count, rewards partial days" |
| Long-break cycle resets on a new day; an offered break expires overnight | Yesterday's 3 sessions shouldn't make today's first break long |
| The label persists across sessions until changed/cleared, and shows in the status line | Afternoon-long intentions ("Taxes") are the common case |
| Sound played by the app (`NSSound`), notifications silent | The "Play sound" toggle and sound picker then work whether or not notifications are allowed |
| Notification permission requested on the first Start of each launch unless allowed | macOS reports "denied" while its prompt is unanswered and withdraws the prompt when the app quits; asking again is a no-op after a real answer |
| Delivered notifications are cleared when the next phase starts | A stale "Break's over" shouldn't sit in Notification Center |
| *Show seconds* stays opt-in, with a battery note | Per-second status item redraws cost ~3% CPU (AppKit redraws the item for every display's menu bar, ~24 ms each); SwiftUI text was worse (5.3%) |
| Settings tabs: General, Timer, Shortcuts, Automation, About, built from SlopKit pieces | `SlopSettings` can't add a Timer tab or select a tab; the menu's "Custom…" opens straight to Timer |
| App Intents deferred | SwiftPM builds don't run Xcode's App Intents metadata processor, so intents wouldn't be discoverable. The global shortcut covers keyboard control |
| Label entry uses an `NSAlert` with a text field | A `.menu`-style status menu can't host a text field; an alert is native, Esc cancels |

### Gap review: v1 scope

| v1 item | Status | Evidence |
|---|---|---|
| Start a 25-minute session from the menu; icon shows minutes | Done | Walkthrough: icon "⏱ 25m", VoiceOver label "Focus timer, focusing, 25 minutes left" |
| Pause, Resume, Stop reflected in icon and menu | Done | Paused icon (pause circle + time), time frozen for 4 s+, Resume/Stop menu items swap |
| Presets 15/25/45/50, custom length, break length | Done | Focus Length submenu with checkmarks; "Custom…" opens Settings ▸ Timer; typed 35 committed and shows "35 Minutes (Custom)" |
| Notification with Start Break / Skip Break, sound toggle | Done (logged), real delivery partly verified | Effects log shows title/body/buttons and sound. Real `UNUserNotificationCenter`: categories registered, posts reach `usernoted` (seen in the system log), permission prompt shown on first Start. Buttons not pressed for real: permission was never granted (see risks) |
| Break countdown with its own symbol; ends with a notification | Done | Leaf icon "5m"; "Break's over" logged |
| "Today: N sessions · time", resets at midnight, persisted | Done | "Today: 4 sessions · 1 hr 45 min" after four sessions (one extended); midnight/day-it-ended unit tests |
| Permission asked on first Start; fallback if denied | Done | Asked on first Start (log + real prompt). Denied: sound still plays, bell blinks 3× (screenshots), menu shows "Notifications are off for Focus." + Open Notification Settings… |
| Correct across sleep/wake and relaunch | Done | Unit tests (sleep through end/break/everything, clock set back, relaunch running/paused/expired). Live: process frozen with SIGSTOP for 40 s past the end → exactly one "ended while asleep" notification, no sound, session logged at its true end time; quit mid-session + relaunch resumed with the right time; quit past the end + relaunch logged it silently. Real system sleep not exercised (owner's Mac) |
| Show seconds; idle CPU within budget | Done | perf.sh idle 0.004 %; with a session running (minute mode) 0.002 % lowest window, 23 MB. Seconds mode ~3 % (opt-in, documented) |
| Settings: General, Timer, About | Done | Plus Shortcuts and Automation; light + dark screenshots |
| Should: long break every 4, auto-start toggles, Add 5 Minutes, label, run a Shortcut, global shortcut | Done | Long break after the 4th session (walkthrough); offered-break flow with auto-start off; label via alert; Automation with fake shortcut names, failure line in menu; global ⌃⌥T (set for the test, then removed) started and paused from Calculator |
| Should: App Intents | Deferred | See decisions |

### Gates

- `scripts/check.sh Focus --perf`: PASS. 78 Swift Testing tests (timer machine 27, settings/stats
  5, text 9, controller 31, storage 4, shortcuts command 3). Launch 149 ms, first status item
  281 ms, idle CPU 0.004 %, footprint 21.7 MB.
- Countdown visible (perf.sh with a running session seeded): launch 126 ms, idle CPU 0.002 %
  lowest / 0.019 % median, footprint 23.3 MB.
- `drive tree`: no `[unlabeled]` in the menu, any Settings tab or About.
- No sockets open (`lsof -i`), no networking code.

### Design-system checklist (§10)

| # | Item | Result |
|---|---|---|
| 1 | Main job in one click/shortcut | Pass: Start Focus (⌘↩ in the menu, or the global shortcut) |
| 2 | Native look, light + dark | Pass: system symbols, template status image, grouped forms; Settings checked in both. The status menu follows the system menu bar appearance |
| 3 | Keyboard + menus | Pass: every action in the menu with its shortcut; global Start/Pause recorder |
| 4 | Esc / ⌘, / ⌘Q | Pass: Esc cancels the label alert, ⌘W closes Settings |
| 5 | Settings General + About | Pass |
| 6 | Copy | Pass: title case items, sentence case labels, verbs, no "!" (unit-tested for alerts) |
| 7 | Empty states | Pass: "Ready to focus" / "Today: no sessions yet" |
| 8 | Permissions only when needed | Pass: notifications on first Start; Open Notification Settings… link (opening it not tested: owner active) |
| 9 | Nothing destructive | Pass: Stop logs the session; nothing deletes |
| 10 | No network | Pass |
| 11 | Performance | Pass (default minute mode) |
| 12 | VoiceOver names | Pass, status item label is spoken text |
| 13 | Reduce Motion | Pass: no blink under Reduce Motion (unit-tested; not toggled system-wide) |
| 14 | Relaunch state | Pass: running/paused sessions resume |

### Known risks / not tested

- **Real notifications never shown as banners.** The first permission prompt was withdrawn by
  macOS when the test app quit, which macOS then treats as "not allowed"
  (`UNErrorDomain Code=1`). The owner needs to turn notifications on for Focus in System
  Settings ▸ Notifications (or via the menu's link) once. Action buttons on real
  notifications are therefore untested; the handler is unit-tested.
- Real system sleep/wake not exercised (simulated with SIGSTOP + unit tests).
- `drive` clicks don't give the app activation rights, so the label alert opened unfocused in
  tests (works for a real click); its "Set Label" was pressed via Accessibility.
- Open Notification Settings… URL (`x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=…`)
  not opened: owner was active.

### Blind tester notes

- Use `FOCUS_DATA_DIR=/tmp/focus-test/data FOCUS_TEST_LOG=/tmp/focus-test/effects.log`
  (notifications, sounds and shortcut runs go to the log), `FOCUS_SECONDS_PER_MINUTE=1` to
  run whole sessions in seconds, `FOCUS_TEST_PERMISSION=denied` for the fallback,
  `FOCUS_TEST_SHORTCUTS="Work On,Work Off,Fail Test"` for Automation.
- No permissions needed. The global shortcut is unset; setting one needs the recorder
  (keyboard) and `key --global`.

## Parity pass (2026-11-03)

Per `docs/parity-pass.md`. Session isn't installed and the screen was locked, so the
original was studied from stayinsession.com (home, Learn guides, URL-scheme and export docs,
changelog), the Mac App Store listing (description, version history to 2.13.48) and the
Learn guide's screenshots (downloaded to `/tmp/focus-parity/`, not committed). UI was verified
with an offscreen render hook (`FOCUS_SNAPSHOT_DIR`), unit tests and headless runs of the
release build.

### What the original looks like

- **Main window**: a left column with the timer and a right column that's a notes pane
  during a session and a day calendar (hour grid, sessions as coloured blocks, a red "now"
  line) otherwise. An icon rail switches Timer / Analytics / Settings (⌘1, ⌘2…).
- **Timer column**: daily-target dots, a heading asking for your focus, a category pill
  (dot + name + chevron), an intention field with suggestions from past sessions (each with
  its category pill), a round clock face with minute ticks you drag to set the length, the
  time, a "15:05 → 15:30" capsule flanked by −5 / +5, and round buttons (pause, finish/stop).
  "@category" and "30m"/"1h" typed in the intention set the category and length.
- **After a session**: an overflow phase counting up; reflection with Focused / Neutral /
  Distracted and notes; ⌘↩ submits. Breaks show a big countdown; an optional always-on-top
  rest window.
- **Analytics**: Day/Week/Month with ‹ › navigation; tiles (total focus, average a day, most
  focused time, total break, focus/break ratio), mood counts, a daily distribution bar chart
  with an average line, a category distribution table, and a session log grouped by day with
  category/notes filters; export to CSV/JSON.
- **Menu bar**: remaining minutes; pause/finish/abandon. A "mini player" floating window.
- **Settings**: General (daily target, intention suggestions, auto-start, reflection,
  sleep behaviour), Notification, Background sound, Calendar, per-profile Session/Website
  blocker/App blocker, Slack, Menubar & Dock, Window, Window tracker, Shortcuts, AppleScript,
  Keyboard shortcuts, Account.

### Gap table

| Item (original) | Status | Notes |
|---|---|---|
| Main window: timer left, notes/day calendar right | **Done** | `FocusWindow` (AppKit-hosted, opens on demand, ⌘0, reopen from Finder/Dock). Shows in the Dock with a full menu bar while open |
| Section switcher (Timer / Analytics, ⌘1 ⌘2) | **Done** | Toolbar segmented control + View menu ⌘1/⌘2 |
| Big round clock with minute ticks, drag to set length | **Done** | `FocusDial`: ring + 60 ticks + knob; drags snap to 5 min (5–60); VoiceOver adjustable |
| "Start → end" capsule with −5 / +5 | **Done** | Works idle (changes the length) and running (`shorten`/`extend`) |
| Daily target dots | **Done** | Settings ▸ General ▸ Daily goal (default 8, None hides) |
| Category pill + categories with colours | **Done** | Menu pill everywhere; Settings ▸ Categories (add, rename, colour grid, drag to reorder, delete with confirmation). Defaults Work/Study/Personal |
| Intention field + suggestions from past sessions | **Done** | Word-start matches first, ↑↓/Return/Esc, picks the suggestion's category |
| "@category" and "30m/1h" in the intention | **Done** | `IntentionParser`; length applies to that one session only |
| Notes pane during a session, recent notes | **Done** | Saved with the run and the log |
| Day calendar with session blocks and now line | **Done** | `DayTimeline` (logged sessions, breaks, the live block) |
| Reflection (mood + notes), ⌘↩ submits | **Done** | Window, menu bar panel and break screen; ⌘↩ = start focus *or* save reflection, like the original. Skipped for sessions under a minute; cleared when the next session starts |
| Finish vs abandon | **Done (adapted)** | Finish = counts now, break follows. Stop = stop (still counts at 80%). No "abandon without logging": partial time is part of the day's total |
| Analytics: Day/Week/Month, tiles, moods, chart, categories, log, filters | **Done** | `StatsReport` + Swift Charts. Category filter, Notes Only, context menu to change mood/category or delete (confirmed) |
| Export CSV | **Done** | ⇧⌘E and toolbar button; RFC 4180, formula-safe |
| Export JSON | Deferred (S, 1 h) | CSV covers spreadsheets/time logging; history.jsonl is already JSON |
| Break screen / always-on-top rest window | **Done** | Optional full-screen cover on every display, Esc/Hide/Back to Work, reflection inline. Off by default |
| App blocker | **Done (hide only)** | Settings ▸ Hide Apps: hides listed apps when a session starts and whenever one is activated/launched during it, with a short HUD. Never quits. Not during breaks or pauses |
| Website blocker | Skipped | Needs a browser extension (Safari/Chrome) or a hosts-file/network filter (root). Use a Focus mode filter via Automation |
| Menu bar timer + controls | **Done, richer** | `.window` panel: category, goal dots, small dial, heading, start→end, today, intention field, controls, ±5, reflection, footer |
| Mini player (floating window) | **Done (adapted)** | Window ▸ Float on Top keeps the main window above others |
| Keyboard shortcuts | **Done** | Timer menu (see README), Settings ▸ Shortcuts lists them; global Start/Pause and Show Window recorders |
| Global shortcut to show the window | **Done** | Unset by default |
| Apple Focus / DND, Shortcuts, AppleScript automation | **Done (existing)** | Run a shortcut at start/end. AppleScript hooks: skipped (Shortcuts covers it) |
| Overflow (count up past zero) | Deferred (M, half a day) | Needs a new phase in `TimerMachine`, menu bar text for overtime, and stats rules; auto-start breaks covers the common flow |
| Pre-end warning, presence reminder | Deferred (S–M, 2–3 h) | Extra tick target in `reschedule()` + a quiet notification; low everyday value |
| Calendar logging (EventKit) | Deferred (M, half a day) | Needs a calendar permission prompt (can't be approved in testing) and writes to the owner's calendar; would be opt-in with a dedicated "Focus" calendar |
| URL scheme | Deferred (S, 2 h) | Possible through `app.json` `infoPlist` (CFBundleURLTypes) + `application(_:open:)`; registering a scheme wasn't worth doing untested on a locked screen |
| Background sounds | Skipped | Needs sound assets (can't copy theirs; synthesizing good ambience is its own project) |
| Window tracker, Slack, sync, widgets, Live Activities, todos | Skipped | Accessibility snooping / network / accounts / WidgetKit extension (no SwiftPM support) / iOS-only |
| "When Mac goes to sleep" option | Skipped | Our sleep handling is already correct and quiet |

### Decisions

| Decision | Why |
|---|---|
| Stay menu-bar-first (`LSUIElement`); the window opens on demand and the app becomes a Dock app while it's open | Keeps launch/idle budgets and the 1-click flow; matches the original's window when you want it |
| Window hosted by AppKit, not a SwiftUI `Window` scene | A `Window` scene can open itself at launch on macOS 14 |
| Breaks are now logged (kind = short/long break) | Needed for total break, focus/break ratio and the timeline; they never count as sessions |
| History log stays append-only; edits/deletes append a line with the same id (last wins) | No rewrites of a user's history file; old lines get a stable id from their start time |
| Ring-and-ticks dial in the category colour, not a pie wedge with a hand | Same structure (minute face, drag to set), our own look; avoids the original's signature red clock |
| Mood icons are arrows (↑ → ↓) in green/grey/orange | The original uses emoji; arrows match its own "1↑ · 0→ · 0↓" notation without copying artwork |
| Category colours from a fixed list of system colours, plus "Accent" | Adapts to dark mode/contrast; no hardcoded hex |
| Typed length ("45m") applies to that session only | Doesn't silently change the default |
| ⌘↩ starts a session or saves the waiting reflection | Same as the original; one key for "go on" |
| Settings window 580 pt wide | Seven toolbar tabs don't fit SlopKit's 480 pt |
| Hide Apps: with `FOCUS_TEST_LOG` it only logs unless `FOCUS_HIDE_REAL=1` | Tests never touch the owner's apps |

### Deviations from the design system

- **Menu bar archetype uses `.window`** (rich content: dial, intention field, reflection),
  320 pt wide. The reflection + offered-break state is ~560 pt tall (over the 480 pt
  guideline) because it stacks reflection, dial and controls; it doesn't scroll.
- **Colours beyond the accent**: category colours (system colours), green for breaks, mood
  tints. Needed to match the original's colour-coded categories.
- **Settings width 580 pt** instead of 480 (seven tabs).
- **Break screen** is a full-screen cover (opt-in, dismissable with Esc), not a HUD.

### Shared components built in-app (candidates for SlopKit)

- `PanelRow` / `PanelFooter` (`MenuPanel.swift`): menu-like rows and the Settings/About/Quit
  footer for `.window`-style menu bar panels.
- `DotImage` (`CategoryViews.swift`): non-template colour dots for menus.
- `Radius` (`DayTimeline.swift`): corner radius tokens.
- `DockPresence` (`FocusWindow.swift`): Dock icon while a window is open (Snapper has a twin).

### Gates (2026-11-03)

- `scripts/check.sh Focus --perf`: **PASS**. 110 Swift Testing tests in 12 suites (32 new:
  machine parity 6, controller parity 14, stats 6, intentions 4, export 1, history log 1).
  Launch 127 ms, first status item 288 ms, idle CPU 0.006 % (median 0.036 %), footprint
  22.2 MB.
- Offscreen renders (release build, light + dark), all looked at:
  `/tmp/focus-test/renders/` — `main-idle`, `main-focus` (notes), `main-focus-timeline`,
  `main-reflection`, `main-break`, `stats-day|week|month`, `panel-idle|focus|reflection`,
  `break-screen`, `settings-general|timer|categories|blocking|shortcuts`, each `-light`/`-dark`.
  Offscreen artefacts: prominent buttons render unaccented (window not key), toolbar
  (Timer/Stats switch, Export) isn't drawn, Settings tabs show as a segmented control.
- Headless release run (`FOCUS_SECONDS_PER_MINUTE=1 FOCUS_START=1`, test log): hiding on at
  start, off at the break; notification + sound at the end; break screen shown/hidden;
  focus and break logged; reflection pending persisted in `state.json`.
- Real app hiding: launched Chess myself, listed `com.apple.Chess` in a test data dir,
  `FOCUS_HIDE_REAL=1`: `isHidden` false → true once the session started; Chess quit after.

### On-screen checks still owed (screen locked)

1. `scripts/drive` walkthrough of the panel (`.window` style) and the Focus window, light and
   dark; `drive tree` for `[unlabeled]` controls (all custom buttons have labels in code).
2. Toolbar Timer/Stats switch and Export button render; Dock icon appears/disappears with the
   window; Timer/View/Window menus and their shortcuts (⌘↩, ⌘P, ⇧⌘↩, ⌘., ⌥⌘→, ⇧⌘. ⇧⌘,, ⌘L,
   ⌘1, ⌘2, ⌘0, ⇧⌘E).
3. Intention field: ↑/↓ reach the suggestion list (`onKeyPress` on a focused `TextField`),
   Return picks, Esc dismisses; suggestion overlay isn't clipped.
4. Dragging the dial knob; the colour grid popover in Settings ▸ Categories; drag to reorder.
5. Break screen live: covers every display, Esc hides it, focus returns; the panel closes when
   "Open Focus Window" is chosen.
6. Hide Apps: HUD appears when switching to a hidden app mid-session.
7. Notification banners/buttons (needs the owner to allow notifications once).

## Polish pass (2026-11-05)

Per `docs/polish-pass.md` (+ the mid-pass Golden Gate / light-dark addition). All shots from
the release build with test data only: `FOCUS_DATA_DIR=/tmp/focus-test/<state>`,
`FOCUS_TEST_LOG`, `FOCUS_SAMPLE_HISTORY=1` (new: five weeks of made-up sessions in an empty
*test* folder), `FOCUS_SECONDS_PER_MINUTE=2` for reflection/break states,
`SLOP_APPEARANCE=light|dark`. The owner's defaults domain was exported first and re-imported
at the end. Scripts: `/tmp/focus-test/scripts/shoot-all.sh` (every surface, one mode),
`realpanel.sh` (the real status-item panel, owner-idle gated).

New test hooks: `FOCUS_SAMPLE_HISTORY=1` (needs `FOCUS_DATA_DIR`), `FOCUS_BREAK_WINDOW=1`
(break screen as one opaque 1100 x 760 normal-level window, so a screenshot can never contain
anything behind it), `FOCUS_PANEL_WINDOW=1` (the menu bar panel's view live in a plain
window, for driving when the status item can't be clicked).

### Defects found and fixed (before → after)

| # | Surface | Defect (before) | After |
|---|---|---|---|
| 1 | Lint | 5 corner literals (`cornerRadius: 5` ×3, `2` ×2), 11 spacing literals; a private `Radius` enum (6/10) shadowing SlopKit's | 0 / 0. SlopKit `Radius` everywhere: cards `l` 12, fields/mood buttons `m` 8, timeline blocks `xs` 4, suggestion highlight `nested(in: m, padding: 4)` = 4, chart bars `xs`, session colour bar a `Capsule` |
| 2 | Main window, Stats, panel | SwiftUI `Divider` 1 pt (pane split, stats header and columns, timeline hour lines, panel separators) | Pane split measured 1 px `#EAEAEA` (0.5 pt); `Hairline` everywhere, `SelfSizingHairline` in the panel (see SlopKit issue) |
| 3 | Dial | Time readout 8.3 pt above the dial centre (caption pulled the group up: colon centre 332.3 vs dial 340.5) | Digits on the centre (colon 362.3 vs dial 361.5; caption hangs below, hidden twin above). Ring centred: track 86.5–103.5 / 256.5–273.5 → centre 180.0 = pane centre; stroke 17.25 pt both sides |
| 4 | Main window | Dial and controls jumped between states: dial centre 362 pt idle → 340 pt focusing; controls 598 → 589 pt | Fixed 116 pt header slot and a fixed-height control slot: dial centre 361.5 pt and controls 589 pt in idle, focusing and paused |
| 5 | Day timeline | Opened scrolled to midnight (scroll ran before layout), so today's sessions and the now line were off-screen | Scrolls to three hours before now; now line visible on open |
| 6 | Day timeline | White text on 80 % category fills (white on green ≈ 2:1); hour labels nudged with a −6 pt offset | Tinted blocks with a 3 pt colour edge and primary/secondary text (passes in both modes); labels centred on their line with an alignment guide |
| 7 | Categories | "No Category" was the accent (blue, same as Work) in rows, timeline and picker, but gray in the chart and table | Gray everywhere categories are compared (`dataTint`); the dial keeps the accent |
| 8 | Stats chart | Stack order random per bar and per launch (dictionary order) | Legend order on every bar |
| 9 | Stats chart | "avg 2h 25m" annotation drawn over the Friday bar; accent-blue average line | Average in the card header with a dashed key; gray rule |
| 10 | Stats chart | Y ticks at 1h 40m / 3h 20m / 5h | Round steps from `ChartAxis.scale` (unit-tested): 0m–4h by 1h, 15 min steps for light weeks |
| 11 | Stats chart | Gridlines 1 pt, mixed dashed (x) and solid (y) | One device pixel in `separatorColor`, solid, both axes |
| 12 | Stats chart | Empty period: no y axis, bare dashed lines, x labels 17 pt lower than with data | 0–1h axis kept (nothing moves), "No focus time in this period." in the plot |
| 13 | Stats chart | Bars announced as "Nov 2, 2026 at 12 AM to …" with no value | Day/hour label + "Work, 1h 30m" value |
| 14 | Mood buttons | Selected: white label on green fill (≈ 2:1) | Tint wash + 2 pt ring in the mood colour, primary label |
| 15 | Intention suggestions | List drawn over the field in the live window (fixed 46 pt offset); 1 pt border | Placed under the field by a geometry reader at any text size (4 pt gap); row text lines up with the field's text at 12 pt; hairline border; highlight concentric (4 pt in 8 pt, 4 pt inset) |
| 16 | Menu bar item | Width shrank when 10m → 9m (and 10:00 → 9:59), shifting the items to its left | Width reserved for "00m" / "00:00" (`TimeText.widthTemplate`, unit-tested) |
| 17 | Contrast | `.tertiary` text: notes hint, break-screen Esc line, panel shortcut keys (≈ 1.9:1) | System placeholder colour for the notes placeholder (same as every text field), `.secondary` for the others |
| 18 | Notes pane | Earlier-today rows stretched to fill the pane (colour bar 145 pt tall) | Rows at their own height |
| 19 | Window | Side pane showed Today when the window opened on a running session | Notes while focusing, Today otherwise, also on open |
| 20 | Settings ▸ Categories | Category List with `minHeight: 200`: 3 rows then ~128 pt of empty section; doubled full-width line above Add Category | List sized to its rows (31 pt pitch, scrolls past 8), last separator hidden; empty state text |
| 21 | Settings ▸ Shortcuts | Key combos in a monospaced font (⌘↩ and ⌘P didn't line up) | System font, secondary |
| 22 | Notifications | Denied state only in the panel, as two caption lines | Panel: bell-slash notice with what still happens + link. Settings ▸ General: a Notifications row (On / Not asked yet / off with "Open Notification Settings…") |
| 23 | Break screen | Two prominent buttons while a reflection waits (Save and Back to Work); translucent `background.opacity(0.6)` card on the glass; `.padding(40)` | Back to Work is prominent only without a reflection; system `.regularMaterial` card; `Spacing.xxl` |
| 24 | Dial in the menu bar panel | Ticks invisible in the real glass panel (Canvas `.tertiary` went vibrant) | Resolved `tertiaryLabelColor` / `quaternaryLabelColor`: ticks visible (real panel shot) |
| 25 | Panel | "Short break" caption touched the ring at 104 pt; long "Today:" line truncated | Caption scales to 80 %; today line wraps |
| 26 | Colour swatches | Selected swatch marked with a white checkmark (invisible on yellow/mint); 1 pt border | 2 pt primary ring around the selected swatch, hairline swatch edge |

### Golden Gate + light/dark

- **Menus are text only**: the menu bar panel's footer rows lost their decorative symbols
  (Open Focus Window, Stats, Settings…, About, Quit). Category menus keep their colour dots
  (information); "No Category" got a gray dot so the list is consistent.
- **Toolbar**: the standard toolbar (segmented Timer/Stats, Export) on the system glass; no
  drawn strips. Stats header sits below it in content with a hairline.
- **No sidebar** in Focus (two panes split by a hairline), so the sidebar rules don't apply.
- **Inactive windows**: system controls grey out; the custom round Pause/Resume button now
  does too (`appearsActive`). The dial ring, goal dots and category colours stay coloured:
  they're progress/data, like a progress bar. Inactive shot: `main-idle-inactive-light.png`.
- **Glass**: only system materials (break screen `fullScreenUI` + `regularMaterial` card;
  the system menu bar window). Real-panel radius measured 17.1 pt; the row hover highlight is
  concentric (`17 − 8 = 9`).
- **Light and dark**: every surface shot in both (`*-light.png` / `*-dark.png`). No drawn
  pure black/white surfaces (white only as text/icons on accent fills, like system
  buttons). Placeholder text: light #8E8E8E on #F7F7F7 (the system placeholder colour, 3.1:1,
  accepted as for every field), dark #AEAEAF on #36383A (5.5:1). No layer colours in Focus.

### Gates

- `scripts/lint.sh Focus`: pass (was 5 failures, 11 warnings).
- `scripts/check.sh Focus --perf`: PASS. 114 tests in 13 suites (+4: chart axis ×3, width
  template). Perf (busy machine, load 4.4): launch 158 ms, first status item 320 ms, idle CPU
  0.002 % lowest, footprint 21.1 MB. The final `check.sh` run landed at load 17 (other agents
  building) and read 0.375 % lowest; a re-run straight after (load 16) passed: launch 151 ms,
  status item 275 ms, idle CPU 0.002 % lowest, 21.0 MB. Nothing in this pass adds idle work.
- `drive tree`: no `[unlabeled]` in the main window (timer, stats), every Settings tab, the
  panel window or the real status-item panel. Window buttons 16x16.

### Screenshots

`/tmp/slopapp-polish/focus/before/` (inventory before fixes) and
`/tmp/slopapp-polish/focus/after/`: `main-idle|main-suggest|main-focus|main-focus-timeline|
main-paused|main-reflection|main-break|main-offered|main-idle-inactive`, `stats-day|week|
month|empty`, `panel-idle|focus|reflection|break|offered-denied` (panel test window),
`realpanel-idle-light` and `realpanel-paused-light-1` (the real status-item panel),
`break-screen` (windowed hook), `settings-general|general-denied|timer|categories|hide-apps|
shortcuts|automation|about`, `status-idle|focus|paused`, each `-light` and `-dark` unless
named otherwise.

### Not done / owed

- **Real panel in dark mode**: not shot — the owner came back (HID idle < 60 s) between
  runs. The panel test window covers its layout in dark.
- **Hover** on the panel rows and swatches: needs the real pointer to hover; designed in code
  (accent row, white text), not seen.
- **Drag to reorder categories** and dragging the dial knob: real-mouse drags, owner active.
- In the offered-break state (auto-start breaks off) −5/+5 change the next *focus* length while
  the dial shows the break: left as it was (behaviour, not finish); worth a look in a blind test.

### SlopKit issue

- `Hairline` in a window that sizes itself to its content (`NSHostingController` with
  `.preferredContentSize`, the way `MenuBarExtra(.window)` panels are hosted) crashed AppKit's
  constraint pass at launch (`_updateConstraintsForSubtreeIfNeeded…` exception), reproducibly;
  `Divider` didn't. Focus uses an in-app `SelfSizingHairline` (`MenuPanel.swift`: lays out
  1 pt, draws the top half with `scaleEffect`) in the panel, a candidate for SlopKit.
  **Resolved 2026-11-06:** SlopKit's `Hairline` now always lays out 1 pt and draws one device
  pixel, so Focus uses it in the panel and `SelfSizingHairline` is gone.

## Sources

- [Session website](https://www.stayinsession.com/)
- [Session Learn (help index)](https://www.stayinsession.com/learn)
- [Session: getting started guide (parity pass)](https://www.stayinsession.com/learn/getting-started-with-session-pomodoro-app)
- [Session URL scheme](https://www.stayinsession.com/learn/session-url-scheme)
- [Session export data](https://www.stayinsession.com/learn/export-data)
- [Session changelog](https://www.stayinsession.com/changelog)
- [Session on the Mac App Store](https://apps.apple.com/us/app/session-pomodoro-focus-timer/id1521432881)
- [Session on Setapp](https://setapp.com/apps/session)
- [Product Hunt reviews](https://www.producthunt.com/posts/session-3/reviews)
- [Timing: best Pomodoro apps for Mac 2026](https://timingapp.com/blog/best-pomodoro-apps-for-mac/)
- [Toolradar: Session](https://toolradar.com/tools/session)
- [TomatoBar (open source menu bar Pomodoro)](https://sourceforge.net/app/tomatobar/mac/)

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.
