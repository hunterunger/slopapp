# Tally research (inspired by Numi)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md) on 2026-11-03.
> Studied: **Numi 3.34** (Setapp listing) through its download page, its public GitHub wiki
> (full syntax reference, shortcuts, extension API), the Setapp listing and ~20 Setapp
> reviews. Numi is **not installed** on this Mac, so nothing was explored live. Soulver and
> Calca (same genre) and the open-source Parsify/Numbat projects informed the grammar notes.
> We study how it works so we don't reinvent the wheel. We never copy its name, icons,
> artwork, wording, sounds or signature visuals.

## The job

A calculator that keeps its work. People reach for it when a calculation has more than one
step or needs to be revisited: splitting a bill, a budget, pricing with tax and discount,
"how many GB is 3 hours of this bitrate", converting a recipe or a room's dimensions. A
normal calculator loses the trail; a spreadsheet is too heavy. Done feels like: type a line
in plain words, the answer appears on the right as you type, and tomorrow the sheet is
still there.

**The one interaction that matters: type `rent = 1450` / `rent / 3 + 12%` and see each line's
result appear, right-aligned, while typing, with no Return or "=" needed; click a result to
copy it.**

## Who and when

- Splitting a shared bill or rent with tips/tax, kept for next month.
- A developer converting data sizes and durations (`750 MB in GiB`, `90 min in h`).
- A real-estate agent or DIYer converting lengths and areas (a Setapp reviewer).
- Quick currency estimates while shopping abroad (opt-in rates).
- Frequency: a few times a day for heavy users; each use 10 s – 5 min. Window stays open
  or is summoned by a global shortcut.

## Feature inventory

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Per-line evaluation with right-aligned results | Live, as you type | must | Results column right-aligned, `.monospacedDigit()`, secondary color. |
| 2 | Arithmetic, precedence, parentheses | `+ - * / ^ mod`, plus word forms (plus, minus, times, divided by) | must | See grammar. Decimal arithmetic so `0.1 + 0.2 = 0.3`. |
| 3 | Bitwise ops `& | xor << >>` | Supported | later | Developer niche. |
| 4 | Implicit multiplication `6 (3)` | Supported | should | `2(3 + 1)`. |
| 5 | Number bases `0x 0b 0o`, `in hex/bin/oct` | Supported | should (input) / should (output) | |
| 6 | Scientific notation `in sci` | Supported | later | Input `1.5e3` is must. |
| 7 | Scales `k`, `M`, thousand, million, billion | Case-sensitive single letters | must | `m` = metre, `K` = kelvin; `k` and `M` are scales only when glued to a number. |
| 8 | Percentages: `x + 20%`, `20% of x`, `on`, `off`, `as % of` | Full set incl. reverse forms (`5% of what is 6`) | must (basic five) / later (reverse forms) | |
| 9 | Variables `name = expr` | Supported; reviews: variables break silently after moving lines | must | Re-evaluate the whole sheet top-down every edit; never show a stale value. |
| 10 | `prev`, `sum`/`total`, `avg`/`average` | prev = line above; sum/avg = lines above up to a blank line | must | |
| 11 | Comments `//`, headers `#`, labels `Label:`, quoted text ignored | All four | must | Styling: headers bold, comments tertiary. |
| 12 | Units: length, mass, data, time | Large unit set, SI prefixes, case-sensitive | must | Unit table below. |
| 13 | Temperature, area, volume, angle | Supported | should (temperature, area, volume) / must (angle via `°` for trig) | |
| 14 | CSS units px/pt/em with `ppi`/`em` variables | Supported | later | |
| 15 | Currency (ISO codes, symbols, names) | Online rates several times a day; crypto hourly | should, **opt-in** | Offline: same-currency math always works; conversion needs rates. See Currency. |
| 16 | Time zones, `now`, `time in Madrid` | Supported; reviews say unreliable | later | Needs a city database. |
| 17 | Dates, `fromunix()` | Date units, unix conversion | later | Date-difference is a review request; v1.1 candidate. |
| 18 | Functions (sqrt, cbrt, root, abs, log, ln, fact, round, ceil, floor, trig, hyperbolic) | Supported, radians default | must (sqrt, abs, round, ceil, floor, ln, log, sin/cos/tan) / later (rest) | |
| 19 | Constants `pi`, `e` | Supported | must | |
| 20 | Copy result of current line | ⇧⌘C | must | Also click a result. |
| 21 | Copy all / Clear all | ⌥⌘C / ⌥⌘⌫ | should | Clear all is undoable (⌘Z). |
| 22 | Wrap selection in parentheses | ⇧⌘0 | later | |
| 23 | Import / export plain text | ⌘O / ⌘S, UTF-8 `.numi` | should | Plain `.txt`; our own sheet is autosaved anyway. |
| 24 | Print | ⌘P | later | |
| 25 | Multiple sheets, iCloud sync | Multiple calculations, optional iCloud | later (multiple sheets) / skip (sync) | v1: one autosaved sheet. |
| 26 | Global hotkey to show the window | Reviews ask that it also *hides* | should | Toggle show/hide. Unset by default. |
| 27 | Menu bar mode | Available | later | |
| 28 | JS extensions (custom units/functions) | `numi.addUnit`, `numi.addFunction` | skip | Code execution surface; out of scope. |
| 29 | CLI + Alfred workflow | Separate CLI | later | Core is a pure library, so a CLI is cheap later. |
| 30 | Themes | Several | skip | System appearance + accent only. |
| 31 | Newsletter pop-up | Shown in app (review complaint) | skip | Never. |

