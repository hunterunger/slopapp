# Snapper

Screenshots, annotated and shared in seconds.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to CleanShot X.

**Status:** beta 0.2.0 (v1 complete, two blind-test rounds, parity pass)

## What it does

- **All-in-One** (⌥⇧⌘5): a bar with every capture kind (area, full screen, window,
  scrolling, timer, text, recording); click one or press its number.
- **Capture an area** (⌥⇧⌘4): the screen freezes and dims, the pointer becomes a crosshair
  with a magnifier, and a readout shows the size. Drag to capture. Shift makes it square,
  Option grows it from the center, hold Space while dragging to move it, arrow keys nudge
  the pointer (Shift: 10 pt), Return takes the whole screen, Esc cancels.
- **Capture a window** (Space during an area capture, or the menu): click the highlighted
  window. It's captured on its own, even if covered, with a soft shadow on transparency, or
  on a gradient backdrop with padding (Settings → Screenshots → Background).
- **Capture the full screen** (⌥⇧⌘3) under the pointer, or **the previous area** again.
- **Self-timer**: pick an area (Return: whole screen), a countdown runs (3, 5 or 10 s), then
  it's captured fresh, so menus and hover states can be caught.
- **Scrolling capture**: pick the scrolling part of a window, press Start, scroll down at
  your own pace, press Done. One tall image, stitched as you go, with a live preview.
- **Capture text** (⌥⇧⌘2): pick an area and its text is copied (on-device text recognition,
  line breaks kept or not; words spread along one line stay on one line). Also "Copy Text"
  on any thumbnail and in the editor.
- **Record the screen** (⌥⇧⌘6): pick an area or window, then Record Video (Return) or
  Record GIF (⌥Return). A small bar shows the time with Stop, Pause and Discard; the rest of
  the screen dims (optional), and the record shortcut or the menu bar icon stops it. Videos
  are H.264 MP4 (15–60 fps, cursor optional); any video can be exported as a GIF later.
- **Sound, camera, clicks and keys** in recordings, from the record bar (and Settings →
  Recording): pick a **microphone** (its symbol fills with your voice level), record the
  **computer's sound**, or both (mixed into one track when you stop). Show your **camera**
  in a round or rounded bubble that's part of the video: drag it anywhere, drag its edge,
  pinch or scroll to resize it, right-click for sizes and the shape. **Show clicks** draws a
  ring where you click; **Show keystrokes** puts the shortcuts you press (or, if you choose,
  all keys) in a caption at the bottom. All off until you turn them on; GIFs are silent.
- **Trim a video**: Trim on its thumbnail (or ⌘E) opens it with the Mac's own trimming bar
  under the picture. Drag the handles, press Trim (or Return): the part you keep is copied without re-encoding, and the
  thumbnail and history get the shorter video. "Restore Untrimmed Recording" in the
  thumbnail's menu undoes it.
- After each capture a **thumbnail** appears in a bottom corner. Hover it: Copy and Save in
  the middle, Close and Pin in the top corners, Annotate and Share in the bottom ones
  (⌥-click Save: Save As…). Drag it straight into another app; right-click for more (Copy
  Text, Show in Finder, Export as GIF…). Thumbnails stack up from the corner, can close by
  themselves, and their size is adjustable. Closed one too soon? **Reopen Last Capture**.
- **QR codes**: when a capture contains a QR code, its text appears under the thumbnail
  with Copy, and Open for a web link (http and https only; anything else is copy-only).
  Read on this Mac, after the thumbnail appears, so captures never wait for it. Up to three
  codes per capture; Settings → Quick Access turns it off.
- **Annotate**: every tool in the title bar: crop, background, select, rectangle, filled
  rectangle, ellipse, line, arrow, text, pencil, highlighter, blur/pixelate, spotlight and
  numbered steps, with colors and line widths. The **Background** tool puts the capture on a
  gradient or color with padding, rounded corners and a shadow. Select, move, resize,
  duplicate (⌘D), copy and paste objects (⌘C/⌘V), delete, undo/redo. A bottom bar has the
  zoom, a drag handle to drop the result into another app, and Share, Pin, Copy and Save.
  Save As… (PNG, JPEG or HEIC), Print (⌘P), Done. Closing keeps your edits and undo history.
