# Squish

Drop in images and PDFs, get smaller files out.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to Squash and PDF Squeezer.

**Status:** alpha

## What it does

Drop images, PDFs or whole folders on the window (or the Dock icon, or use **Choose Files…**
⌘O, or Finder → right-click → Quick Actions / Services → **Compress with Squish**). They are
compressed straight away, several at once.

The window has three columns: the **file list** (each row: before → after and how much was
saved), a **preview** of the selected file with a **before/after split** you drag sideways
(zoom with ⌘+ / ⌘− / pinch, ⌘9 to fit, page through PDFs), and the **options**, with the
**preset** on top and **Apply to All** at the bottom. Under the preview: the sizes, "Size
reduced by N%", the saved file's name, pixel size or page/image counts, Share, Show in
Finder, and the file's icon to drag the result into Mail, a browser or Finder.

- **Presets.** High Quality, Balanced (default) and Smallest File are built in. **Save as
  New Preset…** keeps your own (quality, size, format, PDF and metadata options; where files
  go isn't part of a preset). Edit a preset's options and it shows "(Edited)": **Update**,
  **Revert**, **Rename** or **Delete** it from the preset menu or the Compression menu
  (⌘1–⌘9 pick presets).
- **Safe by default.** Smaller copies are saved next to the originals as `name-small.ext`
  (the suffix is editable), into a **subfolder** of each original's folder (`Compressed/`),
  or into a folder you pick. Existing files are never overwritten: names get " 2", " 3".
  **Replace Originals** is opt-in and moves each original to the Trash; **Edit ▸ Undo** or
  **Put Back Original** returns it. Put Back checks a fingerprint, so it only ever restores
  the exact original. Compressing a replaced file again always starts from the original,
  never from the copy. **Keep file dates** gives copies the original's dates.
- **No double squishing.** Dropping a file that's already in the list runs it again in
  place; Squish's own outputs (tagged with an extended attribute) are skipped when a folder
  is added again. When you change settings, **Apply to All** redoes every file made with
  the old ones.
- **Never bigger.** If a result wouldn't be at least 2% smaller, nothing is written and the
  row says the original was kept.
- **Images:** JPEG, HEIC, PNG, AVIF and TIFF are re-encoded with ImageIO at your quality
  (and progressive JPEG if you like). PNGs are reduced to a palette (256, 128 or 64 colors,
  dithered; flat colors stay exact) or kept lossless. **Resize**: longest edge, width,
  height, fit within a box, or a percentage; never enlarges. **Metadata**: remove all
  (default; keeps orientation and the color profile), remove location only, or keep all.
  iPhone HDR gain maps are kept when the size doesn't change. GIFs and animated images are
  left alone. WebP files can be read and converted, but this Mac's ImageIO can't write
  WebP, so "Same as Original" skips them.
- **PDFs:** images inside are downsampled to your dpi and re-compressed at your quality with
  a Quartz filter; text, vectors, links and annotations stay. **Grayscale** turns pages
  gray. Locked or password-protected PDFs are left alone.

| Preset | Images (JPEG/HEIC quality) | PNG | Images in PDFs |
|---|---|---|---|
| High Quality | 80% | lossless | 220 dpi, 80% |
| **Balanced** (default) | 70% | 256 colors | 144 dpi, 70% |
| Smallest File | 55% | 128 colors | 96 dpi, 50% |

No network access, no accounts, no tracking. No permissions needed.

## Keyboard

| Action | Shortcut |
|---|---|
| Choose Files… | ⌘O |
| Show in Finder (selection, or all results) | ⇧⌘R |
| Quick Look | Space or ⌘Y |
| Copy Compressed File | ⌥⌘C |
| Compress Again (selection, or all) | ⌘R |
| Apply Settings to All | ⌥⌘R |
| Stop | ⌘. |
| Remove from List | Delete |
| Put Back Originals (after Replace Originals) | ⌘Z for the last batch |
| Clear List | ⇧⌘⌫ |
| Presets | ⌘1 – ⌘9 |
| Compare Before and After | ⌘K |
| Zoom In / Out / to Fit / Actual Size | ⌘+ / ⌘− / ⌘9 / ⌥⌘0 |
| Previous / Next PDF Page | ⌥⌘↑ / ⌥⌘↓ |
| Show Sidebar / Show Options | ⌃⌘S / ⌥⌘I |
| Settings | ⌘, |

## Not there yet

Shortcuts actions (the build pipeline doesn't produce App Intents metadata yet), watched
folders, watermarks, rename templates, sorting the list, password-protected PDFs, true
one-channel gray PDFs, WebP output (needs an encoder macOS doesn't ship).

## Develop

```sh
scripts/test.sh Squish                 # unit tests (core + file queue)
scripts/run.sh Squish                  # build a debug .app and open it
scripts/check.sh Squish --perf         # the full gate
swift apps/Squish/Tools/make-fixtures.swift /tmp/squish-test   # test images and PDFs
swift run -c release --package-path apps/Squish SquishBench /tmp/squish-test/batch
```

Environment for scripted runs: `SQUISH_TRASH_DIR=/tmp/...` sends "trashed" originals there
instead of the Trash; `SQUISH_PASTEBOARD=<name>` makes Copy Compressed File use a private
pasteboard instead of the clipboard; `SQUISH_APPEARANCE=light|dark`;
`SQUISH_DIAGNOSTICS=/tmp/...log` logs main-thread lag per batch.

Code: `Sources/SquishCore` (compression, naming, settings, memory budget; tested) and
`Sources/Squish` (app wiring and views). The file queue itself is SlopKit's `FileQueue`.

Memory: files run 8 at a time within a 256 MB estimated budget. Apple's AVIF encoder needs
about 400 MB for one 8 MP photo, so AVIF conversions run one at a time.
