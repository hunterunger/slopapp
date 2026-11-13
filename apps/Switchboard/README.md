# Switchboard

Open every link in the right browser.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to OpenIn.

**Status:** stable (1.0.0)

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
website + path), a path (`/docs`), the app the link came from, and keys held. Rules can also be
for email links (match the address: `example.com` or `name@example.com`) or for files (match
the type: `pdf, docx`). Rules are checked
top to bottom; ones that can never run (a broader rule above catches their links, or they need
the "always show the picker" key, which wins) are flagged. Removing a browser keeps the rules
that use it: they show the picker until you add it back, then reconnect. Deleting rules or
browsers can be undone (Undo button next to the list, or ⌘Z). Chrome, Edge, Brave and other Chromium browsers can be targeted per
profile; Chromium and Firefox can open private windows.

**Safari profiles and private windows** (Settings → Browsers → + → Safari Profiles… or
Safari, Private Window): Safari has no way for other apps to ask for either, so Switchboard
picks the window from Safari's File menu and then opens the link there. This needs
**Accessibility** (Settings shows where to turn it on). Without it, those links aren't opened at
all (never silently in a normal window); a message says why and Reopen brings the link back.

**Email links** (Settings → Email): make Switchboard the default email app (macOS asks you to
confirm; Give Back To hands it to Mail or another app again). Email links then go to a mail
app or to webmail in the browser and profile you choose: Gmail (pick the account), Outlook
(work or school, or Outlook.com), Fastmail, Yahoo Mail, Proton Mail, or any webmail with a
compose address like `https://mail.example.com/compose?to={to}&subject={subject}`. They get
their own picker (number keys follow the Email list), rules and "when no rule matches". The
list starts with the mail apps installed, Mail first.

**Files** (Settings → Files): Switchboard can open PDF documents, web locations (`.webloc`,
`.url`) and any type you add, so rules decide where they go (say, PDFs from Slack in your work
profile). Each type remembers the app it opened in before and keeps opening there unless a
rule says otherwise. For a web location, the link inside goes through your rules.

**Rewrite** (Settings → Rewrite), applied to web links in this order before rules:

- Remove tracking from links (off by default): drops tags such as `utm_source`, `fbclid` and
  `gclid` using a fixed offline list; other parameters are kept.
- Rewrite links: find and replace, plain or a regular expression with `$1`-style groups, on
  one website or all (`example.com` also covers `www.`; `*.example.com` covers every
  subdomain). A rewrite that produces another app's link (`vscode://…`) opens that app; if no
  app on the Mac opens those links, the rewrite is skipped and the link opens as it was.
- Open in apps (off until you turn each on): Zoom meetings, Microsoft Teams, Apple Music,
  Podcasts, App Store pages, Spotify, Figma, Slack channels, Notion, Linear and Discord links
  open in their app when it's installed, and in your browser when it isn't. A link an app sends out is never sent back to it, and
  holding the picker key (⌥) shows the browsers instead.

**Settings file** (General): Export… writes everything as one readable JSON file; Import…
shows what it will do first, then adds to your settings (new rules go after yours) or replaces
them. Either can be undone with ⌘Z.

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

## Not there yet

- Chrome-based browsers bring themselves forward even when asked to open a link in the
  background.
- Safari profiles and private windows depend on Safari's File menu and on the new window
  coming to the front in time; they haven't been tried against every Safari version and
  language. Safari's own Settings → Websites → Open Links With Profiles is the alternative.
- The webmail compose addresses come from each service's public documentation; Fastmail's and
  Proton's haven't been tried with a signed-in account yet.
- Becoming the default email app or a file type's app goes through macOS's own settings; it
  hasn't been tried on a Mac that isn't a test machine yet.
- No `tel:` links, recent-links history, Shortcuts actions or Share menu yet. Google Meet has
  no Mac app to hand links to; Webex isn't in Open in apps yet.

## Develop

