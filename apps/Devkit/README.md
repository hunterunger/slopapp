# Devkit

Offline developer tools: JSON, Base64, JWT, hashes and more.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to DevUtils.

**Status:** alpha (0.1.0)

## What it does

33 tools in one window, all offline. Nothing you paste ever leaves your Mac. Every tool
has the same layout: options along the top, input on the left with **Clipboard**,
**Sample** and **Clear**, output on the right with **Copy**.

| Tool | Does |
|---|---|
| JSON | Format, minify, validate (strict RFC 8259) with line and column errors. Keeps key order and number text exactly (`12345678901234567890` stays as written). Sort keys, 2/4 spaces or tab. Handles 50 MB documents off the main thread. |
| JWT | Decodes header and payload, shows `exp`/`nbf`/`iat` as dates, verifies HS256/384/512 with a secret and RS/PS/ES 256/384/512 with a public key (PEM, certificate, JWK or JWK Set). |
| Base64 | Encode (standard or URL-safe, with or without padding) and decode (either alphabet, padding optional). Binary results show as a hex dump. |
| Unix Time | Seconds, milliseconds, microseconds or nanoseconds (guessed by size) to local, UTC, ISO 8601, RFC 2822 and relative time; dates back to timestamps. |
| Regex | ICU regular expressions with live highlighting, groups (named too), and replacement preview. Runaway patterns stop after half a second. |
| URL Encode | Percent-encode a component or a whole URL; decode with or without `+` as space. |
| URL Parser | Scheme, user, host, port, path segments, fragment, each query parameter decoded, and the query string as JSON (repeated keys become arrays). |
| HTML Entities | Escape (only `& < > " '`, or non-ASCII by name or number) and unescape all 2,125 named references from the HTML standard. |
| Backslash Escape | Escape and unescape C-family string literals (`\n`, `\t`, `\"`, `\u00e9`, `\u{1F600}`, `\x41`, octal). |
| UUID and ULID | Generate v4, v7 or ULIDs, up to 1,000 at once; inspect any UUID or ULID. |
| Text Diff | Line diff side by side or unified, with changed characters highlighted. |
| YAML to JSON / JSON to YAML | YAML 1.2 (so `no` stays a string), anchors, merge keys, several documents. JSON to YAML keeps key order and uses `|` blocks for multi-line text. |
| Number Base | Binary, octal, decimal, hex and any base 2–36, for integers of any size. |
| HTML / CSS / XML Format | Beautify or minify. HTML keeps inline elements on one line and leaves `<pre>` alone; CSS also handles SCSS and LESS; XML is validated. |
| SQL Format | Clauses on their own lines, column lists and conditions indented, subqueries nested; keywords upper, lower or as typed; minify. |
| Lorem Ipsum | Paragraphs, sentences or words. |
| QR Code | Make a QR code (error correction L/M/Q/H, save as PNG, drag out, copy) or read one from an image (drop, open or paste), with Vision. |
| String Inspector | Characters, words, lines, sentences, bytes (UTF-8 and UTF-16) and every character's code point, name and bytes. |
| JSON to CSV / CSV to JSON | RFC 4180 quoting, delimiter detection, nested objects flattened to `parent.child` columns, numbers detected (but ZIP codes stay text). |
| Hash | MD5, SHA-1, SHA-256, SHA-384, SHA-512 (or HMACs) of text or a file of any size; compare with a published checksum. |
| Text Case | camelCase, PascalCase, snake_case, kebab-case, CONSTANT_CASE and more. |
| Cron | Explains an expression in plain English and lists the next runs in local time or UTC. 5 or 6 fields, names, `@daily`-style macros. |
| Color | Hex, `rgb()`, `hsl()`, `hsb()` in, every format out (plus SwiftUI and AppKit code and WCAG contrast). |
| Random String | Passwords, tokens and license-key style strings from the system's secure generator, with the entropy shown. |
| SVG to CSS | An SVG as a `background-image` data URI, URL-encoded or Base64. |
| Certificate | X.509 certificates or whole chains: subject, issuer, validity, key, names, usages, fingerprints. |
| Hex and Text | Text to the hex of its UTF-8 bytes and back. |
| Sort Lines | Sort (A–Z, Z–A, natural, by length, reverse, shuffle), remove duplicates and empty lines, trim. |
| GZip | Compress (gzip, zlib or raw deflate, as Base64 or hex) and decompress (format detected). |

### Paste and Detect

Press **⇧⌘V** anywhere in Devkit: it reads the clipboard once, picks the tool that fits
(a JWT, JSON, a certificate, HTML, XML, SVG, SQL, a cron expression, CSS, YAML, CSV, a URL
with a query, gzip data, a UUID, a timestamp, a color, URL-encoded, Base64, HTML-entity or
backslash-escaped text, `0x` numbers) and fills it in. If nothing matches, the text goes
into the current tool.

**⇧⌘R Replace Clipboard** does the same and puts the result straight back on the clipboard
(for example, a minified JSON on the clipboard becomes formatted JSON).

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
| ⇧⌘R | Replace Clipboard with the detected tool's output |
| ⌥⌘V | Paste the clipboard into the current tool (no detection) |
| ⌘R | Generate again (UUID and ULID, Lorem Ipsum, Random String) |
| ⌘/ | Search tools |
| ⌥⌘T | Keep the window on top of other apps |
| ⌥⌘L | Stack input and output vertically |

A global shortcut to bring Devkit forward and paste and detect can be set in Settings ▸
Shortcuts (not set by default). **Settings ▸ General ▸ Show in menu bar** adds a menu bar
icon (off by default); with it on, closing the window keeps Devkit in the menu bar.
Tools can be hidden from the sidebar (right-click a tool, or Settings ▸ Advanced).

## Permissions

None. No network access, no accounts, no analytics.

## Not there yet

JavaScript/ERB beautifying, HTML to JSX, cURL to code, JSON to code, PHP serializers, Base64
images, JWT signing, QR templates (Wi-Fi, SMS) and logos, reordering tools, URL scheme and
Shortcuts actions. No HTML or Markdown preview (that would need a web view).

YAML parsing uses [Yams](https://github.com/jpsim/Yams) (MIT, wraps libyaml).

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
- `DEVKIT_SEED=<number>`: repeatable Lorem Ipsum and Random String output.
- `DEVKIT_SNAPSHOT=<folder>`: draw every tool (with its sample) and Settings to PNGs, light
  and dark, then quit. Only Devkit's own windows; works with the screen locked.

```sh
scripts/drive launch build/Devkit.app --env DEVKIT_PASTEBOARD=devkit-test --env DEVKIT_DEFAULTS=devkit-test
```
