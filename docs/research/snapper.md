# Snapper research (inspired by CleanShot X)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied on
> 2026-11-02: **CleanShot X 5.0.2** (Setapp build, /Applications/Setapp/CleanShot X.app,
> already running as the owner's daily screenshot tool) read-only, plus cleanshot.com's
> feature page and third-party shortcut guides and reviews. We study how it works so we don't
> reinvent the wheel. We never copy its name, icons, artwork, wording, sounds or signature
> visuals.
>
> What was looked at: the status item menu (opened and closed), and the Settings window's
> General, Shortcuts, Quick Access, Screenshots, Annotate and Advanced panes (sidebar rows
> clicked to switch panes; nothing toggled). The Settings window was closed afterwards; the
> app was left running. **Not opened**: Capture History, any quick-access overlay, any past
> capture, the save folder. No CleanShot hotkey was pressed.

## The job

Someone needs a picture of part of their screen, right now, usually to show it to someone
else: a bug in a ticket, a UI detail in Slack, a step in a how-to. They want the exact
region, maybe a red arrow or a blurred email address on it, and then they want it *somewhere*:
on the clipboard, in a chat, in a folder, or floating next to their work as a reference. Done
feels like: shortcut, drag, it's already in the corner waiting to be pasted or dragged.
**The one interaction that matters: press a shortcut → drag a box → a thumbnail appears in
the corner → copy it, drag it into a chat, or annotate it.**

## Who and when

- Reporting a bug or showing a UI state (area or window capture → arrow + text → paste in a ticket).
- Sharing a snippet of a document/website with a colleague (area → copy → paste in chat).
- Redacting before sharing (area → pixelate the email/name → copy).
- Keeping a reference on screen while working (area → pin → it floats above the editor).
- Writing docs/tutorials (window capture with shadow, step counters 1-2-3).

Frequency: many times a day for heavy users (the owner uses it daily); each use is 2–30 s.

## Feature inventory

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Area capture | Global hotkey (⇧⌘4 in the owner's setup, replacing macOS's), crosshair over the whole screen, drag a box, capture on release | must | Frozen-screen overlay, magnifier, size readout, Esc cancels |
| 2 | Window capture | Menu item / hotkey; in area mode Space switches to window picking ("Select Window ␣" in Shortcuts) | must | Space toggles window mode; captures the window alone with shadow |
| 3 | Full-screen capture | ⇧⌘3 | must | Screen under the pointer |
| 4 | Capture previous area | Menu item, no default shortcut | should | Cheap: remember the last rect |
| 5 | All-In-One mode | ⇧⌘5, a mode picker with remembered selection | later | v1 has per-mode shortcuts; the menu is the picker |
| 6 | Self-timer | Menu + 5 s default interval | later | |
| 7 | Scrolling capture | Menu | later (v2) | Roadmap v2 |
| 8 | Text capture (OCR) | ⇧⌘2 | later (v2) | Roadmap v2 (Vision) |
| 9 | Screen recording / GIF | Menu, many recording settings | later (v2) | Roadmap v2 |
| 10 | Hide desktop icons | Menu toggle + "Hide desktop icons while capturing" (on); can use a custom wallpaper | should | We leave out Finder's desktop-icon windows from our captures, so the icons never show up in a capture. Nothing on the Mac changes, so there's nothing to restore. |
| 11 | Magnifier / crosshair | Screenshots → Crosshair Mode (disabled by default), Show magnifier | must | Magnifier on by default (the brief asks for it). It reads from the frozen image, so it's cheap. |
| 12 | Freeze screen | Off by default | must (always on) | We always freeze. Magnifier and capture both read the same frozen image, so the capture is exactly what you saw, and it's instant. |
| 13 | Quick Access Overlay | After every capture, a thumbnail card in a screen corner (Left by default, "Move to active screen", size slider) with Copy, Save, Annotate, Pin, Close, drag-out | must | Bottom corner of the screen the capture came from, left or right |
| 14 | Overlay auto-close | Off by default; action "Save and Close"; interval 30 s | must | Never / 10 s / 30 s / 1 min / 5 min; action Close or Save and Close; pauses while hovered |
| 15 | Close after dragging | On (⌥ keeps it) | should | On |
| 16 | Save button behavior | Save to Export location (⌥ = choose) | must | Save goes to the save folder; ⌥-click Save As… |
| 17 | Restore last capture | Shortcut slot "Restore Last Capture" | should | "Reopen Last Capture" in the menu, so closing a card never loses a capture |
| 18 | After-capture actions | Matrix: Show overlay (on), Copy (off), Save (off), Upload, Annotate, Pin | must | Show thumbnail (on), Copy to clipboard (off), Save to folder (off) |
| 19 | Export location | Desktop by default; Choose… | must | macOS's own screenshot folder if set, else Desktop; Choose…; `SNAPPER_SAVE_DIR` override for tests |
| 20 | File format | PNG default (JPEG etc.) | should | PNG / JPEG |
| 21 | Retina 1x, @2x suffix, sRGB, 1 px border | Options | later | Kept out of v1 to stay small |
| 22 | Window shadow / background | Capture window shadow (on), wallpaper or transparent background | should | Shadow toggle (on); backgrounds later |
| 23 | Shutter sound | Play sounds (on), Shutter sound System Default | should | macOS's screen capture sound, on by default |
| 24 | Annotate: arrow, line, rect, filled rect, ellipse, pencil, highlighter, text, counter, pixelate/blur (redaction), spotlight, crop, background tool | Single-letter tool keys (A, L, R, F, E, D, M, T, C, P, H, K, B) | must (arrow, line, rect, ellipse, text, highlighter, pixelate, blur, counter, crop) / later (pencil, spotlight, background, filled rect) | Our letters: V select, A arrow, L line, R rect, O ellipse, T text, H highlighter, P pixelate, B blur, N counter, C crop |
| 25 | Annotate: colors, stroke width, undo/redo, = / − to resize the tool | | must | 8 colors, 3 widths, ⌘Z/⇧⌘Z |
| 26 | Annotate: copy ⇧⌘C, save ⌘S, save as ⇧⌘S, print ⌘P, pin, share/upload ⌘U | | must (copy/save/save as/share/pin) | Print later |
| 27 | Annotate: select, move, resize, delete, duplicate objects | | must (select/move/delete), should (resize handles) | |
| 28 | Annotate: shadow on objects (on), smooth drawing, always on top, Dock icon (on) | Settings → Annotate | should | Dock icon + menu bar while an editor is open (the menus need it) |
| 29 | Pin to the screen | From overlay, menu "Pin to the Screen…" (choose file), "Pin Last Screenshot" | must | Floating, always on top, resizable, opacity, arrow keys move, Esc closes |
| 30 | Pin options | Rounded corners, shadow, border (all on); lock mode (click-through) | should | Rounded + shadow + hairline border; lock later |
| 31 | Capture history | Advanced → Keep history 3 days | skip | Privacy: we keep nothing past the session |
| 32 | Cloud upload | Sign-in, upload & copy link | skip | No network, no accounts |
| 33 | URL scheme API, Raycast integration | Advanced | later | |
| 34 | Ask for name after capture, file name template | Advanced | later | Fixed template "Screenshot <date> at <time>" |
| 35 | Open file / open from clipboard in Annotate | Shortcuts slots | should | "Annotate Clipboard Image" / "Pin Clipboard Image" are cheap |

## Key flows

### Flow 1: capture an area (the main job)
1. Press the hotkey. The screen dims slightly and the pointer turns into a crosshair; a loupe
   next to it shows the pixels under it.
2. Drag. The selection is clear, everything else stays dimmed, and a readout shows W × H.
   Shift makes it square, Option grows it from the center, holding Space moves it.
3. Release. A short shutter sound; the capture shows up as a thumbnail card in the bottom
   corner. Esc at any point cancels.
4. On the card: Copy, Save, Annotate, Pin, Close, or drag it straight into another app.

### Flow 2: capture a window
1. Window hotkey (or Space during area mode). Moving the pointer highlights the window under it.
2. Click: the window is captured on its own, with its shadow and a transparent background,
   even if part of it was covered.

### Flow 3: annotate
1. Annotate on the card (or after-capture setting). A window opens with the capture, a toolbar
   of tools, colors and widths.
2. Pick a tool by click or letter; drag on the image. Click an object to select/move it, Delete
   removes it. ⌘Z/⇧⌘Z.
3. Copy (⇧⌘C), Save (⌘S), Share, Pin. Closing keeps the edits on the capture.

### Flow 4: pin
1. Pin on the card. The capture floats above all windows at its real size.
2. Drag to move, drag edges or scroll/pinch to resize, arrow keys nudge, 1–9/0 set opacity,
   right-click for Copy/Save/Annotate/Opacity/Close, Esc closes.

### Flow 5: first run
1. Menu bar icon appears. First capture without Screen Recording permission: a small window
   explains why and links to the exact Privacy pane (no capture, no crash).
2. After granting, macOS needs a restart of the app; the window offers Restart.

## Settings inventory (CleanShot, as seen)

| Pane | Setting | Value seen | Keep? |
|---|---|---|---|
| General | Launch at login / Show menu bar icon | on / on | yes (SlopSettings) |
| | Hide desktop icons while capturing | on | yes (on) |
| | Play sounds / Shutter sound | on / System Default | yes (on) |
| | Export location | Desktop (+ Choose…) | yes |
| | After capture matrix (Show overlay / Copy / Save / Upload / Annotate / Pin) | overlay on, rest off | Show / Copy / Save |
| Quick Access | Position on screen | Left | yes (Left/Right) |
| | Move to active screen / Overlay size | on / slider | screen of the capture; fixed size |
| | Auto-close (+ action, interval) | off (Save and Close, 30 s) | yes |
| | Close after dragging | on | yes |
| | Save button behavior | Save to Export location | yes, ⌥ for Save As… |
| Screenshots | File format / sRGB / Retina 1x / 1 px border / Background preset | PNG / on / off / off / None | PNG/JPEG only |
| | Self-timer / show cursor / freeze screen | 5 s / off / off | freeze always |
| | Window background / capture window shadow | wallpaper or transparent / on | shadow toggle |
| | Crosshair mode / magnifier | Disabled / on | magnifier toggle (on) |
| Annotate | Inverse arrow, smooth drawing, remember background, draw shadow, expand canvas, always on top, Dock icon, color names | various | later |
| Advanced | Ask for name, file name format, @2x suffix, copy mode, history, OCR, All-In-One memory, pin corners/shadow/border, URL API | various | later/skip |

## Menus and shortcuts

CleanShot status item menu: All-In-One ⇧⌘5, Capture Area ⇧⌘4, Capture Previous Area, Capture
Fullscreen ⇧⌘3, Capture Window, Scrolling Capture, Self-Timer, Capture Text (OCR) ⇧⌘2, Record
Screen │ Hide Desktop Icons │ Open…, Pin to the Screen… │ Capture History… │ About, Settings… ⌘,,
Quit.

The owner has **disabled macOS's own screenshot shortcuts** (symbolic hotkeys 28–31, 184) so
CleanShot owns ⇧⌘3/4/5 and ⇧⌘2. On a stock Mac, macOS owns ⇧⌘3/4/5 and ⌃⇧⌘3/4 (copy to
clipboard).

**Our defaults (decision):** ⌥⇧⌘4 Capture Area, ⌥⇧⌘5 Capture Window, ⌥⇧⌘3 Capture Full
Screen; Capture Previous Area unset. Why: they keep the familiar "3/4/5" digits and
don't collide with CleanShot (⇧⌘2–5), macOS defaults (⇧⌘3/4/5, ⌃⇧⌘3/4, which the brief's
⌃⇧⌘ suggestion would hit on a stock Mac), or typing (⌥⇧+digit types characters, ⌘ prevents
that). All rebindable in Settings → Shortcuts.