- **Capture History**: every capture is kept for a month (Settings → History: Off, 1 Day,
  1 Week, 1 Month, Forever), with its edits still editable. Capture History… in the menu
  (or a shortcut, or `snapper://open-history`) shows them as thumbnails by day, newest first:
  filter by kind, search by the app they came from, then Restore the thumbnail, Annotate, Pin,
  Copy, Save As…, Show in Finder, Quick Look (Space) or Delete (⌫, undoable while the window
  is open). Drag one or many straight into another app. Reopen Last Capture uses history, so
  it works after a relaunch too.
- **Pin** a capture: it floats above every window. Drag to move, drag an edge or pinch to
  resize, 1–9 and 0 set the opacity, arrow keys nudge, right-click for more, Esc closes.
  Rounded corners, shadow and border are settings.
- **Desktop icons** are left out of captures (on by default), without touching Finder.
- Annotate or pin an image from the clipboard or from a file, or open any image with
  Snapper (Finder ▸ Open With).
- **File names** follow a template ("{type} {date} at {time}" by default; Settings →
  Advanced).
- Every command is also in the app's own menus whenever a Snapper window is open, for when
  the menu bar icon is hidden behind the notch or a full menu bar: open Snapper again
  (Finder, Spotlight) and Settings opens with those menus. Snapper says so once if macOS
  had no room for its icon.
- Edited images are never lost on quit: with History on they're kept there (edits
  included, even for an opened file); with History off, Snapper asks first.

## Keyboard

| Where | Keys |
|---|---|
| Anywhere | ⌥⇧⌘5 All-in-One, ⌥⇧⌘4 area, ⌥⇧⌘3 full screen, ⌥⇧⌘2 text, ⌥⇧⌘6 record (again: stop). Window, previous area, scrolling, self-timer, toggle desktop icons, pin file, reopen last capture, close all thumbnails and Capture History can get shortcuts in Settings → Shortcuts |
| Selecting | Space area/window, Shift square, Option from center, arrows nudge, Return whole screen / highlighted window, Esc cancel |
| All-in-One bar | 1–7 pick a mode, Esc close |
| Recording | Return record video, ⌥Return record GIF, Esc cancel (before recording) |
| Scrolling capture | Return start / done, Esc cancel |
| Thumbnail (after clicking it) | ⌘C copy, ⌘S save, ⇧⌘S save as, ⌘E annotate (a video: trim), ⇧⌘P pin, ⌘W or ⌫ close |
| Trimming | Return trim, Esc cancel, Space play, arrows step |
| Editor tools | V select, R rectangle, F filled rectangle, E ellipse, L line, A arrow, T text, D pencil, M highlighter, P blur/pixelate, H spotlight, C counter, K crop, B background; ] / [ line width (= / − too) |
| Editor | ⌘C copy object (or the image), ⌘V paste object, ⌘D duplicate, ⇧⌘C copy image, ⌘S save, ⇧⌘S save as, ⌘P print, ⇧⌘P pin, ⌘= / ⌘− / ⌘0 / ⌘9 zoom, pinch or ⌘-scroll zoom, scroll pans, ⌫ delete, arrows move, ⌘Z / ⇧⌘Z, Return applies a crop, ⌥Return new line in text |
| Capture History | arrows move, ⇧-arrows extend, ⌘A select all, Return restore, double-click or ⌘E annotate, Space Quick Look, ⌘C copy, ⇧⌘S save as, ⇧⌘P pin, ⌘R show in Finder, ⌫ delete, ⌘Z undo |
| Pin | Esc close, 1–9/0 opacity, arrows move, ⌘= / ⌘− zoom, ⌘0 actual size, ⌘C copy, ⌘S save, ⌘E annotate |

The defaults use the digits people know from other screenshot tools with an extra ⌥, so
they stay clear of macOS's own shortcuts (⇧⌘3/4/5, ⌃⇧⌘3/4) and of those tools.

**URL commands** (for launchers and scripts): `snapper://open-history`,
`snapper://restore-recently-closed`, `snapper://capture-area`, `…/capture-previous-area`,
`…/capture-full-screen`, `…/capture-window`, `…/scrolling-capture`, `…/self-timer`,
`…/capture-text`, `…/record-screen`, `…/all-in-one`.

## Permissions

**Screen Recording**, to take screenshots and recordings. Snapper asks the first time you
capture, with a button to the right System Settings pane; macOS applies it after Snapper
restarts. Only when you turn them on for a recording: the **Microphone** and the **Camera**
(macOS asks the first time; if they're off, Snapper says where to turn them on and records
without them), and **Accessibility** for Show keystrokes (to see keys pressed in other
apps). Clicks and computer sound need nothing more than Screen Recording.

## Privacy

No network, no accounts. Text recognition runs on your Mac. The microphone and camera are
on only while a recording is set up or running, and go nowhere but the recording. Pressed
keys are shown on screen and never logged or kept.

**Capture History** keeps each capture in its own folder in
`~/Library/Application Support/app.slopapp.snapper/History/`: the image (or recording), the
unedited original, your edits, and a small `index.json` with the date, kind, size and the
app it came from (its name and bundle id; never window titles, which can be private). It
stays on this Mac. Captures older than the time you pick are deleted at launch and every
hour; Delete in the History window removes a capture's files (undo works until the window
closes), and Settings → History → Clear History… removes them all. To keep nothing, set
Settings → History → Keep captures to **Off**: captures then live only in memory and in a
temporary folder that's emptied when Snapper quits, until you copy, save, drag or share
them.

