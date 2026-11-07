# Devkit research (inspired by DevUtils)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md) on 2026-11-03.
> Studied: **DevUtils** through its website (full tool list), docs index, integrations/URL
> scheme help page, Setapp listing and AlternativeTo comparisons. DevUtils is **not
> installed** on this Mac, so nothing was explored live; in-app details (settings, hotkey)
> are unverified. Open-source equivalents used for patterns: DevToys (Windows/Mac), Boop
> (scriptable scratchpad), CyberChef. We study how it works so we don't reinvent the wheel.
> We never copy its name, icons, artwork, wording, sounds or signature visuals.

## The job

A developer has a blob of text (an API response, a token from a log, a timestamp in an
error, a Base64 string in a config) and needs it made readable or transformed, now, without
pasting it into a random website that might log it. Done feels like: paste, the right tool
is already showing the decoded/formatted result, copy, back to work, all offline.

**The one interaction that matters: open the app (or a shortcut) with something on the
clipboard → the matching tool is selected with the clipboard already in its input → the
output is on the right → ⌘⇧C copies it.**

## Who and when

- Pretty-printing a minified JSON response to find a field; validating hand-edited JSON.
- Decoding a JWT from a request header to check `exp` and claims.
- Converting `1730592000` from a log into a date (and the reverse for a query).
- Testing a regex against sample lines before putting it in code.
- Generating a UUID/ULID for a fixture; hashing a string to compare checksums.
- Frequency: several times a day for many developers; each use 5–60 s.

## Feature inventory

DevUtils ships ~47 tools. We pick 12 for v1.

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | JSON format / validate / minify | Formatter with indent options, error location | must | `JSONSerialization` can't keep key order or big ints → own small tokenizer-based pretty printer in the core that preserves order and number text; error with line:column. Indent 2/4/tab, sort keys toggle. |
| 2 | Base64 encode/decode (text) | String and image modes | must | Standard + URL-safe alphabet, padding tolerant; shows "not valid UTF-8, showing hex" for binary. Image mode later. |
| 3 | URL encode/decode | Encode/decode | must | Component vs. full-URL modes; `+` as space toggle. |
| 4 | JWT decoder | Decodes header/payload, verifies signature | must (decode) / should (HMAC verify) | Show `iat/nbf/exp` as local dates + "expired 3 h ago". Verify HS256/384/512 with a secret via CryptoKit; RS/ES later. Never sends anything anywhere. |
| 5 | UUID / ULID generate & decode | Generate many, decode | must | v4 and v7, ULID; bulk count (1–1000), upper/lowercase; decode shows version/variant/timestamp. |
| 6 | Hash generator | MD5, SHA-1/256/512, Keccak-256 | must | CryptoKit (MD5/SHA-1 under `Insecure`), SHA-256/384/512 all at once; HMAC should; file drop hashing should (streamed). Keccak later. |
| 7 | Unix timestamp converter | Time converter | must | Auto-detect s / ms / µs by magnitude; shows local, UTC, ISO 8601, RFC 2822, relative; reverse: date → timestamp; "Now" button. |
| 8 | Regex tester | RegExp tester | must | `NSRegularExpression` (ICU syntax; label it "ICU, like Swift/ObjC; differs slightly from JS/PCRE"). Flags i, m, s, x; highlights matches; table of groups; replace preview. Runs off main with a timeout (catastrophic backtracking). |
| 9 | Color converter | Converter | must | HEX(3/4/6/8)/RGB(A)/HSL(A)/HSB, swatch, copy as SwiftUI `Color(...)`/CSS. System color picker button. |
| 10 | Text diff | Diff checker | must | Line diff with Swift `CollectionDifference` (Myers); side-by-side or unified; ignore whitespace toggle; character-level highlight within changed lines should. |
| 11 | Number base converter | Base converter | must | Bin/oct/dec/hex (+ custom base 2–36), arbitrary length via a simple big-int in the core. |
| 12 | String case converter | Case converter | must | camel, Pascal, snake, kebab, CONSTANT, Title, sentence, lower, UPPER. |
| 13 | HTML entity encode/decode | Yes | should | |
| 14 | URL parser | Yes | should | Scheme/host/port/path/query table via `URLComponents`. |
| 15 | Line sort/dedupe | Yes | should | Sort, reverse, unique, trim, count. |
| 16 | String inspector | Yes | should | Chars, words, lines, bytes (UTF-8/16), grapheme vs scalar counts. |
| 17 | Backslash escape/unescape | Yes | should | |
| 18 | Lorem ipsum, random string | Generators | later | `SecRandomCopyBytes`. |
| 19 | Cron parser | Human description + next runs | later | |
| 20 | YAML ⇄ JSON, JSON ⇄ CSV | Converters | later | Needs a YAML parser (no dependency yet). |
| 21 | HTML/CSS/JS/XML/SQL beautify/minify | Many formatters | later | XML via `XMLDocument` is cheap; others need real parsers. |
| 22 | cURL to code, JSON to code, HTML to JSX, PHP serializers, SVG to CSS | Yes | later / skip (PHP) | Niche. |
| 23 | Hex ⇄ ASCII | Yes | later | |
| 24 | QR read/generate | Yes | later | CoreImage generator; Vision for reading. |
| 25 | X.509 certificate decoder | Yes | later | Security framework. |
| 26 | HTML / Markdown preview | Yes | skip | Needs a web view (design system: no web views). |
| 27 | Smart detection (clipboard → tool) | Detects tool from clipboard content; one-click | must (detection) | **Opt-in auto-read** of the clipboard on activation (off by default); always-available ⌘⇧V "Paste & Detect". Respects concealed/transient pasteboard types. |
| 28 | Menu bar access | Status bar icon opens the app | should | Optional status item; app is a window app. |
| 29 | URL scheme (`…://tool?input=…&copy`, `auto`) | Documented | later | App Intents first. |
| 30 | Alfred / Raycast / Terminal integration | Yes | later | A CLI over the pure core is cheap later. |
| 31 | Customizable/grouped tool list | Reorder, hide, group | should (hide) / later (reorder) | |
| 32 | Syntax highlighting | Yes | should (JSON only) | `AttributedString` coloring with semantic colors. |
| 33 | Global hotkey | Unverified | should | Show window + Paste & Detect. Unset by default. |

