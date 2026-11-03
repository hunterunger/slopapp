# Ruler research (inspired by PixelSnap)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied on
> 2026-11-03: **PixelSnap 2.6.4** (Setapp build, /Applications/Setapp/PixelSnap.app,
> read-only), its website and changelog, the Setapp listing and reviews, and a few
> third-party write-ups. We study how it works so we don't reinvent the wheel. We never
> copy its name, icons, artwork, wording, sounds or signature visuals.
>
> **What was looked at:** the bundle's English strings (every action name, settings label
> and onboarding line), the compiled status menu and Preferences nibs (every tab, control,
> popup option and action name, read offline as archives), the Info.plist (no URL scheme,
> `LSUIElement`), the list of onboarding videos and sounds, and the app's preference keys
> (names only). PixelSnap was not running; it was launched without activation and quit
> afterwards. Its preferences were compared before and after: only a launch counter and the
> color panel's window-frame autosave moved, no settings.
>
> **Not explored live:** the status menu and the Preferences window. The status item has
> no menu that Accessibility can open, and an Accessibility press on it **crashed
> PixelSnap** (a trap inside its status button action, logged as a crash report). Opening it
> needs a mouse click, which this step doesn't do. The nibs gave the same structure
> (menu items, Preferences tabs, controls, options), but **default values and default
> in-overlay key bindings are not verified**; they're marked as such below. The measuring
> overlay was never started, per instructions (it captures the owner's screen).

## The job

A designer or front-end developer is looking at something on screen (a mockup in Figma, a
page in the browser, a build in the Simulator, a competitor's app) and needs a number: how
wide is that button, how big is the gap between these two cards, are these two labels
really aligned, is this padding 16 or 20. Design tools answer that only for their own
files; everything else on screen is pixels. Done feels like: press a shortcut, point at the
thing, read the number (and paste it) in under two seconds, without opening a design tool
or taking a screenshot to zoom into.

**The one interaction that matters: press a shortcut → the screen freezes under a
crosshair → hovering shows the edge-to-edge width and height of the space under the
pointer, snapped to the nearest visible edges → drag a box around an element and it
shrinks to the element's exact bounds with W × H → Return copies it, Esc leaves.**

## Who and when

- A front-end dev compares their browser build against the Figma mockup: measures the
  card padding in both and finds the 4 pt difference.
- A designer reviews an iOS build in the Simulator: checks that icons line up on one
  baseline with guides, measures the gap between list rows.
- A PM or QA person files a bug: "the button is 38 pt tall, spec says 44", with a
  screenshot that has the measurement drawn on it.
- Someone checks an element in an app that doesn't expose sizes (a PDF, a video frame, a
  native app's settings window).
- Frequency: many short bursts a day for designers/devs (each use 2–20 seconds, a session
  of several measurements maybe a minute); occasional for everyone else.

## Feature inventory

Priority: **must** (v1 isn't worth shipping without it), **should** (v1 if cheap, else
v1.1), **later**, **skip** (with reason). Key names in "How the original does it" come
from its onboarding and third-party write-ups; defaults not verified live.

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Global shortcut starts measuring | One rebindable global hotkey ("Activate"); also the status menu's "Find Dimensions"; right-click on the status item starts it | must | `KeyboardShortcuts`, proposed default ⌥⇧M (see Menus). Menu item "Measure" shows it. Pressing it again while measuring closes (or enters background mode if we build it). |
| 2 | Full-screen overlay on every display, crosshair cursor | Overlay over all screens; cursor can be hidden (setting) | must | Reuse Snapper's `RegionOverlay`/`OverlayPanel` pattern: one borderless panel per display at `.screenSaver` level, `.canJoinAllSpaces` + `.fullScreenAuxiliary`. |
| 3 | Freeze screen | Optional setting (off = measures the live screen; on = freezes so moving things can be measured and windows stay active) | must (always on) | We always freeze, like Snapper: one ScreenCaptureKit snapshot per display, edge detection and the drawing read the same pixels. Freezing also lets you measure hover states and open menus (hover, then press the shortcut). |
| 4 | Distance tool (hover) | From the pointer, lines run left/right and up/down to the nearest edges; labels show the horizontal and vertical span | must | Scan the frozen image's row and column outward from the pointer until the color changes beyond tolerance. Two lines with end ticks, a label for each span. Cheap: two 1-D scans per mouse move. |
| 5 | Area tool / find dimensions (drag) | Drag a box around an element; on release it snaps inward to the element's bounds; shows W × H. Several objects can be selected at once | must | Shrink each edge inward until its row/column has a pixel differing from the box's border color beyond tolerance. Label W × H. Areas stay on screen for the session. |
| 6 | Area without snapping | Right-drag, or hold ⌘ while drawing; Ctrl-click counts as right-click | must | Hold ⌘ to draw a free box (and right-drag). Same `SelectionGeometry` as Snapper. |
| 7 | Multiple measurements on screen | Areas accumulate; distances can be "held" (pinned); Clear All in menu and context menu | must (areas) / should (pinned distances) | Areas persist until Esc closes or "Clear" (⌫ on hovered, ⌘⌫ all). |
| 8 | Distances between areas | Distance tool snaps to selected objects; hovering between two areas measures the gap between them | should | Treat placed areas' edges as edges for the hover scan, so the gap between two boxes reads correctly even on noisy backgrounds. |
| 9 | Hold horizontal / vertical distance | Two keys pin the current horizontal or vertical distance on screen | should | Simplify: one key (P) pins the current hover measurement (both axes); pinned items behave like areas (hover, delete, copy). |
| 10 | Move/resize an area | Space moves the rectangle while drawing; resize handles; Shift keeps aspect / draws squares | should | Space-move and Shift-square come free from `SelectionDrag`. Resize handles after placement: later. |
| 11 | Arrow-key cursor nudge | Arrows move the cursor 1 px, Shift+arrows 10 px; while placing a guide, arrows nudge the guide | must | Snapper's `nudgePointer` (warps the pointer). Steps are 1 pt / 10 pt, or 1 px / 10 px when the unit is pixels. |
| 12 | Crosshair mode | Hold Shift: full-screen horizontal and vertical lines through the pointer to check alignment of everything at once | should | Hold ⇧ (when not dragging) shows the lines; release hides. Very cheap. |
| 13 | Guides | Keys add a horizontal or vertical guide at the pointer (or a click-to-place guide mode); guides snap to edges and to area objects, center between other guides; labels show distance between guides and to the screen edges | should | H / V add a guide at the pointer, snapped to the nearest edge within a few points. Label the gap to neighbours. Drag to move, ⌫ removes the hovered one. |
| 14 | Snap toggles | Settings: snap distance tool to guides; to selected objects | skip | Always snap; ⌘ is the escape hatch. Fewer settings. |
| 15 | Tolerance (edge sensitivity) | Four levels (Zero, Low, Medium, High) with a slider per level in Settings; = / − change, T cycles; default level in the status menu and Settings | must (one good default) / should (= − keys) | Edge = color distance above a threshold. A fixed default that ignores anti-aliasing and JPEG noise; = and − step through 3–4 presets with a HUD-style badge showing the level. No per-level sliders. |
| 16 | Auto contrast | Measurement color adapts to what's under it | must | Draw lines and labels so they read on any background: a 1 px line with a contrasting halo, labels on a material badge (Snapper's `BadgeLayer`). No user colors. |
| 17 | Colors and theme | Overlay / guides / alternative colors pickable; ⌥ toggles to the alternative color; light/dark/system appearance for labels | skip | Accent color for lines + halo, system appearance for labels. Design system: no custom colors. |
| 18 | Units | Show/hide unit suffix; Retina interpretation: Points, Points (rounded), Screen pixels | must | Default **points** (rounded to whole points unless the edge is on a half point at 2×, then show .5). Option: **pixels** (backing pixels of that display). Unit suffix shown ("pt"/"px"), not optional. |
| 19 | Width/height indicators | Optional extra tick marks/arrows showing which span is width and which is height | skip | Our labels are placed on their line, which already says which is which. |
| 20 | Aspect ratio | Optional ratio in area and/or distance labels; formats: automatic, standard (16:9), reduced (1.77:1), common values only | later | Small add once labels exist. |
| 21 | Copy dimensions | Return copies; context menu item; format setting: "width, height" or "height, width", CSS (width or height first), SASS (width or height first); HUD "Dimensions Copied" | must | Return / ⌘C copies the hovered or last measurement. Formats (Settings): plain "120 × 44", CSS (`width: 120px; height: 44px;`), SwiftUI (`.frame(width: 120, height: 44)`). HUD "Copied". |
| 22 | Right-click context menu | On objects: copy, delete, screenshot, etc. ("easy access") | should | Context menu on an area/guide: Copy, Copy As ▸, Delete, Clear All, Take Screenshot. Doubles as the discoverable list of overlay keys. |
| 23 | Screenshot of measurements | S saves, C copies a screenshot (with measurements drawn) of the screen; ⌘S opens a "capture area" tool to screenshot a region; padding around the selection (slider; hold ⌥ to toggle); scale Retina to 1×; PNG/JPEG; export folder; sounds (five choices); notification text | later (owner: Snapper overlaps) | One action: "Copy Screenshot" (C) and "Save Screenshot" (S) of the area around all measurements (bounding box + padding), measurements drawn in. PNG, saved to the Desktop (or Snapper's folder). No sound choices (system screenshot sound only, or none). Area tool for screenshots: later (that's Snapper's job). |
| 24 | Screenshot app integration | Sends captures to CleanShot X (quick-access overlay, annotate, cloud) | later | Could hand off to Snapper (open its editor with the image). Needs a cross-app contract; not v1. |
| 25 | Design-tool integrations | Sketch plugin, Figma, Affinity (and formerly Adobe XD) read the app's zoom level so dimensions are in document units; needs Automation/Accessibility | skip (v1) | Fragile (Figma integration is fixed in many changelog entries), needs Automation/AX permissions, and XD support was dropped. A manual "scale" (e.g. ×0.5 for a 200% zoom) covers most of it: later. |
| 26 | Background mode | After measuring, the hotkey leaves measurements on screen (click-through) while you go back to work; hotkey again resumes | later | Needs a non-frozen, click-through overlay that tracks nothing; pinned measurements become stale when windows move. |
| 27 | Restore last session | Status menu item / auto-restore after quitting brings back the previous measurements | later | Cheap once measurements are a value type: persist the last session per display. |
| 28 | Disable hotkey in chosen apps | "Disable in Apps…" list in Shortcuts | skip | Rare; the user can rebind. |
| 29 | All in-overlay keys rebindable | Shortcuts tab lists every action (guides, hold distance, tolerance, screenshot, copy, color toggle, cursor nudges) with recorders; Restore Defaults | skip | Fixed, documented overlay keys (shown in the hint line and context menu). Only the global shortcut is rebindable. |
| 30 | Show/hide cursor | Setting to hide the system cursor while measuring | skip | We always show a precise crosshair; hiding it adds nothing. |
| 31 | Animations toggle | Setting | skip | Honor Reduce Motion instead. |
| 32 | Onboarding tour | Welcome window with a video per tool (distance, area, guides, crosshair, tolerance, screenshots, background mode, context menu); launch-at-login prompt; "Show Tutorial" in Settings | skip | Design system: no tours. The overlay's one-line hint shows the keys; the first run shows the hint for longer. |
| 33 | Language picker | In-app language override, 7 languages | skip | Use the system language. |
| 34 | Status item | Smaller icon option; hide icon (then launching the app twice opens Preferences) | must | `MenuBarExtra` (VoiceOver-pressable, unlike the original's). "Show in menu bar" in General; relaunch brings it back (SlopKit). |
| 35 | Touch Bar buttons | Add guides, tolerance popup | skip | Touch Bar is gone from current Macs. |
| 36 | Updates, license, Setapp | Sparkle updates, license manager, unlink device, Setapp contact-info prompt | skip | Not applicable. |
| 37 | Crash reporting | Bundles Sentry | skip | Design system: no telemetry. |
| 38 | Magnifier | Not a PixelSnap feature (xScope and Shottr have one) | should | Snapper already draws a loupe (`LoupeLayer`). A magnifier next to the pointer makes 1 pt edges checkable; show it while ⌥ is held or always (decide in build). |
| 39 | Physical units (cm / in) | Not supported; a Setapp review calls this a dealbreaker | later | `CGDisplayScreenSize` gives a physical size but it's unreliable for some external displays; offer as an opt-in unit with a calibrate step later. |
| 40 | Scale factor for zoomed designs | Done via per-app integrations only | later | A "×" scale in the menu (100%, 50%, 200%, custom) applied to readouts. |

## Key flows

### Flow 1: measure an element (the main job)
1. From any app, press the global shortcut (ours: ⌥⇧M). Or choose **Measure** from the
   menu bar menu.
2. Within one frame, a borderless overlay covers every display. The live screen is shown
   until each display's snapshot arrives (~50–100 ms), then the frozen image is swapped in.
   No dimming (unlike a screenshot tool: you're measuring, not selecting). Cursor becomes
   a crosshair.
3. A one-line hint sits at the bottom of the pointer's display: drag to measure an
   element, H/V guides, ⇧ crosshair, Return copy, Esc done.
4. Hover: two lines extend from the pointer to the nearest edges left/right and up/down,
   with a span label on each ("120 pt", "44 pt").
5. Drag a box loosely around a button and release: the box snaps inward to the button's
   bounds and shows "120 × 44 pt". ⌘-drag (or right-drag) keeps the box exactly as drawn.
   Space while dragging moves the box; ⇧ squares it.
6. Drag another box around a second element. Hovering in the gap between the two boxes
   measures the gap between their edges.
7. Return (or ⌘C) copies the hovered measurement, else the last one, in the chosen format.
   A small "Copied" HUD appears.
8. Esc: if a drag is in progress, cancels it; otherwise closes the overlay. Focus goes back
   to the app that was frontmost. Measurements are discarded (or kept for "restore", later).

### Flow 2: check alignment
1. Press the shortcut. Hold ⇧: full-screen horizontal and vertical lines through the
   pointer. Move along a row of icons: anything off the line is obvious. Release ⇧.
2. Press H to drop a horizontal guide at the pointer; it snaps to the nearest edge within a
   few points. Press V for a vertical guide. Arrows nudge the pointer 1 pt (⇧: 10 pt).
3. Guides show the distance to their neighbours (other guides or the screen edge).
4. Hover a guide and press ⌫ to remove it; ⌘⌫ clears everything.

### Flow 3: share a measurement
1. With measurements on screen, press C: a PNG of the region around all measurements
   (plus padding), with the lines and labels drawn in, is copied. HUD "Screenshot Copied".
2. Or press S: saved to the Desktop as PNG. HUD "Screenshot Saved" with the file name.
3. The overlay stays open, so you can keep measuring.

### Flow 4: first run / onboarding
1. Launch. The menu bar icon appears (a ruler symbol, outline). No window, no tour.
2. First press of the shortcut (or Measure): if Screen Recording is off, no overlay.
   Instead a small `PermissionGate` window: one sentence ("Ruler reads the pixels on screen
   to find edges, so it needs Screen Recording.") and "Open System Settings" (the exact
   pane). It re-checks live; when granted and macOS requires a relaunch, a Restart button.
3. Original for comparison: a multi-page welcome window with a video per tool, a
   launch-at-login question, and a modal alert explaining Screen Recording with a button
   to System Settings. Asking at the moment of need with one sentence is better.
4. Once granted, the first overlay shows the hint line for longer (until the first
   measurement), then normal.

### Flow 5: change units or copy format
1. Menu bar menu → **Units** ▸ Points / Pixels (checkmark), **Copy Format** ▸ Plain / CSS /
   SwiftUI. Both also in Settings › General. Takes effect on the next measurement.

## Settings inventory

From the Preferences nib (tabs in order: General, Screenshots, Tolerance, Appearance,
Integrations, Shortcuts, About). Defaults weren't readable without opening the window;
"likely" marks an educated guess from the option order and the app's defaults keys.

| Setting | Default | Options | Keep? |
|---|---|---|---|
| Start at login | off (onboarding asks) | checkbox | Yes: "Launch at login" (General). |
| Show menu bar icon | on | checkbox (smaller icon in older versions) | Yes: "Show in menu bar". |
| Language | System Default | 7 languages | No. |
| Display units | likely on | checkbox | No: always show units. |
| Retina interpretation | likely Points | Points, Points (rounded), Screen pixels | Yes: "Units" Points / Pixels. Points show .5 only when an edge truly sits on a half point. |
| Clipboard format | likely "width, height" | width, height; height, width; CSS (w/h first); SASS (w/h first) | Yes: Plain, CSS, SwiftUI. Width always first. |
| Freeze screen | likely off | checkbox | No: always frozen. |
| Distance tool: snap to guides / to selected objects | likely on | two checkboxes | No: always. |
| Aspect ratio in area / distance tool | likely off | two checkboxes + format popup (Automatic, Standard, Reduced, Only common values) | Later. |
| Display width/height indicators | likely off | checkbox | No. |
| Show cursor | likely on | checkbox | No. |
| Animations | on | checkbox | No (Reduce Motion). |
| Show tutorial | — | button | No. |
| Screenshots: export location | Desktop | Desktop / Other… | Later (Desktop in v1). |
| Screenshots: file format | likely PNG | PNG, JPEG | No: PNG. |
| Screenshots: padding | some padding (slider) | slider; hold ⌥ to toggle | Fixed padding (e.g. 24 pt); ⌥ while pressing C/S drops it. |
| Scale Retina screenshots to 1× | likely off | checkbox | Later. |
| Play sounds | likely on | checkbox (+ 5 bundled sounds) | No: no sound, the HUD is the feedback. |
| Default tolerance | likely Low or Medium | Zero, Low, Medium, High (+ slider per level) | Keep levels in the overlay (= / −), remembered; no sliders. |
| Auto contrast | likely on | checkbox | No: always. |
| Appearance | System Appearance | System, Light, Dark | No: follows system. |
| Overlay / Guides / Alternative colors | brand colors | color wells + restore | No: accent color + halo. |
| Integrations: CleanShot, Sketch, Figma, Affinity | off | Enable buttons; units must be points | No (later: Snapper hand-off). |
| Shortcuts: every action | see Menus | recorders, Restore Defaults, Disable in Apps… | Only the global shortcut. |
| About: version, acknowledgements, website, contact, license | — | — | `AboutView`. |

Our Settings (`SlopSettings`): **General** (Launch at login, Show in menu bar, Units,
Copy format), **Shortcuts** (Measure), **About**.

## Menus and shortcuts

**Original status menu** (from the nib): Activate… (license, hidden on Setapp) · Find
Dimensions · Clear All · Restore Last Session · Default Tolerance ▸ Zero / Low / Medium /
High · Preferences… · Check for Updates… · About PixelSnap… · Quit. Left-click opens the
menu, right-click starts measuring. No main menu (agent app).

**Original overlay keys** (from onboarding strings and a third-party list; rebindable,
defaults not verified): global hotkey (one write-up lists ⌃⌥⌘P); single letters for hold
horizontal / vertical distance and add horizontal / vertical guide (H / V family, ⇧H / ⇧V
for a click-to-place guide mode); = / − tolerance up/down, T cycles; Return copy
dimensions; S save screenshot, C copy screenshot, ⌘S open screenshot area tool; ⌥ toggle
color; hold ⇧ crosshair; arrows 1 px, ⇧ arrows 10 px; Esc cancel; Space move rectangle;
⌘ disables snapping; right-drag area without snapping; ⌫ deletes; the hotkey again enters
background mode.

**Ours, menu bar menu** (`.menu` style):
- Measure  ⌥⇧M (global)
- Restore Last Measurements (later)
- —
- Units ▸ Points / Pixels
- Copy Format ▸ Plain / CSS / SwiftUI
- —
- `MenuFooter`: Settings… ⌘, · About Ruler · Quit Ruler ⌘Q

Default global shortcut **⌥⇧M** ("measure"). Taken in Slopapp already: ⌥⇧V Clips,
⌥⇧C Dropper, ⌥⇧⌘3/4/5 Snapper. (⌥⇧M types "Â" on a US layout; same trade-off Clips and
Dropper made.)

**Ours, in the overlay** (fixed; listed in the hint line and the context menu):

| Key | Action |
|---|---|
| drag | Measure an element (snaps to bounds) |
| ⌘-drag / right-drag | Free box, no snapping |
| Space (while dragging) | Move the box |
| ⇧ (while dragging) | Square |
| ⌥ (while dragging) | Grow from center (same as Snapper) |
| hold ⇧ (not dragging) | Crosshair lines |
| H / V | Add horizontal / vertical guide at the pointer |
| P | Pin the current hover distance |
| = / − | Edge sensitivity up / down (badge shows level) |
| Return / ⌘C | Copy hovered or last measurement |
| C / S | Copy / save screenshot of the measurements (⌥: no padding). **Later**; built instead: click = element, U units, Z magnifier, ⌘Z undo |
| ⌫ / ⌘⌫ | Delete hovered item / clear all |
| arrows, ⇧ arrows | Move pointer 1 / 10 (pt or px) |
| Esc | Cancel drag, else close |
| ⌥⇧M | Close (same as Esc) |

## Permissions and system integration

- **Screen Recording: required.** Edge detection reads pixels. PixelSnap shows a modal
  alert ("needs Screen Recording", button to System Settings), plus a note that the app
  must be in /Applications. Ours: `PermissionGate` on first use, live re-check, Restart
  button only if macOS needs it. If denied: Measure shows the gate again; nothing crashes.
- **Accessibility** (original: asked for, apparently for design-tool zoom reading and
  cursor control): **not needed** for us. Pointer warping (`CGWarpMouseCursorPosition`)
  works without it, as in Snapper.
- **Automation** (original: Adobe XD/Sketch integration): not needed.
- Login item: `SlopKit` launch-at-login.
- No URL scheme in the original. We could add `ruler://measure` later for Shortcuts users;
  an App Intent "Start Measuring" later.
- **Test mode** (ours, must): a generated test scene window and Snapper's
  `CaptureExclusions.onlyWindows` + `PrivacyMask`, so scripted and blind tests can only
  ever see the test pattern, never the owner's screen. The test scene should contain known
  rectangles (solid, gradient, shadowed, anti-aliased text, 0.5 pt hairline) at known sizes
  so edge detection is checkable to the point.

## Reuse from Snapper

Snapper's `Capture/` is written to move to SlopKit for Dropper, Ruler and Snip. Ruler
needs, as is: `ScreenCaptureKitCapturer.snapshot` (per-display, best resolution, our own
windows excluded, privacy mask in test mode), `OverlayPanel` (per-display borderless key
panel, all Spaces, full-screen aux), `ScreenCoordinates` (AppKit/Quartz/pixel conversions),
`SelectionDrag`/`SelectionGeometry` (drag, square, from-center, Space-move, nudge, label
placement), `LoupeLayer` and `BadgeLayer`, and the "show panels now, swap the frozen image
in when it arrives" sequence. Ruler-specific: an `EdgeDetector` in a Core target (pure,
testable: takes a pixel buffer + scale, answers "span at point" and "bounds within rect"
for a tolerance) and a measurement model (areas, pins, guides as values in screen-local
points). Moving `Capture/` into SlopKit first is the right first build task.

## UX patterns worth adopting

- **Freeze, then measure the freeze.** What you see is exactly what's measured, and it
  lets you measure things that vanish on focus change (menus, hover states, tooltips).
- **Loose drag, exact result.** You don't need to hit the edge; drag roughly around the
  element and the box shrinks to its true bounds. This is the whole product.
- **Hover measures without clicking.** The most common question ("how big is this gap")
  is answered by just pointing.
- **Escape hatches are modifiers, not modes.** ⌘ turns snapping off only while held,
  ⇧ shows the crosshair only while held. No state to forget.
- **Measurements accumulate.** Several boxes on screen at once, and gaps between them are
  measurable. Comparing is the real job, not single numbers.
- **Copy in the format you'll paste.** One key, and the clipboard holds CSS or code.
- **Sensitivity is a key away.** When a shadow or gradient fools the edge finder, = / −
  fixes it in place instead of in a settings window.
- **The screenshot includes the measurement.** Sharing a finding is one key.

## What we won't copy, and what we'll do better

- **Not copying:** name, icon, the welcome video tour, colors, label styling, sounds,
  wording, license/upsell flows, its integrations' plumbing.
- **Doing better:**
  - **The menu bar icon works with VoiceOver and keyboard.** PixelSnap's status item
    crashed when pressed through Accessibility; `MenuBarExtra` doesn't have that problem.
  - **Never lock up the Mac.** A recent Setapp review reports 2.6.4 freezing the whole
    Mac with Force Quit unusable. Our overlay sits above everything, so: edge detection
    stays off the main thread when it's heavy (precompute luminance once per snapshot),
    Esc and the global shortcut always close it, and a watchdog closes the overlay if the
    main thread stalls (or simply: overlay panels never outlive a stalled frame for more
    than a couple of seconds). Test this explicitly.
  - **Points vs pixels is explicit.** Labels always carry the unit; on a mixed setup
    (Retina laptop + 1× external) each display uses its own scale, and pixel mode says so.
  - **Fewer settings, better defaults.** PixelSnap has ~30 preferences across 7 tabs
    (colors, sounds, per-tool snap toggles, cursor, animations, language). We ship ~4.
  - **Readable on anything without color settings.** Haloed lines and material label
    badges instead of three user-picked colors.
  - **Copy formats people paste today:** SwiftUI next to CSS, instead of SASS and
    height-first variants.
  - **A magnifier** for 1 pt work (PixelSnap has none; xScope and Shottr do).
  - **No nags, accounts, crash reporter or update framework.** (Reviews mention a
    persistent Setapp contact prompt; the app bundles Sentry.)
  - **Physical units** (later): the one functional complaint in the Setapp reviews.

## Edge cases

- **Multiple displays** with different scales (2× laptop, 1× external): one overlay per
  display, each with its own snapshot and scale; measurements can't span displays (labels
  say so if a drag crosses the edge: clamp to the start display, like Snapper). Hot-plugging
  a display while the overlay is up: close the overlay.
- **Scaled resolutions** ("More Space"): the backing scale is still 2× but the panel is
  downsampled; "pixels" means backing pixels, not panel pixels. Document it in the unit
  help text.
- **Half-point edges** on 2× (hairlines, 0.5 pt borders): points mode shows "0.5 pt"
  rather than rounding to 0 or 1.
- **Anti-aliasing, gradients, shadows, blur/vibrancy, JPEG noise**: default tolerance must
  ignore 1-px AA fringes; shadows usually need higher sensitivity to include or lower to
  exclude. Test scene covers each.
- **Uniform area** (drag over empty space): no edge found, keep the box as drawn and say
  nothing; don't shrink to zero.
- **Hover with no edge in a direction**: line runs to the screen edge and the label says
  so (span to the screen edge is still useful).
- **Tiny elements** (1–3 pt): snapping must not collapse them; the magnifier helps.
- **Menu bar, notch, Dock**: measurable (they're on the frozen image); labels avoid the
  notch area (PixelSnap fixed "labels below the notch" in 2.6).
- **Full-screen Spaces and Stage Manager**: overlay joins all Spaces; measures the
  visible Space.
- **Dark/light**: labels on material, lines haloed; check both on white, black, mid-gray,
  photo backgrounds.
- **Screen Recording revoked mid-use**: the next snapshot fails → close overlay, show the
  gate. Never show an overlay with no image and pretend to measure.
- **Sleep/wake, screen lock while the overlay is up**: close it.
- **Our own windows**: never measured (excluded from the snapshot), except the test scene
  in test mode.
- **Very large displays** (6K, 2–3 displays): snapshot memory is tens of MB per display;
  release on close (Snapper does). Edge scans stay O(width + height) per move.
- **Pointer nudging off-screen**: refuse, like Snapper.
- **Hotkey pressed while overlay is up**: closes it (no second overlay).
- **Accessibility**: VoiceOver announces each new measurement ("120 by 44 points") via
  accessibility notifications; every overlay action also in the context menu; Reduce
  Motion: no animated line growth.
- **Non-English**: labels are numbers + units; use `Measurement`/number formatting with
  the locale's decimal separator for ".5".

## Our v1 scope

- [x] Global shortcut (⌥⇧M, rebindable) and menu item "Measure" open the overlay on every
      display; pressing again or Esc closes; focus returns to the previous app
- [x] Frozen snapshot per display (SlopKit capture), overlay visible within one
      frame, frozen image swapped in when ready; our windows excluded
- [x] Hover distance: horizontal and vertical spans from the pointer to the nearest edges,
      labeled with units
- [x] Drag to measure: box snaps inward to the element's bounds, W × H label; ⌘-drag /
      right-drag keeps the box as drawn; Space moves, ⇧ squares
- [x] Multiple areas on screen; hover between areas measures the gap; ⌫ deletes hovered,
      ⌘⌫ clears all
- [x] Return / ⌘C copies the hovered or last measurement in the chosen format (Plain, CSS,
      SwiftUI) with a "Copied" HUD
- [x] Units: points (default, .5 where real) or pixels, per-display scale; in the menu and
      Settings
- [x] Arrow keys nudge the pointer 1 / 10
- [x] One good default edge tolerance (anti-aliasing ignored), verified on the test scene
- [x] Readable lines and labels on any background (halo + dark badge), light and dark
- [x] One-line hint with the keys; right-click context menu listing the actions
- [x] Screen Recording permission window on first use; revoked mid-use handled (snapshot
      failure closes the overlay and shows the window; not exercised live, needs revoking
      the grant)
- [x] Test mode: test scene + `onlyWindows` privacy mask, never the owner's screen
- [x] Menu bar menu (Measure, Units, Copy Format, footer) and Settings (General,
      Shortcuts, About)
- [x] Perf: shortcut → overlay < 100 ms, hover readout updates every frame on a 6K
      display, idle budgets from the design system

Should (v1 if cheap): crosshair (hold ⇧) **built**, guides (H/V) with gap labels **built**,
pin (P) **built**, tolerance = / − **built**, magnifier (Z) **built**, copy/save screenshot
of measurements (C/S) **later** (owner decision).

## Decisions

Owner defaults (2026-11-03), and calls made while building:

1. **Shared capture code first:** done before this build. Snapper's capture code is in
   SlopKit `Capture/`, and Ruler uses it unchanged (`ScreenCaptureKitCapturer`,
   `CaptureExclusions.onlyWindows` + `PrivacyMask`, `FrozenDisplay`, `ScreenCoordinates`,
   `SelectionDrag`/`SelectionGeometry`, `BadgeLayer`, `LoupeLayer`). SlopKit wasn't modified.
2. **Default shortcut ⌥⇧M**, rebindable in Settings › Shortcuts.
3. **Screenshots of measurements (C/S): later.** Snapper overlaps; C and S are left free.
4. **Guides: should, built** (H/V, snapped to an edge within 4 pt, gap labels between
   neighbouring guides, hover stops at guides, ⌫ deletes the hovered one). Dragging guides
   is later.
5. **Physical units: later.**
6. **Own overlay, not `RegionOverlay`.** SlopKit's `RegionOverlay` is a pick-one-area
   session that ends on release; Ruler needs a long-lived session with many measurements,
   so it has its own panels (`MeasureOverlay`/`MeasureView`) built from the same SlopKit
   pieces. The panel level is just below pop-up menus (not `.screenSaver`), so the
   right-click menu shows above the overlay. It still covers the menu bar and Dock.
7. **Edge rule: neighbouring-pixel difference**, not difference from a reference color.
   Gradients and soft shadows then don't stop a measurement, and hover and box snapping
   follow the same rule. Box snapping first used a flood fill from the border, but it
   leaked into a white card on a near-white background through the card's faint shadow
   corners, so it now shrinks each side inward to the first edge. When the box cuts an
   element (only one edge on an axis), the part on the element's side is kept.
8. **Tolerance levels:** Strict 3, Fine 8, Normal 20 (default), Loose 56. A threshold of 0
   is useless on real captures: flat fills vary by 1–2 levels. Levels are remembered.
9. **Decode in the capture's own color space.** Converting the captured image to sRGB
   dithered flat saturated fills by up to 13 levels in 16 pt tiles, which broke Fine. In the
   display's own color space the noise is ≤ 2.
10. **Pixels go in mmap'd memory**, released on close. With malloc arrays, ~86 MB (5K + Retina
    laptop) stayed resident after closing (malloc's freed large blocks). Now the footprint
    returns to ~45 MB.
11. **Click = measure the element under the pointer** (the edge-to-edge box around it),
    alongside drag. That makes a button's size one click, and keyboard + click enough to
    measure.
12. **Copy target:** hovered area or pin, else the last one placed, else the live hover
    distance. Plain format has no unit and uses the locale's decimal separator. CSS and
    SwiftUI always use ".".
13. **Hint line always visible** at the bottom (moves to the top when the pointer nears it,
    hidden while dragging). There's no first-run variant: simpler, and always discoverable.
14. **Toasts inside the overlay** (SlopKit's `HUD` sits at status-bar level, under the
    overlay). They're also announced to VoiceOver. The overlay's accessibility value carries
    the live readout.
15. **Magnifier off by default** (Z toggles it, remembered; also in Settings). An
    always-on loupe hides labels near the pointer.
16. **"to edge"** is added to a span label when exactly one end is the display edge.
17. No watchdog thread: heavy work (decode, box snapping) runs off the main thread, and
    hover is ~17 µs at 5K, so the main thread never stalls. Esc and ⌥⇧M always close, and
    so do sleep, screen lock, session switch and display changes.

## Build notes (2026-11-03)

- **Tests:** 44 Swift Testing tests in RulerCore (hover spans, element bounds incl. soft
  shadows, white-on-near-white cards, gradients, cut boxes, AA fringes, tiny elements;
  units, .5 points, locales, copy formats, nudge steps; board limits, hit testing, guides,
  undo; test-scene layout). `scripts/check.sh Ruler --perf` green.
- **Real-capture self-check** (`RULER_TEST_HOOKS` `selfcheck`, on the real ScreenCaptureKit
  freeze of the test scene, 5K display at 2×): all 13 exact shapes measure exactly by
  hover and by box snapping at Normal and Fine, including 100.5 × 50.5 pt, the
  300 × 0.5 pt hairline, 2 × 2 and 1 × 1 pt squares, the 1 pt outline, the rounded rect,
  the gradient strip, the shadowed white card and the box on a dark panel. Strict is exact
  too. Loose misses only the shadowed white card, as intended.
- **Perf:** launch 153 ms, status item 319 ms, idle CPU 0.004%, idle footprint 23 MB.
  Shortcut → overlay on screen 17–34 ms (2 displays). Frozen image ready ~180–300 ms
  (ScreenCaptureKit, 5K + 3456×2234, sequential in SlopKit's snapshot), pixels decoded
  +15–65 ms. Hover 16.5 µs per update on a 5K image (release). Box snap: 0.2–3 ms
  typical, whole 5K display 37 ms (off the main thread). Footprint while measuring ~215 MB
  on 5K + Retina, back to ~45 MB after closing.
- **Walkthrough** (release build, test mode, `--direct`): menu (Measure, Units, Copy
  Format, footer), Measure from the menu, ⌥⇧M opens and closes, Esc closes and focus
  returns, hover labels, drag snapping with the real mouse, click-to-measure, gap between
  areas, pin, guides with gap labels, magnifier, tolerance keys, units key, undo, clear,
  copy in Plain/CSS/SwiftUI (pasteboard checked), pixels mode (69.5 pt → 139 px), arrow
  and ⇧arrow nudge (cursor moved exactly 1 and 10 pt), the right-click menu above the
  overlay, Settings (General, Shortcuts, About), no-permission launch → permission
  window (Esc closes), light and dark. `scripts/drive tree` shows no `[unlabeled]`.
  Screenshots in `/tmp/ruler-test/` (test mode only).
- **Gotcha for testers:** `scripts/drive key Ruler opt+shift+m --global` left ⌥⇧ marked
  as held system-wide once (the hotkey swallows the key, and the modifier release went
  missing), so the next drag was squared and from-center. Prefer the menu item or the
  `measure` hook. If the global key is used, check that drags aren't squared.
- **Design checklist (§10):** 1 pass (one shortcut). 2 pass (system controls, accent
  color, dark badges from SlopKit; the test scene uses fixed colors on purpose). 3 pass
  (every overlay action is in the right-click menu with its key; Measure in the menu bar
  menu). 4 pass. 5 pass. 6 pass. 7 n/a (no empty states; the overlay hint explains
  itself). 8 pass. 9 pass (nothing destructive; ⌘Z undo in the overlay). 10 pass (no
  network code). 11 pass. 12 pass. 13 pass (no movement animations, only a toast fade).
  14 pass (Settings remember; the overlay is per session by design).

## Sources

- [PixelSnap website](https://pixelsnap.com/) (features, integrations)
- [PixelSnap changelog](https://pixelsnap.com/changelog) (1.0 → 2.6.4: modifiers, guides,
  tolerance, screenshot padding, background mode, restore session)
- [Setapp listing](https://setapp.com/apps/pixelsnap) and
  [Setapp customer reviews](https://setapp.com/apps/pixelsnap/customer-reviews)
  (99% of 1,503; freeze complaint on 2.6.4, no real-world units, contact-info nag)
- [Alchemists: PixelSnap](https://alchemists.io/articles/pixel_snap) (overlay key list)
- [The Sweet Bits review](https://thesweetbits.com/tools/pixelsnap-app/)
- [MacMagazine article](https://macmagazine.com.br/post/2021/01/20/todo-designer-precisa-ter-o-pixelsnap-instalado-no-mac/)
- [AlternativeTo: PixelSnap](https://alternativeto.net/software/pixelsnap/about) and
  [alternatives](https://alternativeto.net/software/pixelsnap) (Shottr, xScope, Meazure)
- [Sowiks screenshot app comparison](https://sowiks.com/blog/best-screenshot-apps-for-mac)
  (Shottr's built-in ruler)
- [Affinity forum: screen measurement apps](https://forum.affinity.serif.com/index.php?%2Ftopic%2F145106-need-screen-measurement-apps-for-macos%2F=)
- [Product Hunt: PixelSnap](https://www.producthunt.com/products/pixelsnap/reviews)
- Installed PixelSnap 2.6.4: bundle strings, status menu and Preferences nibs,
  Info.plist (read-only)

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.