## Not there yet

Auto-scrolling for scrolling capture, editing a video beyond trimming (cuts in the middle,
zoom), a camera-only recording, cloud upload (left out on purpose).

## Develop

```sh
scripts/test.sh Snapper     # unit tests
scripts/run.sh Snapper      # build a debug .app and open it
scripts/check.sh Snapper    # the full gate: tests, release bundle, launch smoke test
```

Logic lives in `Sources/SnapperCore` (tested). Views and wiring live in `Sources/Snapper`.
The capture overlay, screen capture service and geometry come from SlopKit
(`SlopKit/Capture`). Candidates to move there next: `ScrollStitcher`, `RecordingPlan` +
`StreamRecorder`, `GIFEncoder`, `TextRecognizer`, `RegionFrame`/`Countdown` and the
sidebar Settings layout, `RecordingSink` + `RecordingTimeline` + `MediaEditor`, and the
camera/microphone permission pieces (`MediaKind`, `MediaPermissionWindow`).

Test hooks (environment variables, all off by default): `SNAPPER_SAVE_DIR`,
`SNAPPER_HISTORY_DIR` (Capture History lives there instead),
`SNAPPER_TEST_SCENE=1|full` (captures then contain only a generated test pattern:
every capture is filtered to the scene window *and* masked to its frame minus the menu bar,
so nothing else on screen can end up in a test capture),
`SNAPPER_TEST_HOOKS=1`, `SNAPPER_LOG`, `SNAPPER_APPEARANCE`, `SNAPPER_SILENT`,
`SNAPPER_PASTEBOARD=<name>` (Copy goes to a private pasteboard, never the real clipboard),
`SNAPPER_DEFAULTS_SUITE=<name>` (settings in their own suite, and Snapper's default shortcuts shown instead of the installed copy's), `SNAPPER_TEMP_DIR`,
`SNAPPER_NO_SHORTCUTS=1` (a test copy never touches an installed copy's settings, temporary
folder or hotkeys), `SNAPPER_FAKE_MEDIA=granted|denied|undetermined` (a generated test
camera and a tone as the microphone; always on in test mode, so a test recording never
opens a real camera or microphone), `SNAPPER_FAKE_ACCESSIBILITY=granted|denied`,
`SNAPPER_TEST_REAL_INPUT=1` (show real clicks and keys in test mode).
Test mode covers every capture kind: self-timer and scrolling captures use the same filtered,
masked snapshots; recordings stream only the test scene window, clipped to the selection
inside it, and refuse anything else. See `Sources/Snapper/Diagnostics.swift`.

### Store screenshots

`scripts/shots.sh Snapper` takes the set listed in `showcase.json` (scenes in
`Sources/Snapper/Showcase.swift`, all made-up content) and writes `web/public/shots/snapper/`. See
[docs/screenshots.md](../../docs/screenshots.md).
