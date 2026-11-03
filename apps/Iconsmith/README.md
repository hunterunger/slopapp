# Iconsmith

Turn any image into app and folder icons.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to Image2icon.

**Status:** alpha

## What it does

Drop a picture on the window (or the Dock icon, **Open Image…** ⌘O, or paste one with ⌘V).
It shows up as an icon right away, large and at the 128, 32 and 16 pt sizes Finder really
uses. Then either export it or put it on files and folders.

- **Shapes:** macOS App (Apple's icon grid: a rounded tile with margins and a soft shadow,
  so it isn't shrunk into a grey box on macOS 26), Square (full bleed, for iOS and Xcode,
  where the system applies the mask), Circle, As Is (the picture itself, transparency
  kept), and Folder (the picture on the front of the folder icon your Mac draws today).
- **Placement:** Size slider, Fit or Fill for non-square pictures, drag the preview (or
  ⌥ arrow keys) to move the picture, double-click or ⌘0 to re-center. Logos with
  transparent margins are trimmed to their visible part and given breathing room;
  photos fill the shape.
- **Background:** Automatic (the color at the picture's edges, or white when they're
  transparent, so every shape shows), None (transparent; the preview outlines the shape),
  or any color.
- **Export** (⌘E, or **File ▸ Export As**): a save panel that opens in the picture's own
  folder, with the format and its options at the bottom. A one-line status shows what was
  saved, with Show in Finder and, for favicons, **Copy HTML** for the `<link>` tags.

  | Format | What you get |
  |---|---|
  | .icns File | All ten macOS sizes, each drawn at its own pixel size |
  | Iconset Folder | The ten PNGs `iconutil` expects |
  | Xcode App Icon | `AppIcon.appiconset` in the current layout: macOS 10 sizes, iOS and watchOS single 1024 px (opaque, never pre-rounded). Accepted by `actool` without warnings |
  | Favicons | `favicon.ico` (16/32/48), `icon-192.png`, `icon-512.png`, `icon-maskable-512.png`, `apple-touch-icon.png`, `manifest.webmanifest` (name, colors, icons), `head.html` |
  | PNG Image | One PNG, 256 to 2048 px |
  | Windows Icon (.ico) | 16 to 256 px |

  Nothing is overwritten without the save panel asking; a replaced export goes to the Trash.
- **Custom Finder icons:** drop files, folders or disks on **Apply to Files & Folders**
  (or ⌘J to choose them) and they get the icon at once. **Remove Custom Icons** (⇧⌘J) gives
  items their standard icon back, with or without a picture loaded. Each item shows its
  own result, and ⌘Z puts back exactly what was there before, including an older custom
  icon.
- **Any source:** PNG, JPEG, HEIC, TIFF, WebP, PSD, GIF (first frame), SVG and PDF (drawn
  sharp at every size), .icns (largest size). Drop an app or a folder to use its icon.

No network access, no accounts, no tracking. No permissions needed: Iconsmith only
changes the items you drop or choose.

## Keyboard

| Action | Shortcut |
|---|---|
| Open Image… | ⌘O |
| Paste a picture / Copy the icon as PNG | ⌘V / ⌘C |
| Export (last format) | ⌘E |
| Export As .icns, Iconset, Xcode, Favicons, PNG, .ico | ⌥⌘1 – ⌥⌘6 |
| Apply Icon to… / Remove Custom Icons… | ⌘J / ⇧⌘J |
| Shape: macOS App, Square, Circle, As Is, Folder | ⌘1 – ⌘5 |
| Bigger / Smaller | ⌘= / ⌘- |
| Move picture | ⌥ arrow keys (or arrows when the preview is focused) |
| Re-center | ⌘0 |
| Undo / Redo (icon changes and edits) | ⌘Z / ⇧⌘Z |
| Settings | ⌘, |

## Not there yet

Custom icons on apps (needs App Management and is wiped by app updates), Icon Composer
`.icon` export, iOS dark and tinted variants, Android icons, background removal, batch
export of many pictures, dragging the result out of the window, Shortcuts actions.
Text and emoji on icons are deliberately left out: macOS 26's Finder does that itself.

## Develop

```sh
scripts/test.sh Iconsmith     # unit tests
scripts/run.sh Iconsmith      # build a debug .app and open it
scripts/check.sh Iconsmith    # the full gate: tests, release bundle, launch smoke test
swift apps/Iconsmith/Tools/make-fixtures.swift   # test pictures and folders in /tmp/iconsmith-test
```

Logic lives in `Sources/IconsmithCore` (tested). Views and wiring live in `Sources/Iconsmith`.
Scripted runs can fence icon changes to one folder with `ICONSMITH_ALLOWED_ROOT=<dir>` (the
target choosers open there), keep ⌘C/⌘V/Copy HTML off the real clipboard with
`ICONSMITH_PASTEBOARD=<name>`, send
replaced exports to `ICONSMITH_TRASH_DIR=<dir>` instead of the Trash, and force
`ICONSMITH_APPEARANCE=light|dark`.

Design follows [`docs/design-system.md`](../../docs/design-system.md). Shared pieces
(Settings form, About, DropZone, HUD) come from SlopKit.
