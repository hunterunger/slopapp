# Tidy

Uninstall apps completely and clear out the junk.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to CleanMyMac.

**Status:** beta (0.2.0)

## What it does

- **Uninstall**: pick an app (from the list, by dropping it on the window, or `⌘O`) and see
  every file it keeps, grouped by kind, with sizes and paths. Uncheck anything you want to
  keep (uncheck the app itself to reset it), then Move to Trash. Running apps are asked to
  quit first. Apps that are part of macOS are never removed.
- **Leftovers**: files from apps that are no longer installed. Nothing is checked until you
  check it.
- **Junk**: app caches, logs, crash reports, Xcode derived data, device support files,
  simulator caches, archives and package manager caches, with sizes.
- **Large & Old**: big files in your home folder, filtered by size, last use and kind.

Everything goes to the Trash after you review it, and Put Back (`⌘Z`, or File ▸ Recently
Moved to Trash…) brings it back while it's still there, even after you quit and reopen Tidy.
If something with the same name has taken its place, Keep Both puts it back as
"Name (restored)". Tidy never deletes anything permanently, never claims to speed up your
Mac, and doesn't scan for malware.

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
- **Not in v1:** an administrator password prompt (locked items get Show in Finder),
  removing Apple's App Store apps, deleting unavailable simulators, stopping loaded launch
  agents, Choose Folder outside the home folder.

## Permissions

- **Full Disk Access** (optional): lets Tidy measure and move app containers macOS protects,
  and look in Desktop, Documents and Downloads for large files without macOS asking about
  each folder. Without it, those items are shown locked and skipped.
- Items in `/Library` and apps owned by root need an administrator: Tidy shows them locked
  with Show in Finder, so Finder can ask for your password.

## Keyboard

`⌘1`–`⌘4` sections · `⌘F` search · `⌘0` show the window · `⌘O` choose an app · `⇧⌘O` choose a folder for large files ·
Space check/uncheck the selected rows · `⌘⌫` Move to Trash (asks first for uninstalls) ·
`⌘Z` / `⇧⌘Z` undo/redo a move (File ▸ Recently Moved to Trash… for earlier ones) ·
`⌘Y` Quick Look · `⇧⌘R` Show in Finder · `⌘R` scan again

## Develop

```sh
scripts/test.sh Tidy     # unit tests (fixtures under /tmp/tidy-test/unit)
scripts/check.sh Tidy    # the full gate
apps/Tidy/Scripts/make-fixtures.sh   # a fake Mac in /tmp/tidy-test to try it on
```

**Test mode.** Setting any `TIDY_*` variable makes every scan and every move stay inside
the given folders (see `Sources/TidyCore/TidyEnvironment.swift`):

```sh
scripts/drive launch build/Tidy.app \
  --env TIDY_HOME=/tmp/tidy-test/home --env TIDY_APPS_DIRS=/tmp/tidy-test/Applications \
  --env TIDY_TRASH_DIR=/tmp/tidy-test/Trash --env TIDY_SYSTEM_LIBRARY=/tmp/tidy-test/Library \
  --env TIDY_RUNNING_IDS=com.fixture.Busybee
```

Optional: `TIDY_ASSUME_FULL_DISK_ACCESS=1` (test mode only), `TIDY_APPEARANCE=dark|light`.
`swift run -c release --package-path apps/Tidy tidy-tool bench` times every scan read-only
and prints only counts, sizes and timings.

Logic lives in `Sources/TidyCore` (tested), fixtures in `Sources/TidyFixtures`, views and
wiring in `Sources/Tidy`.
