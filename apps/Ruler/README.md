# Ruler

Measure anything on screen, to the pixel.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to PixelSnap.

**Status:** alpha 0.1.0 (v1 built and self-tested; blind testing next)

## What it does

Press **⌥⇧M** (or choose **Measure** from the menu bar ruler). The screen freezes under a
crosshair, and Ruler measures the frozen pixels:

- **Hover**: lines run from the pointer to the nearest edge left, right, up and down, and
  one pill next to the pointer reads the width × height between them.
- **Drag loosely around something** and let go: the box shrinks to the element's exact
  bounds, with its size in the middle. Hold ⌘ (or drag with the right button) to keep the
  box exactly as drawn. Shift makes it square, Option grows it from the center, Space
  moves it. **Click** to keep the edge-to-edge box under the pointer.
- **Resize a box** by dragging a side or corner (Shift keeps its proportions).
- Measurements **stay on screen** while you keep going. Hovering between two boxes reads the
  gap. ⌫ deletes the one under the pointer, ⌘⌫ clears everything, ⌘Z undoes.
- **Hold a distance**: P keeps the current width and height on screen, X just the width,
  Y just the height.
- **Return** or **⌘C** copies the measurement under the pointer (else the last one, else the
  hover distance) as plain `200 × 120`, CSS, Sass, Tailwind or SwiftUI. A held width or
  height copies just that (`width: 200px;`).
- **Screenshots**: S saves and C copies a picture of the box under the pointer (else of
  everything measured) with the measurements drawn in, plus padding (⌥ flips it). ⌘S, then
  drag, saves exactly the area you drag.
- **Guides**: H and V drop a horizontal or vertical guide at the pointer, snapped to an edge,
  a box's side or the middle between two guides. Drag a guide to move it. Gaps between
  guides and to the display edges are labeled, and hover distances stop at guides.
- Hold **⇧** for a full-screen crosshair. **= / −** (or **T**) change edge tolerance,
  **U** switches points and pixels, **Z** shows a magnifier, **?** hides the key hints.
- Arrow keys move the pointer by 1 (⇧: 10) points, or pixels in pixel mode.
- **Esc** closes. **⌥⇧M** with measurements on screen keeps them there (click-through)
  while you go back to work, and ⌥⇧M again picks them back up. Switching to another app
  does the same. **Restore Last Session** brings back the last closed session, even after
  quitting.
- Right-click anywhere for a menu with every action.

Units are **points** by default, with .5 where an edge really sits on a half point on
Retina. **Pixels** means the display's own backing pixels, so on a "More Space" scaled
mode that's not the panel's physical pixels. Each display uses its own scale.

**Scale** (menu bar or Settings) divides every number, for designs shown bigger or smaller
than real: @2x for a mockup exported at 2× and viewed at 100%, 50% Zoom when a design tool
is zoomed out, or any custom value. A corner badge says when it's on.

## How edges are found

An edge is where two neighbouring pixels differ by more than the tolerance (the largest
change of red, green or blue, 0–255). Smooth gradients and soft shadows have no such step,
so they don't stop a measurement. A card with a drop shadow measures as the card. A loose
box shrinks each side inward to the first edge it meets. The capture is read in the
display's own color space, because converting it to sRGB dithers flat fills by up to 13
levels.

| Tolerance | Threshold | Use |
|---|---|---|
| Strict | 3 | Faint borders (captures differ by 1–2 even on flat fills) |
| Fine | 8 | Low-contrast separators |
| Normal (default) | 20 | Most UI; ignores anti-aliasing haze and soft shadows |
| Loose | 56 | Noisy images, JPEG artifacts; misses white-on-near-white edges |

## Keyboard

| Where | Keys |
|---|---|
| Anywhere | ⌥⇧M measure / keep on screen / resume (change it in Settings → Shortcuts) |
| Measuring | drag, ⌘-drag / right-drag (free box), click (element), drag a side or corner (resize), Shift square, Option from center, Space move, H / V guides, P / X / Y hold, hold ⇧ crosshair, S / C screenshot (⌥ padding), ⌘S screenshot of an area, = / − / T tolerance, U units, Z magnifier, ? hints, Return / ⌘C copy, ⌫ delete, ⌘⌫ clear, ⌘Z undo, B keep on screen, arrows nudge, Esc close |