## Key flows

### Flow 1: paste and detect
1. Copy a JWT in the browser. Press the global shortcut (or click the Dock icon).
2. Window comes forward. If auto-read is on, the clipboard is read once now; otherwise the
   user presses ⌘⇧V. The detector picks **JWT**, selects it in the sidebar, fills the input.
3. Output: header and payload pretty JSON, claim dates in a small table, an "Expired" badge
   if `exp` passed.
4. ⌘⇧C copies the primary output (payload JSON). `HUD` "Copied".

### Flow 2: pick a tool manually
1. Sidebar (NavigationSplitView) lists the 12 tools with SF Symbols; ⌘1…⌘9 jump to the
   first nine; ⌘F filters the sidebar.
2. Each tool: input editor on the left/top, options in a slim bar, output on the
   right/bottom; output updates live (debounced ~100 ms; heavy tools off main).
3. **Use Output as Input** (⌘↩) chains tools (e.g. Base64 decode → JSON format).

### Flow 3: first run
1. Window opens on JSON with an empty input and a placeholder line "Paste JSON, or press
   ⇧⌘V to detect what's on the clipboard". No tour, no clipboard read.
2. Settings ▸ General shows "Read the clipboard when Devkit opens" (off) with a one-line
   privacy note.

## Detection rules (pure core, ordered, first match wins)

1. JWT: three base64url segments separated by `.`, first decodes to JSON with `alg`.
2. JSON: trimmed starts with `{` or `[` and parses.
3. UUID / ULID: exact pattern.
4. Unix timestamp: 9–13 digit integer (or with fraction) in a plausible range (1990–2100).
5. Color: `#RGB(A)`, `#RRGGBB(AA)`, `rgb(…)`, `hsl(…)`.
6. URL-encoded: contains `%[0-9A-F]{2}` and decodes to different text.
7. Base64: length % 4 == 0 (or base64url), only alphabet chars, ≥ 8 chars, decodes to
   mostly printable UTF-8.
8. Number with base prefix (`0x`, `0b`, `0o`).
9. Otherwise: no change (stay on current tool). Detection never fires on more than 1 MB.

## Settings inventory

| Setting | Default | Options | Keep? |
|---|---|---|---|
| Read the clipboard when Devkit opens | off | | must |
| JSON indent | 2 spaces | 2/4/tab | must |
| Show in menu bar | off | | should |
| Hidden tools | none | per-tool | should |
| Global shortcut | unset | recorder | should |
| Launch at login | off | | v1 (standard) |

## Menus and shortcuts

File: none beyond Close ⌘W · Edit: standard + Paste & Detect ⇧⌘V, Copy Output ⇧⌘C, Clear
Input ⌘⌫ (undoable), Use Output as Input ⌘↩ · View: tools ⌘1–⌘9, Filter Tools ⌘F, Swap
Input/Output layout · Window · Help.

## Permissions and system integration

None. No network, ever (no tool needs it). Clipboard reads only on explicit action or the
opt-in setting. App Intents (later): "Format JSON", "Decode JWT", "Convert Timestamp" for
Shortcuts.

## UX patterns worth adopting

- Detection turns "which tool do I need?" into zero clicks.
- Live output with the input still editable; errors inline with position.
- Chaining outputs into inputs covers multi-step decodes without a pipeline builder.
- Everything offline is the core selling point; we make it verifiable (no network
  entitlement use at all).

## What we won't copy, and what we'll do better

- Not copying: name, icon, tool artwork, wording, paid tiers.
- Better: free, small (12 solid tools instead of 47 uneven ones); clipboard never read
  unless asked; JSON formatter that keeps key order and big numbers exactly; regex tester
  says which engine it uses; timestamp tool guesses seconds vs milliseconds and shows both.

## Edge cases

- Huge input (50 MB JSON): format off main with progress and cancel; syntax highlighting
  turned off above 1 MB.
- Invalid UTF-8 in Base64 output: show hex dump.
- JSON with duplicate keys, `NaN`, trailing commas, comments: error with location (strict
  JSON); a "lenient" toggle later.
- Big integers (`12345678901234567890`) preserved as text.
- Regex catastrophic backtracking: timeout (500 ms) with a clear message.
- Timestamps before 1970 / negative; ms vs s ambiguity near boundaries.
- Emoji/combining characters in case conversion and string inspector.
- Concealed pasteboard (password managers) never auto-read.
- Dark/light, VoiceOver on editors and output, window size and selected tool persist.

