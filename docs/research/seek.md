# Seek research (inspired by HoudahSpot)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied:
> HoudahSpot 6.8 (not installed on this Mac) from its product page, 6.x release notes,
> Setapp customer reviews and coverage, plus Apple's `NSMetadataQuery` / Spotlight
> attribute docs and Finder's own search as the baseline, on 2026-11-03. We never copy its
> name, icons, artwork, wording, sounds or signature visuals.

## The job

Seek finds files when you remember *something* about them but not where they are: "a PDF,
bigger than 5 MB, from last spring, with 'invoice' in it", "every .psd modified this week
under Projects", "screenshots from yesterday". Spotlight's bar is built for launching and
quick hits; Finder's search window hides its criteria behind + buttons and ⌥ tricks and
can't show paths. People reach for Seek a few times a week when a quick search fails.
"Done" is the file found, previewed and opened or dragged out in under 30 seconds.

The one interaction that matters most: **type a few words, add one or two criteria (kind,
date, size, folder), see a live sortable list with paths, press Space to preview, Return to
open.**

## Who and when

- "Where's that contract PDF from March?"
- Cleaning up: all files > 1 GB in Home, sorted by size.
- Finding every file of a type in a project tree.
- Finding text inside documents when the name is unknown.

Frequency: a few times a week; 10–60 seconds each.

## Feature inventory

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Quick search field | Type words, Return | must | Toolbar `.searchable`, ⌘F; matches name *and* content by default (like Spotlight), with a scope toggle Name / Name & Contents. Live as you type (debounced 150 ms). |
| 2 | Criteria builder | Rows: name, text, extension, tags, dates, size, resolution, author…; any/all/none groups | must (Kind, Name, Extension, Date modified/created/last opened, Size, Contents, Tags) / should (any/none groups, image size, duration, author) / later (hundreds of attributes) | Compact rows under the toolbar: attribute ▸ operator ▸ value, + / − buttons. All rows AND'ed in v1. Built into one `NSPredicate` over `kMDItem*` keys. |
| 3 | Locations, include/exclude subfolders | Several folders; exclude subfolders; Home by default | must (Home default, This Mac, chosen folders) / should (exclude folders) | `searchScopes` = folders or `NSMetadataQueryLocalComputerScope`. |
| 4 | Results list with columns | List/icons/thumbnails; hundreds of columns; sort | must (list: Name, Kind, Size, Date Modified, Folder) / should (column chooser, Date Created/Last Opened) / later (thumbnails view) | `Table` with sortable columns; values come from the query's `valueListAttributes`, not from touching the files. |
| 5 | Group results | By kind, date, size, application | later | |
| 6 | Quick Look and preview pane | Quick Look; info pane with metadata; text preview with highlighted matches, folding to matches | must (Space Quick Look) / should (inspector with metadata) / later (text preview with highlights: a reviewer asked for highlighting) | |
| 7 | File actions | Open, reveal, drag, copy, move to Trash with undo, tag | must (Open ↩/⌘O, Show in Finder ⌘R, drag out, Copy Path ⌥⌘C, Move to Trash ⌘⌫ with undo) / later (tagging, rename) | |
| 8 | Filter results | Filter by name/path, regex | should | Second filter field narrows the live list (path substring). |
| 9 | Recent searches / templates / saved searches | Recent, templates ("Recent Files", "Applications"), save as template | must (recent searches) / should (save search to sidebar, a few built-in starters: Large Files, Recent Downloads, Screenshots, Images This Week) | Sidebar: Starters, Saved, Recent. Store as JSON. Export to Finder `.savedSearch`: later. |
| 10 | Raw query entry | Advanced queries in the field | should | "Raw query" criterion accepting Spotlight query syntax (`kMDItemFSSize > 1000000`). |
| 11 | Copy results as text | Tab-delimited | should | ⌘C on a selection copies paths; "Copy as Table" for TSV. |
| 12 | Tag cloud, Mail search, AppleScript, Alfred/LaunchBar | Yes | skip / later | Mail isn't in Spotlight's public index anymore. URL scheme/App Intent later. |
| 13 | Hidden and system files | Not a headline feature; a reviewer wants an "admin" mode | later | Spotlight doesn't index most hidden/system locations; a non-Spotlight file walk is a separate engine. |
| 14 | Non-indexed volumes | Requires Spotlight | must (explain) | If a scope isn't indexed, say so with what to do (System Settings → Spotlight privacy, or `mdutil`), rather than showing an empty list. |
| 15 | Defaults for new windows | Save current setup as default | later | |

### Must-haves, counted

1 search field, 2 core criteria, 3 locations, 4 results table, 6 Quick Look, 7 file
actions, 9 recent searches, 14 not-indexed explanation. Eight.

## Query engine notes (NSMetadataQuery)

- One `NSMetadataQuery` per window on the main run loop; `predicate` built from criteria;
  `searchScopes`; `valueListAttributes` for the visible columns; `sortDescriptors` from the
  table. Results stream: `NSMetadataQueryDidUpdate` / `DidFinishGathering`; live updates
  continue after gathering (new files appear).
- Read values with `result.value(forAttribute:)` only for visible rows (lazy); wrap
  `disableUpdates()`/`enableUpdates()` around reads.
- Name match: `kMDItemFSName LIKE[cd] "*word*"` per word; content: `kMDItemTextContent
  CONTAINS[cd]`; Kind via `kMDItemContentTypeTree` (UTType conforming: "PDF", "Image",
  "Movie", "Audio", "Folder", "Application", "Text", "Archive").
