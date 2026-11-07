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
  change the size (8–200 pt). The eye button (**⇧⌘H**) hides fonts that can't show every
  character of your text.
- **Specimen cards:** a small status mark (filled = on, hollow = off, lock = macOS's) and the
  family name along the top, the number of styles on the right, your text large and centred.
  Hover a card for its star and its **⊕ Compare** button.
- **Honest previews.** Characters a font doesn't have are drawn faint (and counted on the
  card), never quietly borrowed from another font. Fonts that can't show your text at all
  (Arabic, Braille, emoji…) show a sample of their own characters instead, marked "Sample".
- **Grid or list** (**⌘1 / ⌘2**). The list shows state, name, styles, weight range,
  category, format, version, foundry, location and date added, with a preview of the
  selected font on top; disclose a family for its styles; click a column to sort.
- **Sort** by name, date added, number of styles, category or foundry (View ▸ Sort By or the
  toolbar); choosing the same key again reverses it.
- **Sidebar:** All Fonts, Your Fonts, macOS Fonts, Active, Inactive, Favorites, Variable;
  your **Tags**; **Smart Collections**; then categories (Serif, Sans Serif, Monospaced,
  Script, Display, Symbol, Other, Other Scripts), all with counts. Categories come from the
  font itself (CoreText class, PANOSE, names, colour tables); if one is wrong, Font ▸
  Category sets it yourself (undoable).
- **Tags:** **⌘T** opens a tag panel for the selection (type to filter, Return or Tab toggles,
  Return on a new name creates it), **⌘N** makes a new tag, or drag cards onto a tag in the
  sidebar. Rename and delete from the tag's right-click menu. Undoable.
- **Smart collections** (**⌥⌘N**, or the + in the sidebar) save rules: name contains,
  category, on/off, your fonts or macOS's, a tag, variable only, favourites only, a minimum
  number of styles. A new one starts from the current sidebar item and search, and shows a
  live count.
- **Compare tray:** **Return** (or the ⊕ on a card) collects fonts into a tray that stays put
  while you browse and across launches; the toolbar shows how many. **⌘K** opens them stacked
  with the same text and size, each with a style picker, reorder by dragging, remove, and a
  link to its details. **⌥⌘K** clears it.
- **Search** (⌘F) matches family, style, PostScript and full names, ignoring case and
  accents, within the selected sidebar item.
- **Keyboard:** arrows move (⇧ extends), **Space** opens a family (and closes it again),
  **Return** collects, Esc goes back, typing a name jumps to it, ⌘A selects all.
- **Family page** with tabs (**⌘1–⌘5** while it's open) and a style picker shared by all of them:
  - **Styles:** every style in your text.
  - **Characters:** every character the style has, by group (letters, numbers, punctuation,
    symbols, currency, marks), searchable by character, Unicode name or code point, with a
    big view of the selected one and Copy Character / Code Point / HTML Entity.
  - **Text:** a heading and paragraph at a reading size you pick, and a waterfall (9–96 pt).
  - **Variables** (variable fonts): a slider per axis with sample letters across its range,
    named instances, Reset, and Copy CSS (`font-variation-settings`).
  - **Info:** PostScript name, version, designer, foundry, format, glyph count, weight,
    axes, copyright, licence, file location with **Show in Finder** (⇧⌘R), tags, and a table
    of every style.
- **Add Fonts…** (**⌘O**, or drop font files or folders on the window) copies them into your
  Fonts folder, skipping exact copies and fonts whose name is already installed, then selects
  them. Anything skipped is listed with the reason.
- **Favorites:** the star on a card, or ⌘D. Undo with ⌘Z.
- **Turn fonts on and off** (Font ▸ Activate ⌘; / Deactivate ⇧⌘;) with the same switch
  Font Book uses, so changes show up in every app. One undo step per change. Fonts that
  come with macOS, fonts installed for all users (`/Library/Fonts`), and fonts that share a
  name with one of those are locked, with the reason shown. Changes made in Font Book appear
  within a second.
- **Copy Name** (⌘C) and **Copy PostScript Name** (⌥⌘C) for CSS, Figma or a terminal.

No permissions, no network, no accounts. Favourites, tags, smart collections and category
corrections live in `~/Library/Application Support/app.slopapp.specimen/`
(`favorites.json`, `collections.json`, `categories.json`) next to a disposable index cache.

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| Edit preview text | ⌘L (Return or ↓ goes back to the fonts) |
| Search | ⌘F |
| Grid / List | ⌘1 / ⌘2 |
| Bigger / smaller / 36 pt | ⌘+ / ⌘− / ⌘0 |
| Hide fonts that can't show the text | ⇧⌘H |
| Show details | Space, ⌘↓ or double-click |
| Detail tabs | ⌘1–⌘5 (on the family page) |
| Back | Esc, Space or ⌘[ |
| Add to / remove from Compare | Return |
| Compare / clear Compare | ⌘K / ⌥⌘K |
| Tags… / New Tag… / New Smart Collection… | ⌘T / ⌘N / ⌥⌘N |
| Add Fonts… | ⌘O |
| Add to / remove from Favorites | ⌘D |
| Activate / Deactivate | ⌘; / ⇧⌘; |
| Copy name / PostScript name | ⌘C / ⌥⌘C |
| Show in Finder | ⇧⌘R |

## Not there yet

Activating fonts in place from your own font folders (watched locations), temporary
activation, nested tags, an OpenType features tab, overlay compare and pairing layouts,
tracking and auto size, weight/width/language filters, PDF specimens, tag export. Moving
fonts to the Trash and a duplicate finder are deliberately left out.

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
| `SPECIMEN_SNAPSHOT_DIR=/tmp/shots` | Walk the window through every screen and sheet in light and dark, write PNGs of Specimen's own window, quit (works with the screen locked; never saves preferences; creates sample tags in `SPECIMEN_DATA_DIR`) |
| `SPECIMEN_SNAPSHOT_ADD=/a.ttf:/b.ttf` | With the above in test mode: also add these files and record what got selected |
| `SPECIMEN_INSTALL_DIR=/tmp/x` | Where Add Fonts… copies files. Test mode defaults to `<test folder>/Added` and registers copies for the session only, so tests never install anything |

The test font is Silkscreen (SIL OFL 1.1, `Tests/Fixtures`).
`swift run --package-path apps/Specimen specimen-fixture install|status|clean` copies it to
`/tmp/specimen-test`, shows whether it's registered and on, and cleans up (turns it back on,
unregisters it, deletes the folder) after a crash.
