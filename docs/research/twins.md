# Twins research (inspired by Gemini 2)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied: Gemini 2
> (MacPaw; not installed on this Mac: the `/Applications/Gemini.app` here is Google's
> unrelated assistant) from its product page, App Store listing, reviews and its full
> 33-page user guide, plus the open-source czkawka (MIT core) for scanning strategy and
> the APFS headers in the macOS SDK, on 2026-11-03. We never copy its name, icons,
> artwork, wording, sounds or signature visuals.

## The job

Twins finds files that are byte-for-byte copies of each other in folders you choose, and
helps you remove the extra copies safely. People reach for it when the disk is filling up
or a folder has become a mess of "photo (1).jpg", re-downloaded installers and duplicated
project folders. "Done" is space back, every file still present at least once, and
nothing removed that can't be put back.

The one interaction that matters most: **drop a folder, wait a few seconds, see the
duplicate groups sorted by wasted space with the extra copies already ticked, press Move
to Trash, and know it's undoable.**

## Who and when

- Downloads folder full of repeated installers and PDFs.
- Photo exports copied into several project folders.
- Merging an old backup drive into the current Mac.
- A shared project folder with duplicated assets.

Frequency: once a month or less; a session lasts 1–10 minutes.

## Feature inventory

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Choose locations | Start screen with + (recommended locations or a folder), drop folders/drives, Finder Service | must | `DropZone` window (drop-in archetype) + ⌘O "Choose Folders…". Multiple folders; overlapping folders deduplicated. |
| 2 | Exact duplicate detection | Compares content plus metadata | must | See hashing strategy. Byte-identical content only, regardless of name. |
| 3 | Similar files (photos/audio) | Finds near-identical files (burst photos), not auto-selected | later | Vision `VNGenerateImageFeaturePrintRequest` distances locally. Never auto-selected. |
| 4 | Photos / Music libraries | Opens and scans libraries; removal via a Photos album | skip | Library packages are databases; deleting inside them corrupts them. Packages are opaque by default. |
| 5 | Summary | Chart of wasted space by category; Smart Cleanup button | must (summary line) / skip (chart) | "214 duplicates in 61 groups · 3.2 GB can be freed". |
| 6 | Groups list + preview | List or grid; disclosure per file; preview pane; sort by size/name/count | must | Sort by wasted space (default), size, name, count. Each group shows its copies: path, modified date, a checkbox. Space = Quick Look; ⌘R reveal. |
| 7 | Auto-selection | Smart Selection learns from your choices; filters Newest/Oldest/Any; Always/Never Select folders | must (simple, explainable rules) / skip (learning) | Default rule: keep the oldest copy (ties: shortest path); "Keep copies in…" preferred folder; per-group menu: Keep Oldest / Newest / This One. Deterministic and explained per group. |
| 8 | Never remove the last copy | Warns and requires a checkbox to select every copy | must | Hard invariant in the core: a group can't have all copies selected. The UI simply won't allow it. |
| 9 | Difference hints | Icons show which metadata differ (dates, names, paths) | should | Highlight the differing parts of paths and dates. |
| 10 | Removal | Trash (default), move to folder, delete permanently; remove empty folders; replace with hard links | must (Trash + undo) / later (replace with APFS clone) / skip (permanent delete) | `FileManager.trashItem`, recording the resulting URL for ⌘Z / "Put Back". Volumes without a Trash: the button says "Delete…" and confirms. |
| 11 | Restore after removal | "Put Back" per file or all, only within the session | must | ⌘Z and a "Put Back All" button after removal; works across app restarts by keeping the last removal's log. |
| 12 | Ignore list | Files, folders, extension groups; per-item checkbox | should | Ignored folders/extensions in Settings. Defaults: `.git`, `node_modules`, `Library`, packages. |
| 13 | Minimum file size | General preference | must | Default 1 KB (skips trivia and empties). |
| 14 | Hard links | Option to treat hard links as ordinary files when auto-selecting | must | Same `(dev, inode)` = one file, never a duplicate (no space to gain). |
| 15 | APFS clones | Not addressed | must | Clones share blocks: trashing one frees ~nothing. Use `getattrlist` `ATTR_CMNEXT_PRIVATESIZE` (private bytes) to report real reclaimable space; label clones "Shares storage". |
| 16 | Duplicate folders | Whole duplicated folders as one group | later | |
| 17 | Duplicates Monitor | Menu bar helper watching folders, notifies on new copies | skip | Background work and notifications for a rare need. |
| 18 | Achievements, ranks, learning, activation | Yes | skip | Not our style. |
| 19 | Stop/rescan | Stop button, Start Over | must | Cancel mid-scan discards partial results; Rescan ⇧⌘R. |
| 20 | Search within results | Type to filter groups | should | `.searchable` filters by name/path. |
| 21 | Export list | Not offered | later | CSV of groups. |