- Cap rendering, not results: the table virtualizes; counts shown ("12,408 items").
- Stop the query (`stop()`) when the window closes; never run queries in the background.
- Punctuation in names (dashes, apostrophes) is a known Spotlight weak spot (HoudahSpot
  6.8 shipped workarounds): add a post-filter on `kMDItemFSName` for exact substrings.

## Key flows

### Flow 1: find (main job)
1. ⌘N or launch: window with sidebar (Starters, Saved, Recent), search field focused, an
   empty state ("Type to search your Home folder").
2. Type "invoice". Results stream into the table within ~200 ms, sorted by Date Modified.
3. Click "+ Criterion" (⌘⇧N): Kind is PDF; another: Date Modified is in the last year. The
   list updates live.
4. ↑/↓ through results; Space previews; Return opens; ⌘R reveals; drag a row into Mail.

### Flow 2: first run
1. No permission prompt. The Home folder is the default scope.
2. If Spotlight indexing is off for a chosen scope, an inline message explains and links to
   System Settings → Spotlight.

## Settings inventory

| Setting | Default | Options | Keep? |
|---|---|---|---|
| Default location | Home | Home, This Mac, folder | must |
| Search field matches | Name & contents | Name only, Name & contents | must |
| Default sort | Date Modified, newest first | any column | should |
| Excluded folders | none | list | should |
| Show folders in results | on | toggle | should |

## Menus and shortcuts

File: New Search ⌘N · Open ↩/⌘O · Show in Finder ⌘R · Quick Look Space · Move to Trash ⌘⌫ ·
Save Search… ⌘S · Close ⌘W. Edit: Copy Paths ⌥⌘C · Copy ⌘C · Select All ⌘A · Find ⌘F ·
Undo ⌘Z. Search: Add Criterion ⇧⌘N · Remove Criterion · Location ▸ · Name Only / Name &
Contents. View: Columns ▸ · Show Sidebar ⌃⌘S.

## Permissions and system integration

- No permission needed to query Spotlight. Verify during build whether opening/Quick
  Looking results in Desktop/Documents/Downloads triggers macOS's folder-access prompt for
  our bundle (likely once per protected folder, on first file read, not on the query
  itself). Icons and metadata come from the query, so listing results should read no files.
- No Full Disk Access requested; no network.

## UX patterns worth adopting

- **Criteria visible as rows**, editable in place (vs Finder's hidden ⌥ groups).
- **Paths as a first-class column**: "which copy is this?" answered at a glance.
- **Starters** that teach what's possible (Large Files, This Week's Screenshots).
- **Live results** while you refine.

## What we won't copy, and what we'll do better

- Not copying: name, icon, layouts, tag cloud, plug-ins, templates' names/wording.
- Better: a much smaller first screen (one field + a few criteria; power in a "More"
  attribute menu); keyboard-first throughout; the honest not-indexed message; saved
  searches persist (a review complains custom searches must be rebuilt each time).

## Edge cases

- Spotlight disabled, still indexing ("results may be incomplete while macOS indexes"),
  or a corrupt index (files missing: point to rebuilding the index).
- External/network volumes not indexed; volume ejected while results show it.
- 100k+ results: table stays responsive; memory < 120 MB.
- iCloud Drive files not downloaded (still listed; open triggers download).
- Names with punctuation, diacritics, CJK; case and diacritic-insensitive by default.
- Files deleted while listed (live update removes them); Trash results excluded by default.
- Date criteria across DST and time zones ("today" in local time).

## Our v1 scope

- [ ] Window with search field (name & contents), live results within ~200 ms.
- [ ] Criteria rows: Kind, Name, Extension, Date Modified/Created/Last Opened, Size, Contents, Tags (AND).
- [ ] Locations: Home (default), This Mac, chosen folders.
- [ ] Sortable table: Name, Kind, Size, Date Modified, Folder; virtualized.
- [ ] Space Quick Look, Return open, ⌘R reveal, drag out, copy paths, Move to Trash with undo.
- [ ] Recent searches in the sidebar; a few starters.
- [ ] Not-indexed / indexing-in-progress explanations.
- [ ] Settings: General (default location, match mode), About.
- [ ] Unit tests: predicate building for every criterion (golden predicate strings), date-range math, size parsing ("5 MB"), saved-search encoding; integration test against a temp folder that `mdimport` indexes.

## Open questions

Decisions (owner defaults, 2026-11-03: native, fast, private, no network):

1. **Spotlight only** in v1; a non-indexed file-walk engine (hidden/system files) is later.
2. **Saved searches:** should (sidebar); Finder `.savedSearch` export later.
3. **Any/None groups:** should; v1 ANDs criteria.
4. **Text preview with highlights:** later.

## Sources

- [HoudahSpot](https://www.houdah.com/houdahSpot/)
- [HoudahSpot 6 release notes](https://www.houdah.com/houdahSpot/releases/releaseNotes6.html)
- [HoudahSpot Setapp customer reviews](https://setapp.com/apps/houdahspot/customer-reviews)
- [ifun.de: HoudahSpot 6](https://www.ifun.de/houdahspot-6-mac-dateisuche-generalueberholt-163665/)
- [Brett Terpstra on HoudahSpot 5](https://brettterpstra.com/2019/04/04/houdahspot-5-dot-0/)
- Apple: `NSMetadataQuery`, Spotlight metadata attributes (`kMDItem*`).

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.