## Permissions and system integration

- Screen Recording (TCC) for every capture. CleanShot asks on first capture. Without it,
  ScreenCaptureKit returns only the wallpaper/our own windows or throws.
- No Accessibility needed (window list comes from CGWindowList, which gives frames without it).
- Launch at login (SMAppService via SlopKit).

## UX patterns worth adopting

- The capture is never "gone": thumbnail first, decide later; closing can be undone.
- Single-letter tool keys in the editor; the same tool keys every time.
- Space = window mode during area selection; Esc always backs out.
- Pins behave like sticky notes: drag, resize, fade, Esc.
- The thumbnail lives in the corner of the screen where you captured.

## What we won't copy, and what we'll do better

- Not copying: name, icon, artwork, wording, sounds (we use macOS's own capture sound),
  overlay look, cloud/upsells.
- Better: frozen screen by default (WYSIWYG, instant), desktop icons hidden *without*
  touching Finder, no history kept on disk (temporary files deleted on quit), every
  card/editor/pin action also in menus with shortcuts, no network ever.

## Edge cases

- Multiple displays with different scales: one overlay per display; a selection stays on
  the display where it started; pixel math per display.
- Selection smaller than 3×3 pt: treated as a click, not a capture.
- Retina: images at native pixels; annotation widths scale with the image's scale.
- Permission revoked mid-session: the next capture shows the permission window.
- Full-screen Spaces: overlay and cards join all spaces (`.fullScreenAuxiliary`).
- Huge captures (5K full screen): encode off the main thread; release frozen images when the
  overlay closes so idle memory returns to baseline.
- Editor closed with unsaved edits: edits go back to the capture (card or "last capture").
- Save folder missing or not writable: error HUD with what to do; falls back to nothing.
- Name collisions in the save folder: "… 2.png".

## Our v1 scope

- [x] Area capture on a global shortcut with frozen overlay, magnifier, W × H readout, Shift/Option/Space-move, arrow nudge, Esc cancels
- [x] Window capture (Space toggles; hotkey opens straight into window mode), with shadow option
- [x] Full-screen capture of the screen under the pointer
- [x] Capture previous area
- [x] Quick-access card: Copy, Save (⌥ Save As…), Annotate, Pin, Close, drag-out; stacks; auto-close setting; Reopen Last Capture
- [x] After-capture settings: show card / copy / save
- [x] Save folder setting + `SNAPPER_SAVE_DIR`; PNG/JPEG
- [x] Annotation editor: select/move/resize/delete, arrow, line, rect, ellipse, text, highlighter, pixelate, blur, counter, crop, undo/redo, colors, widths, copy/save/save as/share/pin
- [x] Pins: floating, always on top, resizable (keeps aspect), opacity, arrow keys, context menu, Esc closes, Close All Pins
- [x] Desktop icons left out of captures (setting, on)
- [x] Permission window when Screen Recording is missing (no crash)
- [x] Menu bar menu with every action + Settings (General, Shortcuts, Advanced, About)
- [x] Perf: hotkey → overlay < 100 ms; capture → thumbnail < 300 ms; idle budgets

## Open questions

None blocking. Decisions are recorded below instead of asking the sleeping owner.

## Decisions (build step, 2026-11-02)

| Decision | Why |
|---|---|
| Default shortcuts ⌥⇧⌘3/4/5 | See "Menus and shortcuts". |
| Always freeze the screen | The magnifier and the capture read the same frozen image, so the capture is exactly what you saw and takes no extra time. The overlay appears right away (dimming the live screen) and swaps in the frozen image when it arrives (~50–100 ms). |
| Captures leave out our own cards and overlay but include pins | Pins are content the user put on screen on purpose; cards are UI. |
| Hide desktop icons = exclude Finder's desktop-level windows from the capture filter | Same result in every capture, with no change to Finder prefs, so nothing to restore and nothing to go wrong. |
| Full-screen captures the display under the pointer | Simple and predictable; one image. |
| Readout shows points (W × H pt), the image is saved at native pixels | Matches what macOS shows; points are what people reason about. |
| Card doesn't take keyboard focus | It lingers up to minutes; stealing keys from the app you're typing in is worse than needing a click. Card actions are also in the menu bar menu ("Last Capture" section). |
| Copy and Save close the card; Annotate and Pin hand the capture over | Same as macOS's own thumbnail; Reopen Last Capture undoes a close. |
| Editor makes Snapper a regular app (Dock icon + menu bar) while open | An `LSUIElement` app has no visible menu bar, and the design system wants every action in a menu. |
| Editor tools/colors as menu items without single-key equivalents; the canvas handles the letters | Bare-letter menu key equivalents would also fire while typing a text annotation or in any text field. Menu titles show the letter, e.g. "Arrow  (A)", and toolbar tooltips do too. |
| Window captures: shadowless capture + our own drawn shadow | ScreenCaptureKit's "include shadow" squeezes window + shadow into the window's size (blurry, wrong pixels). Capturing the bare window at its exact size and drawing a soft shadow on a transparent margin keeps the window pixel-perfect. |
| Pixelate block = max(10 pt, ⅕ of the box's short side) | Fixed 10 pt blocks left big headline text guessable. |
| Annotation colors are fixed sRGB values | They're image content, not UI chrome; they must look the same in light and dark and in the saved file. |
| No history on disk | Privacy. Temporary files for drag-out live in the app's temp folder and are deleted on launch and quit. |
| Counter numbers follow creation order and renumber on delete | Steps stay 1, 2, 3 with no gaps. |

## Build notes (steps 3–4, 2026-11-03)

### What was built

- `SnapperCore` (pure, tested): selection geometry and modifiers, AppKit ⇄ Quartz ⇄ pixel
  coordinate conversion, window picking, desktop-icon window detection, remembered area,
  window shadow, file naming/save location/encoding, card queue with auto-close timers,
  pin geometry, the annotation model (hit testing, handles, Shift constraints), the editor
  state with snapshot undo/redo and counter renumbering, and the renderer (Core Graphics,
  Core Text, Core Image redaction).
- `Snapper`: menu bar app; `Capture/` (ScreenCaptureKit service behind `ScreenCapturing`,
  window list, region overlay with layer-based dimming, magnifier, size readout and hint);
  capture cards (`FloatingPanel` per card, AppKit drag source); editor window
  (`NSHostingController` + AppKit canvas, tool strip, toolbar actions, menu commands; the
  app turns into a regular app with a Dock icon and menu bar while an editor is open);
  pins (`NSPanel`); permission window (`PermissionGate`); Settings (`SlopSettings`);
  test scene and test hooks.

### Shared components built in-app (move to SlopKit later)

- `Sources/Snapper/Capture/ScreenCaptureService.swift`: `ScreenCapturing` protocol, SCK
  implementation (display snapshots that leave out our windows except kept ones, optional
  Finder desktop-icon exclusion, "only these windows" test mode, single-window capture),
  `WindowList`, `NSScreen.displayID/underPointer/primaryHeight`.
- `Sources/Snapper/Capture/RegionOverlay.swift` + `OverlayView.swift`: the full-screen
  area/window picker with frozen screen, magnifier (`LoupeLayer`), readout (`BadgeLayer`).
- `Sources/SnapperCore/Capture/*`: `SelectionGeometry`, `ScreenCoordinates`,
  `WindowPicker`, `DesktopIcons`, `WindowShadow`.
  None of these import Snapper types.

### Tests

58 Swift Testing tests in 10 suites (`scripts/test.sh Snapper`): geometry, coordinates
(Retina, second display), window picking, files (naming, collisions, save, JPEG flatten),
card queue timers and hover, pin sizing, annotation hit testing/handles/constraints, editor
undo/redo/drag coalescing/cancel/counters/style/crop, rendering (pixel checks for shapes,
text, counters, crop size, pixelate and blur destroying detail), window shadow.

### Gates

- `scripts/check.sh Snapper --perf`: all PASS. Launch 141 ms, first status item 238 ms,
  idle CPU 0.036 %, footprint 22.0 MB (budget 50).
- Latency (release build, `SNAPPER_LOG`): hotkey → overlay on screen 14–46 ms (global
  hotkey 14–21 ms); frozen screen ready 76–218 ms (the overlay is already up and dimming
  the live screen meanwhile); selection → card 12–29 ms (area), ~80–110 ms (window,
  includes a fresh single-window capture), full screen 83–165 ms.
- Memory after three 5K full-screen captures and closing them: back to ~5 MB above the
  idle baseline (frozen screens are released when the overlay closes; the last closed
  capture is parked as a temp PNG, not kept in memory; malloc pressure relief afterwards).
- `scripts/drive tree`: no `[unlabeled]` in the card, editor, pin, Settings, About or
  permission window. Card actions stay in the accessibility tree when not hovered.

### Walkthrough (release build, `--direct`, test scene, `SNAPPER_SAVE_DIR=/tmp/snapper-test/out`)

Every v1 item was driven with `scripts/drive` + synthetic mouse events and checked in
screenshots (kept in /tmp only): area capture with magnifier and readout; Space → window
mode with highlight and size; window capture with shadow; global hotkeys ⌥⇧⌘3/4/5;
Esc cancel; Shift square (480 × 480 px from a 240 pt drag); Return = whole screen;
full-screen and previous-area captures; card Save (file correct), Copy (PNG + TIFF on the
clipboard), Annotate, Pin, drag-out into a Finder window on /tmp (file copied, card
closed), auto-close after 10 s, Reopen Last Capture; editor: every tool, undo/redo via
⌘Z/⇧⌘Z, crop with Return, ⌘S (900 × 800 px, annotations burned in, pixelation
unreadable), Share sheet, ⌘W (Dock icon goes away again); Annotate Clipboard Image; pin
opacity/nudge/zoom/Esc; Settings tabs, menu, About, light and dark; no-permission launch
shows the permission window (no crash) and the menu's "Screen Recording is off" line.

### Design checklist (§10)

1. Main job in one shortcut: pass. 2. Native look, accent color, light/dark: pass
   (annotation palette is content, by decision). 3. Every action in a menu with its
   shortcut: pass, except single-letter editor tools (in the Tools menu with the letter in
   the title; see Decisions). 4. Esc/⌘,/⌘Q/⌘W: pass. 5. Settings General + About: pass.
6. Copy/HIG: pass. 7. Empty states: n/a (no library); permission window explains itself.
8. Permission only when needed, exact pane, live re-check + Restart: pass (SlopKit gate).
9. Nothing destructive: captures are never deleted without a way back (Reopen Last
   Capture; editor puts the card back if edits weren't exported). 10. No network: pass.
11. Budgets: pass. 12. VoiceOver names: pass. 13. Reduce Motion: card fade only, stack
   moves without animation under Reduce Motion: pass. 14. Editor windows open centered,
   sized to the capture; Settings via SwiftUI: pass.

### Deferred (later)

- Self-timer, All-In-One mode, backgrounds for window captures, file name templates,
  @2x suffix / 1x scaling, print, pencil and spotlight tools, filled rectangle, lock mode
  for pins, multiple-display selection across screens (a selection stays on one display).
- v2 (roadmap): recording/GIF, scrolling capture, OCR.

### Known risks

- Multi-display: built and unit-tested per display, but this Mac has one display, so the
  overlay on a second screen hasn't been walked through.
- Window-shadow look is ours (soft, 34 pt blur), not the system's exact shadow.
- Copy writes to the real clipboard (needed to test it); clipboard *reading* happens only
  for "Annotate/Pin Clipboard Image".
- macOS may show its periodic "Snapper is capturing your screen" confirmation for
  ScreenCaptureKit apps; we can't suppress it.
- The share menu shows the owner's contacts: never screenshot it in tests.

## Sources

- https://cleanshot.com/features
- https://keyscreen-website.pages.dev/cleanshot-x-keyboard-shortcuts (third-party shortcut list: Space moves the selection, Esc cancels)
- https://alchemists.io/articles/clean_shot/ (third-party: modifier behaviour)
- https://daveswift.com/cleanshot-x/ (review)
- The installed app's status menu and Settings panes (read-only, 2026-11-02)

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.

### Round 1 (2026-11-03)

| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
| With `SNAPPER_TEST_SCENE=1`, Capture Full Screen saved the real menu bar (other apps' menus, status icons, clock) | blocker (privacy) | Accept | The test-mode filter excluded every *app*, but the menu bar and clock belong to no app in ScreenCaptureKit's list. Now every test-mode snapshot is also masked to the allowed windows' frames minus the menu bar strip (`PrivacyMask`, fails closed), and window capture refuses any window but the scene. Unit tests fail if any pixel outside the kept area survives; runtime check: full screen with the windowed scene = 0 opaque pixels outside the scene (inside = exactly 2000 × 1416); with the full-screen scene, the top 66 px rows are fully transparent. |
| Capture commands only in the status item (can hide behind the notch) | minor | Accept | File menu now has Capture Area/Window/Full Screen/Previous Area (with their shortcuts), clipboard/file images and Reopen Last Capture. Snapper shows its menu bar + Dock icon whenever a titled window of its own is open (editor, Settings, About, permission window). |
| Esc doesn't close the permission window; no default button | minor | Accept | Local prompt: Esc closes, Return = Open System Settings, Restart button after requesting. SlopKit's `PermissionPrompt` lacks a default button: flagged for the tooling agent rather than edited. |
| No Help; overlay keys undocumented | nit | Accept | Help ▸ Snapper Help opens the README on GitHub; README lists overlay, card, editor and pin keys. |
| AX labels; recorders read as search fields; "(R)" in Tools menu titles | nit | Accept (partly) | Color/width buttons read "Color, Blue" / "Line width, Thick". Tools items are plain titles with the key as a subtitle ("Press R"); real key equivalents would fire while typing text. Shortcut recorders come from KeyboardShortcuts via SlopKit: flagged for the tooling agent. |
| Window-pick hint doesn't mention Return; no format choice in Save As; saving twice makes "… 2"; editor title doesn't say what's open | nits | Accept | Hint mentions Return; Save As has a Format menu (PNG/JPEG/HEIC, also in Settings); saving the same capture again overwrites its own file ("Updated …"); editor title is the source (screenshot name, "Clipboard Image" or file name) with "Annotate · W × H px" below. |
| Missing: editor zoom | — | Accept | View ▸ Zoom In ⌘=, Zoom Out ⌘−, Actual Size ⌘0, Zoom to Fit ⌘9; pinch and ⌘-scroll zoom at the pointer, scroll pans. The canvas now clips to its bounds (macOS 14 stopped doing that by default, so a zoomed image covered the tool strip). |

Process note: system dialogs from other apps sat over the middle of the screen during this round; all mouse actions were kept to areas checked clear of foreign windows first.

### Round 2 (2026-11-03)

Privacy check passed (every capture contained only the test scene); no majors.

| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
| Thumbnail Save asked for a location once, then saved silently (and an extra file appeared) | minor | Accept | The card read the *global* Option-key state, so a stale or scripted modifier could turn Save into Save As. Now only an actual Option-click does; plain Save always goes to the Settings folder, and the confirmation names the file and folder ("Saved “….png” to out"). Saving the same capture again updates its file. |
| `open -a Snapper image.png` / Open With did nothing | minor | Accept | `application(_:open:)` opens each image in the editor; app.json declares image document types (rank Alternate, so no default changes). Verified: app already running (normal launch), not running, and `--direct` launch: one process, editor opens each time. |
| Window mode ignored clicks until the pointer moved | minor | Accept | The overlay now picks the window under the click itself on mouse-down. Verified with an instant pointer jump + click. |
| Text near the edge ran off and was clipped | minor | Accept | Text boxes are kept inside the visible image while typing and on commit (`Annotation.keptInside`, tested). |
| Shortcut ✕ buttons invisible to VoiceOver; Color/Line Width labels changed | minor | Accept (✕ deferred) | Color and Line Width are now standard pop-up buttons: "Color" = "Red", "Line Width" = "Thick", always. Recorders are now named after their row. The ✕ is drawn inside the KeyboardShortcuts package's recorder and isn't an AX element; a custom "Clear Shortcut" action was tried and the recorder ignores it. Deferred to SlopKit/KeyboardShortcuts (tooling agent). |
| Tools menu: no checkmark; no Thicker/Thinner keys | nit | Accept | An AppKit menu delegate checkmarks the current tool, color and width when the menu opens; `]` / `[` change the width (subtitles show them). |
| Editor title kept the old size after a crop | nit | Accept | Subtitle follows the output size ("Annotate · 900 × 800 px") on every change. |
| Blur/pixelate hid annotations beneath them | nit | Accept | Redactions draw first (on the capture), all other marks on top; hit testing matches. Documented in the README; render test. |
| Copy closed the thumbnail even with "Close thumbnails: Never" | nit | Accept | New setting "Close thumbnail after copying or saving" (on by default, like macOS); auto-close stays separate. |
| Undo history lost when reopening the editor | nit | Accept | The editor state (with undo/redo) is kept on the capture and restored. |
| (found while verifying) A capture requested right after Esc was dropped | — | Fixed | The previous capture was still finishing; requests now retry for up to 1.5 s instead of being ignored. |
| Missing: key hint in the overlay | — | Accept | The hint now lists Shift/Option/Space/Return/Esc and sits near the top of the screen, where it's seen. |

Also this round: the capture components moved to SlopKit (`apps/SlopKit/Sources/SlopKit/Capture/`): `ScreenCapturing`/`ScreenCaptureKitCapturer`, `FrozenDisplay` (per-display image + scale + point↔pixel), `PixelBuffer` (raw RGBA, luminance, leak counting), `RegionOverlay` with `LoupeLayer`/`BadgeLayer`, `SelectionGeometry`, `ScreenCoordinates`, `WindowPicker`/`WindowList`/`DesktopIcons`, `WindowShadow`, `PrivacyMask`. Snapper uses them; their tests moved to SlopKitTests. `Arrow` was renamed `ArrowKey` for the shared namespace.

Ship: status beta, version 0.2.0 (build 2).


## Parity pass (2026-11-03)

Per [`docs/parity-pass.md`](../parity-pass.md): look and work like the original, no missing
everyday features. Studied: CleanShot X 5.0.2's status menu and Settings General pane
(read-only via `scripts/drive`; the other panes need a real click on the sidebar, which
wasn't possible while the owner was active, so they came from the product page's official
Settings screenshots), cleanshot.com's feature page images and demo videos (quick-access
overlay, annotate window, background tool, scrolling capture, recording panel, All-in-One
bar; frames extracted to `/tmp/snapper-parity/`, never committed), and a third-party
shortcut list for the editor's tool letters. Capture history, any overlay and any past
capture were never opened; no CleanShot shortcut was pressed; no setting was changed.

### Gap table

| Item | Original | Before | Now |
|---|---|---|---|
| Status menu order | All-In-One, Area, Previous Area, Fullscreen, Window, Scrolling, Self-Timer, Text, Record │ Hide Desktop Icons │ Open…, Pin… │ History │ About, Settings, Quit | Area, Window, Full Screen, Previous │ images │ thumbnails │ toggle | **Done**: same order and grouping (no History, by design); Stop/Pause/Discard Recording on top while recording; icon turns into a stop symbol |
| Quick-access card | Capture fills the card; on hover it dims, Copy and Save pills in the middle, Close top-left, Pin top-right, Annotate bottom-left, Upload bottom-right; right-click menu; new cards stack above older ones; size slider; "Move to active screen" | Material frame around the thumbnail, three round buttons along the bottom, newest at the corner, fixed size | **Done**: same layout (Share instead of Upload), dims on hover, oldest stays in the corner, size slider and "Move to active screen" in Settings, context menu (Annotate, Pin, Copy, Copy Text, Save, Save As, Share, Show in Finder, Close, Close All); recordings show a play badge with duration |
| Annotate window | Tools in the title bar (crop, background, then shapes, text, pencil, highlighter, redact, spotlight, counter), color and style next to them, Save As… and Done on the right; bottom bar with zoom, "drag me" handle and quick outputs; Background tool sidebar | Tool strip under the toolbar, outputs in the toolbar | **Done**: same structure (title hidden, tools as a segmented radio group in the title bar, Crop/Background toggles on the left, Color + Width/Redaction menus, Save As…, Done), bottom bar (zoom menu + size, Drag Out handle, Share/Pin/Copy/Save), Background sidebar |
| Tool letters | V K D M L T A C E P H R F B | V A L R O T H P B N C | **Done**: the original's letters (README, Tools menu subtitles, Annotate pane) |
| Pencil, filled rectangle, spotlight | yes | no | **Done** (smoothed freehand, solid box, combined spotlight dimming) |
| Blur/pixelate as one redaction tool with a style | yes | two tools | **Done** (P; Pixelate/Blur menu; changing it converts the selected redaction) |
| Background tool | gradients, wallpapers, plain colors, padding, inset, shadow, corners, presets | no | **Done**: 8 gradients of our own, 12 plain colors, padding, corners, shadow; undoable; part of the document so it stays editable. Wallpapers/presets/inset/auto-balance deferred |
| Copy object ⌘C / paste / duplicate ⌘D / copy image ⇧⌘C / print ⌘P | yes | ⌘C copied the image | **Done** |
| Settings window | Sidebar: General, Shortcuts, Quick Access, Wallpaper, Screenshots, Screen Recording, Annotate, Cloud, Advanced, About | 4 tabs | **Done**: sidebar with General, Shortcuts, Quick Access, Screenshots, Recording, Annotate, Advanced, About (no Cloud; Wallpaper folded into Screenshots → Window Screenshots) |
| General pane | App / Capture / Sounds / Export / After Capture | mixed in one tab | **Done**: same sections |
| All-In-One | ⇧⌘5 bar: Area, Fullscreen, Window, Scrolling, Timer, OCR, Recording | no | **Done**: ⌥⇧⌘5 bar near the bottom of the screen, number keys 1–7, Esc. Remembering the last selection: deferred |
| Self-timer | menu + interval setting (5 s) | no | **Done**: pick area (Return = screen) → 3/5/10 s countdown (Esc cancels) → fresh capture |
| Capture Text (OCR) | ⇧⌘2, language, keep line breaks | no | **Done**: ⌥⇧⌘2, on-device Vision (accurate, language auto-detected), "Keep line breaks" setting, also Copy Text on cards and in the editor |
| Scrolling capture | pick area → Start → scroll → Done, live preview, auto-scroll | no | **Done** except auto-scroll (needs synthetic scroll events = Accessibility permission; deferred) |
| Screen recording | area/window, video or GIF, controls bar, pause/restart, countdown, dim screen, cursor, click highlight, keystrokes, mic/system audio, webcam, fps, 1x, GIF fps/size, video editor | no | **Done**: area/window/full screen; Record Video (Return) / Record GIF (⌥Return); bar with Stop, time, Pause, Discard; record shortcut or menu stops; dim screen, countdown, fps, cursor, 1x, GIF fps and width; Export as GIF from a video card. Audio, webcam, click/keystroke overlays, restart, trimmer deferred |
| Window background / padding | wallpaper or transparent, padding, shadow | shadow only | **Done**: Transparent or one of our gradients, padding slider, shadow toggle; opens editable with the Background tool. Using the real desktop wallpaper deferred (privacy: would put the owner's wallpaper into test captures) |
| File name template | Advanced → file name | fixed | **Done**: `{type} {date} at {time}` with tokens, live example, Restore Default |
| Pinned screenshot options | rounded corners, shadow, border | fixed on | **Done** (Advanced → Pinned Screenshots) |
| Annotate options | draw shadow on objects, always on top, Dock icon, inverse arrow, smooth drawing, expand canvas, color names | none | **Done**: shadow on objects, always on top; pencil is always smoothed; the rest deferred |
| Shortcuts pane | every action recordable | 4 | **Done**: 14 actions (All-in-One, toggle desktop icons, pin file, reopen last, close all thumbnails, area, previous, full screen, window, self-timer, scrolling, text, record/stop) |
| Shutter sound choice | System Default / others | on/off | Deferred (S, 1 h): macOS's screenshot sound is the only one that fits |
| Retina 1x / 1 px border / sRGB for screenshots | options | no | Deferred (S, 1–2 h) |
| Show cursor in screenshots | option | no | Deferred (S): SlopKit's snapshot API hides the cursor; needs a SlopKit option (other agents' area) |
| Capture history | 3 days | — | Skipped by design (privacy) |
| Cloud upload | yes | — | Skipped by design (no network) |
| URL scheme API | yes | — | Deferred (M, 3 h) |
| Ask for name after capture | Advanced | no | Deferred (S, 1 h) |
| "Capture area & copy/save/annotate/pin" shortcut variants | Shortcuts | no | Deferred (S, 1 h) |
| Quick Look / Open With / Rotate / Temporarily Hide on the card menu | yes | no | Deferred (S, 2 h) |
| Video trimmer, audio, webcam, click & keystroke overlays | yes | no | Deferred (L, 2–4 days together): each needs its own UI and permissions (microphone, camera, Accessibility for keystrokes) |
| Auto-scroll in scrolling capture | yes | no | Deferred (M, 4 h): needs posting scroll events (Accessibility permission) |
| Wallpaper pane / background presets | yes | no | Deferred (M, 3 h) |
| Lock (click-through) pins | yes | no | Deferred (S, 2 h) |

### Decisions

| Decision | Why |
|---|---|
| Default keys ⌥⇧⌘2/3/4/5/6 = Text / Full screen / Area / All-in-One / Record; Window has no default | The original's digits (⇧⌘2–5) plus ⌥, so nothing collides with macOS or the original. A one-time migration frees the old ⌥⇧⌘5 from Capture Window on existing installs. |
| Self-timer picks the area first, then counts down | You choose what to capture while the screen is calm; the countdown is for opening the menu or hover state you want. |
| Scrolling capture: manual scrolling, stitched by matching row signatures | Works in every app with no permission; robust to the scrolled amount; stops at 40 000 px. |
| Recordings are silent | Audio needs microphone permission and its own UI; the everyday use (show a bug, a flow) works without it. |
| GIF = record MP4, convert at the end (ImageIO) | One recorder, and any video can become a GIF later from its card. |
| Recording test mode records the scene window alone (desktop-independent window stream) and refuses other areas | ScreenCaptureKit display filters can't remove surfaces no app owns; a single-window stream can't contain anything else, by construction. |
| Copy/Save/Save As/Pin/Copy Text menu items act on a clicked thumbnail or pin when one is key | The new editor commands are always enabled, so they must not swallow the card's and pin's own shortcuts. |
| Editor's ⌘C copies the selected object, else the image; ⇧⌘C always the image | The original's model. |
| `SNAPPER_PASTEBOARD` private pasteboard | Tests check Copy and Capture Text without ever touching the real clipboard. |
| `SNAPPER_CARD_HOVER=1` | Screenshots of the hover layout without moving the owner's pointer. |
| In test mode the All-in-One bar sits over the test scene | It's translucent; over the scene, screenshots can't show anything else through it. |

### Deviations from the design system (and why)

- **Settings isn't `SlopSettings`**: a sidebar window (List + grouped Form) built from
  SlopKit's `LaunchAtLoginToggle`, `MenuBarIcon.storageKey` and `AboutView`, because the
  original has eight panes in a sidebar and `SlopSettings` is a three-tab view. Sidebar
  tiles are System Settings-style (SF Symbols on system colors). Worth a sidebar variant in
  SlopKit.
- **Editor window title hidden** (the tools take the title bar, like the original); the
  title stays set for the Window menu and VoiceOver, and the size moved to the bottom bar.
- **Card has no frame around the thumbnail** (the capture is the card) and dims on hover.
- **Background gradients** are fixed sRGB colors (image content, like annotation colors).
- **Test-mode bar placement** (above).

### Privacy in test mode (every new capture kind)

- Self-timer and scrolling capture use the same `snapshot` path as area/full screen
  (filtered to the scene, masked to its frame minus the menu bar, fails closed). Measured:
  self-timer full screen = 0 opaque pixels outside the scene (2000 × 1416 inside, exactly
  the scene); scrolling result 1840 × 3360 px, all scene content.
- Recording: `RecordingPlan` never yields a display source in test mode (unit test
  `testModeOnlyEverRecordsTheSceneWindow`: a full-display selection records only the
  scene window's rect, a partial one only its part inside the scene, a miss is refused);
  the controller also refuses a display plan in test mode. Runtime: `source=window(…)`,
  1920 × 1280 px = 960 × 640 pt selection; frames checked: only scene content (and the
  pointer). Off-scene selection: refused with a HUD.
- Window capture of any non-scene window: refused (hook `windowOther`).
- OCR reads only the frozen (masked) selection or the scene window.

### Tests and gates

- Unit tests: **61 in 14 suites** (was 41): new suites for the new tools, background,
  file name templates, scrolling stitcher (frames from a synthetic page stitch back
  pixel-exact; no-overlap and height limit), recording plan + GIF encoder, text layout and
  Vision OCR.
- `scripts/check.sh Snapper --perf`: all PASS. Launch 179 ms, first status item 394 ms,
  idle CPU 0.002 % (lowest), footprint 26.0 MB (budget 50); machine busy (load 4.7).
- Walkthrough (release build, `--direct`, test scene, hooks, private pasteboard): full
  screen + card copy; Capture Text (236 characters, all the scene's text); self-timer with
  countdown and Esc cancel; scrolling capture (7 frames, every 360 px step matched, seamless
  1840 × 3360 result) and cancel; recording video with pause (5.0 s H.264, 1920 × 1280),
  GIF (800 × 533), copy (file URL on the private pasteboard), Reopen + Save
  (`Recording … .mp4` in the save folder), off-scene refusal; window capture with a gradient
  background (opens editable in the Background tool); editor: pencil, filled rectangle,
  spotlight, arrow and pixelate drawn with the mouse (owner idle), Background tool,
  Done → card comes back; All-in-One bar with number keys; every Settings pane in light and
  dark; no-permission launch: recording/scrolling/text/self-timer all show the permission
  window, no crash. `scripts/drive tree`: no `[unlabeled]` in cards, editor, Background
  sidebar, record/scrolling bars, All-in-One, Settings.
- Not tested with the real mouse: dragging a new area for the new modes (the overlay is the
  same SlopKit overlay as area capture, verified in earlier rounds; the new modes were
  driven with Return = whole screen and scene-region hooks), hover on a real card (shown
  with `SNAPPER_CARD_HOVER`).
- First-ever text recognition on a Mac takes ~25 s while macOS compiles its model (once
  per system, measured in a separate process); afterwards ~0.1 s.

### Screenshots (kept in /tmp only)

`/tmp/snapper-test/shots/`: `card-hover-dark.png`, `card-hover-light.png`,
`card-window-bg-light.png`, `card-video-dark.png`, `editor-dark.png`,
`editor-background-dark.png`, `editor-window-bg-light.png`, `editor-tools-light.png`,
`all-in-one-dark.png`, `record-bar.png`, `countdown.png`, `recording-frames.png`,
`scrolling-result.png`, `settings-*-light.png`, `settings-general-dark.png`,
`settings-grid-light.png`, `settings-grid2-light.png`.

### In-app components to move to SlopKit later

`ScrollStitcher` (Core), `RecordingPlan` + `StreamRecorder`/`RecordingSink`/`VideoFrames`,
`GIFEncoder`, `TextRecognizer`/`TextLayout`, `RegionFrame` + `Countdown`,
`PickedRegion`, the sidebar Settings layout (`Pane`, `PaneIcon`).

## Polish pass (2026-11-05)

Per [`docs/polish-pass.md`](../polish-pass.md). Release build stamped with SDK 27.0, every
surface shot with `scripts/drive shot Snapper` (own windows only) in light and dark from
`SNAPPER_TEST_SCENE=1` content and synthetic images in `/tmp/snapper-test/in/` (nothing of
the owner's). Screens that need Screen Recording ran with `--direct`; the permission window
with a normal launch. New screenshot-only hooks: `editorSample`, `editorCrop`,
`editorSelect`, `editorBackground`, `editorDone`, `pinLast`, `permissionWindow`,
`openSettings` (Diagnostics.swift); `SNAPPER_CARD_HOVER` now also shows a pin's close button.

### Defects fixed (before → after)

| # | Surface | Before | After |
|---|---|---|---|
| 1 | Source | `lint.sh`: 10 corner-radius literals, 6 spacing warnings | 0 and 0: every radius from `Radius` / `Radius.nested` / a derived capsule |
| 2 | Thumbnail | 12 pt card, 24 pt round buttons 6 pt in: circle centre (18, 18) vs corner centre (12, 12), not concentric | `Radius.xl` card, buttons `Spacing.xs` in, radius 12 = `nested(16, 4)`: measured 4.0 pt along the edges, 4.2 pt at the curve |
| 3 | Thumbnail | 1.0 pt white 18 % edge | 0.5 pt separator hairline (`hairlineBorder`) |
| 4 | Thumbnail | Copy/Save stacked (2 × 25 + 8 pt) collided with the corner buttons on cards under ~112 pt (min height was 0.42 × width = 67 pt at 160) | min height 92 pt (`CardLayout`, tested at every width 160–320), pills fall back to a row (`ViewThatFits`), pills 28 pt |
| 5 | Thumbnail | Tall captures (scrolling) showed their middle | show their top |
| 6 | Thumbnail | Video badge padding 6/3 literals, ~20 pt, 8 pt in | 24 pt capsule 4 pt in, the same spot as the corner buttons |
| 7 | All-in-One | Tiles meant as 80 × 58 came out 104 × 66 (accessory-bar padding), insets 8 pt sides / 4 pt top-bottom, bar 778 × 74 from a guessed formula, hover shape not concentric, 1 pt dividers | fixed 80 × 60 tiles, even 8 pt inset, tile hover/pressed radius 8 = `nested(16, 8)` (`TileButtonStyle`), bar exactly 610 × 76 computed from the same constants, 0.5 pt group separators; scrolling icon "arrow.down.to.line" (read as download) → "scroll" |
| 8 | Recording bar | 14 pt literal radius on a 46 pt bar; controls 24/28/29 pt tall; Record Video default not visibly prominent; width 215 → 216 pt when Pause ↔ Resume | capsule bar 44 pt (radius 22 = height ÷ 2), every control a 28 pt capsule/circle 8 pt in (measured 8/8/8, concentric), Record Video accent-filled, timer in a fixed slot (157 pt wide in every state), time turns secondary while paused |
| 9 | Scrolling bar | 14 pt literal radius; width jumped 205 → 382 pt on Start and stayed left-anchored (centre 88 pt right of the area); "Scroll back up" in plain `.orange` (~2:1) | capsule bar like the recording bar, re-centred after Start (logged off-centre 0 pt in both states), fixed slots for the hint and the height, `.textOrange`, Start/Done prominent |
| 10 | Scrolling preview | Stitched image centred vertically in the strip; 6 pt literal radius; 1 pt border | starts at the top, then shows the newest rows; `Radius.m`; 1 device-pixel border |
| 11 | Countdown | 22 pt literal; "Esc to cancel" `.tertiary` (~1.9:1); block 36 pt from the top vs 23 pt from the bottom; the digit never animated (a content transition with no animation) | `Radius.xxl`; `.secondary`; 32 / 30 pt; digit rolls with `.snappy`, fades under Reduce Motion |
| 12 | Pin | 1.0 pt border; 8 pt literal; white xmark with a drop shadow 6 pt in | 1 device pixel; `Radius.m`; the thumbnail's material round button 8 / 8 pt in, 0.12 s fade |
| 13 | Pin (window capture) | Border and rounding drawn around the transparent shadow margin: a frame floating 44 pt outside the window | only when the image's edges are opaque (`ImageEdges`, tested) |
| 14 | Editor toolbar | Color pop-up 88 pt with an empty gap between swatch and chevron | 40 pt swatch menu with a checkmarked list; VoiceOver "Color" = "Red" |
| 15 | Editor | Bottom-bar and sidebar dividers 1.0 pt; bar padding 6 pt (off-grid), 39 pt | 0.5 pt hairlines (`Hairline`); bar 40 pt, `Spacing.xs` |
| 16 | Editor | Drag Out pill: 11 pt literal; in dark mode its fill resolved in the wrong appearance inside a behind-window material: 1.00:1 against the bar | capsule from its height (24 pt), colour resolved in `updateLayer`, opaque bar: #414141 pill on #252525, label 5:1 |
| 17 | Background sidebar | 4 × 36 pt swatches in a 232 pt panel: 12 pt left vs 52 pt right; selection a 3 pt stroke over the swatch; 1 pt `primary` 15 % edges; "None" 52 pt wide, centred; no values | 216 pt panel, 16 / 16 pt margins, 40 pt swatches 8 pt apart; 2 pt accent ring 2 pt outside, concentric (8 + 4 = 12 pt); 1 px separator edges; "None" full width; Padding/Corners/Shadow show "64 pt" / "12 pt" / "50 %" |
| 18 | Crop | Size badge radius 5 pt literal, padding 6/3 | `Radius.s`, `Spacing.s`/`xs`, same badge as the capture overlay's readout |
| 19 | Selection | 8 pt square handles at fractional positions (blurry 1.5 pt ring); dashed box blurry | 9 pt round handles snapped to the pixel grid, soft shadow; dashed box on half points (2 crisp pixels) |
| 20 | Settings | Hand-built sidebar under one title bar: the pane title sat over the sidebar | `NavigationSplitView`: title over the detail column, system sidebar 200 pt, selection 10 / 10 pt in, no sidebar toggle |
| 21 | Settings | Pane tiles 5 pt literal on 20 pt | `Radius.iconTile(side: 20)` = 4.5 pt |
| 22 | Settings → Screenshots | Padding slider without a value | "56 pt" in a fixed slot (the slider doesn't shift) |
| 23 | Permission window | Footnote `.tertiary`; body in two long lines and an orphaned "Mac." | `.secondary`; three even lines |
| 24 | Text capture HUD | "…scene · captur…" cut mid-word | word boundary, no trailing separator: "…test scene…" (tested) |
| 25 | VoiceOver | Fixed-slot labels read as "unknown" | static text |

Unchanged on purpose: the menu bar menu (a system menu), the region overlay (crosshair,
readout, magnifier, hint: SlopKit's, already on `Radius`/`Spacing`), the hover dim on
thumbnails, annotation and background colours (image content).

### Gates

- `scripts/check.sh Snapper --perf`: all PASS. Tests **68 in 17 suites** (was 61): card
  layout, image edges, text preview. Launch 147–196 ms, first status item 303–351 ms, idle
  CPU 0.004 % (a 0.104 % reading during a load-10 run didn't repeat), footprint 25.8 MB.
- `scripts/drive tree`: no `[unlabeled]` on the card, All-in-One, pin, record/recording and
  scrolling bars, editor with the Background sidebar, and all eight Settings panes. Every
  window button is 16 × 16 (Settings, editor, permission window, test scene).

### Screenshots

`/tmp/slopapp-polish/snapper/before/` (the starting state) and
`/tmp/slopapp-polish/snapper/final/{light,dark}/`: `card-hover`, `all-in-one`,
`scrolling-ready`, `scrolling-running`, `pin-hover`, `record-ready`, `recording`,
`recording-paused`, `countdown`, `editor-empty`, `editor-selection`, `editor-crop`,
`editor-background`, `settings-<pane>` (all eight), `text-result`; `light/menu`.
Permission window: `/tmp/slopapp-polish/snapper/after/permission-{light,dark}-1.png`;
video badge and tall card: `/tmp/slopapp-polish/snapper/after/cards-light-{1,2}.png`.

### Not done, and why

- **Hover and pressed states with the real pointer** (thumbnail, All-in-One tiles, bar
  buttons, pin close): not exercised. The owner was active at the start and the screen was
  locked for most of the pass; shown with `SNAPPER_CARD_HOVER` only. The tile and capsule
  hover fills are new and need a look with a real mouse.
- **Glass in window-only screenshots** renders as flat grey, so text contrast on the real
  glass bars (secondary hints) couldn't be measured; full-screen shots aren't allowed.
- `scripts/measure corners` reports the thumbnail as "NOT concentric": its straight-edge
  probe lands on capture content, not on the round button. Checked with `measure line`
  instead (4.0 pt edge, 4.2 pt at the curve).

### In-app components to move to SlopKit later

`Hairline` + `hairlineBorder` (`Hairline.swift`: SwiftUI's `Divider` is 1 pt on macOS),
`ControlBar` geometry with `BarIconButton`, `BarTextButton`, `CapsuleButtonStyle`,
`FixedWidthText` (`ControlBar.swift`), `TileButtonStyle` (`AllInOneBar.swift`),
`ImageEdges` (Core).

### Golden Gate + light/dark (2026-11-06)

Per the mid-pass addition to `docs/polish-pass.md` and design system §4 "Fitting in on
macOS 27 Golden Gate" / §10 items 25–26. Shots in `/tmp/slopapp-polish/snapper/gg/{light,dark}/`
(test scene and `/tmp/snapper-test/in/` images only); every surface in both modes, plus a
live appearance switch with the windows open (new hooks `appearanceLight` /
`appearanceDark`). Defaults were backed up first and restored afterwards.

| Check | Before | After |
|---|---|---|
| SlopKit `Hairline` | Snapper had its own `Hairline` / `hairlineBorder` (now SlopKit's, which lays out 1 pt) | in-app copy deleted; SlopKit's used in the editor sidebar/bottom bar and the All-in-One separators. All-in-One stays 610 × 76 (its width formula already counted 1 pt per separator); the editor sidebar divider moved 0.5 pt, nothing aligns across it |
| Settings sidebar | white symbols on fixed-colour tiles (System Settings style) | plain sidebar symbols: accent-tinted in the key window, grey in a background one (both shot: `settings-active`, `editor-active-and-settings-inactive-2`) |
| Menus | status menu, card and pin context menus, Zoom, Tools, Line Width, Redaction: already text only | unchanged. The Color menu keeps its swatches (they're the information) |
| Toolbar | the editor's standard `.toolbar`, nothing drawn behind items | unchanged |
| Inactive window: canvas selection | dashed box and handle rings always accent | accent in the key window, system grey in a background one, redrawn on key change (`editor-active…-1` vs `editor-inactive-2`) |
| Inactive window: Background sidebar | selected swatch ring always accent | `Color.selectionRing(controlActiveState)` |
| Inactive panel: prominent bar buttons | Record Video / Start / Done accent-filled with pure white text, pressed state drawn with black | accent-filled only while the panel is key (`appearsActive`), otherwise the quiet capsule; text `alternateSelectedControlTextColor`; pressed/hover via brightness |
| Overlay chrome (over arbitrary content) | crop dim black 50 %, crop outline/thirds white, crop badge black 72 % / white text, handles pure white with black shadow, recording-area dim black 35 %, thumbnail hover dim black 38 % | `OverlayPalette`: ink scrim, paper ring and thirds, badge fill/text, opaque paper handles with an ink shadow; region frame gets an ink underline under its accent/red dashes so it shows over a page of the same colour; hover dim ink 40 %. Measured: recording dim #282828 @ 40 % (was #000000 @ 35 %) |
| Layers that didn't follow a live switch | scrolling preview card's background and border were resolved once at creation | `PreviewView.updateLayer` re-resolves them: #282828 → #FFFEFF when switched dark → light live. Drag Out pill, pin border, canvas: also follow (shot `live-*`) |
| Drawn pure black/white | swatch menu image had a black/white "selected" dot (unused) | removed |
| Glass | FloatingPanel (system regular glass) for the bars, countdown, All-in-One and thumbnails; SlopKit HUD | unchanged: no custom translucent fills; text sits on the system's regular (text-bearing) glass or on `regularMaterial` capsules |
| Reopen opens Settings | (new SlopKit behaviour) | right for Snapper: its status icon can hide behind the notch, and Snapper has no main window. Opening the app with nothing showing opens Settings; Open With an image opens only the editor (see below) |

Checked side by side in both modes: Settings sidebar active (accent icons, accent selection)
and inactive (grey icons, grey selection); canvas selection active (accent dashes and handle
rings) and inactive (system grey); the live switch (dark → light and back, and light → dark)
with the editor, Settings, the scrolling preview and a pin open: every layer followed
(scrolling-preview background #282828 ↔ #FFFEFF, Drag Out pill, pin border, canvas page);
crop overlay, thumbnail hover, bars, countdown and All-in-One in both.

Reopen (tested on a launch without the test scene): with nothing open, `open -a Snapper`
opened Settings (1 window: "General"); `open -a Snapper sample.png` opened only the editor,
no Settings. Kept as is (no `opensSettingsOnReopen = false`).

Gates: `scripts/check.sh Snapper --perf` all PASS (68 tests; launch 178 ms, first status
item 319 ms, idle CPU 0.004 %, footprint 23.8 MB). Shots: `/tmp/slopapp-polish/snapper/gg/{light,dark}/`
(`settings-active`, `editor-active-and-settings-inactive`, `editor-inactive`,
`editor-background-active`, `editor-crop`, `live-*`, `card-hover`, `scrolling`,
`scrolling-live-*`, `pin`, `record-ready`, `recording`, `all-in-one`; crops
`c-active-sel.png` / `c-inactive-sel.png`). `-N` suffixes are per window; the Snapper Test
Scene and second-display overlays are among them.

Not done: hover states with the real pointer (the owner was active for long stretches; every
shoot waited for 90 s of idle, since the editor, Settings and the bars activate Snapper);
contrast on the real glass at the clearest setting (window-only shots can't see the
backdrop; Snapper uses only the system's regular glass and material backings).

## Bug fix (2026-11-07): drag to Desktop failed

Owner report: dragging a capture card to the Desktop showed Finder's "The operation can't be
completed because one or more required items can't be found." Cause: with "close after
dragging" on, ending the drag closed the card, and `remember` → `discardTemporaryFile()`
deleted the drag file at once, but Finder copies a dragged file URL after the drag session
ends, so the file was already gone (error -43). Fix: a superseded drag file is now deleted
after a 5-minute grace period (`CaptureItem.temporaryFileGrace`); each file has its own
folder so a late delete can't hit a newer one, and `TemporaryFiles.clear()` still empties
everything at quit and launch. Not yet re-verified with a real drag (owner to confirm).

## Capture History (research, 2026-11-07)

Owner: "There's the cleanshot history that needs to be replicated too." Studied read-only:
CleanShot's features page, URL-scheme docs and changelog, plus reviews. The coordinator
looked at the installed app's setting names and folder layout only. Nobody opened the owner's
captures, and the History window wasn't opened (it would show them).

### What the original does

| Area | Original | Source |
|---|---|---|
| Storage | Every capture in its own folder, `Application Support/CleanShot/media/media_<id>/<file>`; annotated ones also get a project file, so edits reopen as objects | installed app (folder layout only) |
| Index | `mediaHistory` JSON array in its prefs: `creationDate`, `url`, `tempURL`, `projectURL`, `cloudMedia`, `urlBookmark`, `appMetadata {app, bundleID, bundleURL, window}` | installed app (key names only) |
| Retention | "up to 1 month" (4.7 added the 1-month option; earlier 1 day / 3 days, the owner's is set to 3 days); reviews complain a month is the cap | features page, changelog, Setapp reviews |
| Window | Opens from the menu, a shortcut ("Open Capture History") and `cleanshot://open-history` (4.4+) | API docs, Raycast/Pie Menu shortcut lists |
| Actions | restore (also several at once, 4.5), remove files (4.5), filter by capture type (4.5), clear history (4.5.1), open Annotate and pin from history (4.5.1), double-click opens Annotate (4.6), external files opened with CleanShot are included (4.7), performance work (4.8.10) | changelog |
| Restore recently closed | "Restore Recently Closed File" shortcut (3.5.1) and `cleanshot://restore-recently-closed` | changelog, API docs |

The window's exact look isn't documented in text (one product screenshot); we don't copy it
anyway.

### Our design (decisions)

| Decision | Why |
|---|---|
| Folder per capture under `~/Library/Application Support/app.slopapp.snapper/History/<id>/`: the image as captured (`original.png`), the current version in the Save format with the capture's file name, the edits as `annotations.json`, recordings with a `poster.png` | Same model as the original (and as our `CaptureItem`): reopening is editable, and a drag hands over a real, persistent file with a nice name |
| One `index.json` (`{version, entries}`), each entry: id, date, kind, pixel size, scale, file size, file names, source app (bundle id and name), duration, last saved path. Decoding never fails as a whole: unknown fields are ignored, missing ones get defaults, unknown kinds read as "screenshot", a broken entry is skipped | Migration-safe; an index in prefs (the original's) would bloat `defaults` |
| No window titles | They can be sensitive (document names, mail subjects), and we don't show them. README says so |
| Source app = the window's app for window captures, the frontmost app otherwise; in test mode it's "Snapper Test Scene" | What people search by. Test captures never record the owner's apps |
| Kinds: Screenshot, Window, Scrolling, Recording, GIF (self-timer and previous area count as screenshots) | The filter people need; matches the original's "capture type" |
| Retention Off / 1 Day / 1 Week / **1 Month** (default) / Forever, pruned at launch and hourly; open cards, editors and pins are never pruned out from under you | The brief's options; a month matches the original's maximum and the owner's daily use |
| Writes happen in a background actor after the card is up | The capture → card budget (< 300 ms) must not move |
| Delete is undoable (⌘Z in the History window); deleted folders are erased when the window closes and at launch/quit | Design system: nothing destructive without undo. Files don't linger past the session |
| "Clear History…" asks first, then erases everything not open | Destructive and unrecoverable |
| Reopen Last Capture reads history, so it survives a relaunch; without history it keeps today's in-session behaviour | The brief |
| Drags use the history file when history is on; the 5-minute grace path stays for history off | Removes the Finder −43 race for good |
| Window: library archetype, a thumbnail grid grouped by day (Today, Yesterday, dates), newest first; toolbar Kind filter and app search; per-item context menu; double-click Annotate, Return Restore, Space Quick Look, ⌫ Delete, arrows move, ⌘A select all | The original's actions, Mac-native |
| URL commands `snapper://open-history` and `snapper://restore-recently-closed` | Same jobs as the original's URL scheme, our own names |
| `SNAPPER_HISTORY_DIR` test override | Tests never touch the real history |

## Capture History (build, 2026-11-07)

### What was built

- **Core** (`Sources/SnapperCore/History/`, tested): `HistoryEntry` / `HistoryKind` /
  `SourceApp` (every field decodes with a default; unknown kinds read as screenshots),
  `HistoryIndex` (newest-first index, `{version, entries}` JSON that skips broken entries
  and accepts a bare array, retention expiry with protected ids, kind filter, app search),
  `HistoryRetention`, `HistoryDays` (day grouping, "Today" / "Yesterday" / dates),
  `GridNavigation` (arrow keys across day sections), `HistoryStore` (an actor: one folder
  per capture, add / update after edits / saved path / delete to `.deleted` with undo /
  purge / prune / clear, entries whose files vanished are dropped), `HistoryThumbnail`
  (ImageIO downsampling), and `Codable` for `AnnotationDocument` / `Annotation` / `RGBA`
  (unknown mark kinds dropped), so restored captures are still editable.
- **App** (`Sources/Snapper/History/`): `HistoryController` (index mirror, records each
  capture after its card is up, follows edits and saves, prunes at launch and hourly,
  restore, delete with undo, clear), `CaptureSource` (front app or the window's app; "Snapper
  Test Scene" in test mode), the History window (`HistoryWindow.swift`), Settings → History
  (Keep captures, Disk used, Open Capture History, Show in Finder, Clear History… with
  confirmation, turning it Off asks first), Shortcuts → "Open capture history", "Capture
  History…" in the status menu and the File menu, `snapper://` URL commands (open-history,
  restore-recently-closed and every capture mode).
- **Drags**: `CaptureItem.temporaryFile` hands over the history file whenever the capture is
  in history (a drag right after an edit writes the new version straight into its history
  folder first); the 5-minute grace temp path stays for history off.
- **Reopen Last Capture** is history-backed (the last closed card, else the newest capture
  that isn't open), so it works after a relaunch; with history off it's the old in-session
  path.
- **Menus** route to the History window when it's in front: Undo/Redo, Save, Save As…, Copy
  Image, Pin to Screen.

### Window

Library archetype in a standard titled window ("Capture History", frame remembered):
standard toolbar with a text-only Kind menu (All Captures, Screenshots, Windows, Scrolling
Captures, Recordings, GIFs) and the system search field ("Search Apps"); a lazy grid of
176 pt tiles grouped by day with pinned headers (day title and count); a footer
("1,234 captures · 312 MB", "Kept for 1 month") under a SlopKit hairline. Tile: 12 pt
rounded selection background (`selectionTint`) and ring (`selectionRing`, grey when the
window isn't key), thumbnail 8 pt in with a concentric 4 pt corner and a hairline, time,
size (or "Edited", or the recording's kind) and source app. Thumbnails are downsampled to
352 px off the main thread and cached (600). Empty states: no captures yet (Capture Area),
history off (Keep Captures for 1 Month), a kind with none (Show All Captures), no search
results (the system's search state); a loading state while the index is read.

Mouse and keys: click, ⌘-click, ⇧-click; double-click annotates (recordings open);
drag-out of one or the whole selection as files; context menu (text only): Restore
Thumbnail(s), Annotate / Open, Pin, Copy, Save As…, Show in Finder, Quick Look, Delete.
Keys: arrows (⇧ extends, ⌘↑/⌘↓ first/last), Return restore, Space Quick Look (system panel),
⌘A, ⌘C, ⌘E, ⇧⌘S, ⇧⌘P, ⌘R, ⌫, ⌘Z / ⇧⌘Z. Deleting something that's open on screen is
refused with a HUD.

### Verified without the display (log + files, `SNAPPER_HISTORY_DIR`, synthetic history)

The display slept and the screen locked for this part, so screen capture and window shots
weren't possible; these ran through test hooks and were checked in the log and on disk:
3,000-entry index read in 28–38 ms (background); 1-month prune removed exactly the 750
older entries; delete one → index −1 and the folder in `.deleted`; undo → back; select all
(2,250) + delete → 0; undo → 2,250; delete + close the window → `.deleted` purged; Reopen
Last Capture restored an entry, and again after a relaunch.

### Looked at (offscreen, both modes)

With the display asleep, the windows were drawn offscreen by a test hook (`snapshotWindows`:
`cacheDisplay` of our own windows into PNGs, no window server involved). Shots in
`/tmp/slopapp-polish/snapper/offscreen/{light,dark}/`: `grid` (150 captures, two selected
across days), `windows` (Kind filter), `search` ("notes"), `nomatch`, `empty`, `off`, `big`
(3,000 generated → 2,250 kept by the 1-month prune; long app names truncate with an
ellipsis), `settings` (Settings → History; the offscreen render leaves the sidebar blank).
Found and fixed from them: fixed-width 176 pt tiles left 16 pt on the left and ~156 pt on
the right; columns now share the width (adaptive minimum 176 pt), margins 16 / 16 pt, and
the thumbnail box keeps its 160 : 112 shape. Selection in the (inactive) offscreen window is
the system's unemphasized grey with a grey ring, in both modes.

### Tests, gates, perf

- Unit tests: **91 in 21 suites** (was 68): index round trip, migration-safe decoding (old
  entry, unknown kind + extra fields, broken entry skipped, bare array, garbage), retention
  with a fixed clock (every setting, a day later), open entries never pruned, kind filter and
  app search, day grouping and titles, capture-path kinds, annotation document round trip
  and unknown marks, store add (folder + index, read back by a new store), edits updating
  the entry (format change, document added and removed), restore after a "relaunch" (edits
  still objects; missing files → nil), delete/undo/purge, prune, clear (stray folders too),
  missing files dropped on load, recordings (file + poster), thumbnail size, grid keyboard
  navigation across days.
- `scripts/check.sh Snapper --perf`: all PASS. Launch 143 ms, first status item 285 ms, idle
  CPU 0.004 %, footprint 23.1 MB (before history: 178 ms / 319 ms / 0.004 % / 23.8 MB).
- Capture → card, before history (test scene, 6 each): full screen 116–138 ms (median 129),
  window 123–201 ms (median 136). **After: not measured**: the display slept for the rest of
  the session and ScreenCaptureKit fails without it (−3811). By construction the card is
  shown before history is touched (`deliver` adds the card, then `history.record` only
  builds a value and starts a background task; all encoding and disk writes are on the
  `HistoryStore` actor).
- Installed: `ditto build/Snapper.app /Applications/Slopapp/Snapper.app`, `lsregister -f`
  on it and `-u` on the build copy, relaunched. Defaults restored to the round's backup.

### Not done (and why)

The display was asleep from 00:54 on, so these need someone at the Mac or the next agent:
on-screen screenshots of the History window (only offscreen renders), capture → card latency
after, `scripts/drive tree` for `[unlabeled]` controls in the new window and Settings pane,
a real drag from a card / the editor / History into Finder (owner-presence gate), Quick Look,
the menu bar menu's new item, and active-window (accent) selection in History. The ready
script is `/tmp/slopapp-polish/snapper/tools/histui.sh` (latency, both modes, tree, menu).
"Hide from screen sharing" doesn't exist in Snapper, so there was nothing to keep unchanged.

## QR codes on the thumbnail (2026-11-09)

Owner request: when a capture contains a QR code, show its content under the floating
thumbnail.

### What was built

- `SnapperCore/Text/CodeReader.swift`: `VisionCodeReader` (Vision `VNDetectBarcodesRequest`,
  QR and Micro QR, on-device) behind `CodeReading`; `ScannedCodes.unique` (reading order, no
  duplicates or blanks, at most 3); `ScannedCode.link` (only a single http(s) URL with a host
  is a link) and `displayText` (whitespace collapsed; a link without `https://`, so the site
  leads and survives truncation). Captures over 60 MP aren't scanned.
- The card scans its capture after it appears (the card never waits), then grows by one row
  per code under the thumbnail: QR glyph, the text (a link on one line, other text on two;
  the full text on hover), Open for a link, Copy. Buttons are the card's corner buttons, at
  the same inset, so the bottom ones stay concentric with the card's corners. The right-click
  menu also gets "Open <host>" and "Copy QR Code “…”". Hovering the row holds auto-close but
  doesn't dim the capture or show its buttons.
- A scan of an older version of the capture is dropped, and edits clear the codes (a blurred
  code mustn't keep showing its content). Settings → Quick Access → "Show QR code contents"
  (on) turns it off for open cards too.

### Decisions

- **Open is http(s) only.** A code on screen is untrusted; `tel:`, `x-apple…:`, `file:` and
  custom schemes can launch apps or act without a browser in between. They're copy-only.
  Test mode never opens a browser.
- The link is shown without its scheme but otherwise in full (no shortening services, no
  fetch), so the host is what people read first.

### Verified

- Unit tests: link rules (10 non-links incl. `javascript:`, `file:`, bare domains), display
  text, dedupe/cap, and Vision reading two generated codes top to bottom.
- Offscreen render (`snapshotCardCodes` hook, no window on screen): the test pattern (now with
  a QR code) through the real reader found `https://example.com/slopapp-test`; one and two
  codes at 160 and 240 pt, light and dark. Fixed from them: links wrapped inside the domain
  at 160 pt (now one line, and the glyph is dropped below 200 pt).
- Not yet looked at on screen with the real glass (the owner was at the Mac).
