# Squish

Drop in images and PDFs, get smaller files out.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to Squash and PDF Squeezer.

**Status:** alpha

## What it does

Drop images, PDFs or whole folders on the window (or the Dock icon, or use **Choose Files…**
⌘O, or Finder → right-click → Quick Actions / Services → **Compress with Squish**). They are
compressed straight away, several at once, and each row shows before → after and how much
was saved.

- **Safe by default.** Smaller copies are saved next to the originals as `name-small.ext`
  (the suffix is in Settings), or into a folder you pick. Existing files are never
  overwritten: names get " 2", " 3". **Replace Originals** is opt-in and moves each
  original to the Trash; **Edit ▸ Undo** or **Put Back Original** returns it while the app
  is open. Put Back checks a fingerprint, so it only ever restores the exact original.
  Compressing a replaced file again always starts from the original, never from the copy.
- **No double squishing.** Dropping a file that's already in the list runs it again in
  place; Squish's own outputs (tagged with an extended attribute) are skipped when a folder
  is added again. When you change settings, **Redo All** redoes every file made with the old
  ones.
- **Never bigger.** If a result wouldn't be at least 2% smaller, nothing is written and the
  row says the original was kept.
- **Images:** JPEG, HEIC, PNG, AVIF and TIFF are re-encoded with ImageIO. PNGs are reduced
  to a palette (up to 256 colors, dithered; flat colors stay exact) unless you choose High
  Quality. Optional resize (longest edge, never enlarges) and format conversion. **Remove
  Metadata** (on by default) drops location, camera and editing details but keeps
  orientation and the color profile. iPhone HDR gain maps are kept when the size doesn't
  change. GIFs and animated images are left alone. WebP files can be read and converted to
  JPEG/HEIC/PNG/AVIF, but this Mac's ImageIO can't write WebP, so "Same Format" skips them.
- **PDFs:** images inside are downsampled and re-compressed with a Quartz filter; text,
  vectors, links and annotations stay. Locked or password-protected PDFs are left alone.

| Quality | Images (JPEG/HEIC quality) | PNG | Images in PDFs |
|---|---|---|---|
| High Quality | 80% | lossless | 220 dpi, 80% |
| **Balanced** (default) | 70% | 256 colors | 144 dpi, 70% |
| Smallest File | 55% | 128 colors | 96 dpi, 50% |
| Custom… | your % | lossless at 90%+ | your dpi |

No network access, no accounts, no tracking. No permissions needed.

## Keyboard

| Action | Shortcut |
|---|---|
| Choose Files… | ⌘O |
| Show in Finder (selection, or all results) | ⇧⌘R |
| Quick Look | Space or ⌘Y |
| Compress Again (selection, or all) | ⌘R |
| Redo All with New Settings | ⌥⌘R |
| Stop | ⌘. |
| Remove from List | Delete |
| Put Back Originals (after Replace Originals) | ⌘Z for the last batch |
| Clear List | ⇧⌘⌫ |
| High Quality / Balanced / Smallest File / Custom | ⌘1 – ⌘4 |
| Settings | ⌘, |

## Not there yet

Dragging a result out of a row, named presets, PDF grayscale, before/after compare view,
Shortcuts actions, WebP output (needs an encoder macOS doesn't ship).

## Develop

```sh
scripts/test.sh Squish                 # unit tests (core + file queue)
scripts/run.sh Squish                  # build a debug .app and open it
scripts/check.sh Squish --perf         # the full gate
swift apps/Squish/Tools/make-fixtures.swift /tmp/squish-test   # test images and PDFs
swift run -c release --package-path apps/Squish SquishBench /tmp/squish-test/batch
```

Environment for scripted runs: `SQUISH_TRASH_DIR=/tmp/...` sends "trashed" originals there
instead of the Trash; `SQUISH_APPEARANCE=light|dark`; `SQUISH_DIAGNOSTICS=/tmp/...log`
logs main-thread lag per batch.

Code: `Sources/SquishCore` (compression, naming, settings, memory budget; tested) and
`Sources/Squish` (app wiring and views). The file queue itself is SlopKit's `FileQueue`.

Memory: files run 8 at a time within a 256 MB estimated budget. Apple's AVIF encoder needs
about 400 MB for one 8 MP photo, so AVIF conversions run one at a time.