## Our v1 scope

- [x] Sidebar app with 12 tools: JSON, Base64, URL encode, JWT decode, UUID/ULID, Hash,
      Unix time, Regex, Color, Diff, Number base, Case.
- [x] Each tool: live output, inline errors, Copy Output ⇧⌘C, Clear Input (⌘K, see decisions).
- [x] Paste & Detect ⇧⌘V with the rules above (unit-tested with a fixture per rule and
      false-positive cases).
- [x] Opt-in "read clipboard on open", off by default; concealed types respected.
- [x] ⌘1–⌘9 tool switching, filter (⇧⌘F, see decisions), Use Output as Input.
- [x] Heavy work off main; regex timeout; 50 MB JSON doesn't freeze the UI.
- [x] Settings: General (clipboard, JSON indent, launch at login), About.
- [x] Pure `DevkitCore` with unit tests per tool (round-trips and known vectors: RFC 4648
      Base64, NIST SHA test vectors, RFC 7519 JWT example, ULID spec examples).

Should: HMAC JWT verify, HTML entities, URL parser, line tools, string inspector, escape,
menu bar item, hide tools, global shortcut, JSON highlighting, file hashing.
Built in v1 from the should list: HMAC JWT verify, global shortcut (unset), JSON
highlighting, file hashing (streamed, with progress), checksum compare. Deferred to later:
HTML entities, URL parser, line tools, string inspector, escape, menu bar item, hide tools.

## Open questions → owner-default decisions (2026-11-03)

1. **The 12 tools**: the roadmap's ten + Number base + Case converter.
2. **Clipboard auto-detect**: opt-in only; manual ⇧⌘V always there.
3. **Archetype**: window app (library window), optional menu bar item later; not
   menu-bar-only.
4. **No web views**: Markdown/HTML preview skipped.
5. **No third-party parsers in v1** (YAML etc. wait until a dependency is approved).

## Sources

