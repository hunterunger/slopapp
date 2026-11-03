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

