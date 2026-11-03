# Ruler

Measure anything on screen, to the pixel.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to PixelSnap.

**Status:** alpha 0.1.0 (v1 built and self-tested; blind testing next)

## What it does

Press **⌥⇧M** (or choose **Measure** from the menu bar ruler). The screen freezes under a
crosshair, and Ruler measures the frozen pixels:

- **Hover** to see the distance from the pointer to the nearest edge left, right, up and
  down, with a label on each span.
- **Drag loosely around something** and let go: the box shrinks to the element's exact
  bounds and shows W × H. Hold ⌘ (or drag with the right button) to keep the box exactly as
  drawn. Shift makes it square, Option grows it from the center, Space moves it.
- **Click** to keep the edge-to-edge box under the pointer (for example, a button's size).
- Measurements **stay on screen** while you keep going. Hovering inside one reads its size,
  and hovering between two reads the gap. ⌫ deletes the one under the pointer, ⌘⌫ clears
  everything, ⌘Z undoes.
- **Return** or **⌘C** copies the measurement under the pointer (else the last one, else the
  hover distance) as plain `200 × 120`, CSS (`width: 200px; height: 120px;`) or SwiftUI
  (`.frame(width: 200, height: 120)`).
- **Guides**: H and V drop a horizontal or vertical guide at the pointer, snapped to an edge
  within 4 pt. Gaps between neighbouring guides are labeled, and hover distances stop at
  guides.
- **P** pins the current hover distance. Hold **⇧** for a full-screen crosshair.
- **= / −** make edge detection more or less tolerant (Strict, Fine, Normal, Loose).
  **U** switches points and pixels, and **Z** shows a magnifier.
- Arrow keys move the pointer by 1 (⇧: 10) points, or pixels in pixel mode. Esc (or ⌥⇧M again) closes,
  and the app you were in gets focus back.
- Right-click anywhere for a menu with every action.

Units are **points** by default, with .5 where an edge really sits on a half point on
Retina. **Pixels** means the display's own backing pixels, so on a "More Space" scaled
mode that's not the panel's physical pixels. Each display uses its own scale.

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
| Anywhere | ⌥⇧M measure (change it in Settings → Shortcuts) |
| Measuring | drag, ⌘-drag / right-drag (free box), click (element), Shift square, Option from center, Space move, H / V guides, P pin, hold ⇧ crosshair, = / − tolerance, U units, Z magnifier, Return / ⌘C copy, ⌫ delete, ⌘⌫ clear, ⌘Z undo, arrows nudge, Esc close |

## Permissions

**Screen Recording**, to read the pixels on screen. Ruler asks the first time you measure,
with a button to the right System Settings pane. macOS applies it after Ruler restarts.
Accessibility isn't needed (moving the pointer with the arrow keys doesn't require it).

## Privacy

No network, no accounts, no history. The frozen screen lives only in memory while the
overlay is open and is released as soon as it closes. Nothing is ever saved.

## Not there yet

Screenshots of measurements (Snapper covers screenshots), physical units (cm/in), a scale
factor for zoomed designs, aspect ratios, moving or resizing placed boxes, dragging guides,
background mode and restoring the last session. See
[`docs/research/ruler.md`](../../docs/research/ruler.md).

## Testing

Test mode never shows or measures your own screen:

```sh
scripts/drive launch build/Ruler.app --direct --env RULER_TEST_SCENE=1 --env RULER_TEST_HOOKS=1 --env RULER_LOG=/tmp/ruler-test/log.txt
```

- `RULER_TEST_SCENE=1` opens "Ruler Test Scene" (shapes at known sizes, captioned). While
  it's open, every freeze contains only that window. Everything else (other apps, menu bar,
  desktop, other displays) is masked out with SlopKit's `PrivacyMask` and shown as a plain
  backdrop.
- `RULER_TEST_HOOKS=1` listens for the distributed notifications
  `app.slopapp.ruler.test.<measure|close|selfcheck|hover|drag>`. `selfcheck` measures every
  scene shape on the real frozen image and logs expected vs found. `hover` takes `"x,y"`
  and `drag` takes `"x,y,w,h[,1 = free]"` in scene points.
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

Logic lives in `Sources/RulerCore` (edge finding, measurements, units, copy formats, the
test-scene layout; tested). The overlay, menu and settings live in `Sources/Ruler`. Screen
capture, coordinates, the badge and magnifier layers and the privacy mask come from
SlopKit's `Capture/`.
