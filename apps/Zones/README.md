# Zones

World clocks and meeting times, in the menu bar.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to World Clock Pro.

**Status:** beta (0.2.1)

## What it does

Click the globe in the menu bar to see what time it is everywhere you care about. Your local
time sits in a card at the top with the date and whether you're in working hours; below it,
each place shows its offset ("Tomorrow · +7 h") and a large time, in your accent colour while
people there are working and dimmed at night, so you can tell at a glance who you can reach.

- **Plan a meeting.** Drag sideways on the list (the line down the middle follows you), or
  two-finger swipe, or **← →** for 15 minutes, **⇧← ⇧→** for an hour, **⌥← ⌥→** for a day, and
  every clock moves together. The chip on the line shows how far from now you are; click its
  ✕ or press **Esc** to go back. Closing the panel always resets.
- **Go to a date.** Click the date under your city (or **⌘D**) for a calendar; the time of day
  stays the same.
- **Working hours.** 9–5, Monday to Friday by default; set your own in Settings → Places, and
  give any place its own hours and workdays (a Sunday–Thursday office, a night shift).
- **Row styles** (Settings → General, or ⚙ → Row Style): Standard, Compact (one line per
  place, for long lists) and Timeline, which adds a strip of each place's day (working
  hours, evening, night, and where its date changes) under every row.
- **Planner** (**Open Planner**, **⌘0**): a window with every place as a clock card (analog
  or digital) and a grid of one whole day, hour by hour, shaded by working hours, with the
  hours when everyone is working marked and listed. Click an hour (or **← →**, **⌥← ⌥→** for
  days) to read it everywhere; **⌘C** copies it.
- **Add to Calendar…** (⚙ menu, or the planner) makes an hour-long event at the shown time,
  with the time in every place in its notes, and opens it in your calendar app, which asks
  where to add it. Zones never reads your calendars and needs no calendar access.
- **Share** (the share button) sends the shown time in every place to Messages, Mail, Notes…
- **Type a time.** Click a place's time (or select a row and press **Return**, or just start
  typing a digit) and type `3pm`, `9:30 am`, `15:30` or `noon`. Every row jumps to that moment.
  If the time doesn't exist that day (clocks going forward) or happens twice (going back),
  Zones says so.
- **Copy Times** (**⌘C**) copies the shown moment in every place as plain text with absolute
  dates, ready for an invite: `London: Wed, Nov 4, 3:15 AM GMT`. Well-known abbreviations
  (EST, GMT/BST, CET/CEST, JST, IST, AEST/AEDT…) are used where they're unambiguous;
  otherwise the UTC offset (`UTC+8`). Settings has a single-line
  and an ISO 8601 format; right-click a row to copy just that one.
- **Add Place…** (**⌘N**) searches 34,000 cities offline (accents and case don't matter:
  `zurich`, `sao paulo`, `東京`, `nyc`), countries, time zone names (`Europe/Paris`),
  abbreviations (`PST`, `IST` lists every zone it can mean) and fixed offsets (`UTC+5:30`).
  `paris, texas` narrows by country or region.
- **Daylight saving is always right.** Offsets are computed for the moment you're looking at,
  from macOS's own time zone database, so the weeks when the US and Europe change on
  different dates, southern-hemisphere zones, half-hour and 45-minute offsets and the date
  line all come out right. A row warns "Clocks go back 1 h on Sun" during the week before a
  change.
- **Menu bar clocks.** Right-click any place → Show in Menu Bar (or the menu bar buttons in
  Settings → Places) to put its time in the menu bar, as many as you like
  ("LON 5:20 PM   TOK 2:20 AM"). Settings → General → Menu bar shows: icon only (default),
  icon and times, or times only. On a full menu bar (notched MacBooks) macOS may hide the
  item; Settings says so when it happens, and a keyboard shortcut (Settings → Shortcuts)
  opens Zones anyway.
- Rename (right-click → Rename…), reorder (drag a row up or down, ⌥⌘↑/↓, or Settings →
  Places), remove (right-click → Remove, or **⌫**), Sort by Time Difference and Sort by Name, all with Undo
  (**⌘Z**). Choosing a place that's already listed shows its row instead of adding it twice.

Every action is also in the **⚙** menu at the bottom right, with its shortcut.

No permissions, no network access, no accounts, no tracking. Local time is the Mac's time
zone (no Location access) and follows it when you travel.

## Keyboard

| Key | Action |
|---|---|
| ← → / ⇧← ⇧→ / ⌥← ⌥→ | 15 minutes / 1 hour / 1 day earlier or later |
| ↑ ↓ | Select a row |
| Return, or a digit | Type a time on the selected row |
| ⌫ | Remove the selected place (⌘Z undoes) |
| ⌥⌘↑ ⌥⌘↓ | Move the selected place |
| ⌘C | Copy Times |
| ⌘N | Add Place… |
| ⌘D | Go to a date |
| ⌘0 | Open Planner |
| Esc | Close the calendar, back to now, then close |
| ⌘, / ⌘Q | Settings / Quit |
| Esc / ⌘W in Settings or About | Close the window |
| (your choice) | Settings → Shortcuts → Open Zones, from any app. Unset by default. Also opens the panel when the menu bar icon is hidden or squeezed behind the notch. |

## Not there yet

Airport codes, widgets, Shortcuts actions, a separate menu bar item per clock. No map and no
weather, on purpose.

## City data

City names come from [GeoNames](https://www.geonames.org) (`cities15000`), licensed under
[Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/). See
[THIRD_PARTY.md](THIRD_PARTY.md). Time zone rules come from macOS, never from the bundled
file. To refresh the list: `python3 -I apps/Zones/Tools/build-cities.py` (downloads from
GeoNames and rewrites `Sources/ZonesCore/Resources/cities.tsv.deflate`).

## Develop

```sh
scripts/test.sh Zones          # unit tests (DST weeks, offsets, date line, parsing, search)
scripts/run.sh Zones           # build a debug .app and open it
scripts/check.sh Zones --perf  # tests, release bundle, smoke test, perf budgets
```

Logic lives in `Sources/ZonesCore` (tested); views and wiring in `Sources/Zones`.

| Variable | Effect |
|---|---|
| `ZONES_DEFAULTS_SUITE=<name>` | Keep places and settings in this UserDefaults suite (tests) |
| `ZONES_RESET=1` | Start from the first-run state (local time + UTC) |
| `ZONES_NOW=2026-03-15T15:00:00Z` | Pin "now" (the clock doesn't move) |
| `ZONES_TIMEZONE=America/New_York` | Pretend the Mac is in this time zone |
| `ZONES_APPEARANCE=light\|dark` | Force an appearance (screenshots) |
| `ZONES_EXPORT_DIR=/tmp/x` | Add to Calendar writes `Meeting.ics` there instead of opening it |
| `ZONES_SNAPSHOT_DIR=/tmp/x` | Render the panel, planner and Settings (light and dark) to PNGs offscreen, then quit |

Quit any running Zones first: while a copy with the same bundle id is running, `drive launch`
attaches to it and ignores `--env`.

```sh
scripts/drive launch build/Zones.app --env ZONES_DEFAULTS_SUITE=zones-test --env ZONES_RESET=1 \
  --env ZONES_NOW=2026-03-15T15:00:00Z --env ZONES_TIMEZONE=America/New_York
scripts/drive menubar Zones
```