```sh
scripts/test.sh Switchboard            # unit tests (routing, patterns, profiles, ...)
scripts/run.sh Switchboard             # build a debug .app and open it (quits any running Switchboard, your installed one too)
scripts/check.sh Switchboard --perf    # tests, release bundle, smoke test, perf budgets
```

Testing without touching your default browser: run a separate copy with `--direct` (it gets
its own process even while your installed Switchboard runs) and hand it links through the test
inbox instead of `open`. `open -a`, and `drive launch` without `--direct`, go to the installed
copy (it has the same bundle id), so links would really open and `--env` would be ignored.

```sh
scripts/bundle.sh Switchboard
APP="$PWD/build/Switchboard.app"
mkdir -p /tmp/sb-inbox
scripts/drive launch "$APP" --direct --env SWITCHBOARD_DRY_RUN=1 --env SWITCHBOARD_LOG=/tmp/sb.log \
  --env SWITCHBOARD_CONFIG=/tmp/sb-config.json --env SWITCHBOARD_INBOX=/tmp/sb-inbox
# One link per file; decisions and timings land in /tmp/sb.log.
printf 'url=https://example.com/\n' > /tmp/sb-inbox/t.tmp && mv /tmp/sb-inbox/t.tmp /tmp/sb-inbox/1.link
printf 'url=mailto:ann@example.com\nsource=com.tinyspeck.slackmacgap\nmodifiers=option\n' > /tmp/sb-inbox/t.tmp && mv /tmp/sb-inbox/t.tmp /tmp/sb-inbox/2.link
```

`scripts/drive` addresses that copy by its pid (`drive apps --paths`). For a copy that can't be
confused with the installed one at all, copy the bundle elsewhere and give it another bundle id
(`plutil -replace CFBundleIdentifier …`, then `codesign --force --sign -`).

| Variable | Effect |
|---|---|
| `SWITCHBOARD_DRY_RUN=1` | Decide and log, don't open anything. Becoming the browser, email app or a file type's app only changes an in-memory copy of macOS's settings |
| `SWITCHBOARD_LOG=<file>` | Append routing decisions and timings |
| `SWITCHBOARD_CONFIG=<file>` | Use this settings file |
| `SWITCHBOARD_INBOX=<folder>` | Route `*.link` files dropped there (`url=`, optional `modifiers=option,command`, `source=<bundle id>`, `pick=1`) as if macOS had sent them |
| `SWITCHBOARD_RENDER_DIR=<folder>` | With the inbox: `render=<name>` draws Switchboard's open windows into PNGs there (works with the screen locked); `tab=<name>` and `sheet=<name>` open a Settings tab or sheet first |
| `SWITCHBOARD_MENU_PROBE=<bundle id>` | At launch, log the shape of that running app's File menu as Switchboard reads it for Safari windows: positions and shortcuts, never titles (reads only) |
| `SWITCHBOARD_APPEARANCE=light\|dark` | Force an appearance (screenshots) |
| `SWITCHBOARD_ASSUME_DEFAULT=1` | Show the "is the default browser" state without being it (screenshots of a test copy) |
| `SWITCHBOARD_SETTINGS_TAB=general\|browsers\|email\|files\|rules\|rewrite\|about` | Open Settings on that tab at launch (screenshots without Accessibility) |
| `SWITCHBOARD_FLIP_APPEARANCE_AFTER=<seconds>` | Switch light ↔ dark once while running (checks live appearance changes) |

`scripts/perf.sh` (and `check.sh --perf`) launch without `--direct`, so while the installed
copy runs they measure that one. Measure a `--direct` copy by pid with `scripts/drive stats`.

Bundling registers the app with LaunchServices as a *candidate* browser, email app and viewer
for the file types above (it never becomes the default for any of them by itself; the file
types are declared at the lowest rank, so macOS never picks it on its own). To unregister a build:
`/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u build/Switchboard.app`

### Store screenshots

`scripts/shots.sh Switchboard` takes the set listed in `showcase.json` (scenes in
`Sources/Switchboard/Showcase.swift`, all made-up content) and writes `web/public/shots/switchboard/`. See
[docs/screenshots.md](../../docs/screenshots.md).