### Must-haves, counted

1 locations, 2 exact detection, 5 summary, 6 groups + Quick Look, 7 simple auto-selection,
8 keep-one invariant, 10 Trash, 11 undo/Put Back, 13 min size, 14 hard links, 15 clones,
19 cancel/rescan. Twelve, most small; the work is #2 and #15.

## Hashing strategy

1. **Walk** chosen folders with `FileManager.enumerator` (`skipsPackageDescendants`,
   hidden files skipped by default), prefetching `fileSize`, `isRegularFile`,
   `fileResourceIdentifier`, `volumeIdentifier`. Skip symlinks, zero/minimum-size files,
   ignored names. Collapse hard links by resource identifier.
2. **Group by size.** Unique sizes are done (usually > 90% of files, zero reads).
3. **Head hash**: SHA-256 (CryptoKit) of the first 16 KB; split groups.
4. **Tail/middle sample** for files > 1 MB: last 16 KB; split again (catches same-header
   media and installers cheaply).
5. **Full hash** of the survivors, streaming 1 MB chunks, a few files in parallel per
   volume (2 on spinning/network volumes, 4–8 on SSD).
6. Optional final **byte compare** isn't needed with SHA-256; skip it.
7. **Cache** `(path, size, mtime, inode) → full hash` in Application Support so rescans
   are near-instant; invalidated by any change.
8. Off the main actor, cancellable, progress by phase ("Listing 41,203 files…",
   "Comparing 1,912 candidates… 38%").

## Key flows

### Flow 1: find and remove (main job)
1. Open Twins: a drop zone ("Drop folders to check for duplicates", or Choose Folders… ⌘O).
2. Drop ~/Downloads. Scan starts immediately; progress by phase; Esc/Stop cancels.
3. Results: summary line, then groups sorted by wasted space, extra copies ticked (the
   copy to keep is marked "Keep" with the rule shown: "oldest").
4. Review: Space previews, ⌘R reveals, change the kept copy with a click.
5. Move to Trash (⌘⌫). No confirmation (it's undoable). A bar: "Moved 214 files to the Trash · 3.2 GB" with Undo. ⌘Z puts
   everything back.

### Flow 2: first run
1. The drop zone is the onboarding. No permission prompt up front; if a chosen folder is
   protected (Desktop/Documents/Downloads), macOS's own folder prompt appears once.
2. Choosing the whole home folder explains it may take a few minutes and skips Library
   and packages unless turned on.

## Settings inventory

| Setting | Default | Options | Keep? |
|---|---|---|---|
| Minimum file size | 1 KB | 0, 1 KB, 100 KB, 1 MB, 10 MB | must |
| Keep which copy | Oldest | Oldest, Newest, Shortest path | must |
| Prefer keeping copies in | none | folder list | should |
| Skip | `.git`, `node_modules`, Library, packages, hidden files | folders/extensions | should |
| Include hidden files / look inside packages | off / off | toggles | should |

## Menus and shortcuts

File: Choose Folders… ⌘O · Rescan ⇧⌘R · Stop Scan ⌘. · Start Over. Edit: Undo ⌘Z ·
Select Suggested · Deselect All ⇧⌘A. Selection: Keep Oldest / Newest / This Copy. Actions:
Move to Trash ⌘⌫ · Quick Look Space · Show in Finder ⌘R. ⌘F filters groups.

## Permissions and system integration

- No Full Disk Access requested. Folder-level macOS prompts for protected folders appear
  only when the user chooses them. Files the scan can't read are listed as "Skipped (no
  access)" rather than failing the scan.
