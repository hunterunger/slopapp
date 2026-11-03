# Tiles research (inspired by Mosaic)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied: Mosaic
> (Light Pillar; not installed on this Mac) from its product page and reviews; Rectangle
> (MIT, the reference for keyboard window snapping) from its README and docs; and macOS's
> own tiling (Sequoia 15 and later) from Apple's help, on 2026-11-03. We never copy names,
> icons, artwork, wording, sounds or signature visuals.

## The job

Tiles puts the window you're working in exactly where you want it, from the keyboard, in
a fraction of a second: left half next to a reference doc, a third for chat, centered for
focus, onto the other display. People do this dozens of times a day, especially on large
or multiple displays. "Done" is the window snapped with no dragging and no resizing by hand.

The one interaction that matters most: **press ⌃⌥← and the front window fills the left
half; press it again and it becomes two-thirds, again one-third.**

## Who and when

- Side-by-side writing: editor left, browser right.
- Three-up on an ultrawide: chat | work | reference in thirds.
- Moving a window to the external display after docking.
- Centering a small window for focus or a screen share.

Frequency: tens of times a day; each use < 1 second.

## macOS's built-in tiling (the bar to beat)

macOS 15+ already offers: Fn-⌃-arrows for halves, Fn-⌃-F fill, Fn-⌃-C center, Fn-⌃-R
return to previous size, Fn-⌃-⇧-arrows to arrange two windows, quarters and
half+quarters arrangements from the green button / Window menu, drag-to-edge and
⌥-drag tiling, and an optional margin between tiled windows. It has **no thirds, no
two-thirds, no repeat-to-cycle sizes, no keyboard move to another display, no keyboard
quarters, no per-app exclusions, no "almost maximize"**, and its drag tiling often fights
third-party snap areas. Tiles v1 has to be clearly better on exactly those gaps, and
stay out of the way of what macOS already does well (we don't ship drag-to-edge snapping
in v1).

## Feature inventory

