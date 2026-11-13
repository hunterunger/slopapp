# Crate

Open, preview and make archives.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to Archiver.

**Status:** beta (0.3.0)

## What it does

Drop something on the window (or the Dock icon, **Open…** ⌘O, Finder's **Open With**):

- **One archive → you see what's inside.** A Finder-style list with folders you can expand
  (←/→), sizes, dates and kinds, ⌘F to filter, Space for Quick Look, ⌘↓ or double-click to
  open a file. The actions sit top right: **Close**, **Split**, **Convert**, and **Extract**
  (Return), which unpacks next to the archive (or the selection, if you selected items).
  The archive's name and size are centered along the bottom, next to **Extract to:** (Next
  to Archive, Ask Each Time, Desktop, Downloads, or recent folders). Drag rows straight
  into Finder to copy just those.
- **When it's done**, the window lists what was made. Drag those items anywhere, **Show in
  Finder**, **Back** to the archive, or **Done** (Return) to start over.
- **Several archives (or hold ⌥ while dropping/opening) → they're extracted right away**,
  several at once, one row each with progress and Show in Finder. Settings can make
  "extract right away" the default (then ⌥ shows the contents instead).
- **Anything else → a new archive.** Review the list (+ / − to add or remove), press
  **Compress** (Return), then pick a format card (Zip, 7z, Tar.gz, Tar.xz), name,
  compression (None / Fast / Normal / Best), **Encrypt** with a password, an optional split
  size and where to save it. **Create** (Return). Settings can skip the list.

Reads zip (zip64, AES and ZipCrypto passwords), **7z (including password-protected, with or
without hidden file names)**, RAR 4/5 (including solid), tar, tar.gz, tar.bz2, tar.xz,
single-file .gz/.bz2/.xz, plus cpio, xar, cab, lha, iso and deb. Split sets (`.7z.001`,
`.zip.001`, `.z01` + `.zip`, `.part1.rar`, `.rar` + `.r00`) open from any part; a missing
part is named.

**Convert** (⌘K) repacks an open archive in another format (RAR or 7z → Zip, or Zip → an
encrypted 7z). **Split** (⌥⌘S) cuts an archive, or any single file you drop, into `.001`,
`.002`… parts. **Join Parts** (⌘J, or File ▸ Join Split Files… ⌥⌘J) puts a `.001` set back
together into one file.

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
- **Passwords are only stored if you ask.** By default they're kept in memory while the
  archive is open. With Settings ▸ Advanced ▸ "Remember passwords in the Keychain" (or the
  same checkbox in the password sheet), passwords that work are saved in one Keychain item
  and tried first on the next locked archive. "Forget All…" removes them.
- **Move Archive to Trash** (Settings ▸ General ▸ After extracting, off by default) only happens
  after a complete extraction with nothing skipped, and Edit ▸ Undo puts it back. Crate never
  extracts into a Trash: an archive opened from the Trash extracts to ~/Downloads, and
  trashed archives drop out of Open Recent.

## Passwords

### Password-protected 7z

Crate opens and makes AES-256 encrypted 7z archives itself. libarchive (which reads
everything else) can't decrypt 7z, so Crate does 7z's encryption layer on its own: the key
is SHA-256 of the salt, the UTF-16 password and a counter, 2^19 times (7-Zip's scheme), and
the data is AES-256-CBC through Apple's CommonCrypto. When you open one, Crate decrypts it
on the fly as libarchive reads it, so decompression, listing and every safety check below
work as for any archive, and nothing decrypted is written to disk except the files you
extract. When you make one, libarchive writes a normal 7z and Crate adds the encryption,
laid out the way 7-Zip does it; **Hide file names** (on by default) encrypts the file list
too. Checked both ways against 7-Zip 26.05 (LZMA, LZMA2, PPMd, BCJ, Deflate, Copy, solid
and not, hidden names, split volumes, non-ASCII passwords).

### Why can't Crate open my password-protected RAR file?

RAR uses its own encryption (AES with a different key scheme and header layout) and
libarchive can't decrypt it. Crate says so plainly and lists the contents when the names
aren't hidden. For now, open those with Keka or The Unarchiver.

### Making password-protected zips

Zip passwords offer **Strong (AES-256)** (default; macOS Archive Utility and Windows
Explorer can't open these, 7-Zip, Keka and The Unarchiver can) or **Compatible (ZipCrypto,
weak)**. Tar archives can't have passwords.

## Split archives

The archive is written, then cut into `name.zip.001`, `.002`… (the 7-Zip convention).
7-Zip, Keka, The Unarchiver and Crate open these; Archive Utility doesn't. Split also
works on an archive you've opened, or on any one file (a video, a disk image) dropped on
the window: Split shows next to Compress. **Join Parts** puts any `.001` set back together.

## Shortcuts

| | |
|---|---|
| ⌘O | Open an archive, or files to compress |
| ⌥⌘J | Join split files… |
| ⌘K | Convert the open archive |
| ⌥⌘S | Split into parts… |
| ⌘J | Join the open `.001` set |
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

Finder **Services**: "Extract with Crate", "Extract with Crate To…", "Open in Crate" and
"Compress with Crate".

## Permissions and privacy

None. Crate reads what you give it and writes next to it (or where Settings says). No
network. It registers as an *alternate* app for archive types and never asks to become the
default; Settings ▸ General ▸ File types ▸ Choose… lets you pick which types open in Crate.

## What's not there yet

Opening encrypted RAR, a grid (icon) view, editing an archive in place, legacy filename
encodings (CP437/Shift-JIS) menu, a Finder Quick Look extension, Shortcuts actions.

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

Test environment variables: `CRATE_TRASH_DIR=/some/folder` makes Move Archive to Trash
move archives into that folder instead (and treats it as a Trash);
`CRATE_DOWNLOADS_DIR=/some/folder` replaces ~/Downloads as the fallback for archives in the
Trash; `CRATE_APPEARANCE=light|dark` forces the appearance for screenshots;
`CRATE_PASSWORDS_FILE=/tmp/x.json` keeps remembered passwords in that file instead of the
Keychain (tests only); `CRATE_DRY_DEFAULTS=1` makes Settings ▸ File types pretend instead
of changing which app opens archives; `CRATE_SNAPSHOT_DIR=/tmp/shots` lets a test write a
name into `/tmp/shots/request` to get Crate's own windows rendered to `/tmp/shots/<name>.png`
(works on a locked screen, sees nothing but Crate). `CRATE_7ZZ=/path/to/7zz scripts/test.sh Crate` adds
the interop tests against the real 7-Zip.

The system **liblzma** (`/usr/lib/liblzma.5.dylib`) decodes 7z headers through
`Sources/CLZMA/crate_lzma.h`, the same way. The 7z encryption code is ours
(`Sources/CrateCore/SevenZip/`), from 7-Zip's public format notes.

Design follows [`docs/design-system.md`](../../docs/design-system.md). Shared pieces
(Settings, About, DropZone, FileQueue, HUD) come from SlopKit.
