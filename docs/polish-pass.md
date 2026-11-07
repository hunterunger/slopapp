# Polish pass (2026-11-05)

The owner looked closely at the launcher and caught details a picky Mac user notices at once:
tiny window buttons (the app was in macOS's compatibility look) and a content panel whose
corners didn't follow the window's. Their direction: **"I want each app to have a very close
attention to detail."** This pass brings every app up to that bar. It's about finish, not
features (the parity pass did features).

## What's already fixed for you

- `scripts/bundle.sh` stamps the real SDK, so every rebuilt app gets the current macOS look
  (full-size window buttons, current controls). **This changes how your app looks**: check
  every window, sheet, popover, menu and panel for anything the new look breaks or that now
  looks off (control sizes, toolbar heights, list insets, glass/material changes).
- SlopKit has `Radius` (`xs 4, s 6, m 8, l 12, xl 16, xxl 22`), `Radius.nested(in:padding:)`,
  `Radius.iconTile(side:)` and `.windowConcentric(fill:inset:hairline:)` (`Corners.swift`).
- `scripts/lint.sh <Name>` (part of `check.sh`) fails on corner-radius literals and hardcoded
  colours, and warns on spacing literals.
- `scripts/measure` checks screenshots: `corners` (window radius, concentric inset shapes),
  `line` (colour changes along a line, so you can measure gaps, insets and alignment in
  points), `color`, `contrast`.

## The bar

`docs/design-system.md` §4 "Detail rules" and §10 items 15–24. In short: concentric corners
from `Radius`, even insets on the 4 pt grid, things that look aligned are aligned to the
point, 0.5 pt separator hairlines, full-size window buttons, contrast in light and dark,
designed hover/pressed/selected/disabled/focus/empty/loading/error states, layouts that
survive long, empty and huge content, and nothing that jumps.

Compare against the original's level of finish too (`docs/research/<slug>.md`, the parity
section): where the original is polished in a way we aren't (an animation, a state, a precise
alignment), match the quality without copying its look.

## How to work

1. Read `AGENTS.md`, `docs/design-system.md` (all of §4 and §10), this file,
   `.claude/agents/app-builder.md`, your app's research doc and its source.
2. `scripts/lint.sh <Name>`: fix every failure. Corner literals → `Radius` tokens, and work
   out which are nested (they need `Radius.nested`). Colours: semantic or brand colours; a
   colour that is the app's data (a picked colour, an annotation colour the user chose, a
   syntax-highlight theme) may stay with `// lint:allow <reason>`. Move spacing literals to
   `Spacing` where it's the same kind of gap; leave deliberate optical nudges with
   `// lint:allow`.
3. `scripts/bundle.sh <Name>`, then **inventory every surface**: each window, tab, sidebar
   section, sheet, alert, popover, menu bar panel, HUD, overlay, Settings tab and empty/error
   state. Screenshot each with `scripts/drive shot <Name>` in light and dark: launch with
   `scripts/drive launch build/<Name>.app --env SLOP_APPEARANCE=dark` (or `light`; SlopKit's
   app delegate applies it to every app). Never change the system appearance. Use the app's
   test-data env vars so none of the owner's data appears.
