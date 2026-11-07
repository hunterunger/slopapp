# Squish research (inspired by Squash + PDF Squeezer)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied on
> 2026-11-02: **Squash 3.3.0 (913)** (Setapp build, /Applications/Setapp/Squash.app) and
> **PDF Squeezer 4.9 (911)** (Setapp build, /Applications/Setapp/PDF Squeezer.app), both
> read-only, plus Realmac's Squash docs (which now describe **Squash 4**, ahead of the
> Setapp build), Witt Software's site/FAQ, App Store and Setapp reviews. We study how they
> work so we don't reinvent the wheel. We never copy their names, icons, artwork, wording,
> sounds or signature visuals.
>
> Neither app was running; both were launched, walked through and quit. No setting was
> toggled. Only files created for this study (`/tmp/squish-test/research/`, made from
> macOS wallpapers) were handed to them with `open -a`; nothing was exported or saved by
> the originals. The test PDF's "Open Recent" entry was cleared afterwards. Sidebar values
> the installed Squash showed are the owner's last-used values, so they are not reported
> as defaults.

## The job

Someone has files that are too big for where they're going: a 15 MB phone photo for a web
page, a folder of screenshots for a blog, a 40 MB scanned PDF that an email, a portal or an
AI upload limit rejects. They want the same files, visibly smaller, without learning about
codecs or DPI, and without risking the originals. "Done" is a list that says
"14.6 MB → 880 KB, −94%" next to every file and a Reveal button. **The one interaction that
matters: drop files on the window → they shrink immediately with sensible settings → the
smaller copies sit next to the originals.** Squash (images) and PDF Squeezer (PDFs) both
grew into feature-heavy tools; Squish is the drop-and-done core of both in one window.

## Who and when

- Preparing photos/screenshots for a website, CMS or blog (resize to a max edge, strip GPS).
- Getting a PDF under an upload/email limit (contracts, scans, portfolio PDFs, AI uploads;
  one Setapp reviewer uses PDF Squeezer to get under a 30 MB chatbot limit).
- Converting iPhone HEIC to JPEG for someone who can't open HEIC.
- Removing location/camera metadata before sharing a photo publicly.
- Batch: a folder of 50–500 images after a shoot or export.

Frequency: a few times a week, in bursts; each use is 10 s–2 min. Settings are set once.

## The two originals at a glance

| | Squash 3.3 (installed) / Squash 4 (docs) | PDF Squeezer 4.9 |
|---|---|---|
| Window | 900×625. Empty state: big photo symbol, one line, "Import Images…" button. Toolbar: presets-sidebar toggle, settings-panel toggle, mute (background music), trash (clear). After import: **grid of large image cards** (format badge + size) on the left, a scrolling **stack of "node" cards** with on/off switches on the right, a full-width blue **Export Images** button at the bottom. Squash 4 changes the grid to a **list** (thumb, output name, "2.1 MB → 93 KB", red if bigger), adds a before/after split preview in the middle and an Activity ring. | 1000×528. Empty state: download symbol + one line ("drag and drop PDFs or folders"). Toolbar: sidebar, profile popup, Compare, Info/Settings inspector toggle, Share, Save, Save As…. After a drop: center shows the selected file's big thumbnail with **"2.7 MB → 879 KB" and "Size reduced by 66%"**; sidebar lists files when there are several; right inspector shows profile settings or file info. |
| When work happens | Squash 3: nothing until you press Export. Squash 4: sizes are calculated in the background on import ("Automatically compress", on by default), files written only on Export. | Compression starts **on drop** with the default profile (setting, on by default). The result stays in memory; **nothing is written until Save / Save As / drag-out / Share**. |
| Output location | Export node "Save images to the specified directory" (off by default → you're asked for a folder at export time). Squash 4: Choose Folder…, Same Folder as Original, Subfolder of Original (`squashed`/`minified`/`compressed`/custom), 5 recent folders. | **Save** replaces the original (asks "overwrite?" once, with don't-ask-again; original goes to the Trash by default). **Save As** opens a save panel at "Last folder" (default) / "Folder of original file" / a chosen folder. CLI and Quick Action save at the input location. |
| Naming | Squash 3: Rename node off by default (prefix/suffix/replace). Squash 4: token template (`{{original}}-squashed`, number, date, dimensions, AI "Describe" by default on capable Macs), lowercase, whitespace handling; duplicates in a batch get `-2`, `-3`. | Save As keeps the name; optional "Append a postfix" (off by default, value `-compressed`). CLI: name collisions get a number ("Work 2.pdf"). |
| Overwrite | Off by default: existing files are kept and the new one gets a numbered suffix (`photo-1.jpg`). On: replaces, with a warning when it would replace originals. A warning triangle marks rows whose export would replace the source. | Save = replace. "Move file to trash before replacing it" on by default; "Move original file to Trash after Save As" off. **Restore… (⌘R)** brings back the original while the app is open (not after quit). |
| If output is bigger | Exports it anyway; the after size shows in red; docs tell you to lower quality/resize/change format. | Refuses: "could not be reduced with the selected profile, try a stronger one." Optional fallback: "If the compression fails try up to N more profiles" (0 by default) walks down the profile list. |
| Metadata | Squash 3: "Preserve image metadata" off → **stripped by default**; "Retain Dates" (file creation/modification) off. Squash 4: five Remove checkboxes (Location, Camera & lens, Date & time, Author & copyright, Other), **all on by default**; orientation, DPI, color model and profile name always kept; pixels saved upright. Exports converted to sRGB. | Per profile: custom title/author/subject/keywords/creator/producer, update modification date (on), update both dates (off); Advanced: remove thumbnails, app data (on), document tags, article threads, web capture info, output intents. |
| Resize | None, Width, Height, Max Size (longest edge, never upscales), Max Width/Height (box, never upscales), Percent, Free size (stretches; swap button). | Image "Maximum Resolution" in dpi per profile (downsample above it). |
| Quality | Per format: JPEG quality + Progressive; PNG algorithm (Squash 4: oxipng default, Crush, Zopfli, Standard, pngquant lossy); HEIC quality; WebP lossy/lossless; AVIF quality + effort; JPEG XL; TIFF. Squash 4 slider has named stops Low/Medium/High/Best + custom %. | Profiles. Built-in: **Light 300 dpi / 80%**, **Medium 144 dpi / 75%**, **Strong 72 dpi / 50%** (JPEG quality). Topmost profile = default. Automator/Quick Action default: 72 dpi / 60%. |
| Formats in | Anything macOS decodes (JPEG, PNG, TIFF, HEIC, RAW, DNG, PSD, GIF…). | PDF 1.0–2.0, password-protected (asks; passwords re-applied to output). Folders (+ subfolders, on by default). |
| System integration | Open With (document types `public.image`), Shortcuts actions (Resize, Export, Export Using Preset, Copy Metadata, Apply Adjustments), Squash 4 watched folders. No Share/Finder extension, no Services. | Shortcuts (Intents extension: compress, convert to bitmap, extract images), Automator action, installable **Finder Quick Action** (an Automator Services workflow: compress, save at input location, replace existing → original to Trash) and **Folder Action**, CLI `pdfs` (symlink to /usr/local/bin). Dock-icon drop, Share button. |
| Extras | Adjustments, effect/border packs, watermarks, crop, rotate, highlighter/redact, presets, AI renaming, "Zen" background music, interface sounds, confetti, themes, 4 Dock icons, Copy Squashed, drag-out export. | Compare mode (side-by-side), per-profile result cached in the profile popup ("Medium (879 KB, 66%)"), sort by name/size/ratio/date/status, total-saved status bar, extract images (⌘E) / text (⌘T), convert to bitmap (⌘B), PDF/A-4 profile, profile import/export (`.pdfscp`), notifications, log file. |

### Squash settings panes (installed 3.3)

| Pane | Setting | Value seen / default |
|---|---|---|
| General | Theme | Dark (3.2 made dark the default; options Automatic/Light/Dark in v4) |
| | Interface sounds; Export completed sound | on; on |
| | Default View | Image Grid |
| | Zen Track | mute / shuffle / three ambient tracks |
| | Dock Icon | four icon variants |
| Effects | Installed effect packs (Analog Borders, Analog Filters, Basic Set) | all enabled; Remove |
| *Squash 4 adds* | Replace previous images (on), Automatically compress images (on), Show exported images in Finder, confetti, barcode search, beta updates, share usage data (off); Watched pane (folder + preset + Save To: subfolder `Squashed` / replace originals / preset folder; open at login; notify). | |

### PDF Squeezer settings panes (installed 4.9)

| Pane | Setting | Value seen / default |
|---|---|---|
| General | Include files from subfolders when adding a folder | on |
| | Adding a new file starts the compression with the default profile | on |
| | Show notification after all compressions have been completed | off |
| | Switch to comparison mode after the compression has completed | off |
| | Move file to trash before replacing it | on |
| | Move original file to Trash after Save As | off |
| | If the compression fails try up to N more profiles | 0 |
| | Closing the main window quits the entire app | on |
| | Save Dialog: Append a postfix | off (`-compressed`) |
| | Save Dialog: Open save dialog at | Last folder / Folder of original file / Choose… |
| | Reset "Don't Ask Me" warnings; Revert to Factory Defaults | buttons |
| Compression Profiles | Ordered list (name, dpi, quality); add, remove, up/down, Duplicate, Export, Import, Reset; "Use new compression engine" | Medium 144/75%, Strong 72/50%, Light 300/80%; new engine on |
| Automation | Shortcuts (Open), Automator (Open), Quick Action (Install), Folder Action (Install/Manage), CLI (Install, Help) | — |
| Software Update | Setapp notice, version, Release Notes | — |