## Permissions

**Screen Recording**, to read the pixels on screen. Ruler asks the first time you measure,
with a button to the right System Settings pane. macOS applies it after Ruler restarts.
Accessibility isn't needed (moving the pointer with the arrow keys doesn't require it).

## Privacy

No network, no accounts. The frozen screen lives only in memory while the overlay is open
and is released as soon as it closes (or steps into the background). Screenshots are only
saved when you press S, to the folder in Settings (the Desktop by default). Restore Last
Session keeps only the measurements (numbers and positions), never pixels.

## Not there yet

Physical units (cm/in), rebinding the in-overlay keys, a
light label style, right-click on the menu bar icon to start, and design-tool integrations
(Scale covers zoomed designs by hand). See
[`docs/research/ruler.md`](../../docs/research/ruler.md).

## Testing

Test mode never shows or measures your own screen:

```sh
scripts/drive launch build/Ruler.app --direct --env RULER_TEST_SCENE=1 --env RULER_TEST_HOOKS=1 \
  --env RULER_LOG=/tmp/ruler-test/log.txt --env RULER_PASTEBOARD=app.slopapp.ruler.test \
  --env RULER_SCREENSHOT_DIR=/tmp/ruler-test/shots
```

- `RULER_TEST_SCENE=1` opens "Ruler Test Scene" (shapes at known sizes, captioned). While
  it's open, every freeze contains only that window. Everything else (other apps, menu bar,
  desktop, other displays) is masked out with SlopKit's `PrivacyMask` and shown as a plain
  backdrop. Screenshots (S/C) are cropped to the scene and refused on other displays.
- `RULER_FAKE_CAPTURE=1` (with the scene): freeze by drawing the scene itself instead of
  recording the screen. No Screen Recording needed, and it works on a locked screen.
- `RULER_PASTEBOARD=name` copies to a private pasteboard instead of the clipboard;
  `RULER_SCREENSHOT_DIR=path` saves screenshots there.
- `RULER_TEST_HOOKS=1` listens for the distributed notifications
  `app.slopapp.ruler.test.<name>`: `measure`, `close`, `toggle` (the shortcut),
  `background`, `resume`, `restore`, `selfcheck` (measures every scene shape on the real
  frozen image and logs expected vs found), `leakcheck` (every screenshot crop stays in the
  scene and nothing outside it is unmasked), `hover` (`"x,y"` in scene points), `drag`
  (`"x,y,w,h[,1 = free]"`), `mousedrag` (`"x1,y1,x2,y2[,shift[,hold]]"`: a real-style mouse
  drag; `hold` stops before mouse-up to show the box being drawn), `flags` (`shift`,
  `command`, `none`: modifiers as if held, e.g. the crosshair), `appearance` (`light`,
  `dark`, `system`: switches the app's appearance live), `focusscene` (the test scene
  becomes the key window, to see other windows inactive), `key` (a letter, or `return`, `delete`, `escape`, `cmd-z`,
  `cmd-delete`, `opt-s`…) and `dump` (a .png path: the overlay as drawn, at the display's
  own pixels, so line crispness can be checked).
- `RULER_LOG=path` logs timings and sizes (never pixels). `RULER_APPEARANCE=light|dark`
  forces an appearance.
- While measuring, `scripts/drive tree Ruler` shows the live readout as the overlay's value
  ("Horizontal 200 pt, vertical 120 pt. Areas: …").

## Develop

```sh
scripts/test.sh Ruler     # unit tests
scripts/run.sh Ruler      # build a debug .app and open it
scripts/check.sh Ruler    # the full gate: tests, release bundle, launch smoke test
```

Logic lives in `Sources/RulerCore` (edge finding, measurements, units, scale, aspect
ratios, copy formats, label placement, screenshot crops, saved sessions, the test-scene
layout; tested). The overlay, menu and settings live in `Sources/Ruler`. Screen
capture, coordinates, the badge and magnifier layers and the privacy mask come from
SlopKit's `Capture/`.
