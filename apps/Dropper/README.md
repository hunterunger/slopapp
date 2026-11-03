# Dropper

Pick any color on screen and copy it in the format you need.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to Sip.

**Status:** beta (0.2.0)

## What it does

Press **⌥⇧C** in any app. The pointer turns into the system magnifier; click a pixel and
its value is on the clipboard in your format, with a small confirmation showing the color.
Esc cancels without touching the clipboard.

- **Formats:** Hex (`#3366CC`), CSS `rgb()`, `hsl()`, HSB, SwiftUI `Color`, `NSColor`,
  `UIColor`, and CSS `color(display-p3 …)`. Choose the one that gets copied in the menu
  (Copy Format) or in Settings. Numbers always use a `.` decimal point.
- **Every format, one click:** the menu bar menu lists the last color in every format.
  Click one to copy it.
- **History:** the last 100 colors, newest first, without duplicates. The menu shows the
  10 most recent; clicking one copies it in your format. Colors your chosen space can't
  show are marked "outside sRGB", so a vivid P3 red and a plain red don't look alike.
- **Contrast Checker** (menu › Contrast Checker…): text and background colors (type or
  paste hex, `rgb()`, `hsl()` or `color(display-p3 …)`, or pick from the screen), a live
  preview, the WCAG 2 ratio, and pass/fail for normal text, large text and interface
  elements at AA and AAA. The shown ratio is rounded down to two decimals so a pass is
  never overstated; pass and fail use the exact ratio. Your pair is kept between uses;
  when you've picked new colors since, a "Use Last Picks" button offers them.
- **Main menu:** while Settings or the Contrast Checker is in front, the Color menu has
  Pick Color, Contrast Checker, Copy Last Color As and Recent Colors, so everything works
  even when a crowded menu bar hides the icon. Help › Dropper Help opens this page.

## Color accuracy

Dropper converts what's on screen to a standard color space instead of reporting raw
display values, so a web page's `#FF0000` picks as `#FF0000` on a P3 MacBook too.

- **sRGB** (default): matches CSS, Figma and most web tools. Colors more vivid than sRGB
  (wide-gamut photos, P3 designs) are copied as the closest sRGB value and flagged
  "Outside sRGB".
- **Display P3**: for P3 asset catalogs and wide-color designs. Hex and RGB values are P3
  numbers, and the Swift formats use the P3 initializers.

## Keyboard

| Key | Action |
|---|---|
| ⌥⇧C | Pick a color from anywhere (change it in Settings › Shortcuts) |
| Esc | Cancel the pick |
| ⌘K | Contrast Checker (from the menus; a global shortcut can be set in Settings) |
| ⌘1 / ⌘2 | Contrast Checker: pick the text / background color |
| ⌘E | Contrast Checker: swap colors |
| ⇧⌘C | Contrast Checker: copy the result |
| Esc, ⌘W | Close the Contrast Checker |

## Privacy and permissions

- No permissions. Dropper uses the macOS color sampler, which runs outside the app and
  needs no Screen Recording access.
- No network connections, no analytics. History is a small JSON file in
  `~/Library/Application Support/app.slopapp.dropper`.

## Not there yet

Palettes, a precise picker with pixel nudging and zoom, picking a contrast pair in one go,
contrast fix suggestions, OKLCH and Android/Flutter formats, custom format templates, and
copying another format straight from the "Copied" confirmation.

## Develop

```sh
scripts/test.sh Dropper     # unit tests
scripts/run.sh Dropper      # build a debug .app and open it
scripts/check.sh Dropper    # the full gate: tests, release bundle, launch smoke test
```

Logic lives in `Sources/DropperCore` (tested). Views and wiring live in `Sources/Dropper`.
Test hooks (`DROPPER_DATA_DIR`, `DROPPER_FAKE_PICKS`, ...) are listed in
`Sources/Dropper/Diagnostics.swift`.
