# Crate

Open, preview and make archives.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to Archiver.

**Status:** beta (0.2.0)

## What it does

Drop something on the window (or the Dock icon, **Open…** ⌘O, Finder's **Open With**):

- **One archive → you see what's inside.** A Finder-style list with folders you can expand
  (←/→), sizes, dates and kinds, ⌘F to filter, Space for Quick Look, ⌘↓ or double-click to
  open a file. Return (**Extract All**) unpacks it next to the archive. Select items first
  and the button extracts just those; **Extract To…** ⇧⌘E picks a folder; or drag rows
  straight into Finder.
- **Several archives (or hold ⌥ while dropping/opening) → they're extracted right away**,
  several at once, one row each with progress and Show in Finder. Settings can make
  "extract right away" the default (then ⌥ shows the contents instead).
- **Anything else → a new archive.** Pick Zip (default), Tar.gz, Tar.xz or 7z, Fast /
  Normal / Best, an optional zip password, and an optional split size, then Return.

Reads zip (zip64, AES and ZipCrypto passwords), 7z, RAR 4/5 (including solid), tar, tar.gz,
tar.bz2, tar.xz, single-file .gz/.bz2/.xz, plus cpio, xar, cab, lha, iso and deb. Split sets
(`.7z.001`, `.zip.001`, `.z01` + `.zip`, `.part1.rar`, `.rar` + `.r00`) open from any part;
a missing part is named.

**Archive ▸ Convert To** repacks an open archive in another format (RAR or 7z → Zip).

## Safety

- **Nothing is overwritten.** Output goes to a hidden working folder and is moved into
  place under a free name (`photos 2`). Items with the same name inside one archive (or
  names that differ only in case, like `README` and `readme`) all get extracted; the list
  shows the name each will get ("readme 2 was “readme”"). One top-level folder is never nested twice
  (`photos/photos`); several items are wrapped in a folder named after the archive.
- **Hostile archives can't escape.** Entries with `..` or absolute paths, links pointing
  outside the folder, writes through links, devices and FIFOs are skipped (the list says
  so). setuid/setgid bits are dropped.
- **Zip bombs and full disks are stopped**: an archive may unpack to at most 100× its size
  (always allowed up to 1 GB), and 256 MB of free space is kept. Partial output is removed.
- **Quarantine is kept**: files from a downloaded archive keep its `com.apple.quarantine`
  flag, so Gatekeeper still checks apps inside.
- **Passwords are never stored**, only kept in memory while the archive is open.
- **"Move the archive to the Trash after extracting"** (off by default) only happens after a
  complete extraction with nothing skipped, and Edit ▸ Undo puts it back. Crate never
  extracts into a Trash: an archive opened from the Trash extracts to ~/Downloads, and
  trashed archives drop out of Open Recent.

## Passwords

### Why can't Crate open my password-protected 7z or RAR file?

Crate reads archives with the libarchive that ships with macOS, and libarchive can't decrypt
7z or RAR encryption. Crate tells you so instead of failing vaguely, and still lists the
contents when the file names aren't encrypted. For now, open those archives with Keka or
The Unarchiver. Support is the top item for the next version: either decrypting 7z's
AES-256 ourselves (CommonCrypto on top of libarchive's LZMA) or a permissively licensed
library, if one exists. (Bundling 7-Zip isn't an option: its license doesn't fit
Slopapp's MIT/BSD/Apache rule.)

### Making password-protected zips

Zip passwords offer **Strong (AES-256)** (default; macOS Archive Utility and Windows
Explorer can't open these, 7-Zip, Keka and The Unarchiver can) or **Compatible (ZipCrypto,
weak)**. 7z and tar can't have passwords in Crate. **Password-protected 7z and RAR
archives can't be opened yet**: the system's libarchive can't decrypt them. Crate says so
plainly and lists their contents when it can.

## Split archives

The archive is written, then cut into `name.zip.001`, `.002`… (the 7-Zip convention).
7-Zip, Keka, The Unarchiver and Crate open these; Archive Utility doesn't.

## Shortcuts

| | |
|---|---|
| ⌘O | Open an archive, or files to compress |
| ⌘N | New archive from files |
| Return / ⌘E | Extract all (or the selected items) |
| ⇧⌘E | Extract to a folder… |
| ⌘↓ | Open the selected file |
| Space / ⌘Y | Quick Look (follows the selection with the arrow keys) |
| ⌘F | Filter the list |
| ⇧⌘R | Show in Finder |
| ⌘. / Esc | Stop, or cancel a new archive |
| ⇧⌘W | Close the archive |
| ⇧⌘⌫ | Clear the extraction list |

Finder **Services**: "Extract with Crate" and "Compress with Crate".

## Permissions and privacy

None. Crate reads what you give it and writes next to it (or where Settings says). No
network. It registers as an *alternate* app for archive types and never asks to become the
default.

## What's not there yet

Opening encrypted 7z/RAR, making encrypted 7z, editing an archive in place, a "join split
parts" command, legacy filename encodings (CP437/Shift-JIS) menu, a Finder Quick Look
extension, Shortcuts actions.

## Develop

```sh
scripts/test.sh Crate     # unit tests
scripts/run.sh Crate      # build a debug .app and open it
scripts/check.sh Crate    # the full gate: tests, release bundle, launch smoke test
apps/Crate/Tools/make-fixtures.sh   # test archives (incl. hostile ones) in /tmp/crate-test/fixtures
```

Logic lives in `Sources/CrateCore` (tested). Views and wiring live in `Sources/Crate`.
Archives are read and written with the **system libarchive** (`/usr/lib/libarchive.2.dylib`,
BSD-2-Clause), linked through the SDK's `libarchive.tbd`. Apple doesn't ship its headers, so
`Sources/CArchive/crate_archive.h` declares the few functions Crate uses. Nothing is bundled.

Test environment variables: `CRATE_TRASH_DIR=/some/folder` makes "Move the archive to the
Trash" move archives into that folder instead (and treats it as a Trash);
`CRATE_DOWNLOADS_DIR=/some/folder` replaces ~/Downloads as the fallback for archives in the
Trash; `CRATE_APPEARANCE=light|dark` forces the appearance for screenshots.

Design follows [`docs/design-system.md`](../../docs/design-system.md). Shared pieces
(Settings, About, DropZone, FileQueue, HUD) come from SlopKit.
