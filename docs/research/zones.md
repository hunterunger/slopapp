# Zones research (inspired by World Clock Pro)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied: World
> Clock Pro 1.8.6 (build 25101601.136, Setapp build, bundle
> `com.komarovmobile.macworldclock-setapp`; installed copy at
> /Applications/Setapp/World Clock Pro.app, read-only) + its Setapp and Mac App Store
> listings and release notes, plus comparable menu bar clocks (Clocker, Zone Bar, Time,
> Dot), on 2026-11-03. We study how it works so we don't reinvent the wheel. We never copy
> its name, icons, artwork, wording, sounds or signature visuals.
>
> World Clock Pro was not running; it was launched for this study and quit afterwards
> (including the menu bar companion it starts on its own). No setting was toggled. Its city
> list is personal (it can reflect where the owner's contacts live), so only its *layout* is
> described here, never its content, and the main window was never screenshotted. A probe
> of the add-city search was cleared without adding anything; a relaunch confirmed the city
> list was unchanged. Screenshots of Settings panes stay in `/tmp/slopdrive`.

## The job

Zones answers "what time is it there, and when is a good time for all of us?" without
mental arithmetic. People who work with a distributed team, clients abroad or family in
other countries reach for it many times a day for a glance ("is it too late to ping
them?") and a few times a week for planning ("if I propose 4 pm my time, what is that for
the others, and is anyone asleep?"). "Done" is knowing the answer in under two seconds,
and, when planning, having a pasteable line of times to drop into a message.

The one interaction that matters most: **click the menu bar icon (or press a shortcut),
see every place's current time with a day/night cue; drag or arrow across the list to
slide time forward, read off everyone's time at once, press ⌘C to copy that moment in
all zones.**

## Who and when

- A glance before messaging a colleague: is it working hours for them, or 11 pm?
- Proposing a meeting time: slide to "tomorrow 9 am" locally and check nobody lands at night.
- Receiving "let's talk at 3 pm London" and translating it to local time (a top complaint
  about the original: it couldn't do this directly).
- Writing an invite or Slack message and pasting "11:00 Chicago · 17:00 London · 02:00
  (Wed) Tokyo".
- Travelling: local time follows the Mac's time zone, home stays in the list.

Frequency: glances many times a day (1–3 seconds each); planning a few times a week (10–60
seconds). Setup (adding places) is rare.

## How the original is built (observed)

- **Two processes.** A full window app with a Dock icon (map + city cards + converter),
  plus a separate sandboxed menu bar companion app bundled inside it
  (`Contents/MacOS/Menu/World Clock Pro Menu.app`, macOS 14+, SwiftUI/TCA). Closing the
  main window launches the companion. The menu bar mode was bolted on in 1.8 (Feb 2025),
  six years after the window app.
- **Bundled city database** (`city.db`, SQLite, 15 MB, ~141k places with country,
  region, IANA zone, coordinates, population, capital flag; an unused airport-code column).
  It also fetches database updates over the network.
- **Network and tracking:** Amplitude analytics, Sentry crash reporting, RevenueCat, a
  weather service. A Setapp reviewer removed it over the RevenueCat traffic.
- **Permissions:** Location (both processes, to name your local city and follow you when
  travelling; the menu bar companion has a "Precise Location" item), Calendars (to create
  events from a chosen time, with alert offsets).
- The menu bar companion's status item was not reachable through Accessibility on this Mac
  (it appears to sit behind the notch overflow), which matches the original's own
  onboarding page devoted to "can't see the icon". Its panel was studied from the Settings
  preview image, the companion's action names and the release notes instead.

## Feature inventory

Priority: **must** (v1 isn't worth shipping without it), **should** (v1 if cheap, else
v1.1), **later**, **skip** (with reason).

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Menu bar panel listing places | Companion app: a popover with one row per place: name (location arrow on the local one), a subline with relative day + offset ("Tomorrow, −14hrs"), a large time on the right tinted by time of day | must | `MenuBarExtra` with `.window` style (rich content), 320 pt wide. Row: name, subline "Tomorrow · +7 h", time in `.title2` `.monospacedDigit()`. |
| 2 | Local time row | "Enable Local Time" setting; local city from Location Services, follows you when travelling | must | Use `TimeZone.current`, refresh on `NSSystemTimeZoneDidChange`. No Location permission. Label = the city part of the zone ID ("Chicago") or the user's rename; pinned first, can't be removed, can be hidden. |
| 3 | Day/night cue | Time digits colored by time of day in the menu panel; a daylight strip and a day/night map in the window | must | A small SF Symbol per row (`sun.max` / `sunset` / `moon`) driven by hour bands, plus `.secondary` styling at night. Semantic colors only, never color alone (VoiceOver + color blindness). |
| 4 | Add a place by search | Title-bar search field: empty query lists big cities by population with their current time; typing matches city, country, or a zone abbreviation ("PST" → "PST, Timezone"); ⌘N "Add City" | must | Offline: bundled city list (see Open questions on GeoNames vs Natural Earth) + `TimeZone.knownTimeZoneIdentifiers` + abbreviations + "UTC", "GMT±N". Diacritic/case-insensitive prefix match, ranked by population. Show "City, Region, Country" and current time per result. Arrows + Return to add, Esc to cancel. |
| 5 | Remove / reorder places | Cards in the window have a per-card button; order by drag in the window | must | Drag to reorder in the panel's edit mode and in Settings; right-click → Remove; ⌫ on a selected row. Undo (⌘Z) for remove. |
| 6 | Rename a place | Not observed in the original (Clocker and Zone Bar offer custom labels; Zone Bar adds emoji) | should | "Mum", "Berlin office". Right-click → Rename…. |
| 7 | Time scrubber | Window: "drag to convert time" across a timeline with a Now reset button; menu panel: drag horizontally on the list, a vertical line with a "+2:49 ×" delta chip, auto-reset after idle; 1.8.3 added picking future dates and keeping focus on local time | must | Horizontal drag anywhere on the list, scroll wheel/trackpad, ←/→ (15 min), ⇧←/→ (1 h). A chip shows "+3 h 15 min · Wed 4 Nov" with a reset button; Esc or the chip's × resets to now. Reset when the panel closes (no stale scrubbed time on next glance). |
| 8 | Jump to a date | 1.8.3: pick future dates in the menu panel | should | Compact `DatePicker` in the chip (or ⌘D). Needed to plan around DST changes and next week's meetings. |
| 9 | Type a time for a zone | Not supported; a Setapp reviewer wanted exactly this ("enter the meeting time and zone, get my time") | must (owner decision) | Click a row's time (or press Return on a selected row), type "3pm" / "15:30", every row follows. Parsing is small and local. |
| 10 | DST-correct offsets | Offsets come from its own data; a reviewer reports it was wrong during the weeks when US and EU DST differ | must | Always compute per instant with `TimeZone.secondsFromGMT(for:)` at the *scrubbed* date, never cache "offset now". Unit-test the US/EU mismatch weeks, southern hemisphere, half-hour zones. |
| 11 | Upcoming DST change hint | Not observed | should | Subline note when a zone changes within 7 days: "Clocks go back Sun". `nextDaylightSavingTimeTransition(after:)`. Cheap and prevents missed meetings. |
| 12 | Copy times in all zones | Companion has "Copy Times"; the window had a share sheet | must | ⌘C (and a button) copies the scrubbed (or current) instant in every listed zone as plain text. Absolute dates, never "Tomorrow" (the reader isn't here). Default format: one line per place, "Tue 3 Nov, 11:00 AM: Chicago". |
| 13 | Copy formats | Not observed beyond one format | should | Settings picker: list (default), single line ("11:00 Chicago · 17:00 London"), with UTC offsets, ISO 8601. Per-row copy via right-click → Copy Time. |
| 14 | Optional second clock in the menu bar | Original shows only an icon (menu bar mode); the macOS clock can't show other zones | must | Setting: menu bar shows icon only (default), or icon + one chosen place ("LON 17:20"). Keep it short to survive notch overflow. |
| 15 | More than one menu bar clock | Not in the original (Clocker, Zone Bar do it) | later | Each extra item widens the menu bar and risks the notch. Revisit if asked. |
| 16 | 12/24-hour format | "Use system regional settings" (on) else 12/24 radio | must (system) / should (override) | `Date.FormatStyle` follows the system for free; override is one picker. |
| 17 | Seconds | Analog/digital clock face options (hide second hand, seconds animation) | skip | Glanceable times don't need seconds, and per-second redraw costs CPU. Update on minute boundaries. |
| 18 | Working-hours shading | Not observed (Time and Dot users ask for "focus hours") | should | Per-place working hours (default 9–17) shown as a subtle band in the scrubber; rows outside working hours read as `.secondary`. Answers "can I ping them?" directly. |
| 19 | Fixed UTC offset entries | Adds "UTC" and "GMT" as zones | must (UTC) / should (UTC±N) | UTC is essential for devs/pilots. Fixed offsets don't follow DST: label them clearly. |
| 20 | Airport code search | Database has an IATA column, unused | later | OurAirports data is public domain; small add-on index. |
| 21 | Global shortcut to open the panel | None found | should | `KeyboardShortcuts`, unset by default, recorder in Settings. Also the escape hatch when the icon is hidden behind the notch. |
| 22 | Open/close panel from keyboard | n/a | must | Esc closes; ⌘, Settings; ⌘Q Quit; ⌘C copy; ⌘N add place. |
| 23 | World map with city pins, day/night terminator | Large map is the window app's centrepiece | skip (v1) / later | Signature visual of the original and costly; the list answers the question faster. A tiny day/night strip per row is enough. |
| 24 | Weather per city | Live weather on the map | skip | Needs network and an API key; not the job. |
| 25 | Add to calendar | Picks the scrubbed time, creates an event via EventKit with an alert ("10 minutes before" default), shows a confirmation bezel | later | Needs Calendar permission. A cheaper later path: "New Event at This Time" writes a temporary `.ics` and opens it in Calendar, no permission. |
| 26 | Share a meeting time as a link / QR | "Copy Link"/"Copy URL" to a hosted page, QR code, "Share Timezones" | skip | Needs a server and sends data out. Copying text covers it. |
| 27 | Join meeting links / calendar day view | Not in the original (Time, Dato do it) | skip | A different app (calendar). |
| 28 | Widget | Notification Center widget (broke on Big Sur per reviews) | later | WidgetKit extension; macOS already has a Clock widget. |
| 29 | Screensaver | World map screensaver | skip | Not the job. |
| 30 | Touch Bar + trackpad haptics while scrubbing | Touch Bar time strip; "Haptic feedback when scrolling time" (on) | skip / should (haptic) | Touch Bar is gone. A light `NSHapticFeedbackManager` tick at each hour while dragging is cheap: should. |
| 31 | Launch at login | General: "Start at login" (off); onboarding asks with an OFF switch | must | Standard SlopKit toggle, off by default (owner decision). |
| 32 | Show/hide in menu bar | "Enable Menubar app" checkbox | must | Standard SlopKit "Show in menu bar"; relaunch brings it back. |
| 33 | Onboarding / What's New | Three-page sheet on every launch (menu bar intro with a pre-checked "turn on" box, a page on hidden menu bar icons, a launch-at-login switch), then a five-slide feature tour; "show this window when the app opens" is on by default; modal sheets block Quit | skip | Design system: no tours, no what's-new. First run seeds sensible places and the panel explains itself. |
| 34 | Rating prompts, feedback email, social links, cross-promo | "Are you enjoying…", Help menu links to Facebook/Twitter, banners for a sister iPhone app inside the menu panel | skip | Not our style. |
| 35 | Location-based local city | Location Services, "Precise Location" | skip | Permission for little gain; the system time zone is the truth. |
| 36 | City DB updates over the network | "Automatic time zone database updates" (premium) | skip | Zone rules come from macOS (tzdata updates with the OS). City names don't change often; ship updates with app releases. |
| 37 | Sort places by offset | Not observed (Clocker offers it) | should | One menu item: "Sort by Time Difference". |
| 38 | Shortcuts / App Intents | None | later | "Time in <place>", "Copy times at <time>". |
| 39 | iCloud sync of the list | Shared app groups with its iOS app | skip | No accounts, no network. |

### Must-haves, counted

1 panel list, 2 local row, 3 day/night cue, 4 offline search, 5 remove/reorder, 7 scrubber,
10 DST-correct math, 12 copy times, 14 optional second clock, 16 system 12/24 h, 19 UTC,
22 keyboard basics, 31/32 standard General settings. Thirteen, most of them small; the real
work is #4 (search + data) and #7 (scrubber).

## Key flows

### Flow 1: glance (the main job)
1. Click the globe in the menu bar (or press the optional global shortcut).
2. The panel opens instantly under the icon: local row first, then the user's places in
   their order. Each row: name; subline with relative day and offset ("Tomorrow · +7 h");
   time on the right; a sun/moon symbol.
3. Esc, a click outside, or clicking the icon again closes it. Nothing else to do.

### Flow 2: plan a meeting
1. Open the panel. Drag left/right on the list (or ←/→, scroll) to slide time in 15-minute
   steps. A vertical marker and a chip show the delta ("+3 h 15 min") and the date.
2. Each row's time, day label and day/night symbol update live; offsets are recomputed for
   that instant (correct across DST changes).
3. Optional: click the chip's date to pick another day; or click a row's time and type "3pm"
   to set the moment in that place's time.
4. Press ⌘C (or the Copy button). A small HUD says "Copied". Pasted text lists the moment
   in every zone with absolute weekday and date.
5. Esc resets to now; closing the panel also resets.

### Flow 3: add a place
1. In the panel, press ⌘N or click "+" (Add Place). A search field appears at the top of
   the panel, focused.
2. Empty query shows a short list of large cities. Typing "par" shows Paris, France first
   (population ranking), then Parma, etc. "pst", "cet", "utc", "gmt+5:30", "Europe/Paris"
   also match.
3. Each result shows "City, Region, Country" and its current time.
4. ↑/↓ to move, Return to add, Esc to cancel. The new row appears at the bottom, briefly
   highlighted (fade under Reduce Motion).

### Flow 4: first run
1. Launch: the globe appears in the menu bar; no window, no tour.
2. The panel already contains the local row and **UTC** only, plus an inline empty-state line
   with one action: "Add Place…" (⌘N). (Alternative: seed 2–3 big cities; see Open questions.)
3. No permissions are requested at any point.

### Flow 5: menu bar clock
1. Settings → General (or right-click a row → "Show in Menu Bar").
2. Choose "Menu bar shows: Icon only / Icon and one place's time"; pick the place.
3. The status item now reads e.g. "🌐 LON 17:20" (SF Symbol, not emoji), updating on the
   minute.

## Settings inventory

Original (all observed in Settings, three toolbar tabs):

| Pane | Setting | Default | Options | Keep? |
|---|---|---|---|---|
| General | Start at login | off | on/off | yes (SlopKit "Launch at login") |
| General | Enable Local Time | on | on/off | yes, as "Show local time" |
| General | Haptic feedback when scrolling time | on | on/off | no setting; just do a light tick (should) |
| General | Event alerts | 10 minutes before | none, at time of event, 5/10/15/30 min, 1/2 hours, 1/2 days before | no (no calendar in v1) |
| Clocks | Hide seconds hand (analog faces) | off | on/off | no (no analog faces) |
| Clocks | Show digits (analog faces) | off | on/off | no |
| Clocks | Disable seconds animation (digital faces) | off | on/off | no (no seconds) |
| Clocks | Use system regional settings | on | on/off | yes |
| Clocks | 12-hour / 24-hour (disabled while system is used) | 12-hour | radio | yes, as a picker "System / 12-hour / 24-hour" |
| Menu app | Enable menu bar app | owner's install: on | on/off | yes, SlopKit "Show in menu bar" |

Ours (proposed):

| Tab | Setting | Default |
|---|---|---|
| General | Launch at login | per SlopKit default |
| General | Show in menu bar | on |
| General | Menu bar shows | Icon only (alt: Icon and time of [place]) |
| General | Show local time | on |
| General | Time format | System |
| General | Copy format | List (alt: Single line, With UTC offsets, ISO 8601) |
| General | Places (list editor: reorder, rename, remove, working hours) | local + UTC |
| Shortcuts | Open Zones | unset |
| About | AboutView + data attribution | |

## Menus and shortcuts

Original main menu (window app):

- **App**: About, Settings… ⌘,, Services, Hide ⌘H, Hide Others ⌥⌘H, Quit ⌘Q.
- **File**: Add City ⌘N.
- **Edit**: standard (Copy ⌘C etc., disabled in practice).
- **Window**: standard, plus the main window ⌘1.
- **Help**: link to the sister iPhone app, Email feedback, What's new, Take a tour, Facebook, Twitter.

Original menu bar companion (from its action names and release notes): add a time zone
(opens the main app), open the app, copy times, share time zones, and a settings menu with
Precise Location, Settings, Quit. Promotional banner for the iPhone app inside the panel.

Ours (panel is a `.window` MenuBarExtra, so put actions in a footer row + a "…" menu):

| Action | Shortcut (panel focused) |
|---|---|
| Add Place… | ⌘N |
| Copy Times | ⌘C |
| Reset to Now | Esc (first press when scrubbed; second press closes) |
| Scrub ±15 min / ±1 h | ← → / ⇧← ⇧→ |
| Move selection | ↑ ↓ |
| Remove place | ⌫ (undo ⌘Z) |
| Rename… / Show in Menu Bar / Copy Time | right-click a row |
| Sort by Time Difference | footer "…" menu |
| Settings… | ⌘, |
| About Zones | footer |
| Quit Zones | ⌘Q |
| Open panel (global) | user-set, unset by default |

## Permissions and system integration

- **None required.** No Location (system time zone is enough), no Calendars (no event
  creation in v1), no Accessibility, no network.
- Login item via `SMAppService` (SlopKit).
- Listen to `NSSystemTimeZoneDidChange`, `NSSystemClockDidChange`, `NSCalendarDayChanged`,
  `NSCurrentLocaleDidChange` (12/24 h), and `NSWorkspace.didWakeNotification` to resync the
  minute timer.
- Later: App Intents, WidgetKit, `.ics` hand-off to Calendar.

## UX patterns worth adopting

- **Drag the list itself to move time.** No separate slider to find: the whole panel is the
  scrubber, with a thin vertical marker and a delta chip that doubles as the reset button.
  The original's menu panel does this well.
- **Delta, not just absolute.** The chip says how far from now you are ("+2 h 45 min"), so
  "in three hours" questions need no arithmetic.
- **Relative day + offset in one quiet subline** under each name ("Tomorrow · −14 h"),
  with the big number reserved for the time.
- **Auto-return to now.** A scrubbed panel must not greet the next glance with a stale time;
  the original resets after idle, we reset on close.
- **Search that already knows the answer**: an empty query lists the biggest cities with
  their current time, so many adds are a click away; abbreviations ("PST") work.
- **Time-of-day tint** lets you scan for "who's asleep" without reading numbers (we add a
  symbol so it isn't color-only).
- **Follow system 12/24 h by default** with an override hidden in Settings.

## What we won't copy, and what we'll do better

- Not copying: name, globe/clock artwork, the map, analog faces, wording, the tour videos,
  colors, the "pulse" local marker, upsell and rating flows.
- **One process, no Dock icon.** The original is a window app with a menu bar companion
  bolted on, two processes, and a promotional banner inside the menu. Zones is only the
  menu bar panel.
- **Correct DST, always.** Compute offsets per instant from the OS time zone database, and
  test the weeks when the US and EU are out of step (a Setapp review reports the original
  got this wrong). Show upcoming changes.
- **Convert "their time" to mine** directly: type a time on any row (a review's main
  complaint).
- **No network, no tracking.** The original ships Amplitude, Sentry and RevenueCat and a
  reviewer uninstalled over it. Zones makes zero network requests.
- **No permissions.** No Location prompt for something the system time zone already knows.
- **Quiet first run.** No three-page what's-new sheet on every launch, no tour, no modal that
  blocks Quit (observed: the original couldn't be quit via Apple Events while its sheet was up).
- **Reachable when the icon is hidden.** The original devotes an onboarding page to its
  icon disappearing behind the notch. We keep the status item narrow (icon only by default)
  and offer a global shortcut to open the panel anyway.
- **Pasteable text that makes sense to the recipient**: absolute weekday/date, not
  "Tomorrow".
- **Accessible**: every row reads as one VoiceOver sentence; the original's controls were
  mostly unlabeled (city cards, Now reset, add button, window buttons all `[unlabeled]`).
- **Light**: update on minute boundaries only; city data loaded only when searching.

## Edge cases

**Time math (unit tests in `ZonesCore`)**
- US/EU DST mismatch: 2026-03-08 → 03-29 and 2026-10-25 → 11-01, New York–London is 4 h
  instead of 5 h. Scrubbing into/out of those weeks must change the shown offset.
- Southern hemisphere DST (Sydney, Santiago) moves the opposite way; Lord Howe Island
  shifts by 30 minutes.
- Non-hour offsets: India +5:30, Nepal +5:45, Chatham +12:45 (+13:45 in DST), Newfoundland
  −3:30. Offset text: "+5 h 30 min" / "+5:30".
- Extreme spread: Kiritimati +14 vs Baker/Howland −12 (26 h): "Tomorrow" and "Yesterday"
  in the same list; a place can be two calendar days away from another.
- Scrubbing across local midnight, across the date line, and across a DST gap: 15-minute
  steps in UTC instants (not wall-clock) so a spring-forward gap doesn't produce a
  nonexistent time or a stuck scrubber; fall-back repeated hour shows the right abbreviation.
- Typed times (should): "2:30 am" on a spring-forward day in that zone doesn't exist →
  move to the next valid time and say so; an ambiguous fall-back time → pick the first.
- Zones whose rules changed recently (e.g. Kazakhstan unified offsets in 2024; Mexico
  dropped DST in 2022): we rely on the OS tzdata, never on a bundled offset.
- Zones with no DST, and `TimeZone.abbreviation()` returning "GMT+2" for many non-US zones:
  show the abbreviation only when it's a real letters abbreviation; otherwise the offset.
- Ambiguous abbreviations in search: CST (US Central, China, Cuba), IST (India, Ireland,
  Israel), BST: show every match with its country/zone name.
- Fixed UTC±N entries: never shift with DST; labeled as fixed.

**System**
- Mac's time zone changes while running (travel, manual change): local row updates
  immediately, offsets recomputed.
- Sleep/wake and clock changes: the minute timer resyncs; no drift, no stale minute.
- Midnight rollover: "Today/Tomorrow" labels update.
- Locale change (12/24 h, first weekday, language): formats follow without relaunch.
- Menu bar overflow/notch: status item hidden by macOS; global shortcut still opens the
  panel. Menu bar clock text kept short.
- Multiple displays: panel opens under the icon on the active display.
- Dark/light mode and accent colors; Increase Contrast.
- Reduce Motion: scrubbing marker moves without easing; add-row highlight fades.

**Data and input**
- Empty list (only local, or local hidden and nothing added): empty state with one action.
- Many places (20+): the panel caps at ~480 pt and scrolls; the scrub gesture still works
  (horizontal drag vs vertical scroll must not fight: vertical = scroll list, horizontal =
  scrub; arrow keys always work).
- Duplicate names (Springfield, US has several; San José CR vs CA): show region and country.
- Non-ASCII search ("Zürich" / "zurich", "São Paulo" / "sao paulo", "Kraków", CJK names via
  alternate names): diacritic- and case-insensitive.
- The same zone added twice under two labels (two offices in the same city): allowed.
- Copy with nothing scrubbed copies "now"; with one place, still copies (local + it).
- Pasted text in RTL apps and plain-text fields: no emoji, no special separators by default.

**Accessibility**
- VoiceOver row: "London, 5:20 PM, tomorrow, 7 hours ahead, night." Scrubber exposed as an
  adjustable element (VoiceOver swipe up/down = ±15 min).
- Keyboard only: open with the shortcut, scrub, copy, add, remove, close.

## Our v1 scope

Status after the build (2026-11-03): every item built and walked through on the release
build, except where noted.

- [x] Menu bar globe icon; click opens a 320 pt panel listing places; Esc / click outside / ⌘W closes.
- [x] Local time row first (from the system time zone, no Location permission), follows a time zone change live; can be hidden in Settings.
- [x] Each row: name, current time (`.monospacedDigit()`), relative day ("Yesterday/Today/Tomorrow"), offset vs local ("+7 h", "+5 h 30 min"), day/night symbol.
- [x] Add a place offline: ⌘N / + opens search; matches city (diacritic-insensitive), country, IANA ID, abbreviation, UTC/GMT±N; results show region, country and current time; ↑↓ Return adds, Esc cancels.
- [x] Remove a place (right-click → Remove, or ⌫), undo with ⌘Z; reorder by drag (vertical drag on a row in the panel, walked through; Settings → Places uses a standard `List.onMove`, not exercised by mouse because a system prompt covered that part of the screen).
- [x] Scrubber: horizontal drag / scroll / ←→ (15 min) / ⇧←→ (1 h) moves time for all rows; chip shows delta and date; Esc or Now resets; closing the panel resets. (Two-finger horizontal swipe is implemented but couldn't be exercised by the automation tool.)
- [x] Offsets and day labels computed for the scrubbed instant (correct in US/EU mismatch weeks, southern hemisphere, half-hour zones, across DST gaps). Unit-tested with a fixed clock.
- [x] Copy Times (⌘C + button): every row at the current or scrubbed instant, absolute weekday/date, plain text; "Copied" HUD.
- [x] Menu bar shows icon only (default) or icon + one chosen place's time (also "time only"), set in Settings or a row's context menu; updates on the minute.
- [x] Times follow the system 12/24-hour setting and update on locale change.
- [x] UTC available as a place.
- [x] Settings (General: Launch at login, Show in menu bar, Menu bar shows, Show local time; About with data attribution). ⌘, opens, ⌘Q quits from the panel.
- [x] Places persist across relaunch (UserDefaults).
- [x] No network traffic, no permission prompts.
- [x] Idle CPU < 0.2% with the menu bar clock on (0.06% measured over 60 s; minute-aligned timer); memory < 50 MB with the city index loaded (41 MB while searching, 20 MB idle).
- [x] VoiceOver names every row and control; no `[unlabeled]` in `scripts/drive tree`.
- [x] **Type a time on a row** (owner made it a must): click the time, Return, or type a digit; "3pm", "9:30 am", "15:30", "noon"; DST gap/overlap explained.

Shoulds built too (cheap once the core existed): rename places; jump by day (⌥←/⌥→);
upcoming DST change hint; copy format options (list, single line, ISO 8601) and per-row
copy; 12/24 h override; global shortcut to open the panel (unset by default; also opens it
when the icon is hidden or behind the notch); fixed UTC±N; sort by time difference; haptic
tick per hour while dragging.

Not built (later): working-hours shading (#18), date picker (⌥←/→ covers day jumps).

## Open questions

Decided (owner defaults, 2026-11-03):

1. **City data:** GeoNames `cities15000` (CC BY 4.0). `apps/Zones/Tools/build-cities.py`
   downloads it plus `admin1CodesASCII.txt` and writes a 1.5 MB raw-DEFLATE TSV (name,
   folded search keys incl. capitalized Latin exonyms, codes like NYC and CJK names, country,
   region, population, zone; no coordinates). Credited in the About window, Settings →
   About, the README and `apps/Zones/THIRD_PARTY.md`.
2. **First run:** local time + UTC, with an inline hint and an "Add Place…" button.
3. **Menu bar clock:** must, one place. Options: icon only (default), icon and time, time only.
4. **Typed time on a row:** must. Built.
5. **Calendar hand-off:** later.
6. **Launch at login:** off by default (standard SlopKit toggle).

Builder decisions:

- **NSStatusItem + NSPopover instead of `MenuBarExtra(.window)`**: needed for the global
  shortcut, the clock text beside the icon, reset-on-close and Esc semantics. A hidden
  `MenuBarExtra(isInserted: false)` stays as the first scene so SwiftUI doesn't open
  Settings at launch.
- **Row mouse handling in AppKit** (`AppController.handleMouseDown`): SwiftUI drag gestures
  on rows with context menus inside a popover never saw the drag (a drag became a tap).
  Horizontal drag scrubs (3 min per point, snapped to quarter hours), vertical drag
  reorders, a click selects, a click on the time starts typing one.
- **Scrub steps** move to the next 15-minute/1-hour mark of local wall time, in real elapsed
  time, so the repeated hour when clocks go back is stepped through and the missing hour is
  skipped. Day steps keep the wall time (09:00 stays 09:00 across a change).
- **Typed time** lands on the day that row currently shows; bare numbers are 24-hour ("3"
  is 03:00). A nonexistent time moves to the first valid instant with a note; an ambiguous
  one picks the first occurrence with a note.
- **Abbreviations in copied text**: macOS only has letter abbreviations for US zones in
  English ("EST"); elsewhere Zones writes "UTC+9" rather than ICU's "GMT+9", which is
  unambiguous for the reader. Search has its own curated abbreviation table (PST, CET, IST…).
- **Offsets** read "+26 h" (never days); the time chip reads "+1 d 2 h".
- **Search ranking**: exact name (3+ letters) → abbreviation → name prefix → alternate name →
  any key prefix → word inside a name → cities of a matching country; population breaks
  ties. Byte-level `memmem` over one buffer: a few ms per keystroke.
- **Memory**: the city list loads on first search (mmap + Compression into a scratch mapping,
  single-pass parse, ~6 MB resident) and is dropped 30 s after the panel closes.
- **Menu bar text** is "LON 7:59 AM": a renamed label up to 8 characters, else initials of
  multi-word names ("NYC", "LA") or the first three letters.

## Build notes (2026-11-03)

- **Tests:** 72 Swift Testing tests in 6 suites (`scripts/test.sh Zones`): US/EU mismatch
  weeks (11 instants, both springs and autumns), Sydney/Santiago/Lord Howe (30-min shift),
  Kolkata/Kathmandu/Chatham/St John's/Adelaide/Eucla offsets, Kiritimati vs Baker Island
  (+26 h, two days apart), Samoa vs American Samoa, scrubbing through spring-forward and
  fall-back, typed-time parsing and DST gap/ambiguity, copy formats, menu bar tags, search
  (diacritics, CJK, NYC, abbreviations, offsets, IANA ids, comma filter, speed), model
  (first run, persistence, remove/undo, move, rename, Esc semantics, time zone change).
- **check.sh Zones --perf:** all green. Launch 152 ms, first status item 266 ms, idle CPU
  0.002 % (lowest window), footprint 20.4 MB. With the menu bar clock on: 37 ms CPU per
  minute (0.06 %). While searching: 41 MB.
- **Walkthrough** (release build, `scripts/drive`, screenshots in `/tmp/zones-test/`): first
  run (local + UTC + hint), ⌘N search → Return adds (Tokyo, London, Kathmandu), arrow /
  ⇧ / ⌥ scrubbing, Now reset, Return → type "9am" on Kathmandu, invalid entry message,
  ⌘C (pasted text checked), Esc twice (reset, then close), ⌫ remove + Undo bar + ⌘Z,
  mouse drag sideways (+3 h) and vertical reorder, right-click menu → Rename, ⋯ menu with
  all shortcuts, About window with GeoNames credit, Settings (all four tabs), menu bar
  "time only" ("LON 7:59 AM"), global shortcut recorded and opening the panel from
  Calculator with the icon hidden (anchored under the menu bar), relaunch restores a hidden
  icon. Light (`ZONES_APPEARANCE=light`) and dark. Pinned clock in the US/EU mismatch week
  (London +4 h) and the week before the EU change ("Clocks go back 1 h on Sun").
- **Accessibility:** no `[unlabeled]` in the panel, search, ⋯ menu, About or any Settings
  tab. Rows read as one sentence ("London, 3:00 PM, today, 4 hours ahead, daytime");
  the time header is adjustable (±15 min).
- **Bugs found and fixed while testing:** Settings opened at launch (SwiftUI's first scene);
  toggling "Show in menu bar" crashed (status item visibility writes UserDefaults, which
  re-triggered our observer: infinite recursion); search rows rendered stale results
  (`.id(index)` in a LazyVStack); 2-letter exact matches ("Tô") beat Tokyo; drags became
  taps (moved to AppKit tracking); quick reopen after Esc toggled closed (close now
  unanimated); panel sometimes not key after reopening (retry focus); ⌘C/⌘Z/⌘Q hidden in
  SwiftUI's menu (⋯ is now an NSMenu); city list load retained ~8 MB of NSData buffers.
- **Environment note:** on the owner's crowded notched menu bar, a wider item ("icon and
  time") can be pushed out of view by macOS. That's why icon-only is the default and the
  global shortcut exists; the panel then anchors under the menu bar.
- **Design checklist (§10):** 1 pass (click → glance; ⌘C copies), 2 pass (system popover,
  materials, accent, no hex), 3 pass (every action in ⋯ with its shortcut), 4 pass, 5 pass
  (+ Places tab), 6 pass, 7 pass (first-run hint; "No places to show" + Add Place…; no
  search matches explains what to type), 8 n/a (no permissions), 9 pass (Undo for remove),
  10 pass (no network code), 11 pass, 12 pass, 13 pass (popover animation off under Reduce
  Motion; reorder animation off), 14 pass (Settings window size remembered; places persist).

## Sources

- World Clock Pro on Setapp (features, version 1.8.6, 89% of 435 ratings, reviews incl. DST and RevenueCat complaints): https://setapp.com/apps/world-clock-pro
- World Clock Pro on the Mac App Store (description, full version history incl. 1.8 menu bar mode and 1.8.3 future dates, reviews): https://apps.apple.com/us/app/id858446756
- Installed copy, read-only: /Applications/Setapp/World Clock Pro.app (menus, Settings panes, onboarding sheets, search behaviour, bundle structure, entitlements, `city.db` schema)
- Zone Bar (FAQ on DST, fixed offsets, offline use, minute updates, copy via right-click): https://sindresorhus.com/zone-bar
- Clocker (MIT, time slider, labels, copy all times): https://github.com/n0shake/clocker and https://apps.apple.com/us/app/clocker-menubar-world-clock/id1056643111
- Time 1.4 on Product Hunt (click-to-set time, fixed UTC offsets, date picker, per-zone menu bar display, "focus hours" request): https://www.producthunt.com/p/time-time-zones-in-your-menu-bar/time-1-4-for-macos
- Dot blog on menu bar time zones (scrubbing, daylight shading): https://trydot.app/blog/time-zones-mac-menu-bar
- GeoNames export and license (CC BY 4.0): https://www.geonames.org/export/ and https://download.geonames.org/export/dump/readme.txt
- Natural Earth terms of use (public domain): https://www.naturalearthdata.com/about/terms-of-use/
- Menu bar world clock roundups (market context): https://dev.to/appish/mac-menu-bar-world-clock-best-timezone-tracking-apps-for-2025-3b0

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.

### Round 1 (2026-11-03)

Tester summary: no blockers or majors. Every time checked matched `date`, including half-hour
offsets and daylight saving.

| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
| F1 Choosing a search result marked "already added" adds a duplicate | minor | accept | Adding a place that's already listed now selects and highlights the existing row (`ZonesModel.existingID(for:)` / `highlight`). The ✓ tooltip says so. |
| F2 "Icon and time" / "Time only" items get hidden by macOS on a crowded notched menu bar | minor | accept (mitigate) | Can't be prevented. `AppController.refreshStatusItemVisibility()` checks the item's window (off screen, occluded, overlapping the notch) after layout, on occlusion changes and when Settings opens. When hidden, General shows "macOS is hiding the menu bar item because the menu bar is full. Icon only takes the least space." and points to the keyboard shortcut. Not triggerable on the external-display layout during this round (the item fit), so only the visible case was walked through. |
| F3 ⌘W / Esc often don't close Settings | minor | accept | Opening Settings or About from the panel no longer hands focus back to the previous app when the panel closes (a race that left Settings unfocused). SettingsOpener activates (`activate(ignoringOtherApps:)`) and makes the window key. Esc now closes Settings and About unless a text field or the shortcut recorder is editing. Verified: Esc and ⌘W both close Settings. |
| F4 Panel sometimes closed during keyboard use | minor | accept | `popoverShouldClose` only allows a close for our own close (Esc, ⌘W, icon), a mouse click outside, or the app losing focus. The "Copied" HUD and menus no longer count. During testing, the remaining closes were other agents' apps taking focus (Crate became frontmost). |
| F5 Rows and the "Shown time" header have role AXUnknown | minor | accept | Rows are AX buttons (press = type a time) with named actions: Type a Time, Copy Time, Show in Menu Bar, Rename, Move Up/Down, Remove. The header is an incrementor (±15 min) whose value reads naturally: "2 days 1 hour later, Tuesday, March 17, 12:00 PM". |
| F6 Undo doesn't reverse Sort by Time Difference | nit | accept | Undo now covers sort too (`ZonesModel.UndoAction`). Menu reads "Undo Sort" / "Undo Remove London". Test added. |
| F7 Copied zone labels inconsistent ("UTC+9" vs "EST") | nit | accept | Small built-in table of well-known abbreviations (GMT/BST, IST Ireland/India, WET, CET/CEST and EET/EEST capitals, MSK, JST, KST, HKT, SGT, AEST/AEDT, ACST/ACDT, AWST, NZST/NZDT, SAST…), picked by DST state. Ambiguous ones (China CST, Israel IST) fall back to UTC±h. Tests added. |
| F8a Two "Add Place…" buttons in the empty state | nit | accept | First-run hint is text only and points to the footer button; "No places to show" explains instead of repeating the button. |
| F8b First search result not visibly highlighted / ↓ didn't go to the second | nit | accept | A pointer already resting over the list no longer moves the highlight when results change (hover ignored for 0.3 s after each update). Verified: first result highlighted, ↓ moves to the second. |
| F8c Header offset "+1 d 1 h 27 min" | nit | accept | Over a day the header reads "+1 day 2 h", "+10 days" (minutes dropped; the date line and rows give the exact time). Under a day unchanged ("+3 h 15 min"). |
| Missing: Remove and Move Up/Down in the ⋯ menu | — | accept | Added "Remove <place>" (⌫), "Move Up" / "Move Down" (⌥⌘↑ / ⌥⌘↓), enabled for the selected place. |
| Missing: working-hours shading | — | defer | Stays `later` (#18). It needs per-place hours, which means new settings UI. |

Gates after fixes: 74 tests pass. `scripts/check.sh Zones --perf` all green (launch
164 ms, first status item 363 ms, idle CPU 0.008 %, footprint 22.7 MB, on a busy machine
with load 13). No `[unlabeled]` in the panel, search or Settings. Shipped as beta 0.2.0
(build 2). README updated.