- No network. No background helper.

## UX patterns worth adopting

- **Safe by default**: only exact copies auto-selected; similar files never are.
- **The last copy is untouchable.**
- **Undo right after removal**, in the same window.
- **Sorted by what you gain**, so the first screen holds most of the value.

## What we won't copy, and what we'll do better

- Not copying: name, icon, pie-chart summary, achievements, learning selection, monitor,
  Photos/Music library scanning, subscription.
- Better: honest reclaimable space (hard links and APFS clones counted correctly; Gemini
  even offers to create hard links but never reports clones); explainable selection rules
  instead of "it learns"; undo that survives a relaunch; package contents left alone.

## Edge cases

- Hard links, APFS clones, symlinks/aliases (never followed into loops), firmlinks.
- Packages (.app, .photoslibrary, .bundle) treated as single items, not scanned inside.
- Files changing during the scan (size/mtime recheck before trashing; skip if changed).
- Files in use / locked (`uchg`) / no permission: skipped with a reason.
- External, network and FAT/exFAT volumes (no Trash on some: confirm permanent delete);
  volume ejected mid-scan.
- iCloud Drive placeholders (dataless files): never download to hash; skip with a note.
- 1M files: memory stays bounded (no per-file objects beyond size groups), UI stays live.
- Case-only name differences, Unicode-normalization twins (NFD/NFC) of the same path.
- Same folder dropped twice / nested folders: each file once.

## Our v1 scope

- [ ] Drop/choose folders; scan with phased progress; cancel.
- [ ] Exact duplicates via size → head/tail → full SHA-256, with cache.
- [ ] Hard links collapsed; APFS clones flagged with real reclaimable size.
- [ ] Groups sorted by wasted space; Quick Look, reveal, filter.
- [ ] Auto-selection by rule (oldest default), never all copies.
- [ ] Move to Trash with undo/Put Back (also after relaunch); confirm only where no Trash.
- [ ] Settings: General (minimum size, keep rule, skips), About.
- [ ] Unit tests and a fixture builder (`apps/Twins/Tools/make-fixtures.sh` → `/tmp/twins-fixtures`): identical files with different names, same-size-different-content, same head different tail, hard links, `cp -c` clones, zero-byte, packages, symlink loops, unreadable file, nested overlap.
- [ ] Walkthroughs and blind tests scan **only** generated fixture folders, never the owner's files.

## Open questions

Decisions (owner defaults, 2026-11-03: native, fast, private, no network):

1. **Similar photos:** later (Vision feature prints, never auto-selected).
2. **Photos/Music libraries:** skip; packages are opaque.
3. **Permanent delete:** not offered except on volumes without a Trash, with confirmation.
4. **Replace duplicates with APFS clones** (frees space, keeps every path): later, a
   strong "do better" candidate.
5. **Hash:** SHA-256 via CryptoKit (no dependency); revisit only if profiling shows hashing,
   not disk I/O, is the bottleneck.

## Sources

- [Gemini 2 product page](https://macpaw.com/gemini)
- [Gemini 2 user guide (PDF)](https://cdn2.macpaw.com/manuals/Gemin-2-User-Guide-29062021.pdf)
- [Macworld review](https://www.macworld.com/article/2434914/gemini-2-duplicate-file-finder-review.html)
- [Gemini 2 on the Mac App Store](https://apps.apple.com/cz/app/gemini-2-the-duplicate-finder/id1090488118?mt=12)
- [czkawka](https://github.com/qarmin/czkawka)
- macOS SDK `sys/attr.h` (`ATTR_CMNEXT_PRIVATESIZE`, `ATTR_CMNEXT_CLONEID`, `ATTR_CMNEXT_CLONE_REFCNT`).

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.
