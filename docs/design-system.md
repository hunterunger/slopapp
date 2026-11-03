# Slopapp design system

Every Slopapp app follows these rules. They're decided up front so each new app is a
layout choice, not a design project. SlopKit (`apps/SlopKit`) implements most of them;
run `swift run --package-path apps/SlopKit SlopKitGallery` to see every component.

The goal: each app should feel like Apple shipped it as a small utility. Take cues from
how the best Setapp utilities *behave* (Paste's instant panel, CleanShot's quick-access
thumbnail, Sip's one-keystroke picker, Squash's drop-and-done window, OpenIn's
pick-a-browser popup). Don't copy how they *look*: no names, icons, copy, or signature visuals.

## 1. Principles

1. **Native first.** SwiftUI, with AppKit where SwiftUI falls short (floating panels,
   status items, event taps). Standard controls and system materials only, so apps pick up
   each macOS release's look for free (Liquid Glass on macOS 26+). No custom-drawn chrome,
   no web views, no brand colors in the UI.
2. **The user's accent color, not ours.** Use `.tint`/`Color.accentColor`. The brand shows
   up in exactly two places: the app icon and the About view.
3. **One job, instantly.** The main action is one shortcut or one drop away. Opening,
   acting and dismissing should take under a second and need no mouse.
4. **Quiet by default.** No onboarding tours, no badges, no "what's new" sheets, no sounds
   except system ones, no notifications unless the user asked for the result.
5. **Fast and light.** See the budgets in section 8. A utility that costs battery is broken.

## 2. App archetypes

Pick one per app (an app can add a second, e.g. a menu bar app with a library window).

### a. Menu bar utility (Awake, Zones, Dropper, Clips)
- `MenuBarExtra` with an SF Symbol that shows state (outline = idle, `.fill` = active).
- `.menuBarExtraStyle(.menu)` for lists of actions and toggles. `.window` only for rich
  content (a calendar, a chart). Fixed width 320 pt, no scrolling below 480 pt tall.
- Menu order: status line (if any) → main actions → options → `MenuFooter`
  (Settings…, About, Quit).
- `LSUIElement` (no Dock icon). The icon can be hidden in Settings; launching the app again
  brings it back (`SlopAppDelegate` does this).

### b. Drop-in utility window (Squish, Convert, Iconsmith, Crate)
- One `Window` scene (not `WindowGroup`), compact (about 520×420), resizable.
- Empty state is a big `DropZone` filling the window: symbol, one line ("Drop images
  here"), "or click to choose". `⌘O` does the same.
- After a drop: a queue list, one row per file: thumbnail/icon, name, before → after,
  per-item progress, a Reveal in Finder button. The drop zone stays usable as a slim strip.
- SlopKit's `FileQueue` + `FileQueueView` do all of the above (parallel, cancel/retry, folders,
  dedupe); the app only writes a `FileProcessor`. Squish is the reference; see the gallery.
- Options sit in a bottom bar or the toolbar, never in a modal before the work starts.
  Good defaults; the user should rarely open Settings.
- Closing the window quits the app (`SlopAppDelegate`).

### c. Browser/library window (Specimen, Tidy, Clips history)
- `NavigationSplitView`: sidebar of sources/filters, content list or grid, optional detail.
- Toolbar search (`.searchable`), `⌘F` focuses it. Sort and view options in the toolbar.
- Selection works with the keyboard (arrows, `⌘A`, Space for Quick Look where relevant).
- Empty states use `ContentUnavailableView` with one action.

### d. Overlay/HUD (Switchboard picker, Snapper quick-access, Clips panel)
- `FloatingPanel`: non-activating (the app you were in keeps focus), system material,
  rounded, shadowed.
- Placement: near the mouse for choosers, a screen corner for post-action thumbnails,
  center of the active screen for search panels.
- Keyboard first: arrows move, Return confirms, **number keys 1–9 pick directly**, Esc
  dismisses. Clicking outside dismisses.