## Key flows

### Flow 1: calculate
1. Open Tally (or the global shortcut). The single sheet window appears with the cursor at
   the end of the last line.
2. Type `dinner = 186.40`. Result `186.4` appears on the right of the same line.
3. Next line `dinner + 18%` → `219.952`. Next `prev / 4` → `54.988`.
4. Click a result (or ⇧⌘C on the current line): copies the plain number, a small `HUD`
   says "Copied".
5. Close the window. Everything is autosaved; reopening shows the same sheet.

### Flow 2: first run
1. Window opens with a short example block (a header, three lines of math, a unit
   conversion, a comment saying "Delete these lines whenever you like"). No tour.
2. Currency lines like `100 USD in EUR` show a dimmed `rates off` hint in the result column;
   clicking it opens Settings ▸ Currency.

### Flow 3: turn on currency (opt-in)
1. Settings ▸ Currency: toggle "Download exchange rates" (off). Below it, one line: "Tally
   fetches daily reference rates from the European Central Bank, at most once a day. No
   other data is sent."
2. On: one GET of the ECB daily XML (29 currencies + EUR). Stored as
   `rates.json` (`{ "date": …, "base": "EUR", "rates": {…} }`) in Application Support.
3. Settings shows "Rates from 3 Nov 2026" and **Update Now**. Results using rates older than
   7 days show a small clock symbol with the date on hover.
4. Off again: rates file stays (still used, marked with its date) unless **Delete Rates**.
5. Fully offline alternative: a line like `1 USD = 1.37 CAD` defines a rate for the rest of
   the sheet (overrides the file). Works with downloading off.

## Grammar scope for v1

The parser is a pure Swift library (`TallyCore`): `Lexer → Parser (Pratt) → AST →
Evaluator(context)`. A sheet is evaluated top to bottom on every edit (debounced to the next
runloop turn; sheets are small); each line gets `Result = .value(Quantity) | .none |
.error(reason)`. `.none` shows nothing; `.error` shows nothing in the column but a reason in
the line's tooltip/VoiceOver. A line never shows a value it can't fully justify (unknown
words make the line `.none`, not a partial answer).

**Lines**
- Empty line: separator (resets `sum`/`avg` blocks).
- `// …`: comment. `# …`: header. Both `.none`.
- `Label: expr`: text up to the first colon is ignored if the remainder parses.
- `"…"`: quoted text anywhere is ignored.
- `name = expr`: assignment; result shows the value. Names: letter or `_` first, then
  letters/digits/`_`; can't shadow units, keywords, functions, constants.

**Values**: `Quantity { value: Decimal, unit: Unit? }`, where `Unit` is a single unit with
dimension (length, mass, data, time, temperature, area, volume, angle, currency, percent) or
none. No compound units (`km/h`) in v1.

**Numbers**: `12`, `12.5`, `.5`, `1,250` (comma only as 3-digit grouping), `1.5e3`,
`0xFF`, `0b1010`, `0o17`; scales `k`, `M`, `thousand`, `million`, `billion` (`3k`, `2.5M`,
`1.2 billion`). Decimal comma locales: later.

