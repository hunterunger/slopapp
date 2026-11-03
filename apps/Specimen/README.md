# Specimen

Browse and compare your fonts.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to Typeface.

**Status:** alpha (0.1.0)

## What it does

Type something into the preview bar and every font you have shows it, one card per family.

- **Preview text and size** sit in a bar above the fonts, always visible. Leave the text
  empty to see each font's own name. **⌘L** jumps to the text, the presets menu has
  pangrams, alphabets, numbers, accented letters and a code sample, and **⌘+ / ⌘− / ⌘0**
  change the size (8–200 pt).
- **Honest previews.** Characters a font doesn't have are drawn faint (and counted on the
  card), never quietly borrowed from another font. Fonts that can't show your text at all
  (Arabic, Braille, emoji…) show a sample of their own characters instead, marked "Sample".
- **Sidebar:** All Fonts, Favorites, Active, Inactive, Variable, then categories (Serif, Sans
  Serif, Monospaced, Script, Display, Symbol, Other, Other Scripts) with counts. Categories
  come from the font itself (CoreText class, PANOSE, names, colour tables); if one is wrong,
  Font ▸ Category sets it yourself (undoable).
- **Search** (⌘F) matches family, style, PostScript and full names, ignoring case and
  accents, within the selected sidebar item.
- **Keyboard:** arrows move (⇧ extends), Return or Space opens a family, Esc goes back,
  typing a name jumps to it, ⌘A selects all.
- **Family page:** every style in your text, a waterfall (12–72 pt) of the selected style,
  and its details: PostScript name, version, designer, foundry, format, glyph count,
  variable axes, file location with **Show in Finder** (⇧⌘R).
- **Compare** (⌘K) stacks 2–8 selected fonts with the same text and size. Each row has a
  style picker and a remove button.
- **Favorites:** the star on a card, or ⌘D. Undo with ⌘Z.
- **Turn fonts on and off** (Font ▸ Activate ⌘; / Deactivate ⇧⌘;) with the same switch
  Font Book uses, so changes show up in every app. One undo step per change. Fonts that
  come with macOS, fonts installed for all users (`/Library/Fonts`), and fonts that share a
  name with one of those are locked, with the reason shown. Changes made in Font Book appear
  within a second.
- **Copy Name** (⌘C) and **Copy PostScript Name** (⌥⌘C) for CSS, Figma or a terminal.

No permissions, no network, no accounts. Favourites and category corrections live in
`~/Library/Application Support/app.slopapp.specimen/` (`favorites.json`, `categories.json`)
next to a disposable index cache.

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| Edit preview text | ⌘L (Return or ↓ goes back to the fonts) |
| Search | ⌘F |
| Bigger / smaller / 36 pt | ⌘+ / ⌘− / ⌘0 |
| Show details | Return, Space, ⌘↓ or double-click |
| Back | Esc or ⌘[ |
| Compare | ⌘K |
| Add to / remove from Favorites | ⌘D |
| Activate / Deactivate | ⌘; / ⇧⌘; |
| Copy name / PostScript name | ⌘C / ⌥⌘C |
| Show in Finder | ⇧⌘R |

## Not there yet

Activating fonts in place from your own font folders, temporary activation, tags, a
character browser, variable-axis sliders, a List view, sort options, "hide fonts that can't
show this text", adding fonts by drag and drop, a persistent compare tray. Moving fonts to
the Trash and a duplicate finder are deliberately left out of v1.

## Develop

```sh
scripts/test.sh Specimen         # unit tests
scripts/run.sh Specimen          # build a debug .app and open it
scripts/check.sh Specimen --perf # the full gate: tests, release bundle, smoke test, budgets
```

Environment switches (for tests, walkthroughs and blind tests):

| Variable | Effect |
|---|---|
| `SPECIMEN_DATA_DIR=/tmp/specimen-test/data` | Favourites, categories and the index cache go here instead of Application Support |
| `SPECIMEN_TEST_FONTS=/tmp/specimen-test` | Test mode: font files in that folder are registered for the session while Specimen runs (and cleaned up on quit), and they're the only fonts Specimen may turn on or off |
| `SPECIMEN_APPEARANCE=light\|dark` | Force an appearance for screenshots |
| `SPECIMEN_STRESS=10` | Repeat the library 10× to test scale (display only; turning fonts on/off is disabled) |
| `SPECIMEN_BENCH=scroll,typing` (+ `SPECIMEN_BENCH_OUT=file.json`) | Measure scroll and typing on the real window, write JSON, quit |

The test font is Silkscreen (SIL OFL 1.1, `Tests/Fixtures`).
`swift run --package-path apps/Specimen specimen-fixture install|status|clean` copies it to
`/tmp/specimen-test`, shows whether it's registered and on, and cleans up (turns it back on,
unregisters it, deletes the folder) after a crash.
