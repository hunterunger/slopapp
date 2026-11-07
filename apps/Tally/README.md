# Tally

A notepad that does the math as you type.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to Numi.

**Status:** alpha (0.1.0)

## What it does

Type one calculation per line. The answer appears on the right of the same line as you
type, with no `=` or Return needed, and a slim bar along the bottom keeps a running total
(of the selected lines, if you select some). Click an answer (or press ⇧⌘C) to copy it.
Keep as many sheets as you like in the sidebar; they save themselves, so they're still
there tomorrow. Optionally, Tally also lives in the menu bar.

```
# Rent
rent = 1450                      1,450
rent / 3 + 12%                   541.3333333
dinner = $186.40                 $186.40
dinner + 18%                     $219.95
5 km in miles                    3.106855961 mi
1 GiB in MiB                     1,024 MiB
```

- **Math**: `+ - * / ^ mod`, parentheses, `plus`, `minus`, `and`, `with`, `without`, `times`,
  `divided by`, `2(3 + 1)`, `5!`, scales (`3k`, `2.5M`, `1.2 billion`), `1,250`, `1.5e3`,
  `0xff`, `0b1010`. Bitwise `& | xor << >>`. Exact decimal arithmetic: `0.1 + 0.2` is `0.3`.
- **Percentages**: `150 + 20%`, `20% of 150`, `5% on 200`, `6% off 50`, `30 as % of 120`,
  and the reverse forms: `5% of what is 6`, `5% off what is 47.50`, `$70 as a % on $20`.
- **Variables and earlier lines**: `price = 40` (names match in any case), `prev` (the line above), `sum`/`total` and
  `avg`/`average` (lines above, back to a blank line or header). Every edit re-evaluates the
  whole sheet, so a renamed or moved variable never leaves a stale answer behind.
- **Notes**: `# headers`, `// comments`, `Label: 1200 + 85`, `"quoted text"`. A line with
  words Tally doesn't know shows nothing rather than a guess.
- **Units**: length, mass, data (decimal and binary), time, temperature, area, volume and
  angles. Convert with `in`, `to`, `as` or `into`: `6 ft to cm`, `100 Mb in MB`,
  `1 h 30 min in min`, `20 °C in °F`, `2 m * 3 m`. Mixed units add up in the left unit.
- **Speeds and other rates**: `60 km/h in m/s`, `30 mph`, `100 km / 2 h`, `$25 per hour * 38 h`,
  `$4/kg * 750 g`, `1 GB / 100 Mbps`.
