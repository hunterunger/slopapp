# Snip research (inspired by TextSniper)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied:
> TextSniper 1.13 (not installed on this Mac) from its website, Mac App Store listing and
> full version history, third-party reviews, the MIT-licensed TRex (an open-source
> equivalent) and Apple's Vision docs, on 2026-11-03. We study how it works so we don't
> reinvent the wheel. We never copy its name, icons, artwork, wording, sounds or signature
> visuals.

## The job

Snip gets text that you can see but can't select: a paused video frame, a screenshot in a
chat, a scanned PDF, an error dialog, a slide in a screen share, a UI label. People reach
for it many times a week when retyping would be slow or error-prone (serial numbers,
long URLs, code from a video, a table of numbers). "Done" is pasting the exact text a
second later, with line breaks where they belong, without a window ever appearing.

The one interaction that matters most: **press a shortcut, drag a box over the text,
the text is on the clipboard and a small "Copied" HUD confirms it.**

## Who and when

- Copying a URL or command shown in a video tutorial or a screen-shared slide.
- Grabbing an error message from a dialog whose text isn't selectable.
- Pulling a column of numbers out of an image of a table into a spreadsheet.
- Reading a QR code shown on a web page or in a screenshot, without a phone.
- Translating a manga panel or a foreign-language image (paste into a translator).

Frequency: a few times a day to a few times a week; each use takes 2–5 seconds.

