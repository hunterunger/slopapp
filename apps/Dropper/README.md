# Dropper

Pick any color on screen and copy it in the format you need.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to Sip.

**Status:** beta (0.2.0)

## What it does

Press **⌥⇧C** in any app (or click the eyedropper in the menu bar). Click a pixel and its
value is on the clipboard in your format, with a small confirmation showing the color.
Esc cancels without touching the clipboard.

- **Menu bar icon:** the eyedropper picks, the small arrow next to it opens the Dropper
  panel (right-click always opens the panel). A dot shows the last color you picked.
  Settings › General switches to a single icon or turns the dot off.
- **The panel:** a toolbar (pick, Contrast Checker, new palette, color editor), the copy
  format, your **Color History** and every **palette** as a strip of colors. Click one to
  open it: each color shows its name and value; click to copy, drag it into another app,
  or use **•••** for Copy As (every format), Check Contrast, Add to Palette, Edit and
  Remove. The bottom bar has Settings, color-blindness preview, the Library window and Quit.
- **Palettes:** named groups of colors with notes. Turn on a palette's circle and new
  picks are added to it as well as to the history. Rename, sort (hue, lightness, name,
  date), lock, duplicate, merge, export and delete from the palette's ••• menu.
- **Library window** (panel › window button, or Window › Dropper Library, ⌘0): palettes
  on the left, their colors in the middle (drag to reorder, drag onto another palette to
  add, select several for bulk actions), and an editor on the right: name, saturation and
  brightness square, hue slider, hex and RGB/HSB/HSL fields, notes, and the color in every
  format with a copy button each.
- **Color Dock:** add palettes to the dock (palette ••• › Add to Color Dock) and they sit
  in a slim strip on the screen edge, above other windows. Hover a palette to see its
  colors; click one to copy it, or drag it out. Drag the grip to move the dock; it snaps
  to the nearest edge.
- **31 formats** in four groups: Web (Hex, RGB, RGBA, HSL, HSLA, HWB, OKLCH, Lab, LCH,
  `color(display-p3 …)`, CMYK, HSB), Apple (SwiftUI, NSColor, UIColor in RGB and HSB,
  CGColor, Objective-C NSColor and UIColor), Android and Flutter (ARGB hex, Android XML
  resource, Jetpack Compose, Flutter) and Other (.NET, Java, unit RGB/RGBA for OpenGL).
  Choose the copy format in the panel; hide the ones you never use in Settings › Formats,
  where you can also give apps their own format (pick in Xcode, get SwiftUI).
  Numbers always use a `.` decimal point.
- **Pick multiple colors** (hold the panel's eyedropper, or the Color menu): keeps picking
  until Esc and copies every value, one per line. **Pick Contrast Pair** picks a text and a
  background color and opens the Contrast Checker with them.
- **Contrast Checker** (⌘K): the verdict (AAA, AA, AA Large, Fail) and the ratio drawn in
  your two colors, a column per color with its value (type or paste hex, `rgb()`, `hsl()`,
  `oklch()` or `color(display-p3 …)`), an eyedropper, **Fix** (changes only that color's
  lightness to reach the next level: AA, then AAA) and hue, saturation and brightness
  sliders; plus the full WCAG 2 breakdown for normal text, large text and interface
  elements. The ratio is rounded down, so a pass is never overstated. Save the pair as a
  palette with one click.
- **Import and export palettes:** Adobe Swatch Exchange (`.ase`), Apple Color List
  (`.clr`), GIMP (`.gpl`), Dropper's JSON, CSS custom properties, and a printable PDF
  swatch sheet (export only). Import also reads
  any text file (CSS, design tokens, notes) and collects the colors written in it.
- **Color blindness preview:** the eye button in the panel shows every swatch as people
  with protanopia, deuteranopia, tritanopia or achromatopsia see it. Copied values never
  change.

## Two pickers

- **System magnifier** (default): the macOS loupe. Needs no permission.
- **Dropper loupe** (Settings › Picker): a round magnifier with a pixel grid, the pixel
  you'll get outlined and its value in your format. Arrow keys move exactly one pixel
  (⇧: ten), **+ / −** change its size, **⌥+ / ⌥−** its zoom (or scroll, ⌥-scroll). Click,
  Return or Space picks; Esc or right-click cancels. It needs **Screen Recording**: it
  reads the pixels from a still image of the screen taken when it opens. Without the
  permission Dropper falls back to the system magnifier.

## Color accuracy

Dropper converts what's on screen to a standard color space instead of reporting raw
display values, so a web page's `#FF0000` picks as `#FF0000` on a P3 MacBook too.

- **sRGB** (default): matches CSS, Figma and most web tools. Colors more vivid than sRGB
  (wide-gamut photos, P3 designs) are copied as the closest sRGB value and flagged
  "Outside sRGB".
- **Display P3**: for P3 asset catalogs and wide-color designs. Hex and RGB values are P3
  numbers, and the Swift formats use the P3 initializers. Android, Flutter, .NET, Java and
  the HSB code formats stay sRGB, since those APIs take sRGB.

## Keyboard

| Key | Action |
|---|---|
| ⌥⇧C | Pick a color from anywhere (change it in Settings › Shortcuts) |
| Esc | Cancel the pick; close the panel |
| Arrows, ⇧ arrows | Dropper loupe: move 1 or 10 pixels |
| + / −, ⌥+ / ⌥− | Dropper loupe: size, zoom |
| ⌘K | Contrast Checker (a global shortcut can be set in Settings) |
| ⌘N, ⌘O | New palette, import palette (while a Dropper window is in front) |
| ⌘0 | Library window |
| ⌘1 / ⌘2 | Contrast Checker: pick the text / background color |
| ⌘E | Contrast Checker: swap colors |
| ⇧⌘C | Contrast Checker: copy the result |
| Esc, ⌘W | Close the Contrast Checker or the panel |

Optional global shortcuts (unset by default): pick multiple colors, contrast checker, show
the panel, open the Library, show or hide the Color Dock.

## Privacy and permissions

- No permissions for the default picker: the macOS color sampler runs outside the app.
- The optional Dropper loupe needs Screen Recording and only reads the still image while
  it's open; nothing is saved or sent anywhere.
- No network connections, no analytics. Your colors and palettes are one JSON file in
  `~/Library/Application Support/app.slopapp.dropper`.

## Not there yet

Custom format templates, colors with transparency, grouping colors inside a palette, opening `.ase`/`.clr` files from
Finder, a `dropper://` URL scheme, and sending colors straight to design apps.

## Develop

```sh
scripts/test.sh Dropper     # unit tests
scripts/run.sh Dropper      # build a debug .app and open it
scripts/check.sh Dropper    # the full gate: tests, release bundle, launch smoke test
```

Logic lives in `Sources/DropperCore` (tested). Views and wiring live in `Sources/Dropper`.
Test hooks (`DROPPER_DATA_DIR`, `DROPPER_FAKE_PICKS`, `DROPPER_TEST_SCENE`, ...) are listed
in `Sources/Dropper/Diagnostics.swift`.