**Profile editor** (main-window inspector, four tabs):
- *Images*: Optimize images (on; off = leave images untouched), Image Quality slider,
  Maximum Resolution (dpi combo), Color Profile (Original / RGB / CMYK / Grayscale),
  Reduce color complexity (on), Clip invisible parts of images (on), Remove alternate
  images (on), Downsample monochrome scans (on; tooltip warns small scanned text may
  suffer).
- *Fonts, Annotations, Form Fields*: remove unused glyphs (on), remove standard fonts (on),
  merge embedded fonts (on), flatten remaining annotations, remove annotations except
  fields/links, flatten form fields, flatten links (all off).
- *Metadata, Resources* and *Advanced*: see table above. Profile title at the bottom.

## Menus and shortcuts

**Squash 3.3**: File: Import Images… ⌘O, Export All Images, Export Selected Image As… ⌘E,
Remove Image ⌫, Close ⌘W, Close All ⌥⌘W. View: Previous/Next Image (arrows), Show Editor,
Show Original Image, Hide Split View, Full Screen. Zen: Stop ⌥⌘P, Shuffle ⌥⌘S, three
tracks. Help: Help, Forum, Website. *Squash 4 (docs)*: ⌘S calculate, ⌘E Export All,
⇧⌘E Export Selected As…, ⌘⌫ Remove All (confirm), ⌫ remove, ⇧⌘C Copy Original,
⌥⌘C Copy Squashed, ⌘+/⌘−/⌘0/⌘9 preview zoom, ⌥ while importing = add instead of replace,
⌘Z undo a replace-drop.

**PDF Squeezer 4.9**: App menu links to its iOS and Windows versions. File: Open… ⌘O, Open
Recent, Remove ⌫, Remove all files ⇧⌫, Close ⌘W, Close All ⌥⌘W, Save ⌘S, Save as… ⇧⌘S,
Save all ⌥⌘S, Save all as… ⌥⇧⌘S, Extract Images… ⌘E, Extract Text… ⌘T, Convert to
Bitmap… ⌘B, Stop Compression ⌘., Restore… ⌘R, Reveal in Finder ⇧⌘R. View: Customize
Toolbar, Sidebar ⌃⌘S, Show Sidebar (Automatically/Always), Sort by (Name, Original Size,
Compression Ratio, Date Added, Status, Reverse), Indicate Compression Result, Statusbar,
Zoom to Fit ⌘9 / In ⌘+ / Out ⌘−. Help: Help ⌘?, Save Log File….

Neither has global shortcuts or a menu bar item.

## Feature inventory

Priority: **must** (v1 isn't worth shipping without it), **should** (v1 if cheap, else
v1.1), **later**, **skip** (with reason).

| # | Feature | How the originals do it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Drop files/folders on the window | Both; PDF Squeezer recurses subfolders by default | must | `DropZone` empty state; folders recurse; unsupported files are listed as skipped, not silently dropped. |
| 2 | Choose Files… (⌘O) | Both | must | Open panel, images + PDFs + folders, multiple selection. |
| 3 | Start on drop | PDF Squeezer: on drop (default). Squash: only on Export | must | Drop = process + write immediately (drop-and-done). Builder decision. |
| 4 | Queue rows with before → after, % saved | Squash 4 list rows; PDF Squeezer center readout | must | Row: thumbnail, name, "14.6 MB → 880 KB", "−94%", per-item progress, Reveal; `.monospacedDigit()`. |
| 5 | Bounded parallel processing | Squash 3 reviewed as one-at-a-time (a 150-file job "took hours"); PDF Squeezer 4.8.2 added multi-core | must | Task group capped at ~`activeProcessorCount − 1` for images, 2 for PDFs (memory). |
| 6 | Safe output: alongside with suffix | Squash 4 "Same folder" + rename template; PDF Squeezer Save As postfix (off) | must | Default `name-<suffix>.ext` next to the original. Never overwrite an existing file: append " 2", " 3". |
| 7 | Output to a chosen folder | Squash Choose Folder… / recents | must | Bottom-bar "Save to" menu: Next to Originals / folder… / recent folder. Remember bookmark. |
| 8 | Replace originals (opt-in) | PDF Squeezer Save (original to Trash, confirm once); Squash Overwrite + same folder | should | Off by default. When on: original goes to the Trash (`trashItem`), confirm the first time. Undo = Put Back from Trash. |
| 9 | Never make a file bigger | Squash writes it (red); PDF Squeezer refuses with an error | must | If not smaller, keep the original, write nothing, row says "Already as small as it gets – kept original" (wording TBD). See open question for format changes. |
| 10 | Quality presets + custom | Squash slider stops Low/Medium/High/Best + %; PDF Squeezer Light/Medium/Strong profiles | must | One control for both types: Light / Balanced (default) / Strong / Custom… (custom = quality % and PDF dpi). See defaults table below. |
| 11 | Resize (images) | 7 modes in Squash | must | Off, or "Longest edge" with presets (1280, 1920, 2560, 3840) + custom px; never upscale. Percent/box modes later. |
| 12 | Metadata stripping | Squash strips by default; granular in v4 | must | Toggle "Remove metadata" on by default. Keep orientation (bake pixels upright) and color profile. "Keep everything but location" later. |
| 13 | Format: keep or convert | Squash: JPEG/PNG/TIFF/HEIC/WebP/AVIF/JPEG XL | must (keep, JPEG, HEIC, PNG) | Default "Same as original". JPEG/HEIC/PNG via ImageIO. AVIF if `CGImageDestinationCopyTypeIdentifiers` lists it (true on macOS 27). **WebP can't be encoded by ImageIO** (decode only): see open questions. |
| 14 | PDF image downsampling | PDF Squeezer engine (Pdftools SDK) | must | `PDFDocument.write(to:withOptions:)` with a `QuartzFilter` (dpi + JPEG quality). Validated here: a 2-page 15.4 MB letter PDF → 425 KB (300 dpi/0.8), 111 KB (144/0.75), 31 KB (72/0.5). |
| 15 | Per-item cancel / retry, Stop all | PDF Squeezer Stop ⌘.; Squash 4 Activity popover | must | Row cancel while running; Retry on failure; ⌘. stops the batch. |
| 16 | Reveal in Finder | PDF Squeezer ⇧⌘R; Squash Show in Finder | must | Per row + "Reveal All" for the batch (selects all outputs). |
| 17 | Clear list | Squash trash button / ⌘⌫; PDF Squeezer Remove all ⇧⌫ | must | Removes rows only, never files. |
| 18 | Batch total | PDF Squeezer status bar (total saved) | should | Footer line: "8 files · saved 23.4 MB (−71%)". |
| 19 | Re-run with new settings | Squash 4 recalculates live on setting change | should | If options change after a batch, offer "Apply to All Again" (re-processes from originals, replaces our own outputs). Disabled for rows whose original was trashed. |
| 20 | Drop on Dock icon / Open With | Both register document types | should | `CFBundleDocumentTypes` for `public.image` + `com.adobe.pdf`, role Viewer, rank Alternate (never steal defaults). |
| 21 | Finder Quick Action / Services | PDF Squeezer installs an Automator workflow; Squash has none | should | Cheapest native path: `NSServices` in Info.plist ("Compress with Squish", file types image + PDF) → app opens and enqueues with current settings. No extension target. Appears under Quick Actions/Services in Finder's context menu once enabled. |
| 22 | Quick Look a result (Space) | Squash preview; PDF Squeezer Compare | should | `QLPreviewPanel` on the selected row's output. |
| 23 | Drag a result out of a row | Both | should | Row is a drag source for the output file URL. |
| 24 | Password-protected PDFs | PDF Squeezer asks, re-applies passwords | later | v1: skip with a clear row error ("Locked PDF. Remove the password in Preview, then try again."). |
| 25 | PDF grayscale / color conversion | PDF Squeezer Color Profile | later | Quartz filter `ColorSettings`; cheap to add as a Custom option later. |
| 26 | Before/after visual compare | Squash split preview; PDF Squeezer Compare mode | later | Quick Look of output covers v1. |
| 27 | Presets (save named settings) | Squash presets; PDF Squeezer profiles + `.pdfscp` import/export | later | Built-in Light/Balanced/Strong cover v1. |
| 28 | PNG lossless optimisation (oxipng/zopfli) / lossy palette | Squash | later | ImageIO PNG re-encode saves ~0% (measured: 2,995,140 → 2,993,755 B). Needs a third-party lib; pngquant/libimagequant are GPL (not allowed). Resize + strip + never-bigger keep v1 honest. |
| 29 | Watched folders | Squash 4 | later | Needs the app running/at login; out of scope for a drop-in window. |
| 30 | Shortcuts / App Intents | Both | later | One "Compress Files" intent with the preset. |
| 31 | Notifications when done | PDF Squeezer (off by default) | later | Only if the window is in the background for long batches. |
| 32 | Copy result to clipboard | Squash ⌥⌘C | later | |
| 33 | Retain file dates | Squash "Retain Dates" (off) | later | |
| 34 | Rename templates / AI names | Squash 4 | skip | Not the job. |
| 35 | Adjustments, effects, borders, watermarks, crop, rotate, redact | Squash | skip | Image editor territory. |
| 36 | Extract images/text, convert to bitmap, PDF/A, PDF metadata editing, font/annotation flattening | PDF Squeezer | skip | Specialist PDF tooling; not "make it smaller". |
| 37 | Background music, interface sounds, confetti, themes, alternate Dock icons | Squash | skip | Design system: quiet, native, no custom themes. |
| 38 | CLI, Automator action, Folder Action | PDF Squeezer | skip | Services + (later) Shortcuts cover automation. |
| 39 | Free-tier export limits, cross-platform upsell menu items | Squash 4, PDF Squeezer | skip | Not our model. |

