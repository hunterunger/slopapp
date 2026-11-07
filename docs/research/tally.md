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

## Parity pass (2026-11-03)

Per [`docs/parity-pass.md`](../parity-pass.md): look and work much more like Numi, and don't
miss features. Numi isn't installed, so this used the
[Numi wiki](https://github.com/nikolaeu/numi/wiki/Documentation) (full syntax),
[its GitHub releases](https://github.com/nikolaeu/numi/releases) (3.20–3.34: notes and a
notes list, time zone service, today widget, Alfred, crypto), the
[Setapp listing](https://setapp.com/apps/numi) and its five screenshots, and the
[numi.app](https://numi.app/) preview (downloaded to `/tmp/tally-parity/`, not committed).
**What the screenshots show:** one quiet editor surface where the title bar shares the
sheet's background; answers right-aligned in a contrasting colour; syntax colouring (labels,
operator words, variables, headers each in their own colour); a clicked answer gets a filled
highlight; and a slim bar along the bottom with a control on the left, the sheet's
**Total** (or "Click to copy" while hovering an answer) in the middle, and a control on the
right. Numi 3 adds several notes with a notes list.

### Gap table

| Feature / design item | Numi | Tally before | Now | Notes |
|---|---|---|---|---|
| Editor surface: title bar shares the sheet background | yes | standard title bar | **done** | `toolbarBackground` in the theme's background; compact unified title showing the sheet's title |
| Bottom bar: left control, Total in the middle, right control | yes | none | **done** | Left: theme menu. Middle: `Total: $1,648.43`, or `Selection:` for selected lines; click (or ⇧⌘T) copies. Right: New Sheet (window) / Open window (menu bar panel) |
| Syntax colouring | yes | headers/comments/labels only | **done** | `Highlighter` (core): numbers, operator words, units/currencies/zones, variables, labels, comments, headers. Places only after `in`/`to` or before `time`; `and`/`is`/`with` only in lines with numbers |
| Click-to-copy highlight | filled pill | grey hover/flash | **done** | Tinted with the theme's answer colour |
| Several sheets + list | notes + notes list | one sheet | **done** | Sidebar (`NavigationSplitView`), newest edit first, title from the first line, date; hidden by default for the minimal look, ⌃⌘S or the toolbar toggles it. ⌘N, ⇧⌘] / ⇧⌘[, Delete Sheet… (sidebar menu, Delete key, File menu). Each sheet keeps its own undo and insertion point |
| Themes | day/night + others | system only | **done** | System (default, accent answers), Paper, Midnight, Dusk, Graphite: our own palettes. View ▸ Theme, bottom-bar menu, Settings ▸ Appearance with swatches |
| Menu bar mode | yes (dock or menu bar) | no | **done** | Settings ▸ General: Show Tally in the menu bar; then Show Dock icon can be turned off. Click: the current sheet in a panel (live, same text), sheet switcher, total, open window. Right-click: Open Tally, New Sheet, Settings…, Quit |
| Global hotkey | yes | show/hide window | **done** | Menu-bar-only: toggles the panel |
| Float on top | unconfirmed | no | **done** | Window ▸ Float on Top (cheap, handy for a calculator) |
| Time zones: `PST time`, `New York time`, `time in Madrid`, `2:30 pm HKT in Berlin` | yes | no | **done** | Offline: every city in the system's zone database plus ~150 extra cities/countries, and upper-case abbreviations |
| Dates and times: `now`, `today + 3 weeks`, `Dec 25 - today`, `5pm - 9am`, `fromunix()` | yes | no | **done** | Calendar-aware months/years; ISO dates; `Dec 25`, `25 Dec 2027`; `noon`; `now in unix`; answers that use the clock refresh on the minute |
| CSS units `px pt em` with `em =` / `ppi =` | yes | no | **done** | Defaults 16 px/em and 96 ppi, configurable in Settings ▸ General ▸ Screen units; sheet lines override for the lines below; `rem` = `em` |
| Compound units (`km/h`) | partial | no | **done** | `km/h`, `m/s`, `mph`, `knots`, `Mbps`, `$/h`, `€/kg`, `per`; rate × time = distance, distance ÷ speed = time, `1 GB / 100 Mbps` |
| Bitwise `& | xor << >>` | yes | no | **done** | C precedence; whole numbers only |
| Reverse percentages | yes | no | **done** | `5% of/on/off what is 6`, `6 is 5% of what`, `as a % of/on/off` |
| Word operators `and with without mul divide (by)` | yes | partial | **done** | |
| `log 2 (10)`, `root 2 (8)`, `square root of`, `arcsin`, `sinh/cosh/tanh` | yes | partial | **done** | |
| Units: mil, hand, rod, chain, furlong, cable, league, carat, centner, are, `sqm`, `cbm`, points | yes | partial | **done** | Plus decade, century |
| Variables in any case (`Amount` / `amount`) | yes | case-sensitive | **done** | |
| Autocomplete | yes | no | **done** | Inline grey suggestion (sheet variables after 2 letters; units/currencies/places after a number or `in`, 3 letters); Tab accepts, Esc lists every completion (variables first) |
| Import / export plain text | yes | yes | kept | Import now opens as a new sheet |
| Sheet-defined functions and units (Numi's JS extensions) | JS plugins | no | deferred, **M (~1 day)** | Running user JavaScript is a code-execution surface we won't add. The safe equivalent is in-sheet definitions: `tip(x) = x * 18%`, `1 sprint = 2 weeks`. Needs function scope in the evaluator and plural handling for new units |
| Command-line tool + Alfred/Raycast workflow | yes | no | deferred, **M (~1 day)** | Core is a pure library, so a `tally` CLI target is small; shipping it needs the bundle pipeline to carry a second binary, plus a workflow file and docs |
| Today widget | yes (3.27) | no | deferred, **L** | Needs a WidgetKit app extension, which the SwiftPM + scripts pipeline can't build yet |
| Precision / format settings | Numi 2 | no | deferred, **S (~2 h)** | A "decimal places: auto / 0–8" setting on `ResultFormatter` |
| Weekday words (`next friday`), `UTC+3`, zone differences (`Tokyo - London`) | partial | no | deferred, **S each** | Parser additions; not in the docs' examples |
| Localization (26 languages) | yes | English | deferred, **L** | |
| Decimal-comma input (`1,5`) | locale | no | deferred, **M** | Conflicts with `1,250` grouping; needs a locale setting |
| Crypto rates | yes | no | skip | Needs another network source; currency stays opt-in ECB only |
| iCloud sync | yes | no | skip | No accounts or network sync in Slopapp apps; sheets are plain files |

### Decisions (made while building; owner asleep)

- **Variables match in any case** (`Rent = 1200`, then `rent / 3`), as in the original's own
  examples. Assigning `RENT` updates the same variable.
- **Zone abbreviations follow their region's daylight saving time**: `PST` in July means
  Pacific time, which is what people mean. Upper case only, so "est" in a note isn't a zone.
- **A time in another zone means today there**: `2:30 pm HKT` is today's date in Hong Kong.
  Times show the weekday when it isn't today here (`Wed 7:30 AM Berlin`), and the date when
  it's more than a week away.
- **The sheet's clock is the current minute**: answers show minutes, refresh on the minute,
  and identical answers within a minute reuse their formatting.
- **Total = the most common kind of answer**, added up in its first answer's unit or
  currency (other currencies converted when rates allow). Percentages, dates and `sum`/`avg`
  lines are skipped. Numi seems to add everything in order (its screenshot adds a `5%` line
  into a money total); a budget with a few conversions should still total its money.
- **Sheets** are ordered by last edit (like Notes) and titled by their first line with text.
  The sidebar starts hidden, to keep the original's single-surface look; its state is
  remembered. Deleting asks first (unless the sheet is empty) and can't be undone.
- **Old data**: a 0.1 `sheet.txt` is copied in as the first sheet and left in place, so going
  back to 0.1 loses nothing. A first-run welcome sheet isn't written to disk until edited.
- **Menu bar** icon off by default (Tally stays a Dock app, as before). The Dock icon can only
  be hidden while the menu bar icon is shown, so Tally is never unreachable.
- **Suggestions are inline, not a pop-up list while typing**: a list that opens by itself
  can swallow Return. Grey text never changes what typing does; Tab takes it. Esc (the
  system's completion key in text views) lists everything.
- **`pt` is the typographic/CSS point** (as in the original); US pints stay `pint`.
- **`and` / `with` mean plus** (as in the original), but don't turn unknown words into errors,
  so "rent and utilities" stays a note. Likewise `&` and `|` next to words ("R&D").
- **`per`** with a unit makes a rate (`$25 per hour`); with a number it divides
  (`100 km per 2 hours` = 50 km/h).
- **Month names before or after a day are dates** (`may 5`, `10 dec`); `in dec` is still the
  decimal number format.

### Deviations from the design system (and why)

- **Theme palettes are hard-coded colours** (Paper, Midnight, Dusk, Graphite). The original
  offers themes; ours are our own palettes. The default "System" theme uses only semantic
  colours and the user's accent colour.
- **Syntax colouring** uses system colours (pink, indigo, teal) in the System theme.
- **The title bar takes the sheet's background**, and the **bottom bar is custom**, to match
  the original's single-surface layout.
- **Inline suggestions are drawn by the editor** (NSTextView has no ghost-text API).
- **The menu bar panel is a hand-built `NSStatusItem` + `NSPopover`**, not `MenuBarExtra` +
  `MenuFooter`: Tally is a window app whose menu bar icon is optional and shows a live editor.
  Its right-click menu ends with Settings… and Quit, like `MenuFooter`.

### Gates and evidence

- **Tests**: 89 test functions in 17 suites (75 core + 14 app), with 364 parameterized cases:
  the 68-line v1 corpus, 185 single lines, and 111 new parity lines (time zones and dates on
  a fixed clock, CSS, rates, bitwise, reverse percentages, word operators, function forms,
  units). New suites cover em/ppi lines, totals, highlighting, suggestions, the sheet library
  (first run, migration, ordering, deletion, files) and, in the app, switching sheets, per-sheet
  undo, two editors sharing a sheet, the footer total and selection total, theme restyling and
  Tab accepting a suggestion. All pass.
- **`scripts/check.sh Tally --perf`**: PASS. Launch 161 ms, first window 334 ms, idle CPU
  0.019% (lowest window), footprint 45.3 MB (was 32.8 MB: the split view, sidebar and theme
  machinery), load 3.2.
- **Keystroke latency, 1,000-line sheet**: core (release test, now including dates, zones,
  rates, the total and highlighting the edited line) 3.77 ms; cold 5,000-line paste 10.1 ms.
  End to end in the release app (`TALLY_PERF_SIM=1`: real NSTextView edits in an offscreen
  window, through evaluation, total, colouring, re-wrap, layout and drawing the whole window,
  36 keystrokes): **median 3.17 ms, p95 4.95 ms, max 5.85 ms**, inside one 120 Hz frame.
  Before fixing it, splitting the text storage's bridged string cost 2.9 ms per keystroke
  (median was 8.1 ms); the text is now transcoded to native UTF-8 once.
- **Offscreen renders** (`TALLY_SNAPSHOT_DIR`, release build, test data and defaults suite;
  in `/tmp/tally-parity/renders/`, not committed), all looked at: `main-system-light.png`,
  `main-system-dark.png`, `main-paper.png`, `main-midnight.png`, `main-dusk.png`,
  `main-graphite.png` (each with the grey suggestion "fli|ghts" on the last line),
  `sidebar-system-light.png`, `sidebar-system-dark.png`, `sidebar-midnight.png`,
  `menubar-panel-light.png`, `menubar-panel-dark.png`, `menubar-panel-midnight.png`,
  `settings-general-{light,dark}.png`, `settings-appearance-{light,dark}.png`,
  `main-empty-light.png`. (The dark Settings render draws the tab bar blank; that's the
  offscreen renderer, the light one is fine.)
- **Not run (screen locked)**: `scripts/drive` walkthroughs, `drive tree`, window
  screenshots. Every icon-only control has an explicit accessibility label (theme menu,
  New Sheet, Open Tally Window, Sheets, total button). An in-process AX audit of the
  offscreen windows found no elements at all (SwiftUI builds its AX tree only for a real
  client), so it was dropped as proof of nothing.

### On-screen checks still owed (need an unlocked screen)

1. `scripts/drive tree` on the main window (sidebar shown and hidden), menu bar panel,
   Settings (all tabs) and Syntax Guide: no `[unlabeled]`.
2. Typing walkthrough on `build/Tally.app` with the launcher (`TALLY_DATA_DIR`,
   `TALLY_CLIPBOARD_FILE`, `TALLY_RATES_URL`, `TALLY_DEFAULTS_SUITE`): grey suggestion appears
   while typing a variable, Tab accepts, Esc shows the completion list, Return still makes a
   new line while a suggestion shows.
3. Sidebar: ⌘N, click between sheets, ⇧⌘] / ⇧⌘[, Delete key and context menu (with the
   confirmation), per-sheet ⌘Z, sheet titles updating as the first line changes; the
   sidebar toggle in the title bar and ⌃⌘S.
4. Themes on a real window: title bar colour matches the sheet, caret and selection colours,
   find bar and scroller in the dark themes; switching from the bottom-bar menu.
5. Menu bar: turn the icon on, click (panel shows the current sheet, typing there updates the
   window), right-click menu, hide the Dock icon (Tally keeps running with only the icon; the
   global shortcut toggles the panel), turn it back on.
6. Footer: select several lines, `Selection:` total, click copies (to the clipboard file).
7. Float on Top; `now` lines ticking over at the minute.
8. Light and dark window screenshots with the real title bar.

### Files

New: `TallyCore/Zones.swift` (places, abbreviations, calendar helpers), `Highlighter.swift`
(colouring, completions, inline suggestions), `Library.swift` (sheets on disk);
`Tally/SheetDocument.swift`, `MainView.swift` (window, sidebar, bottom bar), `MenuBar.swift`,
`Theme.swift`, `Snapshots.swift` (render and perf-simulation hooks). Rewritten:
`SheetModel.swift` (library, several editors, totals, clock refresh, themes),
`Editor/SheetStyler.swift`, `Editor/SheetEditor.swift`; extended: lexer, parser, arithmetic,
formatter, units, syntax guide, settings, commands. Candidates for SlopKit later: the
offscreen render helper (Zones and Convert have their own), `Theme`-style editor palettes,
and the status-item-plus-popover controller.

## Polish pass (2026-11-05)

Per [`docs/polish-pass.md`](../polish-pass.md), including the mid-pass Golden Gate and
light/dark addition. Release build (`build/Tally.app`, SDK 27.0) on macOS 27.2, test data
only (`TALLY_DATA_DIR=/tmp/tally-test/data`, `TALLY_DEFAULTS_SUITE=app.slopapp.tally.test`,
`TALLY_CLIPBOARD_FILE`, `TALLY_RATES_URL=file://…` pointing at a missing fixture so nothing
touched the network). The owner's `app.slopapp.tally` domain was exported first and imported
back at the end (verified identical). Download exchange rates stayed off.

**Measuring.** `drive shot` captures read about 20 % low on contrast in light mode (label
colour measures 12.7:1, the system's own secondary label 3.13:1, nominal 3.95:1) and a bit
high in dark mode, so captured numbers are compared against those references, and palette
numbers are nominal (computed from the colours). Baselines and edges were measured with a
small ink-bounding-box tool on @2x shots (`/tmp/slopapp-polish/tally/bin/inkc`).

### Defects fixed (before → after)

| # | Where | Before | After |
|---|---|---|---|
| 1 | Lint | 2 corner literals (theme swatch `cornerRadius: 6`), 4 spacing literals | 0 / 0: `Radius.s`, `Spacing.xs`/`.s` |
| 2 | Theme swatch | 1 pt `strokeBorder(.separator)`; fixed 11 pt monospaced code font (not the editor's type) | `hairlineBorder` (one device pixel); `.callout.monospacedDigit()`, medium answer like the sheet |
| 3 | Answer hover/click pill | `NSBezierPath` radius literal 5; drawn inset 5×2, hit area 6×3, redraw 8×4 (three sizes) | one `pillRect`: `Radius.s`, inset `Spacing.xs`×2, used for drawing, hit testing and the cursor rect |
| 4 | Error answers' baseline | 1.0 pt above the line (367 vs 368, 390 vs 391, 413 vs 414): smaller font centred vertically | on the line's baseline (370/370, 393/393; values 94/94), using the typesetter's own `defaultBaselineOffset(for:)` |
| 5 | Error answers' contrast | System: `tertiaryLabelColor`, 1.67:1 measured light, 2.72:1 dark. Palettes 2.10 / 2.86 / 2.91 / 2.92 | System: secondary label (the floor, 3.13 measured light, 6.47 dark); palettes 4.10 / 4.16 / 4.19 / 4.13 (quiet by size, not by colour) |
| 6 | Palette comments / labels (also the bottom bar's text) | Paper 2.39 / 2.90, Midnight 3.13 / 3.94, Dusk 3.27 / 4.26, Graphite 3.29 / 4.31 | 4.61 / 4.94, 4.65 / 4.90, 4.61 / 4.90, 4.61 / 4.93 (same hues, mixed towards the text colour) |
| 7 | System theme syntax colours, light | teal variables 1.92:1 measured (≈2.2 nominal), pink words 3.23, accent answers 3.25 (blue; a yellow accent would be ≈1.6) | each darkened just enough to reach 4.5:1 nominal (variables 3.70, answers 3.61 measured), resolved at draw time so it follows the accent colour; dark-mode accent 4.15 → 4.5 (lightened) |
| 8 | Long answers | head-truncated: "…v 3, 2015 at 2:46:26 PM"; a capped answer could touch its wrapped text (0 pt gap) | middle-truncated ("Tue, Nov 3,…2:46:26 PM"), errors keep their first words (tail); the tooltip shows the whole answer; capped width leaves the 16 pt gap |
| 9 | Bottom bar edges | theme symbol at 16 pt vs text edge 20; New Sheet symbol 6 pt past the answers' edge | 20.0 and 748.5 vs answers 749.5 (pencil tip, optical) |
| 10 | Bottom bar theme symbol colour | label colour, 13:1, beside a 3.1:1 sibling (AppKit draws a menu's label itself) | same opaque secondary as its sibling (3.13 both) |
| 11 | Total | "Total: $1,648.43" centred as a group: every width change moved "Total:" by half | label ends 2.5 pt left of centre, value starts 2.5 pt right: the label never moves |
| 12 | Bottom bars | sheet bar 28 pt (centre 466) beside the sidebar's 32 pt bar (centre 464) | 32 pt, one centre line |
| 13 | Sidebar footer | rows scrolled visibly under "New Sheet" (a date overlapped it); "+" at 10 pt, titles at 16 | scroll-edge bar on macOS 26+ (rows fade under it), bar material + hairline on 14–15; "+" at 16 |
| 14 | Menu bar panel | title at 12 pt vs text 20; sheets menu symbol 4.5 pt short of the answers' edge, label colour | title 20, symbol ends 359.5 = answers 359.5, bar colour |
| 15 | Editor top inset | 14 pt | 16 pt (`Spacing.l`) |
| 16 | Empty sheet hint | tertiary, 1.66:1 | comment colour, 3.10 (secondary floor) |
| 17 | Settings | 7 explanations as separate rows; the Dock toggle carried the menu bar's explanation; theme checkmark appeared/disappeared; rates error in plain `.orange` (≈2:1 light) | subtitles under each control, section notes as footers; each toggle explains itself; checkmark in a fixed slot, grey when the window is inactive; `.textOrange`; px/ppi in equal slots so both fields end on one edge |
| 18 | Syntax Guide | unrecognised examples in `.tertiary`; answers in plain accent | `.secondary`; the sheet's readable accent |
| 19 | Narrow windows (360–380 pt) | last line's answer missing until a sheet switch; once a blank sheet (dark, 360 pt) | fixed: one coalesced redisplay after the text view resizes itself mid-display (non-contiguous layout). 6 of 6 launches correct |
| 20 | Copy | straight apostrophes in 3 strings ("Couldn't download rates…"); delete alert body repeated the title | curly; "Its lines and answers go with it. You can’t undo this." |

Unchanged on purpose: value answers already shared the line's baseline exactly (92/92);
inputs wrap before their own answer; the 8 pt reserve rounding keeps lines from re-wrapping
on every digit; Total uses `.monospacedDigit()`.

### Golden Gate + light/dark

- **Sidebar**: system `NavigationSplitView` sidebar. With the System theme the toolbar is
  now the system's own, so the sidebar runs edge to edge under the title bar (before, the
  sheet's white strip ran across its top). Rows have no icons (titles and dates, like Notes);
  the footer is a system scroll-edge bar.
- **Menus**: every menu is text only: View ▸ Theme and the bottom-bar theme menu (inline
  picker with its checkmark), the panel's sheet list, the sidebar context menu, the status
  item's right-click menu, all main-menu commands.
- **Toolbar**: standard (`unifiedCompact`, sidebar toggle, title). Palette themes (Paper,
  Midnight, Dusk, Graphite) still paint the toolbar in their background, a recorded
  deviation: otherwise a navy sheet sits under a grey title bar. Scrolled text stops at the
  toolbar edge in both modes (`after-scrolled-{light,dark}.png`).
- **Inactive windows**: every window shot is of an inactive window (the owner was using the
  Mac): sidebar selection and toggles go grey (system), the theme checkmark now greys too,
  text selection is the system's. Answers keep their colour when inactive: they're the
  sheet's syntax colouring (content), not state, and people keep Tally beside other apps.
  The hover pill only appears in the key window (`.activeInKeyWindow` tracking).
- **Glass**: system only (the popover, HUD, toolbar); no drawn translucency.
- **Light and dark**: every window shot in both, side by side, with every theme in both
  system appearances (palette themes force their own and look identical either way). No layer
  or CGColor colours: the editor draws with dynamic `NSColor`s resolved at draw time, and the
  new readable/opaque colours are dynamic providers, so a live appearance change re-resolves
  them. Each theme's syntax colours pass on its own background (`ThemeContrast` tests check
  every role of every theme, System in both appearances).

### Tests and gates

- New `Tests/TallyAppTests/PolishTests.swift`: theme contrast (all palettes; System light and
  dark), the adaptive readable colour, answers and errors on the line's baseline, middle
  truncation and the full-answer tooltip. **94 tests pass** (75 core, 19 app).
- `scripts/check.sh Tally --perf`: **PASS** (busy machine, load ≈5): launch 153 ms, first
  window 362 ms, idle CPU 0.027 %, footprint 52.7 MB.
- `TALLY_PERF_SIM` keystroke latency, 1,000 lines: median 3.22 ms, p95 4.05 ms (was 3.17 / 4.95).
- `scripts/drive tree`: 0 `[unlabeled]` across the main window (sidebar shown and hidden),
  every Settings tab and the Syntax Guide; window buttons 16×16 in all three windows.

### Screenshots

`/tmp/slopapp-polish/tally/shots/`: `before-*` and `after-*` (`after-main-<theme>-<light|dark>`
for all five themes, `after-sidebar-{light,dark}`, `after-sidebar-midnight-{light,dark}`,
`after-long-{light,dark}`, `after-long-min-dark`, `after-scrolled-{light,dark}`,
`a-many-{light,dark}` (40 sheets), `after-settings-<Tab>-<light|dark>` for every tab plus
`-General-nomenubar-*` and `-Currency-failed-*`, `after-guide-{light,dark}`,
`after-delete-alert-light-1`, `after-flash-light-1` (HUD)), and offscreen renders of the menu
bar panel and empty sheet in `renders-before/` and `renders-after/`.

### Not done, and why

- **Hover states** (answer pill, Total turning the answer colour) and the 250 ms click flash:
  designed in code; seeing them needs the real pointer, and the owner was active.
- **Active main window screenshot**: the owner came back mid-check; only the Syntax Guide
  was shot as key. Tally was hidden straight away to hand focus back.
- **The real status item and popover**: AX can't reach Tally's status item and the real mouse
  wasn't available; the panel was checked through `TALLY_SNAPSHOT_DIR` renders (light, dark,
  Midnight) and measured there.
- **Very long tokens** (a 15-digit number, a 40-letter name) still break mid-token in narrow
  windows when they can't fit beside their answer; that's the only place they can go.
- **Deleting a sheet can't be undone** (checklist 9): it asks first. Moving the file to the
  Trash or an undo is a behaviour change, left for a feature pass.

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.