- Shows within one frame of the trigger. No entrance animation longer than 150 ms.
- Small confirmations ("Copied") use `HUD`, never an alert.
- Screen tools (Snapper, Ruler, Dropper, Snip) use SlopKit `Capture/`: `RegionOverlay` (frozen screen on every display, area/window picking, magnifier `LoupeLayer`), `ScreenCaptureKitCapturer` + `FrozenDisplay`/`PixelBuffer` (per-display scale, raw pixels), `SelectionGeometry`/`ScreenCoordinates`/`WindowPicker`, and `PrivacyMask` so test-mode captures contain only the test scene.

### e. Document app (Paper)
- AppKit's document architecture (`NSDocument` + `NSDocumentController`, Info.plist
  `CFBundleDocumentTypes` with `NSDocumentClass`), not SwiftUI's `DocumentGroup`: it gives
  Open Recent, autosave in place with Versions (Revert To), Duplicate/Rename/Move To, window
  tabs and state restoration for free. SwiftUI is used inside: sidebar, bars, sheets, Settings.
- Many windows, one per document. Closing the last window does **not** quit, so the app
  can't use `SlopAppDelegate` as is (it quits window apps); use a small app delegate with
  `applicationShouldTerminateAfterLastWindowClosed` returning false and the About/Settings
  actions. Launching with nothing to open shows the Open panel (like TextEdit), no welcome window.
- Register document types with `LSHandlerRank` = `Alternate`: show up in Open With, never
  take over a file type. Becoming the default app is a button in Settings, never a prompt.
- Window: unified toolbar (one row), `NSSplitViewController` with a sidebar item, content
  pinned below the safe area. Notices are slim info bars above the content, never alerts.
- Every edit goes through the document's `UndoManager` (undo names match menu titles), so
  "Edited", autosave and Revert To just work. Destructive transforms (redaction,
  flattening) write **new files** by default; replacing the original takes a second
  confirmation and keeps the old version in Revert To.
- The window frame persists; new windows cascade; `tabbingMode = .automatic` follows the
  person's "Prefer tabs" setting.

## 3. Standard pieces every app has

- **Settings** (`⌘,`): a `Settings` scene built with `SlopSettings`. Tabs, in order:
  General (Launch at login; menu bar apps: Show in menu bar), Shortcuts (only if the app
  has global shortcuts), Advanced (only if needed), About. Forms use `.formStyle(.grouped)`
  at 480 pt wide.
- **About**: `AboutView` (icon, name, tagline, version, "Part of Slopapp", source link).
  Menu bar apps open it from the menu; window apps from the app menu; all apps in the
  About tab.
- **Global shortcuts**: `KeyboardShortcuts` (re-exported by SlopKit) with `ShortcutRow` in
  the Shortcuts tab. Ship sensible defaults only when they won't collide with macOS
  (prefer ⌃⌥ or ⌥⇧ combos), otherwise leave them unset and show the recorder on first use.
- **Permissions**: `PermissionGate` only on the screen that needs the permission, the first
  time it's needed. One sentence on why, a button that opens the exact System Settings
  pane, live re-check (no restart unless macOS requires it, then offer a Restart button).
- **Quit**: `⌘Q` always works, including from menu bar menus.

## 4. Layout and type

- **Spacing**: 8 pt grid via `Spacing` (`xs 4, s 8, m 12, l 16, xl 20, xxl 24`).
  Window content margins 20. Space between groups 12–16. Inside a row 8.
- **Type**: system text styles only (`.title2`, `.headline`, `.body`, `.callout`,
  `.caption`). No custom fonts, no fixed point sizes except in icons. Numbers that change
  (timers, sizes, percentages) use `.monospacedDigit()`.
- **Color**: semantic only: `.primary`, `.secondary`, `.tertiary`, accent, and system
  red/orange/green for status. Never hardcode hex in an app.
- **Symbols**: SF Symbols inside apps, `.symbolRenderingMode(.hierarchical)` by default.
  Never in the app icon (see brand/BRAND.md).
- **Motion**: under 250 ms, ease or `.snappy`. Honor Reduce Motion (`accessibilityReduceMotion`):
  replace movement and scale with a fade.
- **Windows**: remember size and position (SwiftUI does for scenes). Don't center a window
  the user moved.

## 5. Writing

- Capitalization follows Apple's HIG. **Title case** for menu titles, menu items, buttons,
  window titles and Settings tabs ("Turn Off", "Choose Files…", "Move to Trash").
  **Sentence case** for toggle/checkbox labels, form rows, descriptions and body text
  ("Launch at login", "Show in menu bar", "Drop images here").