- **Times, dates and time zones**: `now in Tokyo`, `time in Madrid`, `PST time`,
  `3pm PST in CET`, `9am + 3 hours`, `5:30pm - 9am`, `today + 3 weeks`, `Dec 25 - today`,
  `2026-12-25`, `fromunix(1446587186)`. Cities, countries and zone abbreviations work offline
  (abbreviations follow their region's daylight saving time). Answers that use the clock
  update every minute.
- **Screen units**: `12 pt in px`, `2 em in px`, `1 cm in px`. 1 em = 16 px and 96 ppi unless
  Settings or a line like `em = 20px` / `ppi = 326` says otherwise.
- **Functions**: `sqrt` (or `square root of`), `cbrt`, `root 3 (8)`, `abs`, `round(x, digits)`,
  `ceil`, `floor`, `ln`, `log`, `log 2 (8)`, `exp`, `sin`/`cos`/`tan` (radians, or degrees with
  `°`), `asin`/`acos`/`atan` (also `arcsin`...), `sinh`/`cosh`/`tanh`; `pi`, `e`.
- **Formats**: `255 in hex`, `10 in binary`, `8 in oct`, `1500 in sci`.
- **Money**: `$20 + $5`, `€12.50 * 4`. Same-currency math always works offline. Converting
  between currencies needs rates: turn on downloads in Settings, or write your own rate on a
  line (`1 USD = 1.37 CAD`), which applies to the lines below it.

Help ▸ Tally Syntax Guide lists everything with live examples.

**Look and feel.** Lines are coloured as you type (numbers, operator words, units, variables,
labels, comments). Pick a theme from the palette button in the bottom bar, View ▸ Theme or
Settings ▸ Appearance: System (follows your Mac and accent colour), Paper, Midnight, Dusk or
Graphite. While you type a name Tally knows, the rest of it shows in grey; press Tab to take
it, or Esc for a list of everything that fits.

## Network and privacy

Tally makes **no network requests by default**. If you turn on **Settings ▸ Currency ▸
Download exchange rates**, it fetches the European Central Bank's daily reference rates
(`eurofxref-daily.xml`, about 30 currencies) at most once a day while it's running. That's a
single anonymous GET with no cookies; nothing about you or your sheet is sent. Rates are saved
as `rates.json` and keep working offline; results based on rates older than a week show a
clock with the rates' date. **Delete Rates** removes the file.

Data lives in `~/Library/Application Support/app.slopapp.tally/`: `sheets.json` (the list),
`sheets/<id>.txt` (each sheet, plain UTF-8 text) and `rates.json`. A `sheet.txt` from Tally
0.1 is copied in as the first sheet and left where it was.

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| New Sheet | ⌘N |
| Next / Previous Sheet | ⇧⌘] / ⇧⌘[ |
| Show / Hide Sidebar | ⌃⌘S |
| Copy Result (line with the cursor) | ⇧⌘C |
| Copy Total (or the selection's total) | ⇧⌘T |
| Copy All (each line with its answer) | ⌥⌘C |
| Clear All (undoable) | ⌥⌘⌫ |
| Undo / Redo | ⌘Z / ⇧⌘Z |
| Find / Find and Replace | ⌘F / ⌥⌘F |
| Import… (as a new sheet) / Export… (plain text) | ⌘O / ⇧⌘S |
| Accept the grey suggestion / list completions | Tab / Esc |
| Bigger / Smaller / Actual Size | ⌘+ / ⌘- / ⌘0 |
| Syntax Guide | Help menu |
| Settings | ⌘, |
| Float on Top | Window menu |
| Show or hide Tally from any app | set your own in Settings ▸ Shortcuts (unset by default) |

Closing the window quits Tally, unless a show/hide shortcut is set or Tally is in the menu
bar: then it stays ready in the background.

## Settings

- **General**: Launch at login; show Tally in the menu bar (click the icon for the current
  sheet in a panel; right-click for a menu) and, while it's there, hide the Dock icon;
  copied results include the unit (`1.2 m`) or not (`1.2`); suggest names as you type;
  screen units (1 em in px, pixel density).
- **Appearance**: theme.
- **Currency**: Download exchange rates (off), Update Now, Delete Rates, what `$` means.
- **Shortcuts**: show/hide Tally.

## Not there yet

No decimal-comma input (`1,5`), no iCloud sync, no plugins, no command-line tool or
launcher (Alfred/Raycast) integration yet, no crypto rates. Variables can't reuse the names
of units or built-in words (`m`, `total`, `now`); Tally says so.

## Develop

```sh
scripts/test.sh Tally          # unit tests: the corpus, grammar, dates, units, sheets, rates, perf
scripts/run.sh Tally           # build a debug .app and open it
scripts/check.sh Tally --perf  # tests, release bundle, smoke test, perf budgets
```

The parser and evaluator are a pure Swift library (`Sources/TallyCore`): lexer → Pratt
parser → evaluator over `Decimal`, with a per-line parse cache. A keystroke in a 1,000-line
sheet takes about 3 ms end to end (re-evaluate, total, colour, re-wrap, draw).

Test hooks (environment variables):

| Variable | Effect |
|---|---|
| `TALLY_DATA_DIR=/tmp/tally-test/data` | Keep the sheets and rates there; open/save panels start in its parent |
| `TALLY_DEFAULTS_SUITE=app.slopapp.tally.test` | Keep settings in that defaults suite, not Tally's own |
| `TALLY_CLIPBOARD_FILE=/tmp/tally-test/clip.txt` | Copies go to this file, not the clipboard |
| `TALLY_RATES_URL=file:///tmp/tally-test/rates.xml` | Fetch rates from a fixture instead of the ECB |
| `TALLY_APPEARANCE=light\|dark` | Force an appearance (screenshots) |
| `TALLY_PERF_LOG=1` | Append per-keystroke timings to `perf.log` in the data folder |
| `TALLY_SNAPSHOT_DIR=/tmp/x` | Render the window (every theme, sidebar), menu bar panel and Settings offscreen to PNGs, then quit (needs the two above) |
| `TALLY_PERF_SIM=1` | Type into a 1,000-line sheet in an offscreen window and print keystroke timings, then quit (needs the two above) |