- [DevUtils website (tool list)](https://devutils.com/)
- [DevUtils docs](https://devutils.com/docs/)
- [DevUtils integrations / URL scheme](https://devutils.com/help/devutils-integrations-2)
- [DevUtils on Setapp](https://setapp.com/apps/devutils)
- [AlternativeTo: DevUtils alternatives](https://alternativeto.net/software/devutils)
- [AlternativeTo: Boop](https://alternativeto.net/software/boop)

## Build notes (steps 3–4, 2026-11-03)

### Decisions made while building

| Decision | Why |
|---|---|
| Clear Input is **⌘K**, not ⌘⌫ | A menu key equivalent wins over the text view, so ⌘⌫ would break "delete to start of line" in every editor. ⌘K is Clear in Terminal and Xcode's console. Undoable. |
| **⌘F is Find** in the focused text (with Find Next ⌘G, Find and Replace ⌥⌘F, Use Selection ⌘E); **Filter Tools is ⇧⌘F**, and ⌘F falls back to the filter when no text has focus | Searching a long formatted JSON or diff matters more than filtering 12 tools. SwiftUI apps get no Find menu, so Devkit adds the standard one. |
| Tool order JWT 2nd, Base64 3rd … (by expected frequency) | ⌘1–⌘9 should reach the common tools. |
| Inputs aren't persisted across launches | They often hold tokens and secrets. Tool, options, split sizes and layout persist. |
| Inputs above 8 MB show a summary card instead of an editor; outputs show the first 2 MB | NSLayoutManager keeps glyphs for every character: a 44 MB paste cost 2 GB and several seconds of main-thread layout. With the card: no stall, 1.3 s CPU total, ~420 MB while holding 44 MB in and 88 MB out. Copy Output always copies everything. |
| Detection: no match → the text goes into the current tool | Paste & Detect should never do nothing. Auto-read (opt-in) only acts when a tool matches. |
| Manual ⇧⌘V reads concealed clipboard items; the automatic read never does | The user asked explicitly; the automatic path must not touch password-manager items. |
| Use Output as Input re-runs detection on the output | One shortcut chains Base64 → JSON, URL → JWT, etc. With no match it stays in the tool and flips Encode/Decode. |
| ULIDs are always uppercase | Spec's canonical form; the Uppercase/Hyphens options apply to UUIDs only. |
| UUID v7 and ULID are monotonic within a millisecond | RFC 9562 §6.2 method 1 (counter in rand_a) and the ULID spec's monotonic mode; bulk lists sort correctly. |
| Date-only input ("2024-11-03") is local midnight | That's what people mean when they type it (JavaScript treats it as UTC). |
| JSON duplicate keys are a warning, not an error | RFC 8259 allows them ("SHOULD be unique"); the location is still shown. |
| Copy in Finder + ⇧⌘V in Hash hashes that file | Natural for checksum checks, and makes file hashing scriptable. |
| Undo is per window; switching tools clears it | Undo steps refer to the editors of the tool that was showing. |

### Shared components built in-app (candidates for SlopKit)

- `CodeTextView.swift`: TextKit 1 plain-text code editor/viewer for SwiftUI (monospaced, no
  smart substitutions, find bar, undoable whole-text replace, placeholder, file drop,
  temporary-attribute highlighting, large-paste hand-off).
- `CodeField.swift`: single-line monospaced field that, unlike SwiftUI's `TextField`, picks up
  values set through Accessibility (VoiceOver/Voice Control/automation), plain-text editing.
- `SplitStack.swift`: two-pane split that keeps its proportion (SwiftUI's `HSplitView` drifts
  as content changes), drag and double-click to reset, accessibility adjustable.

### Gates

- `scripts/test.sh Devkit`: **86 tests in 15 suites pass** (parameterized cases: 17 JSON
  errors, 31 detector fixtures incl. 13 false positives, 9 timestamp ranges, 3 indents).
  Vectors: RFC 4648 §10 Base64, RFC 1321 MD5, FIPS 180 SHA-1/256/384/512 ("abc", empty,
  two-block), RFC 4231 HMAC case 2, RFC 7519 §3.1 token verified with the RFC 7515 A.1 key,
  RFC 9562 Appendix A v1/v6/v7/v4 examples, ULID spec time `01ARYZ6S41`.
- `scripts/check.sh Devkit --perf`: all pass. Launch 169 ms, first window 388 ms, idle CPU
  0.012 % (lowest window; machine busy, load 4.5), footprint 57 MB.
- `scripts/drive tree`: 0 `[unlabeled]` in all 12 tools (empty and filled), UUID inspect,
  decoded JWT, Settings.

### Walkthrough (release build, private pasteboard `DEVKIT_PASTEBOARD=devkit-test`, throwaway defaults suite)

| v1 item | Result |
|---|---|
| Paste & Detect | JWT, JSON, `1730592000`, `#3366CC80`, Base64, `q=hello%20world…`, UUID v7, ULID, `0xFF_FF` each opened the right tool, filled. |
| Copy Output / Use Output as Input | ⇧⌘C wrote the right value to the private pasteboard (selected row in list tools, unified diff in Diff, all 87.7 M characters for the 44 MB JSON). Base64 of a JSON object → ⌘↩ → JSON tool, formatted. Base64 encode → ⌘↩ flips to Decode with the round-tripped text. |
| JSON | Order and big ints kept, highlighting, errors with line/column and Show in Input. 44 MB paste: formatted off main, no UI stall. |
| JWT | RFC example decoded, "Expired 15 years ago", HS256 verified with the Base64 key; wrong secret → "doesn't match". |
| Regex | Matches highlighted, named groups, `${user} at $2` replacement; `(a+)+$` on 40 a's + b stops after 0.5 s with an explanation, CPU back to idle. |
| Hash | "abc" vectors, checksum compare ("Matches SHA-256"), 300 MB file hashed in ~1 s with progress, SHA-256 equal to `shasum`, footprint back to 52 MB (fixed an autorelease build-up that held 360 MB). |
| Diff | Side by side with character highlights, unified copy correct. |
| Time, Color, Number base, UUID/ULID, Case, URL | Values checked against the unit-tested core; v7 bulk generation sorted. |
| Settings | General (Launch at login, clipboard opt-in with privacy note, JSON indent), Shortcuts (global shortcut recorder, unset), About. |
| Light and dark | Screenshots of JSON, JWT, Regex, Diff, Time, Color, Hash, Number, ULID, Settings reviewed in both. |

Found and fixed during testing: text replaced programmatically lost the monospaced font;
SwiftUI split views drifted (JWT signature pushed off screen); SwiftUI `TextField`s ignored
Accessibility value changes; wide SF Symbols broke sidebar alignment; side-by-side diff rows
didn't fill the pane; long digests wrapped with inserted hyphens; no Find menu; per-editor
undo managers that the SwiftUI Undo menu never consulted (now the window's, verified
"Undo Clear Input" is registered); 2 GB footprint for huge inputs; 360 MB after file hashing.

Opt-in clipboard read on activation, verified live during an idle window: setting off → stays
on JSON; on → opens Color with `#00AA55`; on + `org.nspasteboard.ConcealedType` → skipped.

**Not tested live: owner active.** Pressing ⌘Z/⇧⌘Z from the keyboard, the global shortcut
and the file-open panel need Devkit frontmost with keyboard focus. The Mac was in use (and
another builder's app held focus) through repeated ~10-minute waits, so these weren't driven.
Covered otherwise: undo registration on the window's undo manager verified in-process
("Undo Clear Input"); file hashing verified through the clipboard path; the global shortcut
uses SlopKit's KeyboardShortcuts like the other apps.

### Design-system checklist (§10)

| # | Item | Result |
|---|---|---|
| 1 | Main job in one shortcut | Pass: ⇧⌘V picks the tool and fills it; ⇧⌘C copies |
| 2 | Native look, light + dark | Pass: system controls and materials, semantic system colors for syntax/diff, accent for regex matches |
| 3 | Keyboard + menus | Pass: every action in Edit/Tools/View/File with shortcuts |
| 4 | Esc / ⌘, / ⌘Q | Pass (Esc leaves a field; no sheets besides the open panel) |
| 5 | Settings General + About | Pass |
| 6 | Copy | Pass: title-case menus/buttons, sentence-case toggles, errors say what to do |
| 7 | Empty states | Pass: symbol, one line, one action (Paste and Detect / Use Now / Hash a File…) |
| 8 | Permissions | Pass: none needed |
| 9 | Destructive actions undoable | Pass: Clear Input, Paste & Detect, Open File are undo steps |
| 10 | No network | Pass: no networking code |
| 11 | Performance budgets | Pass (see Gates) |
| 12 | VoiceOver names | Pass: 0 unlabeled |
| 13 | Reduce Motion | Pass: no custom animations |
| 14 | Window state persists | Pass: window frame, tool, options, split sizes |

## Parity pass (2026-11-03)

Per [`docs/parity-pass.md`](../parity-pass.md): look and work more like DevUtils, and close the
feature gap. DevUtils isn't installed, so this was studied from devutils.com (tool list,
per-tool docs, changelog) and its product screenshots and video posters (downloaded to
`/tmp/devkit-parity/`, viewed, not committed). The Mac's screen was locked for the whole
pass, so UI was verified with an offscreen render hook (`DEVKIT_SNAPSHOT`), unit tests and
test hooks instead of `scripts/drive`.

### What the original's layout is

- Window: sidebar (search field on top, flat list of tools with icons, reorderable, groups
  optional), tool title in the toolbar, a pin button (float on top) at the top right.
- Every tool: `Input:` header with **Clipboard**, **Sample**, **Clear** (and a gear for tool
  settings); input on the left; `Output:` header with option pop-ups and **Copy** on the
  right. Value tools (Unix time, UUID decode, color) put one input field at the top and a
  grid of labeled read-only fields, each with a copy button, below.
- App: status-bar icon (click to show), global hotkey, smart detection from the clipboard on
  activation, ⚡ "replace the clipboard with the output", ⇧⌘C copy output, ⌘/ search.

### Gap table

| Item (original) | Status | Notes |
|---|---|---|
| Sidebar of tools with search | done (already) | Flat list like the original, now 33 tools in the original's rough frequency order; ⇧⌘F and now ⌘/ focus search. |
| Hide tools ("Manage Tools") | done | Right-click ▸ Hide, Settings ▸ Advanced checkboxes, Tools ▸ Show Hidden; hidden tools still match a search. |
| Reorder tools by drag, tool groups | deferred (M, ~½ day) | Sidebar `onMove` plus persisted order; groups need a settings UI. Frequency order covers most of the value. |
| Input header: Clipboard / Sample / Clear | done | `InputActions` on every tool's input pane (and value tools' input row). Clipboard pastes without detection (⌥⌘V). Sample has a real example per tool. |
| Output header: Copy | done (already) | Copy on every output pane; options stay in the top bar (see deviations). |
| Pin window on top | done | Toolbar pin toggle and Tools ▸ Keep Window on Top (⌥⌘T); persists. |
| Status-bar icon | done (opt-in) | Settings ▸ General ▸ Show in menu bar (off by default). Menu: Show, Paste and Detect, Replace Clipboard, Settings, About, Quit. Closing the window keeps Devkit running while it's on. |
| Global hotkey | done (already) | Unset by default (the original's ⌃⌥⌘Space could clash). |
| Smart detection on activation | done (already, opt-in) | Detection now covers 22 tools (was 9). |
| ⚡ Instant clipboard replace (⇧⌘R) | done | Edit ▸ Replace Clipboard with Output, also in the menu bar menu. |
| Escape hides the window; option-click status icon copies | deferred (S) | Esc currently ends field editing, which matters more in a text tool. |
| Multiple windows (⌘N) | deferred (M) | Single `Window` scene; models are app-wide. |
| URL scheme, Alfred/Raycast, CLI, "Inspect in" service | deferred (M) | Same as v1. |
| JSON format/validate | done (already) | |
| JSON tree view with folding, JSON Path filter | deferred (L, 1 day) | Needs an outline view over `JSONTree` and a JSONPath evaluator. |
| JSON ⇄ YAML | done | Yams (libyaml) for parsing with the YAML 1.2 core schema; our own emitter keeps order. YAML spec examples 2.1, 2.2, 2.10 as vectors; round-trip tests. |
| JSON ⇄ CSV | done | Own RFC 4180 parser/writer (RFC §2 examples as vectors). |
| HTML beautify/minify | done | Own tolerant parser; inline runs kept on one line, `<pre>`/`<textarea>` verbatim, `<script>`/`<style>` re-indented. |
| CSS / LESS / SCSS beautify/minify | done | One formatter handles nesting, `//` comments and `#{}` interpolation. |
| XML beautify/minify | done | Validated with Foundation's `XMLDocument`, formatted by the shared markup printer. |
| SQL formatter | done | Own tokenizer/formatter, keyword case option, minify. |
| JS beautify/minify, ERB | deferred (L, 1–2 days) | Needs a real JS tokenizer (regex literals, ASI, template strings); a sloppy one would corrupt code. |
| Line sort/dedupe | done | Sort orders incl. natural and shuffle, dedupe (case-insensitive option), trim, drop empty. |
| URL encode/decode | done (already) | |
| URL parser / query string to JSON | done | Repeated keys and `key[]` become arrays. |
| HTML entity encode/decode | done | All 2,125 WHATWG named references (generated table), numeric refs. |
| Backslash escape/unescape | done | `\n \t \" \xHH \uXXXX \u{…}` octal, surrogate pairs. |
| String inspector | done | Counts plus a per-scalar table (code point, Unicode name, UTF-8, kind). |
| Number base, string case, Unix time, color, UUID/ULID, hash, diff, regex | done (already) | Unix time "+ - * /" math and Regex match navigation are deferred (S each). |
| Cron job parser | done | English description and next runs (local or UTC); Vixie day-of-month OR day-of-week rule; macros, names, seconds field. |
| Lorem ipsum | done | Paragraphs / sentences / words, classic opening optional. |
| Random string | done | `SystemRandomNumberGenerator`, unbiased; look-alike filter, groups (license keys), entropy shown. |
| QR code generate / read | done | Core Image generator (L/M/Q/H), PNG save/drag/copy; Vision reader from drop, file or pasted image. Wi-Fi/SMS templates and logo overlay deferred (S–M). |
| Certificate decoder (X.509) | done | Own DER reader: names, validity, key, SANs, key usage, EKU, CA, key IDs, fingerprints; chains. |
| JWT HMAC verify | done (already) | |
| JWT RS/PS/ES verify | done | Security framework (RSA PKCS#1 v1.5 and PSS) and CryptoKit (P-256/384/521). Keys as PEM, PKCS#1, certificate, JWK or JWK Set (picks `kid`). |
| JWT signing | deferred (M) | Needs private-key handling and UI to edit claims. |
| Hex ⇄ ASCII | done | One tool with two modes. |
| SVG to CSS | done | URL-encoded (compact, readable) or Base64 data URI. |
| GZip / zlib / deflate | done (not in DevUtils; in the brief) | System deflate, own gzip/zlib framing and CRC-32/Adler-32. |
| Base64 image encode/decode | deferred (S–M, ~½ day) | Drop image → data URI; data URI → preview. |
| HTML to JSX, cURL to code, JSON to code | deferred (M–L each) | Niche, each needs its own generator per target language. |
| PHP serializer/unserializer, PHP ⇄ JSON | deferred (M) | Niche. |
| Keccak-256 hash | deferred (S–M) | Not in CryptoKit; needs our own Keccak-f. |
| HTML preview, Markdown preview | skipped / deferred | HTML preview needs a web view that could load remote content: skipped (privacy, design system). Markdown preview could be native (`AttributedString(markdown:)` blocks) later (M). |

Result: 33 tools (was 12) against the original's 47; of DevUtils' 47, 37 are covered
(LESS/SCSS count as covered by CSS, Hex↔ASCII and YAML/CSV pairs count per direction).

### Deviations and decisions

| Decision | Why |
|---|---|
| Options stay in a slim bar above the panes, not in the output header | Several tools have 3–5 options; in a 280 pt pane header they'd clip at the minimum window width. The pane headers get the original's Clipboard / Sample / Clear and Copy, so the per-tool layout matches. |
| Title on the left of the toolbar (native `navigationTitle` + subtitle), not centered | System window chrome; centering would be custom drawing for no gain. |
| Menu bar icon off by default | v1 behaviour (closing the window quits) stays the default; the original's status-bar flow is one switch away. |
| YAML uses the 1.2 core schema (`no`, `on`, `yes` stay strings) | What js-yaml (and most current tools) do; avoids the Norway problem. Emitting quotes those words so YAML 1.1 readers agree. |
| One Hex tool with two modes, one tool per conversion direction for YAML/CSV | Matches the original's sidebar for the conversions people search by name; hex is rarely used either way. |
| Detection adds certificate, HTML, SVG, XML, SQL, cron, CSS, YAML, CSV, URL-with-query, gzip, HTML entities, backslash escapes; bare URLs and prose stay put | Each rule has false-positive tests (prose with colons, "select … from the menu", `C:\new\temp`, "AT&T", "1 2 3 4 5"). |
| Yams 6.2.2 added (pinned exact, MIT) and listed in design-system §9 | A correct YAML parser (flow style, block scalars, anchors, tags) is too much to hand-roll; JSON→YAML is our own code. |
| New tools persist their options per tool (`tool.<id>.<option>`), never their input | Same rule as v1: inputs may hold secrets. |
| No new SF Symbols in the icon; sidebar symbols only | Unchanged rule. |

Shared components built in-app (SlopKit candidates): `TransformTool.swift` (spec-driven
text→text tool), `InputActions` (Clipboard/Sample/Clear header), `ImageDropTarget`,
`WindowAccessor`, `Snapshot.swift` (offscreen window renders).

### Gates (parity pass)

- `scripts/test.sh Devkit`: **150 tests in 27 suites pass** (was 86 in 15). New vectors:
  YAML 1.2 spec examples 2.1, 2.2, 2.10 plus JSON→YAML→JSON round-trips (indent 2 and 4,
  tricky strings); RFC 4180 §2 CSV quoting; WHATWG entity table (incl. two-code-point
  `&NotEqualTilde;`); RFC 7515 A.2 (RS256, JWK and SPKI/PKCS#1 PEM) and A.3 (ES256) JWS
  verified, tampered payload rejected; Let's Encrypt ISRG Root X1/X2 decoded with their
  published SHA-256 fingerprints, serial and dates; CRC-32 check value `0xCBF43926`,
  Adler-32 "Wikipedia" `0x11E60398`, `gzip -n` and `zlib.compress` outputs decoded; QR
  generate→Vision read round-trip (L and H, PNG); cron next runs across a leap day and the
  day-of-month-or-weekday rule; 8 invalid cron cases; 14 new detector fixtures and 5 new
  false-positive cases.
- `scripts/check.sh Devkit --perf`: **all pass**. Launch 161 ms, first window 424 ms, idle
  CPU 0.019 % (lowest window), footprint 66.9 MB (budget 120; was 57 MB with 12 tools).
- Offscreen renders (`DEVKIT_SNAPSHOT`, release build, private pasteboard, throwaway
  defaults, fixed clock and seed): every tool with its sample, light and dark, plus the empty
  state, JWT ES256 with a JWK, QR read mode, and Settings General / Shortcuts / Advanced:
  78 PNGs in `/tmp/devkit-parity/shots/`, all reviewed. Fixed from the review: Settings ▸
  Advanced was ~1,500 pt tall (now two columns of checkboxes), the RS/ES verification
  result sat below the fold (now above the key field), a too-wide sidebar glyph for String
  Inspector, inconsistent "2 spaces"/"2 Spaces".
- **Owed on screen (the Mac was locked for the whole pass; `scripts/drive` refuses):**
  `scripts/drive tree` for `[unlabeled]` controls on all 33 tools and Settings (an
  in-process walk can't stand in: SwiftUI builds its accessibility tree only for a connected
  client); a scripted walkthrough of Clipboard / Sample / Clear, ⇧⌘V detection into each new
  tool, ⇧⌘R Replace Clipboard (private pasteboard), Keep on Top, hiding a tool from the
  sidebar context menu, the menu bar icon (show, paste and detect, window close keeps the
  app running), QR read by drag-and-drop and Paste Image, Save PNG panel, and the
  certificate file drop; light/dark screenshots of the real window.

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.

## Polish pass (2026-11-05)

Brief: `docs/polish-pass.md` (plus the mid-pass Golden Gate + light/dark addition). Worked on
the release build with `DEVKIT_PASTEBOARD=devkit-polish` (private pasteboard: no real
clipboard reads or writes; Copy and Replace Clipboard were never triggered),
`DEVKIT_DEFAULTS=devkit-polish` (throwaway suite, deleted after), `DEVKIT_NOW`, `DEVKIT_SEED`.
The owner's `app.slopapp.devkit` domain was exported first and re-imported at the end (verified
identical). Inputs for error/edge states went through the private pasteboard and Edit ▸ Paste
Clipboard into Tool. All 33 tools were shot with their sample, in light and dark, before and
after, plus empty, error, minimum-size (760 pt) and active-window states, and every Settings tab.

### Defects fixed (before → after)

Shared layout (affects every tool):

| # | Defect | Before | After |
|---|---|---|---|
| 1 | Panes started at different heights: 5 tools (JWT, Text Case, URL Parser, String Inspector, Certificate) had no options row; 5 single-value tools (Unix Time, Color, Number Base, Cron, UUID inspect) used their own top area | The Input header (and Clipboard/Sample/Clear) sat anywhere from 52 to about 108 pt down, depending on the tool | One 40 pt options row in every tool (a one-line `NoteBar` explaining the tool when it has no options), so every pane header sits at y = 92.5 pt and Clipboard/Sample/Clear are in the same row everywhere |
| 2 | Single-value tools: own Input header (no bar background), 20 pt insets, field options inline | "Input" title 20 pt in, results text 16.5 pt in | Same `PaneHeader` as every pane (30 pt, 12 pt inset); field inset 12 pt top/left/right (measured 12.5/11.5/12); Unit/Now, From/Extra base/Uppercase, Time zone/Show moved to the options row |
| 3 | SwiftUI `Divider` under options row, pane headers, status line, Hash checksum, Regex replace, JWT claims, Cron, Diff columns | 1 pt (2 px) | `Hairline()`: 1 device pixel (measured at y 92, 122.5, 647.5) |
| 4 | Split-pane divider | 1 pt rectangle | 1 device pixel, same as the other hairlines (grab area unchanged at 9 pt) |
| 5 | Status hints (`.tertiary`) | 1.88:1 light, 2.25:1 dark | `.secondary`: 3.95:1 light, 5.74:1 dark |
| 6 | Status line grew from 1 to 2 lines with long messages, squeezing the panes | min 28 + 4 pt | Fixed 32 pt (fits two callout lines); hint truncates with a tooltip |
| 7 | Options row `minHeight: 40` could grow | variable | Fixed 40 pt |
| 8 | Labels wrapped mid-word at the minimum window size (560 pt detail): "Re-/move…", "Case-/sensi…", "Len/gth", "Cou/nt", ". matches/newlines", "Detect numbers/and booleans" | wrapped | One-line labels; an over-full row scrolls sideways (no indicator, no bounce when it fits); a note-only row truncates with a tooltip |
| 9 | Result-list text out of line with the pane title | row text 16.5 pt in, title 12.5 pt (4 pt off); 10 pt top gap | Plain, full-width lists like the panes (Xcode/Console style) + 4 pt row padding: row text at 12.5 pt, row Copy buttons under the header's Copy |
| 10 | Text fields in an options row taller than the pop-ups beside them | 26 pt vs 24 pt | 24 pt (`ToolMetrics.rowControlHeight`) |
| 11 | Result-row notes ("Not for security") `.tertiary` | ~1.9:1 | `.secondary` |
| 12 | Syntax colours on the editor background (light mode) | key 3.52, string 3.57, number 4.17, keyword 3.65 :1 | Darkened 30% in light mode only: 5.8–6.6:1; dark unchanged (4.6–5.2:1); dynamic, so they follow a live appearance change |

Per tool:

| Tool | Before | After |
|---|---|---|
| String Inspector | Fixed column widths (44+84+90+110 + Name) overflowed a 450 pt pane: Kind column cut off ("Upperca") | Flexible widths; all five columns fit, Name truncates in the middle with a tooltip |
| URL Parser | "Query as JSON" was the only unhighlighted JSON output; "No query string" shown as if it were output | Highlighted like every JSON output; placeholder text when there's no query |
| UUID and ULID | "Generate Again" in the output header, unlike Lorem Ipsum and Random String | "Generate" at the end of the options row in all three generators |
| Hash | "Matches"/"No match" in plain green/orange text (~2:1); HMAC key field collapsed to ~6 pt once the row was sized to its content | `.textGreen`/`.textOrange`; key field fixed 180 × 24 pt |
| JWT | Verification messages in plain `.green`/`.red`/`.orange` text; public-key box had a 4 pt corner literal with a 1 pt `.separator` stroke | `.textGreen`/`.textRed`/`.textOrange`; `Radius.s` with `hairlineBorder`, clipped |
| Regex | `/` delimiters, match ranges and "no match" groups in `.tertiary`; flags in `.callout` (a different size from every other options row) | `.secondary`; flags at the standard control size |
| Text Diff | Line numbers `.tertiary`; column divider 1 pt | `.secondary`; vertical `Hairline` |
| Unix Time, Number Base, Color, Cron, UUID inspect | Error line was a whole sentence in plain red (~3.6:1 light) | Red symbol + primary text, one line, tooltip with the full text |
| Color | Swatch: 6 pt corner literal and `.strokeBorder(.separator)` | `Radius.s` + `hairlineBorder` |
| Number Base | "Extra base: 9" → "36" changed width and moved the toggle after it | Label slot sized for two digits |
| Cron | Description inset 20 pt (rest of the pane 12 pt) | 12 pt |
| QR Code | In dark mode the code's light quiet zone was a raw square-cornered white tile | Rounded with `Radius.m` + hairline (the quiet zone stays: scanners need it) |
| Settings ▸ General/Shortcuts | Explanations were separate rows under their controls | Subtitles of the toggle / shortcut row |
| Settings ▸ Advanced | Two checkbox columns sized to content, leaving the right third of the section empty | Two equal columns |
| Lint | 4 corner literals, 8 hardcoded colours | 0; the colour-tool values (`Colors.swift`, the picked colour) are data, marked `// lint:allow` |

### Golden Gate + light/dark

- **Sidebar**: the system `NavigationSplitView` sidebar, edge to edge; tool symbols are accent
  tinted in the active window and grey when inactive (both shot:
  `after/active-hash-{light,dark}.png` vs any other shot). Nothing forces them monochrome.
- **Menus**: text only already (Tools, Edit additions, Find, sidebar context menu, menu bar
  extra). The toolbar keeps its symbols (toolbar items, not menu items).
- **Toolbar**: the standard `.toolbar`; the system draws its glass. No drawn strips.
- **Inactive window**: every routine shot is of the inactive window (`drive` never activates).
  Selections go to the unemphasized grey, accent controls go grey. Checked in both modes.
- **Glass**: none of our own; no text on glass.
- **Light/dark**: every tool, state and Settings tab shot in both, side by side. Colours are
  semantic or resolve per appearance (syntax theme, status colours); diff tints are system
  colours at low opacity (read in both); the only drawn white is the QR code's quiet zone,
  which is data.

### Gates

- `scripts/check.sh Devkit --perf`: all pass. 150 Devkit tests and 77 SlopKit tests; launch
  154 ms, first window 523 ms, idle CPU 0.010%, footprint 66.6 MB (busy machine, load 13.6).
- `scripts/lint.sh Devkit`: pass.
- `scripts/drive tree`: 0 `[unlabeled]` across the 17 distinct tool layouts and Settings;
  close/minimize buttons 16×16.

### Screenshots (`/tmp/slopapp-polish/devkit/`)

- Before: `before-live/<tool>-{light,dark}.png` (all 33), `before/` (offscreen snapshot mode).
- After: `after/<tool>-{light,dark}.png` (all 33, release build), `after/active-hash-{light,dark}.png`.
- States: `r5/json-empty-*`, `r5/json-error-*`, `r5/timestamp-error-*`, `r5/jwt-empty-*`,
  `r5/regex-empty-*`, `r5/diff-empty-*`, `r5/jwt-es256-*`, `r5/hash-hmac-*`,
  `r5/min-*.png` and `r5/min2-*.png` (760 pt window), `r4/settings-{general,shortcuts,advanced}-{light,dark}.png`.

### Not done, and why

- **Hover with the real pointer** (split-divider cursor, button hover): not checked; the owner
  was active for most of the pass. Hover comes from system controls except the divider cursor.
- **The menu bar extra and the About window** weren't shot (the menu bar icon is off by
  default and turning it on writes the owner's setting; About is SlopKit's `AboutWindow`).
  The menu is text only by code.
- **Typed input into the JWT public-key editor** via `drive set` landed on its label (an
  NSTextView inside SwiftUI); the ES256 state was shot with the token, and the offscreen
  `DEVKIT_SNAPSHOT` run covers the key-filled state (`before/jwt-es256-*.png`).
- **String Inspector table** keeps the system inset style (its column header row is its own
  alignment reference); it isn't on the pane title's 12 pt line.
- **Random String** keeps two options rows (length/count/groups, then character sets): one row
  doesn't fit at the default width. Regex keeps its own pattern area above the panes.