- Buttons are verbs: "Convert", "Move to Trash", "Choose Files…". Use "…" when the button
  asks for more input.
- No exclamation marks, no "Oops", no jokes in the UI (the joke is the brand name only).
- Errors say what happened and what to do next: "Couldn't read photo.heic. It may be
  damaged. Try exporting it again from Photos."
- Numbers with units: "4.2 MB", "−63%", "15 min left".

## 6. Keyboard and menus

- Every action is in a menu (the app menu bar or the menu bar extra) with its shortcut,
  so it's discoverable and VoiceOver-reachable.
- Standard shortcuts mean the standard thing: `⌘,` Settings, `⌘O` open/choose, `⌘W`
  close, `⌘Q` quit, `⌘F` search, `⌘C` copy result, `⌘Z` undo, Space Quick Look, Esc cancel.
- Focus is visible and logical; Tab moves through controls in reading order.

## 7. Privacy and data

- **No network** unless a feature needs it, it's off by default, and the README says so.
  No analytics, telemetry, crash reporters or accounts.
- Data lives in `AppPaths.applicationSupport` (`~/Library/Application Support/<bundle id>`).
  Preferences in `UserDefaults`. Nothing outside the user's home without asking.
- Destructive actions move items to the Trash (`FileManager.trashItem`) and support undo
  where possible. Ask for confirmation only when it can't be undone.
- Respect `org.nspasteboard.ConcealedType` / `TransientType` when reading the clipboard.

## 8. Performance budgets

Checked by `scripts/perf.sh` against a release build. Memory is the footprint, not RSS:
RSS counts shared system frameworks, so every SwiftUI app shows ~85 MB.

| Metric | Menu bar utility | Window app |
|---|---|---|
| Launch to running | < 300 ms | < 300 ms |
| First window / menu bar icon | < 600 ms | < 600 ms |
| Idle CPU (lowest of 3 × 5 s windows) | < 0.2% | < 0.2% |
| Idle memory footprint (Activity Monitor's "Memory") | < 50 MB | < 120 MB |

- No polling faster than the data changes; prefer notifications, KVO, FSEvents, dispatch
  sources. If you must poll (pasteboard), use the slowest interval that feels instant
  (≈ 0.5 s) and stop when not needed.
- Heavy work (image encoding, hashing, file scans) runs off the main actor, cancellable,
  with progress. The UI never blocks.
- Load lazily: don't build windows, caches or thumbnails until they're shown.

## 9. Dependencies

Apple frameworks first. A third-party SwiftPM package is allowed when it saves real work,
is actively maintained, permissively licensed (MIT/BSD/Apache), and pinned to an exact
version. Approved so far:

| Package | Version | Why |
|---|---|---|
| [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | 1.10.0 (exact) | Global hotkeys + recorder UI, sandbox-safe, used by hundreds of Mac apps. Re-exported by SlopKit. |

Add new ones to this table with the reason.

## 10. Review checklist

Grade each item pass/fail. QA and the blind test use this list.

1. The main job works in one shortcut, click or drop, with no setup.
2. Looks native: standard controls, system materials, user's accent color, no hex colors,
   no custom fonts. Light and dark mode both look right.
3. Every action is reachable from the keyboard and appears in a menu with its shortcut.
4. Esc dismisses panels/sheets; `⌘,` opens Settings; `⌘Q` quits; standard shortcuts behave.
5. Settings has General (Launch at login, menu bar visibility if relevant) and About.
6. Copy follows HIG capitalization (title case menus/buttons, sentence case labels/body), plain words, verb buttons, no exclamation marks; errors say what to do.
7. Empty states explain themselves with a symbol and one line, plus one action.
8. Permissions are asked only when needed, with one-sentence reason and a working
   System Settings link; the screen updates when granted.
9. Nothing destructive happens without undo or Trash.
10. No network traffic (check with Little Snitch/`nettop`) unless an opt-in feature needs it.
11. Within the performance budgets (section 8).
12. VoiceOver can name every control (no unlabeled icon buttons).
13. Reduce Motion: no sliding or scaling animations.
14. Window size/position persist; the app relaunches in a sensible state.