4. For each screenshot: look at it at full size, and **measure** with `scripts/measure`:
   corners and concentricity, insets on each side, gaps between groups, alignment of leading
   edges and centre lines, hairline widths, contrast of secondary text. Write down every
   defect with numbers ("card padding 12 pt left, 14 pt right"; "thumbnail radius 8 inside a
   12 pt card with 6 pt padding: should be 6").
5. Fix them all. Re-shoot and re-measure until clean. Check the states too: hover (where you
   can trigger it without the real mouse, otherwise note it), selection, disabled, focus
   ring, loading, empty, error, very long names, 0/1/1,000 items.
6. Gates: `scripts/check.sh <Name> --perf`, no `[unlabeled]` in `scripts/drive tree`,
   16x16 window buttons for apps with standard windows.
7. Append a "Polish pass (2026-11-05)" section to `docs/research/<slug>.md`: the defect list
   with before → after numbers, screenshot paths (keep them under
   `/tmp/slopapp-polish/<slug>/`), anything not done and why.

## Rules

- Everything in `.claude/agents/app-builder.md` (owner-presence gate before real mouse or
  global keys, no real clipboard writes, no full-screen screenshots, test data in `/tmp`).
- Other agents polish other apps at the same time. **Only edit your app and its research
  doc.** SlopKit is polished separately first; don't edit it. If a SlopKit component looks
  wrong in your app, say so in your report.
- `build/Switchboard.app` is the owner's live default browser: only the Switchboard agent
  rebuilds it, and must leave it running and default.
- If the owner's own copy of your app is running, you may quit it to work; relaunch
  `build/<Name>.app` with `open` when you finish so they come back to the polished build.
- Don't bump versions, don't release, don't commit.

## Notes from the SlopKit pass (done first)

- `SLOP_APPEARANCE=light|dark` works in every app that links SlopKit (an image constructor in
  `SlopKitLaunch`, independent of the app delegate).
- `FloatingPanel` has `cornerRadius` (default `Radius.xl`) and publishes it as
  `@Environment(\.floatingPanelCornerRadius)` and as the container shape. Shapes inside a panel
  derive from it (`Radius.nested(in: floatingPanelCornerRadius, padding:)`); don't pass
  literals like `FloatingPanel(cornerRadius: 22)`.
- `.dropZoneCornerRadius(_:)` sets a `DropZone`'s radius.
- Coloured status text: `.textGreen`, `.textOrange`, `.textRed` (system colours darkened in
  light mode so they pass contrast). Never `.tertiary` for text people need to read.
- `FileQueueView`'s strip lines up with the list selection at exactly 10 pt: don't add
  horizontal padding around it.
- `scripts/measure corners` reports "too tight" when an inset is at least the container's
  radius (e.g. a DropZone 20 pt inside a window, grouped Settings sections). That's expected:
  a radius can't go below its minimum. Judge those by eye and by `Radius` tokens.
- The gallery (`swift run --package-path apps/SlopKit SlopKitGallery`, or
  `/tmp/slopapp-polish/slopkit/bundle-gallery.sh` for a stamped bundle) shows every component
  in every state; compare your usage against it.

## Notes from batch 1 (Slopapp, Clips, Switchboard, Snapper, Tidy, Squish)

- **`Divider` is 1 pt on macOS.** Use SlopKit's `Hairline()` / `Hairline(axis: .vertical)` and
  `.hairlineBorder(shape)` (one device pixel) instead. Every batch-1 app had this defect.
- **macOS 26 scroll views run under the toolbar**: scrolled content can draw over a custom
  header or toolbar items. Check every scrolling page scrolled, not just at rest.
- **Controls in a row must share a height** (an icon-only bordered button comes out taller
  than a text button on macOS 26). Measure them.
- **Things that change must not move things**: footers, notices, sizes filling in, Pause/
  Resume labels, back buttons appearing. Fixed slots, `.monospacedDigit()`, reserved space.
- **Layer colours don't follow light/dark** on their own: resolve them in `updateLayer` /
  `viewDidChangeEffectiveAppearance`.
- **AppKit labels inside a glass `FloatingPanel`** pick up the glass's vibrant label colours
  and come out too light on an opaque inner surface; set explicit semantic colours there. A
  `drive shot` of a glass panel has nothing behind it, so measure text contrast over an opaque
  backdrop of your own, not on the bare shot.
- **Status colours:** plain `.orange`/`.green` text is ~2:1 in light mode; use `.textOrange`,
  `.textGreen`, `.textRed`. `.tertiary` text fails contrast.
- **Settings explanations** read best as subtitles under their control, not separate rows.
- **`scripts/measure corners`** can misreport when content touches the probe lines (e.g. a
  capture image under a corner button): confirm with `scripts/measure line`.
- **Hover with the real pointer** usually can't be checked (owner present or screen locked).
  Design hover in code, and if the app has a forced-hover test hook, use it; otherwise list
  it as owed.

## Notes from batch 2 (Convert, Dropper, Zones, Crate, Ruler, Iconsmith)

- **Protect the owner's settings.** Before your first launch: `defaults export <bundle id>
  /tmp/slopapp-polish/<slug>/defaults-backup.plist`; at the end: `defaults import <bundle id>
  <that file>` (or `defaults delete` if the domain didn't exist). Two batch-2 runs changed or
  reset the owner's saved preferences. Test modes must write to a test suite, never the real
  domain.
- **Never press ⌘C (or trigger Copy) unless the app reads/writes a test pasteboard override.**
  One batch-2 run overwrote the owner's clipboard.
- `Hairline` and `AboutView` were fixed in SlopKit (no layout jump when a window reaches a
  Retina screen; About is 360 pt wide with a hairline). If you see an About tagline strand a
  word, report it.
- **NSPopover's corner radius isn't reachable** by SwiftUI's concentric shapes. Measure it
  (`scripts/measure corners` on a popover shot) and use a named constant derived from it.
- **Toolbars on macOS 26**: a long window title can push toolbar items into the » overflow at
  the default and minimum sizes; check both sizes with long content. Scrolled content can
  draw up under the toolbar: check scrolled states.
- **Buttons whose label changes** ("Extract All" → "Extract 2 Items") move their neighbours:
  keep labels fixed and put counts in a status line.
- **Self-sizing windows** (content-sized panels/sheets) are fragile with views that change size
  after attaching; test opening them repeatedly.

## Added mid-pass (owner request): Golden Gate fit, and light/dark as equals

The owner: "ensure all the apps are optimized for dark/light mode AND look like they fit in
with macOS Golden Gate." The rules are in `docs/design-system.md` §4 "Fitting in on macOS 27
Golden Gate" and §10 items 25–26. In short:

- Sidebars: the system's edge-to-edge sidebar, coloured (accent) icons, no inset sidebar card.
- Menus (menu bar, `MenuBarExtra`, context menus, pull-downs): text only unless the image is
  information (app icon, swatch, checkmark, preview). Golden Gate dropped decorative menu icons.
- Standard toolbars; no drawn toolbar strips.
- Inactive windows: selections and accent-coloured custom elements go grey. Shoot one
  inactive screenshot per window (open a second window of yours or `scripts/drive` focus
  another of your own windows; never activate the owner's apps).
- Glass: system materials only; readable text on glass keeps contrast at the clearest setting.
- Light and dark: every surface shot and measured in **both**, side by side. Look for colours
  that only work in one (fixed greys, shadows, borders, images, charts, selection fills),
  pure black/white you drew, and layers that don't update when the appearance changes while
  the app is running.

Add a "Golden Gate + light/dark" subsection to your research-doc section listing what you
checked and changed.

## Notes from the SlopKit round after batch 3 (use these, don't hand-roll)

- `Hairline` now always takes exactly 1 pt of layout and draws one device pixel along its top
  (or leading) edge, so it's safe in self-sizing windows and panels. Things next to a hairline
  moved by 0.5 pt; re-measure alignments that touch one.
- Inactive-window colours (`WindowState.swift`): `Color.windowAccent(_:)`, `.selectionTint(_:)`,
  `.selectionFill(_:)`, `.selectionRing(_:)` taking `ControlActiveState` (or `active: Bool` for
  `appearsActive`). Use them for every custom selection, accent icon and highlight.
- Readable coloured text: `NSColor.readable(_:on:target:)` / `Color.readable(_:on:target:)`
  (keeps the hue, darkens in light / lightens in dark only as much as needed; targets 4.5 text,
  3 symbols). `.textGreen/.textOrange/.textRed/.textAccent` are built on it.
- `ShortcutRow(..., subtitle:)` for a Settings explanation under a shortcut.
- `SettingsWindow.open()` opens Settings from AppKit code.
- Menu bar apps: reopening the app now also opens Settings (so an icon macOS hides can't
  strand the user). If your reopen shows its own window, SlopKit skips it; set
  `opensSettingsOnReopen = false` to opt out.
- `OverlayPalette` for chrome drawn over arbitrary screen content (capture overlays, loupes,
  badges): never pure black/white, readable over any backdrop.
- `FloatingPanel` and `HUD` use the system's regular glass, which follows the clear/tinted
  setting.
