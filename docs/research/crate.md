# Crate research (inspired by Archiver)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied on
> 2026-11-03: **Archiver 5.1.0 (51000)**, Setapp build (`com.incrediblebee.Archiver-setapp`,
> by Mapache Softworks, formerly Incredible Bee), installed at
> /Applications/Setapp/Archiver.app, read-only. Also studied: its website and support FAQ,
> the Setapp listing and reviews, comparison articles, and what macOS itself provides for
> archives (experiments below). We study how it works so we don't reinvent the wheel. We
> never copy its name, icons, artwork, wording, sounds or signature visuals.
>
> Archiver wasn't running. It was launched, walked through and quit. No setting was
> toggled. Only files made for this study (`/tmp/crate-demo/`: a small zip written by our
> own libarchive experiment and a folder holding two one-line text files) were handed to
> it with `open -a`. It extracted the test zip once into `/tmp/crate-demo/demo`. The
> Settings values shown match the defaults hard-coded in the app's bundled scripts, so the
> Settings table reports real defaults. Archiver 5 is an **Electron** app. Its window
> content isn't exposed to Accessibility, so the File Types and Advanced settings panes
> (which can only be reached by clicking, and mouse use was off-limits) were read from the
> app's bundled view templates, not from the screen.
>
> Launch gotcha for later steps: this shell environment exports `ELECTRON_RUN_AS_NODE=1`.
> With it set, any Electron app launched from here exits immediately. Use
> `env -u ELECTRON_RUN_AS_NODE scripts/drive launch …`.

## The job

Someone has an archive they didn't make: a `.zip` from a client, a `.rar` or `.7z` from a
forum, a `.tar.gz` from GitHub, a 7-part split download. They want to see what's inside
before it spills into Downloads, take just the files they need (or everything), and get on
with it. Less often they go the other way: zip up a folder to email or upload, maybe with
a password, maybe in pieces under a size limit. macOS's Archive Utility already
double-click-extracts zip and tar. People reach for a third-party app when they need RAR or
7z, a **look inside first**, a password, or splitting. "Done" means the files are in a
sensibly named folder next to the archive, with no `__MACOSX` junk and no nested
`folder/folder/`. **The one interaction that matters: drop an archive on the window → its
contents appear instantly as a browsable list → press Return to extract all, or select
some and drag them out.**

## Who and when

- An email or chat attachment arrives (`invoice-docs.zip`, `assets.rar`). Check what's in
  it, then extract.
- A download comes in 7z, RAR or multi-part form (`.part1.rar`, `.7z.001`), often with a
  password from the download page.
- Pull one file out of a large archive (a single font from a 2 GB asset pack) without
  extracting everything.
- Zip a project folder to send, with a password for anything sensitive. Clean zips with no
  `.DS_Store` matter when the recipient is on Windows.
- Split a large file or folder into 25 MB / 100 MB / 4 GB pieces for email, upload limits
  or a FAT32 stick.
- Less common: turn a RAR or 7z into a zip for someone who can't open it.

Frequency: a few times a week, in bursts. Each use takes 5–60 seconds, or longer while a
big archive extracts. Settings get set once.

## How the original is built (relevant facts)

