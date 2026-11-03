# Glance research (inspired by Dato)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied: Dato
> (Sindre Sorhus; not installed on this Mac) from its detailed product page and FAQ,
> App Store listing, Product Hunt and r/macapps comments, and comparisons with Itsycal, on
> 2026-11-03. Also read our own Zones research and build notes (`docs/research/zones.md`),
> since the two overlap. We never copy names, icons, artwork, wording, sounds or signature
> visuals.

## The job

Glance answers "what day is it, what's next, and how do I join it?" from the menu bar.
macOS's clock has no month view a click away and nothing about your next meeting; opening
Calendar to check the date of next Thursday or to find a Zoom link is slow. People click
Glance many times a day for a month grid and the next few events, and once or twice a
day to join a call one second before it starts. "Done" is the answer (or the call joined)
without Calendar ever coming to the front.

The one interaction that matters most: **click the menu bar date, see the month and the
next events; the next meeting has a Join button; press Return to join.**

## Who and when

- "What date is next Friday?" / "Which week number is this?"
- Glance at the rest of today's meetings between calls.
- Joining a video call from the event's link without hunting in Calendar or email.
- Checking a date's weekday while writing an email.

Frequency: many times a day; each 1–5 seconds.

## Decision: merge with Zones?

**No. Glance stays a separate app, and it does not include world clocks in v1.** Zones is
already built, shipped as beta, and covers world clocks, scrubbing and copying times well;
duplicating that inside Glance would mean two apps showing the same clocks and two
codebases to keep correct across DST. Merging the other way (calendar into Zones) would
add a Calendar permission and a heavier panel to an app that today needs no permission
and idles at 20 MB. People who want both install both; they're small and share the menu
bar look. Consequence: the roadmap tagline ("Your calendar and world clocks…") should
become "Your calendar and next meeting, one click away." (flagged for the lead; not
edited here). If Zones is installed, Glance's panel may offer an "Open Zones" item: later.

