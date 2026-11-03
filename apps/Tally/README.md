# Tally

A notepad that does the math as you type.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to Numi.

**Status:** alpha (0.1.0)

## What it does

Type one calculation per line. The answer appears on the right of the same line as you
type, with no `=` or Return needed. Click an answer (or press ⇧⌘C) to copy it. The sheet saves
itself, so it's still there tomorrow.

```
# Rent
rent = 1450                      1,450
rent / 3 + 12%                   541.3333333
dinner = $186.40                 $186.40
dinner + 18%                     $219.95
5 km in miles                    3.106855961 mi
1 GiB in MiB                     1,024 MiB
```

- **Math**: `+ - * / ^ mod`, parentheses, `plus`, `minus`, `times`, `divided by`, `2(3 + 1)`,
  `5!`, scales (`3k`, `2.5M`, `1.2 billion`), `1,250`, `1.5e3`, `0xff`, `0b1010`.
  Exact decimal arithmetic: `0.1 + 0.2` is `0.3`.
- **Percentages**: `150 + 20%`, `20% of 150`, `5% on 200`, `6% off 50`, `30 as % of 120`.
- **Variables and earlier lines**: `price = 40`, `prev` (the line above), `sum`/`total` and
  `avg`/`average` (lines above, back to a blank line or header). Every edit re-evaluates the
  whole sheet, so a renamed or moved variable never leaves a stale answer behind.
- **Notes**: `# headers`, `// comments`, `Label: 1200 + 85`, `"quoted text"`. A line with
  words Tally doesn't know shows nothing rather than a guess.
- **Units**: length, mass, data (decimal and binary), time, temperature, area, volume and
  angles. Convert with `in`, `to`, `as` or `into`: `6 ft to cm`, `100 Mb in MB`,
  `1 h 30 min in min`, `20 °C in °F`, `2 m * 3 m`. Mixed units add up in the left unit.
- **Functions**: `sqrt`, `cbrt`, `abs`, `round(x, digits)`, `ceil`, `floor`, `ln`, `log`,
  `exp`, `sin`/`cos`/`tan` (radians, or degrees with `°`), `asin`/`acos`/`atan`; `pi`, `e`.
- **Formats**: `255 in hex`, `10 in binary`, `8 in oct`, `1500 in sci`.
- **Money**: `$20 + $5`, `€12.50 * 4`. Same-currency math always works offline. Converting
  between currencies needs rates: turn on downloads in Settings, or write your own rate on a
  line (`1 USD = 1.37 CAD`), which applies to the lines below it.

Help ▸ Tally Syntax Guide lists everything with live examples.

## Network and privacy

Tally makes **no network requests by default**. If you turn on **Settings ▸ Currency ▸
Download exchange rates**, it fetches the European Central Bank's daily reference rates
(`eurofxref-daily.xml`, about 30 currencies) at most once a day while it's running. That's a
single anonymous GET with no cookies; nothing about you or your sheet is sent. Rates are saved
as `rates.json` and keep working offline; results based on rates older than a week show a
clock with the rates' date. **Delete Rates** removes the file.

Data lives in `~/Library/Application Support/app.slopapp.tally/` (`sheet.txt`, `rates.json`).

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| Copy Result (line with the cursor) | ⇧⌘C |
| Copy All (each line with its answer) | ⌥⌘C |
| Clear All (undoable) | ⌥⌘⌫ |
| Undo / Redo | ⌘Z / ⇧⌘Z |
| Find / Find and Replace | ⌘F / ⌥⌘F |
| Import… / Export… (plain text) | ⌘O / ⇧⌘S |
| Bigger / Smaller / Actual Size | ⌘+ / ⌘- / ⌘0 |
| Syntax Guide | Help menu |
| Settings | ⌘, |
| Show or hide Tally from any app | set your own in Settings ▸ Shortcuts (unset by default) |

Closing the window quits Tally, unless a show/hide shortcut is set: then it stays ready in
the background.

## Settings

- **General**: Launch at login; copied results include the unit (`1.2 m`) or not (`1.2`).
- **Currency**: Download exchange rates (off), Update Now, Delete Rates, what `$` means.
- **Shortcuts**: show/hide Tally.

## Not there yet

One sheet only (multiple sheets later), no time zones or dates, no compound units (`km/h`),
no decimal-comma input (`1,5`), no bitwise operators, no menu bar mode, no iCloud sync.
Variables can't reuse the names of units or built-in words (`m`, `total`); Tally says so.

## Develop

```sh
scripts/test.sh Tally          # unit tests: the 68-line corpus, grammar, sheets, rates, perf
scripts/run.sh Tally           # build a debug .app and open it
scripts/check.sh Tally --perf  # tests, release bundle, smoke test, perf budgets
```

The parser and evaluator are a pure Swift library (`Sources/TallyCore`): lexer → Pratt
parser → evaluator over `Decimal`, with a per-line parse cache. A keystroke in a 1,000-line
sheet takes about 2 ms to re-evaluate.

Test hooks (environment variables):

| Variable | Effect |
|---|---|
| `TALLY_DATA_DIR=/tmp/tally-test/data` | Keep the sheet and rates there; open/save panels start in its parent |
| `TALLY_CLIPBOARD_FILE=/tmp/tally-test/clip.txt` | Copies go to this file, not the clipboard |
| `TALLY_RATES_URL=file:///tmp/tally-test/rates.xml` | Fetch rates from a fixture instead of the ECB |
| `TALLY_APPEARANCE=light\|dark` | Force an appearance (screenshots) |
| `TALLY_PERF_LOG=1` | Append per-keystroke timings to `perf.log` in the data folder |
