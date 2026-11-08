# Tidy disk map research (inspired by DaisyDisk, GrandPerspective and CleanMyMac's Space Lens)

> A feature for an existing app, not a new one. It extends Tidy's **Space Map** module
> (`apps/Tidy`, `⌘6`). Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md),
> 2026-11-07. Studied:
>
> - **DaisyDisk 4.34.3** (Mac App Store build, installed at `/Applications/DaisyDisk.app`).
>   It wasn't running. I launched it to read its menus and Settings, but the screen was
>   locked, so `scripts/drive` couldn't see any window. I quit it straight away: no scan was
>   run and no setting was touched. Its menu items, Settings labels and messages were read
>   statically from the bundle's English `.strings` and compiled nibs. Also its online guide
>   (sunburst, deleting, hidden and purgeable space, disks overview, shortcuts, tips),
>   product page and App Store version history.
> - **GrandPerspective 3.8.1** (not installed): its website and help pages (creating,
>   navigating and inspecting views, size differences, cloud storage, packages, hangs) and
>   App Store version history. **It's GPL: we studied behaviour only and read none of its
>   code.**
> - **CleanMyMac's Space Lens** (installed, not launched because opening it shows the owner's
>   scan results): MacPaw's knowledge base pages. The earlier parity pass already read its
>   strings (see [`tidy.md`](tidy.md), "Parity pass").
> - Reviews and threads (App Store, Mac Power Users, comparison posts), Apple's TN3150 and
>   the `getattrlist(2)` man page, Eclectic Light on APFS space accounting, and a
>   throwaway benchmark on a synthetic tree (below).
>
> We never copy names, icons, artwork, wording, sounds or signature visuals. DaisyDisk's
> sunburst and CleanMyMac's bubbles are signature visuals: we don't use either.

## Where Tidy is today (what to reuse)

Tidy already has a first Space Map (parity pass, 2026-11-03). Read before writing this:
`Sources/TidyCore/SpaceMap.swift`, `DiskUsage.swift`, `TrashPolicy.swift`, `Trash.swift`,
`TrashLog.swift`, `TidyEnvironment.swift`, `Sources/Tidy/SpaceMapModule.swift`, `AppModel`,
`TidyFixtures/Fixture.swift`, `TidyTool/main.swift`, and the tests in `ModuleTests.swift`.

| Piece | What it does now | Plan |
|---|---|---|
| `SpaceScanner` | One `fts` walk of a folder. Size = `st_blocks × 512` (space on disk). Hard links counted once by (dev, inode). Doesn't cross volumes (`FTS_XDEV`). Packages are one item. Each folder lists up to 60 children of at least 1 MB; the rest is folded into "N smaller items". Protected folders are skipped when there's no Full Disk Access. Checks for cancel every 4,096 entries and reports progress. | **Replace the walker and the storage** (see Performance). Keep the rules (sizes on disk, hard links once, packages as one item, folding, exclusions) and their tests. |
| `SpaceNode` | A class per listed item holding a `URL`, a `name` and a `children` array. | Replace with a compact node store. Measured: about 585 bytes per node in this shape, about 84 in a struct-of-arrays layout. |
| `Treemap.layout` | Squarified treemap (Bruls, Huizing and van Wijk 2000), tested for areas, overlaps and aspect ratios. | **Reuse as is.** Call it once per nesting level. |
| `SpaceMapModule` | Intro page with a "Home Folder ▾ / Choose Folder…" pull-down, a scanning page with Stop, then the results: a list (biggest first, size bars, checkboxes, chevrons) beside a one-level treemap in an `HSplitView`. Breadcrumbs and `⌘↑`. Space checks or unchecks a row. Context menu: Show in Finder, Quick Look, Check, Uncheck. Double-click or Return opens a folder. The bottom bar shows "N checked" and Move to Trash…. The confirmation lists names and size. Sizes update without a rescan, and Put Back restores them. | **Keep the module, its stages and its list.** Add the volume scope, a nested map, the details strip, the checked-items tray, back/forward, incremental results and honest totals. |
| `TrashService` / `TrashPolicy` / `TrashLog` | Every move passes a policy check and then `FileManager.trashItem` (or a folder in test mode). It's logged for Put Back, including after a relaunch. `⌘Z` / `⇧⌘Z` undo and redo. | **Reuse.** Make the policy stricter for the map (package contents, cloud folders, app libraries) and allow external volumes (see Safety). |
| Full Disk Access | `FullDiskAccessProbe`, a live re-check, the access sheet and an in-section `Notice`. | Reuse. |
| Test mode | `TIDY_HOME` etc. confine scans and moves to fixture folders. `Fixture.isSafeRoot` refuses anything outside `/tmp/tidy-test` or the temp folder. `tidy-tool bench` prints only counts and timings. | Reuse. Add `TIDY_VOLUMES` and a large generated map tree (see Testing). |

**Problems found while reading the current code** (for the build step to fix and test):

1. **Nested checks double count.** If a folder and something inside it are both checked,
   `checkedNodes` adds both sizes to the total. The move then reports the inner item as
   "It's no longer there", because it went to the Trash with its parent.
2. **Memory.** One class and one `URL` per listed node. The builder also holds *every* child
   of a folder until that folder finishes, so a folder with a million files holds a million
   nodes before it folds them.
3. **No protection against iCloud downloads.** With Full Disk Access, the walk enters
   `~/Library/Mobile Documents` and `~/Library/CloudStorage`. Reading a dataless *folder*
   makes macOS fetch it from the cloud (TN3150), and that can hang the walk.
4. **Nothing shows until the scan ends**, and Stop throws the partial result away.
5. **The scope is the home folder or a folder inside it.** You can't map a whole disk or an
   external one.
6. **"N smaller items" can't be opened**, so a folder with 50,000 small files is a dead end.
7. **The treemap is one level deep**, so it doesn't show what's inside each folder.
8. **No context for the totals**: nothing says how much of the disk the map explains, or
   what's purgeable or free.
9. **Each treemap tile is its own SwiftUI view.** That's fine for 61 tiles but too slow for
   a nested map with hundreds.

## The job

Someone's disk is nearly full (or macOS says so) and they want to know **what's taking the
space, in seconds**, then get rid of the big things they don't need without risking
anything important. Finder's Get Info is slow and goes one folder at a time, and System
Settings' Storage buckets ("System Data", "Documents") don't say which files they mean. The
map answers "where did 200 GB go?" at a glance, and lets you drill into the biggest block
until you reach the actual file. Done feels like: "it was three old iOS backups and a 40 GB
VM image. They're in the Trash, and the map shows the space they free."

**The one interaction that matters most:** press Scan, and within a second a map shows the
biggest folders as big blocks. Click the biggest one again and again until you reach a file
you recognise. Check it, then Move to Trash.

## Who and when

- "Your disk is almost full" alert, or an update that needs 30 GB free.
- Before buying a bigger Mac or an external drive: "what am I actually storing?"
- A developer whose disk shrank: Docker images, simulators, `node_modules`, DerivedData,
  VM images (the Cleanup module handles the known junk; the map finds the rest).
- After a big project: find the old video exports, archives and downloads.
- Checking an external drive or a backup disk before reusing it.

How often: a few times a year for most people, monthly for developers and video people. A
session lasts 2–10 minutes: one scan, a handful of drill-downs, one Move to Trash.

## The visual: a treemap, not a sunburst

**Decision: a squarified treemap, nested two levels deep, always beside a list.** The list
is the primary path for VoiceOver and the keyboard. A sunburst and bubbles are skipped.

Reasons, for macOS 27 and accessibility:

1. **It fills the window.** Windows and panes are rectangles. A circle in a 16:10 pane uses
   about half its area (π/4 × h²/(1.6 h²) ≈ 49 %), and a sunburst's outer rings get thinner
   the deeper they go. A treemap uses all of the pane, so blocks are bigger click targets
   and more of them have room for a label.
2. **Labels fit.** Names and sizes sit horizontally inside rectangles. Sunburst wedges need
   curved text, or a sidebar that you look back and forth to, which DaisyDisk solves with
   hover plus its side list.
3. **Accessibility.** An accessibility element has a rectangular frame. A treemap tile's
   frame *is* its shape, so the VoiceOver cursor, Hover Text, Voice Control's numbered
   overlay and Switch Control point at exactly the right block. Wedge bounding boxes
   overlap heavily. Arrow keys also map onto the treemap's spatial neighbours (as in
   GrandPerspective).
4. **It fits the house style.** Rounded rectangles take `Radius` tokens and concentric
   insets (design system §4). Wedges can't follow the corner rules. The sunburst is
   DaisyDisk's signature look and the bubbles are CleanMyMac's, and we don't copy signature
   visuals.
5. **It's already built and tested** (`Treemap.layout`). GrandPerspective shows that people
   can read a treemap well over many years of use. We use the published algorithm, not
   their code.

What the sunburst does better, and how we make up for it: studies favour sunbursts and
icicle plots over treemaps when people have to understand the *hierarchy* (Stasko & Zhang
2000; Woodburn et al. 2019). The Mac Power Users thread has users on both sides: one finds
the doughnut hard to read, another finds same-coloured treemap blocks confusing at first.
So:

- **Two levels, with a title band.** A folder tile has a thin header band with its name and
  size, and its children are laid out inside it with an even `Spacing.xs` inset, so folders
  read as containers. Files and small folders are plain tiles.
- **Hovering a tile also highlights the folder that contains it**, so you can see where in
  the hierarchy the pointer is.
- **Breadcrumbs** above, the **list** beside the map (same order, same selection), and a
  short drill animation (a fade under Reduce Motion) so you know where you went.
- **No meaning carried by colour alone.** Folders are tinted with the user's accent (deeper
  for bigger ones, as now) and files are neutral. Every tile that's big enough has an icon
  and a label, and the list says everything again. A colour-by-kind palette is `later` (it
  needs a palette that follows the design system's colour rules).

## Feature inventory

Priority: **must** (v1 isn't worth shipping without it), **should** (v1 if cheap, else
v1.1), **later**, **skip** (with the reason). "DD" is DaisyDisk, "GP" is GrandPerspective,
"SL" is Space Lens.

| # | Feature | How the originals do it | Priority | Notes for us |
|---|---|---|---|---|
| **Scope and scanning** | | | | |
| 1 | Choose what to map: home folder, a folder, a disk | DD: a start screen listing every mounted volume with a usage gauge and a Scan button each, plus Scan Folder…; drop a disk or folder on the window or Dock icon. GP: a welcome window with recent scans and Scan Other Folder. SL: a location pop-up (main drive by default) | **must** | The intro's pull-down becomes: **Home Folder** (default), **the startup disk**, each other mounted local disk, **Choose Folder…** (any folder, not just inside home). Disks show name, kind (internal, external, network) and a small used/free bar. |
| 2 | Startup disk scan without double counting | DD and GP scan `/` | **must** | Scan the Data volume (`/System/Volumes/Data`) and show its folders under their firmlinked names (`/Users`, `/Applications`, `/Library`… from `/usr/share/firmlinks`). The sealed system volume becomes one locked tile, "macOS", sized from `ATTR_VOL_SPACEUSED`, and is never walked. Mount points (`ATTR_DIR_MOUNTSTATUS`) are skipped. |
| 3 | Fast scan with progress | DD: "seconds" on an SSD, slower on hard disks and network shares; vendor claims 15 s vs 6 min for Finder. GP: background threads, speed-ups in 3.4 and 3.5 | **must** | A parallel `getattrlistbulk` walker (budgets below). Progress shows items counted and bytes found, never file names (the current path line is fine on screen, but not in logs). |
| 4 | Results grow while scanning | DD: its docs don't say whether the map draws during a scan (couldn't check: the screen was locked). GP: the view window appears when the scan finishes | **must** | Better than both: the top-level map draws within 0.5 s and updates up to 4× a second. Folders still being counted are marked with "+" and a subtle "counting" state. Finished folders can be opened while the rest is still scanning (`should`). |
| 5 | Stop | DD: cancel the scan (quitting mid-scan asks first) | **must** | Esc / Stop. Keeps the partial map, marked "Stopped: partial", with every unfinished folder showing "+". Rescan resumes from scratch. |
| 6 | Rescan | DD: rescan the current folder `⌘R`, the whole disk `⇧⌘R`, as admin or normal user. GP: Refresh (only folders FSEvents says changed) and Rescan (full) | **should** | **Rescan** (`⌘R`, whole map) and **Rescan This Folder** (`⌥⌘R`), which re-walks one subtree and splices it in. Refresh based on FSEvents is `later`. |
| 7 | Scan as administrator | DD: rescan as admin through a privileged helper (not in the App Store build) | **skip** | Needs a root helper (`SMAppService` daemon), which is a big security surface for a cleaner. We show what we couldn't read instead (#16). |
| 8 | Scan several disks at once | DD: parallel scanning | **skip** | One map at a time keeps memory bounded and the UI simple. |
| 9 | Cloud accounts scanned remotely (Dropbox, Google Drive…) | DD: OAuth and remote APIs | **skip** | Network and accounts (house rule). |
| 10 | Starred / recent folders | DD: star a folder to keep it in the disk list. GP: Scan Recent submenu | **should** | The last 5 roots under "Recent" in the pull-down (local `UserDefaults`, clearable). |
| 11 | Drop a folder or disk on the window to map it | DD, GP | **should** | SlopKit `DropZone` on the intro page and the map. |
| 12 | Save and reload scans | GP: save scan data, load it later | **later** | Useful for comparing before and after. The file format is a privacy question (a list of file names), so it would need an explicit save. |
| 13 | Filters and excluded folders | GP: rule-based filters (name, path, size, type, hard link, package, "no cloud files") to mask, hide or skip during the scan | **later** | v1 has fixed exclusions only (protected folders without access, the Trash, mount points). |
| **Map and list** | | | | |
| 14 | The map | DD: sunburst, folders coloured and files grey, tiny items merged into translucent segments. GP: a full-depth treemap coloured by a chosen scheme. SL: bubbles | **must** | A treemap two levels deep (see above). Tiles smaller than about 4×4 pt are merged into the folder's "smaller items" area. Folders tinted with the accent, files neutral, all of it grey when the window isn't key (`windowAccent`). |
| 15 | The list beside the map | DD: a side list of the current folder. SL: a sized list beside the bubbles | **must** (exists) | Keep `SpaceList`: biggest first, size bars, checkboxes, chevrons, "+" for partial. The list and the map share hover and selection. |
| 16 | Space we couldn't see | DD: a virtual "hidden space" item = used space − scanned total, broken into purgeable, other volumes and still hidden, with explanations. GP: "miscellaneous used space" (a grey block when it shows the entire volume) | **must** | Disk scope: a **volume bar** above the map (see Size accounting): *Mapped* / *Other used space* / *Purgeable* / *Free*. At the disk root, a locked virtual tile "Not mapped" with a one-line explanation of what it usually is (the system, other users, snapshots, other volumes in the same container, unreadable folders). Folder scope: no bar, just the folder total. |
| 17 | Small items grouped | DD: "smaller objects", expandable to the full list. GP: tiny rectangles drawn but hard to select | **must** | Keep "N smaller items" in the list and the map. **Make it openable**: it re-reads that one folder's entries on demand (one `getattrlistbulk` pass), so we don't keep every small file in memory. |
| 18 | Packages as one item | DD: one object, with a command to show the contents. GP: a display option (files only / packages / folders) | **must** (exists) / **should** | Exists. Add **Show Package Contents** (opens the bundle in the map), but its contents stay read-only (Safety). |
| 19 | Partial and unreadable folders | DD: purple "restricted" items. GP: leaves them out of the totals | **must** (exists) | "+" after the size, a lock badge, and in the details "Tidy couldn't read N folders here". |
| 20 | Colour by kind, date, depth | GP: many schemes and palettes | **later** | See the visual section. |
| 21 | Show free and other space as tiles | GP: "show entire volume" (black and grey rectangles) | **skip** | The volume bar does this without crowding the map. |
| 22 | Duplicate or twin views | GP | **skip** | One window, one map. |
| **Navigation** | | | | |
| 23 | Drill down | DD: click a folder. GP: zoom `⌘+`. SL: click a bubble, double-click a row | **must** (exists) | Double-click a tile or row, Return, `⌘↓`, or click a folder's header band. |
| 24 | Up | DD: `⌘↑`, click the centre, pinch. GP: zoom out `⌘−`. SL: double-click the empty space | **must** (exists) | `⌘↑`, the breadcrumb, the up chevron. |
| 25 | Back and forward | DD: `⌘[` / `⌘]`. SL: < and > buttons | **should** | A history stack, with toolbar back and forward buttons (`⌘[` / `⌘]`). |
| 26 | Keyboard selection | DD: ↑↓, Page Up/Down, Home/End. GP: arrow keys move spatially once a selection is locked | **must** (list) / **should** (map) | The list already does ↑↓ and ⌘A. Arrows in the focused map move to the neighbouring tile. |
| 27 | Pinch to go in or out | DD | **later** | `MagnifyGesture` → open / up. |
| **Details** | | | | |
| 28 | Hover details | DD: pointing at a folder shows its contents in the side list. GP: hover selects and shows the name and size under the view; a click locks the selection. SL: hover highlights the item in both views with basic details | **must** | A **details strip** under the map (a fixed height, so nothing jumps) shows the item under the pointer, or the selection when the pointer is outside: icon, name, kind, size on disk, path (relative to the root, middle-truncated). No tooltips: they're slow and cover the map. |
| 29 | Selection details | GP: a control panel with Info / Display / Focus tabs. SL: Get Info in the context menu | **should** | An inspector popover (`⌘I`): size on disk, file size (logical), item count, modified, created, "hard-linked (N names)", "clone: shares space with other files", "in iCloud, not downloaded", "macOS may remove this on its own" (purgeable flag), "couldn't read N folders inside". |
| 30 | Copy Path | — | **should** | Context menu and `⌥⌘C`. |
| **Collect and delete** | | | | |
| 31 | Gather items from many folders, then delete | DD: drag to a tray under the map (or ⌘⌫); it holds items until Delete, with a 5-second countdown, then **deletes them permanently**. SL: checkboxes, then "Review Selected", then Remove. GP: delete one selection at a time (off by default in its preferences) | **must** | Keep the checkboxes. The bottom bar becomes a **checked-items tray**: "4 checked · up to 23.1 GB" opens a popover listing each checked item (icon, name, enclosing folder, size) with Uncheck, Show in Finder and Quick Look, plus **Move to Trash…**. Checks survive navigation. **Checking a folder absorbs any checked items inside it** (fixes problem 1), and checking something inside an already-checked folder is refused with a note. |
| 32 | Trash, not permanent | DD deletes permanently (reviews complain about no undo); GP moves to the Trash | **must** (exists) | Trash only, with Put Back and `⌘Z`. The confirmation lists names, count and "up to" the size, and says the space comes back once the Trash is emptied. |
| 33 | Refuse system and essential items | DD: refuses `/System`, `/Library` and the home folder, and names the app or macOS when something is required. SL: system items can't be selected | **must** | See Safety. A locked row shows a lock and its reason in the help text and details ("Belongs to macOS", "Inside an app", "Synced with iCloud Drive: remove it in Finder"). |
| 34 | Sizes update after a move | DD: the map updates after its own deletions (not after Finder's). GP: the view updates to show the freed space | **must** (exists) | Exists (the `removed` overlay). Keep it, and make it work with the new store. |
| 35 | "Freed X, share it" messages, rate prompts | DD | **skip** | Quiet by default. No social prompts. |
| 36 | Reclaim purgeable space, delete snapshots | DD: drag purgeable to the tray (not in the App Store build); copy a Terminal script to delete snapshots | **skip** | Owner rule (no "free up purgeable"; macOS does it). Thinning snapshots needs root (deferred in `tidy.md`). We *explain* purgeable space and link to Time Machine settings. |
| 37 | Apps found in the map | — | **should** | A `.app` row's action is **Uninstall…**, which opens Applications with that app, so its leftovers go too. It isn't trashed raw. |
| **Other actions** | | | | |
| 38 | Reveal in Finder | DD: ⌘-click, menu. GP, SL: toolbar or context menu | **must** (exists) | `⇧⌘R`, the context menu, the tray. |
| 39 | Quick Look | DD and GP: Space. SL: context menu | **must** (exists) | `⌘Y` and the context menu. Space stays **check/uncheck**, which is Tidy's rule everywhere (decided in blind tests). Never Quick Look a dataless file automatically. |
| 40 | Open the file | GP: Open | **later** | Double-click opens folders; for files, Show in Finder is safer. |
| 41 | Open in Terminal | DD | **later** | `NSWorkspace` open with Terminal, no permission needed. |
| 42 | Open Disk Utility | DD | **later** | A link in the volume bar's help. |
| 43 | Export CSV / text / image | DD: CSV. GP: text and image | **later** | It contains file names: explicit save only. |
| 44 | Find in the map | GP: search by name | **should** | The toolbar search already filters the current folder. Searching the whole map ("all items named X, by size") is `later`. |
| 45 | Live free-space figures | DD: the disk list updates live | **later** | Volume bar refresh on `NSWorkspace` mount notifications and after our moves only. |
| 46 | Items changed outside Tidy | DD: struck-out items (deleted, moved). GP: Refresh | **later** | An FSEvents stream on the root while the map is visible marks "changed since the scan". |
| **Settings** | | | | |
| 47 | Size measure | GP: logical or physical, decimal or binary units. DD: always physical except on network drives | **skip** (as a setting) | The map always uses **size on disk**. The details show both. Units like Finder (decimal). |
| 48 | Enable deletion | GP: deletion off by default | **skip** | Trash plus Put Back plus a confirmation is safe enough; a hidden switch would confuse people. |

**Must-haves, honestly short:** #1 scope (home, disk, folder), #2 startup disk without double
counting, #3 a fast parallel walker, #4 incremental results, #5 Stop keeps the partial map,
#14 nested treemap, #16 volume bar with "Not mapped" and purgeable shown apart, #17 openable
smaller items, #28 details strip, #31 checked-items tray with nesting rules, #33 safety rules.
The rest of the musts exist already (#15, #18, #19, #23, #24, #32, #34, #38, #39) and only need
to keep working on the new store.

## Size accounting: reporting honestly

Every number we show answers a question in plain words. On the map it's always one:
**"space on disk"**, meaning what this item takes on this Mac.

| Situation | What the system reports | What we show |
|---|---|---|
| Ordinary file | `ATTR_FILE_ALLOCSIZE` (all forks) ≈ `st_blocks × 512`; `ATTR_FILE_TOTALSIZE` = logical | Size on disk on the map and in the list. The logical size in the details when it differs by more than 10 %. |
| Sparse file (Docker.raw, VM disks) | logical ≫ allocated (`EF_IS_SPARSE`) | Size on disk; details "File size 64 GB, uses 9.8 GB on disk (sparse)". |
| Compressed file (`UF_COMPRESSED`) | allocated < logical | Same as sparse, labelled "compressed". |
| **Hard links** (`linkcount > 1`) | the same inode under several names | Counted **once**, at the first name the walk reaches (as now; GP does the same). That row gets a "hard-linked" mark, and the details say "Also at N other places. Moving this one to the Trash frees nothing while the others exist." The tray total excludes it unless all its names are checked. |
| **APFS full clones** (`EF_SHARES_ALL_BLOCKS`, `ATTR_CMNEXT_CLONEID`) | each clone reports the full allocated size; private size is 0 for **every** member, including the original (measured: 101 files in one clone group, all 0) | Count each clone group **once**, at the first member seen (DD 4.34 added the same). Later members show their size greyed with "clone". Freeing a clone frees nothing while the others exist. |
| **Partial clones** (`EF_MAY_SHARE_BLOCKS` without all) | private size = what deleting frees now | Fetch `ATTR_CMNEXT_PRIVATESIZE` *only for these files* (it makes a bulk read 3× slower, see Performance). The details show "Frees at least X". |
| **Dataless (iCloud and other File Provider placeholders)** (`SF_DATALESS`) | allocated ≈ 0, logical = the cloud size | 0 on disk, so it doesn't inflate the map. The folder's details say "N items (X GB) are in iCloud and not downloaded". **Never trigger a download** (see Permissions). |
| Purgeable item (`EF_IS_PURGEABLE`) | the item can be deleted by the file system when space is needed | A mark "macOS may remove this on its own" (often caches). Counted normally. |
| Packages | a folder | One item, total of its contents. |
| The volume as a whole | `volumeTotalCapacity`, `volumeAvailableCapacity` (free), `volumeAvailableCapacityForImportantUsage` (free + what macOS can purge; inference from several sources, **verify** in the build), `ATTR_VOL_SPACEUSED` per volume | The **volume bar**: *Mapped* (sum of the scan) · *Other used space* (used − mapped: the macOS system volume, other volumes in the same APFS container, local snapshots, other users, unreadable folders, file system overhead) · *Purgeable* (important-usage − free, shown with a dashed edge and "macOS frees this on its own when it needs room") · *Free*. Hovering a segment gives its size. All of it in `monospacedDigit`. |
| Moving to the Trash | frees nothing until the Trash is emptied; Time Machine local snapshots can keep the blocks for up to 24 h | The tray and the result say "**up to** X once you empty the Trash". After a move the bar doesn't pretend: the Trash total shows in the result with Open Trash, like the rest of Tidy. |

Units: `ByteFormat` (decimal, like Finder). Lower bounds get "+". Estimates get "up to".
**We never add a number we can't explain.** If the walk and the volume figures disagree, the
difference goes to "Other used space", never quietly into a folder.

## Scan scopes and volumes

| Scope | What we walk | Deleting | Notes |
|---|---|---|---|
| Home folder (default) | `environment.home`, with protected folders skipped without Full Disk Access (as now) | yes, through `TrashPolicy` | Fastest, no extra prompts. |
| A folder (Choose Folder…, drop, Recent) | the folder (not just inside home any more) | inside home: yes. Elsewhere: read-only, with Show in Finder, except external volumes (below) | |
| Startup disk | `/System/Volumes/Data`, shown with firmlinked paths. The system volume is one locked "macOS" tile. Other users' folders show as locked and partial | inside home only | Needs Full Disk Access to be useful. Without it, the intro says so before the scan, with Scan Anyway. |
| Other local volume (USB, Thunderbolt, SD, disk image) | the volume root, `FTS_XDEV`-style (no crossing) | yes, to that volume's Trash (`FileManager.trashItem` uses `.Trashes/<uid>`), *if* the volume has one | macOS asks once whether Tidy may read files on a removable volume: only when the user picks that volume. Read-only volumes: everything is locked ("This disk is read-only"). FAT/exFAT: no hard links or clones, and the allocated sizes come from the cluster size. |
| Network volume (SMB, NFS, WebDAV) | the share's root | only if `trashItem` succeeds. On failure, no permanent fallback: "This disk has no Trash. Use Show in Finder to delete it there." | Slow: show "Network disks can take minutes" on the intro. `getattrlistbulk` is fastest on network file systems (Tempelmann 2019). macOS asks about network volumes the first time. |
| Time Machine backup disks | — | — | **later**: hidden from the list in v1 (millions of hard links and snapshots; slow, and deleting there is Time Machine's job). |

## Key flows

### Flow 1: find what fills the disk (the main job)

1. `⌘6` (or the sidebar) → Space Map intro: hero, one line, the scope pull-down ("Home
   Folder ▾" by default, then the startup disk, other disks, Recent, Choose Folder…),
   and the round **Scan** button (Return, `⌘R`).
2. Scan → within 0.5 s the results page appears: breadcrumb bar, the volume bar (disk
   scope only), the list on the left and the map on the right, growing as folders are
   counted. A thin progress line in the bar shows "1,204,331 items · 182 GB" and a Stop
   button (Esc).
3. The biggest blocks settle first. The pointer over a block highlights it and its folder;
   the details strip under the map shows its name, kind, size and path.
4. Double-click the biggest folder (or click its header band, or press Return in the list)
   → the map fades into that folder (no animation under Reduce Motion), the breadcrumb
   grows, and Back is enabled.
5. Repeat until you reach a file you recognise. Space checks it (or its checkbox). The
   tray says "1 checked · up to 38.2 GB".
6. `⌘↑` / `⌘[` back up, find a second thing, check it.
7. Click the tray → a popover with both items. Uncheck one, or Quick Look it (`⌘Y`) to be
   sure.
8. **Move to Trash…** → the alert lists the names, "2 items, up to 41 GB will be moved to
   the Trash. The space comes back when you empty the Trash. You can put them back (⌘Z)."
   Cancel is the default for Esc; Move to Trash is not the default button.
9. Moved → the tiles disappear, sizes update up the chain, and a result line shows "Moved 2
   items to the Trash · Put Back · Open Trash".

### Flow 2: first run and Full Disk Access

1. First time on the intro with no access: a `Notice` under the pull-down says "Desktop,
   Documents, Downloads and other apps' data will be skipped: macOS protects them" with
   **Allow Full Disk Access…** (the existing sheet: why, Open System Settings, live
   re-check).
2. Scan anyway → the map works for everything else. The skipped folders appear as locked,
   partial rows ("Needs Full Disk Access") so the totals don't look wrong without a reason.
3. Access granted while the map is open → the notice changes to "Rescan to include
   protected folders" with **Rescan**.
4. Startup disk scope without access: before the scan, a short note that most of the disk
   will be "Not mapped" without access, with Allow… and Scan Anyway.

### Flow 3: an external or network disk

1. Plug in a USB disk → it appears in the scope pull-down (mount notifications), with a
   used/free bar.
2. Pick it → Scan. macOS may ask whether Tidy can access files on a removable volume. If
   the answer is no: "Tidy can't read this disk. Allow it in System Settings ▸ Privacy &
   Security ▸ Files and Folders." with Open System Settings.
3. Map, check, Move to Trash → the items go to that disk's Trash. The result says the
   space comes back when the Trash is emptied *while the disk is connected*.
4. Eject it mid-map → the map shows "The disk was disconnected" with Start Over. The
   partial map is kept read-only until then; nothing acts on paths that are gone.

### Flow 4: "N smaller items"

1. A folder holds 40,000 files under 1 MB → its list ends with "40,000 smaller items ·
   3.1 GB" and the map has a matching hatched tile.
2. Open it → Tidy re-reads that folder (one pass, < 200 ms for 40k entries) and lists them
   biggest first, so they can be checked one by one. The tile itself can't be checked or
   trashed: it's a group, not a thing.

### Flow 5: Stop, Put Back, Rescan

- Stop mid-scan → "Stopped: partial map" in the bar. Unfinished folders show "+". All
  actions work on what was counted.
- `⌘Z` after a move → the items go back and the sizes return in place (as now).
- `⌘R` → a full rescan. Checks are kept for items that still exist (`should`).

## Settings inventory

Originals: DD Settings has General (automatic update checks, anonymous analytics, a
congratulations message after deleting more than 5 GB) and a Full Disk Access pane that
says whether access is granted. GP Preferences: file size measure (logical or physical),
deletion enabled (off by default) and confirmation, default display focus, show entire
volume, colour scheme and palette, package display, default filter, what happens when the
last window closes. SL: none of its own.

| Setting | Default | Options | Keep? |
|---|---|---|---|
| Updates / analytics / congratulations | DD: on / off / on | toggles | **No** (no network, no telemetry, quiet). |
| Size measure | GP: physical | logical, physical | **No**: always on disk, both in details. |
| Deletion enabled + confirm | GP: off, confirm | toggles | **No**: Trash, confirm, Put Back. |
| Colour scheme | GP: by folder | many | **No** in v1 (`later`). |
| Smallest item listed separately | Tidy: 1 MB, 60 per folder (code constants) | — | **Keep as constants** in v1. A Settings row only if blind tests ask. |
| Include Desktop, Documents, Downloads without Full Disk Access | Tidy: skipped | "macOS will ask about each" | **Maybe** (Large & Old already offers this choice; reuse it). |
| Treemap depth | — | 1, 2, 3 | **Later** (2 by default). |
| Recent roots | — | Clear Recent | **Should**: a "Clear Recent" item in the pull-down, no Settings row. |

## Menus and shortcuts

Tidy's existing commands keep their meaning. New or changed items for the map:

| Menu | Item | Shortcut | Notes |
|---|---|---|---|
| File | Map Folder… | `⇧⌘O` when Space Map is showing | Today `⇧⌘O` is "Choose Folder for Large Files…". Make that item follow the section ("Choose Folder…"). |
| File | Scan / Rescan | `⌘R` | Exists (the module's main action). |
| File | Rescan This Folder | `⌥⌘R` | new |
| File | Move to Trash… | `⌘⌫` | Exists. Acts on the checked items (the tray). |
| File | Show in Finder / Quick Look / Get Info / Copy Path | `⇧⌘R` / `⌘Y` / `⌘I` / `⌥⌘C` | First two exist. |
| Edit | Check / Uncheck | Space | Exists (rows). In the map too, when it has focus. |
| View | Open (Enclosing Folder) | `⌘↓` / Return; `⌘↑` | `⌘↑` exists. |
| View | Back / Forward | `⌘[` / `⌘]` | new |
| View | Show Package Contents | — | new, read-only |
| View | Show Checked Items | `⇧⌘K`? | Opens the tray popover. **Owner to confirm the shortcut**; there's no standard one. |

Golden Gate rule: menu items are text only. The context menu on a row or tile: Open, Show
in Finder, Quick Look, Get Info, Copy Path, Check / Uncheck, and Uninstall… for apps.

## Permissions and system integration

- **Full Disk Access** (optional, existing flow). Without it: protected home folders are
  skipped and shown as locked partial rows, and the startup disk is mostly "Not mapped".
- **Removable and network volumes**: macOS's Files and Folders prompts appear the first
  time we read one. We only read a volume's contents after the user picks it. Listing
  volumes (name, capacity, kind through URL resource values and `statfs`) must not trigger
  a prompt: **verify** on macOS 27 with a USB stick in the build step.
- **iCloud and File Provider**: scanner threads call
  `setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD,
  IOPOL_MATERIALIZE_DATALESS_FILES_OFF)` and treat `EDEADLK` as "in the cloud, not
  downloaded". Apple's TN3150 shows that `getattrlistbulk` itself materializes dataless
  *folders* unless that policy is set. Use **dedicated threads** (`Thread` or a pthread
  pool), not Swift concurrency's cooperative pool, because a task can hop threads and the
  policy is per thread. Never set it for the whole process: Quick Look of a cloud file that
  the user asked for should still download it.
- **No admin**, no privileged helper, no Automation (we show our own inspector rather than
  asking Finder for Get Info through AppleScript).
- Time Machine: no `tmutil` calls in v1. The "Not mapped" explanation links to Time
  Machine settings (`x-apple.systempreferences:` URL) for snapshots.

## Performance budgets

### Measured (2026-11-07, this Mac: Apple silicon, macOS 27.2, internal SSD, warm cache)

A throwaway benchmark in the session scratchpad (not committed). The synthetic tree had
200,000 files in 2,000 leaf folders three levels deep, sizes from 1 byte to 40 KB, plus 100
hard links and 100 clones. Each figure is the best of 3:

| Walker | Time | Entries/s |
|---|---|---|
| `fts` (Tidy today, a `String` per entry) | 226 ms | ≈ 0.9 M |
| `FileManager.enumerator` + `totalFileAllocatedSize` | 567 ms | ≈ 0.36 M |
| `getattrlistbulk`, 1 thread, with `ATTR_CMNEXT_PRIVATESIZE` | 642 ms | ≈ 0.31 M |
| `getattrlistbulk`, 1 thread, no private size | 199–207 ms | ≈ 1.0 M |
| … with `ATTR_CMNEXT_CLONEID` or `ATTR_CMNEXT_EXT_FLAGS` added | 202–207 ms | same: these are cheap |
| `getattrlistbulk`, **4 threads**, no private size | **72–75 ms** | **≈ 2.8 M** |
| `getattrlistbulk`, 8 threads (naive shared queue) | 132 ms | contention |

Memory per node, 1 M nodes: a class with `URL` + `String` + children array ≈ **585 B**; a
struct-of-arrays store (parent/first-child/next-sibling `UInt32`, size `Int64`, name offset
and length into one UTF-8 arena, flags) ≈ **84 B** including array growth slack (≈ 45 B
when sized ahead of time).

What we take from this: a single-threaded walk is about the same with fts or bulk reads, and
that matches Tempelmann's 2019 finding that fts is fastest on local APFS. **The gain comes
from running bulk reads in parallel** (64–128 KB buffer per thread, 3–6 threads by core
count, a work-stealing queue). **Never request private size in the bulk call.** Fetch it
per file only for partial clones.

### Budgets (checked by the build and test steps)

| Metric | Budget | How to check |
|---|---|---|
| Walk speed, synthetic 200k tree, warm | < 150 ms (≥ 1.3 M entries/s) | `tidy-tool bench map /tmp/tidy-test/maptree` |
| Walk, synthetic 1 M tree, warm | < 1 s | same, `--files 1000000` |
| Real home (1–3 M files), internal SSD, cold | < 10 s; counts only, never names | `tidy-tool bench map` with no `TIDY_*` (read-only) |
| First map on screen after Scan | < 500 ms | timestamp log in test mode |
| Updates while scanning | ≤ 4 per second; each main-actor update < 4 ms | Instruments / signposts |
| Stop | walk stops < 100 ms; memory released < 1 s | bench |
| Memory, 1 M files mapped | retained < 60 MB above the app's baseline | `scripts/perf.sh`-style footprint after the scan |
| Memory, 5 M files mapped | peak during the scan < 400 MB; retained < 150 MB | the generated 5 M fake tree (`FakeFileSystem`, no disk) |
| Idle with the map shown | CPU < 0.2 % (no timers; the progress poll runs only while scanning) | `scripts/perf.sh Tidy` |
| Idle after Start Over | footprint back under the window budget (120 MB) | `scripts/perf.sh` |
| Layout, 2 levels, ≤ 2,000 visible tiles | < 4 ms, off the main actor, cached per (folder, size) | unit benchmark |
| Drawing and hover | 120 Hz on ProMotion (< 8.3 ms per frame) while hovering and resizing | Instruments; one `Canvas` pass, hit test over cached rects |

How to stay inside them:

- **Keep all folders, but not all files.** Each folder keeps its top K files (K = 64, or
  everything ≥ 1 MB, whichever is smaller) in a small heap while it streams. The rest go
  into its "smaller items" total. A folder of a million files never holds a million nodes.
- **Paths are rebuilt from the parent chain** when needed (Reveal, Trash, details). Nodes
  store only a name slice.
- **The hard-link set** holds only `linkcount > 1` files, keyed by (dev, file id). **The
  clone set** holds only flagged files, keyed by clone id.
- **Bottom-up totals**: each folder has a pending-subfolder counter; when it reaches 0 the
  folder's size is final and rolls up into its parent (that's what drives the "+" and
  "counting" states).
- **Snapshots for the UI** are small: the current folder's children and their running totals
  are copied 4× a second. The tree itself is never copied to the main actor. Treat it as
  immutable once a folder is final.
- **Drawing**: one SwiftUI `Canvas` for the tiles (fills, hairline borders, labels from
  `context.resolve(Text)`), not a view per tile. Hover hit-tests the cached layout. Labels
  are drawn only on tiles at least 64×34 pt (as now).
- **Accessibility** for the canvas: `.accessibilityChildren` with one element per
  first-level tile (frame = tile, label "Caches, folder, 13 GB, 24 percent", actions Open,
  Check, Show in Finder, Quick Look). Second-level tiles are reachable by opening their
  folder, or in the list.

## Safety

The rules the build must keep, each with a unit test:

1. **Only Move to Trash.** `TrashService` → `FileManager.trashItem` (or `FolderTrasher` in
   test mode). No `unlink`, `removeItem` or "delete immediately" fallback, anywhere in the
   map. Emptying the Trash stays in Cleanup with its own confirmation.
2. **Every move passes `TrashPolicy.check` again at move time**, on a path rebuilt from the
   tree. Before moving, re-`lstat` the path and compare (dev, file id) with what was
   scanned. If it changed (replaced, or the path now goes through a symlink), refuse with
   "It changed since the scan. Rescan and try again."
3. **Never system paths:** `/`, `/System`, `/Library` itself and Apple items in it, `/usr`,
   `/bin`, `/sbin`, `/private`, `/Applications` itself, `/Users` and other users' folders,
   the home folder and its top-level folders, `~/Library` and its standard folders,
   anything `com.apple.*`, volume roots, mount points, `.Trashes` and `.Trash`, the running
   Tidy bundle (most of this exists in `TrashPolicy`; the volume-scope paths are new).
4. **New read-only zones for the map** (shown, never moved; "Show in Finder" instead):
   inside any package (`.app`, `.photoslibrary`, `.musiclibrary`, `.fcpbundle`…; the whole
   package can be moved, its insides can't, because deleting inside a library corrupts it),
   `~/Library/Mobile Documents/**` and `~/Library/CloudStorage/**` (deleting syncs the
   deletion to every device; Finder warns properly), `~/Library/Mail/**`,
   `~/Library/Messages/**`, `~/Library/Containers/com.apple.*/**` (exists through the Apple
   rule).
5. **Apps go to the Uninstaller**, not raw to the Trash (#37).
6. **Virtual items can't be checked**: "N smaller items", "Not mapped", "macOS", the volume
   bar segments.
7. **Nested checks collapse** to the outermost checked folder (problem 1).
8. **Always confirm in the map** (exists), with names, count and an "up to" size. Not the
   default button.
9. **Honest freed space**: hard-linked and cloned items say they may free nothing.
10. Moves on another volume go to *that* volume's Trash, and Put Back works there too
    (test with a disk image in the build step).

## Privacy and testing

- **Never scan or show the owner's real files in tests, walkthroughs, blind tests or
  committed screenshots.** Everything runs in test mode against fixtures under
  `/tmp/tidy-test` (or the temp folder for unit tests; `Fixture.isSafeRoot` already
  enforces this).
- **A file-system protocol for unit tests.** The walker reads through a protocol (e.g.
  `DirectoryReader`: `entries(ofDirectoryAt:) throws -> [RawEntry]`, where `RawEntry` has
  name, type, allocated, logical, flags, ext flags, dev, file id, link count, clone id,
  mount status and a per-entry error). The real one wraps `getattrlistbulk`; a
  `FakeFileSystem` is an in-memory tree built from a tiny DSL. Unit tests cover: sums,
  folding and top-K, hard links once, full clones once, partial clones, dataless (0 on
  disk, logical reported), sparse and compressed, packages, unreadable folders (partial,
  "+"), mount points skipped, firmlink path mapping, a folder of 1 M entries (memory stays
  flat), cancellation at random points (no partial node is published as final), the order
  of incremental snapshots, the nested-check rules, and every new policy refusal.
- **Synthetic trees on disk** for integration tests and the benchmark:
  `tidy-tool fixtures --map-tree [files]` builds real clones (`clonefile`), hard links
  (`link`), sparse files (`ftruncate`), packages, a `chmod 000` folder and deep and wide
  folders under `/tmp/tidy-test/maptree`. Dataless files can't be made without a File
  Provider, so they're covered by the fake only.
- **Volumes in test mode**: a `TIDY_VOLUMES` variable lists fixture folders that stand in
  for disks (with fake names and capacities), so the scope pull-down and volume bar never
  show the owner's real disk names (which can be personal) in screenshots. A
  `hdiutil`-created disk image under `/tmp/tidy-test` is fine for testing another volume's
  Trash by hand.
- **The real-Mac benchmark** stays read-only and prints counts, sizes and timings only,
  never names or paths (the existing `tidy-tool bench` rule).
- Logs: the progress line may show the current folder *on screen*, but nothing about the
  scanned paths is written to logs or files.

## UX patterns worth adopting (in our words)

- **Everything you can't see gets a name.** DaisyDisk turns "used minus scanned" into a
  virtual item with a breakdown and an explanation of each part. That makes a familiar
  complaint ("the numbers don't add up") something you can understand. We do it with the
  volume bar and the "Not mapped" tile.
- **Gather first, act once.** A tray that collects items from many folders lets you
  explore freely and decide at the end. The tray shows the running total, so you see what
  you'll get back before you commit.
- **Hover shows, click holds.** GrandPerspective's "hover selects, click locks" makes
  exploring with the pointer fast. We use hover for the details strip and click for the
  selection.
- **The containing folder lights up with the item** (GP), so you always know where you are.
- **Purgeable is not used space.** DD counts purgeable as free by default (like Finder) and
  shows it on request. We show it as its own segment, so neither view lies.
- **The map updates after our own moves** without a rescan (DD, GP; Tidy does this already).
- **A refresh that re-reads only what changed** (GP's FSEvents refresh) is the right
  long-term model for a second look. Later.

## What we won't copy, and what we'll do better

- **Not copying:** the sunburst, DD's colours and its rounded-ring look, CleanMyMac's
  bubbles, any of their names ("Collector", "hidden space", "smaller objects", "Space
  Lens"), their help text, the five-second delete countdown, share and rate prompts, purge
  and snapshot scripts, admin rescans, cloud-account scanning.
- **Doing better:**
  - **Trash plus Put Back instead of permanent deletion.** DD deletes for good, and
    reviewers notice there's no undo.
  - **Results while scanning**, and **Stop keeps what was counted**.
  - **Explanations, not just sizes.** The top Mac Power Users complaint was "it shows where
    the space is, not what it is or whether it's safe to delete". Each locked or special
    row says *why* in one line (belongs to macOS, inside an app, synced with iCloud, a
    clone, hard-linked, purgeable). Known kinds get a short plain label in the details (a
    later pass can share Cleanup's category knowledge: "iOS device backup", "Xcode
    DerivedData", "Docker disk image").
  - **Honest freed space** for clones and hard links ("up to", "may free nothing").
  - **No sandbox gap**: one build, Full Disk Access explained in place. DD's App Store
    build can't see some space, and reviewers have to find that out.
  - **Accessible**: the list is a complete equivalent of the map, and map tiles are
    labelled elements with actions. Neither original says anything about VoiceOver.
  - **Small items aren't a dead end**: "N smaller items" opens.

## Edge cases

- **Huge**: 5 M files; one folder with 1 M entries; 40 levels deep; names at the 255-byte
  limit; a path longer than `PATH_MAX` (walk with `openat` from the parent fd and rebuild
  the path only when it's needed).
- **Empty**: an empty folder ("This folder is empty"); an empty volume; a folder with only
  zero-byte files (the map shows a single "0 bytes" state, not a broken layout).
- **Odd file systems**: exFAT/FAT (no hard links or clones; cluster-sized allocation),
  NTFS read-only (all locked), SMB (no Trash; slow; bulk reads emulated), a disk image
  mounted from a file inside the scanned folder (don't count it twice: mount points are
  skipped, and the .dmg file counts once).
- **Changing while scanning**: files appear or disappear mid-walk (`ENOENT` per entry →
  skip it); a folder becomes unreadable (partial); the volume is ejected (stop, keep a
  read-only map, "The disk was disconnected").
- **Permissions**: Full Disk Access granted or revoked mid-session (re-probe on window
  activation, as now); a removable-volume prompt declined; another user's home folder;
  `chmod 000` folders; SIP folders readable but never movable.
- **iCloud**: Optimise Mac Storage on, with dataless folders and files (no downloads, no
  hang); "Keep Downloaded" folders; Desktop and Documents in iCloud (their contents are both
  protected *and* synced: read-only in the map).
- **Clones and links**: a clone group split across folders (only the first counts, but
  every member is marked); a hard link whose other name is outside the scope (counted here,
  marked "also elsewhere"); a symlink loop (`FTS_PHYSICAL`-style: never follow links).
- **Moves**: a checked item deleted in Finder before Move to Trash ("It's no longer there",
  and the map updates); a name clash in the Trash (system numbering); moving to another
  volume's Trash and then ejecting it (Put Back reports the disk is gone); Put Back after a
  rescan.
- **UI**: a pane narrower than 300 pt (map hides its labels; the list carries on); a very
  wide or tall pane (squarified layout keeps the tiles square); light and dark; inactive
  window (accent turns grey); Reduce Motion (fades only); Increase Contrast (tile borders
  get stronger: `separatorColor` adapts); a long localized path in the details strip
  (middle truncation); right-to-left (the map's layout direction can stay LTR, the list
  follows the system).
- **Sleep and wake mid-scan**: the walk continues or fails per entry. No timeouts that
  would throw the map away.
- **Quit mid-scan**: no prompt (nothing is lost but time). Quit with items checked:
  nothing to ask either; checks aren't a promise.

## Our v1 scope

The test step walks this list item by item (fixtures only).

- [x] Scope pull-down: Home Folder (default), startup disk, other local disks (from
      `TIDY_VOLUMES` in test mode), Recent, Choose Folder… (any folder); drop a folder on
      the page to map it.
- [x] Startup disk: Data volume walked with firmlinked paths, the system volume as one
      locked "macOS" tile, mount points skipped, nothing counted twice.
- [x] Parallel `getattrlistbulk` walker behind a `DirectoryReader` protocol; dataless
      materialization off on its threads; private size only for partial clones.
- [ ] Budgets met (all but the 1 M walk, 1.4–1.6 s here; see Build notes): 200k synthetic tree < 150 ms warm; 1 M < 1 s; first map < 500 ms; Stop
      < 100 ms; 5 M fake tree peak < 400 MB, retained < 150 MB; idle CPU < 0.2 %.
- [x] Results grow while scanning (≤ 4 updates/s), unfinished folders marked "+"; Stop
      keeps a partial map labelled as such.
- [x] Nested treemap (2 levels, header bands, `Spacing.xs` insets, `Radius` tokens) drawn
      in one `Canvas`, at 120 Hz while hovering; tiles < 4×4 pt merged.
- [x] List and map share hover and selection; the details strip shows the hovered or
      selected item at a fixed height.
- [x] Drill down (double-click, Return, `⌘↓`, header band) and up (`⌘↑`, breadcrumb);
      Back and Forward (`⌘[` / `⌘]`).
- [x] "N smaller items" opens (re-reads that one folder) and its items can be checked; the
      group itself can't.
- [x] Volume bar for disk scopes: Mapped / Other used space / Purgeable (separate, dashed,
      explained) / Free; "Not mapped" tile at the disk root; folder totals with "+" when
      partial.
- [x] Sizes on disk; hard links and full clones counted once and marked; dataless counted
      as 0 with "in iCloud" in the details; sparse and compressed explained in the details.
- [x] Checked-items tray: running "N checked · up to X", a popover with Uncheck, Show in
      Finder, Quick Look; nested checks collapse to the outer folder.
- [x] Move to Trash… confirms (names, count, "up to"), moves through `TrashService`, sizes
      update in place, Put Back and `⌘Z` restore them; another volume's items go to that
      volume's Trash.
- [x] Safety refusals, each unit-tested: system paths, package insides, iCloud Drive and
      CloudStorage contents, Mail and Messages, virtual items, changed-since-scan check;
      apps route to Uninstall….
- [x] Without Full Disk Access: notice, locked partial rows, Allow…, "Rescan to include"
      after it's granted.
- [x] Reveal in Finder (`⇧⌘R`), Quick Look (`⌘Y`), Space = check, every action in a menu
      with its shortcut; context menus are text only.
- [ ] VoiceOver (built; `drive tree` not run, screen locked): the list names every row with its size and state; map tiles are labelled
      elements with Open, Check, Show in Finder and Quick Look actions; `scripts/drive tree`
      shows 0 `[unlabeled]`.
- [ ] Light and dark (done, offscreen renders), active window and Reduce Motion (not yet: screen locked); screenshots from fixtures
      only.

## Open questions (owner's call)

1. **Default scope**: keep **Home Folder** as the default (fast, no extra prompts), or make
   the **startup disk** the default like DaisyDisk and Space Lens? My recommendation: Home,
   with the startup disk one click away.
2. **Moving things outside the home folder**: allow external volumes' contents (my
   recommendation: yes, to that disk's Trash), and route `/Applications` apps to the
   Uninstaller. Everything else outside home stays read-only. Agree?
3. **iCloud Drive and Dropbox-style folders**: read-only in the map (recommended, because
   deleting there deletes everywhere), or allow Move to Trash with a stronger warning?
4. **Memory budget**: holding a 5 M-file map can take about 150 MB, above the 120 MB
   window-app budget while the map is shown. Accept a "while a map is open" budget of
   150 MB, released on Start Over (and when leaving the module for 10 minutes)?
5. **Treemap depth**: 2 levels by default (recommended), or 1 like today?
6. **Admin rescans**: skip for good (recommended), or plan a privileged helper later?
7. **Time Machine local snapshots**: list them read-only (`tmutil listlocalsnapshots /`
   needs no root) inside "Other used space", or just explain and link to Time Machine
   settings (v1 plan)?
8. **Tray shortcut**: is `⇧⌘K` (or none) fine for Show Checked Items?
9. **`⇧⌘O`** becoming a section-aware "Choose Folder…" (Large & Old or Space Map): OK?
10. **Saved scans and CSV export**: wanted at all, given they write file names to disk?

## Sources

- DaisyDisk guide: [Understanding the sunburst](https://daisydiskapp.com/guide/4/en/UnderstandingSunburst/),
  [Deleting files](https://daisydiskapp.com/guide/deleting-files),
  [Hidden space](https://daisydiskapp.com/guide/hidden-space),
  [Purgeable space](https://daisydiskapp.com/guide/purgeable-space),
  [Disks overview](https://daisydiskapp.com/guide/disks-overview),
  [Keyboard shortcuts](https://daisydiskapp.com/guide/hotkeys),
  [Tips and tricks](https://daisydiskapp.com/guide/4/en/TipsAndTricks/),
  [Product page](https://daisydiskapp.com/),
  [App Store listing and version history](https://apps.apple.com/us/app/daisydisk/id411643860?mt=12)
- DaisyDisk 4.34.3 bundle, read statically: `Contents/Resources/en.lproj/*.strings`,
  `MainMenu.nib`, `PreferencesWindow.nib` (not copied into the repo).
- GrandPerspective: [Home page](https://grandperspectiv.sourceforge.net/),
  [Help](https://grandperspectiv.sourceforge.net/HelpDocumentation/GrandPerspectiveHelp.html),
  [Creating views](https://grandperspectiv.sourceforge.net/HelpDocumentation/CreatingViews.html),
  [Navigating views](https://grandperspectiv.sourceforge.net/HelpDocumentation/NavigatingViews.html),
  [Control panel](https://grandperspectiv.sourceforge.net/HelpDocumentation/ControlPanel.html),
  [Size differences](https://grandperspectiv.sourceforge.net/HelpDocumentation/HowToExplainSizeDifferences.html),
  [Cloud storage](https://grandperspectiv.sourceforge.net/HelpDocumentation/HowToScanCloudStorage.html),
  [Miscellaneous used space](https://grandperspectiv.sourceforge.net/HelpDocumentation/HowToIdentifyMiscellaneousUsedSpace.html),
  [Show only scanned files](https://grandperspectiv.sourceforge.net/HelpDocumentation/HowToOnlyShowScannedFiles.html),
  [Packages](https://grandperspectiv.sourceforge.net/HelpDocumentation/HowToScanPackages.html),
  [Hangs while scanning](https://grandperspectiv.sourceforge.net/HelpDocumentation/HowToHandleHangsWhileScanning.html),
  [App Store listing](https://apps.apple.com/us/app/grandperspective/id1111570163?mt=12)
- CleanMyMac Space Lens: [Get started](https://macpaw.com/support/cleanmymac/knowledgebase/space-lens),
  [Explore scan results](https://macpaw.com/support/cleanmymac/knowledgebase/space-lens-results);
  earlier parity pass in [`tidy.md`](tidy.md).
- Opinion: [Mac Power Users: "Daisy disk is so dead"](https://talk.macpowerusers.com/t/daisy-disk-is-so-dead/44609),
  [Apple Community: free disk mappers](https://discussions.apple.com/thread/256317534),
  [Dr.Buho: DaisyDisk alternatives](https://www.drbuho.com/review/daisydisk-alternative),
  [G2 DaisyDisk reviews](https://www.g2.com/products/DaisyDisk/reviews),
  [MacKeeper DaisyDisk review](https://mackeeper.com/blog/daisydisk-review)
- Visualisation studies: [Woodburn, Yang & Marriott 2019, arXiv 1908.01277](https://arxiv.org/abs/1908.01277),
  [Stasko & Zhang, InfoVis 2000 (slides)](https://sites.cc.gatech.edu/gvu/ii/talks/infovis00.pdf)
- System behaviour: [Apple TN3150: Getting ready for dataless files](https://developer.apple.com/documentation/technotes/tn3150-getting-ready-for-data-less-files),
  `man 2 getattrlist` / `man 2 getattrlistbulk` (macOS 27.2: `ATTR_CMNEXT_PRIVATESIZE`,
  `ATTR_CMNEXT_CLONEID`, `ATTR_CMNEXT_EXT_FLAGS` with `EF_SHARES_ALL_BLOCKS` /
  `EF_IS_PURGEABLE` / `EF_IS_SPARSE`, `ATTR_VOL_SPACEUSED`, `ATTR_DIR_MOUNTSTATUS`),
  `/usr/share/firmlinks`,
  [Eclectic Light: How can you tell whether a file has been cloned](https://eclecticlight.co/2021/04/02/how-can-you-tell-whether-a-file-has-been-cloned-in-apfs/),
  [Eclectic Light: The arithmetic of free space](https://eclecticlight.co/2026/08/21/the-arithmetic-of-free-space/),
  [Eclectic Light: Where does macOS get its free space figures from](https://eclecticlight.co/2023/04/27/where-does-macos-get-its-volume-free-space-figures-from/),
  [Community gist reading the important-usage capacity key](https://gist.github.com/macshome/82e60671cb42dc6262a73402e5ebe089)
- Performance: [Tempelmann via Michael Tsai: reading directories on macOS](https://mjtsai.com/blog/2019/04/22/performance-considerations-when-reading-directories-on-macos),
  [Healey: Maybe the fastest disk usage program on macOS](https://healeycodes.com/maybe-the-fastest-disk-usage-program-on-macos),
  [filesystem-dev list on fts vs bulk](https://mail-archive.com/filesystem-dev@lists.apple.com/msg00265.html),
  and our own benchmark above.

## Build notes (2026-11-07)

Built in `apps/Tidy` (steps 3–4 of the dev cycle for a feature). Everything ran on synthetic
trees under `/tmp/tidy-test` and Tidy's test mode; no real file of the owner's was scanned,
shown or moved, and the real-home benchmark wasn't run (see Budgets).

### What's built

- **Core (`Sources/TidyCore/Map/`)**: `DirectoryReader` protocol, with `BulkDirectoryReader`
  (`getattrlistbulk`, parsed by the returned-attributes bitmap, one 128 KB buffer per thread,
  `openat` fallback past `PATH_MAX`) and `DatalessPolicy` (`setiopolicy_np` materialization
  off, per scanner thread only). `MapScanner`: dedicated `Thread`s (3–6 by core count), a
  shared LIFO work stack, one store commit per folder, running totals rolled up as each folder
  is read, a pending counter per folder so "final" is exact, hard links and full clones
  counted once (first reached, owner recorded so a rescan can count them again), partial
  clones flagged, dataless items never read (0 on disk, logical size tallied as "in iCloud"),
  packages one item (contents walked without nodes), mount points / other devices / test-mode
  disk stand-ins skipped, excluded (protected) folders kept as locked partial rows, Stop
  between bulk calls with no unfinished folder ever marked final, and Rescan This Folder /
  Show Package Contents splicing a subtree back in. `MapStore`: 64-byte nodes and a name
  arena in `mmap`ed chunks (`Chunks.swift`), all folders but only the top 64 files ≥ 1 MB per
  folder. `MapLayout` (two levels over the existing `Treemap.layout`, now O(1) per step),
  hit-testing and arrow-key neighbours. `CheckTray` (nesting rules), `MapSafety` (locks and the
  last-moment check), `MapVolume`/`VolumeFigures`/`TestVolumes`/`SystemVolumes`/`Firmlinks`/
  `MapPaths`, `SmallItemsReader`, `ItemFacts`. `TrashPolicy` gained `allowedVolumeRoots` (a
  disk's contents, never its root or system folders).
- **UI (`Sources/Tidy/SpaceMap*.swift`)**: scope pull-down (Home Folder, startup disk, other
  disks, Recent with Clear Recent, Choose Folder…) with a used/free line, Full Disk Access /
  "Not mapped" / network notes, folder drop on the intro and the map; results page from the
  first moment of the scan (progress "N items · X", Stop on Esc, "Stopped: partial map" with
  Rescan); volume bar (Mapped / Other used / Purgeable dashed / Free, each with help);
  breadcrumbs with Back, Forward and Up; the list (checkbox, icon, name, bar, size with "+",
  lock / link / clone / iCloud badges, chevrons, "N smaller items" row that opens); the map
  (one `Canvas` for tiles and labels, a second light `Canvas` for the hover highlight so
  pointing never redraws the tiles, header bands, hatched groups, check badges, selection
  ring, accessibility children per first-level tile with Open/Check/Show in Finder/Quick Look);
  the fixed-height details strip; Get Info popover; the tray button and popover; the confirm
  alert; result line with Put Back and Open Trash. Menus: File ▸ Map Folder… (`⇧⌘O`, section
  aware), Get Info `⌘I`, Copy Path `⌥⌘C`, Rescan / Rescan This Folder `⌘R` / `⌥⌘R`; View ▸
  Open `⌘↓`, Enclosing Folder `⌘↑`, Back `⌘[`, Forward `⌘]`, Show Package Contents, Show
  Checked Items `⇧⌘K`.
- **Test data**: `tidy-tool fixtures <root> --map` (map content in the fixture home: exports,
  a sparse VM image, clones, a hard link, 3,000 small files, a `node_modules`, iCloud and
  CloudStorage stand-ins, a photo library, Mail; plus stand-in disks and the `TIDY_VOLUMES`
  value), `tidy-tool map-tree` (synthetic benchmark tree), `TIDY_VOLUMES` in
  `TidyEnvironment`, `FakeFileSystem` (DSL) and `GeneratedFileSystem` (procedural, millions of
  files without disk) in `TidyFixtures`, and a test-mode-only `TIDY_SNAPSHOT_SCRIPT` that steps
  the UI and renders its windows offscreen (used because the screen was locked, below).

### The nine problems in the old code

| # | Problem | Fix |
|---|---|---|
| 1 | Nested checks double counted | `CheckTray`: a checked folder absorbs checks inside it; checking inside a checked folder is refused with a note. Tested. |
| 2 | A class and a `URL` per node; a folder's children all held until it finished | 64-byte nodes in mmap'd chunks, names in an arena, paths rebuilt from ids; per folder only the top 64 files ≥ 1 MB are ever copied. A folder of 1 M files: 1 node chunk (tested). |
| 3 | iCloud downloads during scans | Materialization off on every scanner thread (and small-item and Get Info reads); dataless folders never read; tested with the fake and on a real thread (`getiopolicy_np`). |
| 4 | Nothing shown until done; Stop threw the map away | Results page at once, snapshots up to 4×/s, Stop keeps the partial map ("+", "Stopped: partial map"). |
| 5 | Home or a folder in it only | Any folder, the startup disk (Data volume with firmlinked paths, macOS volume as one locked block), other disks. |
| 6 | "N smaller items" a dead end | Opens: one bulk re-read of that folder, biggest first, each file checkable. |
| 7 | One-level map | Two levels with header bands and `Spacing.xs` insets. |
| 8 | No context for totals | Volume bar, "Not mapped" and "macOS" blocks, "+" for lower bounds, iCloud and unreadable counts in the details. |
| 9 | A SwiftUI view per tile | One `Canvas` (plus a hover overlay), cached layout, hit-testing over rects. |

### Decisions made while building

- **Back and Forward sit in the map's navigation bar** (left of Up and the breadcrumbs), not
  in the window toolbar: Tidy's toolbar always has the module's Start Over chevron, and three
  look-alike chevrons side by side read badly. Still `⌘[` / `⌘]` in the View menu.
- **Private size is read on demand** (Get Info, partial clones only), never during the scan.
  Partial clones count at their allocated size in the map (we can't group them); Get Info
  shows "Frees at least X".
- **Show Checked Items is `⇧⌘K`**; `⇧⌘O` is section aware (Map Folder… in Space Map).
- **No automatic release after 10 minutes away**: losing a map you were working with is
  worse than holding ~25–40 MB; Start Over releases it (the owner's 150 MB allowance holds).
- **Top-level home folders stay locked** in the map (existing `TrashPolicy` rule); their
  contents can be checked.
- **Space has no menu key equivalent** (it would steal Space from the search field); Check
  and Uncheck are in every context menu, Space works in the list and the map.
- **Layout runs on the main actor**, cached per folder, version and size: 0.15 ms for 2,067
  tiles in release, so a background hop would only add a frame of lag while resizing.
- **Time Machine disks**: only non-browsable volumes are hidden; detecting a backup disk
  without reading it is not verified.
- **Drop**: a `dropDestination` on the intro and the map (the intro keeps the module hero
  layout rather than becoming a `DropZone`).
- **Test mode**: the excluded Trash fixture folder shows the "Needs Full Disk Access" lock
  reason (only in test mode; the real `~/.Trash` is a protected folder).

### Budgets (2026-11-07, this Mac: Apple silicon, macOS 27.2, internal SSD, load 7–23 from other builders)

| Metric | Budget | Measured | |
|---|---|---|---|
| Walk, synthetic 200k tree, warm | < 150 ms | **82 ms** (6 threads; 84 ms with 3, 111 ms with 4); 230–250 ms when other processes had evicted the vnode cache | pass (warm) |
| Walk, synthetic 1 M tree | < 1 s | **1.43–1.58 s** (6 threads), the app 1.57 s | **miss**: this Mac's vnode cache holds 263,168 vnodes, so 1 M files can't be warm. A single-threaded walk asking only for names takes 5.3 s and `du` 10 s on the same tree; ours is 6.5× faster than `du`, and more threads don't help (kernel-bound: 4.4 s of system time). |
| Real home, cold | < 10 s | not run | the brief forbids scanning the owner's files; `tidy-tool bench map ~` prints counts only if the owner wants it |
| First map after Scan | < 500 ms | **99 ms** (fixture), 216–248 ms (200k and 1 M trees) | pass (test-mode timing log) |
| Updates while scanning | ≤ 4/s | 4/s (250 ms poll, first at 120 ms); each copies one folder and its biggest children | pass |
| Stop | < 100 ms | ≤ 0.2 ms (`bench stop`, 4 points in a 2 M generated walk); unit test at 4 random points | pass |
| Memory, 5 M files | peak < 400, retained < 150 MB | generated 5.09 M files / 300k folders / 899k nodes: **peak +66 MB, retained +67 MB**, +1 MB after release | pass |
| Memory, 1 M files | retained < 60 MB above baseline | store 1–5 MB for the 1 M tree (11k nodes); 1.2 M generated files with 300k folders: 22 MB. The app with a 1 M map shown, settled: 84–94 MB vs 58 MB idle (+26–36 MB including the drawn UI) | pass |
| Idle with the map shown | CPU < 0.2 % | 0.15 % (22 ms over 15 s, 1 M map) | pass |
| Idle after Start Over | < 120 MB | 68.9 MB | pass |
| Layout, ≤ 2,000 tiles | < 4 ms | 0.15 ms (2,067 tiles, release) | pass |
| Drawing and hover at 120 Hz | < 8.3 ms/frame | not measured | the screen was locked (no display, no Instruments trace); hover redraws only the overlay canvas |

A note on memory while drawing: with the display locked, CoreAnimation keeps every frame's
surfaces until the window is composited, so the app showed ~280 MB of "graphics" footprint
while the map updated and dropped back seconds after it stopped. A 40-line SwiftUI app
redrawing a `Canvas` 4× a second does exactly the same (280 MB, back to 61 MB), so it's the
locked display, not the map. Re-check on an unlocked screen.

### Spikes

- **Purgeable formula** (volume figures only, no names): `volumeAvailableCapacity` 17.97 GB
  matches diskutil's container free space and `df`; `…ForImportantUsage` 28.60 GB, so
  purgeable = 10.63 GB. The system volume's `ATTR_VOL_SPACEUSED` (13.76 GB) matches diskutil's
  "Volume Used Space" for `/`. The bar uses exactly these.
- **Removable-disk prompt, exFAT, another disk's Trash: not run.** `hdiutil` is refused in
  this sandbox ("Operation not permitted"), and mounting a disk while the owner is away could
  leave a Files and Folders prompt on their screen. Listing disks reads only URL resource
  values (no files on them). The parser takes only the attributes a file system returns (exFAT
  returns no clone ids or extended flags, which then read as 0). Moves on another disk go
  through `FileManager.trashItem`; any failure other than permission or "gone" becomes "This
  disk has no Trash. Use Show in Finder to delete it there." To check by hand: a USB stick or an
  exFAT image under `/tmp/tidy-test`, map it, move a synthetic file, Put Back.
- **Network disks**: not checked (no share available).

### Tests and gates

- **Tests**: 143 Swift Testing tests in 24 suites (55 new in 7 map suites: scanner on the fake
  and on real temp folders, layout, tray, safety, volumes, paths), all passing.
- `scripts/check.sh Tidy --perf` (final run): Tidy lint, icon, **test**, bundle, smoke and perf
  **pass** (launch 130 ms, first window 354 ms, idle CPU 0.017 %, 60.6 MB; load 14). The run
  still exits 1 on one **SlopKit** test (`Clipboard paster on quit › restoresPendingRightAway`),
  which belongs to another builder's uncommitted `TextInsertion` work and wasn't touched here.
- **Walkthrough with `scripts/drive`: blocked.** The screen was locked for the whole session
  (`CGSSessionScreenIsLocked`), so Accessibility sees no windows, `scripts/drive tree` can't
  list controls and ScreenCaptureKit can't capture. Instead, the real release build was stepped
  through every v1 flow with the test-mode snapshot script and its windows rendered offscreen
  (inactive-window look; the sidebar's material renders black offscreen): intro (home, startup
  disk, disk with bar), scanning, stopped partial map, startup disk with macOS and Not mapped,
  nested map with header bands, hover highlight of block and folder, details strip, smaller
  items opened and checked, nesting note, Get Info for a clone and a hard link, iCloud lock,
  sparse file, absorbed check, tray popover, confirm alert, moved with sizes updated, Put Back
  (`⌘Z`) restoring, another disk's move, a read-only disk, light and dark. Two crashes and
  several layout defects were found and fixed this way (below). **Still to do on an unlocked
  screen**: `scripts/drive` walkthrough, `scripts/drive tree` for `[unlabeled]` controls,
  active-window shots, real hover and drag-drop, Reduce Motion.

Defects found in the offscreen pass and fixed: a crash pairing old tiles with new items in
the accessibility children (the layout is now an immutable value per render); an infinite
recursion in Scan; list rows squeezing names ("Ap…ns"); canvas labels truncated by a guess
(now measured, middle-truncated, cached); narrow header bands showing only a size (the name
wins); the previous map's move result lingering on a new map; the list pane collapsing to
260 pt.

Screenshots (not committed): `/tmp/tidy-test/shots/a/*.png` (light: intro, map, nested,
smaller items, checks, tray, confirm, moved, undone), `/tmp/tidy-test/shots/b/*.png` (dark:
home, hover, Get Info, iCloud, sparse, absorbed, disks, read-only, scanning, stopped),
`/tmp/tidy-test/shots/c/*.png` (stopped partial map), `/tmp/tidy-test/shots/d/d01-1m.png`.

### Deferred

- Pinch to open/close, colour by kind, saved scans and export (owner: never), FSEvents
  refresh, Open in Terminal / Disk Utility, live free-space refresh, whole-map search: `later`
  as in the inventory.
- Time Machine disk detection beyond "not browsable"; the removable-disk, exFAT and network
  checks above (need a disk or share and the owner nearby).

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.

### Round 1 (<date>)
| Finding | Severity | Decision | Why / fix |
|---|---|---|---|

## Owner decisions (2026-11-07)

- **Synced folders (iCloud Drive, Dropbox, Google Drive…) are read-only** in the map: sizes shown,
  no checking or trashing there; Reveal in Finder instead.
- **Memory:** up to ~150 MB while a large map is open is fine (all folders, top 64 files per folder).
- **Never save scans**, no CSV export: scans live only in memory.
- Other open questions: take the doc's recommendations (Home by default with the startup disk one
  click away, other disks trash to their own Trash, apps go to the Uninstaller, two treemap levels,
  no admin scanning, Time Machine snapshots explained rather than listed).