**Operators** (low → high): conversion `in | to | as | into` → `+ -` (and `plus`,
`minus`) → `* / mod` (and `times`, `x` between numbers, `×`, `÷`, `divided by`,
`multiplied by`) → implicit multiplication → unary `-` → `^` (right-assoc) → postfix `%`,
`!`. So `-2^2 = -4`, `2^3^2 = 512`.

**Percent rules**
- `a + p%` = a × (1 + p), `a - p%` = a × (1 − p), `a * p%` = a × p.
- `p% of a` = a × p; `p% on a` = a × (1 + p); `p% off a` = a × (1 − p).
- `a as % of b` = a / b as a percent.
- `p% + q%` = percent.

**Units** (each with singular, plural and symbol; case-sensitive symbols):
- Length: mm, cm, m, km, inch/inches (not `in`), ft/foot/feet, yd, mi/mile, nmi.
- Mass: mg, g, kg, t/tonne, oz, lb, st/stone.
- Data (decimal and binary): b/bit, B/byte, kB, MB, GB, TB, PB, KiB, MiB, GiB, TiB,
  kb, Mb, Gb (bits). `b` = bit, `B` = byte.
- Time: ms, s/sec/second, min/minute, h/hr/hour, day, week, month (= 1/12 year), year
  (= 365 days).
- Temperature (should): °C/C/celsius, °F/F/fahrenheit, K/kelvin. Offset conversion;
  arithmetic on temperatures uses the left unit.
- Area/volume (should): `sq`/`square` and `cu`/`cubic` + length unit, ha, acre, L, mL,
  cup, tsp, tbsp, gallon (US).
- Angle: `°`/deg, rad. Trig takes radians unless the argument has a degree unit.

**Unit arithmetic**: `+`/`-` between same dimension converts to the **left** unit
(`1 m + 20 cm = 1.2 m`); a unitless operand adopts the other's unit (`5 km + 2 = 7 km`);
`*`/`/` by a scalar keeps the unit; same-dimension `/` gives a plain number; different
dimensions on `+ - /`, or unit × unit, are `.error(incompatible units)`. Mixed adjacency
`1 m 20 cm` / `1 h 30 min` sums (should).

**Line references**: `prev` (result of nearest non-empty line above with a value), `sum` /
`total` and `avg` / `average` (all values above, up to the previous blank line or sheet
start; units must be compatible, else error).

**Functions**: `sqrt`, `cbrt`, `abs`, `round`, `ceil`, `floor`, `ln`, `log` (base 10),
`sin`, `cos`, `tan`, with or without parentheses for a single argument (`sqrt 16`).
`round` is half away from zero. Constants `pi`, `e`.

**Currency** (opt-in rates): ISO codes (any case: `usd`), symbols `$`(USD) `€` `£` `¥`(JPY)
`₹`, and names `dollar(s)`, `euro(s)`, `pound(s)`. Same-currency math never needs rates.

**Display**: at most 10 significant digits, trailing zeros trimmed, locale grouping on the
integer part; currency rounds to the currency's minor units (2 for most, 0 for JPY/KRW/ISK);
percent results end in `%`; units use the symbol (`1.2 m`, `1,250 g`). Copy puts the
displayed text on the clipboard (should: a setting for "number only").

## Test corpus (v1)

Evaluated as one sheet, top to bottom, blank lines included. `—` = `.none` (nothing shown),
`err(…)` = `.error`. Tests use a fixture rates file `{base EUR, USD 1.0850, GBP 0.8430}`
for lines 50–51; with no rates file those lines are `err(rates off)`.

