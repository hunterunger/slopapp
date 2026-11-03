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
