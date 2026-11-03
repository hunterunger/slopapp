# Snapper

Screenshots, annotated and shared in seconds.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to CleanShot X.

**Status:** beta 0.2.0 (v1 complete, two blind-test rounds)

## What it does

- **Capture an area** (⌥⇧⌘4): the screen freezes and dims, the pointer becomes a crosshair
  with a magnifier, and a readout shows the size. Drag to capture. Shift makes it square,
  Option grows it from the center, hold Space while dragging to move it, arrow keys nudge
  the pointer (Shift: 10 pt), Return takes the whole screen, Esc cancels.
- **Capture a window** (⌥⇧⌘5, or Space during an area capture): click the highlighted
  window. It's captured on its own, even if covered, with a soft shadow on transparency
  (turn the shadow off in Settings).
- **Capture the full screen** (⌥⇧⌘3) under the pointer, or **the previous area** again.
- After each capture a **thumbnail card** appears in a bottom corner: Copy, Save (always to
  the folder in Settings, and the confirmation says where; ⌥-click: Save As…), Annotate,
  Pin, Close, or drag it straight into another app. Copy and Save close the card unless you
  turn that off; cards can also close themselves after a while (Settings). Closed one too
  soon? **Reopen Last Capture**.
- **Annotate**: arrow, line, rectangle, ellipse, text, highlighter, pixelate, blur, numbered
  steps and crop, with colors, three line widths, select/move/resize/delete and undo/redo.
  Then copy, save (again updates the same file), save as PNG, JPEG or HEIC, share or pin
  the result. Closing the window keeps your edits, and reopening it from the thumbnail
  brings back your undo history. Blur and pixelate act on the capture itself, so arrows and
  text always stay visible on top of them; text is kept inside the image.
- **Pin** a capture: it floats above every window. Drag to move, drag an edge or pinch to
  resize, 1–9 and 0 set the opacity, arrow keys nudge, right-click for more, Esc closes.
- **Desktop icons** are left out of captures (on by default), without touching Finder.
- Annotate or pin an image from the clipboard or from a file, from the menu bar menu, or
  open any image with Snapper (Finder ▸ Open With, or drop it on the Dock icon while an
  editor is open).
- Every command is also in the app's own menus (File ▸ Capture Area…) whenever a Snapper
  window is open, for when the menu bar icon is hidden behind the notch.

## Keyboard

| Where | Keys |
|---|---|
| Anywhere | ⌥⇧⌘4 area, ⌥⇧⌘5 window, ⌥⇧⌘3 full screen; Capture Previous Area has no default (set one in Settings → Shortcuts) |
| Selecting | Space area/window, Shift square, Option from center, arrows nudge, Return whole screen / highlighted window, Esc cancel |
| Card (after clicking it) | ⌘C copy, ⌘S save, ⇧⌘S save as, ⌘E annotate, ⇧⌘P pin, ⌘W or ⌫ close |
| Editor | ⌘= / ⌘− zoom, ⌘0 actual size, ⌘9 zoom to fit, pinch or ⌘-scroll to zoom, scroll to pan; V select, A arrow, L line, R rectangle, O ellipse, T text, H highlighter, P pixelate, B blur, N counter, C crop; ] / [ line width (= / − work too); ⌫ delete; arrows move; ⌘Z / ⇧⌘Z; ⌘C copy image; ⌘S save; ⇧⌘S save as; ⇧⌘P pin; Return applies a crop; ⌥Return new line in text |
| Pin | Esc close, 1–9/0 opacity, arrows move, ⌘= / ⌘− zoom, ⌘0 actual size, ⌘C copy, ⌘S save, ⌘E annotate |

The defaults stay clear of macOS's own screenshot shortcuts (⇧⌘3/4/5, ⌃⇧⌘3/4) and of
other screenshot apps' ⇧⌘2–5.

## Permissions

**Screen Recording**, to take screenshots. Snapper asks the first time you capture, with
a button to the right System Settings pane; macOS applies it after Snapper restarts.

## Privacy

No network, no accounts, no history. Captures live only in memory and in a temporary
folder that's emptied when Snapper quits, until you copy, save, drag or share them.

## Not there yet

Screen recording and GIFs, scrolling capture, text recognition (OCR), self-timer,
backgrounds for window captures, file name templates, print. (v2 on the roadmap.)

## Develop

```sh
scripts/test.sh Snapper     # unit tests
scripts/run.sh Snapper      # build a debug .app and open it
scripts/check.sh Snapper    # the full gate: tests, release bundle, launch smoke test
```

Logic lives in `Sources/SnapperCore` (tested). Views and wiring live in `Sources/Snapper`.
`Sources/Snapper/Capture/` (screen capture service, window list, region overlay with
magnifier) and `Sources/SnapperCore/Capture/` (selection geometry, coordinate conversion,
window picking) have no Snapper dependencies, so they can move to SlopKit for Dropper,
Ruler and Snip.

Test hooks (environment variables, all off by default): `SNAPPER_SAVE_DIR`,
`SNAPPER_TEST_SCENE=1|full` (captures then contain only a generated test pattern:
every capture is filtered to the scene window *and* masked to its frame minus the menu bar,
so nothing else on screen can end up in a test capture),
`SNAPPER_TEST_HOOKS=1`, `SNAPPER_LOG`, `SNAPPER_APPEARANCE`, `SNAPPER_SILENT`. See
`Sources/Snapper/Diagnostics.swift`.