| # | Input | Expected |
|---|---|---|
| 1 | `2 + 3` | 5 |
| 2 | `2 + 3 * 4` | 14 |
| 3 | `(2 + 3) * 4` | 20 |
| 4 | `2 ^ 10` | 1,024 |
| 5 | `-2 ^ 2` | -4 |
| 6 | `2 ^ 3 ^ 2` | 512 |
| 7 | `10 / 4` | 2.5 |
| 8 | `1 / 3` | 0.3333333333 |
| 9 | `0.1 + 0.2` | 0.3 |
| 10 | `7 mod 3` | 1 |
| 11 | `8 times 9` | 72 |
| 12 | `100 divided by 8` | 12.5 |
| 13 | `1,250 + 750` | 2,000 |
| 14 | `1.5e3` | 1,500 |
| 15 | `0xff + 1` | 256 *(should)* |
| 16 | `3k + 2.5M` | 2,503,000 |
| 17 | `1.2 billion / 1000` | 1,200,000 |
| 18 | `2(3 + 1)` | 8 *(should)* |
| 19 | *(blank)* | — |
| 20 | `20% of 150` | 30 |
| 21 | `150 + 20%` | 180 |
| 22 | `150 - 20%` | 120 |
| 23 | `5% on 200` | 210 |
| 24 | `6% off 50` | 47 |
| 25 | `30 as % of 120` | 25% |
| 26 | `12.5% of 80` | 10 |
| 27 | *(blank)* | — |
| 28 | `price = 40` | 40 |
| 29 | `qty = 3` | 3 |
| 30 | `price * qty` | 120 |
| 31 | `prev + 10%` | 132 |
| 32 | `Rent: 1200 + 85` | 1,285 |
| 33 | `// a comment` | — |
| 34 | `# Groceries` | — |
| 35 | `hello world` | — |
| 36 | *(blank)* | — |
| 37 | `10` | 10 |
| 38 | `20` | 20 |
| 39 | `30` | 30 |
| 40 | `sum` | 60 |
| 41 | *(blank)* | — |
| 42 | `1 m + 20 cm` | 1.2 m |
| 43 | `5 km in miles` | 3.106855961 mi |
| 44 | `6 ft to cm` | 182.88 cm |
| 45 | `3 lb in kg` | 1.36077711 kg |
| 46 | `250 g + 1 kg` | 1,250 g |
| 47 | `1 GB in MB` | 1,000 MB |
| 48 | `1 GiB in MiB` | 1,024 MiB |
| 49 | `100 Mb in MB` | 12.5 MB |
| 50 | `100 USD in EUR` | €92.17 (fixture) |
| 51 | `50 EUR in GBP` | £42.15 (fixture) |
| 52 | `$20 + $5` | $25.00 (no rates needed) |
| 53 | `90 min in hours` | 1.5 h |
| 54 | `2 days in hours` | 48 h |
| 55 | `1 TB in GiB` | 931.3225746 GiB |
| 56 | `10 km / 2` | 5 km |
| 57 | `1 GB / 1 MB` | 1,000 |
| 58 | `5 kg + 3 m` | err(incompatible units) |
| 59 | `5 / 0` | err(division by zero) |
| 60 | `sqrt 16 + 2` | 6 |
| 61 | `pi * 2` | 6.283185307 |
| 62 | `sin(30°)` | 0.5 |
| 63 | `round(2.5)` | 3 |
| 64 | `x = 5` | 5 |
| 65 | `x ^ 2 + 1` | 26 |
| 66 | `20 °C in °F` | 68 °F *(should)* |
| 67 | `0 K in C` | -273.15 °C *(should)* |
| 68 | `1 h 30 min in min` | 90 min *(should)* |

Also unit-test separately: renaming `price` on line 28 makes lines 30–31 `err(unknown
name)` immediately (no stale values; the review complaint), and moving line 29 below line 30
makes line 30 an error.

## Settings inventory

| Setting | Default | Options | Keep? |
|---|---|---|---|
| Download exchange rates | off | on/off, Update Now, Delete Rates | should |
| `$` means | USD | any ISO code | should |
| Copy includes unit | on | number only | should |
| Show/hide shortcut | unset | recorder | should |
| Launch at login | off | | v1 (standard) |
| Font size | system body | ⌘+ / ⌘- in View menu | should |

## Menus and shortcuts

App menu (standard + Settings ⌘,) · File: Import… ⌘O, Export… ⌘S (should) · Edit: standard
+ Copy Result ⇧⌘C, Copy All ⌥⌘C, Clear All ⌥⌘⌫ (undoable) · View: Bigger ⌘+, Smaller ⌘-,
Actual Size ⌘0 · Window · Help (a "Syntax Guide" window listing the grammar with examples,
should).

## Permissions and system integration

None. Network only when the user turns on exchange rates (ECB, HTTPS, once per day at
most, only while the app runs). No Accessibility. Global shortcut via `KeyboardShortcuts`.

## UX patterns worth adopting

- Answers appear in place while typing; no "=" or Return ceremony.
- Labels and quoted text let a sheet read like a note, not code.
- `sum` over a blank-line block is a natural mini-spreadsheet.
- Plain-text files: the user's sheets are never locked in.

## What we won't copy, and what we'll do better

