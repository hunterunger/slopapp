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
