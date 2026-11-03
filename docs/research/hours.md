# Hours research (inspired by Timing)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied: Timing
> (not installed on this Mac) from its website, help FAQ and press materials, comparison
> pages, and the open-source ActivityWatch (MPL-2.0) for architecture, on 2026-11-03. We
> never copy its name, icons, artwork, wording, sounds or signature visuals.

## The job

Hours tells you where your time actually went, without starting timers. It quietly notes
which app is in front while you're at the Mac, and at the end of the day or week shows a
timeline and totals you can group into projects ("Client A", "Email", "Distraction").
People reach for it to fill in a timesheet, to bill a client, or to be honest with
themselves about focus. "Done" is a believable answer to "what did I do on Tuesday
afternoon and for how long?" in a few seconds, with nothing having left the Mac.

The one interaction that matters most: **open the window, see today as a timeline of
colored app blocks with totals per app and project; drag an app onto a project once and
it's remembered.**

## Who and when

- Freelancer filling a weekly timesheet from Friday's review.
- Someone checking how much of the day went to chat and email.
- Recovering "what was I doing at 3 pm" for a standup.
- Comparing this week's focus time to last week's.

Frequency: recording is passive all day; reviews once a day or week (1–5 minutes).

## Feature inventory

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Automatic app tracking | Once per second records the frontmost app, window title, document path or URL | must (app only) | Event-driven: `NSWorkspace.didActivateApplicationNotification` starts a new segment. No polling, no permission. Store bundle ID + app name + start/end. |
| 2 | Window titles, document paths | Via Accessibility; some apps via Screen Recording | later, opt-in (off) | Privacy default: never recorded. Opt-in later needs Accessibility and a clear explanation. |
| 3 | Website/URL tracking | Via AppleScript/Automation for Safari, Chrome, Firefox, Arc… ; private tabs discarded | later, opt-in (domain only) | Apple Events per browser (Automation prompt). Domain only, never full URLs. |
| 4 | Idle detection | Suspends after N min (default 3) with no input; screensaver counts as idle; long wait (3 h) when an app keeps the screen awake | must | `CGEventSource.secondsSinceLastEventType(.combinedSessionState, …)` checked every 30 s (no permission), plus screen lock, screensaver, sleep and display-sleep notifications to close segments exactly. Default idle threshold 5 min; idle time trimmed back to the last input. Media playback (a power assertion held by the front app) extends it: should. |
| 5 | "What did you do?" on return | Prompt after ≥ 5 min away | later | Quiet by default; offer "Add time away" from the timeline instead. |
| 6 | Timeline view | Combined blocks for a day; drag to assign | must | Day timeline: horizontal (or vertical) track of blocks colored by project (gray if none), hover/selection shows app and duration. |
| 7 | Totals by app and project | Reports by day/week/hour | must | Sidebar: Today, Yesterday, This Week, Last Week, pick a date. Content: timeline + list of apps with durations and bars. |
| 8 | Projects and rules | Drag activities into projects; ⌥-drag creates an automatic rule | must | Project = name + system color. Rule = "app X → project" (v1); assigning an app asks "Always?" with a checkbox. Rules apply retroactively. |
| 9 | Manual time entries / timers | Optional timers; fill gaps from the timeline | should | "Add Entry…" for meetings away from the Mac. Timers: later. |
| 10 | Export | PDF, XLSX, CSV, HTML; timesheets | must (CSV) / later (others) | CSV of segments or of totals per project per day. |
| 11 | Exclusions | Exclude apps/sites/activities from tracking | must | "Never record" app list. Time in those apps is simply not recorded (shows as a gap). |
| 12 | Pause tracking | Menu bar item shows tracking/paused; quit tracker | must | Status menu: Pause for 1 h / until tomorrow / Resume. Icon shows paused state. |
| 13 | Menu bar: today's total | Time and productivity score in the menu bar | should | Optional "4 h 12 min" text beside the icon. |
| 14 | Productivity score | Score per project | later | |
| 15 | Delete data | Not prominent | must | Delete a selection, a day, or everything. Retention setting (1 year by default; see decisions). |
| 16 | Sync, teams, web app, API, Zapier, MCP, AI summaries, Screen Time import, calendar/call tracking | All of them | skip | Network, accounts, or AI features that read activity: against the privacy promise. |
| 17 | Backups | ZIP backups in the data folder | later | One SQLite file the user can back up. |
| 18 | Launch at login | Tracker is a separate helper | must | Recording only works while running: see decisions. |

### Must-haves, counted

1 app tracking, 4 idle/lock/sleep, 6 timeline, 7 totals, 8 projects + app rules, 10 CSV,
11 exclusions, 12 pause, 15 delete data, 18 launch at login. Ten.

## Key flows

### Flow 1: review the day (main job)
1. Click the status icon → Open Hours (⌘0), or open the app. Window: sidebar (Today,
   Yesterday, This Week, Last Week, Projects), content = timeline + app/project totals.
2. Hover a block: "Xcode · 10:12–11:47 · 1 h 35 min". Select apps in the list.
3. Drag an app (or right-click → Assign to Project) onto a project; a checkbox "Always
   assign Xcode to Client A" is on by default; totals update.
4. ⌘E exports the visible range as CSV.

