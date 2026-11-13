# Tidy

Uninstall apps completely and clear out the junk.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to CleanMyMac.

**Status:** beta (0.2.0)

## What it does

Tidy is laid out like the cleaner it replaces: a sidebar of modules, each opening on a page
with one big round button, then result tiles with Review, then a checkable review list.

- **Smart Scan** (`⌘1`): one scan across junk, the Trash, leftovers of deleted apps and
  broken background items. Clean moves the checked junk to the Trash; the Trash tile (off
  unless you turn it on) empties the Trash after asking. Everything else is for review.
- **Cleanup** (`⌘2`): System Junk (app caches, logs, crash reports, Xcode derived data,
  device support, simulator caches, archives, package manager caches), **Mail Downloads**
  (copies Mail saved when you opened attachments; edited ones start unchecked) and the
  **Trash** (empty it, or erase only some items; always asks first).
- **Maintenance** (`⌘3`): tasks to run when something misbehaves (Flush DNS Cache and
  Rebuild Spotlight Index ask for your password; Reset Quick Look and Clear Font Caches
  don't), **Login Items** your apps carry (with a link to System Settings, where macOS keeps
  their switches), and **Background Items**: your launch agents and the system's launch
  agents and daemons, with their app, whether they're running, and whether their program is
  gone. Broken agents of yours start checked and can be moved to the Trash.
- **Applications** (`⌘4`): the uninstaller. Pick an app (from the list, by dropping it on
  the window, or `⌘O`) and see every file it keeps, grouped by kind, with sizes and paths.
  Uncheck anything to keep (uncheck the app itself to reset it), then Move to Trash. Running
  apps are asked to quit first; apps that are part of macOS are never removed. The
  **Leftovers** tab lists files from apps that are no longer installed; nothing is checked
  until you check it.
- **Large & Old** (`⌘5`): big files in your home folder, filtered by size, last use and kind.
- **Space Map** (`⌘6`): what takes space in your home folder, any folder, the startup disk
  or another disk. A list biggest-first beside a two-level map of blocks sized by space on
  disk; it draws while it scans, and Stop keeps what was counted. Open folders (or a folder's
  "smaller items") to go deeper, check items anywhere (the tray at the bottom collects them),
  then Move to Trash (asks first; another disk's items go to that disk's Trash). Hard links and
  clones count once; iCloud placeholders are never downloaded; synced folders, package
  insides, Mail and Messages are shown but never moved; apps go to the Uninstaller. Scans
  live only in memory.

Everything except emptying the Trash goes to the Trash after you review it, and Put Back
(`⌘Z`, or File ▸ Recently Moved to Trash…) brings it back while it's still there, even after
you quit and reopen Tidy. If something with the same name has taken its place, Keep Both
puts it back as "Name (restored)". Emptying the Trash is the only permanent delete and it
always asks. Tidy never claims to speed up your Mac or free up memory, and doesn't scan for
malware.

### How leftovers are matched

Conservatively: by the app's bundle id (and its own helpers' ids), never by partial names.
Exact folder names count only in Application Support, Caches and Logs, only for distinctive
names (not "Code", "Notes", "Helper"...), and only if no other installed app has that name.
Launch agents count if they run a program inside the app. See `Sources/TidyCore`.

### Deliberate choices

- **Confirmation.** The review pane's Move to Trash button doesn't ask: it acts on the list
  right above it and everything can be put back. ⌘⌫ or the menu item asks before an
  uninstall, because it can fire without looking at the pane. Large & Old doesn't ask either
  (you check each file yourself); Put Back covers mistakes.
- **One window.** Tidy is a single-window utility: closing the window quits it, since
  nothing runs in the background. Window ▸ Tidy (`⌘0`) brings the window forward.