| # | Feature | How the originals do it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Halves (left/right/top/bottom) | Rectangle: ⌃⌥ arrows; macOS: Fn-⌃ arrows | must | Default ⌃⌥←/→/↑/↓. |
| 2 | Repeat to cycle sizes | Rectangle: repeat left/right cycles ½ → ⅔ → ⅓; option to traverse displays | must | The signature win over macOS. Cycle ½ → ⅔ → ⅓ on the same edge. |
| 3 | Quarters | Rectangle ⌃⌥U/I/J/K; macOS: menu only | must | ⌃⌥U, I, J, K. |
| 4 | Thirds and two-thirds | Rectangle ⌃⌥D/F/G, ⌃⌥E/T; repeat cycles thirds | must | ⌃⌥D (first), F (center), G (last), E (first two), T (last two). Orientation-aware on portrait displays (thirds stack vertically). |
| 5 | Maximize / almost maximize / maximize height | Rectangle all three; macOS Fill | must (maximize, almost) / should (height) | ⌃⌥Return maximize; ⌃⌥⇧Return almost (90%, centered). Not full screen (no new Space). |
| 6 | Center | Both | must | ⌃⌥C keeps size, centers in visible frame. |
| 7 | Restore previous frame | Rectangle ⌃⌥⌫; macOS Fn-⌃-R | must | Per-window memory of the pre-Tiles frame (keyed by pid + AX window identity, in memory). |
| 8 | Next / previous display | Rectangle ⌃⌥⌘←/→; macOS: menu only | must | Keeps the same relative layout on the target display (left half stays left half). |
| 9 | Gaps between windows | Rectangle gap setting; macOS "tiled windows have margins" | should | One "Gap" slider 0–20 pt, default 0. |
| 10 | Larger / smaller, move to edge without resizing | Rectangle | later | |
| 11 | Sixths, eighths, ninths, corner thirds | Rectangle | later | |
| 12 | Drag-to-edge snap areas | Rectangle snap areas; Mosaic drop-on-layout; macOS native | skip (v1) | macOS has it; two systems fighting over the same drag is a top Rectangle support issue. |
| 13 | Layout grid picker (Mosaic's signature) | A panel with layout tiles; drag a window onto one; "Quick Layout" drag across a grid | later | Keyboard version is the interesting idea: a `FloatingPanel` grid, arrows pick cells, Return applies. v1.1 candidate. |
| 14 | Custom layouts / groups / per-app auto layouts | Mosaic Pro | later | |
| 15 | Tile all / arrange multiple windows | Rectangle tile-all, cascade; macOS arrange two/quarters | later | |
| 16 | Ignore apps | Rectangle: shortcuts unregistered while that app is frontmost | should | Games, remote desktops, apps with their own ⌃⌥ shortcuts. |
| 17 | Animation | Rectangle experimental, off | skip | Instant is better; honors Reduce Motion trivially. |
| 18 | "Minimum size reached" feedback | Rectangle shows a HUD when an app refuses the size | must | After setting, read back the frame; if it differs, keep it fully on screen and show SlopKit `HUD` "Window can't be that small". |
| 19 | Menu listing every action with its shortcut | Rectangle's status menu | must | Status menu = cheat sheet; clicking an item acts on the front window of the app that was active. |
| 20 | Touch Bar, iPhone remote, window capture | Mosaic Pro | skip | Not the job / obsolete. |
| 21 | URL scheme | Rectangle `rectangle://execute-action?name=` | later | App Intents instead (Shortcuts). |
| 22 | Move between Spaces | Not possible with public API (Rectangle notes this) | skip | |

### Must-haves, counted

1 halves, 2 cycling, 3 quarters, 4 thirds/two-thirds, 5 maximize/almost, 6 center,
7 restore, 8 next/prev display, 18 min-size handling, 19 menu cheat sheet, plus the
Accessibility first-run screen. Eleven; the math lives in a pure, tested core.

## Key flows

### Flow 1: snap (main job)
1. Focus any window; press ⌃⌥←.
2. Tiles reads the focused window via Accessibility (`AXUIElementCreateApplication(pid)` →
   `kAXFocusedWindowAttribute`), computes the target in the visible frame of the display
   holding most of the window (excludes menu bar and Dock), applies gap, and sets
   size → position → size (the double size-set handles moves between displays of different
   sizes).
3. Press ⌃⌥← again within ~1.5 s on the same window → ⅔; again → ⅓; again → ½.
4. Total time < 50 ms; no animation.

### Flow 2: first run / Accessibility
1. Launch: status icon + a small first-run window (the only window Tiles ever opens besides
   Settings): one sentence on why ("Tiles moves and resizes windows for you, which macOS
   only allows with Accessibility access"), `PermissionGate(.accessibility)` with Open
   System Settings, live re-check (no restart needed).
2. Once granted, the window shows the shortcut cheat sheet with a "Try it: press ⌃⌥←" line,
   and a note that macOS's own Fn-⌃ tiling keeps working.
3. If not granted: shortcuts show the gate again instead of silently failing.

### Flow 3: move to the other display
1. ⌃⌥⌘→ moves the window to the next display, same relative layout (or same relative
   position and clamped size if it wasn't tiled).

## Settings inventory

| Setting | Default | Options | Keep? |
|---|---|---|---|
| Shortcuts for every action | Rectangle-style ⌃⌥ set (above) | recorder per action, Restore Defaults | must |
| Repeat cycles sizes | on | toggle | must |
| Repeat ←/→ at the edge moves to next display | off | toggle | should |
| Gap between windows | 0 pt | 0–20 | should |
| Almost-maximize size | 90% | 80–95% | later |
| Ignored apps | none | app list | should |
| Launch at login / Show in menu bar | off / on | toggles | must |

## Menus and shortcuts

Status menu (each item shows its shortcut): Left Half ⌃⌥← · Right Half ⌃⌥→ · Top Half ⌃⌥↑ ·
Bottom Half ⌃⌥↓ · — · Top Left ⌃⌥U · Top Right ⌃⌥I · Bottom Left ⌃⌥J · Bottom Right ⌃⌥K ·
— · First Third ⌃⌥D · Center Third ⌃⌥F · Last Third ⌃⌥G · First Two Thirds ⌃⌥E · Last Two
Thirds ⌃⌥T · — · Maximize ⌃⌥↩ · Almost Maximize ⌃⌥⇧↩ · Center ⌃⌥C · Restore ⌃⌥⌫ · — · Next
Display ⌃⌥⌘→ · Previous Display ⌃⌥⌘← · — · Ignore "<frontmost app>" · `MenuFooter`.
None of these collide with macOS defaults (⌃←/→ switch Spaces; Fn-⌃ is macOS tiling).

## Permissions and system integration

- **Accessibility** (required). Asked on the first-run window; revoked mid-use → next
  shortcut shows the gate.
- Global hotkeys via `KeyboardShortcuts` (Carbon hotkeys; no Input Monitoring needed).
- No Screen Recording, no network.

## UX patterns worth adopting

- **Repeat the same key to refine** (Spectacle/Rectangle): no extra shortcuts to learn.
- **The menu is the cheat sheet**: discoverability without a tour.
- **Feedback only on failure** (min-size HUD); success is the window moving.
- **Relative layout survives display moves.**

## What we won't copy, and what we'll do better

- Not copying: Mosaic's layout panel visuals, Pro tiers, remote app; Rectangle's icon/copy.
- Better than macOS: thirds, cycling, display moves, quarters on keys, ignore list.
- Better than Rectangle: fewer, clearer settings; no drag-snap conflicts with macOS; a
  first-run screen that explains coexistence with built-in tiling.

## Edge cases

- Apps with minimum sizes (thirds on a laptop), fixed-size windows (System Settings),
  sheets and panels (act on the main window, not the sheet).
- `AXEnhancedUserInterface` turned on by some apps/VoiceOver makes AX moves slow and
  janky: temporarily set it off on the app element while moving, then restore (Rectangle's
  workaround).
- Full-screen windows (can't tile: HUD "Exit full screen first"); minimized windows; no
  focused window (desktop focused: do nothing quietly).
- Stage Manager on: visible frame shrinks; still use `visibleFrame`.
- Displays of different scale, arrangement above/below, display unplugged between press and
  restore; coordinate flip between AppKit (bottom-left) and AX (top-left of primary).
- Terminal/iTerm resizing in character increments (frame won't be exact: don't loop).
- Dock auto-hide and menu bar auto-hide; notched displays.
- Electron/Java apps that report AX frames late: read back after a short delay once.

## Our v1 scope

- [ ] Accessibility first-run window with live re-check and shortcut cheat sheet.
- [ ] Halves, quarters, thirds, two-thirds with the default ⌃⌥ shortcuts.
- [ ] Repeat-to-cycle ½ → ⅔ → ⅓ (left/right; top/bottom on portrait).
- [ ] Maximize, almost maximize, center, restore previous frame.
- [ ] Next/previous display keeping relative layout.
- [ ] Min-size handling: window stays on screen, HUD explains.
- [ ] Status menu lists every action with shortcut; Settings: General, Shortcuts, About.
- [ ] Pure core (`TilesCore`): layout math for every action, cycle state, display choice,
      coordinate conversion, gaps; tested with fake screens (portrait, mixed scale, stacked).

## Open questions

Decisions (owner defaults, 2026-11-03: native, fast, private, no network):

1. **Default shortcuts:** ship the ⌃⌥ set above (they don't collide with macOS). If the
   user also runs Rectangle, `KeyboardShortcuts` registration fails visibly in Settings.
2. **Drag-to-edge snapping:** skip; macOS does it.
3. **Mosaic-style grid picker:** later (v1.1), keyboard-first.
4. **Gaps:** should, default 0.

## Sources

- [Mosaic product page](https://lightpillar.com/mosaic.html)
- [MacTrast review of Mosaic](https://www.mactrast.com/2017/04/review-mosaic-simple-window-managment-mac/)
- [Mosaic Setapp reviews](https://setapp.com/fr/apps/mosaic/customer-reviews)
- [Rectangle (MIT)](https://github.com/rxhanson/Rectangle)
- [Apple: Tile app windows on Mac](https://support.apple.com/guide/mac-help/tile-app-windows-mchl9674d0b0/mac)
- [Macworld: Sequoia tiling, don't ditch that tiling app](https://www.macworld.com/article/2365751/macos-sequoia-windows-tiling-dont-ditch-that-tiling-app.html)

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.
