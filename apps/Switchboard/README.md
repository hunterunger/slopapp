# Switchboard

Open every link in the right browser.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to OpenIn.

**Status:** beta (0.2.0)

## What it does

Switchboard stands in as your default browser. When you click a link anywhere:

- If a rule knows where it goes, it opens there. No UI, about 10 ms of overhead.
- Otherwise a list of your browsers appears at the pointer, with the link's website and path
  on top. Press **1–9**, or move with **↑/↓** (or Tab) and press **Return**, or click.
  - Hold **⌘** while picking to always open that website there (creates a rule).
  - Hold **⇧** to open it in the background. **⌘C** (or the copy button) copies the link.
    **Esc** cancels.
  - Right-click a row, or use its **…** button, for Open / Open in Background / Always Open
    Here.
  - Many browsers? The list scrolls so it always fits on screen. Settings → General → Picker
    size makes rows smaller or larger.
- Hold **⌥** while clicking a link to always get the picker. The browser your rules would have
  chosen is already highlighted, so Return opens it there.
- **Open Link from Clipboard** finds the first link in whatever you copied (even inside a
  sentence) and shows the picker, again with the rules' choice highlighted.

Rules match a website (`example.com`, `*.example.com`; paste a whole URL and it's split into
website + path), a path (`/docs`), the app the link came from, and keys held. Rules are checked
top to bottom; ones that can never run (a broader rule above catches their links, or they need
the "always show the picker" key, which wins) are flagged. Removing a browser keeps the rules
that use it: they show the picker until you add it back, then reconnect. Deleting rules or
browsers can be undone (Undo button next to the list, or ⌘Z). Chrome, Edge, Brave and other Chromium browsers can be targeted per
profile; Chromium and Firefox can open private windows.

Optional: **Remove tracking from links** (General) drops ad and newsletter tags such as
`utm_source`, `fbclid` and `gclid` before a link opens or is matched. Off by default; it uses a
fixed offline list and never changes other parameters.

No network access, no accounts, no tracking. Settings live in
`~/Library/Application Support/app.slopapp.switchboard/config.json`.

## Setup

1. Open Switchboard. A signpost appears in the menu bar.
2. Choose **Make Default Browser…** and confirm in the macOS dialog.
   Switchboard then starts at login so links never wait for it.
3. Optional: Settings → Browsers to reorder, hide or add profiles; Settings → Rules for rules.

To stop: menu bar → **Stop Being Default Browser** → pick the browser to hand back to.

If macOS won't let Switchboard read a Chromium browser's profile list (macOS 27 protects other
apps' data), add the profile by its folder name (shown at `chrome://version` → Profile Path),
or give Switchboard Full Disk Access. Switchboard checks the folder exists, since a wrong name
would make Chrome create a new, empty profile.

Known limits: Chrome-based browsers bring themselves forward even when asked to open a link in
the background. Safari private windows and Safari profiles aren't supported yet (they need
Accessibility scripting).

## Develop

```sh
scripts/test.sh Switchboard            # unit tests (routing, patterns, profiles, ...)
scripts/run.sh Switchboard             # build a debug .app and open it
scripts/check.sh Switchboard --perf    # tests, release bundle, smoke test, perf budgets
```

Testing without touching your default browser: send links straight to the app.

```sh
APP="$PWD/build/Switchboard.app"
scripts/drive launch "$APP" --env SWITCHBOARD_DRY_RUN=1 --env SWITCHBOARD_LOG=/tmp/sb.log \
  --env SWITCHBOARD_CONFIG=/tmp/sb-config.json
open -a "$APP" 'https://example.com/'      # picker appears; decisions + timings in /tmp/sb.log
open -a "$APP" "switchboard://open?url=https%3A%2F%2Fexample.com&pick=1"   # force the picker
```

| Variable | Effect |
|---|---|
| `SWITCHBOARD_DRY_RUN=1` | Decide and log, don't open anything (and never change the default browser) |
| `SWITCHBOARD_LOG=<file>` | Append routing decisions and timings |
| `SWITCHBOARD_CONFIG=<file>` | Use this settings file |
| `SWITCHBOARD_APPEARANCE=light\|dark` | Force an appearance (screenshots) |
| `SWITCHBOARD_ASSUME_DEFAULT=1` | Show the "is the default browser" state without being it (screenshots of a test copy) |
| `SWITCHBOARD_SETTINGS_TAB=general\|browsers\|rules\|about` | Open Settings on that tab at launch (screenshots without Accessibility) |
| `SWITCHBOARD_FLIP_APPEARANCE_AFTER=<seconds>` | Switch light ↔ dark once while running (checks live appearance changes) |

Bundling registers the app with LaunchServices as a *candidate* browser (it never becomes the
default by itself). To unregister a build:
`/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u build/Switchboard.app`
