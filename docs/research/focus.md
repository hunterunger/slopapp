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

## Sources

- [Session website](https://www.stayinsession.com/)
- [Session Learn (help index)](https://www.stayinsession.com/learn)
- [Session on the Mac App Store](https://apps.apple.com/us/app/session-pomodoro-focus-timer/id1521432881)
- [Session on Setapp](https://setapp.com/apps/session)
- [Product Hunt reviews](https://www.producthunt.com/posts/session-3/reviews)
- [Timing: best Pomodoro apps for Mac 2026](https://timingapp.com/blog/best-pomodoro-apps-for-mac/)
- [Toolradar: Session](https://toolradar.com/tools/session)
- [TomatoBar (open source menu bar Pomodoro)](https://sourceforge.net/app/tomatobar/mac/)

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.