## Feature inventory

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Menu bar item | Date/time text with custom formats; icon styles (date in a calendar glyph, static clock, none); follows 24 h; optional seconds | must | Default: a calendar glyph with today's day number (template image rendered from the system font) and no time (the system clock already shows it). Options: icon only, icon + short date ("Tue 3 Nov"), custom format (should). |
| 2 | Month calendar | Month grid, week numbers optional, event dots, highlight weekdays | must | Grid with event dots; today highlighted with the accent color; week numbers optional (off, follows locale's ISO/Gregorian rules). |
| 3 | Navigation | Arrows days/weeks, ⌥-arrows months, ⌥⇧ years, Space today, swipe | must | ←/→ day, ↑/↓ week, ⌥←/→ month, Space or T today; trackpad swipe = month. |
| 4 | Agenda | Upcoming events for the next week (adjustable), reminders optional | must | Selected day's events, or "Today + next 6 days" when today is selected. Time, title, calendar color dot, location. All-day at top. |
| 5 | Join button | Detects links from Zoom, Meet, Teams, FaceTime, Slack, Webex + 50 more in location/notes/URL | must | Local regex table over `event.url`, location, notes (Zoom, Meet, Teams, Webex, FaceTime, Slack huddles, Whereby, Jitsi, GoToMeeting, Chime, Around, Discord). The next meeting with a link gets a prominent Join; Return joins when the panel opens near meeting time. Opens in the default browser/app. |
| 6 | Join next meeting by global shortcut | Yes | should | Unset by default, recorder in Settings. |
| 7 | Event details / open in Calendar | Details popover; double-click edits in Calendar; open in Fantastical/BusyCal/Outlook | must (open in Calendar) / should (details popover) | Double-click or ⌘O opens the event in Calendar. |
| 8 | Calendars selection | Which calendars appear, per feature | must | Settings list of `EKCalendar`s grouped by account with checkboxes. |
| 9 | Declined events / all-day handling | Hidden in some features | must | Hide declined by default. |
| 10 | Create event / reminder with natural language | Global shortcut, title parsing (English), "/" to pick calendar | later | Needs write access; v1 is read-only. "New Event…" opens Calendar at that date (no write permission). |
| 11 | Reminders | Optional in the list, complete from the list | later | Separate Reminders permission. |
| 12 | Upcoming event in the menu bar | Separate item with the next event | should | Optional "in 12 min: Standup" text beside the icon; short, truncated. |
| 13 | Meeting-start notification / full-screen notification | System notification with Join; full-screen takeover option | should (system notification at start, opt-in) / skip (full-screen) | `UserNotifications` asked only when enabled. |
| 14 | Go to date / date calculator | Natural-language "next friday", "+2w"; calculator | later | ⌘G go to date (DatePicker) is cheap: should. |
| 15 | Copy date / week number | Right-click menu bar item | should | Panel context menu: Copy Date (ISO and long), Copy Week Number. |
| 16 | World clocks, time-travel slider, copy times | Built in | skip | Zones does this (see decision). |
| 17 | Hourly chime | Custom sounds | skip | Not the job; no sounds. |
| 18 | Widgets | Calendar, Up Next, world clocks | later | |
| 19 | Redact sensitive info while screen sharing | Hides titles; ⌥ menu toggle | should | A "Hide Titles" toggle in the panel's … menu shows "Busy" instead of titles. Automatic switching while sharing: see Open questions. |
| 20 | Shortcuts actions | Calendar enabled state, notifications state | later | |
| 21 | Launch at login / Show in menu bar | Yes | must | SlopKit General; launch at login off by default. |

### Must-haves, counted

1 menu bar item, 2 month grid, 3 keyboard navigation, 4 agenda, 5 Join, 7 open in Calendar,
8 calendar selection, 9 hide declined, 21 General, plus the Calendar permission flow. Ten.

## Key flows

### Flow 1: glance and join (main job)
1. Click the calendar glyph (or the optional global shortcut). A 320 pt `.window`-style
   panel opens: month grid on top, agenda below.
2. The next event with a meeting link within the next 15 minutes (or in progress) sits at the
   top of the agenda with a Join button, focused: Return joins.
3. Arrows move the selected day; the agenda follows. Esc closes; reopening resets to today.

### Flow 2: first run / Calendar permission
1. Launch: glyph in the menu bar. First click: the grid works immediately (dates, week
   numbers need no permission); the agenda area shows a one-line reason ("Glance shows your
   upcoming events and meeting links. They stay on this Mac.") with **Allow Calendar Access**.
2. The button calls `EKEventStore.requestFullAccessToEvents()` (macOS 14+; Info.plist
   `NSCalendarsFullAccessUsageDescription`). Granted → agenda fills live.
3. Denied → the row changes to "Calendar access is off" + Open System Settings
   (`Privacy_Calendars`), with a live re-check on panel open. No restart needed.

## Settings inventory

| Setting | Default | Options | Keep? |
|---|---|---|---|
| Menu bar shows | icon with day number | icon, icon + date, custom format | must (first two) / should (custom) |
| Next event in the menu bar | off | toggle | should |
| Show week numbers | off | toggle | must |
| Calendars | all | checkbox per calendar | must |
| Show declined events | off | toggle | must |
| Agenda length | 7 days | 1–14 days | should |
| Notify when a meeting starts | off | toggle (asks for notifications) | should |
| Join next meeting shortcut / open shortcut | unset | recorders | should |
| Launch at login / Show in menu bar | off / on | toggles | must |

## Menus and shortcuts

Panel: ←/→/↑/↓ days/weeks, ⌥←/→ months, Space/T today, Return join (when a Join is
focused), ⌘O open selected event in Calendar, ⌘C copy event (title, time, link), ⌘G go to
date, ⌘R refresh, ⌘, Settings, ⌘Q Quit, Esc close. A "…" menu in the panel lists all of
these with shortcuts plus `MenuFooter` items.

## Permissions and system integration

- **Calendars (full access)**: asked in context on first open of the agenda, not at launch.
  SlopKit's `Permission` enum has no `.calendars` case yet: add one (status via
  `EKEventStore.authorizationStatus(for: .event)`, pane `Privacy_Calendars`, no relaunch).
- Notifications only if the user enables meeting-start alerts.
- Live updates via `EKEventStoreChanged`; no polling. Day rollover via
  `NSCalendarDayChanged`; time zone via `NSSystemTimeZoneDidChange`.
- No network: links open in the user's browser by user action only.

## UX patterns worth adopting

- **The next call's Join is the default button**: one click/Return from menu bar to meeting.
- **Read-only by design**: Calendar stays the editor; Glance never risks changing events.
- **The grid works before permission**, so the first click is useful.

## What we won't copy, and what we'll do better

- Not copying: name, icon styles, chime, full-screen notification, natural-language
  creation, wording.
- Better: one job (no clocks duplicated with Zones), no network, permission asked in
  context with the grid already working; quiet defaults (no notifications unless asked).

## Edge cases

- Permission denied/restricted, granted later in System Settings while running.
- No calendars / all disabled: `ContentUnavailableView` with Choose Calendars….
- Many events in a day (20+): agenda scrolls inside a capped height (≤ 480 pt panel).
- All-day multi-day events; events crossing midnight; time zone changes while travelling;
  DST days.
- Duplicate events across subscribed calendars (same title/time): show once (should).
- Links in HTML notes; multiple links (prefer the meeting-provider one).
- Week start and week numbers per locale (ISO vs US); right-to-left locales; non-Gregorian
  calendars (follow `Calendar.current`).
- Crowded/notched menu bar: icon-only default keeps it narrow.

## Our v1 scope

- [ ] Menu bar glyph with day number; optional short date.
- [ ] Panel: month grid with event dots, week numbers option, keyboard navigation, today reset on reopen.
- [ ] Agenda for the selected day / next 7 days; declined hidden; calendar colors.
- [ ] Meeting-link detection (unit-tested table) and Join (Return when focused).
- [ ] Open event in Calendar; copy event.
- [ ] Calendar permission in context; grid works without it; live re-check.
- [ ] Settings: General (launch at login, menu bar style, week numbers), Calendars, Shortcuts, About.
- [ ] Unit tests: link detection, agenda building (all-day, multi-day, declined, DST, time zone change), week numbers per locale, grid layout per locale.

## Open questions

Decisions (owner defaults, 2026-11-03: native, fast, private, no network):

1. **Merge with Zones:** no (see above). Glance drops world clocks; roadmap tagline should change.
2. **Write access (create events/reminders):** later; v1 is read-only.
3. **Meeting notifications:** should, off by default.
4. **Redacting titles while screen sharing:** should, as a manual "Hide Titles" toggle;
   automatic detection only if a public signal is reliable (verify during build).

## Sources

- [Dato](https://sindresorhus.com/dato)
- [Dato on the Mac App Store](https://apps.apple.com/za/app/id1470584107)
- [Dato reviews on Product Hunt](https://www.producthunt.com/products/dato/reviews)
- [r/macapps thread comparing Dato and Itsycal](https://reddit.birdcat.cafe/r/macapps/comments/1ewr0qt/my_free_macos_apps)
- [MacUpdate: Dato](https://Macupdate.com/app/mac/61666/dato)
- Apple: EventKit (`requestFullAccessToEvents`, `EKEventStoreChanged`).
- Our own `docs/research/zones.md`.

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.