### Suggested defaults (for the build)

| Preset | Images (JPEG/HEIC quality) | PDFs (max image dpi / JPEG quality) | Basis |
|---|---|---|---|
| Light | 0.85 | 300 / 0.80 | PDF Squeezer "Light" |
| **Balanced** (default) | 0.75 | 144 / 0.75 | PDF Squeezer "Medium"; macOS 27's own Reduce File Size Quartz filter is 144 dpi / 0.70 |
| Strong | 0.55 | 72 / 0.50 | PDF Squeezer "Strong" |
| Custom… | 1–100 % | dpi field + quality % | |

Other defaults: format Same as original; resize Off; Remove metadata on; save Next to
Originals with suffix (open question for the exact word); Replace originals off.

## Key flows

### Flow 1: drop and done (main job)
1. Launch → window shows the drop zone ("Drop images or PDFs here", "or click to choose",
   ⌘O). The bottom bar already shows the current options (Balanced, Original size,
   Same format, Remove metadata, Next to Originals).
2. Drop 12 photos and a PDF (or a folder). The drop zone shrinks to a slim strip; one row
   per file appears instantly with a thumbnail and the original size.
3. Rows process in parallel (bounded); each shows a progress indicator, then
   "4.1 MB → 620 KB  −85%" and a Reveal button. A row that couldn't shrink says it kept the
   original; a failed row shows the reason and Retry.
4. Footer shows the batch total. Reveal All selects the outputs in Finder. Drop more files
   any time: they join the queue.

### Flow 2: change options
1. Pick Strong in the bottom bar (or Custom… → small popover with quality % and PDF dpi).
2. New drops use it. Already-finished rows get an "Apply to All Again" affordance.

### Flow 3: replace originals (opt-in)
1. Settings → "Replace originals" (or the Save-to menu). First use: one confirmation
   explaining originals go to the Trash.
2. Each output takes the original's name/location; the original is in the Trash.

### Flow 4: from Finder
1. Select files → right-click → Quick Actions / Services → "Compress with Squish".
2. Squish opens (or comes forward) and enqueues them with current settings.