### Flow 2: first run
1. A single window: what Hours records (the front app's name and time, nothing else),
   where it's stored (this Mac only), and that idle time is skipped. A "Launch at login"
   checkbox (checked) and a Start Recording button.
2. After Start: the window shows today's (still empty) timeline with "Recording. Come back
   later to see your day." (`ContentUnavailableView`). No permission prompts at all.

### Flow 3: pause
1. Status menu → Pause Recording ▸ 30 min / 1 h / Until Tomorrow. Icon switches to the
   paused symbol. Resume Recording returns.

## Settings inventory

| Setting | Default | Options | Keep? |
|---|---|---|---|
| Launch at login | on (chosen on first run) | toggle | must |
| Idle after | 5 min | 1–30 min | must |
| Never record these apps | empty | app list | must |
| Keep history for | 1 year | 30 days, 90 days, 1 year, forever | must |
| Show today's total in the menu bar | off | toggle | should |
| Week starts on | system | system, Mon, Sun | should |
| Record window titles (needs Accessibility) | off | toggle | later |
| Delete All Data… | n/a | button with confirmation | must |

## Menus and shortcuts

Status menu: "Recording · 3 h 40 min today" (status line) · Open Hours ⌘0 · Pause
Recording ▸ · — · `MenuFooter`. Window: ⌘1–4 sidebar sections, ←/→ previous/next day or
week, ⌘T today, ⌘E export CSV, ⌫ delete selected time (undoable), ⌘F filter apps.

## Permissions and system integration

None for v1: app activation notifications, idle seconds and lock/sleep notifications are
all permission-free. Opt-in later features would need Accessibility (window titles) or
Automation (browser domains), each asked only when the user turns it on.

## Data and performance design

- SQLite (system `libsqlite3`) at `AppPaths.applicationSupport/hours.sqlite`: `segment(id,
  bundle_id, app_name, start, end)`, `project`, `rule`, `entry` (manual). A few MB a year.
- A segment is open in memory and written when it closes (activation change, idle, lock,
  sleep) and every 5 min as a checkpoint, so a crash loses at most 5 min.
- Zero timers except the 30 s idle check (with leeway). Target ≈ 0.0% idle CPU.
- Durations computed with wall-clock start/end stored in UTC; display in local time; days
  split at local midnight.

## UX patterns worth adopting

- **Assign once, remembered forever** (drag with an "Always" choice).
- **Idle trimmed automatically**, so reports are believable without editing.
- **A visible recording state** in the menu bar: honest about what's happening.

## What we won't copy, and what we'll do better

- Not copying: name, icon, timeline visuals, productivity score styling, AI/MCP/team features, subscription.
- Better: no window titles, URLs, or document paths by default, and no Accessibility or
  Screen Recording prompts at all in v1; nothing ever leaves the Mac; a retention limit
  and one-click delete; event-driven tracking (Timing samples every second).
- Better than built-in Screen Time: a real timeline of *when*, projects, CSV export, idle
  trimming, and no iCloud sharing of the data.

## Edge cases

- Sleep/wake, lid close, lock screen, fast user switching (other user's session must not count).
- Screensaver running; display asleep with the Mac awake.
- Clock/time zone changes and DST (a 23- or 25-hour day).
- Long video watching with no input (idle vs. watching: should).
- Apps without bundle IDs; app renamed/updated (key by bundle ID); our own app in front.
- Crash or force-quit mid-segment (checkpoint); database locked/corrupt (start a new file, keep the old).
- Midnight-spanning segments split across days.
- Huge history (2 years) loads a week view in < 200 ms (indexed by start).

## Our v1 scope

- [ ] Event-driven front-app recording with idle, lock, sleep and screensaver handling.
- [ ] First-run window explaining what's recorded; Launch at login chosen there.
- [ ] Day and week views: timeline + totals by app and project.
- [ ] Projects; assign apps with an "always" rule (retroactive).
- [ ] Never-record app list; pause/resume from the status menu.
- [ ] CSV export of the visible range.
- [ ] Delete selection/day/all (with undo for selection), retention setting.
- [ ] Settings: General, Recording (idle, exclusions, retention), About.
- [ ] Unit tests: segment building from event sequences (activation, idle, lock, sleep,
      midnight, DST), rule matching, totals, CSV.

## Open questions

Decisions (owner defaults, 2026-11-03: native, fast, private, no network):

1. **Window titles:** off and not built in v1. Later as an explicit opt-in with Accessibility.
2. **Browser domains:** later, opt-in per browser, domain only.
3. **Launch at login:** a checkbox on the first-run screen, checked, so the user decides
   once; Settings can turn it off. (Unlike other apps, a tracker that doesn't start with
   the Mac is broken.)
4. **Retention:** 1 year default.
5. **Archetype:** window app plus a status item (recording state lives in the menu bar);
   closing the window does **not** stop recording (exception to "closing quits": Hours
   stays as a menu bar app).

## Sources

- [Timing website](https://timingapp.com/)
- [Timing FAQ (permissions, idle, storage, CPU)](https://timingapp.com/help/faq)
- [Timing press kit](https://timingapp.com/presskit/)
- [ActivityWatch (MPL-2.0)](https://github.com/ActivityWatch/activitywatch)
- [GetApp: Timing](https://www.getapp.com/project-management-planning-software/a/timing)

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.
