# Dropper research (inspired by Sip)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied on
> 2026-11-03: **Sip 5.1.1 (511)** (Setapp build, /Applications/Setapp/Sip.app, read-only),
> its help center (docs.sipapp.io) and changelog, Setapp listing and reviews, plus two
> alternatives people move to (Pika, System Color Picker) for contrast. We study how it works
> so we don't reinvent the wheel. We never copy its name, icons, artwork, wording, sounds or
> signature visuals.
>
> What was looked at: the app's bundled configuration (format list, default hotkeys, per-app
> presets), the main menu, the status item (icon only), all ten Settings panes (switched with
> the sidebar's arrow keys; one popup and one format-options popover opened and closed with
> Esc; nothing toggled), and the picker's window structure (opened with Sip's own `sip://picker`
> URL, no screenshot, no color picked, closed by quitting). Sip was not running before and was
> quit afterwards; its preferences were checked unchanged. **Not opened**: the status panel
> (history, palettes, contrast checker; its custom status item ignores Accessibility presses
> and mouse clicks aren't allowed), the main window, the Color Dock contents, Cloud account
> state, snapshot list.

## The job

A designer or developer sees a color on screen (in a mockup, a website, a screenshot, a video
frame, another app) and needs its exact value, typed out in the syntax of whatever they're
writing right now: `#3366CC` for CSS, `Color(red:green:blue:)` for SwiftUI, `UIColor(...)` for
an iOS project. They also want to check that two colors are readable together, and keep the
handful of colors they're working with nearby. Done feels like: shortcut, click, it's already
on the clipboard in the right format, and it's the same value the design file has.
**The one interaction that matters: press a shortcut → the cursor becomes a magnifier → click
a pixel → the value is on the clipboard in your format, with a small confirmation.**

## Who and when

- Building a UI from a static mockup or screenshot: pick each color, paste into CSS/Swift.
- Matching a brand color from a live website or PDF.
- Checking accessibility: is this gray text on this background AA? (pick both, read the ratio).
- Re-using a color picked five minutes ago (history), or the five brand colors of a project
  (palette).
- Converting a value someone sent ("#3366CC, but I need it as SwiftUI").

Frequency: bursts of many picks during UI work (10–50 in an hour), then nothing for days.
Each pick is 1–5 s; a contrast check is 10–30 s.

## Picking engine: NSColorSampler vs Snapper's capture overlay

The brief asks to weigh both. Summary first, details after.

| | **NSColorSampler** (system) | **Own overlay** (reuse Snapper `Capture/`) |
|---|---|---|
| Permission | None. Runs out of process; works on a fresh Mac with zero prompts. | Screen Recording. First use needs a grant and a relaunch (`Permission.screenRecording.needsRelaunchAfterGrant`); macOS 15+ also re-confirms screen-capture apps periodically. Reviews of Sip complain about its Screen Recording behavior. |
| Time to loupe | Instant (system UI). | Overlay shows in a frame (Snapper measured); frozen image swaps in ~50–100 ms later. |
| Magnifier | The system loupe: round, pixel grid, fixed size/zoom. Not customizable. Space shows RGB numbers (per the System Color Picker FAQ); it can't show hex or our format. | Snapper's `LoupeLayer` (21×21 pixels at 6 pt, center pixel outlined, point readout). We can add a live value readout in the chosen format, +/− zoom, and size. |
| Precision | Pixel under the pointer. Arrow-key nudging: **unverified**, test in build. | Arrow nudge exists in Snapper (1 pt, ⇧ 10 pt). On 2× displays 1 pt = 2 pixels, so Dropper needs a 1-pixel step (0.5 pt). Reads the exact pixel from a frozen image, so what you see is what you get. |
| Multi-display | Handled by the system. | One panel per display already (Snapper). Each display may have a different color space; convert per display. |
| Color accuracy | Returns an `NSColor`; expected to be tagged with the display's color space (**verify in build**), which we convert with ColorSync (`usingColorSpace`). | We read the raw pixel from the capture. Snapper doesn't set `SCStreamConfiguration.colorSpaceName`, so the builder must either set it explicitly or read the `CGImage.colorSpace` and convert. Read the pixel without letting Core Graphics color-match it on the way (copy bytes, or draw 1×1 into a context with the image's own color space). |
| Extras it enables | Simple: one color per invocation (we can re-open it for multi-pick). | Live value readout, Shift-click to keep picking, pick a contrast pair in one overlay, average 3×3/5×5, hover states frozen at trigger time. |
| Memory / code | ~0 extra; a few lines. | Tens of MB transient while the overlay is up (released after); ~1,000 lines already written, but they live in Snapper and need moving to SlopKit first. |

**Recommendation:** v1 picks with **NSColorSampler** (matches the roadmap spec; the main job
works with no setup and no permission, design-system rule 1). We wrap it with our own result
HUD and formats. The **precise picker** (own overlay with live readout, pixel nudge,
zoom, multi-pick) is a **should** for v1.1, opt-in from Settings ("Use precise picker"), asking
for Screen Recording only when switched on, built on Snapper's `Capture/` once it moves to
SlopKit. Ruler (PixelSnap) needs the same move, so it's not wasted work. See Open questions.

### Color spaces (accuracy matters)

- What's on screen is in the **display's** color space (built-in Retina displays: Display P3-ish
  "Color LCD"; many externals: sRGB-ish; calibrated profiles are anything). A web page's
  `#FF0000` (sRGB) is stored on a P3 panel as roughly P3 (0.92, 0.20, 0.14).
- Sip defaults to **Display Native**, which reports those raw panel numbers. That's why a P3
  MacBook gives "wrong" hex for web colors, and very likely behind the "color was inaccurate,
  had to use Photoshop" review. Its per-app "Smart Profiles" (sRGB for Safari/Chrome, Display
  Native for Xcode) are off by default.
- **Ours:** convert every pick from the display's space to an **output space**. Default
  **sRGB** (matches CSS hex, Figma, most tools, round-trips web colors). Option **Display P3**
  (for P3 asset catalogs, `color(display-p3 …)`, SwiftUI/UIKit P3 initializers). "Display
  native" only as an Advanced debugging option, if at all.
- When a picked color is outside sRGB (vivid P3 content), hex/rgb are clamped; show a small
  "Outside sRGB" note next to the value and offer the P3 formats.
- 8-bit framebuffer + conversion can land ±1 per channel off the authored value (e.g. `#FE0000`
  for `#FF0000`). Test with known swatches; document the tolerance; never "snap" silently.
- Night Shift and True Tone are applied after the framebuffer and don't affect sampled values.
- HDR/EDR content brighter than SDR white clips to 1.0.

## Feature inventory

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Global shortcut opens the picker | ⌃⌥⌘P (the only global shortcut enabled by default); also `sip://picker`, the status item's left half, the panel toolbar | must | `KeyboardShortcuts`, default proposed ⌥⇧C (see Menus and shortcuts / Open questions). Menu item "Pick Color" shows it. |
| 2 | Loupe picker | Own full-screen-ish 800×800 overlay window centered on the pointer, round magnifier with pixel grid and the color code under it (Settings: show code on, name off); needs Screen Recording | must (system loupe) / should (own precise loupe) | See "Picking engine". |
| 3 | Nudge 1 px / 10 px with arrows, ⇧ for 10 | Picker shortcuts, rebindable | should | Comes with the precise picker; check whether the system sampler supports arrows. |
| 4 | Picker size and zoom | + / − size, ⌥+ / ⌥− zoom, two-finger swipe; Settings sliders (5 steps; seen at step 2) | later | Precise picker only. |
| 5 | Click copies + adds to history | Copy in the selected format; adds to history and to the selected palette; plays a sound (on) | must | Copy at once, `HUD` "Copied #3366CC" with a swatch. System sound off by default (design system: quiet). |
| 6 | Esc cancels | Yes | must | |
| 7 | ⌘ while picking shows a mode menu (single, multiple, contrast, send to app) | Hold ⌘ in picker | skip | Hidden; replaced by explicit menu items (Pick Color, Pick Contrast Pair) and ⇧-click to keep picking (precise picker). |
| 8 | Pick multiple colors in one go | Via the ⌘ mode menu | should | NSColorSampler: re-open after each pick while ⇧ was held at the click. |
| 9 | Format choice | A format selector under the panel toolbar; 28 built-in formats in groups (see "Formats"); enable/disable each in Settings | must (7 formats) | One default format, chosen in the menu ("Copy Format" submenu) and Settings. |
| 10 | Copy last color as any format | Panel shows values; right-click/copy | must | "Last Color" section in the menu: one item per enabled format, click copies. |
| 11 | Format options | Per format: All caps, Show prefix #, Remove white spaces | should | Hex: uppercase (on), `#` prefix (on). CSS: legacy commas vs modern spaces. |
| 12 | Custom formats | Template editor with separate clipboard / menu / picker strings; duplicate a built-in; export `.format` | later | Template strings like `{r255}, {g255}, {b255}` are cheap later. |
| 13 | Smart Formats (per-app format) | Off by default; presets VS Code → CSS Hex, Xcode → Swift UIColor RGB | later | Nice: pick in Xcode, get Swift. Needs frontmost-app tracking only. |
| 14 | Color profile | Display Native (default), Display P3, sRGB IEC61966-2.1, Generic RGB, Adobe RGB | must (sRGB / Display P3) | Default sRGB. See "Color spaces". |
| 15 | Smart Profiles (per-app profile) | Off; presets Chrome/Safari → sRGB, Xcode → Display Native | skip | A correct conversion plus an output-space choice removes the need. |
| 16 | Color history | Undeletable "palette" at the top of the list, newest first, clear only; optional limit (off, 25 when on) | must | Newest first, de-duplicated (re-picking moves to top), cap 100, Clear History. Recent 10 in the menu. |
| 17 | Palettes | Create, name + note, add by picking while selected, drag between palettes (⌥ copies), reorder, group, sort, lock, merge, remove duplicates, duplicate, delete | should (basic) / later (rest) | Basic: New Palette, Add Last Color to palette, rename, delete, remove a color, copy any color. Lives in a small Library window. |
| 18 | Palette export / import | Export Sip palette, ASE, CLR, JSON, PDF; opens `.ase` / `.clr` / Sip files (document types) | later | Export `.clr` (Apple Color List, free via `NSColorList`) and CSS variables first. Review asked for import. |
| 19 | Contrast checker | Panel tool / ⌃⌥⌘O (off by default) / `sip://contrast/hex/a,b`; text + background, live score, Fail / AA / AAA, a Fix button that adjusts a color | must | Full WCAG 2.x breakdown (normal text, large text, UI components), swap, pick either from screen, type hex, preview. |
| 20 | Contrast "fix" | Adjusts brightness/hue/saturation to pass | should | Suggest the nearest passing color by changing lightness only (OKLCH), per target level. |
| 21 | APCA | No | later | Draft standard; Pika has it. |
| 22 | Color Panel (editor) | HEX/RGB/HSB/HSL + alpha fields, hue and opacity sliders, export/duplicate/delete; ⌃⌥⌘C (off) | later | Typing a hex into the contrast checker covers the main need. `NSColorPanel` exists for free if wanted. |
| 23 | Color names | 2,500-entry bundled name list; picker can show name (off); reviewers dislike some names | later | Our own small, plain list ("dark blue") for VoiceOver and labels. Don't reuse theirs. |
| 24 | Color blindness simulation | Normal / Protanopia / Deuteranopia / Tritanopia / Achromatopsia, applied to swatches | later | |
| 25 | Color Dock | Floating strip on a screen edge with chosen palettes; drag colors out; snaps to edges; visible in all Spaces | later | Clips/Snapper-style floating panel later. |
| 26 | Status item | Split "Extended" icon (left = pick, right arrow = panel) or "Single"; fills with last picked color (on) | must (icon) / should (tint) | `eyedropper` SF Symbol; optional small swatch of the last color. Must have an accessibility label (Sip's has none). |
| 27 | Status panel | Rich popover: toolbar (pick, contrast, new palette, color panel), palette list with history on top, bottom bar (prefs, color blindness, main window, quit) | must (as a `.menu`) | Standard menu (design system a). Rich panel not needed in v1. |
| 28 | Main window | Library of palettes and colors | should | Same as #17's Library window. |
| 29 | Send to app ("plugins") | ⌘ while picking → set primary/secondary color in Photoshop, Illustrator, InDesign, Sketch, Xcode, VS Code, Nova via AppleScript | skip | Automation permission per app, brittle. |
| 30 | Get primary/secondary color from those apps | Global shortcuts (off) | skip | Same. |
| 31 | Auto import from clipboard | Off; watches the clipboard for color strings | later | Instead: "Add from Clipboard" (parse a hex/rgb/hsl string once, on demand). |
| 32 | Cloud sync | Sign in with Apple | skip | No accounts, no network. |
| 33 | Snapshots (backups) | Schedule (seen: Day) + manual, export, reset | skip | Our data is one small JSON file; Time Machine covers it. |
| 34 | URL scheme | `sip://picker`, `contrast[/hex/a,b]`, `settings/<tab>`, `color/...`, `palette/...` | later | `dropper://pick`, `dropper://contrast?fg=&bg=` and App Intents later. |
| 35 | Launch at login | Off | must | `SlopSettings` General. |
| 36 | Sounds | Play sounds (on), own sounds | skip | Quiet by default; no custom sounds. |
| 37 | Appearance theme | Auto / Light / Dark | skip | Follow the system. |
| 38 | Onboarding / tutorials | Onboarding on first launch; first-use coach hints in the picker (command, precision, size, zoom) | skip | One-line hint in the HUD the first time is enough. |
| 39 | Reset buttons per pane | Reset Preferences / Appearance / Formats / Shortcuts / … | skip | Few settings; KeyboardShortcuts recorder has its own reset. |
| 40 | Licensing | Paddle license, 15-day trial; Setapp build | skip | |

### Formats

Sip ships 28, in groups: .NET (ARGB, RGB), Android (ARGB, RGB, XML), CGColor (CMYK, RGB),
CSS (Hex), CSS 3 (RGB, RGBA, HSL, HSLA), CSS 4 (CMYK, HWB), Java (RGB, RGBA), NSColor (RGB, HSB),
Swift NSColor (RGB, HSB), Swift UIColor (RGB, HSB), SwiftUI Color (RGB, HSB), UIColor (RGB, HSB),
OpenGL (RGB, RGBA). Default selected: CSS Hex. All enabled by default. Missing: OKLCH, LCH, LAB,
`color(display-p3 …)`, Compose/Flutter, Tailwind.

Ours (example values for sRGB 0.2, 0.4, 0.8; exact syntax is the build step's call):

| Format | Example | Priority |
|---|---|---|
| Hex (default) | `#3366CC` | must |
| CSS RGB | `rgb(51, 102, 204)` (option: modern `rgb(51 102 204)`) | must |
| CSS HSL | `hsl(220, 60%, 50%)` | must |
| HSB | `hsb(220, 75%, 80%)` | must |
| SwiftUI | `Color(red: 0.2, green: 0.4, blue: 0.8)`; P3: `Color(.displayP3, red: …)` | must |
| NSColor | `NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1)`; P3: `NSColor(displayP3Red: …)` | must |
| UIColor | `UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)`; P3: `UIColor(displayP3Red: …)` | must |
| CSS Display P3 | `color(display-p3 0.2 0.4 0.8)` | should |
| OKLCH | `oklch(53.2% 0.168 262.3)` | should |
| Android / Compose / Flutter | `#FF3366CC`, `Color(0xFF3366CC)` | should |
| Unit RGB (OpenGL) | `0.2, 0.4, 0.8` | should |
| LAB / LCH / CMYK / HWB / .NET / Java | | later |
| Custom templates | | later |

Rules: numbers always use `.` as the decimal separator regardless of locale; unit components
rounded to 3 decimals with trailing zeros trimmed (`0.2`, `0.333`); hue 360 wraps to 0; picks
are opaque so alpha is 1 (formats with alpha only matter for typed or edited colors, later).

## Key flows

### Flow 1: pick a color (the main job)
1. Press the global shortcut from any app (Sip: ⌃⌥⌘P; ours: proposed ⌥⇧C). Or menu bar
   icon → Pick Color.
2. The cursor becomes a loupe (system sampler in v1). Move to the pixel. Esc cancels.
3. Click. The value in the default format is on the clipboard; a HUD near the pointer shows the
   swatch and the copied text for ~1.2 s; the color goes to the top of History. The menu bar
   icon's swatch (if on) changes.
4. Need another format? Open the menu: the "Last Color" section lists it in every enabled
   format; click one to copy. (Sip: the panel shows the color in its selected format; switch the
   format control first.)

### Flow 2: first run
1. Sip: onboarding window on first launch (seen as completed in this install), then first-use
   coach hints inside the picker. It asks for Screen Recording because its picker captures
   the screen (its usage string says so). After a grant, macOS needs a relaunch.
2. Ours: no onboarding. Launching shows the menu bar icon. The first pick works with no
   permission (NSColorSampler). The first HUD adds one line: the shortcut and "Choose formats
   in the menu". Only the opt-in precise picker would show `PermissionGate` for Screen Recording.

### Flow 3: contrast check
1. Sip: panel toolbar → Contrast Checker (or ⌃⌥⌘O once enabled, or `sip://contrast/hex/a,b`).
   Edit text and background with fields/sliders; a live score with Fail / AA / AAA; Fix adjusts
   a color.
2. Ours: menu → Contrast Checker… (shortcut, optional global). A small window: Text and
   Background swatches, each with a hex field and a "Pick" button (⌘1 / ⌘2, proposal) that runs
   the sampler; Swap (proposal ⌘E); a preview of sample text at normal and large sizes in those
   colors; the ratio (e.g. "4.62:1", truncated, never rounded up); pass/fail rows for normal text
   AA (4.5) / AAA (7), large text AA (3) / AAA (4.5), UI components (3). Starts with the last two
   history colors. ⌘C copies the ratio summary. Should: "Suggest" the nearest passing color.
3. Should: "Pick Contrast Pair" menu item / shortcut: two picks in a row (text, then background)
   and the window opens with the result.

### Flow 4: reuse a color
1. Sip: open the panel → history (top palette) or a palette → click a color → copy.
2. Ours: menu → recent colors (up to 10) as items with a swatch image and the value; click copies
   in the default format; ⌥ (alternate item) or a submenu offers other formats. "Show All Colors…"
   opens the Library window (history + palettes) when palettes ship.

### Flow 5: save to a palette (should)
1. Sip: select a palette in the panel; every pick then also lands in it. Drag colors between
   palettes; ⌥-drag copies.
2. Ours: Library window → New Palette (⌘N), "Add Last Color" (⌘L proposal), drag from history
   into a palette, rename inline, Delete moves to an undoable removal. Export `.clr` / CSS
   variables later.

## Settings inventory

Seen in Sip 5.1.1 (values as installed; defaults cross-checked with its bundled config where
possible).

| Pane | Setting | Value seen | Options | Keep? |
|---|---|---|---|---|
| General | Start on system startup | off | on/off | yes: "Launch at login" (off) |
| General | Play sounds | on | on/off | skip (quiet; no sound) |
| General | Limit colors in history | off (25) | number | yes, fixed cap 100 instead of a setting |
| General | Auto import from clipboard (+ gear) | off | on/off | skip; on-demand "Add from Clipboard" later |
| General | Color profile | Display Native | Display Native, Display P3, sRGB, Generic RGB, Adobe RGB | yes: "Color space" sRGB (default) / Display P3 |
| General | Color blindness | Normal | 5 modes | later |
| Appearance | App theme | Auto | Auto/Light/Dark | skip |
| Appearance | Status menu | Extended (split icon) | Extended/Single | skip (one icon, one menu) |
| Appearance | Last picked color in status icon | on | on/off | should: "Show last color in menu bar" (off by default; keeps the icon a template) |
| Appearance | Picker size / zoom | step 2 of 5 each | sliders | later (precise picker) |
| Appearance | Picker overlay: color code / color name | on / off | on/off | later (precise picker shows the value always) |
| Formats | Enable each of 28 formats; per-format options (caps, # prefix, whitespace) | all on | | yes: default format + "Show in menu" per format; hex uppercase and # prefix |
| Smart Formats | Use per app | off; VS Code → CSS Hex, Xcode → Swift UIColor RGB | add/remove apps | later |
| Smart Profiles | Use per app | off; Chrome/Safari → sRGB, Xcode → Display Native | add/remove apps | skip |
| Dock | Show Color Dock / all Spaces / position / screen | on / on / Left / built-in | | later |
| Shortcuts | 5 groups, each shortcut with an enable box; only Open Picker enabled by default | | record, reset | yes: Pick Color (default set), Contrast Checker (unset), Pick Contrast Pair (unset) |
| Cloud | Sign in with Apple | not signed in view | | skip |
| Snapshots | Create snapshot | Day | Never/Minute/Hour/Day | skip |
| About | Version, Contact Us | | | yes: `AboutView` |

Ours, per the design system: **General** (Launch at login, Show in menu bar, Color space,
Default format, Hex uppercase, Show last color in menu bar), **Shortcuts**, **About**.
Formats-in-menu toggles can live in General as a list or in an Advanced tab if it gets long.

## Menus and shortcuts

**Sip.** It's an agent app (`LSUIElement`), so its main menu (standard Sip/File/Edit/Format/
View/Window/Help; File has New ⌘N, Open… ⌘O for its document types) is only visible when a
window is up. All real actions live in the status panel. Default shortcuts (bundled config +
docs; only the first is enabled out of the box):

| Action | Default | Scope |
|---|---|---|
| Open Picker | ⌃⌥⌘P | global, **on** |
| Open Contrast Checker | ⌃⌥⌘O | global, off |
| Open Status Menu / Open Main Menu | ⌃⌥⌘M / ⇧⌃⌥⌘M | global, off |
| Open Color Panel | ⌃⌥⌘C | global, off |
| Show/Hide Color Dock | ⌃⌥⌘D | global, off |
| Get Primary / Secondary Color (from design apps) | ⌃⌥⌘F / ⌃⌥⌘B | global, off |
| Pick color | click, Return or Space | picker |
| Close picker | Esc | picker |
| Nudge 1 px / 10 px | arrows / ⇧ arrows | picker |
| Picker size bigger / smaller | + / − (two-finger swipe) | picker |
| Picker zoom in / out | ⌥+ / ⌥− (⌥ swipe) | picker |

**Ours (proposal).** Menu bar menu, `.menu` style:

```
Pick Color                         ⌥⇧C   (global, rebindable)
Pick Contrast Pair                       (should; global, unset)
──────────
Last Color: [swatch] #3366CC             (status line, disabled)
  Copy as Hex / RGB / HSL / HSB / SwiftUI / NSColor / UIColor   (one item each, enabled formats only)
──────────
Recent Colors                            (up to 10 swatch items; click copies default format)
  Clear History
──────────
Copy Format ▸  (radio list of formats: sets the default)
Color Space ▸  sRGB / Display P3
Contrast Checker…                  ⌘K in-menu (proposal)
Show All Colors…                         (should: Library window)
──────────
Settings…  ⌘,    About Dropper    Quit Dropper  ⌘Q   (MenuFooter)
```

Default global shortcut: **⌥⇧C** proposed ("C" for color; follows the design system's ⌥⇧
preference; Clips uses ⌥⇧V, Snapper ⌥⇧⌘3/4/5; it does block typing "Ç" on US layouts).
Alternative: adopt Sip's ⌃⌥⌘P for muscle memory (collides only if Sip stays installed). Open
question. Contrast checker window shortcuts (proposal): ⌘1 pick text, ⌘2 pick background,
⌘E swap, ⌘C copy result, Esc / ⌘W close.

## Permissions and system integration

- **Sip:** Screen Recording (usage string: used only to sample colors). Apple Events usage
  string for its design-app plugins (asked per app when used). Login item. URL scheme `sip://`.
  Document types: `.color`, `.palette`, `.format`, `.snapshot`, `.ase`, `.clr`. Network for
  Sign in with Apple / cloud sync and license validation (Paddle).
- **Ours v1:** **no permissions** (NSColorSampler). Login item via `LaunchAtLogin`. No network.
  Data: `AppPaths.applicationSupport/colors.json` (history, later palettes); settings in
  `UserDefaults`.
- **Later:** Screen Recording only if the precise picker is turned on (asked in place with
  `PermissionGate`, relaunch offered). App Intents ("Pick Color", "Convert Color") and a
  `dropper://` URL scheme. `.clr` export via `NSColorList`.
- Clipboard: write the formatted string as plain text. Should: also put an `NSColor` on the
  pasteboard in the same write so color wells and design apps that accept colors can paste it.

## UX patterns worth adopting

- **One shortcut to a loupe, one click to the clipboard.** No window in between; the value is
  ready before your hand leaves the mouse.
- **The status icon can carry the last color**, so you can glance at what you picked.
- **Separate "how it's copied" from "how it's shown"** (Sip's format has clipboard, menu and
  picker strings). For us: the menu shows a compact value, the clipboard gets the full code.
- **Per-format small options** (caps, prefix) instead of dozens of near-duplicate formats.
- **History is always on and can't be lost by accident**; palettes are opt-in organization.
- **Contrast checker that starts from what you just picked**, with a one-click fix.
- **Nudge with arrows, ⇧ for ×10** (precise picker) and +/− to zoom: precision without the mouse.
- **Pick from where it's needed**: re-opening the picker after a pick for multi-pick sessions.

## What we won't copy, and what we'll do better

- Not copying: name, icon, droplet-shaped status icon, artwork, wording, sounds, the 2,500 color
  name list, format icons, onboarding, licensing/cloud flows.
- Doing better:
  - **Correct colors by default.** sRGB conversion by default instead of raw display values
    (the likely cause of "inaccurate color" reviews); clear Display P3 option; an
    "Outside sRGB" note instead of silent clamping.
  - **No permission to start.** The main job works on first launch with zero prompts (Sip
    needs Screen Recording; a reviewer called its Screen Recording handling strange).
  - **Simpler.** Two reviewers call Sip overcomplicated and hard to use; its Settings has ten
    panes. Ours: one menu, three Settings tabs, no hidden ⌘-while-picking mode menu.
  - **A real WCAG breakdown**: normal vs large text vs UI components, exact ratio, no
    rounding up past a threshold, swap, pick from screen. Sip's docs show only Fail / AA / AAA.
  - **Every format copyable from the menu in one click** (a reviewer left for want of a quick
    "copy the HTML code" shortcut).
  - **Modern formats** Sip lacks: OKLCH, `color(display-p3 …)`, Compose/Flutter (should).
  - **Accessible**: labeled status item (Sip's has no label), VoiceOver names colors.
  - **Locale-safe output** (always `.` decimals in code).
  - **Light**: no sync, no dock, no background capture; idle at ~0% CPU.

## Edge cases

- **Multiple displays** with different color spaces (P3 built-in + sRGB external): conversion
  uses the space of the display the pixel came from; picking across the seam works.
- **Mixed scale factors** (1× external, 2× built-in) and "looks like" scaled resolutions: the
  sampled pixel is a physical pixel; precise-picker nudge is 1 pixel, not 1 point.
- **Full-screen apps and other Spaces**: shortcut works over a full-screen app; HUD shows on the
  active Space.
- **Shortcut pressed while the sampler is already open**: ignore (don't stack samplers).
- **Esc / click outside / app switch** during picking: cancels cleanly, clipboard untouched,
  nothing added to history.
- **Protected content** (DRM video, some secure windows) may sample as black; don't crash,
  record what was returned.
- **Out-of-gamut** P3 colors when the output is sRGB: clamp, flag "Outside sRGB".
- **Rounding**: ±1 per channel after display round-trip; component formatting never shows
  `-0` or `1.0000001`; hue 360 → 0; grays have hue 0 and saturation 0.
- **Locale**: German/French decimal commas must not leak into code formats.
- **Contrast**: identical colors (1:1), black on white (21:1), ratios just under a threshold
  (4.499 shows as failing AA), colors with alpha in typed input (composite over background
  first, later), P3 colors (contrast computed in sRGB).
- **Typed hex parsing**: `#abc`, `abc`, `#AABBCC`, `aabbcc`, `#AABBCCDD`, whitespace, invalid
  input (field shows an error state, no crash); `rgb()`/`hsl()` paste later.
- **History**: empty state ("No colors yet. Press ⌥⇧C to pick one."), cap 100 with oldest
  dropped, duplicates move to top, corrupted/missing JSON file starts fresh without losing the
  app (back up the bad file).
- **Dark/light mode**: swatches get a hairline border so white-on-light and black-on-dark
  swatches stay visible.
- **Sleep/wake, display connect/disconnect** mid-pick: sampler cancels; no stale display IDs.
- **Accessibility**: VoiceOver reads each swatch as its value (and a plain hue name later);
  status item labeled; Reduce Motion for the HUD.
- **Menu bar icon hidden** (Settings): shortcut still works; relaunch brings the icon back.

## Our v1 scope

- [x] Menu bar app (`LSUIElement`), `eyedropper` icon with an accessibility label (`eyedropper.full` while picking)
- [x] Global shortcut (default ⌥⇧C, rebindable) and menu item open the system color sampler; Esc cancels with no side effects
- [x] Click copies the color in the default format and shows a HUD with swatch + value
- [x] Output color space: sRGB (default) or Display P3, converted from the sampled display's space; "Outside sRGB" flagged
- [x] Formats: Hex, CSS RGB, CSS HSL, HSB, SwiftUI, NSColor, UIColor (P3 variants when the space is P3); hex uppercase + `#` options; locale-safe numbers. Plus CSS Display P3 (a cheap should).
- [x] Menu: Last Color with one item per format (the item is the value itself); Copy Format submenu sets the default
- [x] History: persisted, newest first, de-duplicated, cap 100; recent 10 in the menu (click copies); Clear History
- [x] Contrast checker window: text + background (pick from screen or type hex), swap, preview, WCAG ratio, pass/fail for normal text AA/AAA, large text AA/AAA, UI components; starts from the last two picks
- [x] Settings: General (Launch at login, Show in menu bar, Color space, Default format, Hex options), Shortcuts (Pick Color, Contrast Checker), About
- [x] No permissions, no network; perf within menu bar budgets
- [x] Core tested: conversions (sRGB/P3, HSL/HSB), every formatter incl. locale, hex parsing, WCAG luminance/ratio/levels, history rules

Should (v1 if cheap, else v1.1): precise picker (Snapper overlay via SlopKit, opt-in, Screen
Recording) with live readout, pixel nudge, zoom and ⇧-click multi-pick; Pick Contrast Pair;
contrast "Suggest" fix; basic palettes + Library window; extra formats (CSS P3, OKLCH,
Android/Compose/Flutter, unit RGB); last color in the menu bar icon; `NSColor` on the
pasteboard.

## Decisions (owner defaults, 2026-11-03)

1. **Picking engine: NSColorSampler for v1** (no permission, instant). The precise
   own-overlay picker stays a v1.1 should, opt-in, once Snapper's `Capture/` moves to SlopKit.
2. **Default shortcut ⌥⇧C.** Sip isn't in use, so there's no muscle memory to keep. Conflicts
   are handled by SlopKit's `ShortcutRow` (KeyboardShortcuts' recorder warns about system and
   menu shortcuts). Known cost: it blocks typing "Ç" with ⌥⇧C on US layouts; rebind if needed.
3. **Palettes: should, v1.1** (not v1). History covers the "colors I just used" need.
4. **Default color space sRGB**, Display P3 as the option, out-of-sRGB colors flagged
   ("Last Color · outside sRGB" in the menu, a note in the HUD, "Outside sRGB" in the
   contrast checker).

### NSColorSampler color space: measured

Verified on 2026-11-03 (macOS 27, M4 Max, built-in Liquid Retina XDR "Color LCD") with a
test window filling six regions with exact colors, picked with real clicks:

| Region drawn as | Sampler's NSColor (space, components) | `usingColorSpace(.extendedSRGB)` | Copied (sRGB) |
|---|---|---|---|
| sRGB #3366CC | Display P3 (0.24988, 0.39526, 0.77344) | (0.19998, 0.40004, 0.79986) | #3366CC |
| sRGB #FF0000 | Display P3 (0.91748, 0.20032, 0.13855) | (1.00001, −0.00023, 0.00010) | #FF0000 |
| P3 (1, 0, 0) | Display P3 (1, 0, 0) | (1.09309, −0.22684, −0.15008) | #FF0000, flagged outside sRGB |
| P3 (0.2, 0.4, 0.8) | Display P3 (0.19995, 0.39990, 0.79980) | (0.10392, 0.40585, 0.82761) | #1A67D3 |
| sRGB #808080 | Display P3 (0.50195 ×3) | (0.50195 ×3) | #808080 |
| sRGB #12AB7F | Display P3 (0.30811, 0.66064, 0.50928) | (0.07079, 0.67063, 0.49792) | #12AB7F |

With Display P3 output, the P3 (0.2, 0.4, 0.8) region copies as `#3366CC` and P3 red as
`#FF0000` (not flagged). Findings:

- The sampler returns colors **tagged generic Display P3** (not the display's own "Color LCD"
  profile), at better than 8-bit precision.
- `usingColorSpace(.sRGB)` **clamps silently** (P3 red becomes plain (1, 0, 0)), so it can't
  detect out-of-gamut colors. Dropper converts with `.extendedSRGB` and stores that; P3 values
  come from the standard matrices in `ColorMath` (they match ColorSync to 1e-4).
- sRGB content round-trips exactly after 8-bit rounding. Sampling noise is about 0.0003, so
  "outside sRGB" uses a tolerance of half an 8-bit step (0.002).
- Only one display was available; an sRGB external display wasn't tested. The conversion
  works from whatever space the NSColor carries, so it should hold.

## Sources

- Sip help center: [Using Sip](https://docs.sipapp.io/using-sip), [Picker](https://docs.sipapp.io/picker.md),
  [Color Formats](https://docs.sipapp.io/color-formats.md), [Smart Formats](https://docs.sipapp.io/smart-formats.md),
  [Smart Profiles](https://docs.sipapp.io/smart-profiles.md), [Contrast Checker](https://docs.sipapp.io/contrast-checker.md),
  [Palettes](https://docs.sipapp.io/palettes.md), [Color Panel](https://docs.sipapp.io/editor.md),
  [Color Dock](https://docs.sipapp.io/color-dock.md), [Color Blindness](https://docs.sipapp.io/color-blindness.md),
  [Snapshots](https://docs.sipapp.io/snapshots.md), [Shortcuts](https://docs.sipapp.io/shortcuts.md),
  [URL Schemes](https://docs.sipapp.io/url-schemes.md), [Getting Started](https://docs.sipapp.io/getting-started.md),
  [What's New in 5.0](https://docs.sipapp.io/whats-new.md), [index](https://docs.sipapp.io/llms.txt)
- [Sip release notes](https://sipapp.io/updates/)
- [Sip on Setapp](https://setapp.com/apps/sip) and [customer reviews](https://setapp.com/apps/sip/customer-reviews)
- [TidBITS review](https://tidbits.com/2019/08/06/sip-smart-color-management-for-your-mac/),
  [Macworld review](https://www.macworld.com/article/221639/sip-review-get-exact-color-information-of-on-screen-pixels.html),
  [r/macapps thread on color pickers](https://lr.in.psf.lt/r/macapps/comments/u7q2rd/designers_whats_your_favorite_color_picker_app)
- Alternatives: [Pika](https://superhighfives.com/pika) ([README](https://github.com/superhighfives/pika)),
  [System Color Picker](https://sindresorhus.com/system-color-picker)
- Apple: [NSColorSampler](https://developer.apple.com/documentation/appkit/nscolorsampler),
  [NSColorSpace.sRGB](https://developer.apple.com/documentation/appkit/nscolorspace/srgb)
- WCAG: [Understanding SC 1.4.3 Contrast (Minimum)](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)
- In repo: `apps/Snapper/Sources/Snapper/Capture/` and `apps/Snapper/Sources/SnapperCore/Capture/`
  (overlay, loupe, ScreenCaptureKit service, coordinate helpers)

## Build notes (v0.1.0, 2026-11-03)

**Shape.** Menu bar utility (`.menu` style) + an AppKit-owned Contrast Checker window (so the
optional global shortcut can open it without a SwiftUI `openWindow` environment) + a
swatch HUD. Core (`DropperCore`): `ColorValue` (extended sRGB, P3 via `ColorMath`),
`ColorFormatter`, `HexParser`, `Contrast`/`ContrastReport`, `ColorHistory` + `FileHistoryStore`,
and `DropperModel`, which takes a `ColorSampling`, `Clipboard`, `HistoryStore` and
`PreferencesStore` (all faked in tests).

**Choices made while building.**
- Every format is written from the color rounded to 8 bits per channel, so the hex and the
  SwiftUI value of one pick describe exactly the same color (`#12AB7F` →
  `Color(red: 0.071, green: 0.671, blue: 0.498)`).
- In Display P3 mode, Hex/RGB/HSL/HSB are P3 numbers (what P3 asset catalogs and P3 Figma
  files show); CSS Display P3 is always P3 whatever the setting.
- The menu's Last Color section shows each format's actual value as the item title: you
  see what you'll get. Recent Colors shows the 10 picks before the last one.
- Copying a recent color moves it to the top (it becomes Last Color, so its other formats
  are one menu away).
- Picks from the Contrast Checker's eyedropper buttons go to history but not the clipboard.
- Clear History asks first (it can't be undone).
- Contrast is computed in sRGB (WCAG), even in P3 mode; typed hex is read in the chosen space.
- History file errors: the unreadable file is renamed `colors.json.unreadable-<time>` and a
  one-line note shows in the menu.
- Sounds, onboarding: none. The first successful pick's HUD shows a one-time hint (shortcut,
  formats in the menu), for 4 s instead of 1.4 s.

**Gates.**
- `scripts/check.sh Dropper --perf`: PASS. 47 tests in 6 suites. Launch 143 ms, first status
  item 289 ms, idle CPU 0.017% (lowest window), footprint 20.7 MB (machine busy, load 5.8).
- Walkthrough on `build/Dropper.app` with test env (data in `/tmp/dropper-test`, private
  pasteboard, `DROPPER_LOG`): real picks with the system sampler over a fixture window (six
  known swatches, see the table above) via the menu item, the test hook and the real global
  ⌥⇧C; Esc cancel (log shows cancelled, clipboard untouched); P3 mode; every Last Color format
  item; a recent color; Copy Format and Color Space submenus; Clear History (Cancel and
  Clear); Contrast Checker (seeded from last two picks, typed hex incl. 3-digit and invalid
  input, both eyedropper buttons, Swap, Copy Result, Esc, ⌘W); Settings General and Shortcuts;
  corrupt history file; real clipboard (`pbpaste`) with fake picks.
- `scripts/drive tree` (windows + menu bar): 0 `[unlabeled]`.
- Screenshots (in `/tmp/dropper-test`, not committed): `menu-dark.png`, `menu-light.png`,
  `hud1.png`, `hud2.png` (outside-sRGB note), `contrast-dark.png`, `contrast-light.png`,
  `contrast-invalid.png`, `settings-general-dark.png`, `settings-shortcuts-dark.png`.
  The status-item menu follows the menu bar's appearance, not the forced app appearance.

**Design checklist (§10).** 1 pass (one shortcut + click). 2 pass (system controls; the only
colors drawn are the user's picked colors; swatch borders use semantic colors). 3 pass (every
action in the menu bar menu with shortcuts; Contrast Checker buttons have ⌘1/⌘2/⌘E/⇧⌘C).
4 pass (Esc cancels picks and closes the checker, ⌘W, ⌘, and ⌘Q). 5 pass. 6 pass. 7 pass
("No colors yet. Press ⌥⇧C to pick one."). 8 pass (no permissions). 9 pass (Clear History
confirms). 10 pass (no networking code). 11 pass. 12 pass. 13 pass (HUD fades only).
14 pass (Contrast Checker frame autosaved; menu bar app relaunches with history).

**Deferred (with reasons).** Precise picker (v1.1, needs Snapper's capture code in SlopKit and
Screen Recording), Pick Contrast Pair and contrast "Suggest" (should; v1.1), palettes and
Library window (owner decision: v1.1), OKLCH / Android / Flutter / unit RGB formats (should;
cheap but not needed for the main flow), last color in the menu bar icon (should, off by
default anyway), `NSColor` on the pasteboard (should; unclear how text-first apps react),
Add from Clipboard, URL scheme, App Intents (later).

**Known limits / risks.**
- One early Contrast Checker eyedropper pick (of four) returned the checker window's own
  background instead of the fixture pixel above it; it didn't happen again in three retries.
  Likely a window-ordering race in the automated click (mouse warp + click right after the
  sampler opened). Worth watching in blind tests.
- Arrow-key nudging in the system loupe: not available (the system sampler has no API for it).
- If another app already owns ⌥⇧C globally, registration fails silently; the menu still
  shows the shortcut. The recorder in Settings is the fix.
- Tooling: `scripts/drive set` on an unfocused SwiftUI text field changes the text without
  telling SwiftUI; `focus` + `type` works. Menu item actions run after the menu closes, so
  wait ~1 s before reading the clipboard.

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.

### Round 1 (2026-11-03)

No blockers or majors; every swatch, including Display P3, came out exact. Triage by the
coordinator, fixes in 0.2.0.

| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
| F1 No Dropper commands in the main menu while Settings/Contrast Checker is frontmost; on a crowded notched menu bar the status item is hidden, so Pick Color is unreachable from menus | minor | accept | New **Color** menu (Pick Color ⌥⇧C, Contrast Checker… ⌘K, Copy Last Color As ▸ every format, Recent Colors ▸ 10 + Clear History…) and **Help › Dropper Help** (repo README, `Brand.repoURL` + `/tree/main/apps/Dropper`). `Commands.swift`. |
| F2 sRGB red and P3 red both read "#FF0000" in Recent Colors | minor | accept | Recent rows (status menu and Color menu) append "· outside sRGB" (or the chosen space) when the value is clamped (`DropperModel.menuTitle`). |
| F3 Settings first opened on Shortcuts | nit | accept | Remove SwiftUI's `com_apple_SwiftUI_Settings_selectedTabIndex` at launch (as the Slopapp launcher does); always opens on General. |
| F4 Contrast Checker discards typed values on reopen | nit | accept | **Decision:** the checker never overwrites the person's colors. The pair is saved (UserDefaults `contrastPair`, survives relaunch). First-ever open starts from the last two picks; afterwards, newer picks are *offered* in a bar ("New picks [swatch][swatch] Use Last Picks") instead of replacing. Picks made with the checker's own eyedroppers don't trigger an offer. Logic in `ContrastPair` (5 tests). |
| F5 With invalid input, the previous pass/fail stays visible | nit | accept | While either field is invalid: ratio shows "–:1", every badge shows "–" ("no result" for VoiceOver), preview and that swatch are dimmed, Copy Result is disabled. |
| F6 Ratio truncated (5.36:1 for 5.366) | nit | decide | **Decision: keep truncation** to 2 decimals so a borderline value never reads as a pass (4.499 shows 4.49, not 4.50); pass/fail always uses the exact ratio. Tooltip on the ratio: "Rounded down, so a pass is never overstated. Pass and fail use the exact ratio." README says so. |
| F7 Shortcut recorders read as search fields | nit | defer | Comes from the KeyboardShortcuts package (suite-wide fix later). SlopKit's `ShortcutRow` already names each recorder after its row ("Pick color", "Open contrast checker"), so nothing more to do in-app. |
| F8 Straight apostrophe in "You can't undo this." | nit | accept | Now "can’t"; no other straight apostrophes in UI strings. |
| Missing: paste rgb()/hsl()/#rgb into the Contrast Checker | nit | accept | `ColorParser`: hex (#rgb/#rrggbb), `rgb()`/`rgba()` and `hsl()`/`hsla()` in comma or space syntax (percent channels, `deg`, opaque alpha only), `color(display-p3 …)`. Return rewrites a valid value as hex. 30 new test cases. |
| Missing: copy as another format from the "Copied" toast | nit | defer | The toast ignores the mouse by design (non-activating HUD); other formats are one click away in the menu and in Color › Copy Last Color As. |

**Gates after the fixes:** `scripts/check.sh Dropper --perf` PASS. 57 tests in 8 suites. Launch
144 ms, first status item 315 ms, idle CPU 0.050% (lowest window), footprint 22.6 MB. 0
`[unlabeled]` in windows and menus. Walkthrough on the release build with fake picks (keyboard
and Accessibility only; no mouse this round, because another agent was using the mouse and an
external 5K display had become the main display): recent rows show the marker; Color menu
items (Copy Last Color As › SwiftUI, Recent Colors › a color, Contrast Checker…) copy and open
as expected; Help menu present; Settings opened on General after a previous session ended on
Shortcuts; typed `rgb(118, 118, 118)` became `#767676` and survived close and reopen; two new
picks showed the offer bar and Use Last Picks applied them; typing `hsl(220` blanked the
results, and finishing it to `hsl(220, 60%, 50%)` restored them. Screenshots:
`/tmp/dropper-test/r1-offer.png`, `/tmp/dropper-test/r1-invalid.png`.

Shipped as **0.2.0, status beta** (`app.json` build 2).

## Parity pass (2026-11-03)

Owner direction (docs/parity-pass.md): look and work much more like Sip, and don't miss
features. Studied from Sip's help center pages and their official screenshots (downloaded
to `/tmp/dropper-parity/`, not committed): the status panel (toolbar, format control,
palette list, palette detail, bottom bar), the main window (three columns with the Color
Panel editor), the picker loupe and its ⌘ mode menu, the Contrast Checker (pass, fail,
fix, edit), the Color Dock, the formats menu and Shortcuts. Sip itself was not launched
this time (its panel ignores Accessibility presses, and the earlier walk already covered
Settings).

### What Sip looks like (layout only; nothing copied)

- **Status panel**, ~350 pt wide, under the icon: a row of four toolbar icons (picker,
  contrast, +, color panel), a full-width format dropdown, a white card listing "Color
  History" as a long color strip and then each palette as a radio + name + color strip;
  clicking a palette opens it as a list of round swatches with name and hex (••• on
  hover); a bottom bar with settings, color-blindness menu, main window, quit.
- **Main window**: sidebar of palette strips, a middle list of colors, and the Color Panel
  on the right: name, a saturation/brightness square, hue and opacity sliders, a big
  swatch, HEX + RGB/HSB/HSL + alpha fields, notes, created/modified, and export /
  duplicate / delete.
- **Picker**: a round magnifier with a pixel grid, the center pixel boxed, and a pill
  inside the circle with a swatch and the hex; holding ⌘ shows a mode menu (pick one,
  multiple, check contrast).
- **Contrast Checker**: a card whose top half is filled with the background color and
  shows the verdict ("AAA"/"Fail") and a sentence in the text color, with the ratio in a
  pill; below, a column per color: swatch, hex field with an eyedropper, a Fix button, and
  hue/saturation/brightness sliders, a swap arrow between; "Create Palette" at the bottom.
- **Color Dock**: a slim vertical strip on a screen edge, one segmented bar per palette;
  hovering one shows its colors in a flyout with "Palette / Color" and •••.

### Gap table

| Item (Sip) | Before | Now | Notes |
|---|---|---|---|
| Split status icon (pick / panel), filled with last color | single icon, `.menu` | **done** | Eyedropper half picks, arrow opens the panel; right-click or an AX press opens the panel. Dot of the last color (setting, on). Single-icon style in Settings. |
| Status panel: toolbar, format selector, history strip, palettes, bottom bar | `.menu` | **done** | AppKit status item + anchored glass panel (`StatusItem.swift`, `PanelView.swift`). |
| Palettes (create, name, notes, add by picking while selected, radio) | – | **done** | `Palette`, model ops, active palette ("New picks go here"). |
| Palette actions: rename, duplicate, export, delete, lock, merge, sort | – | **done** | Sort by hue / lightness / name / date added. |
| Delete duplicated colors | – | n/a | Our palettes never hold duplicates (same rule Sip states). |
| Reorder palettes / colors, drag between palettes, ⌥-drag copies | – | **done (mostly)** | Library: drag to reorder palettes and colors; dragging a color onto a palette adds a copy (text drag, so colors from other apps work too). Moving (vs copying) between palettes: deferred (S). |
| Group colors inside a palette | – | deferred (M) | Needs a nested model + UI; rare in daily flow. |
| Main window (3 columns) | – | **done** | Library window, `LibraryWindow.swift`. |
| Color Panel editor: name, SB square, hue slider, HEX, RGB/HSB/HSL fields, notes, info | – | **done** | `ColorEditor.swift`; also lists every format with copy buttons (replaces the old menu's "every format" list). Replace with a new pick. |
| Opacity slider / alpha | – | deferred (M) | Our colors are opaque picks; alpha touches every format, parser and contrast. |
| Duplicate color | – | n/a | Palettes can't hold duplicates; "Add to Palette" / "New Palette with This Color" cover it. |
| Export single color | – | covered | Copy As every format; palette export. |
| Picker loupe with grid, center box and value | system loupe only | **done** (opt-in) | `PrecisePicker.swift` on SlopKit `ScreenCaptureService` + `BadgeLayer`; value in the copy format. |
| Arrow nudge 1 px / ⇧ 10 px | – | **done** | Moves by physical pixels in the frozen image; the real pointer is hidden, never warped. |
| Size + / −, zoom ⌥+ / ⌥−, two-finger swipe | – | **done** | Plus Settings › Picker steppers; remembered. |
| Pick multiple colors | – | **done** | Panel eyedropper menu, Color menu, optional global shortcut; copies all values. Works with both pickers. |
| Check contrast from the picker | – | **done** | "Pick Contrast Pair". Sip's hold-⌘ menu inside the picker: not copied (explicit items instead; see decisions). |
| Formats: Android (ARGB, RGB, XML), CGColor, CSS (HSLA, RGBA, CMYK, HWB), Java, .NET, NSColor/UIColor HSB, OpenGL, Swift variants | 8 formats | **done (31)** | Plus OKLCH, Lab, LCH, Display P3, Compose, Flutter, Objective-C. Android RGB (`#RRGGBB`) is the same as Hex, so not repeated. CGColor CMYK: skipped (CMYK has no meaningful screen conversion; CSS CMYK covers the number). |
| Enable / disable formats | – | **done** | Settings › Formats with a live example per format. |
| Format options (caps, #, whitespace) | caps, # | same | Whitespace option: not needed (our formats have one canonical spacing). |
| Custom format templates | – | deferred (M) | Template language + editor + import/export. |
| Smart Formats (per-app format) | – | **done** | Settings › Formats: off by default; turning it on suggests Xcode → SwiftUI, VS Code → Hex, Android Studio → Compose (installed ones only); add any running app. Follows the last app you worked in, so picking from Dropper's own panel still uses it. The HUD says which app's format was used. |
| Smart Profiles | – | skip | Correct conversion makes it unnecessary (decision unchanged). |
| Contrast Checker look (verdict header in the colors, columns, sliders, swap) | form | **done** | `ContrastView.swift`. Kept our full WCAG breakdown below it. |
| Contrast Fix | – | **done** | `ContrastFixer`: OKLCH lightness search to the next level (AA, then AAA), gamut-mapped; says so when impossible. |
| Create Palette from the checker | – | **done** | "Save as Palette". |
| Import / export palettes: Sip, ASE, CLR, JSON, PDF | – | **done** | ASE, CLR, GPL, our JSON, CSS variables, PDF swatch sheet (export only); import also scans any text for colors. Sip's own palette format: can't read (undocumented, proprietary). |
| Open .ase/.clr from Finder (document types) | – | deferred (S) | Registering document types changes LaunchServices handlers on the owner's Mac; not during an unattended pass. |
| Color Dock | – | **done** | `ColorDock.swift`: palettes opt in, snaps to any edge, hover/click flyout, click copies, drag out, ••• actions, show/hide shortcut. |
| Color blindness simulation | – | **done** | Panel bottom bar; 4 deficiencies (Machado et al. 2009) applied to every swatch. |
| Sounds | – | **done (off)** | Setting "Play a sound when a color is copied" uses the system "Pop" sound. |
| Color names | – | **done** | Our own small OKLCH-based namer ("Dark Blue", "Pale Pink"); editable per color. |
| Shortcuts: open picker, contrast, status menu, main window, color panel, dock | 2 | **done** | Pick, pick multiple, contrast, show panel, open Library, toggle dock. "Get primary/secondary color" from design apps: skip (Automation per app). |
| Send to app (plugins) | – | skip | Automation permission per app, brittle (decision unchanged). |
| URL scheme | – | deferred (S) | Same LaunchServices concern as document types. |
| Cloud sync, snapshots, licensing, onboarding | – | skip | No accounts/network; one small JSON file. |
| Appearance theme (Auto/Light/Dark) | – | skip | Follows the system. |

### Decisions (parity pass)

1. **Menu bar UI is now a panel, not a `.menu`.** Matching Sip's panel layout is the
   point of the pass. Everything the old menu offered is still one step away: Copy As
   (every format) in each color's ••• and context menu, the editor's values list, and the
   main-menu Color menu.
2. **Split icon by default**, like Sip's default "Extended" icon; an Accessibility press
   (VoiceOver, scripts) always opens the panel, so the pick-on-click half never surprises
   assistive tech.
3. **System magnifier stays the default picker.** The loupe needs Screen Recording; the
   first pick should work with no prompt. Settings › Picker turns the loupe on and shows
   the permission state; without permission picks fall back to the system magnifier with
   a one-line note.
4. **No hold-⌘ mode menu inside the picker.** Multi-pick and contrast-pair are explicit
   commands (panel eyedropper menu, Color menu, shortcuts) so they also work with the
   system magnifier.
5. **Clicking a palette opens it; clicking a color copies it** (panel). In the Library a
   click selects and double-click copies, as in other Mac list windows.
6. **Palettes never hold duplicates; history keeps 100.** Same rules as Sip's docs.
7. **Fix changes lightness only** (OKLCH), so the hue the designer chose stays; it aims
   at AA first and AAA once AA passes.
8. **Platform formats stay sRGB in P3 mode** (Android, Flutter, .NET, Java, HSB code):
   those APIs interpret numbers as sRGB.
9. **Color Dock shows only palettes you add**, so nothing appears on screen until asked.

### Deviations from the design system

- **Custom status item + panel** instead of `MenuBarExtra(.menu)` + `MenuFooter`: the
  panel's bottom bar has Settings, Library and Quit (About lives in Settings › About).
- **Colored menu bar icon**: when "Show the last color" is on, the icon is a non-template
  image with a color dot; the eyedropper glyph is still drawn in the menu bar's label color.
- **Colored UI surfaces**: the Contrast Checker header is filled with the user's background
  color and its text uses the text color; the Color Dock floats over other windows on
  every Space. Both are the feature itself.
- **Fixed-size type** in the checker's verdict (52 pt) to match the original's poster-like
  verdict; everything else uses text styles.
- **Optional sound** (system "Pop"), off by default.

### Shared components built in-app (candidates for SlopKit)

- `Material.view(wrapping:cornerRadius:)` (StatusItem.swift): SlopKit's `FloatingPanel`
  has the same helper internally; making it public would remove this copy.
- `GradientSlider` (ColorViews.swift): accessible gradient-track slider.
- `ColorHUD` (unchanged): HUD with custom content.
- `SnapshotRenderer`: offscreen PNG rendering of views for locked-screen/CI layout checks.

### Gates (parity pass)

- `scripts/check.sh Dropper`: **PASS** (101 tests in 17 suites; release bundle; smoke).
  New tests: 31 formats incl. CSS reference values for OKLCH/Lab, names, contrast Fix,
  color vision, palette rules, library model (active palette, lock, merge, import names,
  multi-pick, contrast pair, per-app formats, dock flag), v1/v2 file compatibility, ASE /
  JSON / GPL / CSS / text codecs, loupe geometry and pixel nudging, dock snapping.
- Verified through the real app without the screen (test hooks + offscreen rendering):
  export of every format (JSON, ASE, CLR, GPL, CSS, PDF) to `/tmp/dropper-test/export`,
  re-import of ASE, CLR, GPL and a CSS token file with exact hex values and names;
  offscreen renders of the panel (root and opened palette), Contrast Checker, editor,
  Library, Color Dock strip and flyout, Settings, light and dark
  (`DROPPER_RENDER_DIR`, files in `/tmp/dropper-test/render/`, PDF page in
  `/tmp/dropper-test/shots/brand-pdf.png`).
- **Not run yet: needs an unlocked screen.** The Mac was locked (display asleep, owner
  away) for the whole session after the build, so macOS hides windows from Accessibility
  and screen capture: the `scripts/drive` walkthrough on `build/Dropper.app`, the
  `[unlabeled]` tree check, on-screen screenshots, the precise loupe against the test
  scene (`DROPPER_TEST_SCENE=1`, launched `--direct`), and real mouse checks (split icon
  click, drag reorder, Color Dock drag). `scripts/perf.sh` was also not run: it quits
  every running Dropper, and a Dropper I didn't start (pid 10334, launched normally from
  build/Dropper.app at 16:45, likely the owner's) was running.

## Polish pass (2026-11-05)

Brief: `docs/polish-pass.md`. Every surface shot with `scripts/drive shot` on the stamped release
build, light and dark (`SLOP_APPEARANCE`), on test data only (`DROPPER_DATA_DIR` fixture with 14
history colours and 5 palettes: one with a very long name, one empty, one locked, one of 60
colours; `DROPPER_DEFAULTS` suite, `DROPPER_PASTEBOARD` private pasteboard, `DROPPER_FAKE_PICKS`,
`DROPPER_EXPORT_DIR`). The loupe was shot over the app's own test scene (`DROPPER_TEST_SCENE=1`,
launched `--direct`), whose capture contains only that window. No `shot --screen`, no real
clipboard writes, no real mouse, no global keys. Screenshots: `/tmp/slopapp-polish/dropper/`
(`final/` = after, `render-before/` + `before-*.png` = before, `loupe/` = loupe sizes).

### Defects found and fixed (before → after)

**Crash**
- Opening the Contrast Checker crashed the app (AppKit "update constraints" exception, three
  crash reports today). Cause: SlopKit's `Hairline` is 1 pt tall until the window reaches a
  Retina screen, then 0.5 pt; in this self-sizing window (`preferredContentSize`) that resized
  the window mid-layout. → The hairline sits in a fixed 1 pt slot. Opens every time now.

**Lint** (`scripts/lint.sh Dropper`): 23 corner literals, 2 colour hits, 17 spacing warnings → 0 / 0 / 0.
The two colour hits were the SwiftUI/UIKit *code text* Dropper copies (`"Color(red: …)"`),
marked `lint:allow`; the PDF sheet's 40 pt page margin is `lint:allow`.

**Menu bar panel**
- Panel radius 14 (literal) → `Radius.xl` 16 (measured 15.4 on the glass edge).
- Card radius 12, padding 8; rows' hover shape 10 at 4 pt padding; strips 8 → card `Radius.xl`,
  card padding 4, row hover `nested(16, 4)` = 12, row padding 4, strips `nested(12, 4)` = 8. All
  four curves concentric; strips 16 pt from the panel edge on both sides (measured 16.0/16.0).
- Format menu: 192 pt wide, floating centred → full width of the card (8–312 pt, measured).
- Toolbar icons 3.5 pt right of centre (the pick menu's arrow) and uneven gaps (27.5 vs 20 pt)
  → arrow hidden (hold still opens the menu, as the tooltip says; also in the Color menu);
  centred.
- Bottom bar icons at 17 pt vs strips at 20 pt → both at 16 pt (`contentInset`).
- Card height was an estimate: up to ~40 pt of blank card under a short palette → measured
  content height (estimate only before the first measure), so the card hugs its rows.
- Color History row had no hover state and its ••• was full strength while the palettes' were
  at 35 % → same row style for both (hover fill, ••• 45 % at rest, full on hover).
- "Empty" strip label `.tertiary` (≈1.9:1) → `.secondary`.
- List-detail header ••• trailing 4 pt vs rows' 8 pt → 8 pt; header leading matches swatches.

**Swatches everywhere**: 1 pt `primary.opacity` strokes (blurry, doubled on dark) → one device
pixel edge (`hairlineBorder`) on strips, round swatches, gradient tracks, dock bars, flyout
swatches. Small swatches 6/7 pt → `Radius.xs`, or nested in their container.

**Library window**
- Sidebar strip inset from the selection 6 pt at the sides, 8 pt below, radius 8 inside an
  8 pt selection → 2 pt side padding makes it an even 8/8 (measured), strip `Radius.xs`.
- Window title stuck on the fixed "Dropper Library" (or "Untitled") until the selection changed
  → starts as the selected list's name ("Color History – 14 colors").
- Export menu in the info forms drew as plain text + round arrow, lighter and lower than the
  bordered Duplicate/Delete buttons → a bordered Export button that opens the formats in a menu
  under it (`ExportMenuButton.swift`). Same height as its neighbours.
- Explanations as separate caption rows ("A locked palette can't…", "Every pick lands here…")
  → subtitles of their control. Counts use monospaced digits.
- Sidebar + / import buttons at 10 pt vs row text at 18 pt → aligned to 18 pt.
- Form strips radius 8 inside sections ~10 pt in → `Radius.s` (inset ≈ section radius, so
  the shape's own token).

**Color editor**
- Hex field 7 pt higher than the R/G/B fields (caption vs menu heights) → one grid, both rows
  aligned (fields 790–842 px, measured).
- Values: names in a fixed 112 pt column ("NSColor (Objective-C)", "Unit RGBA (OpenGL)" wrapped)
  and values ran into the copy buttons → a grid sized to the longest name, values wrap in their
  own column.
- Saturation/brightness square radius 10 literal + 1 pt stroke → `Radius.l` + device-pixel edge.
- Channel label gap 2 pt → 4 pt, fields 8 pt apart.

**Contrast Checker**
- 32 pt of blank window under the footer (content ignored the title-bar safe area but the window
  still added it) → `safeAreaRegions = []`; footer 20 pt from the bottom (measured).
- Swap button nudged with a 30 pt literal → same caption + row slot as the columns, centred on
  the fields (measured).
- Swatch 26, field 25, Fix 23.5 pt tall in one row → all 24 pt.
- Ratio pill 12 pt from the top, 16 pt from the right, radius 10 → 8/8 with radius
  `nested(16, 8)` concentric with the window corner (`windowConcentric` itself feeds back into
  this self-sizing window, so the macOS 26 title-bar-window radius is used).
- "Not a color" plain `.red` → `.textRed`; "–" cells `.tertiary` → `.secondary`; 1 pt `Divider`
  → hairline; offer swatches → `Radius.xs`.

**Color Dock and flyout**
- Dock 29 pt wide although laid out for 26 (the grip glyph's 13 pt width pushed it), radius 9
  around 12 pt capsule bars 7 pt in → 28 pt wide (measured), bars 8 pt in on every side, dock
  ends radius 14 = bar radius 6 + 8 (concentric).
- Flyout radius 12 with 12 pt padding and 6 pt swatch radius → flyout `Radius.xl`, swatches
  `nested(16, 12)` = 4; insets 12/12.5 measured.

**HUD**: radius 14, padding 12 × 16 with a 7 pt swatch in the corner → `Radius.xl`, even 12 pt
padding, swatch `nested(16, 12)`.

**Loupe**
- Grid lines 1 pt → one device pixel; pill swatch edge 1 pt → one device pixel.
- "Fits inside" was `width ≤ 0.8 × diameter`, which let a long readout's round ends cross the
  ring → checks both capsule ends against the circle (ring + 4 pt clearance). Shot at 104, 136,
  168, 208 and 256 pt: inside from 136 pt for hex, under the loupe at 104 pt.
- Prompt badge 10 pt above → `Spacing.s`.

**Settings**: every explanation row (colour space, menu bar icon, Color Dock, picker engine,
copy format, loupe keys) → subtitle or section footer. Loupe Size and Zoom steppers were 24 pt
apart horizontally ("168 pt" vs "6×") → value slot of one width, steppers aligned.

**Errors**: export failure showed Cocoa's "The folder “Brand.json” doesn't exist." → "Couldn't
export “Brand”" + "The folder “export” is missing or can't be written to. Export again and
choose another folder." (verified by exporting into a missing `DROPPER_EXPORT_DIR`; then a real
ASE export to the test folder).

### Checked and fine
Window buttons 16×16 (Library, Contrast, Settings); Library window radius 17.1 pt; no
`[unlabeled]` in `drive tree` (panel, dock, Library, alert); toolbar controls in the Library all
36 pt; Settings tabs light/dark; Screen Recording not granted path in Settings › Picker (gate
shown); text contrast: secondary text only, status text via `.textRed`.

### Not done, and why
- **Hover with the real pointer** (panel rows, ColorRow •••, dock flyout): not triggered; the
  owner or another agent was using the Mac throughout (HID idle mostly 0 s, and someone clicked
  the test instance's menu bar icon several times). Hover is designed in code (row fill + •••).
- **Loupe colour accuracy**: over the test scene, `#3366CC` reads exact but `#12AB7F` reads
  `#0DAC7F` and sRGB red stripes `#FE0100`: the capture is an 8-bit display-space image, and
  converting back to sRGB moves dark channels a few units. Not a finish issue; worth a look
  (capture in sRGB or float, or sample the system sampler's way).
- **Contrast pill radius** uses the measured macOS 26 title-bar-window radius instead of reading
  it (`windowConcentric` crashes this self-sizing window, see above): about 1 pt off.

### Shared-component notes (SlopKit)
- `Hairline` changes height with `displayScale`; inside a self-sizing window
  (`NSHostingController.sizingOptions = .preferredContentSize`) that crashes AppKit on macOS 26.
  Suggest a fixed 1 pt layout height with the line drawn inside it.
- `windowConcentric` / `ConcentricRectangle` in the same kind of window also loops; worth a note
  in `Corners.swift`.
- `ExportMenuButton` (`ExportMenuButton.swift`): a bordered button that pops an `NSMenu` under
  itself, for menus inside grouped forms; candidate for SlopKit.

### Gates
- `scripts/check.sh Dropper --perf`: **PASS** (lint, 101 tests in 17 suites, bundle, smoke, perf:
  launch 129 ms, first status item 234 ms, idle CPU 0.018 %, footprint 22.9 MB).

### Golden Gate + light/dark (2026-11-06)

Owner: "ensure all the apps are optimized for dark/light mode AND look like they fit in with
macOS Golden Gate" (macOS 27.2). Checked against design system §4 "Fitting in on macOS 27
Golden Gate" and §10 items 25–26. Shots, light and dark side by side:
`/tmp/slopapp-polish/dropper/goldengate/` (`*-light*` / `*-dark*`, `inactive-*`, `loupe-*`,
`reopen-settings-light.png`). Same test-data rules as above. The owner's `app.slopapp.dropper`
defaults were backed up first and restored after (window frames had moved); the test suite's
defaults were deleted.

**Changed**
- **Inactive windows**: the Library sidebar's "new picks go here" eyedropper stayed accent blue
  in a background window → `Color.windowAccent(controlActiveState)`, grey when inactive
  (`inactive-library-*.png`). Same for the panel's active-palette radio. List and sidebar
  selections, text selection and toggles are the system's and already grey.
- **Panel card text on glass**: secondary text was vibrant, blended with what's behind the
  glass instead of the 75 % card under it: 3.2:1 light, 3.1:1 dark on a bare shot (measured
  on glyph pixels), and it would shift with the backdrop. → solid `controlBackgroundColor` card
  and label colours resolved for the appearance (`PlainLabelColors` in `PanelView.swift`): dark
  3.1 → 4.05:1 on the same measure; light is now exactly the system secondary on white (3.95:1,
  the design system's accepted floor) whatever is behind the panel.
- **Glass**: Dropper's glass helper (panel, Color Dock, flyout, HUD) sets `style = .regular`
  explicitly, the text-bearing style that follows the clear/tinted slider and Reduce
  Transparency. The HUD's private copy of the helper is gone (it uses the same one).
- **Loupe chrome → `OverlayPalette`**: ring, pixel marker, shadows, grid and the readout were
  pure white/black (a white readout pill with dark text). Now ink/paper from SlopKit's overlay
  palette, and the readout matches `BadgeLayer` (dark badge, light text) like the hint badge
  beside it; same in both modes because it sits on screen content (`loupe-136-light.png`,
  `loupe-136-dark.png`, `loupe-256-white.png`, shot over the test scene only).
- **Knobs on colour** (hue/saturation/brightness sliders, the editor's square): pure white ring +
  black shadow → overlay paper/ink. The square's white→black gradients stay (colour math).
- **Settings opener**: Dropper's own `SettingsOpener` (and the `onOpenSettingsAvailable`
  modifier on three views) → `SettingsWindow.open()`. Clean swap; the panel's Settings button
  opens Settings in both modes.
- **Hairline**: my fixed 1 pt wrapper around the Contrast Checker's hairline is gone (SlopKit's
  `Hairline` now lays out 1 pt). Opened and closed the checker 6 times in light and 6 in dark:
  no crash. The line is one device pixel (px row 894 = 447 pt, `#E6E6E6` on white).

**Checked, no change needed**
- **Menus are text** (context menus, ••• menus, Copy As, Add to Palette, Export, the Color and
  Window menus). The only images are colour swatches in Color › Recent Colors: information,
  kept.
- **Sidebar**: the system's edge-to-edge `.sidebar` list, no card; rows show colour strips, no
  symbols to tint. **Toolbar**: the standard unified toolbar.
- **Inactive shots**: Library, Contrast Checker and Settings each shot while another Dropper
  window was key, light and dark.
- **Reopen**: with the icon hidden by macOS (`VisibleCC = 0` on this Mac), `open
  build/Dropper.app` on the running app opens Settings (SlopKit's reopen; Dropper's panels are
  `NSPanel`s, so they don't count as visible windows). Reopening again with Settings showing
  just brings it forward. One instance throughout.
- **Light/dark**: Library, editor, panel (list and palette pages), Color Dock and flyout,
  Contrast Checker, HUD, every Settings tab and the export alert shot in both modes. Picked
  colours are data; the chrome around them is semantic or overlay palette. The PDF swatch sheet
  stays white on purpose (a printed page).
- `drive tree`: no `[unlabeled]`.

**Not done**
- The real clear-glass setting wasn't switched (that's a System Settings change). The panel's
  readable text now sits on a solid card. The toolbar icons, bottom bar and HUD text sit on
  regular glass, as SlopKit's `HUD` does.
- Hover with the real pointer: still owed (same reason as above).

**Gates**: `scripts/check.sh Dropper --perf` **PASS** (lint, 101 tests in 17 suites, bundle,
smoke, perf: launch 141 ms, first status item 247 ms, idle CPU 0.002 %, footprint 22.9 MB).
