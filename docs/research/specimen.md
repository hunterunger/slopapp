# Specimen research (inspired by Typeface)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied on
> 2026-11-03: **Typeface 4.5.2 (5314)**, Setapp build, `/Applications/Setapp/Typeface.app`
> (bundle id `com.criminalbird.typeface-setapp`, sandboxed, minimum macOS 12), read-only.
> Also its help center (16 articles, 13 tips, 7 troubleshooting pages), the Mac App Store and
> Setapp listings and reviews, a TypeDrawers thread, review sites, and Apple's CoreText
> headers (macOS 27 SDK). We study how it works so we don't reinvent the wheel. We never copy
> its name, icons, artwork, wording, sounds or signature visuals.
>
> **How the installed copy was studied.** Typeface wasn't running. Every launch opened its
> *support tools* window instead of the library, because the session kept reporting ⌥⇧ (and
> later ⌃⌥⌘) as held down. Typeface treats a modifier held at launch as "open recovery
> tools", and another process on this Mac was holding them. The tools window's own
> "Launch App" button didn't respond to Accessibility presses, and mouse and global keys are
> off limits for this step, so **the main library window was never shown**. What I did see:
> the support tools window, the full static main menu, and all four Settings panes (opened
> from the app menu; I only switched tabs, changed nothing, and put it back on General). I
> filled the gaps from the help center and from the bundle's localization keys
> (`nl.lproj/Localizable.strings`: 935 keys naming every detail tab, context-menu item,
> filter, sidebar tag and dialog, with Dutch values that I translated). The dynamic menus
> (Font, Typography, View ▸ Library) are empty until the library loads, so their contents
> come from the help center's shortcut list. No tags, collections, backups or font names of
> the owner's were read or recorded. The Backup pane lists dated backups; only its layout
> is described here. Typeface was quit at the end.
>
> **Local measurements** (this Mac, counts only, `/tmp/specimen-probe`): 188 families /
> 666 faces / 298 files (516 faces in `/System`, 144 in `/Library/Fonts`, 6 in
> `~/Library/Fonts`). Family names: 15 ms. All face descriptors incl. disabled: 51 ms.
> Reading URL + enabled + scope for every face: **535 ms** (the slow part). Symbolic traits
> for all: 19 ms. Creating a CTFont + CTLine at 36 pt for 400 faces: 174 ms (≈0.45 ms each).
> Variation axes for all: 44 ms (118 variable faces). **23% of faces (154/666) have no
> CoreText class**, and PANOSE resolves only 35 of those (most of the rest are non-Latin
> system fonts with PANOSE "any").

## The job

