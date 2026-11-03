# Devkit

Offline developer tools: JSON, Base64, JWT, hashes and more.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to DevUtils.

**Status:** alpha (0.1.0)

## What it does

Twelve tools in one window, all offline. Nothing you paste ever leaves your Mac.

| Tool | Does |
|---|---|
| JSON | Format, minify, validate (strict RFC 8259) with line and column errors. Keeps key order and number text exactly (`12345678901234567890` stays as written). Sort keys, 2/4 spaces or tab. Handles 50 MB documents off the main thread. |
| JWT | Decodes header and payload, shows `exp`/`nbf`/`iat` as dates ("Expired 3 hours ago"), verifies HS256/384/512 signatures with a secret. |
| Base64 | Encode (standard or URL-safe, with or without padding) and decode (either alphabet, padding optional, whitespace ignored). Binary results show as a hex dump. |
| URL Encode | Percent-encode a component or a whole URL; decode with or without `+` as space. |
| Unix Time | Seconds, milliseconds, microseconds or nanoseconds (guessed by size) to local, UTC, ISO 8601, RFC 2822 and relative time; dates back to timestamps. |
| UUID and ULID | Generate v4, v7 (time-ordered) or ULIDs, up to 1,000 at once; inspect any UUID or ULID for its version, variant and embedded time. |
| Hash | MD5, SHA-1, SHA-256, SHA-384, SHA-512 (or HMACs) of text or a file of any size; paste a published checksum to compare. |
| Regex | ICU regular expressions (as in Swift and Objective-C) with live highlighting, groups (named too), and replacement preview. Runaway patterns stop after half a second. |
| Text Diff | Line diff side by side or unified, with changed characters highlighted; ignore whitespace or case. |
| Color | Hex, `rgb()`, `hsl()`, `hsb()` in, every format out (plus SwiftUI and AppKit code and WCAG contrast). |
| Number Base | Binary, octal, decimal, hex and any base 2–36, for integers of any size. |
| Text Case | camelCase, PascalCase, snake_case, kebab-case, CONSTANT_CASE and more, line by line. |

### Paste and Detect

Press **⇧⌘V** anywhere in Devkit: it reads the clipboard once, picks the tool that fits
(a JWT, JSON, a UUID, a timestamp, a color, URL-encoded or Base64 text, `0x` numbers) and
fills it in. If nothing matches, the text goes into the current tool.

Devkit never reads the clipboard on its own unless you turn on **Settings ▸ General ▸ Read
the clipboard when Devkit opens** (off by default). Even then it skips items marked private
by password managers, reads each clipboard change once, and only acts when a tool matches.

## Keyboard

| Shortcut | Action |
|---|---|
| ⇧⌘V | Paste and Detect |
| ⇧⌘C | Copy Output (the selected row in list tools) |
| ⌘↩ | Use Output as Input (sends it to the tool that recognizes it, e.g. Base64 → JSON) |
| ⌘K | Clear Input (undoable) |
| ⌘1 … ⌘9 | Jump to the first nine tools; ⌥⌘[ and ⌥⌘] for previous and next |
| ⇧⌘F | Filter Tools (⌘F does too when no text is focused) |
| ⌘F, ⌘G, ⌥⌘F | Find, Find Next, Find and Replace in the focused text |
| ⌘O | Open a text file into the current tool (Hash: hash a file) |
| ⌘R | Generate new IDs (UUID and ULID) |
| ⌥⌘L | Stack input and output vertically |

A global shortcut to bring Devkit forward and paste and detect can be set in Settings ▸
Shortcuts (not set by default).

## Permissions

None. No network access, no accounts, no analytics.

## Not there yet

YAML/CSV/XML converters, HTML entities, URL parser, cron, QR codes, certificates, RS/ES JWT
signatures, a menu bar item, hiding or reordering tools, URL scheme and Shortcuts actions.
No HTML or Markdown preview (that would need a web view).

## Develop

```sh
scripts/test.sh Devkit             # unit tests (published test vectors for every tool)
scripts/run.sh Devkit              # build a debug .app and open it
scripts/check.sh Devkit --perf     # tests, release bundle, smoke test, perf budgets
```

Logic lives in `Sources/DevkitCore` (pure, tested). Views and wiring live in `Sources/Devkit`.

Test hooks (environment variables), so scripted runs never touch your clipboard or settings:

- `DEVKIT_PASTEBOARD=<name>`: use a private named pasteboard instead of the clipboard.
- `DEVKIT_DEFAULTS=<suite>`: keep settings in a separate UserDefaults suite.
- `DEVKIT_APPEARANCE=light|dark`: force an appearance for screenshots.
- `DEVKIT_NOW=<unix seconds>`: pretend it's this time (JWT expiry, relative dates).

```sh
scripts/drive launch build/Devkit.app --env DEVKIT_PASTEBOARD=devkit-test --env DEVKIT_DEFAULTS=devkit-test
```