### Flow 5: first run
1. No onboarding (both originals have none either beyond Squash's free-tier notice).
2. The first time we write next to a file in Desktop/Documents/Downloads, macOS may show its
   folder-access prompt. If denied: row error with "Choose a Folder…" to save elsewhere.

### What the originals do (for reference)
- *Squash 3*: drop → cards appear → set nodes on the right → Export Images → asked for a
  folder (if Export node is off) → files written. Squash 4: drop → sizes calculated in the
  background → Export.
- *PDF Squeezer*: drop → compressed with the default profile immediately → read
  "X → Y, reduced by Z%" → Save (replace, original to Trash) or Save As… (panel at last
  folder) or drag out / Share. Switching profile in the toolbar compresses again and caches
  each profile's result in the popup.

## Settings inventory (ours)

Settings (`⌘,`, `SlopSettings`): General, About. Everything per-batch lives in the bottom
bar; Settings holds the "where" rules.

| Setting | Default | Options | Notes |
|---|---|---|---|
| Quality preset | Balanced | Light / Balanced / Strong / Custom | Bottom bar, remembered |
| Resize | Off | Off / longest edge 1280/1920/2560/3840 / custom px | Bottom bar; images only |
| Format | Same as original | Same / JPEG / HEIC / PNG (/ AVIF if supported) | Bottom bar; images only |
| Remove metadata | On | toggle | Bottom bar |
| Save to | Next to originals | Next to originals / chosen folder / recent folders | Bottom bar menu |
| Suffix | TBD (open question) | text field | Settings → General; used when saving next to originals |
| Replace originals | Off | toggle (originals to Trash) | Settings → General, with one-time confirm |
| Launch at login | — | not shown | Window app; nothing to keep running |

## Permissions and system integration

- No Accessibility, Screen Recording or Full Disk Access.
- Slopapp ships direct and unsandboxed (docs/plan.md), so writing beside dropped files works,
  but TCC may prompt the first time we write into Desktop/Documents/Downloads or removable
  volumes. Handle denial per row (Flow 5).
- Document types (Open With / Dock drop), `NSServices` for Finder. No extensions, no login
  item, no network.

## UX patterns worth adopting

- **Result as a sentence.** PDF Squeezer's big "before → after" plus "reduced by N%" is the
  whole reward; our rows should read the same way at a glance.
- **Compress on drop, decide nothing first.** PDF Squeezer starts with the default profile
  the moment a file lands; Squash 4 at least calculates sizes. No modal before work.
- **Original goes to the Trash, not oblivion.** Both treat replacement as recoverable.
- **Named stops instead of raw numbers.** Squash 4's Low/Medium/High/Best and PDF Squeezer's
  Light/Medium/Strong hide codec numbers behind words, with Custom for the curious.
- **"Max size" never upscales.** Squash's longest-edge mode handles mixed portrait/landscape
  batches and leaves small images alone.
- **Collision-safe names.** Both add a number rather than overwrite; Squash flags rows that
  would replace a source.
- **Show which profile result you'd get.** PDF Squeezer caches each profile's result in its
  popup; a cheap version for us is the batch total updating after "Apply to All Again".
- **Folders just work** (recurse subfolders), and skipped files are reported.

## What we won't copy, and what we'll do better

- Not copying: names, icons, the orange/fruit or squeezing imagery, wording, sounds, music,
  themes, effect packs, `.pdfscp`-style profile files, free-tier limits.
- **Fast on big batches.** Bounded parallelism plus ImageIO thumbnail-based downsampling
  (measured here: 1920 px JPEG from a 15 MB, 6016 px original in ~7 ms encode). Squash's
  most common complaint is speed/one-at-a-time.
- **Never bigger.** Squash happily writes a larger file; PDF Squeezer errors out. We keep the
  original and say so in plain words.
- **One window for both types.** No choosing an app by file type.
- **Small surface.** Reviewers call Squash 3 bloated ("hundreds of options", no docs);
  we have five bottom-bar controls.
- **Writes by default, safely.** Squash makes you export; PDF Squeezer's main "Save" replaces
  the original. We write a suffixed copy next to the original on drop.
- **Native look and quiet.** System controls, accent color, no sounds.

## Edge cases

- **Inputs**: corrupt or zero-byte file; unsupported type (SVG, Word) → "skipped" row;
  duplicate drops of the same file; a folder with thousands of files (lazy thumbnails,
  bounded queue); iCloud placeholder files (reading triggers download; show "Downloading…");
  read-only/locked files and read-only volumes (fall back to error + Choose a Folder…);
  files that are our own outputs (don't re-squish `name-suffix` files dropped back in, or at
  least don't chain suffixes).
- **Images**: EXIF orientation (bake upright via `kCGImageSourceCreateThumbnailWithTransform`);
  alpha → JPEG (flatten on white or keep PNG; "Same format" avoids it); Display P3 / CMYK /
  16-bit / HDR gain maps (keep the color profile; don't silently clip to sRGB); animated
  GIF/APNG/HEICS (skip with message or keep first frame — choose); multi-page TIFF; RAW/DNG
  ("Same format" impossible → use JPEG); Live Photo HEIC with aux images; huge images
  (100+ MP: never decode full size when resizing, use the thumbnail API); HEIC encode needs a
  hardware encoder (some older Intel Macs can't — hide HEIC if not in the destination list);
  PNG re-encode rarely shrinks (never-bigger keeps the original).
- **PDFs**: vector/text-only PDFs (no gain → keep original); pages with giant media boxes
  where the "dpi" limit doesn't bite — measured: a 1-page 2.6 MB PDF ballooned to 28.8 MB
  through the Quartz filter, so the size guard is essential; encrypted PDFs (detect
  `isEncrypted`/`isLocked`, skip); forms, annotations, links and outlines must survive
  (use `PDFDocument.write` with the filter, not a CGContext redraw); PDF/A and tagged PDFs
  may lose conformance (warn later, not v1); scanned 1-bit pages.
- **Output**: name collisions (" 2"); suffix chosen so the output name already exists from a
  previous run (number, never overwrite); path length/Unicode names; output folder deleted or
  on an ejected disk; disk full mid-write (write to a temp file, then move atomically).
- **App**: quit mid-batch (finish current file or cancel cleanly; never leave half-written
  outputs — temp file + atomic move); sleep/wake mid-batch; window closed = quit
  (`SlopAppDelegate`) — confirm only if work is running; light/dark; VoiceOver labels for
  row buttons; Reduce Motion for row insertion; memory budget (< 120 MB idle; batch peak
  bounded by concurrency).

## Our v1 scope

- [x] Empty state is a `DropZone` ("or click to choose"); ⌘O opens a multi-select panel
      (images, PDFs, folders).
- [x] Dropping files/folders (recursive) starts processing immediately; more drops join the
      queue; unsupported files appear as skipped rows.
- [x] Row: thumbnail, name, before → after, % saved, per-item progress, Reveal; Cancel while
      running; Retry on failure; plain-language error text.
- [x] Bounded parallel processing (images ≈ cores − 1, PDFs 2); UI never blocks; ⌘. stops all.
- [x] Bottom bar: quality preset (Light / Balanced / Strong / Custom…), Resize (Off / longest
      edge presets / custom, never upscale), Format (Same / JPEG / HEIC / PNG, + AVIF when
      supported), Remove metadata toggle, Save to (Next to Originals / Choose Folder… /
      recents).
- [x] Images: ImageIO decode → optional downsample → re-encode at preset quality;
      orientation baked; color profile kept; metadata removed when the toggle is on (GPS,
      camera, dates, author all gone; verify with `mdls`/`exiftool`).
- [x] PDFs: `PDFDocument.write` with a Quartz filter at the preset's dpi/quality; text,
      links and annotations survive; locked PDFs skipped with a clear message.
- [x] Output next to original as `name-<suffix>.ext` (or into the chosen folder with the
      original name); never overwrites an existing file (adds a number); written via temp
      file + atomic move.
- [x] Never bigger: if the result isn't smaller, nothing is written and the row says the
      original was kept.
- [x] Replace originals: off by default; when on, originals go to the Trash after a one-time
      confirmation.
- [x] Footer batch total; Clear List (removes rows only); Reveal All.
- [x] Menu items with shortcuts for every action (Choose Files… ⌘O, Stop ⌘., Reveal ⇧⌘R,
      Clear List ⇧⌘⌫, Settings ⌘,); Settings has General (suffix, replace originals) and About.
- [x] Should (if cheap): Open With / Dock-icon drop, Finder Service "Compress with Squish",
      Space = Quick Look output, Apply to All Again ("Redo All"). Drag a row out: deferred.

## Open questions

1. **WebP output.** The roadmap lists WebP, but ImageIO on macOS 27 can't encode WebP
   (`CGImageDestinationCopyTypeIdentifiers` has no `org.webmproject.webp`). Options: drop
   WebP output from v1 (still accept WebP input), or add libwebp (BSD) as an approved
   dependency. Recommendation: drop for v1, offer AVIF where available.
2. **Suffix word.** Next-to-original naming: `-compressed`, `-small`, `-min`, or
   `-squished` (brand joke in a filename)? Recommendation: `-small`, editable in Settings.
3. **Format changes vs never-bigger.** If the user explicitly converts HEIC→JPEG and the JPEG
   is bigger, do we still write it (they asked for the format) and flag the growth, or keep
   the original? Recommendation: write it, show the growth in orange; never-bigger applies
   strictly only when the format is unchanged.
4. **"Kept original" with a chosen output folder.** Should we copy the original into the
   folder so the folder holds the complete batch? Recommendation: yes, copy and label the
   row "Copied original (already small)".
5. **PNG savings.** Without a PNG optimiser, PNGs only shrink via resize or conversion. Accept
   for v1, or approve an MIT/BSD-licensed optimiser later (no GPL pngquant)?
6. **sRGB conversion for web.** Squash converts everything to sRGB; we plan to keep the source
   profile. OK, or add "Convert to sRGB" when Format is JPEG/resize is on?

## Decisions (builder, 2026-11-03)

Answers to the open questions above, made autonomously (owner asleep):

1. **WebP output:** dropped for v1. WebP input works (convert to JPEG/HEIC/PNG/AVIF); with
   "Same Format" a WebP row is skipped with a hint to pick another format. The Format menu
   is built from `CGImageDestinationCopyTypeIdentifiers`, so WebP appears by itself on a
   macOS that can write it. AVIF is offered (writable on macOS 27).
2. **Suffix:** `-small` (plain word, short), editable in Settings. Empty or unsafe suffixes
   fall back to `-small` so "next to originals" can never clobber the original.
3. **Format change vs never-bigger:** never-bigger is strict (the brief's rule): a result
   must be at least 2% smaller or nothing is written and the row says the original was kept.
4. **Kept originals with a chosen folder:** not copied in v1 (the row says why). Later.
5. **PNG savings:** solved without a dependency. Squish has its own palette quantizer
   (median cut + 2 k-means passes + serpentine Floyd–Steinberg, with dominant flat colors
   reserved exactly and never dithered) and an indexed-PNG writer (zlib level 9, 1/2/4/8-bit
   depth, tRNS, sRGB/iCCP). Screenshots shrink ~70% with no visible change; photos as PNG
   ~68% with light dither grain. High Quality keeps PNGs lossless.
6. **sRGB:** the source color profile is always kept (P3 stays P3).
7. **Presets:** High Quality / Balanced / Smallest File / Custom. JPEG quality 0.80 / 0.70 /
   0.55: Apple's JPEG encoder is step-shaped (0.70 → 1.87 MB, 0.75 → 2.59 MB on the test
   photo), so the presets sit just under the steps. PDFs 220/144/96 dpi at 0.80/0.70/0.50
   (72 dpi made text scans unreadable; 96 is the floor).
8. **When files are written:** on drop (drop and done), like PDF Squeezer.
9. **Unsupported files** (Word, text) are refused by the drop target (standard Mac drop
   behaviour) rather than listed as skipped rows; supported-but-unwritable ones (WebP, RAW,
   GIF, animations) are listed with the reason.
10. **Encrypted PDFs** that open without a password (owner password only) are skipped too:
   saving them would silently strip their protection.
11. **Replace originals** keeps the original's creation/modification dates on the new file.

## Build notes (2026-11-03)

- Targets: `SquishCore` (settings, `Squisher`, `ImageCompressor`, palette PNG,
  `PDFCompressor`, output naming behind a `FileStore` protocol, `MemoryBudget`), `Squish` (app),
  using SlopKit's `FileQueue` (moved there after round 1),
  `SquishBench` (headless benchmark of the real queue + compressor).
- Writes are atomic: temp file in the destination folder, then `renamex_np(RENAME_EXCL)` so
  two files finishing at once can't claim the same name. Replace mode writes first, trashes
  the original second, takes its name third.
- Tests (after round 1): 42 Squish core tests + 15 FileQueue tests in SlopKit, all green. `scripts/check.sh Squish --perf`
  green: launch 125 ms, first window 303 ms, idle CPU 0.02%, footprint 27.8 MB.
- Benchmarks (M-series, 14 cores, default concurrency 8):
  - SquishBench, 200 × 2400 px JPEGs (1.0 MB): 0.62 s (323 files/s); 1 at a time 4.26 s.
  - SquishBench, 50 × 3840×2160 JPEGs: 0.58 s; to HEIC 1.20 s (−71%).
  - SquishBench, 50 × 2880×1800 screenshot PNGs (palette): 1.43 s (−72%).
  - In the app, 200 × 1 MB JPEGs: 0.85 s; 200 × 3.3 MB 8 MP JPEGs: 2.16 s, −41%. Main-thread
    lag probe (`SQUISH_DIAGNOSTICS`): worst tick 28–40 ms while processing; one 60–90 ms
    hitch when the first rows appear. Accessibility tree answers in ~0.1 s mid-batch.
  - Footprint 60–100 MB under a 200-image batch, back to ~64 MB after Clear List.
- Fixtures: `swift apps/Squish/Tools/make-fixtures.swift /tmp/squish-test` (photos with
  EXIF+GPS, a screenshot PNG, HEIC, WebP via cwebp, animated GIF, broken/empty files,
  scanned/text-only/locked PDFs, a 200-file batch). Visual before/after checked for the
  photo JPEG, screenshot PNG (flat areas identical, text identical), photo PNG and a scanned
  PDF page.
- Walkthrough (release build, `scripts/drive`, light + dark): empty state, `open -a` with
  every fixture (all 12 outcomes correct), menus, custom quality and size popovers, Replace
  Originals confirmation + in-place replace (with `SQUISH_TRASH_DIR`), Redo All after a
  preset change (overwrites its own outputs, no " 2" copies), Quick Look on Space, Delete
  removes rows, Settings and About, Finder service via `NSPerformService`. No `[unlabeled]`.
- Deferred: drag a row out, copying kept originals into a chosen folder, named presets,
  PDF grayscale, compare view, Shortcuts.

## Sources

- Squash docs (Squash 4): [index](https://docs.realmacsoftware.com/squash-docs/llms.txt),
  [Main Window](https://docs.realmacsoftware.com/squash-docs/quick-guide/main-window),
  [Format](https://docs.realmacsoftware.com/squash-docs/quick-guide/nodes/format),
  [Resize](https://docs.realmacsoftware.com/squash-docs/quick-guide/nodes/resize),
  [Privacy](https://docs.realmacsoftware.com/squash-docs/quick-guide/nodes/metadata),
  [Export](https://docs.realmacsoftware.com/squash-docs/quick-guide/nodes/export),
  [Rename](https://docs.realmacsoftware.com/squash-docs/quick-guide/nodes/rename),
  [Settings](https://docs.realmacsoftware.com/squash-docs/quick-guide/preferences),
  [Watched Folders](https://docs.realmacsoftware.com/squash-docs/quick-guide/watched-folders),
  [Keyboard Shortcuts](https://docs.realmacsoftware.com/squash-docs/quick-guide/keyboard-shortcuts),
  [Presets](https://docs.realmacsoftware.com/squash-docs/quick-guide/presets),
  [FAQ](https://docs.realmacsoftware.com/squash-docs/extras/faq)
- [Squash release notes (3.0–3.3)](https://www.realmacsoftware.com/squash/releasenotes/)
- [Squash Setapp reviews](https://setapp.com/apps/squash/customer-reviews)
- [PDF Squeezer product page](https://witt-software.com/pdfsqueezer/),
  [Witt Software FAQ](https://witt-software.com/en/faq/)
- [PDF Squeezer 4 on the Mac App Store](https://apps.apple.com/app/id1502111349)
- [PDF Squeezer Setapp reviews](https://setapp.com/apps/pdf-squeezer/customer-reviews)
- [Macworld PDF Squeezer 4 review](https://www.macworld.com/article/234641/pdf-squeezer-4-review.html)
- Apple: [PDFDocumentWriteOption](https://developer.apple.com/documentation/pdfkit/pdfdocumentwriteoption)
  (`saveImagesAsJPEG` / `optimizeImagesForScreen`, macOS 13.4+; tested here: no effect on a
  JPEG-image PDF, so the Quartz filter route is needed);
  `/System/Library/Filters/Reduce File Size.qfilter` (144 dpi, 0.7, max 2400 px on 27.2).
- Installed apps: Squash 3.3.0 (913) and PDF Squeezer 4.9 (911) bundles (menus, Settings
  panes, profile inspector, Info.plist document types, Automator/Quick Action workflow
  defaults, `pdfs --help`). Local measurements: `/tmp/squish-scripts/*.swift` on test files
  in `/tmp/squish-test/research/`.

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.

### Round 1 (2026-11-03)

Tester verdict: very positive. No blockers or majors. Triage by the coordinator, fixed by
the builder; all gates re-run green (`scripts/test.sh SlopKit Squish Awake`, `scripts/check.sh
Squish --perf`, walkthrough light + dark, no `[unlabeled]`).

| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
| F1 ⌘W / File ▸ Close disabled in Settings and About | minor | accept | SwiftUI's Close only targets the key window. Replaced it with a Close (⌘W) that closes the frontmost of our windows. Verified on Settings and About. |
| F2 Re-adding a listed file made a duplicate row, a "-small 2" copy and double-counted savings | minor | accept | `FileQueue.add` now runs a finished file again in its existing row, passing its previous output so it's overwritten. Verified: dropping the samples twice leaves 12 rows and no " 2" files. Test added. |
| F3 Compression ▸ Custom… (⌘4) didn't reopen the popover once Custom was chosen | minor | accept | The menu is now toggles: Custom… always opens the popover. This also removed the stray separator. |
| F4 Text cut off in both Custom popovers; the quality popover hung over the window edge | minor | accept | Redesigned both popovers (title, stacked layout, `fixedSize` captions, Done/Apply). They're anchored over the bar so they stay inside the window. The size field is focused with its text selected. |
| F5 An empty Name suffix silently became "-small" | nit | accept | Empty is refused: it goes back to "-small" on Return or when Settings closes, and the caption says why. |
| F6 Bottom-bar icons disappeared when crowded and never came back | nit | accept | Replaced `ViewThatFits` with a measured decision (needed width with icons vs window width). Verified 520 → 760 → 520 → 600 px. |
| F7 Help ▸ Squish Help said help isn't available | nit | accept | It now opens the app's README on GitHub (Brand.repoURL + /tree/main/apps/Squish). |
| F8 "Cancelled" spelling, stray Compression separator, inconsistent pop-up accessibility names, slider not settable | nit | accept | "Canceled" (US). Separator gone (F3). Pop-ups are named Quality / Size / Format / Save To with the choice as their value; the icon carries the same description, because AppKit sometimes reads it instead. The custom quality now has a typeable % field next to the slider (settable via Accessibility). |
| Memory: ~860 MB peak in a 200-photo AVIF batch | — | accept (partly met) | Added `MemoryBudget` (256 MB of estimated in-flight cost; one file always runs), an autoreleasepool per file, and returning freed pages after heavy files and batches. Apple's AVIF encoder alone needs ~400 MB for one 8 MP photo, so AVIF now runs one file at a time (faster than before: 44 s vs 53 s headless). The ~300 MB target is met for JPEG/HEIC/PNG, not for AVIF or very image-heavy PDFs. In-app peak for 200 × 8 MP photos: same format 104 MB, HEIC 259 MB, AVIF 526 MB (was ~860), back to 97 MB after the batch. Headless: AVIF 1.47 GB → 426 MB. |
| Expected: Undo / Put Back after Replace Originals | — | accept | Replace records where each original went (`Replacement`). Edit ▸ Undo undoes the last batch; the row's context menu has Put Back Original; File ▸ Put Back Originals works on the selection or all. The compressed copy goes to the Trash; the row says so. Tests cover same-format and format-change put-back. |

Also this round: the generic queue moved to SlopKit (`Sources/SlopKit/FileQueue/`, public,
documented, with a gallery demo). SlopKit's `DropZone` chooser now picks folders when its
types include `.folder`. New hooks for apps: `onFiles`, `menuExtras`, `FileQueue.setOutcome`.

### Round 2 (2026-11-03)

Three majors, one of them a data-loss risk. Fixed in Squish only (SlopKit was off limits
this round). Gates re-run green: `scripts/test.sh Squish SlopKit` (47 + 63), `scripts/check.sh
Squish --perf`, a walkthrough of each fix on the release build, and no `[unlabeled]` controls.

| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
| F1 With Replace Originals, Compress Again re-encoded the compressed file and trashed it as "Aerial photo 2.jpg"; Put Back then restored that copy and the real original was lost with the Trash | major (data loss) | accept | The original is now the only source for its row. A `ReplacementRegistry` (shared with the compressor) records each trashed original with the SHA-256 taken before it was trashed. Compressing a stand-in again re-encodes from the original in the Trash: the stand-in is overwritten in place, or replaced (and its old copy deleted) when the format changes. Only originals are ever trashed. If a new setting can't beat the original, the original is put back. Put Back checks the hash, refuses with an explanation if the file in the Trash isn't byte-identical, and sends the compressed copy to the Trash as "<name> (compressed copy)". Test: replace → compress again ×2 (Smallest, High) → HEIC → put back gives an md5-identical original, and only the original was ever in the Trash. Same check done by hand in the app (md5 before = after). |
| F2 Redo All redid only the selected row, then vanished | major | accept | Each row now remembers the settings it ran with. Redo All (toolbar, and File ▸ Redo All with New Settings ⌥⌘R) redoes every row whose settings are out of date, and stays until none are. ⌘R stays "selection, or all". Verified: redo one selected row, the button stays; Redo All, then it goes away; no duplicate outputs. |
| F3 ⌘W / the close button during a batch closed the window, then the quit alert looped and the list was lost | major | accept | The close button and ⌘W now ask first (as a sheet) while busy: Keep Compressing keeps the window and batch, Stop and Quit cancels and quits. The app also never starts quitting by itself after the last window closes while busy. A first try that put a proxy in front of SwiftUI's window delegate made the app quit when files arrived, so it was replaced by taking over the close button. Verified both buttons mid-batch. Suite note: the clean fix is a "busy" hook on SlopKit's `SlopAppDelegate` (the app's `applicationShouldTerminateAfterLastWindowClosed`/close confirmation), so every drop-in app gets it. |
| F4 Adding a folder again compressed Squish's own "-small" outputs | minor | accept | Outputs get an extended attribute (`app.slopapp.squish.output`). Squish expands folders itself and skips tagged files, plus "<name>-small.*" files that sit next to a "<name>.*", with a HUD such as "5 already compressed files skipped". A tagged earlier output with the target name is overwritten instead of numbered, so there's no "-small 2" across sessions either; a user's own file with that name is still never touched (tested). |
| F5 Bar icons disappeared when Redo All appeared | minor | accept | Redo All moved to the toolbar, and the bar uses short preset names (High / Balanced / Smallest), so all four icons fit at the default 560 px. |
| F6 Pop-up names switched to the value once the list had files | minor | accept | The visible label text now carries the name too. Verified with files in the list: Quality = Balanced, Size = Full Size, Format = Same as Original, Save To = Next to Originals. |
| F7 Custom Size Apply was disabled with no explanation | nit | accept | The caption turns orange and says "Enter a whole number from 16 to 20000." while the value is invalid. |
| F8 Converted rows still showed the original name | nit | defer | The row view is SlopKit's `FileQueueRow`, which was off limits this round. Proposed SlopKit change: when `output.lastPathComponent != name`, show "Photo.webp → Photo-small.jpg" in the title and the VoiceOver label. |
| Undo for Clear List | — | defer | SlopKit's queue can't put rows back with their results (`items` is read-only), and re-adding would re-run everything. Needs a SlopKit `restore(_:)` API. Clear List never touches files. |

Also: `SystemFileStore.size(of:)` no longer reads cached `URL.resourceValues` (stale after a
file is rewritten in place).

### Round 3 (2026-11-03)

Originals were never lost (the tester verified md5s). One major and several minors.
Gates re-run green: `scripts/test.sh SlopKit Squish Convert` (65 + 51 + 47), `scripts/check.sh
Squish --perf` (launch 146 ms, first window 279 ms, idle CPU 0.015%, 34 MB), a walkthrough
of each fix on the release build (AX actions and pid-posted keys only; no real mouse,
global keys or full-screen shots), and no `[unlabeled]` controls.

| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
| F1 After ⌘W the main window couldn't come back (no Dock reopen, no Window ▸ Squish) | major | accept | New SlopKit helper `MainWindow` / `MainWindowCommands` (additive). Window ▸ Squish (⌘0); the Dock icon / `open -a` reopen, opening files and the Services entry all recreate the window, and the list and its results are still there. Verified with Settings left open (the case where closing the main window doesn't quit). With nothing else open, closing it still quits, as the design system says. |
| F2 Opening a .txt said "Already in the list" | minor | accept | Unsupported files get "Squish can't compress text files. It takes images and PDFs." (the type's own name, e.g. ZIP archive, MP3 audio), or a count for a mix. "Already in the list" only when that's true. |
| F3 Rows never showed the real output name | minor | accept | SlopKit's row shows "Photo.webp → Photo.jpg" / "Screenshot.png → Screenshot-small 2.png" when the names differ, and VoiceOver adds "written as …". Apps can turn it off with `.fileQueueShowsOutputName(false)`. |
| F4 Replace Originals persisted silently; Put Back didn't survive a relaunch | minor | accept | The replace log is saved in Application Support (`replaced-originals.json`), dropping originals no longer in the Trash. File ▸ Put Back Originals… with no matching rows offers to put back every remembered original. Launching in Replace mode shows a quiet window subtitle: "Replace Originals is on · 1 original can be put back". Verified: replace, quit, relaunch, put back gives an md5-identical original. Test added. |
| F5 Put Back trashed a compressed file the user had edited | minor | accept | Squish records the hash of what it wrote. If the file changed since, Put Back asks first: "Keep My Changes" (the default) or "Put Back Original". Test added. |
| F6 User files ending in "-small" were always skipped | minor | accept | Only files carrying Squish's tag are skipped now; names alone never count. |
| F7 Custom quality opened at 100% | nit | accept | Custom… starts from the current preset's quality and PDF dpi (Balanced shows 70% and 144 dpi). |
| F8 Undo for Remove from List | nit | accept | Remove from List and Clear List go through Undo (⌘Z), via new SlopKit `FileQueue.restore(_:at:)` and `.fileQueueOnRemove`. |
| F8 Esc on About | nit | accept | Esc closes the About window. Done in Squish with a key monitor; suite note: SlopKit's `AboutWindow` could do it itself. |
| F8 Missing thumbnail after a WebP was replaced | nit | accept | Rows whose input is gone show the output's thumbnail. |
| F8 Redo All left orphaned outputs after switching formats and back | nit | accept | When a row's output changes name, its previous output is removed, but only if Squish tagged it. Test: JPEG → HEIC → JPEG leaves just the original and one output. |
| ⌘Q alert answered by stray keystrokes | observation | accept | "Keep Compressing" is the default button (Return) in both the quit alert and the close sheet; "Stop and Quit" is marked destructive. If the batch finishes while the quit alert is open, Squish quits as asked. |

Also: if macOS won't let Squish read an original in the real Trash (TCC can protect
~/.Trash), Put Back and Compress Again now say so and point to Finder's Put Back. They no
longer misreport it as "not the original anymore", and they never fall back to the
compressed copy. Not testable here without putting a file in the owner's Trash.

## Parity pass (2026-11-03)

Per `docs/parity-pass.md`: look and work much more like the originals, and don't miss
features. Studied again read-only: **Squash 3.3** (installed: launched with three test images
from `/tmp/squish-parity/`, main window, presets sidebar, Resize mode list; sidebar toggled
back, nothing exported, quit), **PDF Squeezer 4.9** (installed: two test PDFs, profile popup,
Info and profile inspectors, Compare mode; all toggled back, Open Recent cleared, quit), and
the official **Squash 4** docs and main-window screenshot (Main Window, Presets pages).

### What the originals look like now

Both converge on one shape: **file list on the left · the selected file in the middle ·
settings on the right, with the preset/profile picker on top.**

- *Squash 4*: list rows (thumbnail, output name, "2 MB → 61 KB"); a before/after **split
  slider** over the selected image with "Before · 2.1 MB" / "After · 57 KB" badges and a
  floating zoom/compare bar; a settings sidebar of collapsible sections (Format, Location,
  Rename, Resize, Crop, Rotate…) with the **preset popup at its top** and **Export Images
  pinned at its bottom**.
- *Squash 3.3* (installed): grid of large cards (format + size badge) and a stack of on/off
  nodes (Resize, Adjustments, Effects, Borders, Watermark, Format + quality + Progressive,
  Metadata, Rename, Retain Dates, Export) above a full-width Export button; presets sidebar
  on the left ("Add Preset").
- *PDF Squeezer 4.9*: sidebar list ("56.4 MB → 151 KB, 99%"); a big page thumbnail with
  "14 KB → 13 KB" / "Size reduced by 7.55%" and a share button; toolbar **profile popup**
  whose items cache each profile's result ("Medium Compression (13 KB, 7.55%)"); right
  inspector: profile settings (Images tab: optimize, quality, max dpi, Color Profile, four
  image toggles; Fonts/Annotations; Metadata; Advanced) or file info (name, size, page /
  image / annotation counts, title, producer, dates; Extract Images / Text, Convert to
  Bitmap); **Compare**: side-by-side split with a source picker on each half, zoom ±.

### Gap table

| Item (original) | Status | Notes |
|---|---|---|
| **Design** | | |
| Three columns: list · preview · settings (both) | done | `NavigationSplitView` sidebar (SlopKit `FileQueueView`) + detail preview + `.inspector` options. Sidebar appears with the first file, hides when the list is cleared (PDF Squeezer "Show Sidebar: Automatically"). |
| Preset/profile picker on top of the settings (Squash 4) / in the toolbar (PDF Squeezer) | done | Sits in the toolbar above the options column; when the options are hidden SwiftUI moves it into the main toolbar, so it's always one click away. |
| Export button pinned under the settings (Squash) | done (adapted) | "Apply to N Files" + batch total. Squish writes on drop, so this button re-applies changed settings instead of exporting. |
| Before/after split compare with size badges (Squash 4) / Compare mode (PDF Squeezer) | done | AppKit scroll view with two image layers and a mask; drag the handle (or VoiceOver adjust); the split stays put while zooming/scrolling. ⌘K toggles; off shows the result alone. Badges "Before · 3.3 MB" / "After · 1.9 MB" / "Original · 14 KB". |
| Zoom in/out/fit/actual, pinch, double-tap (both) | done | ⌘+ / ⌘− / ⌘9 / ⌥⌘0, floating capsule bar like Squash 4's. Previews are capped at 4096 px (memory), so "actual size" of bigger photos is slightly scaled. |
| PDF page navigation in compare (PDF Squeezer) | done | Page stepper in the floating bar, ⌥⌘↑/↓. Pages rendered at 2400 px. |
| Big "X → Y" + "Size reduced by N%" readout (PDF Squeezer) | done | Footer under the preview, plus "Saved as …", pixel size / format change ("JPEG · 3840 × 2160 → JPEG · 1280 × 720") or "PDF · 6 pages · 6 images". |
| File info inspector (PDF Squeezer: pages, images, annotations, title, producer, dates) | partial | Pages, images, size, dimensions shown. Title/producer/dates: deferred (S, 1 h), low everyday value. |
| Share button (PDF Squeezer) | done | Toolbar + footer `ShareLink`. |
| Drag the result out (both) | done | Drag the file icon in the footer. Dragging a *row* needs SlopKit's `FileQueueRow` to be a drag source: deferred (S, SlopKit). |
| Sort the list by name/size/ratio/date/status (PDF Squeezer) | deferred | SlopKit's `FileQueue.items` order is read-only; needs a `sort(by:)` API (S, SlopKit). |
| Squash 3 large-card grid | not adopted | Squash 4 itself replaced it with a list; a list scales to 500-file batches and keeps the preview big. |
| Sounds, Zen music, confetti, themes, alternate Dock icons (Squash) | skip | Design system: quiet and native. |
| **Presets / profiles** | | |
| Named presets: save, apply, update, revert, rename, delete (Squash 4 presets, PDF Squeezer profiles) | done | `PresetLibrary` in SquishCore (tested). Built-ins (High Quality / Balanced / Smallest File) can't change, like Squash's Default. "(Edited)" when options differ. ⌘1–⌘9 in the Compression menu. Presets hold quality, PNG colors, progressive, resize, format, metadata and PDF options, **not** the destination (so a preset can never switch on Replace Originals). |
| Reorder / import / export presets (PDF Squeezer) | deferred | Reorder is in the library (tested) but has no UI yet: needs a Presets settings pane (S, 2 h). Import/export files (S). |
| Per-profile result cached in the picker (PDF Squeezer) | deferred | Means compressing each file once per preset in the background (M, half a day; memory budget). |
| "Try up to N stronger profiles if it doesn't shrink" (PDF Squeezer) | deferred | (S, 2 h). Never-bigger already keeps the original and says so. |
| **Images** | | |
| Resize modes: Max Size, Width, Height, Max Width/Height, Percent (Squash) | done | Longest Edge, Width, Height, Fit Within, Percentage, each with a common-sizes menu. All keep the aspect ratio and never enlarge (Squash's Width/Height can; for a compressor that only makes files bigger). Width/height mean the displayed (rotated) size. |
| Free size / stretch (Squash) | skip | Distorts images; not a compression job. |
| Format per preset, quality slider (Squash) | done | One quality for JPEG/HEIC/AVIF, PNG: Lossless / 256 / 128 / 64 colors. |
| Progressive JPEG (Squash) | done | Toggle; tested via the JFIF flag. |
| Metadata: Squash 4's five Remove checkboxes | partial | Remove All / Remove Location Only (GPS and IPTC place names) / Keep All. Five separate switches: deferred (S, 2 h). |
| Retain Dates (Squash) | done | "Keep file dates" (options column + Settings). |
| Watermark (Squash) | deferred | Text/image watermark with position and opacity (M, 1 day). Editing, not compressing; low everyday value for this job. |
| Adjustments, effects, borders, crop, rotate, highlighter (Squash) | skip | Image-editor territory. |
| Rename templates / AI names (Squash 4) | deferred | Token template (name, number, date, size) (M, half a day). Suffix + subfolder cover the everyday case. AI naming: skip. |
| PNG optimisers oxipng/zopfli (Squash) | deferred | Needs a vetted MIT/BSD library (M). Palette quantizer already gives −70% on screenshots. |
| WebP / JPEG XL output (Squash) | blocked / deferred | ImageIO can't write WebP on macOS 27. JPEG XL: add when `CGImageDestinationCopyTypeIdentifiers` lists it (S). |
| Watched folders (Squash 4) | deferred | Needs a background agent / login item (L). |
| Copy Squashed ⌥⌘C (Squash) | done | "Copy Compressed File" ⌥⌘C and in the row menu. Copy Original: skip. |
| **Output** | | |
| Same folder / subfolder of original / chosen folder + recents / replace (Squash 4 Location) | done | Added "Subfolder of Originals" (default name "Compressed", editable, cleaned of `/`, `:` and leading dots, created on demand). |
| Overwrite warnings / never overwrite (Squash) | kept | Unchanged: numbered names, tagged own outputs replaced. |
| **PDFs** | | |
| Image quality + maximum resolution per profile (PDF Squeezer) | done | Separate from the image quality now (was one shared value). dpi stops 72–600. |
| Color Profile: Grayscale (PDF Squeezer) | done | Uses macOS's own Gray Tone profile, read from `/System/Library/Filters/Gray Tone.qfilter` at run time, merged into our filter. Pages turn gray (tested by rendering); the file stays RGB, so it's only a little smaller. True one-channel gray: deferred (needs a PDF engine). RGB/CMYK conversion: skip. |
| Fonts subsetting/merging, flatten annotations/forms, remove alternates/thumbnails, clip invisible image parts, monochrome scans, metadata editing (PDF Squeezer) | skip | Quartz filters can't; needs a full PDF engine (L). |
| Password-protected PDFs: ask and re-apply (PDF Squeezer) | deferred | (M, half a day). Still skipped with a clear message, so protection is never silently dropped. |
| Extract images/text, convert to bitmap, PDF/A (PDF Squeezer) | skip | Not "make it smaller". |
| **System** | | |
| Shortcuts actions (both) | deferred | App Intents need the `appintentsmetadataprocessor` step that `scripts/bundle.sh` (off limits) doesn't run; a SwiftPM-only build gives Shortcuts nothing to show (M, pipeline change). |
| Notifications when done (PDF Squeezer, off by default) | deferred | Needs notification permission; the Dock bounce covers long batches (S). |
| Finder Quick Action, Open With, Dock drop | kept | Unchanged. |
| Write only on Export/Save (both) | deviation kept | Squish still writes safe copies on drop (the job's one interaction); Apply to All replaces them when settings change. |

### Deviations from the design system (and why)

- **Window**: default 1080×660, minimum 760×480 instead of the drop-in archetype's ~520×420,
  to fit the originals' three columns. A remembered 0.1 window (560 pt) is widened once on
  the first launch (`WindowLayout.upgradeIfNeeded`).
- **Options in an inspector column**, not a bottom bar.
- **Split handle colours**: white line and knob with a dark shadow (`.white`, `.black`
  opacity), so the divider is visible on any image in light and dark mode. Everything else
  uses system colours (`underPageBackgroundColor`, materials, accent).

### Build and gates

- New core: `CompressionOptions` / `CompressionPreset` / `PresetLibrary`, `ResizeMode`,
  `MetadataPolicy`, `Destination.subfolder`, `keepFileDates`, `progressiveJPEG`,
  `pdfGrayscale`, separate PDF quality, `FileFacts`. Settings from 0.1 migrate (tested).
- New UI: `MainView` (three columns), `PreviewPane` + `CompareView` (AppKit compare),
  `OptionsInspector` (sections, preset menu, naming sheet, Apply footer).
- SlopKit untouched; used its existing `fileQueueShowsOutputName(false)` (the narrow list
  showed truncated "→ name"; the footer now says "Saved as …") and
  `fileQueueFollowsNewFiles()` (fixes a bug found here: the Quality field took focus at
  launch, so arrow keys and typing changed settings; text fields no longer get initial
  focus).
- In-app components worth moving to SlopKit later: `CompareImageView` + `PreviewController`
  (before/after compare for any converter), `PresetLibrary` (named presets for any app),
  `WindowLayout` (one-time window resize after a layout change).
- Tests: 71 Squish tests in 15 suites (was 47), all green; never-bigger, never-overwrite and
  byte-identical Put Back tests unchanged and passing. New: resize modes, presets library,
  migration, width-of-rotated-photos, remove-location-only, progressive JPEG, subfolder,
  kept dates, grayscale PDF (rendered pixels), PDF/image facts.
- `scripts/check.sh Squish --perf`: green. Final run: launch 174 ms, first window 505 ms
  (load 3.3; budget 600, was ~300 ms with the one-column window: the inspector form costs
  ~200 ms on first layout), idle CPU 0.04%, footprint 62 MB (budget 120).
- Walkthrough on the release build (AX actions and pid-posted keys only; light and dark):
  empty state; `open -a` with 7 fixtures; arrow keys move through the list and the preview
  follows; image and PDF split compare; zoom in ×3 with the split fixed in the viewport;
  page 2 of 6; compare off; kept-original and skipped rows; Save as New Preset sheet →
  "Web Photos"; editing options shows "(Edited)" and "Apply to 7 Files"; Width 1280 from
  the common-sizes menu + JPEG + Grayscale → Apply (outputs 1280 px wide, earlier
  `-small.png/.heic` copies removed, PDF gray); Update, ⌘2/⌘4 switching, Rename → "Blog",
  Delete (alert); Save To ▸ Subfolder (`Compressed/…`, tagged); Replace Originals → Edit ▸
  Undo: all four originals **md5-identical**, compressed copies in the test trash as
  "(compressed copy)"; Copy Compressed File into a private pasteboard (`SQUISH_PASTEBOARD`);
  options hidden (preset moves to the toolbar); Settings; View ▸ Show Sidebar (⌃⌘S, via
  `SidebarCommands`). Real-mouse drag of the split handle (owner idle ≥ 60 s, Squish in
  front): the divider follows the pointer. During the first try an Open panel also
  appeared in Squish; another agent was driving Snapper at that moment, and the panel never
  came back in a repeat drag or a mouse-free replay, so it was most likely their global
  ⌘O landing in the frontmost app. `scripts/drive tree`: no `[unlabeled]` controls.

### Screenshots (not committed)

- Originals: `/tmp/squish-parity/squash-main.png`, `squash-presets.png`, `pdfs-main.png`,
  `pdfs-info.png`, `pdfs-profile.png`, `pdfs-compare.png`, `web/squash4-main-small.png`.
- Squish: `/tmp/squish-parity/s2-batch-light.png` (first build), `s4-pdf-dark.png`,
  `s5-zoom-page2.png`, `s6-nocompare.png`, `s7-zoomed.png`, `s8-save-preset-1.png`,
  `s9-applied-dark.png` (grayscale PDF compare), `s10-pdf-light.png`, `s11-kept-light.png`,
  `s12-no-options-dark.png`, `s13-settings-dark.png`, `s14-empty-light.png`,
  `s15-dragged-light-1.png` (split handle dragged with the mouse).

## Polish pass (2026-11-05)

Per `docs/polish-pass.md`. Release build stamped with SDK 27.0 (full-size 16×16 window
buttons). Every surface shot in light and dark with `SLOP_APPEARANCE`, test data only from
`/tmp/squish-test/` (`SQUISH_TRASH_DIR=/tmp/squish-test/trash`, so nothing reached the
owner's Trash; `SQUISH_PASTEBOARD` for copies). The owner's Squish defaults were exported
before and imported back after; the Put Back registry was left empty (`[]`).

### Defects found and fixed (before → after)

| # | Surface | Defect (measured) | Fix |
|---|---|---|---|
| 1 | Lint | 2 corner literals (spinner backdrop `12`, badge `6`) | `Radius.l`, `Radius.s`; lint clean |
| 2 | Preview footer | Height changed with the row's state: divider at y 1045 px (kept original) vs 1018 (compressed) vs 1016 (failed), so the image and zoom bar jumped up to 14 pt when the selection changed | Fixed-height footer (hidden tallest layout holds it); divider at 1018 px for every state |
| 3 | Preview footer | Text's leading edge moved 16 pt → 61 pt when the file icon appeared (only rows with a result had one) | Icon slot always present: draggable for a result (compressed copy or the kept original), dimmed otherwise |
| 4 | Preview footer | Failed message in plain `.orange`: 2.2:1 on white (stroke-core sample #EE9A48) | `.textOrange`: 4.5:1 (#A4682D) light; dark unchanged |
| 5 | Preview footer | "Saved as …" was its own line (5 lines for compressed files) | Joined to the facts line: "JPEG · 3840 × 2160 · Saved as photo-small.jpg"; facts never truncate, the name gives way in the middle |
| 6 | Preview footer | Canceled files had no Try Again (rows did) | Try Again for failed and canceled |
| 7 | Compare | Split line and knob ran the full pane height (off the picture, through the badges and zoom bar); split measured across the pane, so on a portrait page a split near an edge could miss the image | Line spans the visible image only; split measured across the visible image, mask and handle from the same rect (`PreviewController.imageRect`) |
| 8 | Compare | Fitted PDF page overlapped the Before badge (page top 145 px vs badge bottom 160 px) and touched the zoom bar (≈1 pt) | Badge band (12 + 24 + 8 pt) and zoom-bar band (12 + 32 + 8 pt) as scroll insets: page now exactly 8.0 pt below the badges and 8.0 pt above the bar |
| 9 | Compare | Fitted image 2.5–2.7 pt low (clip view mixed point insets with document units) | Insets scaled by zoom: photo centre 296.25 pt vs expected 296.5 |
| 10 | Compare | Wide image 15 pt from the pane edge vs badges 12.5 pt | Fit side margin = badge inset: image and badges share both edges (12.5 pt) |
| 11 | Compare | Zoom bar shown (and enabled) over "No preview" | Hidden without a picture |
| 12 | Badges / zoom bar | Heights from padding (badge 10/4 pt padding; bar 6 pt + content) | Fixed 24 pt badge, 32 pt bar (`PreviewMetrics`) |
| 13 | Hairlines | SwiftUI `Divider` 2 px (1 pt) under the preview and above Apply; 1 pt vertical rules in the zoom bar | In-app `Hairline` (1 device px, `separatorColor`): 1 px measured |
| 14 | Options footer | Apply button 12 pt from the column edge vs section cards 10 pt (edges 2 pt off); total 13 pt vs row labels 20 pt | Button edges = card edges (10 pt), total = label edge (20 pt) |
| 15 | Options footer | Disabled "Apply to All" drawn `.borderedProminent`: in dark mode it read as an enabled accent button | Prominent only when there's something to apply; otherwise plain bordered |
| 16 | Options | Notes under Size, Metadata and Save To were extra form rows with separators | Native section footers (`FormNote`) |
| 17 | Options ▸ Size | Scale field 56 pt with no menu, pixel fields 64 pt + menu: columns didn't line up; common-sizes chevron centre 4 pt right of the pop-up indicators (1050.5 vs 1046.5 pt) | One field component for every resize row (64 pt field, fixed unit slot, menu incl. 75/50/33/25 %); chevron centred at 1046.5 pt |
| 18 | Options ▸ Size | VoiceOver "Common scale scales" | "Common scales" |
| 19 | Sidebar (empty) | Show Sidebar with no files drew a second drop zone next to the first | `ContentUnavailableView` "No Files / Files you add appear here." (still a drop target) |
| 20 | Title bar | Subtitle truncated at 1080 pt: "Saved 169.1 MB (−96%) · 13 files · 3 fai…" | "Saved 169.1 MB · 3 failed" (count and % live in the options footer) |
| 21 | Toolbar / View menu | Compare toggle enabled with an empty list | Disabled until there are files |
| 22 | Rows (errors) | Messages repeated the file name and truncated at 3 lines ("…Try openin…", "…and expo…") | Nameless, ≤ 80 characters (tested): "Couldn't read this file. It may be damaged. Try opening it in Preview." etc.; all fit |
| 23 | Rows (errors) | Try Again on files that fail the same way every time (empty, unreadable, locked PDF) | `SquishError.isWorthRetrying` → SlopKit's `FileQueueRetryHint`: no Try Again, left out of ⌘R |
| 24 | Preset sheet | Content inset 16 pt | 20 pt (`Spacing.windowMargin`), measured |
| 25 | Settings | Explanations were separate rows with separators | Subtitles under their own labels (Toggle/LabeledContent two-text labels) |
| 26 | Replace Originals alert | Destructive choice not marked | `role: .destructive` |
| 27 | Put Back all / Delete preset | App-modal floating alerts (they also brought Squish to the front) | Sheets on the main window (`AppModel.ask`), modal fallback without one |

Checked and fine as is: drop zone 20.0 pt from the toolbar, sides and bottom; window
buttons 16×16; list strip and selection insets (SlopKit); preset menu; Location menu;
Save To subfolder/replace states; zoomed view (content scrolls under badges and bar);
compare off (After badge only); multi-selection summary; canceled rows; selected rows'
text on the accent fill; dark mode throughout.

### Gates

- `scripts/check.sh Squish --perf`: all pass. Launch 128–170 ms, first window 541 ms (load
  4.0) / 580 ms (load 4.8, busy machine; budget 600), idle CPU 0.03–0.06 %, footprint
  67.8–70.1 MB.
- Tests: 73 in 16 suites (new `ErrorWordingTests`: no names, says what to do, ≤ 80 chars;
  only encode failures are worth retrying).
- `scripts/drive tree`: 0 `[unlabeled]`; close button 16×16.
- Replace Originals → File ▸ Put Back Originals… on `/tmp/squish-test/replace`: all three
  originals md5-identical afterwards; compressed copies in the test trash.

### Not done, and why

- Hover states (row buttons, drop strip, zoom bar): needs the real mouse; the owner was
  active part of the time and the screen was locked for ~20 minutes, so not exercised.
  They're SlopKit's/AppKit's own styles.
- Edit ▸ Undo after Replace Originals wasn't re-run (the window wasn't key while driving, so
  Undo was disabled); Put Back from the File menu covers the same code path and passed.
- The footer centres its content in the fixed height, so the name sits about 8 pt higher
  for a two-line message than a one-line one. Kept: top-aligning would leave a lopsided
  empty band under the common one-line case.
- `InspectorMetrics.formInset` (10 pt) is measured on macOS 26's grouped `Form`; older
  systems use their own inset, so the Apply footer may be a few points off there.

### Golden Gate + light/dark (2026-11-06)

Follow-up for the owner's "optimized for dark/light mode AND fit in with macOS Golden Gate"
(`docs/design-system.md` §4 "Fitting in on macOS 27 Golden Gate", §10 items 25–26). Shot in
both appearances, active and inactive: `/tmp/slopapp-polish/squish/gg/`
(`empty-`, `compare-inactive-`, `failed-`, `pdf-`, `settings-` × `light`/`dark`; `pdf-light` is
the active-window sample). Defaults backed up and restored; test files only in `/tmp`.

| Check | Before → after |
|---|---|
| Menus (menu bar, row context menu, preset pull-down, Resize/Format/PNG/dpi/Location pickers, common-sizes menus) | Already text only (state checkmarks and preset details are information). No change. Toolbar items keep their symbols, as standard toolbars do. |
| Toolbar | Standard `.toolbar`; nothing drawn behind items; preset picker legible over the scrolled options (system scroll-edge effect). No change. |
| Sidebar | System `NavigationSplitView` sidebar, edge to edge; rows are thumbnails (no symbols to tint). No change. |
| Inactive windows | The zoom bar's Compare toggle stayed accent blue in a background window → `Color.windowAccent(controlActiveState)`: blue active, grey inactive (both shot). Queue selection, sliders, toolbar toggles and the prominent Apply button already go grey (SlopKit / system). |
| Glass | Badges, zoom bar and the working spinner use `.regularMaterial` (system); no hand-made translucency. No change. |
| Drawn pure white/black | The before/after divider and knob were `.white` with `.black` shadows and edge → SlopKit's `OverlayPalette` (`ring` ≈ 85 % white, `ringShadow` from the dark window colour, knob edge via `hairlineBorder`): chrome over arbitrary pictures, the same in both modes. The compare mask's black is a mask (never drawn). PDF pages render on white paper (content). |
| Status colours | Savings `−N%` (`.textGreen`) and failure text (`.textOrange`) read in both modes; footer text secondary. No change. |
| Live appearance change | Can't flip the owner's system appearance, so checked by code: no stored CGColors depend on the appearance (the document layer's shadow is black in both modes by design, the mask is alpha only); everything else is SwiftUI semantic colours that re-resolve. |
| Hairlines (SlopKit now lays out 1 pt) | My in-app `Hairline` is gone; SlopKit's is used. Re-measured: preview divider 1 px at y 1098 px (was 1099), zoom bar still exactly 24 px (12 pt) above it, options divider 1 px; zoom-bar rules crisp. |
| FileQueue (SlopKit changes) | Rows, selection and drop strip checked light/dark, active/inactive: no regressions. |

Gates: `scripts/check.sh Squish --perf` all pass (launch 131 ms, first window 569 ms at load
7.5, idle CPU 0.03 %, 67.3 MB); one earlier run missed first window at load 9.8 while other
builders were busy and passed on re-run. 73 tests; `drive tree`: 0 `[unlabeled]`, close
button 16×16.

Not done: a live light↔dark switch while running (would need changing the owner's system
appearance); hover states (real pointer, owner active). Note: opening Settings with ⌘, brings
Squish forward, and one shot did that while the owner was active; I stopped using it after.

### SlopKit notes (not edited)

- `FileQueueView` multi-selection: separators still draw inside a block of selected rows.
- `AboutView`: the tagline wraps with a two-word last line ("files out.") at the Settings
  width.
- `Hairline` exists in three apps now (Switchboard, Snapper, Squish): worth moving to SlopKit.
- `FileQueueItem.State.isFailedOrCancelled` is internal; apps re-implement it.

### Screenshots (`/tmp/slopapp-polish/squish/`)

Before: `b01-empty-light`, `b02-empty-sidebar-light` (two drop zones), `b03-working-light`,
`b04-done-light`, `b05-compare-light`, `b06-failed-light`, `b07-pdf-light`,
`b08-settings-light`, `b09-about-light`, `b10-inspector-bottom-light`,
`b11-preset-menu-light-1`, `b12-sheet-light-1`, `b13-failed-dark`.
After: `a01-empty-{light,dark}`, `a02-empty-sidebar-{light,dark}`, `a04-done-{light,dark}`,
`a05-compare-{light,dark}`, `a06-failed-{light,dark}`, `a07-pdf-{light,dark}`,
`a08-stopped-dark-2`, `a11-settings-{light,dark}-1`, `a12-resize-percent-light`,
`a13-resize-fit-light`, `a14-location-menu-light-1`, `a15-subfolder-light`,
`a16-replace-alert-light-1`, `a17-replaced-light`, `a19-putback-alert-light-1`,
`a20-putback-done-light`, `a21-sheet-light-1`, `a22-multi-light`, `a23-zoomed-light`,
`a24-compare-off-light`, `a25-putback-sheet-light-1`.
