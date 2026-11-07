# Iconsmith

Turn any image into app and folder icons.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to Image2icon.

**Status:** alpha

## What it does

Drop a picture on the window (or the Dock icon, **Open Image…** ⌘O, or paste one with ⌘V).
It shows up as a big icon, with the 64, 32 and 16 pt sizes Finder really uses underneath.
The templates run down the right side, each drawn with your picture. Then drop folders
and files **on the icon** to give them that icon, or press **Export**.

- **Templates:** *App icons:* macOS App (Apple's grid: a rounded tile with margins and a
  soft shadow), Rounded (a full-size rounded square, the way iOS shows it), Square (full
  bleed, for Xcode, where the system applies the mask), Circle, As Is (the picture itself).
  *Folders & files:* Folder (the picture on the front of the folder your Mac draws
  today), Folder Cover (the picture covers the front), Folder Symbol (the picture pressed
  into the folder, like the symbols macOS puts on folders), Document.
- **Colour:** a background for app icons (Automatic, None, or any colour), or a **folder
  colour** that recolours the folder and keeps its shading. Quick swatches plus the colour
  panel.
- **Adjust** (the sliders button on the icon, ⌥⌘A): Size, Horizontal, Vertical and
  Rotation sliders, each with its own reset, Fit or Fill, and Reset All. You can also drag
  the picture in the big icon, use ⌥ arrow keys, ⌘[ / ⌘] to turn it 90°, double-click or ⌘0
  to re-center.
- **Text** (⌘T): text or emoji on the icon, in the middle, at the top or bottom (the picture
  makes room), or as a corner badge. Font (System, Rounded, Serif, Monospaced), weight,
  automatic or manual size, automatic or custom colour. On folders the text is pressed in
  like a symbol. **New Blank Icon** (⌘N) starts with no picture: a coloured folder with a
  word on it, say.
- **Remove Background** (⌥⌘B): keeps only the subject of a photo (a person, pet or object),
  using macOS's own on-device subject lifting. Nothing is uploaded. ⌘Z or **Restore
  Background** puts it back.
- **Batch:** drop several pictures at once. A "1 of 4" menu in the toolbar switches
  between them; the template, colour and text apply to all. Export can save every picture
  into one folder.
- **Export** (the Export button shows every format as a tile, with that format's options;
  ⌘E exports the last format straight away; **File ▸ Export As** ⌥⌘1–9):

  | Format | What you get |
  |---|---|
  | Folder | A new folder that already has the icon |
  | ICNS | All ten macOS sizes, each drawn at its own pixel size |
  | Xcode | `AppIcon.appiconset` in the current layout: macOS 10 sizes, iOS and watchOS single 1024 px (opaque, never pre-rounded), and optionally iOS 18 **dark and tinted** variants. Accepted by `actool` without warnings |
  | Android | `res/mipmap-*` launcher icons for every density, round icons, adaptive foreground and background layers (+ monochrome for logos), and the 512 px Play Store icon |
  | Favicon | `favicon.ico` (16/32/48), `icon-192.png`, `icon-512.png`, `icon-maskable-512.png`, `apple-touch-icon.png`, `manifest.webmanifest`, `head.html` |
  | Iconset | The ten PNGs `iconutil` expects |
  | ICO | Windows icon, 16 to 256 px |
  | PNG / JPEG | One image, 256 to 2048 px (JPEG on white) |

  Nothing is overwritten without the save panel asking; a replaced export goes to the Trash.
- **Drag it out:** drag one of the small icons to Finder (or any app) to save an `.icns`;
  hold ⌥ for a PNG.
- **Custom Finder icons:** drop files, folders, disks or apps on the big icon (⌘J to choose
  them instead). Pictures dropped there replace the picture; hold ⌥ to give them the icon
  instead. **Apps** ask first: the icon is stored inside the app, an update usually puts
  the original back, Apple's own apps can't be changed, and macOS may ask you to allow
  Iconsmith under *Privacy & Security ▸ App Management* (the result row links there).
- **Restore** (the tab at the bottom, ⌃⌘2, or ⇧⌘J): drop files, folders, disks or apps
  and they get their standard icons back. Each item shows its own result, and ⌘Z puts back
  exactly what was there before.
- **Any source:** PNG, JPEG, HEIC, TIFF, WebP, PSD, GIF (first frame), SVG and PDF (drawn
  sharp at every size), .icns (largest size). Drop an app or a folder to use its icon.

No network access, no accounts, no tracking. No permissions needed, except that macOS may
ask about App Management the first time you change another app's icon.

## Keyboard

| Action | Shortcut |
|---|---|
| New Blank Icon / Open Image… | ⌘N / ⌘O |
| Paste a picture / Copy the icon as PNG | ⌘V / ⌘C |
| Export (last format) / Export all pictures of a batch | ⌘E / ⇧⌘E |
| Export As Folder, ICNS, Xcode, Android, Favicon, Iconset, ICO, PNG, JPEG | ⌥⌘1 – ⌥⌘9 |
| Apply Icon to… / Remove Custom Icons… | ⌘J / ⇧⌘J |
| Templates, top to bottom | ⌘1 – ⌘9 |
| Create / Restore tab | ⌃⌘1 / ⌃⌘2 |
| Adjust… / Text… / Remove Background | ⌥⌘A / ⌘T / ⌥⌘B |
| Bigger / Smaller | ⌘= / ⌘- |
| Rotate left / right 90° | ⌘[ / ⌘] |
| Move picture | ⌥ arrow keys (or arrows when the icon is focused) |
| Re-center | ⌘0 |
| Previous / next picture of a batch | ⌥⌘← / ⌥⌘→ |
| Undo / Redo (icon changes and edits) | ⌘Z / ⇧⌘Z |
| Settings | ⌘, |

## Not there yet

Icon Composer `.icon` export, Shortcuts actions, a Finder Quick Action, novelty templates
(discs, cartridges, photo frames), localization.

## Develop

```sh
scripts/test.sh Iconsmith     # unit tests
scripts/run.sh Iconsmith      # build a debug .app and open it
scripts/check.sh Iconsmith    # the full gate: tests, release bundle, launch smoke test
swift apps/Iconsmith/Tools/make-fixtures.swift   # test pictures, folders and a stand-in app in /tmp/iconsmith-test
```

Logic lives in `Sources/IconsmithCore` (tested). Views and wiring live in `Sources/Iconsmith`.
Scripted runs can fence icon changes to one folder with `ICONSMITH_ALLOWED_ROOT=<dir>` (the
target choosers open there), keep ⌘C/⌘V/Copy HTML off the real clipboard with
`ICONSMITH_PASTEBOARD=<name>`, send replaced exports to `ICONSMITH_TRASH_DIR=<dir>` instead
of the Trash, and force `ICONSMITH_APPEARANCE=light|dark`. `ICONSMITH_DEBUG_DIR=<dir>`
turns on a test hook that takes commands over a distributed notification and renders
Iconsmith's own windows to PNGs there (for checking the UI while the screen is locked; see
`DebugHarness.swift`).

Design follows [`docs/design-system.md`](../../docs/design-system.md). Shared pieces
(Settings form, About, DropZone, HUD) come from SlopKit.