- **Electron app (~570 MB per Setapp), requires macOS 26.** It shells out to bundled
  binaries: `7zz` (7-Zip 24.08, for zip/7z/tar/gz/bz2 and most reading), `unar`/`lsar`
  (The Unarchiver's CLI, for exotic formats such as StuffIt), `unrar` (for RAR), and `duti`
  (to set default file handlers). Creating RAR downloads RARLAB's command-line tool as a
  "plugin" after a license agreement screen. That's only possible outside the App Store.
- Claims **Owner** rank for about 45 archive document types (zip, 7z, rar + r00–r99, tar,
  tgz, tbz, gz, bz2, xz, Z, cpio, pax, xar, pkg, cab, lha/lzh, arj, sit/sitx/sea, hqx,
  jar/war, apk/aar, deb, rpm, exe, adf, zipx, `.001–.099`, `.z01–.z99`, and its own
  `.split`, `.zsplit`, `.chksplit` and `.archiver` formats).
- Registers six Finder **Services**: compress, compress to…, extract, extract to…, extract
  here, convert. These are routed through a private `archiver://` URL scheme. There's no
  Finder extension and no Quick Look extension.
- When creating, it excludes `.DS_Store`. When extracting, it excludes `__MACOSX` and
  `[TOC].xml`. It runs the archivers at lower priority (`nice`) across all CPU cores, and
  auto-renames on name clashes inside the output.
- Its Info.plist includes camera, microphone and Bluetooth usage strings (Electron
  boilerplate). The app never needs them.

## Feature inventory

Priority: **must** (v1 isn't worth shipping without it), **should** (v1 if cheap, else
v1.1), **later**, **skip** (with reason).

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Open an archive | Drop on window or Dock icon, File > Open ⌘O, double-click in Finder (if it's the default app), Service. The drop target decides by content: if every dropped item is an archive, it opens them; otherwise it stages the items for compressing. | must | Same content-based routing. Doc types at **Alternate** rank (never steal from Archive Utility), Open With, Dock drop, ⌘O. |
| 2 | Preview contents | List view: disclosure triangles for folders, file icon, name, size (folders show `--`), archive name in the footer. Alternative grid view of big icons. ←/→ collapse/expand, ↑/↓ move. | must | Native outline (`List`/`OutlineGroup` or `NSOutlineView` for 100k rows): name, size, modified date, kind. Folders show item count and total size. A footer summary ("212 items, 1.4 GB unpacked"). No grid view in v1. |
| 3 | Extract all | Return (Action > Extract). Output goes to the same folder as the archive by default. Multi-item archives are wrapped in a folder named after the archive. Then a "finished" screen with the result as a draggable list, plus Back, Reveal in Finder, Export and Done buttons. | must | Return / ⌘E. Smart destination: one top-level folder → extract it as is (no `x/x/`). Otherwise a folder named after the archive. Never overwrite (numbered suffix). Progress, Cancel, Reveal. |
| 4 | Extract selected | Select rows in the preview and drag them to Finder (copies). Export (E) saves the selection. Double-click opens an item from a temp copy. | must | Select rows → "Extract Selected…" (⇧⌘E, save panel at the archive's folder) **and** drag rows to Finder via file promises. Double-click opens an item from a temp copy. |
| 5 | Quick Look an entry | Space on a selected row: temp-extracts it, then previews. | should | `QLPreviewPanel` on a temp-extracted copy. Cheap once #4 exists. |
| 6 | Password-protected archives | An inline screen with a lock symbol, a "the archive is protected" heading, a password field, a Show Password checkbox, and Cancel/Done. A wrong password re-prompts with a "wrong password" message. Supports header-encrypted 7z/RAR through 7-Zip and unrar. | must (zip) | Inline sheet with SecureField, Show toggle, retry on wrong password. zip AES-128/256 and ZipCrypto work with the system libarchive. **Encrypted 7z and RAR don't** (see Platform); show a clear message. Never store passwords. |
| 7 | Read formats | zip, 7z, RAR4/5, tar (+gz/bz2/xz/Z), cpio, pax, xar/pkg, cab, lha, arj, StuffIt, hqx, jar/apk, deb, rpm, exe (SFX), adf, zipx, iso. | must (core set) | Core: zip (incl. zip64, zipx), 7z, RAR4/RAR5 (incl. solid), tar, tar.gz/.tgz, tar.bz2, tar.xz, single-file .gz/.bz2/.xz. Free from libarchive: cpio, xar/pkg, cab, lha/lzh, iso, ar/deb, jar/war. Skip StuffIt, ARJ, ADF, hqx (legacy, not in libarchive). |
| 8 | Multi-part sets | Drop one or more parts; it finds the rest and opens the set (rar + r00…, partN.rar, 7z.001…, zip.001…, z01…). | must | Drop any part → find siblings by pattern → open with `archive_read_open_filenames`. A missing part gets a message naming it. Verified for `.7z.001`, `.zip.001`, `.z01`+`.zip` and `.partN.rar` (see Platform). |
| 9 | Create an archive | Drop non-archives → staging list (add with +, remove with ⌫, "N Files" footer) → Archive (A) → a "Create Archive: Choose format" screen (a row of big format tiles with a one-line description) + footer: Archive Name (single item → its name, otherwise "Archive"), Compression Level (No Compression / Lowest / **Medium** / Highest), Encrypt checkbox → Password, Repeat password, Show Password → Done. | must | One step, no separate screens. The dropped items appear in a list. A bottom bar holds Format, Password and Save to. A **Create Archive** button (Return). Name defaults the same way. Output goes next to the source, never overwriting. |
| 10 | Formats to create | zip, 7z, RAR (plugin), tar.gz, tar.bz2, tar.Z, tar. | must: zip, tar.gz · should: 7z, tar.xz | Must: zip (default) and tar.gz. Should: 7z (no password, see #11) and tar.xz. Each with a short plain description in its menu ("Opens on any computer", "Smaller, needs 7-Zip on Windows"). Skip tar.Z, tar.bz2 (obsolete), and RAR (proprietary). |
| 11 | Password when creating | Encrypt checkbox for zip and 7z. The website says zip uses classic PKZIP encryption and 7z uses AES-256. | must (zip) | zip AES-256 via libarchive (`zip:encryption=aes256`), with a confirm field and Show toggle. Encrypted 7z isn't possible with libarchive: it **silently ignores** the passphrase. Disable Password for 7z in v1 and say why. AES vs ZipCrypto default: open question. |
| 12 | Compression level | Popup with four levels, Medium by default. | should | Fast / Normal / Best maps to `compression-level`. Default Normal. |
| 13 | Exclude Mac metadata | Leaves out `.DS_Store` when creating and skips `__MACOSX` when extracting. | must | When creating, leave out `.DS_Store`, `._*`, `__MACOSX`, `Icon\r` and resource forks/xattrs by default (clean zips for Windows). When extracting, Apple's libarchive already folds `__MACOSX` AppleDouble entries away (verified). |
| 14 | Split | One non-archive file loaded → Split (S) → "Split Archive: Choose format" tiles (ZIP without compression, the proprietary ZSPLIT, 7ZIP) + Chunk Size field (**10**) + KB/MB/GB popup (MB). Checksum checkbox for its own split format. | should | "Split into parts" option when creating: Off / 25 MB / 100 MB / 1 GB / 4 GB (FAT32) / Custom. Write the archive, then byte-split into `.001`, `.002`… (the 7-Zip convention, which Keka, 7-Zip, The Unarchiver and we can rejoin). Tell the user macOS's Archive Utility can't open split sets. |
| 15 | Combine | Drop split parts → Combine joins them (verifies with its `.chksplit` checksums when present). | later | Opening a split set (#8) covers the common case. A generic "join .001 parts into one file" comes later. Skip its proprietary formats. |
| 16 | Convert | Archive loaded → Convert (C) → "Convert Archive: Choose format" tiles (source format left out) + name/level/encrypt → Done. Extracts to temp and repacks. | should | "Convert to…" in the Archive menu for an open archive. Same bottom-bar options as Create. Cheap once extract and create both exist. Main use is RAR/7z → zip. |
| 17 | After extracting, handle the archive | Settings: Keep archive (default) / Move archive to Trash / Delete archive immediately (with a "can't be undone" note). | should | Keep (default) / Move to Trash. No permanent delete (design system §7). |
| 18 | Output location | Settings: Same folder as input files (default) / Ask me / a chosen folder (Other…). | must (default) · should (setting) | Default: next to the archive. If that folder isn't writable (mounted DMG, read-only share), ask with a save panel. Setting: Next to Archive / Ask Each Time / a chosen folder. |
| 19 | Reveal output when done | Settings "Show output files in Finder", off. For several archives only the last one is shown. | should | Reveal button on every row and a "Reveal in Finder after extracting" setting (off). |
| 20 | Skip preview | Settings "Skip preview" for drag-and-drop extract (off). **Shift while dropping** inverts it for that drop. Also "Skip preview" for creating (off; skips the staging step), with Shift inverting. | should | Hold ⌥ while dropping to extract right away. Finder Service "Extract Here" covers the rest. One setting at most. |
| 21 | Quit when done | Settings, **on**: after archives opened from the Dock or by double-click finish extracting, the app quits (ignored if it was already running). | skip | Design system: the window stays. Closing it quits. |
| 22 | Batch | Several archives dropped at once are previewed or extracted together. The status line shows the last one. | must | Several archives dropped → SlopKit `FileQueue` rows, each extracting in parallel (bounded), with progress, Cancel, Retry and Reveal per row. This is the "Extract Here" path too. |
| 23 | Overwrite warning | Inline screen asking whether to replace when the output name exists, with Cancel/Replace. | must (behaviour) | Never ask. Pick a free name (`name 2`). Undo doesn't apply. Nothing gets overwritten. |
| 24 | Invalid/corrupt archive | Inline screen saying it couldn't be opened, perhaps incomplete or damaged. | must | A row or empty-state error naming the cause (truncated, wrong format, missing part, unsupported encryption) and the next step. If listing fails partway, show what was read. |
| 25 | Inspect app bundles | Advanced setting (off): when browsing extracted results, lets `.app` bundles be expanded like folders. | skip | Niche. |
| 26 | Default app management | Settings > File Types: a checkbox per format (Select all / Deselect all) that sets it as the default handler via `duti`. One review complained it kept asking to be the default (fixed since). | later | One Settings button, "Make Crate the default for archives…", using `NSWorkspace.setDefaultApplication`. Never prompt unasked. |
| 27 | Finder Services | Six items under Finder's Services submenu. A review wished they were at the top level. | should | "Extract with Crate" and "Compress with Crate" Services (like Squish). A top-level Finder Quick Action comes later. |
| 28 | Play sound | On by default when a command completes. | skip | Design system: quiet by default. |
| 29 | Go back to start | Off: after finishing, return to the drop zone automatically. | skip | The queue/browse view is the natural end state. A Clear/Close button handles the rest. |
| 30 | Clean (⌘K) | Removes leftover temp folders after a crash. | skip (as UI) | Clean our temp folder silently on launch. |
| 31 | Grid view | List/grid toggle in the footer. | later | List only in v1. |
| 32 | RAR creation | Downloads RARLAB's `rar` after a license screen. | skip | Proprietary format and tool. Nobody needs to create RAR in 2026. Offer zip/7z. |
| 33 | `.archiver` format | Its own format: pre-compresses images/audio, then xar. | skip | Proprietary, unreadable elsewhere. |
| 34 | Test integrity | Not in Archiver 5 (7-Zip's `t` command is used internally to check passwords). | later | "Verify Archive" reads every entry and checks CRCs. Cheap with libarchive. |
| 35 | Edit inside an archive | Not supported (BetterZip's selling point). | later | Add, delete or rename entries in place. Needs a rewrite of the archive. |
| 36 | Search inside archive | No. | should | ⌘F filters the outline. Matters for archives with thousands of entries. |
| 37 | Filename encoding | Not exposed. The Unarchiver is praised for detecting non-Latin encodings. | later | "Text Encoding" menu for zips with legacy (CP437/Shift-JIS/GBK) names. Edge case below. |
| 38 | Disk images (.dmg) | Not handled by Archiver 5 (Archiver 4 listed it). | skip | Finder mounts DMGs. `hdiutil` exists if ever needed. |
| 39 | Quick Look in Finder | Not provided. macOS has no archive previewer (checked `qlmanage -m`). | later | A Quick Look preview extension listing an archive's contents in Finder. A nice differentiator, but not v1. |
| 40 | Shortcuts / App Intents | No. | later | "Extract Archive", "Create Zip" intents. |
| 41 | Help / feedback | Help (web), Acknowledgements, Send Email…; beta builds show a feedback link in the empty state. | skip | About tab with source link (design system). |
| 42 | Licensing / trial / updates | Register license, trial screens, Updates pane (direct version only). | skip | Not applicable. |
| 43 | Encrypted 7z/RAR (blind test F1) | — | **7z: done in the parity pass**; RAR later | See Parity pass. |
| 44 | Salvage the readable part of a truncated archive | — | later | Blind test round 1. |

**Must rows:** 1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 13, 22, 24, plus two behaviours that come
with them (18: output next to the archive by default; 23: never overwrite). That's 15
items, which become 12 checklist items in the v1 scope. In plain terms that's four
things: open and browse, extract all or some, unlock zip passwords, and create a clean zip
or tar.gz (optionally with a password), all done safely and in batches.

## Key flows

### Flow 1: open and extract (the main job), as Archiver does it
1. Window is 460×306 and shows only a large tray-with-arrow outline symbol. No words, no
   button.
2. Drop an archive on it (or ⌘O, Open With, Dock icon).
3. The window switches to a **preview list**: a disclosure triangle and icon per item,
   name, and size on the right (folders show `--`). The archive's file name sits centred
   in the footer, and list/grid toggles sit bottom right. Top right: a round **Cancel**
   (×) button and a pill holding **Split**, **Convert** and **Extract** icons.
4. Keyboard: ↑/↓ select, ←/→ collapse/expand, Space quick-looks the selection (temp
   extract), and double-click opens an item. Dragging a row to Finder copies it out.
5. Press **Return** (Action > Extract) and it extracts next to the archive. The test zip
   with two top-level items became a folder named after the archive.
6. Finished screen: the result as a list with a "drag the files to your destination" hint.
   The pill now holds **Back**, **Finder** (reveal) and **Export**, next to a round
   accent-coloured **Done** (✓) button that returns to the empty state.
7. With "Skip preview" on (or Shift held while dropping), steps 3–5 collapse into
   drop → extracted. When the archive was opened from the Dock or Finder and "Quit when
   done" is on (the default), the app quits after extracting.

### Flow 2: password-protected archive
1. Drop an encrypted archive. The window shows an inline lock screen: heading, a sentence
   naming the file, a password field (focused), a Show Password checkbox, Cancel and Done.
2. Return submits. A wrong password shows the same screen with a "wrong password, try
   again" line.
3. Archive types with encrypted headers (7z with `-mhe`, RAR with header encryption) ask
   before listing anything. The rest ask on preview or extract.

### Flow 3: create an archive
1. Drop files/folders (anything that isn't all archives). A **staging list** shows them with
   the same outline, a footer with **+** (add more), **−** (remove; ⌫ also works) and an
   "N File(s)" count. The top right holds Cancel and **Archive**.
2. Archive (A or Return) → **"Create Archive: Choose format"**: a horizontally scrolling
   row of big coloured format tiles (ZIP selected, 7ZIP, RAR, TAR.GZ, TAR.BZ, …), the
   chosen format's name and a parenthetical description underneath, then a form: Archive
   Name (pre-filled: the single item's name, otherwise "Archive"), Compression Level
   (Medium), Encrypt checkbox. Ticking Encrypt reveals Password, Repeat password and Show
   Password.
3. Back/forward chevrons top right. Forward/Done creates the archive with a progress
   screen, then the finished screen (Flow 1, step 6).
4. Choosing RAR the first time shows a license-agreement screen and an Install button that
   downloads RARLAB's tool.

### Flow 4: split
1. With one non-archive file loaded (or an archive in preview), Split (S) → **"Split
   Archive: Choose format"**: ZIP (described as "no compression"), ZSPLIT (its own
   format) and 7ZIP tiles. Footer: Chunk Size stepper field (default **10**) + unit popup
   (KB/MB/**GB**, default MB). A Checksum checkbox appears for its own format.
2. Forward → writes the parts next to the source.

### Flow 5: convert
1. Archive in preview → Convert (C) → **"Convert Archive: Choose format"**: tiles for every
   creatable format except the source's (for a zip: 7ZIP, RAR, TAR.GZ, TAR.BZ, …) + the
   same name/level/encrypt form. The name defaults to the archive's base name.
2. Forward → extract to temp, repack, finished screen.

### Flow 6: first run / onboarding
1. No onboarding, no permission prompts. The direct version offers "move to Applications"
   and shows trial/registration screens. The Setapp build skips both.
2. It doesn't ask to become the default archive app on its own any more (a 2026 review
   said earlier 5.0.x builds nagged about this). The File Types pane handles it.
3. Nothing needs TCC permissions: it reads what you drop and writes next to it.

### How Crate's flows should feel (proposal, for build)
- **Empty:** `DropZone`: "Drop an archive to open it, or files to compress", plus "or click
  to choose". ⌘O.
- **One archive dropped → Browse view:** outline + footer summary + bottom bar
  [Extract to: Next to Archive ▾] [Extract All (Return)]. With a selection, the button
  reads "Extract 3 Items". Rows can be dragged out. Space = Quick Look.
- **Several archives dropped (or ⌥-drop, or the "Extract with Crate" Service) → Queue:**
  `FileQueue` rows extracting immediately, each with progress, "1.2 GB → 214 items",
  Reveal, Retry or Cancel. A row needing a password shows an inline "Enter Password…"
  button instead of failing.
- **Anything else dropped → Create view:** list of items (removable) + bottom bar
  [Format: Zip ▾] [Password…] [Split: Off ▾] [Save to: Next to Originals ▾] [Create Zip
  (Return)]. The name field defaults like Archiver's. Done → a FileQueue row with the
  result and Reveal.

## Settings inventory

Archiver 5.1 Settings window ("Archiver Settings", tabs General / File Types / Advanced,
plus Updates in the direct version). Defaults are from the app's code and match the
installed copy.

| Setting | Default | Options | Keep? |
|---|---|---|---|
| Output files to | Same folder as input files | Same folder / Ask me / a custom folder (Other…) | **Yes**: "Save to" (Next to Archive / Ask Each Time / chosen folder) |
| After extracting an archive | Keep archive | Keep / Move to Trash / Delete immediately (with a can't-undo note) | **Yes, minus permanent delete** |
| When a command completes: Show output files in Finder | Off | toggle (only the last archive is shown for batches) | Yes ("Reveal in Finder after extracting") |
| … Play sound | On | toggle | No (quiet by default) |
| … Go back to start | Off | toggle | No |
| Drag and drop extract: Skip preview | Off | toggle; Shift while dropping inverts it | Maybe: ⌥-drop instead, setting only if asked for |
| … Quit when done | On | toggle; applies to Dock/double-click opens when the app wasn't running | No |
| Creating archives: Skip preview | Off | toggle; Shift inverts | No (our create view is already one step) |
| File Types | per type | checkbox per archive type (sets the default app via `duti`), Select all / Deselect all; `pkg` is extension-only | Later: a single "Make Default…" button |
| Advanced: Inspect application bundles | Off | toggle | No |
| Updates: Automatically check for updates | On | toggle + Check Now (direct version only) | No (Slopapp updates are handled elsewhere) |
| *(in the create form)* Compression Level | Medium | No Compression / Lowest / Medium / Highest | Yes, as a bottom-bar option (Fast / Normal / Best), remembered |
| *(in the split form)* Chunk Size | 10 MB | number + KB/MB/GB | Yes, as presets + Custom |

Crate's own Settings (design system §3): **General**: Save to, after extracting
(keep / Trash), reveal after extracting, leave out Mac files when compressing (on),
default zip encryption (if the owner wants it user-visible). **About**. No Shortcuts tab
(no global shortcuts).

## Menus and shortcuts

**Archiver 5.1 main menu** (read with `tree --menu`):

- **Archiver:** About Archiver · Settings… ⌘, · Services · Hide ⌘H · Hide Others ⌥⌘H ·
  Show All · Quit ⌘Q.
- **File:** Open ⌘O · Close Window ⌘W · Close All ⌥⌘W. No Open Recent.
- **Edit:** standard (Undo, Redo, Cut, Copy, Paste, Delete, Select All, AutoFill,
  Dictation, Emoji).
- **Action** (enabled per stage; most shortcuts are **plain keys, no modifier**):
  Clean ⌘K · Archive A (shown with Return when it's the primary action) · Extract Return
  · Combine · Done Return · Cancel Esc · Split S · Convert C · Back B · Export E · Finder F.
- **Window:** standard. **Help:** Archiver Help · Acknowledgements · Send Email…
- In the list: ↑/↓, ←/→ (collapse/expand), Space (Quick Look), ⌫ (remove from the create
  list), double-click (open item).
- No global shortcuts, no menu bar item.

**Crate (proposal):** single-letter shortcuts clash with type-to-select in a list, so use
⌘ combos.

- **File:** Open… ⌘O · Open Recent · New Archive from Files… ⌘N · Close ⌘W.
- **Archive:** Extract All ⌘E (and Return as the default button) · Extract Selected… ⇧⌘E ·
  Quick Look Space / ⌘Y · Reveal in Finder ⇧⌘R · Convert To… (should) · Stop ⌘. ·
  Clear List ⇧⌘⌫.
- **Edit:** Select All ⌘A, Find ⌘F (filter, should).
- **Settings** ⌘, · Quit ⌘Q.

## Permissions and system integration

| Area | Archiver 5 | Crate |
|---|---|---|
| TCC permissions | None used. Info.plist carries unused camera/mic/Bluetooth strings (Electron boilerplate). | None. Don't ship unused usage strings. |
| File access | Not sandboxed (bundles CLI tools, downloads the RAR plugin, runs `duti`). | Not sandboxed (like other Slopapp apps), so sibling volumes and "next to the archive" writes just work. If ever sandboxed: multi-part sets need related-item access and the save panel. |
| Document types | ~45 types at **Owner** rank, with its own exported UTIs. | Zip, 7z, RAR, tar, gz, bz2, xz, tgz, split-part extensions at **Alternate** rank (Open With works, Archive Utility stays the default unless the user chooses). |
| Default app | File Types pane + bundled `duti`. | Later: one button using `NSWorkspace.setDefaultApplication(at:toOpen:)`. |
| Services | Compress / Compress to… / Extract / Extract to… / Extract Here / Convert…, routed through a private URL scheme. | Should: "Extract with Crate", "Compress with Crate" (pattern from Squish's `NSServices`). |
| Finder extension / Quick Look | None. | Later: Quick Look preview extension for archive listings. |
| Quarantine | Not tested in Archiver. | **Must:** extracted files inherit the archive's `com.apple.quarantine` so Gatekeeper still checks downloaded apps. Apple's libarchive does this itself when extracting through `archive_read_extract` (verified), so keep that path. |
| Login item / menu bar | No. | No. |
| Shortcuts | No. | Later. |

## Platform: what macOS gives us (verified 2026-11-03, macOS 27.2, Xcode 27.0)

**Recommendation: build on the system libarchive (`/usr/lib/libarchive.2.dylib`, version
3.7.4), linked through the SDK's `libarchive.tbd`, with a small header of our own.** No
third-party code, no bundled binaries, BSD-licensed library already on every Mac.

| What | Finding |
|---|---|
| **libarchive (system)** | `bsdtar --version` → libarchive 3.7.4, zlib 1.2.12, liblzma 5.4.3, bzip2 1.0.8. The SDK ships `usr/lib/libarchive.tbd` (install name `/usr/lib/libarchive.2.dylib`, which lives in the dyld shared cache, not on disk) but **no headers** (`archive.h` and `archive_entry.h` are missing). A Swift test with a hand-written C header + module map (`module CArchive { header "shim.h" link "archive" }`) compiled and ran on arm64. The x86_64 slice compiled and linked too (no Rosetta here to run it), so a universal build works. The API is all opaque pointers, so a minimal header is ABI-safe. Alternative: vendor upstream `archive.h`/`archive_entry.h` at tag v3.7.4 (BSD-2-Clause). |
| zip read/write | ✅ Read and write, deflate/store, zip64 (`zip:zip64`), compression levels (`zip:compression-level=0…9`). |
| zip encryption | ✅ **AES-256** (`zip:encryption=aes256`), AES-128 and legacy ZipCrypto (`zipcrypt`), all write and read with `archive_write_set_passphrase` / `archive_read_add_passphrase`. A wrong password gives "Incorrect passphrase", no password gives "Passphrase required". `archive_entry_is_encrypted` flags entries before reading. ⚠️ macOS's own `/usr/bin/unzip` **can't open AES zips** ("unsupported compression method 99") and `ditto` fails too. ZipCrypto zips open with `unzip -P`. Windows Explorer also only handles ZipCrypto. |
| zip names | ⚠️ By default libarchive wrote non-ASCII names **without** the UTF-8 flag (general purpose bit 11), so Python/Windows read them as CP437 mojibake (ditto guessed right). Setting `zip:hdrcharset=UTF-8` sets the flag (verified, flags 0x808). Names also came out **decomposed (NFD)** even from NFC input. Normalise to NFC for zips meant for other systems, and add a test. |
| 7z | ✅ Read (LZMA/LZMA2/PPMd/BCJ…) and write (`7zip:compression=lzma2`, `7zip:compression-level=9`). ❌ **Write with a password is silently ignored**: the result is unencrypted. ❌ **Reading AES-encrypted 7z fails** ("encrypted, but currently not supported"), as does reading 7z with encrypted headers. |
| RAR | ✅ RAR4 and RAR5 read, including solid archives and **multi-volume `.partN.rar`** (tested with libarchive's own test fixtures). libarchive's RAR reader is its own BSD code, so **no unRAR license is involved**. ❌ Encrypted RAR (data or headers) is unsupported ("RAR encryption support unavailable"). ❌ No RAR writing anywhere (RAR creation is proprietary RARLAB software). |
| tar family | ✅ tar (pax/ustar/gnutar) with gzip, bzip2, xz/lzma filters, read and write. Also lz4/lzip/lzop/grzip/lrzip read via the filter API. ⚠️ **zstd needs an external `zstd` program** in the system build. With PATH=/usr/bin:/bin, reading `.tar.zst` failed ("unable to run program zstd"). Don't offer zstd. |
| Other reads | cpio, xar (pkg), cab, lha/lzh, iso9660, ar (deb), warc, mtree, rpm filter, uuencode. Free extras. |
| Multi-part read | ✅ `archive_read_open_filenames` with the ordered part list reads: 7-Zip volumes `.7z.001…` (made by 7-Zip `-v1m`), zip volumes `.zip.001…`, raw `split -b` pieces of a zip, Info-ZIP spanned `.z01…z03 + .zip`, RAR5 `.part01–08.rar`. A missing middle part breaks decompression partway, so check that all parts exist before starting. |
| Multi-part write | ❌ Not in libarchive. Write the archive, then byte-split it into `.001`, `.002`… (the 7-Zip convention, readable by 7-Zip, Keka, The Unarchiver and us; **not** by Archive Utility or Windows Explorer). `/usr/bin/zip -s` makes Info-ZIP spanned sets but only supports ZipCrypto passwords. |
| Extraction safety | ✅ With `ARCHIVE_EXTRACT_SECURE_NODOTDOT \| SECURE_SYMLINKS \| SECURE_NOABSOLUTEPATHS`, a crafted zip's `../escaped.txt` and `/abs.txt` were refused per entry (ARCHIVE_WARN with a message) and the safe entry was written. |
| Quarantine | ✅ Extracting a zip tagged `com.apple.quarantine` through `archive_read_extract` put the quarantine attribute on every extracted file (Apple's build does this). Keep it. Don't strip it. |
| Mac metadata | ✅ Apple's zip reader hides `__MACOSX/._*` AppleDouble entries from listings and extraction automatically. With the `zip:mac-ext` read option, xattrs from AppleDouble are restored onto the files (verified with bsdtar). |
| Speed | Listing a 20,201-entry zip with `bsdtar -tf` took 0.12 s (`unzip -Z1` 0.03 s). For tar.gz, listing or extracting one entry means decompressing everything before it (streaming format). Show progress. |
| **AppleArchive** framework (`libAppleArchive`, `aa` CLI) | Only Apple's own `.aar` format, with lzfse/lzma/zlib/lz4 compression. Useless for zip/7z/rar. `.aar` read is a possible later extra. |
| **Compression** framework (`compression.h`) | Raw stream codecs (zlib, lzma, lzfse, lz4, brotli). No containers. Not needed when libarchive covers it. |
| CLIs (fallback only) | `/usr/bin/ditto` (zip ⇄ folder, Finder-style with `--sequesterRsrc`, no passwords, no split). `/usr/bin/zip` 3.0 / `unzip` 6.0 (ZipCrypto only, `-s` spanning, `-x` excludes). `bsdtar`, `gzip`, `bzip2`, `hdiutil` (dmg), `aa`, `compression_tool`. No `xz`, `zstd`, `7z` or `unrar` in /usr/bin (the ones found were Homebrew's). Use libarchive in-process, not CLIs. |
| 7-Zip (what Archiver bundles) | The only practical way to get encrypted 7z, encrypted RAR and header-encrypted archives. `7zz` 24.08 is ~LGPL-2.1, with BSD-3 parts and the **unRAR restriction** for its RAR decoder (you may extract, but may not use that code to re-create RAR compression). Bundling it as a separate executable is legally fine with notices and a source link, but it breaks our "MIT/BSD/Apache" dependency rule and adds a subprocess. **Open question.** |
| Known zip oddity | A zip re-joined with `zip -s 0` was rejected by libarchive ("Invalid header") but listed fine with `unzip`. Rare, but a reason to fall back to `/usr/bin/unzip -l` for the error message, or at least to say "Try Archive Utility" in it. |
| Min macOS | Slopapp apps target macOS 14. These tests ran on libarchive 3.7.4 (macOS 27). Sonoma's libarchive is older (3.5.x era): RAR5 (3.4+) and zip AES write (3.3+) should be there, but **verify on a macOS 14 machine/VM** and probe `archive_version_number()` at runtime. |

## UX patterns worth adopting

- **One drop target, routed by content.** All archives → open them. Anything else →
  prepare to compress. No mode switch before you start.
- **Look before you unpack, by default.** Opening shows the contents, and Return extracts
  everything. A modifier while dropping skips the look for people who just want the files.
- **Output next to the input, wrapped in a folder named after the archive** when the
  archive has several top-level items. You never get 40 loose files in Downloads.
- **Drag rows straight out of the archive into Finder.** Space quick-looks, double-click
  opens. Partial extraction feels like browsing a folder.
- **Sensible archive name:** one item → that item's name. Several → a generic name.
- **Password asked inline, in context**, with a show-password toggle and a repeat field
  when creating. A wrong password re-asks without losing your place.
- **Each format choice says in one line what it's for.** Plain words beat format trivia.
- **Convert leaves out the source format.** Split defaults to a sensible chunk size with a
  unit picker.
- **Mac junk is filtered both ways** (.DS_Store out on create, `__MACOSX` hidden on
  extract).
- **Esc cancels and Return does the obvious next thing** at every stage.
- **Drop any one part of a split set** and the app finds the rest.

## What we won't copy, and what we'll do better

- **Not copying:** the name, the tray symbol, the coloured envelope-style format tiles, the
  glass pill buttons, the wording, the sounds, the trial/RAR-plugin/upgrade flows, the
  proprietary `.archiver` / `.zsplit` / `.chksplit` formats.
- **Native and tiny.** Archiver 5 is a ~570 MB Electron app needing macOS 26, and its UI is
  invisible to Accessibility in our walkthrough (only the window frame showed up, so
  VoiceOver and automation get very little). Crate is SwiftUI, a few MB, macOS 14+, every
  control labelled.
- **Batch extraction you can watch.** Archiver shows only the last result for batches.
  Crate shows a row per archive with progress, result and Reveal (FileQueue).
- **Better browse info.** Archiver shows folder sizes as `--` and no dates. Crate shows
  item counts, total unpacked size, dates and a summary. ⌘F filters long archives.
- **No double nesting:** an archive whose single top-level item is a folder extracts as
  that folder, not `name/name/`.
- **Standard shortcuts.** Archiver uses bare letters (S, C, B, E, F). Crate uses ⌘
  combos, and every action sits in a menu.
- **Honest encryption.** Archiver's site says its zip encryption is the classic PKZIP
  scheme (weak). Crate defaults to AES-256 for zip (pending the owner's call), and says
  in one line that the recipient needs a modern unzip tool.
- **Never a permanent delete.** "After extracting" offers Keep or Move to Trash only.
- **No nagging to become the default app** (a 2026 review's complaint). Alternate rank, and
  an opt-in button later.
- **No sounds, no auto-quit, no forced staging step.** Create is one view with a bottom
  bar, not three screens.
- **Safety by default:** path-traversal and symlink-escape protection, quarantine kept,
  a free-space check before big extractions, write to a temp folder and move into place,
  and partial output cleaned up on cancel or failure.
- **Clear "can't do this" messages** for encrypted 7z/RAR (v1) instead of a generic
  "could not be opened".

## Edge cases

- **Encrypted archives:** some entries encrypted and some not (zip allows it). Wrong
  password, empty password, non-ASCII password (AES uses UTF-8). Header-encrypted 7z/RAR
  can't even be listed. Encrypted 7z/RAR data needs a specific "can't open encrypted 7z yet"
  message. The password field is cleared from memory after use and never written to disk
  or logs.
- **Multi-part sets:** the user drops part 3 of 7. Parts with mixed naming (`.part1.rar`
  vs `.part01.rar`, legacy `.rar` + `.r00…`). A missing part → name it. Parts on a
  read-only volume. The output folder is named after the set, not `name.part1`.
- **Hostile archives:** `../` paths, absolute paths, symlinks pointing outside the output,
  hardlinks, device files, setuid bits (strip), zip bombs (show the unpacked total, check
  free space, cancellable), a huge number of entries (100k+, the outline must stay fast).
- **Names:** case-insensitive APFS clashes (`README` and `readme` in one archive), names
  illegal or too long on macOS (>255 bytes), legacy-encoded zip names (CP437 / Shift-JIS /
  GBK mojibake), NFD vs NFC (normalise to NFC when writing zips), emoji, RTL scripts.
- **Sizes:** zip64 (>4 GB archives or entries, >65,535 entries), empty archives, empty
  folders, zero-byte files, a single-file `.gz` (output is the bare file, not a folder).
- **Destinations:** the archive sits on a read-only volume, mounted DMG, network share or
  iCloud placeholder (not downloaded yet). Output name already exists (number it). Disk
  fills mid-extract (clean up partial output, clear error).
- **Mixed drops:** archives plus plain files in one drop (route to Create, but say so). A
  folder (Create). Zip-based documents (.docx, .epub, .apk, .jar): open only via Open With,
  never claimed as default.
- **Creating:** source files change or vanish mid-archive. Symlinks in the source (store as
  links in tar/7z; zip writes them as links too, so test what Windows recipients get).
  Packages/bundles (`.app`, `.photoslibrary`) archived whole. `.DS_Store`/`._*`/
  `Icon\r` left out. Output inside the folder being archived (don't archive yourself).
  Huge folders (progress by bytes, not files).
- **Split:** the part size is larger than the archive (no split, single file). 4 GB FAT32
  preset. Custom size validation (≥1 MB).
- **Quarantine / Gatekeeper:** apps extracted from downloaded zips must keep quarantine.
  Executable bits and internal symlinks preserved (frameworks inside `.app`).
- **Lifecycle:** app quit or crash mid-job (temp folder cleaned on next launch), sleep/wake
  during a long extraction, cancel during write, retry after failure.
- **Corrupt or truncated archives:** list what was readable, then show the error. A
  libarchive-rejected but valid zip (see Platform) gets a helpful message.
- **UI:** dark/light, Reduce Motion, VoiceOver names for every row and button ("hello.txt,
  12 bytes, encrypted"), multiple displays, full-screen, window size remembered,
  keyboard-only use (Tab, arrows, Space, Return, Esc).

## Our v1 scope

Must-haves, as the checklist the test step walks through (status after build, 2026-11-03):

- [x] Empty state is a `DropZone` ("Drop an archive to open it, or files to compress",
      "or click to choose"). ⌘O opens a panel accepting archives and any files/folders.
      Open With / Dock-icon drop work (doc types at Alternate rank).
- [x] Routing: one archive → Browse view. Several archives → extraction queue (FileQueue)
      starting immediately. Anything else → Create view.
- [x] Reads zip (incl. zip64, AES and ZipCrypto), 7z (unencrypted), RAR4/RAR5 (unencrypted,
      solid), tar, tar.gz/tgz, tar.bz2, tar.xz and single-file gz/bz2/xz through the system
      libarchive. Unsupported or encrypted 7z/RAR gets a specific, plain message.
- [x] Multi-part sets (`.7z.001`, `.zip.001`, `.z01`+`.zip`, `.partN.rar`, `.rar`+`.r00`)
      open from any dropped part. A missing part is named in the error.
- [x] Browse view: outline with name, size, date. Folders expand/collapse (←/→) and show
      item counts. A footer summary (items, unpacked size). Stays responsive with 20k+
      entries. *(Summary sits in the window subtitle; NSOutlineView, lazy rows.)*
- [x] Extract All (Return / ⌘E): next to the archive, smart folder (no double nesting),
      never overwrites (numbered), progress + Cancel, Reveal when done.
- [~] Extract selected: "Extract To…" (⇧⌘E) and the main button with a selection work;
      double-click / ⌘↓ opens an entry from a temp copy. **Dragging rows to Finder (file
      promises) is built but couldn't be verified by automation** (the shared screen had
      other apps' windows in the way); needs a human or blind-tester check.
- [x] Password prompt (inline sheet, Show toggle, retry on wrong password) for encrypted
      zip in Browse and queue rows. Passwords are never stored.
- [x] Create view: dropped items listed (removable). Bottom bar: Format (Zip default,
      Tar.gz), Password (zip, AES-256, with confirm), Save to (next to originals). The name
      defaults to the single item's name or "Archive". Create (Return). Result row with
      size and Reveal.
- [x] Created archives leave out `.DS_Store`, `._*`, `__MACOSX` and `Icon\r`. Zip names are
      stored as NFC with the UTF-8 flag (`zip:hdrcharset=UTF-8`). Checked with Python's
      `zipfile` and `unzip`. *(libarchive sets the flag only on non-ASCII names, which is
      correct: ASCII reads the same in every encoding.)*
- [x] Safe extraction: SECURE_NODOTDOT/SYMLINKS/NOABSOLUTEPATHS, quarantine propagated,
      write into a temp folder then move into place, partial output removed on
      cancel/failure, free-space check against the unpacked total. *(Absolute paths are
      refused by our own path check, since we hand libarchive absolute paths inside the
      working folder; see Build notes.)*
- [x] Menu items with shortcuts for every action (Open ⌘O, New Archive ⌘N, Extract All ⌘E,
      Extract Selected ⇧⌘E, Reveal ⇧⌘R, Stop ⌘., Clear List ⇧⌘⌫, Settings ⌘,). Settings
      has General (Save to, after extracting: keep / Trash, reveal after extracting) and
      About.
- [x] Should (all built): Space = Quick Look an entry. 7z and tar.xz creation. Compression
      level (Fast/Normal/Best). Split into parts (`.001` byte split; presets 25 MB / 100 MB
      / 1 GB / 4 GB / Custom). Convert To… (repack an open archive). ⌘F filter. Finder
      Services "Extract with Crate" / "Compress with Crate" *(declared; not exercised from
      Finder, which needs the app registered in /Applications)*. ⌥-drop = extract without
      browsing, plus a Settings choice.

## Decisions (owner defaults, 2026-11-03)

1. **Encrypted 7z/RAR:** v1 shows "“x.7z” is a password-protected 7z archive, which Crate
   can't open yet. Try Keka or The Unarchiver". When the names are readable (data-only
   encryption) the contents are listed under a banner and Extract is disabled. No 7-Zip
   (`7zz`, LGPL) bundled.
2. **Zip passwords:** the password sheet offers **Strong (AES-256)** (default) with the note
   "Archive Utility on Mac and Windows Explorer can't open it. Use 7-Zip, Keka or The
   Unarchiver.", and **Compatible (ZipCrypto, weak)** with "Opens almost everywhere, but is
   easy to crack." The choice is remembered; the password never is.
3. **Split archives:** built (after the musts): `.001` byte split, presets + Custom (MB).
4. **Browse first** by default, from Finder too. Holding **⌥ alone** while dropping or
   opening extracts right away; Settings ▸ "When you open an archive" can flip the default
   (⌥ then browses). ⌥ only counts with no other modifier, so a stray ⇧⌥ (this test Mac had
   one latched by another agent's automation) doesn't change behaviour.
5. **Never asks to become the default archive app.** Document types are at Alternate rank.
6. **Convert:** built (Archive ▸ Convert To, and a toolbar menu).
7. **Header:** our own `Sources/CArchive/crate_archive.h` (~150 lines, documented, only
   libarchive 3.3-era functions), linking `/usr/lib/libarchive.2.dylib` via the SDK's
   `libarchive.tbd`. Nothing vendored or bundled.
8. **macOS 14:** not verifiable here (macOS 27 only). See Risks in Build notes.

Further calls made while building:

- **Zip-bomb limits:** unpacked bytes may reach 100× the archive's size, always at least
  1 GB; 256 MB free space is kept. Checked up front against the listing's sizes (Browse)
  and again while writing (headers can lie; the queue only has this check). On a trip:
  "Stopped unpacking “x”: it grows to more than 1.07 GB, far more than its own size. This
  is how zip bombs behave, so nothing was kept." No override in v1.
- **Unsafe entries are hidden from the list** (with a banner naming one and the count),
  rather than shown and then silently skipped.
- **Selected items** extract with the same smart rule as Extract All (one item lands as
  is, several get a folder named after the archive). Extract To… puts them straight in the
  chosen folder.
- **Close Archive** is ⇧⌘W (⌘W closes the window, which quits). Esc only stops a running
  job; it doesn't close an archive (too easy to lose your place).
- **Mac metadata:** `__MACOSX` entries are hidden and never extracted; AppleDouble xattrs
  aren't restored (ARCHIVE_EXTRACT_XATTR off), so an archive can't set attributes such as a
  cleared quarantine.
- **Suid/sgid/sticky** bits are masked off; owner read/write is always added so output can
  be cleaned up.
- **Open Recent** uses NSDocumentController's list.

## Open questions (resolved above)


1. **Encrypted 7z / encrypted RAR / header-encrypted archives.** The system libarchive
   can't read them (or write encrypted 7z). Options: (a) v1 shows "Crate can't open
   encrypted 7z/RAR archives yet" and suggests an alternative; (b) bundle 7-Zip's `7zz`
   (~LGPL-2.1 + unRAR restriction, a separate executable, a few MB) as a fallback engine,
   which needs an exception to the MIT/BSD/Apache rule. **Recommendation: (a) for v1,**
   then revisit if the owner hits it.
2. **Default zip encryption.** AES-256 (strong, but macOS's `unzip`/`ditto` and Windows
   Explorer can't open it, so the recipient needs 7-Zip, Keka or The Unarchiver) vs
   ZipCrypto (opens almost everywhere, easily cracked). **Recommendation:** AES-256 by
   default, with a "Compatible (weaker)" choice in the Password popover and a one-line
   note under each.
3. **Split in v1?** The roadmap lists "split large archives". It's cheap (byte-split after
   writing), but split sets only open in third-party tools. **Recommendation:** ship it as
   a "should" in v1 with that note in the UI. Use the `.001` convention rather than Info-ZIP
   spanning.
4. **Preview vs extract on double-click from Finder.** Archiver previews by default (skip
   off). **Recommendation:** always browse first. ⌥-drop or the Finder Service extracts
   straight away. No setting in v1.
5. **Become the default archive app?** **Recommendation:** Alternate rank only in v1. A
   "Make Default…" button later, never a prompt.
6. **Convert in v1?** Cheap once extract and create exist. **Recommendation:** "should".
7. **Header approach for libarchive:** our own minimal declarations (as in the
   experiment, ~60 lines) or vendored upstream `archive.h`/`archive_entry.h` v3.7.4
   (BSD-2-Clause, needs the license file). **Recommendation:** our own minimal header.
   Also add "system libarchive (linked, not bundled)" to the design-system dependency
   table for the record.
8. **macOS 14 floor:** libarchive features were verified on macOS 27 only. Someone should
   run the format test matrix on macOS 14 before release (or raise Crate's minimum if
   something's missing).

## Sources

- Archiver website: <https://archiverapp.com>, support/FAQ: <https://archiverapp.com/support>,
  RAR page: <https://archiverapp.com/formats/rar>
- Setapp listing and reviews: <https://setapp.com/apps/archiver>
- Setapp article "top unarchivers": <https://setapp.com/app-reviews/archiver-apps-for-mac>
- Comparisons: <https://macpaw.com/reviews/best-unarchivers-mac>,
  <https://compresto.app/blog/best-archive-tools-for-mac>,
  <https://setapp.com/app-reviews/winzip-alternatives-for-mac>
- Archiver 4 on the Mac App Store: <https://apps.apple.com/app/id1556026599>
- FileHorse listing (older versions, feature summary): <https://mac.filehorse.com/download-archiver>
- libarchive: <https://github.com/libarchive/libarchive> (RAR test fixtures from
  `libarchive/test/` at tag v3.7.4). Format options: `man archive_write_set_options`.
- 7-Zip license: <https://www.7-zip.org/license.txt>
- Installed copy: /Applications/Setapp/Archiver.app (Info.plist, bundled view templates
  and strings, menus via `scripts/drive tree --menu`, screenshots in `/tmp/slopdrive`, not
  committed).
- Experiments: `/tmp/crate-exp` (Swift + system libarchive), `/tmp/crate-rar-dl` (RAR
  fixtures). Scratch only, not committed.

## Build notes (2026-11-03)

**Architecture.** `Sources/CArchive` (system-library module: our header + `link "archive"`),
`Sources/CrateCore` (no UI: `ArchiveTypes`, `VolumeSet`, `ArchiveReader` + `SafePath`,
`ArchiveTree`, `Extractor`, `ArchiveCreator` + `Converter`, `Router`, `CrateSettings`,
`Naming` + `WorkFolderLedger`, `FileSystem` protocol with `SystemFileSystem`), `Sources/Crate`
(SwiftUI + an `NSOutlineView` for the browse list, file promises, Quick Look). Batch
extraction is SlopKit's `FileQueue` with an `ExtractProcessor`.

**libarchive findings while building.**
- `SECURE_SYMLINKS` checks every component of the absolute path we give it, so the working
  folder must be fully resolved: `/tmp` → `/private/tmp`. Foundation's
  `resolvingSymlinksInPath()` maps `/private/tmp` *back* to `/tmp`; use `realpath(3)`.
- Because we set absolute paths (inside the working folder) on entries, we can't use
  `SECURE_NOABSOLUTEPATHS`; `SafePath.check` refuses absolute and `..` paths first, and
  `NODOTDOT` + `SECURE_SYMLINKS` + `NO_OVERWRITE` stay on as a second layer.
- `archive_read_support_format_raw` bids on any file when nothing else does; a "raw" read
  with no decompression filter is treated as "not an archive".
- Encrypted 7z: data-only encryption lists fine (`archive_entry_is_encrypted`), header
  encryption fails to open; both map to `unsupportedEncryption`. RAR header encryption
  fails to open with "RAR encryption support unavailable".
- Apple's zip reader hides `__MACOSX/` itself; other formats are filtered by us.
- `FileManager.contentsOfDirectory` already hides `._*` files.
- Quarantine is copied by Crate onto every extracted item *and* the wrapping folder (the
  renamed working folder isn't covered by libarchive's own behaviour).

**Gates.**
- Unit tests: **56 Swift Testing tests in 8 suites**, all green (repeated 3× to rule out
  flakes after fixing a launch-cleanup race). Cover: split-set resolution for every
  naming scheme incl. gaps; base names; never-overwrite moves; routing; settings decoding;
  tree build/filter/20k entries; listing zip/RAR4/RAR5 solid/RAR5 8-part; encrypted
  7z/RAR messages; not-an-archive; truncated; corrupt; single-file gz; smart folder;
  traversal + absolute; symlink escape, symlink-then-file, absolute link, hardlink
  escape; case clashes; zip bomb (streaming and up-front); full disk (fake FS);
  quarantine; setuid; selection; AES + ZipCrypto (wrong/right, non-ASCII password);
  cancellation cleanup; read-only destination; creation in all 4 formats × 3 levels;
  junk exclusion; NFC + UTF-8 flag; symlinks stored; split + reopen; name clashes;
  convert RAR → zip; trash override; leftover cleanup only for earlier runs.
- `scripts/check.sh Crate --perf`: tests, universal release bundle, smoke, perf all
  PASS. Perf (busy machine, load ~12): launch 150 ms, first window 244 ms, idle CPU
  0.039%, footprint 28.9 MB (budget 120 MB).
- Walkthrough (release and debug builds via `open -a` + `scripts/drive`, screenshots in
  `/tmp/crate-test/shots`, dark and light): empty state; browse (zip from ditto, tar.gz,
  7z, RAR, 2,000-file zip with ⌘F filter); Return extracts (numbered "Project 2" when
  "Project" exists); password sheet (wrong → message, right → extract; cancelled → asks
  again on Extract and resumes the pending action); traversal.zip (banner, unsafe items
  never written outside); symlink escape.tar; zip bomb (stopped, nothing kept); encrypted
  7z (banner) and header-encrypted 7z (error state); truncated (partial list + banner);
  corrupt 7z; text file named .zip; missing split part (names `big.7z.002`); 8-part RAR
  from part 3; Quick Look (Space); Convert RAR → Zip; create with AES password (verified
  with `bsdtar --passphrase`, `unzip -t`, Python `zipfile`: flags 0x9/0x809, `.DS_Store`
  left out); queue of 7 archives incl. a split 7z, a spanned zip and a ZipCrypto zip
  (password prompt, retry) running concurrently without clobbering ("big 2.bin");
  setuid tar (bit dropped, FIFO skipped); case-clash zip (README + "readme 2");
  quarantined zip (every item and the folder keep the flag); after-extracting → Trash;
  reveal after extracting; Settings; menus.
- `scripts/drive tree`: no `[unlabeled]` controls on any screen (outline rows carry
  "name, size, encrypted" labels).
- Design checklist §10: 1 ✓ (drop → browse → Return), 2 ✓ (system controls, accent,
  semantic colours, both modes), 3 ✓ (every action in File/Edit/Archive with shortcuts),
  4 ✓ (Esc cancels sheets and stops jobs, ⌘, ⌘Q, ⌘W), 5 ✓ (General with Launch at login,
  Advanced, About), 6 ✓, 7 ✓ (drop zone; empty-archive and no-match states), 8 n/a (no
  permissions), 9 ✓ (nothing destructive; Trash only, opt-in), 10 ✓ (no network code),
  11 ✓, 12 ✓, 13 ✓ (only SlopKit's DropZone scale, which honours Reduce Motion), 14 ✓
  (window frame and column widths autosaved).

**Not verified / risks.**
- Dragging rows to Finder (file promises): built, not exercised by automation (other
  apps' windows covered the target on the shared screen).
- Finder Services: declared in Info.plist; macOS only lists them for apps registered
  from /Applications, so not exercised.
- **macOS 14**: libarchive features were only verified on macOS 27 (libarchive 3.7.4).
  Sonoma's older libarchive should have RAR5 and zip AES, but run the unit tests on a 14
  machine before release. `LibArchive.version` is available for a runtime check.
- Opening a big tar.gz to browse means decompressing it once to list it and again to
  extract (streaming format); progress is shown both times.
- The queue's bomb check is streaming only (no listing first), so a bomb writes up to
  ~1 GB before it's stopped and removed.
- FileQueue rows can't show a custom inline button, so a queue row needing a password
  prompts with a sheet automatically; Try Again re-prompts. (Suite cleanup: a per-row
  custom action in `FileQueueView` would let this be an inline "Enter Password…".)

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.

### Round 1 (2026-11-03)

Every hostile fixture was contained (traversal, absolute paths, symlink escapes, setuid,
zip bomb, truncated, corrupt). Triage by the coordinator; fixes and re-checks by the builder.

| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
| F1 Can't open password-protected 7z/RAR | major | **Reject as a v1 blocker** | Owner-default decision: no LGPL 7-Zip, and the system libarchive can't decrypt 7z/RAR. The clear message stays; README now has a "Why can't Crate open my password-protected 7z or RAR file?" section (Help ▸ Crate Help opens it). **Top v1.1 item**: implement 7z AES-256 decryption ourselves (CommonCrypto: SHA-256 key derivation + AES-256-CBC, feeding libarchive's LZMA/LZMA2 decoders or a raw-stream path), or adopt an MIT/BSD library if one exists. Encrypted RAR is harder (RAR5 = AES-256 + PBKDF2, but the decompressor would also need our own read path). |
| F2 Esc and ⌘. don't cancel the New Archive form | minor | Accept | Cancel button is the cancel action (Esc); Archive ▸ Stop reads "Cancel New Archive" (⌘.) while the form is idle and closes it. Verified both. |
| F3 Open Recent lists archives moved to the Trash; "Next to Archive" extracts into the Trash | minor | Accept | Open Recent drops items that are in a Trash or gone. An archive in a Trash extracts to ~/Downloads (`TrashLocation`, also for Convert and Create's "Next to Originals"); `CRATE_DOWNLOADS_DIR` redirects it in tests. Unit-tested; verified live with the overrides. |
| F4 Duplicate / case-clashing names: preview shows 3 items, 4 files written | minor | Accept | The tree no longer merges entries: every entry is listed with the name extraction gives it ("readme 2  was “readme”", tooltip + VoiceOver explain). The extractor and tree use the same rules, including a file in the way of a folder; a test asserts preview names == files written. Selection extracts by archive path. |
| F5 Custom split size 0 silently becomes 1 MB | minor | Accept | Inline warning next to the field and in the bottom bar ("Enter a part size of at least 1 MB."), Create disabled. Verified. |
| F6 Convert toolbar button announced as "Syncing" | minor | Accept | Shown as "Convert" with its icon (the symbol's built-in description is hidden). Tree now reads `menuButton "Convert"`. |
| F7 Archive trashed even when items were skipped; no undo | minor | Accept | Only after a complete extraction with nothing skipped and no read problem (browse and queue); otherwise "The archive was kept because some items were skipped." Edit ▸ Undo puts trashed archives (all parts) back. Verified live with `CRATE_TRASH_DIR`. |
| F8 "Opens on any computer" hint after setting an AES password | nit | Accept | Hint follows the password: "Needs 7-Zip, Keka or The Unarchiver to open (AES-256 password)" / ZipCrypto variant. |
| F9 Raw codes like "(Decompression failed(9))" | nit | Accept | "Damaged" errors no longer show libarchive's text; other details are cleaned of codes (`CrateError.plain`). |
| F10 Capitalisation after commas in VoiceOver strings | nit | Accept | Result line reads "Extracted to “x”. Skipped …" (sentence), New Archive rows "name, folder, 5 items". (FileQueue row labels are SlopKit's.) |
| F11 "Zero KB" for single-file .gz | nit | Accept | Sizes the archive doesn't record show "--", the subtitle says "size unknown". (gzip's ISIZE is mod 4 GB, so not trusted.) |
| F12a Truncated-archive message shown twice | nit | Accept | Banner explains once; a failed extract of the same problem says only "Extraction stopped where the archive ends. Nothing was kept." |
| F12b "Next to Archive" wording | nit | Accept | Same title-case wording in the bar, the menu and Settings (Next to Archive, Ask Each Time, Keep Archive, Move Archive to Trash). |
| F12c No checkmarks in Extract to / Save to menus | nit | Accept | Inline pickers: the current choice is checked. Verified in the tree (`[✓]`). |
| F12d Folder dates not restored | nit | Accept (already mostly true) | Folders with entries keep their archived dates (verified: a 2020 folder stays 2020). Folders the archive doesn't list, and the wrapper folder, get today's date. |
| F12e Quick Look doesn't follow the selection | nit | Accept | Real `QLPreviewPanel` controller: the list takes panel control; ↑/↓ in the panel move the selection and the preview follows. Verified. |
| F12f Help links to the README | nit | Keep | Suite convention. |
| Missing: warn before obvious bombs | — | Accept | Banner when the listing claims more than the limit ("This 2.1 MB archive says it unpacks to 2.15 GB…"); Extract All is refused up front (already was), small selections work. |
| Missing: salvage the readable part of truncated archives | — | Defer | Later (inventory). Extraction stays all-or-nothing for now. |

Gates after round 1 (release build, version 0.2.0, status beta): `scripts/check.sh Crate
--perf` all PASS. 61 unit tests in 9 suites, including new ones for preview names ==
written files, unknown sizes, Trash fallback, Undo of Trash, and cleaned error text. Perf:
launch 158 ms, first window 261 ms, idle CPU 0.048%, footprint 28.8 MB. No `[unlabeled]`
controls. Walkthrough of every fix done with `open -a` and keys posted to Crate's process only:
no real mouse, no global keys, no clipboard, window-only screenshots. Drag-out to Finder is
still not tested: it needs the real mouse, and the owner may be using the Mac.

## Parity pass (2026-11-03)

Owner direction (`docs/parity-pass.md`): look and work much more like Archiver, and don't
miss features. Studied again from the installed Archiver 5.1 (launched with
`env -u ELECTRON_RUN_AS_NODE`, only `/tmp/crate-parity/` files, no settings touched, quit
after) and the research screenshots in `/tmp/slopdrive/archiver-*.png` (empty, preview,
files, create, convert, split, done, settings). The screen locked partway through the
session, so the rest came from those screenshots.

**Archiver's layout, as matched:** a compact window; empty state = one big drop symbol;
browse = outline (disclosure, icon, name, size) with the actions **top right** (a round
Cancel ×, then Split, Convert, Extract) and the **archive name centered in the footer**;
dropped files = a staging list with **+ / −** and "N Files" centered in the footer, Cancel
and Archive top right; then a **"choose format" page** (a row of big format tiles, the
format's one-line description, then Archive Name, Compression Level, Encrypt → Password,
Repeat, Show Password) with back/forward; then a **finished page** listing the results with
"drag the files…", Back, Finder and a round Done ✓.

### Gap table

| Item (Archiver) | Before | Now | Notes |
|---|---|---|---|
| Compact window | 640×500 | **done**: 560×420 default, 480×340 min | Archiver is 460×306; ours needs room for the outline's columns. |
| Empty drop state | DropZone | kept | SlopKit DropZone (symbol + one line + click to choose) is the suite standard and labelled for VoiceOver; Archiver's is a bare symbol. |
| Browse: actions top right (Cancel, Split, Convert, Extract) | Convert + Close in toolbar, Extract in a bottom bar | **done**: toolbar Close ×, (Join Parts), Split, Convert, **Extract** (prominent, Return; "Extract 3 Items" with a selection) | |
| Browse: name centered in footer | subtitle | **done**: footer centered "name — N items, size · format", Extract to: menu on the left | Progress + Stop replace the summary while working. |
| List / grid toggle | — | **deferred** (M, ~½ day) | Grid needs its own folder navigation and file-promise drags; the list does everything the grid does. |
| Finished page: results list, drag to copy, Back / Finder / Done | a result line in the bottom bar | **done**: `ResultPage` after extract, create, convert, split, join; rows are real files (drag anywhere, double-click opens); toolbar Back, Show in Finder, **Done** (Return) | |
| Create: staging list with + / − and "N items" footer, then format page | one combined view | **done**: review page (list, +/−, centered count; toolbar Cancel, Split for one file, **Compress**) → format page | Settings ▸ "When you add files to compress: Show the List First / Go Straight to the Format" (Archiver's "Creating archives: Skip preview"). |
| Format page: tiles + description + Name / Compression / Encrypt | pickers in a grid | **done**: our own format cards (SF Symbols, accent outline when selected), the description line, Archive name, Compression (**None** / Fast / Normal / Best, matching Archiver's four levels), **Encrypt** checkbox revealing Password, Repeat, Show password inline (no sheet), zip strength, 7z "Hide file names", Split, Save to | Not Archiver's coloured envelope tiles (trade dress). |
| Convert: "choose format" page without the source format | menu of formats | **done**: Convert (⌘K) opens the format page in convert mode (source format left out, name = archive's base name, Encrypt available), Back returns to the archive | |
| Split: page with chunk size + unit | only "split when creating" | **done**: Split sheet (part size field + stepper + KB/MB/GB, default 10 MB like Archiver) for an open archive or a single dropped file | A sheet, not a page: there's no format to choose for a byte split. Archiver's ZSPLIT/checksum formats skipped (proprietary). |
| Combine / join split files | — (later) | **done**: Join Parts (⌘J) for an open `.001` set, File ▸ Join Split Files… (⌥⌘J), and a "Join Parts" button when a `.001` set isn't an archive (e.g. `movie.mkv.001`) | Numbered `.001` sets only; joining RAR volumes or `.z01` spans doesn't give a valid single file. Never overwrites; keeps quarantine. |
| **Encrypted 7z: open** | "can't open yet" | **done** (see below) | Data-only and header-encrypted; any coder chain libarchive decodes. |
| **Encrypted 7z: create** | password Zip only | **done**: AES-256 7z, "Hide file names" on by default | Verified by 7-Zip 26.05. |
| Encrypted RAR | can't open | **deferred** (L, 1–2 days for RAR5; RAR4 another M–L) | Same "virtual decrypted view" approach should work: RAR5 = AES-256-CBC + PBKDF2-HMAC-SHA256 (2^n) with a password check value, per-file encryption records and optional header encryption (every header block encrypted, own IVs). We'd have to rewrite headers (drop the encryption record, recompute header CRC32s, drop the HMAC-tweaked data checksums) so libarchive's RAR5 reader accepts it, across solid streams and volumes. RAR4 uses AES-128 with its own SHA-1 KDF. Not attempted this session: 7z came first and the RAR work needs its own test corpus. |
| Password manager / remember | never stored | **done (opt-in)**: Settings ▸ Advanced ▸ "Remember passwords in the Keychain" (off), mirrored as "Remember in Keychain" in the password sheet; one generic-password item (`app.slopapp.crate.passwords`) with a JSON list, newest first, max 50; the 15 newest are tried automatically on a locked archive (browse and queue) before asking; "Forget All…" | `PasswordStore` protocol with Keychain, file (`CRATE_PASSWORDS_FILE`, tests only) and memory stores. **Not exercised against the real login keychain** (doing so would write to the owner's keychain); unit tests use the memory and file stores. |
| Destination presets ("Output files to: same / ask / Other…") | Next to Archive / Ask / one chosen folder | **done**: Extract to: menu adds Desktop, Downloads and the 5 most recent chosen folders | |
| Finder integration (six Services) | 2 Services | **done**: + "Extract with Crate To…", "Open in Crate" (4 total) | Archiver's "Compress to…" and "Convert" Services skipped: the window flow covers them. Services only appear for apps registered from /Applications, so not exercised here. |
| File Types pane (default app per type) | — (later) | **done**: Settings ▸ General ▸ File types ▸ Choose… lists 13 archive types with the current app and "Use Crate" / "Use Crate for All" | Never prompts. **Not exercised for real** (would change the owner's default apps); `CRATE_DRY_DEFAULTS=1` pretends. |
| Extract selected by drag | built, unverified | see Build notes below | Needs the real mouse. |
| Quick Look / preview | done | kept | |
| Quit when done, play sound, go back to start, inspect app bundles, Clean ⌘K | skipped | still skipped | Design system (quiet, window stays); ⌘K is Convert here. |
| RAR creation, `.archiver`, ZSPLIT | skipped | still skipped | Proprietary. |

### Encrypted 7z: how it's built

- **Reading** (`SevenZipDecryptedView`): Crate parses the 7z structure itself (signature,
  encoded header via the system **liblzma**, folders, coders, bind pairs), derives the key
  (7-Zip's KDF: SHA-256 over salt + UTF-16LE password + 64-bit counter, 2^NumCyclesPower
  rounds; CommonCrypto), and presents libarchive with a **virtual unencrypted 7z**: a new
  signature header, the packed streams (AES streams decrypted on the fly, any block on its
  own since CBC only needs the previous ciphertext block; the rest byte for byte), and a
  rewritten header with the AES coders removed. libarchive reads it through
  `archive_read_open2` + seek callbacks, so LZMA/LZMA2/PPMd/BCJ/BCJ2/Deflate, listing and
  **all extraction safety (paths, links, bombs, quarantine, no overwrite)** are the same
  code as every other archive. **Nothing decrypted is written to disk** except the
  extracted files. Keys are cached in memory (16 entries) so list/check/extract derive once.
- **Password check:** header-encrypted archives are checked against the header's CRC (or a
  clean parse); data streams by test-decoding the first 64 KB with liblzma (LZMA/LZMA2
  reject random bytes almost at once); anything that slips through fails libarchive's CRC
  at extraction and is reported as a wrong password (as 7-Zip does). Non-ASCII passwords
  that fail are retried in the other Unicode normalization form (NFC/NFD).
- **Writing** (`SevenZipEncryptor`): libarchive writes a normal LZMA2 7z; Crate adds an
  AES-256 coder in front of each folder (7-Zip's layout: AES first, bound to the
  compressor), with a random 16-byte salt and per-folder IV, 2^19 rounds; with "Hide file
  names" the header is written as an AES-only encoded header (as py7zr and 7-Zip with
  `-mhc=off` do), with its CRC. Passwords are normalized to NFC.
- **Interop (opt-in test, `CRATE_7ZZ=/path/to/7zz`):** 7-Zip 26.05 (official macOS build,
  downloaded to `/tmp/crate-parity/7zip-dl`, not shipped) lists, tests and extracts Crate's
  archives with and without hidden names, rejects wrong passwords; Crate reads 7-Zip's
  encrypted archives made with LZMA, LZMA2, PPMd, BCJ+LZMA, non-solid, Copy, Deflate,
  uncompressed headers, and 700 KB volumes, all with a non-ASCII password. Also py7zr's
  fixtures (data-only and header encryption).
- **Hostile/robustness tests:** traversal, absolute paths and escaping symlinks inside an
  encrypted 7z are refused like anywhere else; a 64 MB bomb inside encryption is stopped
  and cleaned up; truncated archives fail cleanly; 150 rounds of random byte damage to an
  encrypted archive never crash or leave output. Header sizes are capped (256 MB), counts
  bounded, every read bounds-checked.
- **Gotcha found:** Foundation's `Process` passes arguments *and* environment values in
  decomposed (NFD) form, so a test that hands "ö" to 7zz changes the password. The interop
  harness passes arguments through files.

### Deviations from the design system (and why)

- **Primary action in the toolbar** (Extract, Compress, Create, Done as prominent toolbar
  buttons, Return), not a bottom bar: Archiver's actions sit top right. The design system
  allows options "in a bottom bar or the toolbar"; the footer keeps the centered summary.
- **Format cards** (custom buttons) instead of a popup: matches the original's "choose a
  format" tiles; built from SF Symbols, system fills and the accent colour, labelled for
  VoiceOver (name, selected, description as hint).
- **Two-step create** (review list → format page) instead of one view: the original's
  order. Not a modal (in-window pages); Settings can skip the list.

### Decisions

1. Encrypted 7z built in-house (no 7-Zip/LGPL code): ~1,350 lines in
   `Sources/CrateCore/SevenZip/` plus `Sources/CLZMA` (our header for the system liblzma,
   like CArchive). Recorded here instead of `docs/design-system.md` (not ours to edit):
   **system liblzma, linked not bundled**, should join "system libarchive" in the dependency
   table.
2. New 7z archives encrypt names by default ("Hide file names" on): what people expect from
   a password, and what Archiver's 7z encryption via 7-Zip `-mhe` is commonly used for.
3. Salted keys (16 random bytes) although 7-Zip's own encoder uses no salt: the format
   supports it, 7-Zip reads it (verified by the interop test), and it stops precomputed attacks.
4. Remembered passwords are opt-in and live in one Keychain item, never in UserDefaults.
5. Compression "None" added (Archiver's "No Compression"): store for zip and 7z, level 0
   for gzip/xz.
6. Split default 10 MB with KB/MB/GB like Archiver; the create page keeps the presets
   (25 MB, 100 MB, 1 GB, 4 GB FAT32, Custom).

### Shared components built in-app (for later extraction to SlopKit)

- `Pages.swift`: `ResultPage` / `ResultRow` / `ResultToolbar` (a finished screen with
  draggable result files), `PageFooter` (left control + centered summary/progress),
  `FormatCard`, `SplitSheet`. Any drop-in app with a "done" state could use `ResultPage`.
- `SavedPasswords.swift`: `PasswordStore` + Keychain/file/memory stores.


### Gates (parity pass)

- `scripts/check.sh Crate --perf`: **all PASS**. 85 Swift Testing tests in 14 suites (new:
  7z crypto 6, 7z write/hostile/fuzz 7, split/join 4, saved passwords 4); plus the opt-in
  interop suite (`CRATE_7ZZ`, 12 cases against 7-Zip 26.05) **passes**. Perf (final run): launch 134 ms,
  first window 243 ms, idle CPU 0.017 %, footprint 29.0 MB.
- **Walkthrough (release build)**: the screen was **locked for the whole UI part of this
  session** (owner away), which hides windows from Accessibility and blocks screen capture.
  So the walkthrough was driven with `open -a` (files under `/tmp/crate-test/parity`) and keys
  posted to Crate's pid only, and the screenshots come from a new test-only hook
  (`CRATE_SNAPSHOT_DIR`: Crate renders its own windows offscreen to PNG; nothing else on
  screen can be captured). Windows render as inactive (greyed toolbar) because nothing is key
  while locked. Covered, each checked on disk:
  - dark: empty (`d-01`), browse demo.zip (`d-02`), Return → finished page (`d-03`), 7-Zip
    header-encrypted `vault.7z` locked (`d-05`), wrong password (`d-06-…-sheet`), unlocked
    listing (`d-07`), extracted **byte-identical** to the source, Convert page (`d-09`) →
    `vault.zip` (`d-10`, contents checked with `unzip -l`), Advanced settings (`d-25`),
    review (`d-26`), 7z format page (`d-27`), split-file offer (`d-28`);
  - light: review (`l-11`), format page (`l-12`), created Archive.zip (`l-13`), one-file
    review with Split (`l-14`), Split sheet (`l-15-…-sheet`), split into 3 parts (`l-16`),
    join offer (`l-17`), joined **byte-identical** (`l-18`), queue with a 7z password prompt
    (`l-19`) → both extracted, 7z output byte-identical (`l-20`), Remember-in-Keychain sheet
    (`l-21-…-sheet`, file store), second names-hidden 7z **unlocked automatically** with the
    remembered password (`l-22`), 7z format page (`l-23`), General settings (`l-24-2`).
  - Screenshots: `/tmp/crate-test/shots/` (not committed).
  - For the session only, Crate's own defaults got `{"rememberPasswords":true,
    "createFormat":"sevenZip"}` and the Settings tab index; both were put back afterwards
    (the `settings` key didn't exist before and doesn't now).
- **Not done because of the locked screen** (need a human or an unlocked session):
  `scripts/drive tree` for `[unlabeled]` controls (every new control has a label in code:
  toolbar Labels, `+`/`−` and stepper `accessibilityLabel`s, FormatCard name/selected/hint,
  result rows); the Encrypt-checked state of the format page (the checkbox needs a click;
  covered by unit and interop tests); Settings ▸ File types sheet (click only;
  `CRATE_DRY_DEFAULTS=1` for testers); **drag-out to Finder** (real mouse; also needs the
  owner away, and the screen unlocked).
- Fixed during the walkthrough: Esc didn't leave the finished page (Back now has Esc);
  footer text off-centre with no left control; the Split size field wasn't focused; the
  password field now takes focus when Encrypt is ticked; "isn't an archive" wording for a
  non-archive `.001` set (now "one part of a split file… Join Parts puts its 3 parts back
  together as “movie.bin”"); File ▸ Join Split Files… on a real archive set showed "not an
  archive"; "Enter Password…" after cancelling didn't re-list a names-hidden 7z.

### Deferred (with estimates)

| Item | Size | Why |
|---|---|---|
| Encrypted RAR (RAR5, then RAR4) | L (1–2 days) + M–L | See the gap table; needs header rewriting for libarchive's RAR readers and its own corpus. |
| Grid (icon) view | M (~½ day) | Needs folder navigation and file-promise drags of its own; the list covers the job. |
| Drag-out, `[unlabeled]` tree, Encrypt-on screenshot, File types sheet | S (a human, 15 min) | Locked screen this session; see above. |
| Real-Keychain check of remembered passwords | S | Would write to the owner's login keychain; the file store (`CRATE_PASSWORDS_FILE`) exercises the same flow. |
| Settings tab "File Types" like Archiver's | S, needs SlopKit | `SlopSettings` has fixed tabs; it's a sheet from General for now. |

## Polish pass (2026-11-05)

Per `docs/polish-pass.md`. Release build stamped with SDK 27.0 (full-size 16×16 window
buttons, checked in `drive tree`). Every surface shot in light and dark with
`SLOP_APPEARANCE`, test data only from `/tmp/crate-test/polish/` (archives and files made
for this pass), with `CRATE_PASSWORDS_FILE` (remembered passwords in a test file, never the
Keychain), `CRATE_TRASH_DIR`, `CRATE_DOWNLOADS_DIR`, `CRATE_DRY_DEFAULTS=1` and
`CRATE_SNAPSHOT_DIR` (for sheets). Only made-up test passwords were typed, and only into
secure fields. Files were opened with `open -g` (no activation); keys were posted to Crate's
pid only. The owner was at the Mac almost the whole session (HID idle under 60 s at nearly
every check), so most shots are of an inactive window. Once (idle 64 s) Crate was brought
to the front for an active-window check: accent selection, the blue Extract capsule, the
filter field typed into with ⌘F (`light-60-active-selection.png`, `light-62-active-password-*`).

### Defects found and fixed (before → after)

| # | Surface | Defect (measured) | Fix |
|---|---|---|---|
| 1 | Lint | 4 corner literals: format cards `10` (×3), drop ring `8` | Cards `Radius.l`; drop ring is a `ConcentricRectangle` 2 pt inside the window (legacy: `Radius.nested(in: 10, padding: 2)`). Lint clean |
| 2 | All pages | SwiftUI `Divider` = 2 px (1 pt) above every footer, under the result header, above failure lines, under banners, on the format page | SlopKit `Hairline`: 1 px `#EAEAEA` measured |
| 3 | Footers | Browse/create footer 36.5 pt, queue footer 48.5 pt; progress + Stop grew it to 40.5 pt (hairline 927 → 919 px, the list jumped 4 pt) | One `FooterBar`: fixed 40 pt, small Stop / Clear List. Hairline at 919 px in idle, progress, warning and queue states |
| 4 | Footers | Leading text at 16 pt (menu), 18.5 pt (+ glyph), 16.5 pt (queue) | 16 pt margin; the borderless menu's 4 pt inner inset is taken back (`-Spacing.xs`), + glyph at 16.5 pt |
| 5 | Browse list | Columns ended 20 pt short of the right edge (Kind ended at 620 of 640 pt, stray header divider, empty strip); at the 480 pt minimum the table overflowed and scrolled sideways (Kind clipped, rows lost their inset) | `fitColumnsToWidth`: columns fill the visible row exactly (10 pt row inset both sides) on every resize; extra width goes back to Date/Kind then Name, a narrow window takes it from Kind, Date, Name down to their minimums. No sideways scrolling at the minimum |
| 6 | Browse list | Kind/Date truncated in the middle: "Folder,…00 items", "Comma…values" | Tail truncation for every column but Name ("Folder, 1,0…"); Kind 110 → 140 pt, Date 165 → 132 pt by default (autosave key `ArchiveColumns.v2` so the new defaults apply) |
| 7 | Browse toolbar | Extract's title changed with the selection: "Extract All" 106 pt → "Extract 2 Items" 136 pt, the whole group shifted 30 pt | One title, "Extract" (87 pt). The footer says "2 of 12 items selected"; VoiceOver ("Extract All" / "Extract Selected"), the tooltip and Archive menu say which |
| 8 | Format toolbar | "Create Zip" / "Create 7z" / "Create Tar.gz" changed width with the format | "Create" (or "Convert"); the format is in the tooltip |
| 9 | Browse toolbar | At the default 560 pt width, opening the filter sent Convert and Extract to the » overflow menu; at the 480 pt minimum Extract was in » even without filtering (the window title alone reserved 160 pt) | Toolbar title hidden on the browse page (macOS 15+; the name is centred in the footer, the window keeps its title for the Window menu and VoiceOver); the filter field stays open beside the actions, so nothing moves when you type. Minimum width 480 → 540 pt: every action visible at 540 with a 60-character archive name |
| 10 | Toolbars | Primary buttons merged into their neighbours' glass capsule in some states ("Back \| Create" one capsule while Create was disabled; Extract inside the action group) | Extract, Compress, Create and Done are their own `ToolbarItem`: always their own capsule |
| 11 | Browse toolbar | Split used `square.split.2x1` (reads as Show Sidebar); Convert used `arrow.triangle.2.circlepath` (reads as Sync) | `scissors` and `arrow.left.arrow.right` |
| 12 | Password sheet | Wrong password added an orange row: sheet 176 → 203 pt; plain `.orange` text (~2:1); field and checkboxes at the 20 pt margin while the text started 39 pt further in; subtitle changed with the Remember checkbox | Message replaces the subtitle in place (sheet 204 pt in both states), `.textOrange` (core #A4682D); one column: title, field and checkboxes share a leading edge; checkboxes stacked; lock glyph on the 20 pt margin |
| 13 | Format page | Ticking Encrypt moved every label 66 pt left (the grid re-centred on its widest row); the name field changed width with the extension (294 → 298 pt) | Fixed columns (104 + 8 + 320 pt) centred, fixed ".tar.gz"-wide extension slot: labels' trailing edge at 207.5 pt in every state, field 279 pt always |
| 14 | Format page | Row pitch 36 / 32 / 32 / 36 pt (checkbox rows 16 pt tall); the zip radio group sat 4 pt high (32 pt pitch) | Every row 24 pt, the first radio centred in its row: pitch 36 pt throughout, Encrypt on or off, zip or 7z |
| 15 | Format page | "Choose a format:" leading-aligned at 20 pt over centred cards; content inset 16 pt top vs 20 pt sides | Centred heading, no colon; 20 pt all round |
| 16 | Format page | AES/7z hints up to 85 characters, wrapping at the minimum width (and pushing the form down when the format changed) | ≤ 66 characters, one line at 540 pt ("AES-256 password, names hidden too. Opens in 7-Zip, Keka or Crate") |
| 17 | Format cards | 1 pt grey stroke, no hover or pressed state | `FormatCardStyle`: hairline edge, fill 4 % → 8 % hover → 12 % pressed, accent fill + 2 pt accent edge when selected, 50 % when disabled |
| 18 | Format page | Ticking Encrypt left focus in Archive name (the field didn't exist yet when focus was set) | Focus moves to Password on the next run loop |
| 19 | Format page | Zip encryption radios had no label; 7z note didn't say the password isn't kept when names are shown | "Encryption:" label on the radio group; both 7z notes end "Crate doesn't keep this password." |
| 20 | Footer | "The passwords don't match." looked like the grey summary | Real problems (mismatch, bad split size) in `.textOrange` with a warning symbol; steps still to do ("Enter a password…") stay secondary |
| 21 | Result page | "Drag items to copy them anywhere." in `.tertiary` (~1.9:1); warning in plain `.orange` | `.secondary`; `.textOrange` |
| 22 | Status text | Plain `.orange` text in the failure line, Split sheet, File Types sheet, split-size icon | `.textOrange` |
| 23 | Empty archive | Footer "0 items, Zero KB · Zip" | "Empty · Zip" |
| 24 | Error states | Headings ended with a full stop ("…isn't an archive Crate can read.") | No full stop on headings |
| 25 | Review list | Detail in `.caption`, the result list's in `.callout` | `.callout` in both |
| 26 | Review footer | + / − hit areas were the glyphs (AX frames 10×10 and 10×1 pt) | 24×20 pt each (`FooterGlyph`) |
| 27 | Settings | Four explanations were separate rows with separators | Subtitles under their own labels (General: open behaviour, after extracting, file types; Advanced: remember passwords, Mac-only files); "Hold Option (⌥) to do the other." fits one line |
| 28 | File Types sheet | Inset list: rows started 16 pt right of the text margin | Bordered list with alternating rows on the 20 pt margin |
| 29 | Queue rows | Messages repeated the name and ran long: "“q3.zip” needs a password. Enter the password to unpack it." | `CrateError.rowMessage`: nameless, ≤ 80 characters, says what to do ("Needs a password. Click Extract Again to enter it."); no Extract Again for archives that fail the same way every time (not an archive, damaged, unsupported encryption, bomb). 3 new tests |
| 30 | Queue footer | Stop All ↔ Clear List swapped buttons of different widths | One fixed slot for both |
| 31 | Copy | "7-Zip" broke across lines at its hyphen ("Use 7-" / "Zip, Keka…") in the zip encryption note | Non-breaking hyphen (U+2011) in every visible "7‑Zip" |
| 32 | Browse list (filtering) | Typing a filter expanded every folder, NSOutlineView widened Name to fit the indentation, and the table scrolled sideways: rows lost their inset and Kind ran off the edge (seen in the one active-window check) | `autoresizesOutlineColumn = false`: deep names truncate in the middle instead; checked with a 7-level archive expanded with ⌥→ |
| 33 | Browse list (filtering) | The footer kept "1 of 12 items selected" (and Extract kept the selection) after the filter hid the selected row | The selection is reconciled after every reload: rows the filter hides are deselected |
| 34 | Browse list | Opened in the background, the list sometimes didn't get keyboard focus (↓ and Return did nothing) | Takes first responder as soon as it's in a window |

Checked and fine as is: drop zone 20.0 pt from the title bar, sides and bottom; window
buttons 16×16; "Name" header text on the folder icons' edge (27.5 pt); Size values' right
edge = header's right edge; lock icon centred on the name's line; banner and failure-line
symbols on the same 18 pt edge; result and review icons at 16 pt; banner/failure line rows
40 pt like the footer; dark mode throughout (card fills, banner tint, sheets).

### Decisions

- **No title in the browse toolbar** (macOS 15+). The archive's name is already centred in
  the footer with its size and format (the original's layout); the title cost 160 pt and
  pushed the main action into the overflow menu. The filter field is therefore always open,
  like Mail's and Finder's.
- **Extract is one fixed title.** Stable width beats a live count in the button; the count
  moved to the footer.
- **Minimum window 540 × 340** (was 480 × 340): the narrowest width where the browse toolbar
  fits without overflow. Default size stays 560 × 420.

### Gates

- `scripts/check.sh Crate --perf` (final build): all pass. Launch 168 ms, first window
  271 ms, idle CPU 0.017 %, footprint 29.6 MB (load 3.7).
- Tests: 88 in 15 suites (new `RowMessageTests`).
- `scripts/lint.sh Crate`: clean (was 4 corner literals).
- `scripts/drive tree`: 0 `[unlabeled]` on the empty window, browse, result, password sheet,
  review, format page (zip and 7z, Encrypt on), Split sheet, queue, Settings (all tabs) and
  File Types; close button 16×16.

- Crate's own defaults: the pass changed only Crate's `settings` (format, encryption) and
  window frames; `settings` was deleted again afterwards (it didn't exist before) and the
  main/Settings window frames were put back. New keys `NSTableView … ArchiveColumns.v2`
  are the new column autosave.

### Not done, and why

- **Active-window states after the last fixes:** the one active check (above) found #32;
  after fixing it the owner was back (idle 0–36 s for the next ~10 minutes), so the filter
  wasn't typed into again (AX can't set SwiftUI's search binding). The fix was checked by
  expanding a 7-level archive instead (`light-63-deep-expanded.png`). Focus rings, Quick
  Look and format-card hover (in code, `FormatCardStyle`) not observed: not tested, owner
  active.
- **Drop highlight** (accent ring while dragging over a page): needs a real drag; concentric
  by construction, not measured.
- **Split sheet row:** the size field measures 26 pt border to border, the stepper and
  pop-up 24 pt. These are the system's regular control metrics; kept.
- **Footer summary centring:** with the Extract to: menu on the left, the summary is centred
  in the space that's left, so it sits right of centre below ~620 pt. It never overlaps.
- **macOS 14:** `toolbar(removing: .title)` needs macOS 15, so Sonoma keeps the title and the
  collapsing search field; at narrow widths filtering can still overflow there.
- **Disabled form while creating:** labels stay full strength while the controls dim
  (SwiftUI `Text` doesn't follow `.disabled`); Apple's own forms do the same.

### SlopKit notes (not edited)

- `AboutView` uses `Divider()`: a 1 pt (2 px) line under the version (measured).
- `FileQueueView` with `.fileQueueSizeStyle(.neutral)` shows "2.2 MB → 2.2 MB" for an
  extraction (packed → unpacked), which reads as redundant; a style that shows only the
  result size would suit extractors.
- `FooterBar` (fixed 40 pt footer with hairline) and `FormatCardStyle` (selectable card
  with hover/pressed states) are in `Pages.swift`, named to move to SlopKit; `Hairline`-style
  fixed footers now exist in several apps.

### Screenshots (`/tmp/slopapp-polish/crate/`)

`before-l-*.png` (light, before fixes). After, in `light-NN-*.png` and `dark-NN-*.png`:
01 empty, 02 browse, 03 selection, 04 result, 05 password, 06 wrong password, 07 unlocked
(lock icons), 08 empty archive, 09 not an archive, 10 1,001 items, 11 type-select, 12 list
scrolled under the header, 13 review, 14 format, 15/16 Encrypt (zip/7z), 17 mismatch
warning, 19 created, 20 one-file review, 21 Split sheet (`-sheet`), 22 queue password, 23
queue, 24–27 Settings (General, File Types `-sheet`, Advanced, About), 40 truncated banner,
41 failure line, 42 unsafe banner, 43 Convert, 44 big-file review, 45/46 progress, 47 after
Stop, 48 minimum-width browse, 49/50 minimum-width format page; light only: 57/58 the whole
format page with zip and 7z encryption options, 60 active window with selection, 62 active
password sheet, 63 deeply nested archive expanded.

### Golden Gate + light/dark (2026-11-06)

Owner: "ensure all the apps are optimized for dark/light mode AND look like they fit in with
macOS Golden Gate" (macOS 27.2). Checked against design system §4 "Fitting in on macOS 27
Golden Gate" and §10 items 25–26. Defaults backed up first (`defaults export`) and restored
after; test archives only in `/tmp/crate-test/`.

| Check | Before | After |
|---|---|---|
| Menus text-only | Extract to: pull-down showed folder icons beside Desktop, Downloads and recent folders (`menubar.dock.rectangle`, `arrow.down.circle`, `folder`) | Text only; the checkmark on the current choice is the only image (`gg/light-menu-extract-to-1.png`). Main menu, outline context menu, result/review context menus, Save to: and Split pull-downs were already text |
| Inactive windows: format cards | Selected card kept its accent fill, 2 pt accent ring and accent symbol in a background window | `Color.selectionTint` / `.selectionRing` / `.windowAccent` with `controlActiveState`: grey fill, grey ring and grey symbol when inactive, accent when key (`gg/pair-16-format-encrypt-7z.png` inactive, `gg/pair-active-format.png` active) |
| Inactive windows: archive outline | — | `NSOutlineView` already uses the unemphasized selection grey when inactive and accent when key (`gg/pair-03-browse-selection.png`, `gg/pair-active-browse.png`) |
| Inactive windows: drop zone | — | SlopKit `DropZone`; Crate's in-window drop ring stays accent: it only shows while something is dragged over the window, as Finder's does |
| `.secondary` text (≈3.1:1 in light mode on 27.2) | The format page's footer, the only place that says why Create is off ("Enter a password, or turn off Encrypt."), was `.secondary` | `.primary` for that next-step text (`isNextStep`); `.secondary` kept only for supporting text (summaries, hints, details) |
| Sidebar / toolbar / glass | — | No sidebar. Standard SwiftUI toolbar, the system's glass; no drawn strips or translucent fakes (the banner's 8 % orange tint is a status fill, not glass) |
| Live appearance change | Not tested | New test hook: writing `appearance:dark` / `appearance:light` to `$CRATE_SNAPSHOT_DIR/request` switches Crate live. Browse (AppKit cells, lock icons, hairlines), format cards and the password sheet all followed with no stale colours (`gg/live-dark-browse.png`, `gg/live-dark-format.png`, `gg/live-light-password-1.png`) |
| Hairline (now 1 pt of layout) | Footer hairline pixel at y 459.5 pt, bar 40 pt | Pixel at 459.0 pt, then the 40 pt bar from 460: every footer is 41 pt and identical in browse, create, progress and queue; `#EAEAEA` light, `#4C4F51` dark |
| FileQueue (SlopKit changed) | — | Re-shot: rows, strip and footer fine in both modes (`gg/pair-23-queue.png`) |
| Pure black/white, one-mode colours | — | None drawn: fills are `Color.primary` opacities, semantic `NSColor`s, accent, status colours; card fills, banner tint and orange text measured readable in both |

Side-by-side light | dark pairs of every surface: `/tmp/slopapp-polish/crate/gg/pair-*.png`
(empty, browse, selection, result, password and wrong password, empty archive, not an
archive, 1,001 items, review, format pages, mismatch, created, Split sheet, queue, Settings
tabs, File Types, banners, failure line, Convert, progress, after Stop, minimum width).

Gates: `scripts/check.sh Crate --perf` all pass (lint, 88 tests, bundle, smoke; idle CPU
0.015 %, footprint 29.3 MB, busy machine). Not done: hover on format cards and focus rings
over many surfaces still not observed with the real pointer (owner present most of the
session; one 60 s window was used for the active-window shots).