## Feature inventory

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Capture text from a screen region | Global shortcut (⇧⌘2 default) or "Capture Text" in the status menu; a crosshair; drag a rectangle; text goes to the clipboard | must | SlopKit `RegionOverlay` (frozen screen on every display, magnifier) → `FrozenDisplay.crop` → Vision off the main actor → `NSPasteboard`. Default shortcut **⌥⇧⌘2** (sits beside Snapper's ⌥⇧⌘3/4/5; ⇧⌘2 is left free). |
| 2 | Success feedback | A popup/animation after capture; can be turned off (1.6) | must | SlopKit `HUD`: "Copied 4 lines" / "No text found". No sound. |
| 3 | Keep line breaks | On by default; off joins into one paragraph; separate shortcuts per mode; ⌘L toggles during capture | must | Default keeps lines. ⌥ held while releasing the drag joins lines into paragraphs (and de-hyphenates "exam-\nple"). Setting for the default. |
| 4 | Recognition languages | 25+ languages depending on macOS (Latin, CJK, Cyrillic, Arabic, Thai, Vietnamese, Hindi…); vertical CJK on Sonoma | must | `VNRecognizeTextRequest.supportedRecognitionLanguages()` at runtime: we list whatever this macOS supports, never a hardcoded list. |
| 5 | Automatic language detection | Ventura+ | must | `automaticallyDetectsLanguage = true` is the default; the language picker overrides it ("Automatic", then preferred languages in order). |
| 6 | QR codes and barcodes | Reads them from the screen (1.6); optional "open links automatically" | must | Run `VNDetectBarcodesRequest` alongside text on the same crop. If a code is found, copy its payload (takes priority over surrounding text); HUD says "Copied QR code". Opening links: off by default, setting. |
| 7 | Custom words | A list of domain words to improve recognition (1.5) | should | `customWords` + `usesLanguageCorrection`. A plain text field in Settings, one word per line. |
| 8 | Additive clipboard | Appends each capture to a running history that persists across restarts; clear via menu/shortcut; option to auto-clear on ⌘V | should | "Append to Clipboard" toggle in the menu. Appends to what's on the clipboard with a newline; nothing persisted to disk. One modifier during capture is enough (⌥), so append stays a menu toggle. |
| 9 | Capture previous selection | Re-runs OCR on the last rectangle (1.7) | should | Menu item + optional shortcut. Great for slides that advance in a screen share. Rect stored in memory only. |
| 10 | Text to speech | Reads the result aloud with a system voice, adjustable rate, stop shortcut | later | `AVSpeechSynthesizer`; accessibility-minded but not the job. |
| 11 | Import from iPhone/iPad | Continuity Camera import, then OCR | later | `NSMenuItem` with `importsItemsFromDevices`; cheap but niche. |
| 12 | Recognize text in an image file / clipboard image | Not in TextSniper (TRex has "capture from clipboard") | should | "Recognize Clipboard Image" menu item and dropping an image on the status icon. Same pipeline, no permission needed. |
| 13 | Keep table structure | Not offered: TextSniper works line by line (Macworld notes Live Text handles columns better) | later (macOS 26+) | Vision's document request (macOS 26) returns tables, lists and paragraphs: copy tables as tab-separated text so they paste into Numbers/Excel as cells. Gate on OS; v1 sorts lines top-to-bottom, left-to-right. |
| 14 | Smart actions on detected URLs/emails | Detect links in text; optional auto-open | later | `NSDataDetector` on the result; offer "Open Link" in the HUD only if it becomes an actionable panel. |
| 15 | Hide menu bar icon; right-click icon to capture | Hold ⌘ and drag to hide; right-click triggers capture (1.12) | must (hide) / should (right-click) | Standard SlopKit "Show in menu bar"; relaunch brings it back. |
| 16 | Launch at login | Yes | must | SlopKit toggle, off by default. |
| 17 | History of captures | Additive clipboard doubles as history | skip | Privacy: OCR'd screen text is often sensitive. Nothing written to disk. |
| 18 | Shortcuts / URL scheme / CLI | Not in TextSniper; TRex has `trex://capture`, a CLI, a "run Shortcut" automation | later | App Intent "Recognize Text in Image" is the useful one. |
| 19 | Onboarding | A short onboarding (1.8) | skip | PermissionGate on first capture is all we need. |
| 20 | Test mode | n/a | must (for us) | `SNIP_TEST_SCENE=1`: a generated scene (multilingual text + a QR code via `CIQRCodeGenerator`), captures limited to it with `CaptureExclusions(onlyWindows:)` + `PrivacyMask` (Snapper's pattern). |

### Must-haves, counted

1 region capture, 2 HUD feedback, 3 line breaks + paragraph mode, 4 runtime language list,
5 auto-detect, 6 QR/barcodes, 15 hide icon, 16 launch at login, 20 test mode. Nine, and
most of the pipeline already exists in SlopKit `Capture/`.

## Key flows

### Flow 1: capture text (main job)
1. Press ⌥⇧⌘2 (or choose Capture Text in the status menu). The screen freezes on every
   display with a dim overlay and crosshair (SlopKit `RegionOverlay`, same feel as Snapper).
2. Drag a box. Esc cancels. Holding ⌥ when releasing joins lines into paragraphs.
3. The overlay closes on mouse-up (within one frame). Vision runs in the background on the
   pixel crop at native scale.
4. Text (or a barcode payload) lands on the clipboard. HUD: "Copied 3 lines". If nothing
   was found: HUD "No text found", clipboard untouched.

### Flow 2: first run / Screen Recording permission
1. Launch: a status icon appears; no window.
2. First capture attempt: if Screen Recording isn't granted, a small window shows
   `PermissionGate(.screenRecording)` with one sentence ("Snip reads the area you select to
   find text. Nothing leaves your Mac.") and Open System Settings.
3. macOS needs a restart for that grant: the gate offers Restart (`AppRelauncher`).
4. Meanwhile "Recognize Clipboard Image" works without any permission.

### Flow 3: QR code
1. Same as Flow 1 over a QR code. Barcode found → payload copied, HUD "Copied QR code".
2. If "Open links from QR codes" is on and the payload is an http(s) URL, open it in the
   default browser.

## Settings inventory

| Setting | Default | Options | Keep? |
|---|---|---|---|
| Capture shortcut | ⌥⇧⌘2 | recorder | must |
| Capture previous area shortcut | unset | recorder | should |
| Recognition language | Automatic | Automatic + each supported language | must |
| Keep line breaks | on | toggle (⌥ at release flips it) | must |
| Read QR codes and barcodes | on | toggle | must |
| Open links from QR codes | off | toggle | should |
| Append to clipboard | off | toggle (also in menu) | should |
| Custom words | empty | text list | should |
| Launch at login / Show in menu bar | off / on | toggles | must |

## Menus and shortcuts

Status menu: Capture Text (⌥⇧⌘2) · Capture Previous Area · Recognize Clipboard Image ·
— · Append to Clipboard ✓ · Language ▸ (Automatic, …) · Keep Line Breaks ✓ · — ·
`MenuFooter` (Settings… ⌘, · About · Quit ⌘Q). In the overlay: Esc cancels; ⌥ at release =
paragraphs; Space-drag moves the box (as Snapper).

## Permissions and system integration

- **Screen Recording** (ScreenCaptureKit), only on first capture; restart required after
  granting. Denied → capture stays unavailable with the gate; clipboard/file OCR still works.
- No Accessibility, no network. Vision models are on-device.
- macOS 15+ may periodically re-confirm screen-capture apps; the gate handles a revoked
  grant mid-use (capture fails → gate reappears).

## UX patterns worth adopting

- **No window at all on the happy path.** Shortcut, drag, paste. The confirmation is a
  transient HUD, not a result window.
- **Mode modifiers during the drag** instead of separate shortcuts (TextSniper uses ⌘L/⌘H/⌘S
  toggles inside capture; we keep it to one modifier, ⌥ for paragraphs).
- **Re-run on the same rectangle**: valuable for screen shares and slide decks.
- **Barcodes in the same gesture**: no separate "scan QR" mode to remember.

## What we won't copy, and what we'll do better

- Not copying: name, icon, sounds, success animation, wording, onboarding, upsells.
- Better: language list comes from the OS at runtime (TextSniper's site lists stale
  per-OS tables); paragraph mode de-hyphenates; no on-disk history (privacy); clipboard
  image OCR without a permission; tables keep their columns on macOS 26+ (later); a
  deterministic test scene so automation never captures the owner's screen.
- Review complaints to design against: em dashes turned into hyphens, lone "1" rows lost
  from number columns, symbol-heavy text (code) misread. Turn off language correction
  when the crop looks like code/numbers (high digit/symbol ratio), and unit-test "1" rows
  and dashes with rendered fixtures.

## Edge cases

- Multiple displays with different scales; a box spanning two displays (clip to the
  display where the drag started, as Snapper does).
- Tiny boxes (< 8 px): upscale the crop 2× before OCR; empty result → "No text found".
- Light text on dark backgrounds, low contrast, colored UI text.
- Right-to-left (Arabic) and vertical CJK ordering; mixed scripts in one box.
- Multi-column text: lines ordered by reading order, not raw y-sort across columns.
- Huge box (full 6K screen): OCR must stay < 1.5 s on Apple Silicon; show a spinner HUD if
  it takes > 300 ms; cancellable by Esc.
- Concealed content: protected windows (DRM video, password fields) appear black: "No text
  found" is fine.
- Permission revoked mid-session; sleep/wake during the overlay (cancel the overlay).
- Clipboard: write plain text only (`.string`); in append mode, append only if the
  current clipboard is plain text, else replace.

## Our v1 scope

- [ ] ⌥⇧⌘2 (rebindable) → frozen overlay on all displays → drag → text on the clipboard.
- [ ] HUD "Copied N lines" / "No text found"; nothing else appears.
- [ ] Line breaks kept by default; ⌥ at release (and a setting) joins paragraphs and fixes hyphenation.
- [ ] Language menu built from Vision at runtime; Automatic by default.
- [ ] QR codes and barcodes read in the same capture; payload copied.
- [ ] Screen Recording asked on first capture via PermissionGate, with Restart.
- [ ] Status menu with every action and shortcut; Settings (General, Shortcuts, About).
- [ ] Hide/show menu bar icon; launch at login (off).
- [ ] `SNIP_TEST_SCENE` test mode: captures contain only the test scene (PrivacyMask).
- [ ] Unit tests: OCR on rendered fixtures (English, German diacritics, Japanese, a QR,
      a numbers column with "1" rows, em dashes, two columns), paragraph joining.

## Open questions

Decisions (owner defaults, 2026-11-03: native, fast, private, no network):

1. **Default shortcut:** ⌥⇧⌘2, next to Snapper's ⌥⇧⌘3/4/5. Leaves ⇧⌘2 free for people
   migrating from TextSniper to rebind.
2. **History:** none on disk. Append mode lives on the clipboard only.
3. **QR links:** copied, never opened automatically unless the user turns it on.
4. **Overlap with Snapper:** Snapper's OCR item stays "later"; if Snapper ever adds it, it
   should call the same core (move the Vision wrapper into SlopKit when a second app needs it).
5. **Tables (macOS 26 document request):** later, behind an OS check.

## Sources

- [TextSniper website](https://textsniper.app/)
- [TextSniper on the Mac App Store (description + version history + reviews)](https://apps.apple.com/us/app/textsniper-extract-text/id1528890965?mt=12)
- [The Sweet Bits review](https://thesweetbits.com/textsniper-review/)
- [Macworld review (lines vs columns vs Live Text)](https://www.macworld.com/article/634666/textsniper-review.html)
- [MacRumors thread](https://forums.macrumors.com/threads/textsniper-ocr-app.2288283/)
- [TRex (MIT)](https://github.com/amebalabs/TRex)
- Apple: `VNRecognizeTextRequest`, `VNDetectBarcodesRequest`, ScreenCaptureKit docs.

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.