- Not copying: name, icon, themes, wording, the JS extension system, newsletter prompt.
- Better: never shows a stale or misleading result (reviewers lost trust when variables
  silently broke); Decimal arithmetic; no network unless asked, with a manual-rate syntax
  for fully offline currency; global shortcut that toggles hide as well as show; no
  background helpers that relaunch themselves (a review complaint); km/mi and nmi
  conversions in the test corpus because reviewers found them missing.

## Edge cases

- Huge sheets (5,000 lines, pasted): evaluation stays under 16 ms per edit or moves off the
  main actor with the latest-edit-wins rule.
- Huge numbers / overflow (`10^400`): `err(number too large)`, not `inf`.
- Locale with decimal comma: v1 parses `.` only; documented; grouping in display follows
  locale.
- Non-English text in labels/comments: untouched; RTL text lines still align results.
- Ambiguous words: `in` (conversion) vs inches; `m` vs `M`; `x` as times only between
  numbers.
- Rates file corrupt or stale: ignore corrupt file (`err(rates unavailable)`), stale shows
  date.
- Undo across autosave; window size/position persist; dark/light; VoiceOver reads "line 3,
  dinner plus 18 percent, result 219.95".

## Our v1 scope

- [x] One autosaved sheet in a single window; results right-aligned while typing.
- [x] Arithmetic, precedence, parentheses, word operators, scales, Decimal accuracy (corpus 1–17, minus 15).
- [x] Percent forms (corpus 20–26).
- [x] Variables and `prev`, with immediate re-evaluation and no stale values (28–31 + rename/move tests).
- [x] Comments, headers, labels, quoted text, unknown words → nothing (32–35).
- [x] `sum`/`avg` over blank-line blocks (37–40).
- [x] Units: length, mass, data, time; conversion with `in/to/as` (42–49, 53–57).
- [x] Functions and constants (60–63); errors shown as reasons, not values (58–59).
- [x] Same-currency math offline (52); conversions show "rates off" until opted in.
- [x] Copy result (click / ⇧⌘C) with HUD.
- [x] Settings: General (launch at login), Currency (should), About.

Should: opt-in ECB rates + manual rate lines; temperature/area/volume; mixed-unit sums;
hex/bin output; global show/hide shortcut; import/export; Copy All/Clear All; syntax guide.

## Open questions → owner-default decisions (2026-11-03)

1. **Currency**: off by default. Opt-in downloads ECB daily reference rates (no API key,
   ~30 currencies, cached in `rates.json`). Manual `1 USD = 1.37 CAD` lines work offline. No
   crypto.
2. **Unknown words**: strict. A line with unknown words shows nothing, to avoid misleading
   answers (`3 apples + 2` → —). Labels with `:` and quotes cover note-style lines.
3. **Number type**: `Decimal` for arithmetic; `Double` only inside transcendental functions.
4. **Sheets**: one autosaved sheet in v1; multiple sheets later; no iCloud.
5. **Time zones and dates**: later (date differences first, as reviewers ask).
6. **Extensions/plugins**: no.

## Sources