A designer, developer or writer wants to pick a typeface. They want to see their own words
set in every font they have, side by side, at a size that matters to them, narrowed to the
kind of face they need ("a monospaced font for this terminal", "a serif for this book
cover"). Then they want to look closely at a few candidates: all the weights, the
characters, whether it has a true italic or a variable weight axis. Sometimes they also need
to turn fonts on or off so their design apps' font menus stay manageable. Font Book can do
some of this but is slow and clumsy for browsing. "Done" is when they know the font's name
and have it active, and it took a minute, not twenty. **The interaction that matters most:
type your text into the preview field, and the whole grid instantly re-sets in every
font; drag the size slider; click a category in the sidebar to narrow it.**

## Who and when

- Picking a font for a slide deck, logo, poster or app UI: type the headline, scroll the
  grid, shortlist 3–5, compare them.
- A developer choosing a coding font: filter to Monospaced, type `0O1lI{}=>`, compare.
- "Which font is this file using, and do I have it?": search by name, check styles and
  activation.
- Cleaning up: turning off (deactivating) dozens of fonts that clutter font menus, or
  turning one back on for a project.
- Checking a font's coverage: does it have ñ, €, Cyrillic, small caps, a variable weight axis?

Frequency: a few times a week for people who make things, sessions of 1–10 minutes; very
bursty around projects. Others open it once a month. Launch speed and "type and see"
latency are what make it feel good or bad.

## Typeface at a glance (4.5.2)

- **Shape.** One main window: collapsible sidebar on the left, toolbar (sidebar toggle,
  shortlist, preview-text button, view switch, size/tracking slider, search with a filter
  panel), a central grid of previews, and a full-window **details** view replacing the grid
  on double-click or Space, with seven tabs. Esc or a Back button returns. Dark-first custom
  chrome that tints itself to the preview colours.
- **Library model.** Typeface keeps its own database (Realm) of fonts imported from
  "sources": Font Book (system and user-installed fonts), folders you add (watched, with
  subfolders shown in the sidebar, rescanned at launch), optional Adobe Fonts and Google
  Fonts (it downloads the whole ~2 GB library). It never moves files; activation registers a
  file where it lies.
- **Grid.** One preview per family by default (⌥G toggles), with a member-count button that
  expands the family. The representative face is the one nearest Regular, among faces that
  pass the current filters. Each card has an activation dot and a corner "collect" button.
  Previews adapt to the font (emoji fonts show emoji, Arabic fonts show Arabic). Grid,
  Column and List views (⌘1/2/3); List has 15 optional columns.
- **Sidebar.** Built-in tags (All, User, System, Activated, Deactivated, Temp Activated,
  Last Import, Earlier Imports, Manual Import, Tagged/Untagged, Quick Collection), imported
  locations, then user tags (nested with `/`). Classification appears as automatic
  **`#style` tags**: serif, sans, script, ornamental, monospaced, symbolic, applied on import
  when "Classify Fonts" is on. ⌥-click any tag shows its inverse ("Not …").
- **Detail tabs** (⌘1–⌘7): Styles as previews, Styles as a metadata list, Characters
  (Unicode grid by category, search, three orderings, copy as character / HTML entity /
  code point / vector shape), Text (book, magazine, article, logo, quote, hierarchy,
  waterfall layouts plus custom layouts with size, line height, tracking, columns, indents),
  Features (OpenType features per script, with input → output examples), Variables (axis
  sliders, named instances, hidden axes, hover to preview, Copy CSS, optical size follows
  font size), Info (names, version, designer, foundry, copyright, licence, embedding rights
  from `fsType`, languages, glyph count, kind, path, notes, tags).
- **Activation.** Three states with coloured dots: persistent (blue), temporary (orange,
  cleared when the app quits by default), off (grey); a partial dot for mixed families; a
  question mark for a missing file. Protected system fonts can't be turned off. Activating a
  font whose PostScript name clashes with an active one offers a swap. Activating a large
  batch asks for confirmation and explains the system cost. Fonts turned off behind its
  back can be restored on launch (ask / always / never).
- **Extras.** Quick Collection (a shortlist that survives stray clicks), Pairing Studio,
  overlay compare, duplicate finder, family editor, auto-activation for Adobe/Quark and
  "other apps" (an XPC service + Apple Events), Font Switch (drag a font onto selected text
  in a design app), PDF specimen export, tag backups (JSON, automatic daily, keeps 10),
  notes, a support-tools recovery window when a modifier is held at launch, an AppleScript
  `activatefonts` command.

## Feature inventory

Priority: **must** (v1 isn't worth shipping without it), **should** (v1 if cheap, else
v1.1), **later**, **skip** (with reason).

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Library of installed fonts | Imports from Font Book source + folders into its own DB; system fonts optional (hideable); dot-prefixed hidden fonts skipped by default | **must** | Read straight from CoreText every launch (`CTFontCollectionCreateFromAvailableFonts` with `kCTFontCollectionIncludeDisabledFontsOption`), so we're always in sync with Font Book. Skip names starting with `.`. Our cache is disposable. |
| 2 | Group by family | One card per family + member count; representative = closest to Regular among filtered faces; ⌥G to show every face | **must** | Same rule. Family = `kCTFontFamilyNameAttribute`. Show "N styles". Toggle in View menu is a *should*. |
| 3 | Live custom preview text | Toolbar "Pr" button / ⌘L opens a text field; presets dropdown; "Remember" saves custom text as a preset | **must** | Always-visible toolbar text field (no popover), ⌘L focuses it. Empty field → each font shows its own family name. Persist last text. |
| 4 | Preview presets | Alphabet upper/lower, numbers, punctuation, accented, currencies, pangrams in several languages, "font names", "Hamburgefonstiv", dynamic (short/medium/long), per-language | should | Menu next to the field: Font name, Pangram, ABC, abc, 0123456789, Punctuation, Accented, Code sample. No saved presets in v1. |
| 5 | Dynamic previews (adapt to font) | Emoji fonts show emoji, non-Latin fonts show their own script, symbol fonts show their symbols | should | If the font can't render ≥ half of the preview text, show a sample from its own character set (first N letters of its main script) in a secondary style. Prevents rows of tofu. |
| 6 | Preview size | Toolbar slider, pinch, ⌘+ / ⌘− | **must** | Slider (8–200 pt) + ⌘+ / ⌘− / ⌘0 (reset). Card height follows size. |
| 7 | Tracking | ⌥ + slider/pinch, ⌥⌘+ / ⌥⌘− | later | Not needed to choose a font. |
| 8 | Auto size (optically equal) | Scales each preview so fonts look equally big | later | Nice for comparing; normalise by x-height or cap height. |
| 9 | Search | ⌘F; matches PostScript/display name; options for family, foundry, designer; prefix/suffix/exact with quotes; `#tag` and `#!tag` tokens | **must** | `.searchable`, ⌘F; matches family, style, PostScript and full name, case- and diacritic-insensitive. No query syntax. |
| 10 | Classification filter | Auto `#style` tags on import (serif, sans, script, ornamental, monospaced, symbolic), derived from CoreText's stylistic class; deleting a style tag turns classification off | **must** | Sidebar section "Categories": Serif, Sans Serif, Monospaced, Script, Display, Symbol, Other. Derivation chain below (see *Classification*). Counts next to each. |
| 11 | Classification override | Edit via tags | should | Context menu "Category ▸" per family; stored as override. Fixes the 23% the heuristics miss. |
| 12 | Weight / width / slant filters | Filter panel: Thin…Black, Narrow/Normal/Wide, Normal/Oblique | later | Cheap from `kCTFontWeightTrait`/`kCTFontWidthTrait`/`kCTFontSlantTrait`, but not needed to ship. |
| 13 | x-height ratio filter | Low/medium/high (x-height vs ascender) | later | |
| 14 | Figures, features, format filters | Tabular/proportional, lining/oldstyle, ligatures, small caps…; CFF/TrueType outlines, AAT/OpenType tables, Type 1, WOFF/WOFF2 | later | |
| 15 | "Variable" / "Color" / "Bitmap" filters | Display filter group | should | Variable is one bit we already compute (`CTFontCopyVariationAxes`). Show as a sidebar item "Variable". |
| 16 | Language / character support filter | 文A menu of languages; "hide fonts missing glyphs of the preview text" (slows startup on big libraries) | should | "Hide fonts that can't show this text" toggle next to the preview field; coverage via `CTFontGetGlyphsForCharacters`, computed in the background, cached per (font, text). Language list later. |
| 17 | Favourites | Not a separate concept; tags do it | **must** | ★ on each card and ⌘D; "Favorites" in the sidebar. Per family *or* face (family by default). Stored by PostScript name in App Support JSON. |
| 18 | Tags | Create (⌘N, + button, drag onto +), nest with `/`, rename, delete, drag fonts onto tags (⌥ to detach), multi-tag panel (⌘T) with fuzzy search, Tab/Return | should | Flat tags (no nesting) in v1 if cheap: sidebar section, context menu "Tags ▸", ⌘T panel with checkboxes. Nested tags later. |
| 19 | Tag logic (OR in sidebar, AND in search, inverse with ⌥) | Multiple sidebar tags = OR; tags in search = AND; ⌥-click inverts | later | Reviewers found this confusing. v1: one sidebar item at a time + search; that's it. |
| 20 | Tag backup / restore | JSON export; automatic daily backup on quit, keeps 10; restore from Settings or support tools | later | Our store is already a readable JSON file. Add Export/Import later. |
| 21 | Shortlist (Quick Collection) | A persistent tray (toolbar button with count, ⌃0); collect with corner button, ⌘-click or Return; survives clicks and relaunch; saved to a tag on launch | should | Merge with compare: a "Compare" tray you add to (⌘K / button on card). If not cheap, compare uses the selection only. |
| 22 | Compare side by side | Pairing Studio layouts; "toggle compare" overlay of two fonts; Setapp page mentions a side-by-side workspace | **must** | Select 2–8 families or faces → Compare (⌘K / toolbar): stacked full-width rows, same text and size, name on each row, remove (×) per row. Overlay later. |
| 23 | Overlay compare | A/B overlay highlighting differences | later | Two fonts drawn on top of each other in two tints. |
| 24 | Pairing Studio | Headline/body templates (logo, article, hierarchy), candidates cycled with arrows, duplicate studios, export PDF | later | Good idea; a v2 feature. |
| 25 | Family detail: styles | Tab 1 previews every style; tab 2 lists styles with metadata | **must** | Inspector/detail with every face as a preview row (same text), sorted by weight then width then italic. Click a face → select it. |
| 26 | Font info | Name, PostScript, family, style, weight, version, designer, foundry, copyright, description, licence, embedding (`fsType`), languages, glyph count, kind/format, location, path, imported date, notes | **must** | Subset: family, style, PostScript name, version, designer/foundry (`kCTFontManufacturerNameKey`/`kCTFontDesignerNameKey`), format, glyph count, file path with Reveal in Finder, active state, variable axes summary. Selectable text. Licence/embedding: should. |
| 27 | Copy names | Info submenu "copy"; copy file path(s) | should | ⌘C copies the family name (⌥⌘C PostScript name). Context menu: Copy Name, Copy PostScript Name, Copy File Path. |
| 28 | Glyph / character browser | Characters tab: Unicode grid by category (letter, numeral, punctuation, symbol, currency, math, private use, extra glyphs), search, order by Unicode / alphabetic / glyph id; copy char, HTML entity, code point, shape (vector) | should | Grid from `CTFontCopyCharacterSet`, category picker, search by char/name, big preview of the hovered/selected char with code point, Copy (⌘C). Unencoded glyphs and vector copy later. |
| 29 | Variable font axes | Sliders per axis, named instances, hidden axes, hover preview, Copy CSS, optical size auto | should | Sliders from `CTFontCopyVariationAxes`, named-instance menu (from `fvar`), live preview. Copy CSS later. |
| 30 | OpenType features | Per-feature toggles grouped (ligatures, figures, small caps, stylistic sets, alternates…), example substitutions; Typography menu forces features in previews | later | `CTFontCopyFeatures`; doable but niche. |
| 31 | Body text / waterfall | Book/magazine/article layouts, waterfall, custom layouts | should (waterfall only) | A waterfall (12…72 pt) in the detail is cheap and was requested by a reviewer. Paragraph layouts later. |
| 32 | Metrics / outlines / smoothing / underline | View toggles: baseline, x-height, cap height, ascender/descender lines; outlined glyphs; font smoothing; underline | later | Metrics overlay is a nice v1.1 detail-view toggle. |
| 33 | Preview colours / night mode / themes | Custom text + background colours, tinted interface, own dark/light/high-contrast themes | skip | Follow system appearance; `.primary` text on window background. Design system forbids custom chrome. |
| 34 | Alignment of previews | Left/center/right/justified | later | |
| 35 | Grid / List / Column views | ⌘1/⌘2/⌘3; List: sortable columns (activation, name, PostScript, style, weight, family, foundry, designer, kind, version, location, file, path, imported, collected), families expand with →/← | should (List) | v1 grid only is acceptable; a List (`Table`) with name/style/category/format/state/path is the second view if cheap. |
| 36 | Sort | Name, imported date, last activated, random… | should | Name (default), Category, Recently added (file date). |
| 37 | Type-to-jump | Typing letters in the grid jumps to the first font starting with them | should | Cheap and very Mac-like. |
| 38 | Keyboard navigation | Arrows scroll rows, ⌥↑/↓ page, ⌘↑/↓ ends, Space toggles details, Return collects, ⌘A/⇧⌘A | **must** | Arrow keys move selection in the grid, Return/Space opens detail, Esc goes back, ⌘A selects all visible. |
| 39 | Activate / deactivate | Click the dot; ⌘; activate, ⇧⌘; deactivate; context menu; whole tag at once; protected system fonts refused with an explanation | **must** | For every non-system font: Activate/Deactivate via `CTFontManagerEnableFontDescriptors` (the same switch Font Book's "Turn Off" uses). Status as SF Symbol + label, not colour alone. Sidebar items "Active" and "Inactive". System fonts show a lock and can't be toggled. |
| 40 | Activation conflict (same PostScript name) | Dialog offering to deactivate the clashing copy first; refuses for protected system copies | **must** (handling) | Detect before enabling; show one sheet: "Another copy of X is active. Turn it off and use this one?" |
| 41 | Bulk activation warning | Confirms when activating many fonts, explains system cost | should | Confirm above 100 faces. |
| 42 | Temporary activation | Session-only activation (orange), cleared on quit by default; ⇧⌘, clears all | later | `CTFontManagerRegisterFontURLs(…, .session, …)`. Only meaningful for fonts outside the system's font folders. |
| 43 | Activate in place from your own folders | Add folders (watched, subfolders browsable), register files where they are, persistently | later | `CTFontManagerRegisterFontURLs(…, .persistent, …)`. Requires a "Locations" model + FSEvents. Big feature; v1.1 candidate. |
| 44 | Install fonts (copy into the user Fonts folder) | Not Typeface's way (it registers in place); it's Font Book's | should | ⌘O "Add Fonts…" and dropping font files: copy into `~/Library/Fonts` (system auto-activates), select them afterwards. Validate with `CTFontManagerCreateFontDescriptorsFromURL` first. |
| 45 | Restore activations changed elsewhere | On launch: ask / always / never | skip | We don't keep our own activation state; the system is the source of truth. |
| 46 | Auto activation (Adobe, Quark, other apps) | XPC service + Apple Events + per-app permission prompts | skip | Needs Automation permissions and per-app integration; out of scope for a browser. |
| 47 | Font Switch (drag font onto text in a design app) | Drag-and-drop with RTF / app scripting | skip | Fragile, per-app; not the job. Dragging a font *file* out (export) is a later nicety. |
| 48 | Google Fonts library | Downloads ~2 GB catalogue, keeps it updated | skip | No network (design system §7). |
| 49 | Adobe Fonts source | Reads the Adobe Fonts client's synced folder | skip | Those fonts are already active via Adobe's client and show up through CoreText anyway. |
| 50 | Apple downloadable fonts | (Font Book shows macOS's on-demand fonts) | later | `CTFontDescriptorMatchFontDescriptorsWithProgressHandler` downloads from Apple: network, so opt-in only. |
| 51 | Duplicate finder | File ▸ Find Duplicates: groups by PostScript name, "Exact" filter, auto-select by format/location, remove from library or Trash | later | Useful clean-up tool; destructive, so careful UI. |
| 52 | Move font files to Trash | ⌘⌫ with confirmation; protected system fonts refused; fonts on external volumes can't be trashed | later | `FileManager.trashItem` + undo. Destructive; not needed to browse. |
| 53 | Remove from library (keep file) | Context "Remove from library" | skip | We have no library separate from the system. |
| 54 | Family editor | Regroup faces into families | skip | Rare; trust font metadata. |
| 55 | Notes per font | Free-text note (4.5) | later | |
| 56 | Recently activated / imported | Sort by last activated; Last Import / Earlier Imports tags | later | "Recently added" sort covers most of it. |
| 57 | PDF specimen / print | ⌘P prints; export PDF specimen of selected fonts | later | `NSPrintOperation` of the compare view is a cheap v1.1. |
| 58 | Export font files | ⇧⌘E; drag out exports files | later | Drag-out of the file URL is cheap; licensing caveat. |
| 59 | Font Book collections | Imported once at first run into tags, then independent | later | Could read `NSFontCollection` names read-only as sidebar items. |
| 60 | Missing font files | "?" indicator; option to auto-remove missing fonts; "file is in iCloud" error | **must** (handling) | Never crash on a font whose file vanished; skip it and refresh. Don't trigger iCloud downloads. |
| 61 | Run in background / menu bar | Keeps a menu bar item after closing the window | skip | Window app; closing the window quits (design system). |
| 62 | Launch at login | Setting | must (standard) | Design system §3 General tab; off by default. |
| 63 | Support tools (recovery) window | Hold a modifier at launch: tag backup, config folder, reset settings, reset database, clear font cache, debug log, issue report | skip | We have no database to repair. (It also confused this study; see header.) |
| 64 | Intro & What's New window | Welcome screen on first launch, replayable from Help | skip | Design system: no onboarding tours. |
| 65 | Licence / Pro / trial | Pro features behind a licence file; trial | skip | Free. |
| 66 | AppleScript | `activatefonts` command | later | App Intents ("Activate font", "Find fonts in category") later. |
| 67 | Customisable menu shortcuts | Via System Settings App Shortcuts | n/a | Free with standard menus. |

### Classification (how we derive the categories)

Typeface's style tags line up with CoreText's stylistic class, which comes from the font's
OS/2 `sFamilyClass`. On this Mac that leaves 23% of faces unclassified, so we use a chain and
keep it in `SpecimenCore` as a pure, tested function `classify(FontFacts) -> Category`:

1. **Monospaced** if `kCTFontTraitMonoSpace`, or PANOSE proportion = 9, or the advances of
   `i`, `m` and `W` are equal (checked only when the font covers basic Latin). Mono wins over
   serif/sans; a coding font is a "mono" to its users.
2. **CoreText class** (`kCTFontSymbolicTrait & kCTFontClassMaskTrait`): 1–5, 7 (old style,
   transitional, modern, Clarendon, slab, freeform) → Serif; 8 → Sans Serif; 9
   (ornamentals) → Display; 10 → Script; 12 → Symbol.
3. **PANOSE** (OS/2 table via `CTFontCopyTable(kCTFontTableOS2)`, bytes 32–41;
   `sFamilyClass` is bytes 30–31): family type 3 → Script, 4 → Display, 5 → Symbol;
   type 2 with serif style 11–15 → Sans Serif, 2–10 → Serif.
4. **Name hints** (family + style, case-insensitive whole words): Mono/Code/Console →
   Monospaced; Sans/Grotesk/Gothic → Sans Serif; Serif/Slab/Antiqua → Serif;
   Script/Hand/Brush/Calligraph → Script; Display/Poster/Stencil/Inline/Shadow → Display;
   Symbol/Dingbat/Ornament/Icons/Emoji → Symbol. "Sans" beats "Serif" in "Sans Serif".
5. **Colour or emoji fonts** (`sbix`/`COLR`/`CBDT` table present) → Symbol.
6. Otherwise **Other**. Fonts with no basic-Latin coverage get a separate sidebar item,
   "Other Scripts", so CJK/Indic/Arabic system fonts don't flood "Other".
7. A user override (feature 11) beats everything.

Family category = the category of its representative (Regular) face. Unit-test with a table of
`FontFacts` fixtures (traits, PANOSE bytes, names) rather than real fonts. A glyph-shape
serif detector (ink width of "I" at the baseline vs mid-stem) is a possible later fallback.

### Performance plan (the key risk)

Thousands of fonts (designers often have 5–20k faces) are where font managers feel slow.
Budgets: launch < 300 ms, first window < 600 ms, footprint < 120 MB idle, typing in the
preview field never drops a frame, scrolling at 60 fps.

- **Two-phase load.** Phase 1 on launch: `CTFontManagerCopyAvailableFontFamilyNames` (15 ms
  here) or the cached index → the grid appears with family names right away. Phase 2 in a
  background task: build the full index (faces incl. disabled, PostScript name, URL,
  enabled, scope, traits, weight/width/slant, class, mono, variable, Latin coverage). URL
  reads are the slow part (≈0.8 ms per face here), so do them off the main actor, in batches,
  and publish progressively.
- **Persistent index cache.** Save the index (Codable, binary plist) in App Support, keyed
  by PostScript name + file path + file modification date. On launch, diff against
  CoreText's face list and only re-read changed entries. The cache is disposable: delete it
  and it rebuilds.
- **Stay in sync** with `kCTFontManagerRegisteredFontsChangedNotification` (local notify
  center), debounced ~300 ms, re-indexing only the difference. No polling.
- **Render only what's visible.** Lazy grid with fixed card heights per size so scrolling
  doesn't measure off-screen cells. Prototype with SwiftUI `LazyVGrid`. If it stutters
  beyond ~2k items, wrap `NSCollectionView` (documented fallback, decide in build).
- **Preview cache.** `NSCache` of `CTFont` keyed by (PostScript name, size), limited to
  ~300 entries (each live CTFont maps its file; unbounded means memory blow-up: creating
  every font here pushed a probe to 215 MB RSS). A second `NSCache` of typeset `CTLine`s keyed
  by (PostScript name, size, text hash), cost = glyph count. Typeset lines off the main
  actor (CTLine creation is thread-safe), draw on main via `Canvas`/`CTLineDraw`, or use
  SwiftUI `Text` with `Font(ctFont)` if measurements show it's fast enough.
- **Preview text edits.** Debounce ~50 ms, re-typeset visible cells only, drop stale work
  (cancel the previous task). 40 visible cells × 0.45 ms ≈ 18 ms: do it in a background task
  and swap in, never block typing.
- **Disabled fonts** can't be matched by name. Create them from their file
  (`CTFontManagerCreateFontDescriptorsFromURL` → `CTFontCreateWithFontDescriptor`) so they
  still preview.
- **Missing-glyph handling.** CoreText silently falls back to other fonts for characters a
  font lacks, which makes previews lie. Check coverage with `CTFontGetGlyphsForCharacters`
  and render missing characters dimmed or as a placeholder. (Typeface bundles the OFL
  "Adobe Blank" font as a cascade fallback so missing glyphs draw blank. That's a valid
  alternative if licensing allows; see open questions.)
- **Coverage filter** ("hide fonts that can't show this text"): compute in the background
  per (face, text), cache, and show a progress hint while it fills.
- **Measure** with `scripts/perf.sh`, plus index-build time per 1k faces (unit test over
  the real system set), scroll smoothness in Instruments, and preview-typing latency. A
  synthetic 10k library can't be made by registering copies (PostScript names must be
  unique), so test the index and classifier at scale with fake `FontFacts` instead.

## Key flows

### Flow 1: find a font for some text (the main job)

Typeface:
1. Open the app. The grid shows one preview per family, each in a sample adapted to the font.
2. Click the "Pr" toolbar button (⌘L), type text (or pick a preset, or "Remember" it).
3. Drag the size slider (or pinch). ⌥ switches it to tracking.
4. Narrow: click a sidebar tag (e.g. a `#style` tag like serif), or type in search, or open
   the filter panel (weight, width, slant, x-height, figures, features, display, languages).
5. Click cards to select, or click the corner button to add to the Quick Collection
   (toolbar shows the count).
6. Double-click (or Space) a card → details: styles, characters, text layouts, features,
   variables, info. Esc goes back.
7. Activate with the card's dot (blue = on) or ⌘;.

Ours (proposal):
1. Open Specimen: window shows the grid immediately (family names, then previews filling in).
2. Type into the toolbar preview field (always visible, ⌘L focuses it). Every card updates.
3. Size slider in the toolbar; ⌘+ / ⌘−.
4. Sidebar: All Fonts, Favorites, Active, Inactive, then Categories (Serif, Sans Serif,
   Monospaced, Script, Display, Symbol, Other, Other Scripts) with counts. ⌘F search narrows
   within the selected sidebar item.
5. Select a card (click/arrows) → inspector or detail shows all styles, info, and (should)
   characters and variable axes. Return/Space opens, Esc closes.
6. ★ (⌘D) to favourite; select several and press Compare (⌘K) to see them stacked.
7. Activate/Deactivate from the card's status control, the Font menu or the context menu.

### Flow 2: first run / onboarding

Typeface: a welcome/intro window explains the app (replayable via Help ▸ Intro & What's
New). Meanwhile it imports everything from Font Book (system + user fonts) and copies Font
Book's collections into tags once; a loading state while it indexes. Trial/licence prompts
for the standalone build (not Setapp).

Ours: no intro. The window opens straight onto All Fonts with the default preview text
(each font's own name, or a short pangram: open question 6). If the index isn't cached,
family names appear first and previews fill in; a small "Indexing fonts…" progress in the
sidebar footer, not a blocking screen. No permissions are needed.

### Flow 3: compare candidates

Typeface: collect fonts into the Quick Collection (corner button, ⌘-click, Return), switch to
it (toolbar button / ⌃0), or open Pairing Studio (⌘K) for template layouts, or toggle the
overlay compare on a font.

Ours: select 2–8 cards (⌘-click/⇧-click/⇧-arrows) → Compare (⌘K, toolbar, context menu) →
full-width stacked rows with the same text and size, each labelled with family and style, a
style picker per row (switch to Bold to compare bolds), × to remove a row, Esc to return.
Should: a persistent compare tray that survives selection changes.

### Flow 4: turn fonts off and on

Typeface: click the dot, or ⌘; / ⇧⌘;, or the context menu, or drag onto the Activated tag
with ⌥. Whole tags can be toggled. Protected system fonts: an alert explains they can't be
turned off. Clashing PostScript name: a "replace?" sheet. Many fonts: confirmation.

Ours: select families or faces → Font ▸ Deactivate (⇧⌘;) / Activate (⌘;), or the card's
status button, or context menu. Families with mixed state show "Partly active". System fonts
show a lock with the tooltip "macOS needs this font". Undo (⌘Z) re-applies the previous
state. Changes made in Font Book appear within a second (notification).

### Flow 5: add fonts (should)

Drop .ttf/.otf/.ttc/.otc/.woff2? files on the window or ⌘O "Add Fonts…" → validate each
(`CTFontManagerCreateFontDescriptorsFromURL`) → copy into `~/Library/Fonts` (skip exact
duplicates; on a name clash ask) → they activate automatically → select and scroll to them.
Invalid files listed in one sheet with the reason.

## Settings inventory

Typeface's Settings (observed values; these may be the owner's choices rather than
defaults where noted):

| Pane | Setting | Value seen | Options | Keep? |
|---|---|---|---|---|
| General | Default action | Click font to select | select / show details / add to Quick Collection | no: click selects, double-click opens (standard) |
| General | Sidebar: swipe to expand/collapse | on | toggle | no |
| General | Sidebar: expand immediately while dragging | off | toggle | no |
| General | Default detail tab | Last detail tab | last / any of the seven tabs | no: remember last tab silently |
| General | Drag and drop | Prefer font export | export files / font switch | no |
| General | Launch at login | off | toggle | **yes** (standard General row) |
| General | Run app in background (menu bar when windows closed) | off | toggle | no |
| General | On launch (Quick Collection) | Save Quick Collection to tag | restore / clear / save as tag | no |
| General | Remember last selected tag | on | toggle | no: always remember sidebar selection |
| General | Theme | System | System / Light / Dark / High contrast light / High contrast dark | no: follow system |
| General | Tint interface from preview colour | on | toggle | no |
| Library | Skip duplicates on import | off | toggle | n/a |
| Library | Import hidden (dot-prefixed) fonts | off | toggle | no: always hidden |
| Library | Classify fonts (`#style` tags) | on | toggle | no: always classify |
| Library | Remove missing fonts | on | toggle | n/a (we always reflect the system) |
| Library | Use English style names (non-English locales) | — | toggle | later |
| Library | Source: Font Book | on | toggle | → "Show system fonts" (see below) |
| Library | Source: Adobe Fonts | off | toggle | no |
| Library | Source: Google Fonts (downloads ~2 GB) | on | toggle | no (network) |
| Activation | Manual activation | Prefer persistent activations | persistent / temporary | later (with temporary activation) |
| Activation | Clear temporary activations on quit | on | toggle | later |
| Activation | Auto activation: Illustrator, InCopy, InDesign, QuarkXPress, Other apps | all off | per-app switches | no |
| Activation | Restore activated fonts | Ask each time | ask / always restore / keep deactivated | no |
| Backup | Backups folder | (path in its container) | path control | no |
| Backup | Automatic tag backups on quit | daily, keep 10 | list of dated backups + Create Backup, Browse…, Restore | later (Export/Import tags) |

Specimen's Settings (proposal, `SlopSettings`, 480 pt grouped form):

| Tab | Setting | Default |
|---|---|---|
| General | Launch at login | off |
| General | Show system fonts | on (Apple's fonts are part of what people choose from; off hides fonts in `/System/Library/Fonts*`) |
| General | Group styles into families | on (also View menu) |
| General | Default preview text | empty (= each font's name) |
| About | `AboutView` | — |

Preview text, size, sort, sidebar selection and window frame persist automatically, with no
setting.

## Menus and shortcuts

Typeface's main menu (static part, observed): **Typeface** (About, License, Settings… ⌘,,
Services, Hide ⌘H, Hide Others ⌥⌘H, Quit ⌘Q). **File** (Import ▸, New Tag… ⌘N, Find
Duplicates, Manage Families, Export ▸, Print… ⌘P, Close ⌘W). **Edit** (standard, plus Select
All ⌘A, Deselect All ⇧⌘A, Find… ⌘F). **Font** (dynamic: Activate ⌘;, Deactivate ⇧⌘;,
Activate Temporarily ⌥⌘;, Clear Temporary ⇧⌘,, Attach Tags ⌘T, Edit Family ⌘E, Pair ⌘K, Move
to Trash ⌘⌫, Export ⇧⌘E). **View** (Library ▸ with ⌃0–⌃4 tag shortcuts and ⌃⌥ inverses,
Go Back, Toggle Sidebar ⌘/, Grid ⌘1, Column ⌘2, List ⌘3, Group by Family ⌥G, Sort by,
Alignment, Auto Size ⌥A, Metrics ⌥M, Font Smoothing ⌥S, Outlined ⌥O, Underline ⌥U, Colors ⇧⌘C,
Night Mode ⌥N, Bigger ⌘+, Smaller ⌘−, Tracking ⌥⌘+ / ⌥⌘−, Next/Previous Tag ⇧⌘↓/↑).
**Typography** (force features in previews: figures, ligatures, alternates, capitals, small
caps, fractions, super/subscript, positional, stylistic sets, character variants, spacing,
vertical, math, script-specific). **Window** (standard + Typeface ⌘0). **Help** (Online Help
⌘?, Intro & What's New, Support & Feedback, Visit Website). In-grid: Space details, Return
collect, ⌘-click collect, letters type-to-jump; detail tabs ⌘1–⌘7; Characters tab ⌥J/⌥F/⌥R.
Several shortcuts use bare ⌥+letter, which clashes with typing accented characters on some
layouts.

Specimen (proposal; every action in a menu, design system §6):

- **Specimen**: About Specimen, Settings… ⌘,, Hide/Quit standard.
- **File**: Add Fonts… ⌘O (should), Show in Finder ⇧⌘R, Close ⌘W, Print… ⌘P (later).
- **Edit**: Undo/Redo, Copy Name ⌘C, Copy PostScript Name ⌥⌘C, Select All ⌘A, Find ⌘F,
  Edit Preview Text ⌘L.
- **View**: as Grid ⌘1, as List ⌘2 (should), Group Styles into Families, Sort By ▸, Bigger
  ⌘+, Smaller ⌘−, Actual Size ⌘0, Hide Fonts That Can't Show This Text (should), Show/Hide
  Sidebar ⌃⌘S, Show/Hide Inspector ⌥⌘I, Enter Full Screen.
- **Font**: Show Details ⌘↓/Return, Compare ⌘K, Add to Favorites / Remove ⌘D, Tags… ⌘T
  (should), Category ▸ (override, should), Activate ⌘;, Deactivate ⇧⌘;.
- **Window / Help**: standard.
- Grid keys: arrows move, Return/Space open detail, Esc back/clear, letters jump (should).

## Permissions and system integration

Typeface: sandboxed with security-scoped bookmarks for added folders; asks for Apple Events
(Automation) permission only when you turn on auto-activation for Adobe/Quark apps
(`NSAppleEventsUsageDescription`: activate and switch fonts), and per-app prompts for
InDesign/InCopy; Trash needs a folder grant inside the sandbox (it asks you to pick the
folder). An `AutoActivation.xpc` service answers font requests. Opens font files as a
document handler. AppleScript dictionary with `activatefonts`. Adobe Type 1 fonts warn that
some apps won't show them.

Specimen needs **no permissions**:

- Reading fonts: CoreText, no entitlement.
- Enable/disable: `CTFontManagerEnableFontDescriptors(descs, enable)` is macOS-only public
  API; it's the switch Font Book's "Turn Off" uses (verify in build that the state persists
  across relaunch and logout and shows in Font Book). No admin needed for fonts in
  `~/Library/Fonts` and fonts we registered. **Verify in build**: whether disabling a font
  in `/Library/Fonts` (computer-wide) works for a standard user without admin. If not, show it
  as locked like system fonts.
- System fonts in `/System/Library/Fonts` (and the Supplemental subfolder) are protected
  (read-only since Catalina) and can't be disabled; detect via path prefix and refuse
  with an explanation.
- Activate in place (later): `CTFontManagerRegisterFontURLs(urls, .persistent, true, handler)`
  persists for the user across logins; `.session` lasts until logout (temporary). Unregister
  with `CTFontManagerUnregisterFontURLs`. `CTFontManagerGetScopeForURL` tells us what we
  registered. No admin needed. Errors arrive per-URL in the handler (e.g. duplicate name).
- Install (should): copy into `~/Library/Fonts`; the system activates it automatically.
- Slopapp bundles are unsandboxed with hardened runtime (`scripts/bundle.sh`), so no
  bookmarks are needed. Fonts the user drops from `~/Documents`/`~/Desktop`/`~/Downloads` may
  trigger macOS's folder-access prompt the first time; that's user-initiated and fine.
- Document types: declare font UTIs (`public.font`, `public.truetype-ttf-font`,
  `public.opentype-font`, collections) as **viewer, alternate rank** so "Open With ▸
  Specimen" works without stealing Font Book's default. (should)
- No login item except the standard Launch at login setting.

## UX patterns worth adopting

- **The preview text is the app.** Text entry is the first thing you do and it reflows every
  card at once. Make that field permanent, focused on launch, and fast.
- **One card per family, chosen sensibly.** Show the face closest to Regular, but if a filter
  is active, show the member that matches it (filter "Bold" → bold faces represent families).
- **Previews that don't lie.** When a font can't render the text, don't silently substitute
  another font: show what's missing, or switch that card to a sample the font *can* show
  (emoji fonts show emoji, Arabic fonts show Arabic).
- **Classify automatically, let people correct it.** Categories appear without setup, and a
  wrong guess is one context-menu fix away.
- **A shortlist that survives stray clicks.** Selection is fragile; a separate "compare
  tray" with a count lets you browse freely and come back.
- **State you can read at a glance**: on / off / partly on / locked / missing file, shown
  with a symbol *and* text for VoiceOver.
- **Explain refusals instead of failing.** "System fonts can't be turned off", "another copy
  with the same name is active: swap?", "activating 2,000 fonts slows apps down: continue?".
- **Type-to-jump** in the grid, like Finder.
- **Size via ⌘+ / ⌘−**, plus a slider for coarse moves.
- **Family detail as one scrolling page** of every style in your text, then the details.
- **Copy the exact name** (family vs PostScript) because that's what you paste into CSS,
  Figma or a terminal config.

## What we won't copy, and what we'll do better

- **Not copying**: the name, the fox icon, the "Pr" button, the dark custom chrome and
  interface tinting, its themes, its Quick Collection naming, Pairing Studio templates, any
  copy or loading messages, paid/Pro/trial flows, the support-tools window.
- **Doing better:**
  - **No separate database to break.** Typeface keeps its own Realm library; its strings
    include "can't read the database" launch failures, and it ships a recovery window with
    "Reset Database". We read the system's font list live and keep only favourites/tags in a
    small JSON file. The cache is disposable.
  - **Always in sync with Font Book.** Typeface copies Font Book's collections once and then
    diverges. We use the same enable/disable switch Font Book uses and listen for changes.
  - **Instant first paint.** Family names on screen in under 600 ms; previews stream in. No
    blocking "loading fonts" screen; the coverage filter never slows startup (Typeface's help
    says it does).
  - **Categories that cover everything.** A visible "Other" and "Other Scripts" bucket instead
    of silent gaps; a reviewer found Typeface's script filter returned loose results. Manual
    override per family.
  - **Simple filtering rules.** Reviewers were confused by OR (sidebar) vs AND (search)
    tag logic. v1: one sidebar item + search, nothing else to learn.
  - **Undo** for favourite, tag, category and activation changes (a reviewer complaint).
  - **Every font previews, everywhere**, including disabled fonts and in List view (a reviewer
    complaint about blank list rows).
  - **Waterfall** in the detail view (a reviewer request).
  - **No bare ⌥+letter shortcuts** that steal accented-character typing.
  - **Native, accessible**: system appearance, accent colour, VoiceOver labels each card with
    family, style count, category and state (not the preview text).
  - **Free, no network, no account, no telemetry.**

## Edge cases

- **Huge libraries**: 5k–20k faces. Index in background, progressive; grid scroll stays smooth;
  footprint stays < 120 MB (bounded CTFont/CTLine caches).
- **Fonts change while running**: installed/removed/disabled in Font Book or by another app
  → update within ~1 s via `kCTFontManagerRegisteredFontsChangedNotification`; a selected
  font that disappears clears the selection, doesn't crash.
- **Missing file / unmounted volume / iCloud placeholder**: skip, mark "File missing", never
  trigger an iCloud download.
- **Corrupt or unsupported file** (when adding): `CTFontManagerCreateFontDescriptorsFromURL`
  returns nil → listed as "Couldn't read X. It may be damaged."
- **Duplicates**: two files with the same PostScript name; only one can be active. Show
  both, mark the inactive one, offer swap on activation.
- **Collections (.ttc/.otc)**: several faces per file. Activation acts on the file; warn
  that deactivating one face deactivates its siblings.
- **Variable fonts**: one file, many named instances. Show as one family with instances as
  styles where CoreText lists them; axes in detail.
- **Protected system fonts**: no toggle, locked state, explanation.
- **Hidden system fonts** (names starting with `.`, e.g. UI fonts): never shown.
- **Disabled fonts**: still preview (load from URL), searchable, and marked Inactive.
- **PostScript Type 1 / bitmap / legacy suitcase fonts**: may not render on modern macOS;
  show the card with "Can't preview this format" rather than blank.
- **Colour / emoji fonts** (sbix, COLR): render correctly; large sizes can be memory-heavy,
  so cap cache cost.
- **Preview text edge cases**: empty (use font names), very long (single line, truncated
  with fade; detail wraps), newlines (first line in grid), RTL (Arabic/Hebrew render
  right-to-left, alignment natural), emoji in text, combining marks, characters the font
  lacks (dim/placeholder, no silent fallback).
- **Fonts with huge ascenders/descenders** (Zapfino-like): don't clip into neighbours; clip
  inside the card with consistent height.
- **Extreme sizes**: 8 pt and 200 pt; grid column count adapts.
- **Activation errors**: `CTFontManagerEnableFontDescriptors` has no error return. Re-read
  `kCTFontEnabledAttribute` afterwards and report fonts whose state didn't change.
- **Bulk actions**: activating/deactivating 1,000 faces: off main thread, progress,
  confirmation above a threshold, one undo step.
- **Dark/light** and **increased contrast**: previews use `.primary` on the window
  background; check both.
- **Non-English UI**: font family names localised (`kCTFontDisplayNameAttribute` vs family
  name): search both the localised and English names.
- **Accessibility**: VoiceOver names each card ("Avenir Next, 12 styles, Sans Serif,
  Active"); Reduce Motion: no animated reflow; full keyboard use.
- **Multiple displays / full screen**: standard window behaviour; frame persists.
- **Sleep/wake, quit mid-index**: index task cancellable; partial cache never used as complete
  (write atomically).

## Our v1 scope

Archetype: **browser/library window** (`NavigationSplitView`: sidebar, grid, detail).

- [x] Window opens < 600 ms on a cold cache with family names visible; full index builds in
      the background with a small progress indicator; later launches use the on-disk index
      and diff against CoreText.
- [x] Library = every installed font from CoreText, including disabled ones, hidden
      dot-fonts excluded, grouped by family with a style count (representative face nearest
      Regular). "Show system fonts" setting (default on).
- [x] Toolbar preview text field (⌘L) re-sets every visible card live while typing (no
      dropped frames); empty = each font's own name; text persists across launches.
      Characters a font lacks are visibly missing, not substituted.
- [x] Size slider + ⌘+ / ⌘− / ⌘0; cards resize; size persists.
- [x] ⌘F search over family, style, PostScript and display names, within the selected
      sidebar item.
- [x] Sidebar: All Fonts, Favorites, Active, Inactive, Categories (Serif, Sans Serif,
      Monospaced, Script, Display, Symbol, Other, Other Scripts) with counts; classification via
      the tested chain (CoreText class → PANOSE → names → colour tables → Other).
- [x] Favourites: ★ on card, ⌘D, context menu; persisted in App Support JSON; ⌘Z undoes.
- [x] Detail for a family: every style previewed in the current text, plus info (family,
      style, PostScript name, version, designer/foundry, format, glyph count, path with Show
      in Finder ⇧⌘R, state, variable axes listed). Return/Space/double-click opens, Esc
      returns.
- [x] Compare: 2–8 selected families/faces stacked with the same text and size, per-row
      style picker and remove; ⌘K.
- [x] Activate/Deactivate non-system fonts (⌘; / ⇧⌘;, card control, context menu) via
      `CTFontManagerEnableFontDescriptors`; the real effect is verified (state visible in Font
      Book and in TextEdit's font panel); system fonts locked with an explanation; PostScript
      name clashes handled with a swap sheet; one undo step per action.
- [x] Stays in sync with Font Book changes while running (notification, no polling).
- [x] Keyboard: arrows move selection in the grid, ⇧/⌘ extend, ⌘A, Return/Space, Esc;
      Copy Name ⌘C; every action is in a menu with its shortcut.
- [x] Empty states (`ContentUnavailableView`): no search results ("No fonts match '…'" +
      Clear Search), empty Favorites (how to add one), empty category.
- [ ] Within budgets: launch < 300 ms, first window < 600 ms, idle CPU < 0.2%, footprint
      < 120 MB with the full system library browsed top to bottom at 200 pt and 12 pt. **Partly:** launch, first window, idle CPU and idle footprint pass; after browsing everything at four sizes the footprint settles at ~142 MB (CoreText's own font cache; see build notes).
- [x] VoiceOver names every card and control; light/dark; Reduce Motion.
- [x] No network traffic.

**Should (v1 if cheap, else 1.1), in this order:** preview presets menu; type-to-jump;
dynamic samples for fonts that can't show the text; "hide fonts that can't show this text";
character/glyph browser with copy; variable-axis sliders with named instances; waterfall;
category override; flat tags (⌘T panel); compare tray; Add Fonts… (copy to
`~/Library/Fonts`, ⌘O and drop); List view; sort options; "Variable" sidebar item; bulk
activation confirmation; Open With document types.

**Later:** activate in place from watched folders (`.persistent`) and temporary activation
(`.session`); weight/width/feature filters; OpenType features panel; metrics overlay;
overlay compare; pairing layouts; duplicates finder; Move to Trash; PDF/print specimens; tag
export/import and nested tags; notes; Apple downloadable fonts (opt-in network); App Intents.

## Open questions

1. **Activation scope for v1.** Proposal: v1 toggles fonts that are already installed
   (Font Book's model) and refuses system fonts. "Add Fonts…" (copy into `~/Library/Fonts`)
   is a *should*. Activating fonts in place from the owner's own font folders (Typeface's
   model, the big reason pros use it) is v1.1. OK, or is in-place activation a must for the
   owner?
2. **Tags in v1?** The roadmap says "favourites and tags". Proposal: favourites are a
   must, flat tags a *should*. Nested tags and AND/OR logic later.
3. **Compare shape.** Proposal: stacked rows from the selection in v1, a persistent compare
   tray if cheap; overlay and pairing layouts later.
4. **Missing glyphs.** Either draw uncovered characters dimmed via our own coverage check
   (no extra files), or bundle the SIL OFL "Adobe Blank" font as a cascade fallback (simpler
   rendering, needs the OFL licence text in the bundle). Proposal: coverage check, no bundled
   font.
5. **System fonts shown by default?** Typeface shows them (hideable). Proposal: shown,
   with a General setting to hide. They're a large part of what people choose from.
6. **Default preview text.** Each font's own name (most informative in a mixed grid) or a
   short pangram? Proposal: font name when the field is empty, placeholder suggests typing.
7. **`/Library/Fonts` fonts.** If disabling computer-wide fonts needs admin for a standard
   user, treat them as locked like system fonts (proposal), or prompt for admin (no)?
8. **Test fixture font.** Activation tests need a real font file that isn't installed.
   Proposal: commit one small SIL OFL font (with its licence) under the app's test
   resources, registered at `.process` scope in unit tests and with `.session` only in the
   scripted walkthrough, cleaned up after.
9. **Destructive actions** (Move to Trash, duplicates clean-up): kept out of v1. Agree?

## Sources

- Typeface website: <https://typefaceapp.com>
- Help index: <https://typefaceapp.com/help/articles>
- Getting started: <https://typefaceapp.com/help/articles/getting-started>
- Setting up your library: <https://typefaceapp.com/help/articles/font-library>
- Activation: <https://typefaceapp.com/help/articles/activation>
- Keyboard: <https://typefaceapp.com/help/articles/keyboard>
- Searching & filtering: <https://typefaceapp.com/help/articles/search>
- Tagging: <https://typefaceapp.com/help/articles/tags>
- Quick Collection: <https://typefaceapp.com/help/articles/quick-collection>
- List view: <https://typefaceapp.com/help/articles/list-view>
- Appearance: <https://typefaceapp.com/help/articles/appearance>
- Duplicate fonts: <https://typefaceapp.com/help/articles/finding-and-removing-duplicate-fonts>
- Pairing fonts: <https://typefaceapp.com/help/articles/pairing-fonts>
- Auto activation: <https://typefaceapp.com/help/articles/auto-activation>
- Font Switch: <https://typefaceapp.com/help/articles/font-switch>
- Tips (group by family, type to scroll, filter by language):
  <https://typefaceapp.com/help/tips/group-fonts-by-family>,
  <https://typefaceapp.com/help/tips/type-to-scroll>,
  <https://typefaceapp.com/help/tips/filter-fonts-by-language>
- Troubleshooting activation: <https://typefaceapp.com/help/troubleshooting/activation-issues>
- Mac App Store listing, version history and reviews: <https://apps.apple.com/us/app/typeface-2/id1062679359>
- Setapp listing and reviews: <https://setapp.com/apps/typeface>
- TheSweetBits review: <https://thesweetbits.com/tools/typeface-review>
- TypeDrawers font manager thread: <https://typedrawers.com/discussion/comment/59435>
- Font Book with large libraries (forums): <https://forums.appleinsider.com/discussion/33877>,
  <https://spy.macrumors.com/threads/fontbook-does-it-really-suck.67741>
- Apple CoreText headers (macOS SDK): `CTFontManager.h` (scopes, register/unregister,
  `CTFontManagerEnableFontDescriptors`, `CTFontManagerGetScopeForURL`), `CTFontCollection.h`
  (`kCTFontCollectionIncludeDisabledFontsOption`), `CTFontDescriptor.h`
  (`kCTFontEnabledAttribute`, `kCTFontRegistrationScopeAttribute`), `CTFontTraits.h`
  (stylistic classes, `kCTFontTraitMonoSpace`).
- OpenType OS/2 table spec (sFamilyClass, PANOSE): <https://learn.microsoft.com/typography/opentype/spec/os2>

## Owner decisions (2026-11-03)

The owner's defaults for the open questions above, as built:

1. **Activation scope:** activating fonts in place from the owner's own folders is v1.1.
   v1 turns on/off fonts Specimen can manage safely: the user's Fonts folder and fonts
   registered from elsewhere. Tested only with the OFL fixture registered at session scope
   from `/tmp/specimen-test`; no font installed before the build was ever changed.
2. **Favourites only** in v1; tags are v1.1.
3. **Stacked compare only** (no overlay, no pairing layouts, no tray).
4. **Own coverage check**, no bundled fallback font: missing characters are drawn faint in
   the system font and counted on the card.
5. **Apple's fonts shown by default**, hideable (View ▸ Show macOS Fonts, Settings ▸ General).
6. **Empty preview field shows each family's own name.**
7. **Fonts needing an administrator are locked.** `/Library/Fonts` (all users) is locked
   with an explanation pointing to Font Book. Whether a standard user *could* turn those off
   without admin was not verified: testing it would mean changing an installed font. v1.1:
   verify on a test machine.
8. **Test font committed:** Silkscreen Regular + Bold (SIL OFL 1.1) with `OFL.txt` in
   `apps/Specimen/Tests/Fixtures`.
9. **Move to Trash and the duplicate finder are out of v1.**

## Build notes (2026-11-03)

**Shape.** Library window: `NavigationSplitView` sidebar (Library + Categories with counts),
a permanent preview bar (text field, presets menu, size slider) above the content, and the
content area switching between the font grid, a family page and compare. The grid is an
`NSCollectionView` wrapped for SwiftUI with a closed-form grid layout (layout cost depends
on what's visible, not on library size) and cards drawn with CoreText (`CTLine`, cached
fonts and lines in bounded `NSCache`s). Core logic in `SpecimenCore`: classifier chain,
grouping/representative, filtering and counts, activation planner, index + disposable
cache, stores, preview-text rules. CoreText sits behind `FontSystem` (fake in tests).

**What I learned from CoreText on this Mac (macOS 27.2) and changed because of it:**

- `kCTFontRegistrationScopeAttribute` was the slow part of indexing (535 ms for 666 faces),
  and `kCTFontFormatAttribute` costs **~40 MB** because it opens every font file. Neither is
  read while indexing: location comes from the path, the format from the extension (the
  exact format is read for one face in the Info section).
- `kCTFontEnabledAttribute` goes stale for faces turned off while running, and the
  include-disabled collection can list a face twice. "Enabled" = present in the
  enabled-only collection.
- **`CTFontManagerEnableFontDescriptors` acts on the PostScript name, not the file:**
  turning off one of two copies turned off both. So Specimen refuses to turn off a face
  when another copy with the same name is protected (new lock reason "Shares a name with a
  protected font"); otherwise turning off a user's copy of a system font could hit Apple's.
  The swap sheet stays for the case where one copy is on and another off, which same-scope
  copies can't produce.
- Turning off a session-registered font drops its registration, so a plain unregister then
  fails and leaves it behind as "off". Clean-up (Specimen on quit, `specimen-fixture clean`)
  turns faces back on first, then unregisters. Verified: after quitting with the fixture
  turned off, nothing is left registered.
- `CTFontCopyAvailableTables` returns raw tag values, not objects (bridging it crashed).
- `kCTFontManagerRegisteredFontsChangedNotification` arrives for changes made by other
  processes once CoreText has been used; debounced 300 ms, the app reflects them within ~1 s.

**Test mode** (`SPECIMEN_TEST_FONTS=/tmp/specimen-test`): Specimen registers the font files
there for the session at launch, restricts on/off to them (everything else shows "Locked in
test mode"), and cleans up on quit. `SPECIMEN_DATA_DIR` moves favourites, categories and the
index cache. `specimen-fixture install|status|clean` manages the fixture.

### Gates (2026-11-03, release build, machine load 5–8 from other agents)

- `scripts/check.sh Specimen --perf`: **47 tests** (7 suites) pass, bundle + smoke pass.
  Perf: launch 133–155 ms, first window 362–389 ms, idle CPU (lowest window) 0.08–0.14%,
  footprint 93.3–93.8 MB. One run of the full gate measured 228.5 MB; not reproduced in four
  later measurements (85.7–93.3 MB), probably input from another agent reaching the app
  (perf.sh brings it to the front) or overlapping launches. Watch for it.
- `scripts/drive tree`: no `[unlabeled]` controls (grid, detail, compare, Settings).
- **Performance with all installed fonts** (666 faces / 188 families, 1120×740 window,
  `SPECIMEN_BENCH`, cold caches each pass, 60 pt per step = a brisk flick): main-thread time
  per step p50 / p95 / max: **12 pt** 8.3 / 11.7 / 30 ms (1 step of 72 over 16 ms), **36 pt**
  4.4 / 5.6 / 36 ms (1/167), **72 pt** 2.4 / 4.2 / 20 ms (1/507), **200 pt** 1.3 / 2.9 / 8 ms (0/1087).
  **Typing** (43 keystrokes, every visible card re-set): CPU per keystroke 1–2 ms SwiftUI
  + 2.3–3.2 ms drawing cards (max 6.9 ms); keystroke → last card on screen p50 16–18 ms,
  i.e. the next display refresh. **10× library** (`SPECIMEN_STRESS=10`, 6,660 faces / 1,878
  families): scroll p95 9.2 / 7.2 / 5.0 / 3.5 ms at 12/36/72/200 pt, typing 0 keystrokes
  over 16 ms; idle footprint 93 MB, idle CPU ~0.02%. 10k fake faces index + group + filter:
  0.16 s; a search over 2,000 families 25 ms.
- **Memory after browsing everything:** idle after launch ~86 MB; after paging through the
  whole library at 12, 36, 72 and 200 pt it settles at ~141–143 MB. Smaller render caches
  didn't change it: it's CoreText's own cache of every font it has parsed (the same as the
  first-ever launch, ~122 MB, which reads every font once). This misses the scope line
  "< 120 MB after browsing top to bottom"; the idle budget passes.
- Biggest fix from profiling: the state symbol on each card was created and rasterized on
  every draw (~half the card draw time); now made once per appearance.
- **Walkthrough** (release build, keyboard via `scripts/drive`, launched with `open -g` so it
  never took focus from other agents): preview text live in every card; faint missing
  characters ("Año €5" in Apple SD Gothic Neo); own-script samples for Arabic, Braille and
  emoji fonts; ⌘F search + empty state + Clear Search; ⌘L, Return/↓ into the grid; arrows,
  ⇧-extend, type-to-jump; ⌘D favourite (written to `favorites.json`, Favorites count 1);
  Return → family page (styles, waterfall, info), Esc back; ⇧→ ×2 + ⌘K → compare with style
  picker and remove; ⇧⌘; on the fixture → **really off system-wide** (checked from another
  process), ⌘Z → back on; locked font → explanation alert; an external change from another
  process reflected in ~1 s; ⌘+/⌘−/⌘0; View ▸ Group Styles off; Settings (Show macOS fonts
  hides Apple's fonts: 9 families left); light and dark. Screenshots in `/tmp/specimen-shots`.
- **Bugs found and fixed in the walkthrough:** the preview controls collapsed into the
  toolbar overflow when search expanded (moved to a permanent preview bar); missing-glyph
  runs made the rest of the line faint (explicit colour on every run); "Typewriter" name hint
  made American Typewriter "Monospaced"; undo used SwiftUI's environment undo manager
  (Edit ▸ Undo stayed disabled) and redo was lost (now registered on the window's undo
  manager, synchronously); empty state floated the preview bar mid-window; duplicate faces
  were indistinguishable (folder name shown); Esc on the family page needed focus (Back is
  now the cancel action).
- Not verified live: ⌘C to the real clipboard (not done to avoid overwriting the owner's
  clipboard; it's the standard `copy:` action), right-click context menu (needs the mouse;
  every item is also in the Font/Edit menus), Show in Finder (would bring Finder forward),
  the bulk-activation confirmation (> 100 faces; only 2 test faces exist, covered by unit
  tests), and Redo after Undo (needs the app frontmost; the code now registers the redo
  step inside the undo, the standard pattern).

### Design checklist (§10)

1 pass (type and see, no setup) · 2 pass (system controls, accent selection, semantic
colours; the only non-system fonts are the previews themselves) · 3 pass (every action in
File/Edit/View/Font with shortcuts) · 4 pass (Esc back/clears, ⌘, ⌘Q) · 5 pass (General with
Launch at login + Show macOS fonts + Group styles; About) · 6 pass · 7 pass (search,
Favorites, empty category) · 8 n/a (no permissions) · 9 pass (on/off, favourites and
categories undoable; nothing deleted) · 10 pass (no sockets, no networking code) · 11 pass
idle; see the memory note above · 12 pass · 13 pass (only 150 ms fades, none with Reduce
Motion) · 14 pass (SwiftUI window frame; preview text, size, sidebar, filters persist).

### Shoulds built / deferred

Built: preview presets menu, type-to-jump, dynamic samples for fonts that can't show the
text, waterfall, category override (Font ▸ Category, undoable), Variable sidebar item, bulk
activation confirmation (> 100), ungrouped (per-style) view.
Deferred to v1.1 (cost vs. v1 value): "hide fonts that can't show this text", character
browser, variable-axis sliders, flat tags (owner decision 2), compare tray, Add Fonts (copy
to `~/Library/Fonts`, drop), List view, sort options, Open With document types, and
in-place activation from the owner's folders (owner decision 1).

## Parity pass (2026-11-03)

Owner's direction (`docs/parity-pass.md`): look and work much more like Typeface, and don't be
missing features. **The screen was locked for this whole pass**, so `scripts/drive`
walkthroughs, `drive tree` and window screenshots weren't possible. UI was checked with a new
offscreen render hook (`SPECIMEN_SNAPSHOT_DIR`: Specimen draws its *own* window and sheets
to PNGs in light and dark, then quits), unit tests and test hooks. Typeface's look was
studied from the official screenshots on typefaceapp.com (grid, list, sidebar, characters,
variables, body text; downloaded to `/tmp/specimen-parity/`, not committed) and its help
pages (Quick Collection, list view, tags). Typeface itself was not launched (it opened its
recovery screen last time); none of the owner's tags or collections were looked at.

### Gap table

| Typeface feature / design item | Before | Now | Notes |
|---|---|---|---|
| Card: small status dot + small grey name top-left, member count top-right, big centred preview, airy white tile | headline name, "N styles · category", state icon, star, left-aligned preview | **done** | Filled accent dot = on, hollow = off, half = mixed, small lock = protected. Name in subheadline secondary; count top-right; preview centred; tiles in `controlBackgroundColor` with a hairline. Category moved to VoiceOver/Info only, like the original. |
| Grid density (~3 columns at 30–36 pt) | 2 columns | **done** | Column minimum 6.5 × size (≥ 210 pt). |
| Quick Collection: corner collect button, Return collects, toolbar button with count, survives browsing and relaunch, clear | compare used the selection only (2–8) | **done** as the **compare tray** | ⊕ in each card's bottom-right corner (on hover, stays when collected), Return / Enter in grid and list, toolbar button with count (click toggles the tray view; right-click Clear), ⌥⌘K clears, persisted in UserDefaults, undoable. The tray view is the stacked compare (style picker, drag to reorder, details, remove). No 8-font cap. |
| Space opens details, Return collects | Return/Space both opened | **done** (matches the original) | Space toggles the family page (also closes it); Return collects. Double-click and ⌘↓ still open. |
| Tags: + button / ⌘N, drag fonts onto a tag, multi-tag panel ⌘T with type-to-filter, Return/Tab, rename, delete | none (v1.1) | **done** (flat) | Sidebar "Tags" section with counts and +; ⌘T panel (filter, ↑/↓, Return toggles or creates, Tab toggles, mixed state for partial selections); ⌘N with "added to the selected fonts"; drag cards onto a tag; right-click Rename / Delete / New Smart Collection with This Tag; Font ▸ Tags submenu and grid/list context menus; undo. Stored in `collections.json`. |
| Library tags: All, User, System, Activated, … | All, Favorites, Active, Inactive, Variable | **done** | Added **Your Fonts** and **macOS Fonts**. |
| Collections / smart tags | none | **done** as **Smart Collections** | Rules: name contains, category, state, location, tag, variable only, favourites only, minimum styles; live match count; ⌥⌘N starts from the current sidebar item + search; edit/delete from the sidebar. |
| Characters tab: Unicode grid by group, search, copy | none | **done** | Groups (letters, numbers, punctuation, symbols, currency, marks, other), search by character, Unicode name or `U+XXXX`, inspector with big glyph, name, code point, HTML entity, Copy buttons, ⌘C. Built off the main thread from `CTFontCopyCharacterSet` (planes with members only, capped at 70k). |
| Variables tab: slider per axis, sample glyphs along each axis, named instances, Copy CSS | axes listed in Info | **done** | Five sample letters across each axis (click one to jump), slider with min/max, instance picker (faces in the same file), Reset, Copy CSS. Preview at the preview size follows the sliders. |
| Text tab (body text layouts, waterfall) | waterfall on the one-page detail | **done** (one layout) | Heading + paragraph at a chosen body size (our own sample text) and a 9–96 pt waterfall. Book/magazine/custom layouts deferred. |
| Detail as tabs (⌘1–⌘7) | one scrolling page | **done** | Segmented tabs Styles · Characters · Text · Variables (variable fonts only) · Info, ⌘1–⌘5 while the page is open; a style picker in the header shared by every tab; header holds favourite, tags, compare and activate. |
| Info tab incl. tags and a list of every style | info only | **done** | Adds weight, licence, tags with Edit Tags…, and an "All Styles" table (Typeface's second Styles tab). |
| List view (⌘3 in Typeface) with family rows, disclosure, sortable columns, preview of the selection on top | none | **done** | `Table` with state, name (★ / in-compare marks), styles, weight range, category, format, version, foundry, location, date added; disclosure for styles; column headers sort; preview pane above. ⌘1 Grid / ⌘2 List (we have two views, not three). Foundry and version are now indexed (cache v4). Column hide/reorder: deferred. |
| Sort options | name only | **done** | Name, Date Added, Number of Styles, Category, Foundry; same key again reverses; View ▸ Sort By, toolbar menu, list headers; persisted. |
| Hide fonts that can't show the text | none | **done** | Eye toggle in the preview bar and View menu (⇧⌘H). Background check of every face (~60 ms for 666 faces after a 150 ms typing debounce), empty state with "Show All Fonts Anyway". Counts ignore it, like search. |
| Add Fonts… / drop font files | none | **done** | ⌘O open panel (files or folders) and drop on the window: validates with CoreText, copies into `~/Library/Fonts`, skips exact copies and installed PostScript names, selects the new fonts, sheet lists what was skipped. **Test mode** copies into `<test folder>/Added` and registers for the session only. The real `~/Library/Fonts` path was not exercised (it would install a font on the owner's Mac). |
| Toolbar: sidebar toggle, collect, "Pr", view switch, size slider, search | sidebar, back, compare, search; preview bar | **partly** | View switch, sort menu and compare-tray count added to the toolbar. Preview text + size stay in a permanent bar under the toolbar (kept from v1: in the toolbar they collapsed into overflow when search expanded). |
| Activate from watched folders (Typeface's library model) | — | **deferred** (v1.1) | ~1.5 days: locations model, security of `.persistent` registration, FSEvents watching, sidebar "Locations" with subfolders, rescan, and a safe test story. |
| Temporary activation (orange) | — | deferred | ~0.5 day once locations exist (`.session` scope + clear on quit). |
| Nested tags (`a/b`), OR/AND/inverse tag logic, tag export/backup | — | deferred | ~0.5 day nesting; ~0.5 day JSON export/import. Reviewers found the OR/AND logic confusing. |
| OpenType features tab + Typography menu | — | deferred | ~1 day (`CTFontCopyFeatures`, examples per feature). |
| Overlay compare, Pairing Studio | — | deferred | ~1 day overlay; pairing layouts ~2 days. |
| Tracking, auto size, alignment, metrics/outline overlays | — | deferred | ~0.5 day each; not needed to choose a font. |
| Weight/width/x-height/feature/language filters | — | deferred | ~1 day for a filter popover. |
| List column show/hide/reorder | — | deferred | ~2 h (`TableColumnCustomization`). |
| Duplicate finder, Move to Trash | — | skipped (owner decision 9) | Destructive. |
| Google/Adobe sources, auto-activation, Font Switch | — | skipped | Network / per-app automation (see inventory). |
| PDF specimen / print | — | deferred | ~0.5 day. |

### Deviations from the design system (and why)

- **Return collects into the compare tray** instead of opening (Finder convention): it's the
  original's keyboard model and the fastest shortlist flow. Space/⌘↓/double-click open.
- **Hover-revealed card buttons** (star, ⊕): the original's corner collect button. They're
  never hidden from VoiceOver (alpha 0, still in the tree) and stay visible when they carry
  state; every action is also in the menus.
- **State shown as a small accent dot** (filled/hollow/half/lock): shape differs per state
  and VoiceOver reads it, so colour isn't the only signal.
- Cards are drawn tiles (`controlBackgroundColor` + separator) rather than plain list
  rows, as before; only system colours.

### New shared-looking pieces (candidates for SlopKit later)

`MixedCheckboxStyle` (three-state checkbox, `Sheets.swift`) and the offscreen window
snapshot hook (`Snapshots.swift`; same idea as Convert's and Zones').

### Gates (2026-11-03, parity pass)

- `scripts/check.sh Specimen --perf`: **72 tests** (14 suites) pass; bundle, smoke pass. Perf
  (final run, load 3.0): launch 133 ms, first window 433 ms, idle CPU 0.056 %, footprint
  95.6 MB (an earlier run at load 5.4: 131 / 441 ms / 0.067 % / 96.0 MB). All within budget.
- **Scroll/typing bench** (release, real fonts, 1120×740, `SPECIMEN_BENCH`): scroll p50/p95/max
  12 pt 8.2/15/21 ms (3 of 54 steps over 16 ms; 4 columns now vs 3), 36 pt 4.6/6.5/8.8 ms,
  72 pt 2.8/5.4/7.1 ms, 200 pt 3.1/6.4/11 ms. Typing at 36 pt: card draw CPU 2.4 ms per
  keystroke (max 2.6), keystroke → all 18 visible cards drawn p50 17 ms (the next refresh).
  Footprint after paging the whole library at four sizes: 194–216 MB; the unchanged v1 build
  measured 201 MB in the same session (locked screen), so not a regression from this pass.
- **Coverage filter:** 199–256 ms from toggle to result for 668 faces (150 ms of it is the
  typing debounce).
- **Offscreen renders** (release bundle, test mode, light + dark), looked at:
  `/tmp/specimen-parity/shots/` — `grid`, `grid-tag`, `grid-coverage`, `list`,
  `detail-styles`, `detail-characters`, `detail-text`, `detail-variables` (Skia),
  `detail-info`, `compare`, `sheet-tags`, `sheet-smart`, `sheet-install`, each
  `-light.png` / `-dark.png`. Add Fonts success path: `/tmp/specimen-parity/shots-add/`
  (`SPECIMEN_SNAPSHOT_ADD` copied Silkscreen into the test folder's `Added/`, registered it
  for the session, selected it; cleaned up on quit — `specimen-fixture status` showed it
  unregistered afterwards).
- Fixed from the renders: two columns → three; Smart Collection sheet clipped its toggles;
  narrow axes (Skia 0.5–3.2) showed "1" (now two decimals); list "State" header truncated;
  the snapshot run hung on quit while a sheet was closing (left the test font registered
  until `specimen-fixture clean`).
- **Owed on-screen checks** (need an unlocked screen): `scripts/drive tree` for
  `[unlabeled]` controls in the grid, list, every detail tab, compare and the four sheets;
  hover reveal of the card star/⊕ and clicking them; Return/Space in the grid **and in the
  list** (Table may eat Return before `.onKeyPress`); drag a card onto a sidebar tag; drag to
  reorder in compare; ⌘1/⌘2 vs ⌘1–⌘5 menu switching; ⌘T panel keyboard (↑/↓/Tab/Return);
  ⌘C in the Characters tab; the open panel (⌘O) and dropping files on the window; Space not
  closing the page while typing in a field; list context menu acting on the right-clicked
  rows.

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.

## Polish pass (2026-11-05)

Brief: `docs/polish-pass.md` (detail rules, §10 items 15–26). Release build, test mode
(`SPECIMEN_DATA_DIR` scratch folders under `/tmp/specimen-test/`, `SPECIMEN_TEST_FONTS=/tmp/specimen-test`),
`SLOP_APPEARANCE=light|dark`. The owner's `app.slopapp.specimen` defaults were exported first and
re-imported at the end (verified identical); no tags, collections or fonts of theirs were
touched, nothing was activated or installed. No real-mouse actions, no global keys, no
clipboard writes (Copy buttons were not pressed). Surfaces were shot two ways: real windows
with `scripts/drive shot` (chrome, materials, sidebar) and the app's offscreen
`SPECIMEN_SNAPSHOT_DIR` walk (every tab and sheet, light + dark).

### Defects found and fixed (before → after, measured with `scripts/measure`)

| # | Surface | Before | After |
|---|---|---|---|
| 1 | Lint | 4 corner-radius literals (style row 8 ×2, glyph cell 3, inspector 8) + 1 spacing literal (toolbar `HStack(spacing: 4)`), and a hidden `xRadius: 8` on the card | `Radius.m` / `Radius.s` / `Spacing.xs` everywhere; `scripts/lint.sh Specimen` clean |
| 2 | Grid: preview baselines | Baseline = each font's own ascent (clamped): baselines in one row differed by up to **7 pt** (Apple SD Gothic Neo 521 vs Apple Symbols 514 pt), 1.5 pt in calmer rows | One baseline per size for every font (`PreviewMetrics.baseline`: 4 + 0.95 em), shared by cards, style rows, Compare, list preview and axis samples: **0 pt** spread (AppleMyungjo / Arial / Arial Black all 656.5 pt); the remaining 1.5 pt in the Apple SD Gothic Neo row is that font's own Latin design |
| 3 | Grid: card border | 1.0 pt stroke, inset 1 pt (13 pt visible gap between 12 pt-spaced cards) | One device pixel (0.5 pt) inside the bounds, `Radius.m`; gap 12 pt |
| 4 | Grid: card insets | Status mark 10 pt from the edge, caption and preview 12, count 10 from the right; name and count on different baselines (drawn at y 5 and 7) | Everything on a 12 pt (`Spacing.m`) inset; header items (mark, name caps, count, star) centred 13 pt from the top, footer items (caption, ⊕) 13 pt from the bottom; name and count share one baseline; ⊕ and star glyph edges on the inset line |
| 5 | Grid: contrast | Count, "Sample"/"n characters missing" caption, hollow/lock state marks and "Can't preview" in `tertiaryLabelColor`: count measured **1.66:1** on the card | `secondaryLabelColor`: **3.06:1** on thin anti-aliased digits in light (system floor, accepted), **6.29:1** in dark |
| 6 | Grid: hover | Only the buttons faded in; the name re-truncated (moved) when the star appeared | Hover adds a faint `quaternarySystemFill` tint; the star's slot is always reserved, so the name never moves (seen live with the pointer resting on a card) |
| 7 | Toolbar | Back hidden with opacity 0: on macOS 26+ its **empty glass bubble** still showed next to the title on the grid | Always present, disabled on the grid (like Finder); title never shifts |
| 8 | Hairlines | 1 pt `Divider` under the preview bar, in the bar, under the detail header, Characters bar + inspector rule, Variables rows, Compare header, list preview | `Hairline()` / `Hairline(axis: .vertical)` (0.5 pt) |
| 9 | Styles tab | Style rows' content at 28 pt, family name above at 20 pt; selection ring 1.5 pt | Rows hang their 8 pt padding into the margin: names and previews at **20 pt**, aligned with the header; ring 2 pt like the cards |
| 10 | Characters grid | Cells `controlBackgroundColor`, invisible on the pane in **both** modes; fixed 56 pt cells centred with leftover margins; selected cell's square fill poked out of a 3 pt rounded stroke; glyphs placed by their line box | Square cells that stretch to fill the row exactly at the 20 pt margins (left edge 20, right edge on the count text above), 4 pt gaps, `Radius.s` tiles in `.fill.quaternary`; selection a solid accent tile with white glyph; glyphs drawn by `GlyphView`: ink centred left–right, cap height centred on a baseline shared by every cell (so "," still sits low and "'" high) |
| 11 | Character inspector | Big-glyph tile `controlBackgroundColor`: invisible in light and dark; ragged Copy buttons | Visible square `.fill.quaternary` tile with hairline guides for baseline, x-height and cap height; three full-width Copy buttons; empty-group state ("No currency in this style") instead of "No results for ''" |
| 12 | Text tab waterfall | Size numbers vertically centred: **2 pt** above the sample's baseline at 18 pt, more at larger sizes | Baseline-aligned (`alignmentGuide`): **0 pt** |
| 13 | Variables tab | Axis tag in `.tertiary`; Copy CSS → Copied changed the button width and moved Reset | `.secondary`; both labels share one fixed slot |
| 14 | Compare | Rows at 28 pt under a 20 pt header; right buttons 31 pt from the edge; separators from 28 pt to the window edge | Rows, buttons and separators all on the 20 pt margins |
| 15 | List view | Preview count `.tertiary`; lock mark accent-blue (grey in the grid); inactive mark `.tertiary` | Secondary, matching the grid; count `.monospacedDigit()` |
| 16 | Tags sheet | List inset 17 pt inside a 20 pt field edge | Rounded `Radius.m` box with a hairline on the field's edges, row separators off |
| 17 | Smart Collection sheet | Form sections 40 pt in while title and buttons were at 20 pt; `minHeight: 450` left ~100 pt of dead space | Form, title and buttons share the 20 pt edges; height fits the form |
| 18 | Info tab | Tag chips 18.5 pt next to a 24 pt Edit Tags… button | 24 pt chips (centres already matched) |
| 19 | Sidebar | Section "+" glyph 17 pt right of the count badges' right edge (197–206 vs 189 pt) | Right edges aligned (±1 pt) |
| 20 | Settings | Explanation as a separate grey row under two toggles | Subtitles under their toggle; added one for "Group styles into families" |
| 21 | New Tag error text | Plain `.red` | `.textRed` |

### Golden Gate + light/dark

- **Sidebar**: the system `NavigationSplitView` sidebar, edge to edge; icons not forced to a
  colour (they follow the system: grey in background windows). No inset card.
- **Menus**: all text. The toolbar Sort menu showed a chevron image beside the current key;
  it's now the same text + checkmark items as View ▸ Sort By (key, Ascending, Descending).
  Context menus (grid `NSMenu`, list `FontMenuItems`) were already text-only.
- **Toolbar**: the standard toolbar (back, view switch, sort, compare count, search); the
  invisible-Back glass bubble is gone (row 7). The preview text bar under it is a content
  accessory bar (like Mail's filter bar) on the system `.bar` material, not a fake toolbar,
  and nothing scrolls under it (it's outside the scroll views).
- **Inactive windows** (new): selections and accent marks go grey when the window isn't the
  active one. Cards: `unemphasizedSelectedContentBackgroundColor` fill and system-grey ring,
  grey status dots, stars and ⊕ checkmarks; repainted on key/main changes. SwiftUI: style-row
  selection, glyph-cell selection, Compare/list/style status dots, list ★/✓ marks, Info tag
  chips and the tag sheet's checkboxes, via `controlActiveState` (`WindowAccent.swift`).
  Inactive shots: `real-grid-inactive-dark.png`, and every `after-snap/*` render (offscreen
  windows are never key).
- **Live appearance and accent changes**: cards and preview lines repaint on
  `viewDidChangeEffectiveAppearance`; the cached state-mark bitmaps are cleared and visible
  cards redrawn on `NSColor.systemColorsDidChangeNotification` (before, a new accent colour
  left old-colour dots until relaunch). The snapshot walk switches light → dark in one run and
  every dark render came out right.
- **Light and dark**: every surface shot in both; no drawn black/white (cards
  `controlBackgroundColor`, hairlines `separatorColor`, cells `.fill.quaternary`). The two
  invisible-in-both-modes surfaces (glyph cells, inspector tile) were the main light/dark
  finding.
- **Glass**: system materials only.

### Screenshots (`/tmp/slopapp-polish/specimen/`)

- Before: `before/*.png` (offscreen walk, light + dark: grid, grid-tag, grid-coverage, list,
  detail-styles/characters/text/variables/info, compare, sheet-tags, sheet-smart,
  sheet-install), `before/real-grid-light.png`, `before/real-settings-light.png`, plus the
  interrupted run's `before-*.png`.
- After (final build): `after-snap/*.png` (same set, light + dark), and real windows in
  `after/`: `real-grid-light.png`, `real-yours-light.png`, `real-grid-inactive-dark.png`,
  `real-detail-{styles,characters,text,info}-light.png`, `real-list-light.png`,
  `real-noresults-dark.png`, `real-favorites-empty-dark.png`, `real-settings-dark.png`,
  `real-stress-list-light.png`, `real-stress-grid-small-light.png` (1,888 families at 9 pt).
  (`after/*-{light,dark}.png` without `real-` are an intermediate render.)

### Gates

- `scripts/check.sh Specimen --perf`: all pass. 72 tests in 14 suites. Perf (load 5.6, busy
  machine): launch 135 ms, first window 499 ms, idle CPU 0.058 %, footprint 96.6 MB.
- Scroll/typing bench (1120×740, real fonts): scroll p50/p95 12 pt 10.1/12.5 ms, 36 pt
  5.8/8.0, 72 pt 1.8/3.7, 200 pt 1.3/3.4 ms; typing at 36 pt card draw CPU 3.0 ms p50
  (parity: 2.4 at load 3). Bench footprint after paging the library at four sizes: 453–524 MB
  vs 194–216 MB in the parity pass: `footprint` shows 203 MB of it is window-server graphics
  memory ("owned physical footprint (graphics)") that only exists with an unlocked display
  (the parity numbers were taken with the screen locked); heap (Malloc Small ~96 MB) is in
  line. Not a budget metric, but worth re-checking on a quiet machine.
- `scripts/drive tree`: 0 `[unlabeled]` in the grid, list, every detail tab and Settings;
  close button 16×16 in the main and Settings windows.
- Lint clean.

### Not done, and why

- **Active-window screenshot** (accent sidebar icons, accent card selection): needs
  Specimen frontmost; the owner was using the Mac throughout (idle 1–55 s at every check), so
  I didn't take focus. Every shot is of a background window. Owed.
- **Hover with the real pointer** wasn't driven (owner present); a hover state was captured
  incidentally with the owner's pointer resting on a card.
- **Tag colours** (the brief mentions "tags with colours"): Specimen's tags have no colour
  attribute; adding one is a feature (model, storage, picker), not polish. Deferred.
- **Long single-family names**: no installed font has one long enough to test end to end;
  the card name now truncates against a fixed slot (it can't reflow on hover).

### Shared-looking pieces made in-app

`WindowAccent.swift` (accent/selection colours that grey out in background windows; could
move to SlopKit as-is; **moved 2026-11-06**: now SlopKit's `WindowState.swift`, the app copy
is deleted), `GlyphView` + `GlyphMetrics` (optically centred glyph on a shared
baseline) and `PreviewMetrics` (shared preview baseline) in the app.