- **Not yet:** an administrator password prompt for moving files (locked items get Show in
  Finder; only the two maintenance tasks use macOS's password prompt, with fixed commands),
  removing Apple's App Store apps, deleting unavailable simulators, stopping loaded launch
  agents (a trashed agent stops after you log out), Trash folders on other disks, Mail's
  stored attachments, a menu bar monitor, app updates, Choose Folder outside the home folder.

## Permissions

- **Full Disk Access** (optional): lets Tidy see inside the Trash and Mail's downloads,
  measure and move app containers macOS protects, and look in Desktop, Documents and
  Downloads (Large & Old, Space Map) without macOS asking about each folder. Without it,
  those items are shown locked or skipped, with a note.
- Items in `/Library` and apps owned by root need an administrator: Tidy shows them locked
  with Show in Finder, so Finder can ask for your password.

## Keyboard

`⌘1`–`⌘6` modules · Return = the big button · `⌘R` scan · `⇧⌘⌫` Empty Trash… · `⌘F` search · `⌘0` show the window · `⌘O` choose an app · `⇧⌘O` choose a folder for large files ·
Space check/uncheck the selected rows · `⌘⌫` Move to Trash (asks first for uninstalls) ·
`⌘Z` / `⇧⌘Z` undo/redo a move (File ▸ Recently Moved to Trash… for earlier ones) ·
`⌘Y` Quick Look · `⇧⌘R` Show in Finder · Space Map: `⇧⌘O` Map Folder…, `⌘↓`/Return open,
`⌘↑` up, `⌘[` / `⌘]` back/forward, `⌘I` Get Info, `⌥⌘C` Copy Path, `⌥⌘R` Rescan This Folder,
`⇧⌘K` Show Checked Items, Esc stops a scan, arrow keys move between blocks in the map

## Develop

```sh
scripts/test.sh Tidy     # unit tests (fixtures under /tmp/tidy-test/unit)
scripts/check.sh Tidy    # the full gate
apps/Tidy/Scripts/make-fixtures.sh   # a fake Mac in /tmp/tidy-test to try it on
```

**Test mode.** Setting any `TIDY_*` variable makes every scan and every move stay inside
the given folders (see `Sources/TidyCore/TidyEnvironment.swift`). Quit any running Tidy
first: while a copy with the same bundle id is running, `drive launch` attaches to it and
ignores `--env`, so you'd be in your real home folder.

```sh
scripts/drive launch build/Tidy.app \
  --env TIDY_HOME=/tmp/tidy-test/home --env TIDY_APPS_DIRS=/tmp/tidy-test/Applications \
  --env TIDY_TRASH_DIR=/tmp/tidy-test/Trash --env TIDY_SYSTEM_LIBRARY=/tmp/tidy-test/Library \
  --env TIDY_RUNNING_IDS=com.fixture.Busybee
```

Optional: `TIDY_ASSUME_FULL_DISK_ACCESS=1` (test mode only), `TIDY_APPEARANCE=dark|light`,
`TIDY_LOADED_LABELS=label,...` (launch items to show as running). In test mode maintenance
tasks never run: they're appended to `/tmp/tidy-test/tidy-maintenance-log.txt`
(`TIDY_TASK_FAIL=flushDNS,...` or `=cancel` simulates failures and a cancelled password
prompt). Emptying the Trash in test mode erases only inside `TIDY_TRASH_DIR`.
`swift run -c release --package-path apps/Tidy tidy-tool bench` times every scan read-only
and prints only counts, sizes and timings.

Space Map in test mode: `tidy-tool fixtures /tmp/tidy-test/mac --map` adds map content and
stand-in disks and prints a `TIDY_VOLUMES` value (stand-in disks with made-up names and
capacities; real disks are never listed in test mode). `tidy-tool map-tree [root] --files N`
builds a synthetic tree; `tidy-tool bench map|fake|stop|layout` measures the walk, memory on a
generated 5 M-file tree, Stop and the layout. `TIDY_SNAPSHOT_SCRIPT` / `TIDY_SNAPSHOT_DIR`
(test mode only) step the UI from a script and render the windows to PNGs, for design review
when Accessibility can't see the screen (see `Sources/Tidy/SnapshotScript.swift`).

Logic lives in `Sources/TidyCore` (tested), fixtures in `Sources/TidyFixtures`, views and
wiring in `Sources/Tidy`.