- [Numi website](https://numi.app/)
- [Numi wiki (syntax, shortcuts, extensions)](https://github.com/nikolaeu/numi/wiki)
- [Numi on Setapp](https://setapp.com/apps/numi) and [reviews](https://setapp.com/apps/numi/customer-reviews)
- [ECB euro foreign exchange reference rates (daily XML)](https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml)

## Build notes (v0.1.0, steps 3–4, 2026-11-03)

**Shape.** Single-window utility (design system 2b, with an editor instead of a drop zone).
`TallyCore` is pure Swift: `LineSyntax` (headers, comments, labels, quotes, with UTF-16
ranges for styling) → `Lexer` → Pratt `Parser` (AST) → `EvalState`/`Arithmetic` over
`Decimal` (with overflow, underflow and divide-by-zero reported as errors) → `ResultFormatter`. `SheetEngine`
re-evaluates the whole sheet on every edit with a per-line parse cache keyed by line text.
Units (`Units`), currencies (`Currencies`, `RateTable`, `ECBRatesParser`, sheet rates),
`RatesUpdater` (opt-in, at most one fetch per 20 h), storage (`SheetStorage`,
`RatesStorage`, `RatesFetching`, `Clipboard` protocols with file/URLSession/NSPasteboard
implementations, all faked in tests), `SheetText` (welcome sheet, copy and Copy All text),
`SyntaxGuide` (examples evaluated live, so the guide can't drift). The app: an NSTextView
(TextKit 1) with `ResultAwareTextContainer`, which narrows only the lines that have a result,
by that result's width, so text wraps just before its own answer. Results are drawn by an
overlay subview that takes clicks only on results (copy, or open Currency settings for
"rates off"), and VoiceOver gets one element per result ("Line 5, dinner + tip, result
$219.95", press = copy).

**Decisions made while building** (on top of the owner-default decisions above).
- Errors are shown, dimmed, in the result column ("incompatible units", "unknown name
  “price”", "rates off") rather than only in a tooltip. Seeing *why* a line has no answer is
  what rebuilds the trust reviewers lost with silent variable breakage. Half-typed lines
  (`5 +`) and text show nothing.
- Strictness rule: an unknown word next to an operator is a variable reference
  (`price * qty` → "unknown name"); anywhere else the line is text (`hello world`,
  `3 apples + 2`, `Groceries 3 + 4` → nothing). Implicit multiplication only after a
  number or `)`, so `Total 1200 + 85` shows nothing rather than a wrong product.
- Results use the accent color (like Notes' math results), not secondary: they're the
  point of the app. Comments, labels and quotes are secondary; headers semibold.
- Headers start a new `sum`/`avg` block as well as blank lines. Lines that use `sum`/`avg`
  don't count towards later sums. `prev` skips lines without a value and crosses blank lines.
- `pound(s)` is the mass unit (lb); GBP is `£`, `gbp` or `GBP`. `in` is never inches (use
  `inch`/`inches`). `d` isn't a unit, so it stays free as a variable name.
- Variables can't take unit, function, constant or built-in names (`m`, `total`, `e`);
  the line says why ("“total” is a built-in word").
- A failed assignment (`a = 5 / 0`) removes `a`, so later lines say "unknown name"
  instead of using an old value.
- Rates written in the sheet win, and conversions route through them when they involve
  either currency, so a sheet's own rates stay consistent with each other.
- Number display: 10 significant digits; integers up to 15 digits shown in full;
  scientific (`1e20`, `1.234e-10`) outside that. Decimal-comma locales keep `.` as the decimal
  point (it's what input accepts) and group with a narrow space.
- Inverse trig returns radians as a unit (`asin(1)` = 1.570796327 rad, `in deg` → 90°);
  trig results within 1e-14 of zero snap to 0 (`cos(90°)` = 0).
- Export is ⇧⌘S, not ⌘S: the sheet autosaves, and ⌘S opening a save panel would surprise
  people. ⌘O imports (replaces the sheet, undoable). No shortcut for the Syntax Guide (⇧⌘/
  is the system's Help search).
- Closing the window quits, as for other single-window utilities, **unless** a show/hide
  shortcut is set: then Tally stays running so the shortcut can bring the window back.
- Copy All writes "line = answer" for lines with answers, skipping the suffix when the line
  already ends with it (`rent = 1450`).
- First run shows a welcome sheet (header, 4 lines of math, a conversion, two comments);
  an empty sheet shows a placeholder plus a pointer to the Syntax Guide.
- Text size: ⌘+/⌘-/⌘0 scale the system's Title 3 size (15 pt default) in 11 steps.
- Font: system monospaced-digit font, so columns of numbers line up.

**Gates.**
- `scripts/check.sh Tally --perf`: PASS. 63 tests in 11 suites (57 core + 6 app), with the
  68-line corpus and ~220 single-line grammar cases as parameterized cases. Launch 133 ms,
  first window 245 ms, idle CPU 0.039% (lowest window), footprint 32.8 MB (load 3.0).
- Keystroke latency, 1,000-line sheet: core re-evaluation 1.94 ms (release test), 3.5 ms
  (debug). In the release app (`TALLY_PERF_LOG`, 31 keystrokes): evaluate + format median
  2.8 ms; the whole change handler (evaluate, results, re-wrap) median 3.3 ms, p95 6.2 ms,
  max 8.1 ms. Before caching formatted strings and measured widths it was 8.75 ms median.
  A cold 5,000-line paste evaluates in 5.8 ms. First window with a 1,000-line sheet: ~490 ms
  (load 8).
- Walkthrough on `build/Tally.app` with `TALLY_DATA_DIR`, `TALLY_CLIPBOARD_FILE`,
  `TALLY_RATES_URL=file://` fixture: first-run welcome sheet; typing (results live,
  errors, "rates off", strict text); autosave across relaunch; click-to-copy (AX press) and
  HUD; Copy Result ⇧⌘C on the insertion-point line; Copy All; Clear All ⌥⌘⌫ then ⌘Z restores;
  "rates off" click opens Settings ▸ Currency; Download exchange rates on → fetch, save
  `rates.json`, sheet updates to €92.17, status "From Nov 3, 2026, 5 currencies"; sheet rate
  line overrides the table (68.50 CAD); stale rates (Oct 1 file, downloads off) show a clock,
  AX label "using old exchange rates", tooltip with the date; View Bigger/Smaller/Actual Size;
  Syntax Guide window; Settings General/Currency/Shortcuts/About; closing the window quits;
  global show/hide shortcut (⌃⌥⌘T set in Tally's defaults, pressed with `key --global` with
  Tally or Calculator in front): hides Tally when it's frontmost, shows it from Calculator,
  and after closing the window Tally stays running and the shortcut reopens it. No network
  sockets with downloads off (`lsof`). A real ECB download also ran once (see risks) and
  parsed 30 currencies for 3 Nov 2026.
- Import/Export: the panels open in the test folder (`TALLY_DATA_DIR`'s parent) with the
  right prompt and plain-text filtering, and Cancel works. **Not completed end to end**: the
  panel is drawn by macOS's "Open and Save Panel Service" process; posted keys don't reach it
  and SlopDrive refuses mouse clicks on it without `--allow-over`, which the brief doesn't
  allow. The read/write code is a few lines (UTF-8 with Latin-1 fallback, CRLF → LF).
- `scripts/drive tree --all` (main, Settings, Syntax Guide): 0 `[unlabeled]`.
- Screenshots (in `/tmp/tally-test`, not committed): `shot4.png` (dark, values + errors),
  `shot6.png` (dark, 1,000-line sheet), `main-light.png`, `main-bigger-light.png`,
  `main-empty-light.png`, `main-empty-dark.png`, `stale-light.png`, `guide-dark.png`,
  `guide-light.png`, `settings-currency-dark.png`, `settings-Shortcuts-dark.png`,
  `settings-About-dark.png`, `settings-general-light.png`, `import-panel.png`.

**Design checklist (§10).** 1 pass (type; answers appear; click copies). 2 pass (system
text view, system fonts, accent for results, semantic colors; light and dark checked).
3 pass (every action in the menu bar with shortcuts: Copy Result, Copy All, Clear All, Find,
Import, Export, text size). 4 pass (⌘, ⌘Q ⌘W; Esc closes the find bar; standard text editing).
5 pass (General: Launch at login, copy setting; About tab). 6 pass. 7 pass (placeholder +
pointer to the Syntax Guide). 8 pass (no permissions). 9 pass (Clear All and Import are
undoable; Delete Rates can be re-downloaded). 10 pass (no sockets with downloads off; opt-in
download only). 11 pass. 12 pass (results are AX buttons with full labels). 13 pass (hover and
click highlights are color changes; HUD fades). 14 pass (window frame and text size persist;
the sheet reopens where it was).

**Deferred (with reasons).** Multiple sheets and menu bar mode (later, per owner defaults);
time zones/dates (later); bitwise ops, CSS units, compound units (`km/h`), reverse percent
forms (`5% of what is 6`), wrap selection in parentheses, Print (later: niche or v1.1);
decimal-comma input (documented). Everything else in v1 scope and "should" is built.

**Known limits / risks.**
- `total`, `sum`, `avg`, `prev` and unit names can't be variables. Clear message, but people
  do write `total = ...`; watch for it in blind tests.
- `C`, `F`, `K`, `g`, `h`, `s`, `t`, `b` are units, so they can't be single-letter variables.
- Copying a result while the window is inactive needs two clicks (first activates), as
  usual on the Mac.
- Test-run incidents (my mistakes, now prevented): (1) one launch passed its env vars as a
  single zsh word, so Tally used its real data folder and two copies (Tally's own welcome
  text and "182.88 cm") went to the **real clipboard**, overwriting whatever was there. I
  deleted the folder; the clipboard can't be restored. A launcher script with quoted args
  was used from then on. (2) "Download exchange rates" was left on in Tally's defaults after
  a walkthrough, so `check.sh`'s smoke/perf launches fetched real ECB rates once into
  `~/Library/Application Support/app.slopapp.tally`. Deleted; Tally's defaults reset.

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.
