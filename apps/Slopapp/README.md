# Slopapp

Every Slopapp app, installed and up to date.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps. This is the
hub: browse the catalog, install an app in one click, keep them all current, remove them
cleanly. An open alternative to Setapp's own app, minus the account and the subscription.

**Status:** beta (0.2.0)

## What it does

- **Discover**: every app in the catalog. Released apps have an Install button; planned
  ones say Coming Soon. Search (⌘F) matches names, taglines, categories and the paid app
  each one replaces ("Paste" finds Clips).
- **App page**: tagline, what it's an alternative to, version, download and installed
  size, category, minimum macOS, release notes, and every copy found on this Mac.
- **Install**: downloads the zip, checks it (see Trust model), puts it in
  `/Applications/Slopapp` (or `~/Applications/Slopapp` when `/Applications` isn't
  writable), and opens it (Settings: "Open apps after installing", on). Menu bar apps have
  no window, so Slopapp says where they went ("Opened Clips. It's in your menu bar.").
  A note under the button confirms what changed ("Installed version 1.0.0.").
- **Installed**: the apps on this Mac, with version, location and a label for unsigned
  development builds. Open, Update, Reveal in Finder, Move to Trash.
- **Updates**: installed → available version, size and release notes. Update one, or
  Update All (⇧⌘U). An app that's running is quit after you confirm, then reopened. A
  short confirmation says what changed, and "Recently Updated" lists the last week's updates.
- **Reinstall** (⋯ menu, right-click, Apps menu) downloads and verifies the catalog's
  version again over the installed copy, to repair it.
- **Move to Trash…**: the app goes to the Trash; optionally its settings and data too
  (`~/Library/Application Support/<bundle id>`, `Preferences/<bundle id>.plist`,
  `Caches/<bundle id>`, `HTTPStorages/<bundle id>`, `Saved Application State`). Undo (⌘Z,
  or the Undo button) puts everything back. The banner says whether settings went too, and
  goes away if the app is installed again.
- **Changes made outside Slopapp** show up right away: the install folders are watched (kernel
  file events, no polling), and Slopapp re-checks on launch, when it comes forward, on
  Check for Updates and before opening an app.
- **Apps installed elsewhere** are found through LaunchServices. Copies in `/Applications`
  or `~/Applications` (for example, downloaded from the website) are updated and removed
  in place. Copies anywhere else (a development build in `build/`, Downloads) are shown
  and can be opened, but Slopapp never changes them; "Install a Copy in Applications" is
  in the app page's ⋯ menu.
- **Also Great**: free, open-source apps we don't rebuild (Rectangle, Maccy, IINA, Keka,
  AlDente, Stats). Links to their websites; "Installed" and Open when they're already here.
- **Menu bar**: the number of pending updates next to the icon, Update All, the installed
  apps (pick one to open it), Open Slopapp, Check for Updates. Hide it in Settings.

The Dock icon shows only while the window is open; with the window closed Slopapp lives in
the menu bar. If you hide the menu bar icon, closing the window quits.

## Keyboard

| Shortcut | Action |
|---|---|
| ⌘1 – ⌘4 | Discover, Installed, Updates, Also Great |
| Arrows, Return | Move through apps (Discover, results, Installed); show details |
| ⌘[ | Back |
| ⌃⌘S | Show/Hide Sidebar |
| ⌘F | Search (Return opens the first or selected result) |
| ⌘↓ | Show Details of the selected app |
| ⌘R | Check for Updates |
| ⌘O | Install / Update / Open the app whose page is showing, or the selected one |
| ⇧⌘R | Reveal in Finder |
| ⌘⌫ | Move to Trash… |
| ⇧⌘U | Update All |
| ⌘Z | Undo Move to Trash |

## Network and privacy

Slopapp makes exactly two kinds of requests, both plain HTTPS GETs with no cookies, no IDs
and a generic `User-Agent: Slopapp`:

1. **The feed** (`feed.json`, see `brand/brand.json` `feedUrl`): on first launch, when you
   choose Check for Updates, and in the background **at most once every 6 hours** while
   Slopapp is running (scheduled by macOS with `NSBackgroundActivityScheduler`, plus a
   check after wake if one is overdue). No polling.
2. **The apps and icons you ask for** (GitHub Releases).

No analytics, telemetry, crash reporting or accounts. Nothing installs on its own: updates
are only downloaded when you click Update.

## Trust model

An app only lands in Applications if every one of these holds. Any failure stops the
install with a one-line reason, and nothing on disk changes (the old copy stays):

1. **The feed comes over HTTPS** from the address compiled into Slopapp (`SlopappFeedURL`
   in Info.plist, from `brand.json`). Download URLs must be HTTPS too.
2. **sha256**: the downloaded zip must match the feed's checksum byte for byte. This ties
   the download to the feed: a swapped or corrupted file on the download server is refused.
3. **The zip contains exactly one app** whose bundle id and version match the feed entry.
4. **Code signature**: `SecStaticCodeCheckValidity` with strict validation, all
   architectures and nested code. A modified, unsigned or broken bundle is refused.
   - When `brand.json` has a `teamId` (compiled in as `SlopappTeamID`), the app must be
     signed by that Apple Developer team with a certificate that chains to Apple
     (`anchor apple generic`). A self-made certificate claiming the team doesn't pass.
   - Without a `teamId` (today, before the Developer ID exists), ad-hoc signatures are
     accepted, and such copies are labelled **Unsigned development build** in the app.
     In this mode the feed's sha256 over HTTPS is what ties a download to the release.
   - An update can never change signer: if the installed copy is signed by team X, the
     new version must be too.
5. Only after all checks pass is the quarantine flag cleared and the new copy swapped in
   (old copy moved aside, new copy moved in, old copy deleted; on failure the old copy is
   put back).

What this doesn't protect against: someone who controls both the feed's HTTPS host and the
release downloads while no `teamId` is set (they can publish a matching checksum for their
own ad-hoc build). Setting `teamId` closes that gap. Slopapp doesn't verify notarization
itself; Gatekeeper still assesses apps on first launch.

## Settings

General: Launch at login (off), Show in menu bar (on), Open apps after installing (on),
where apps install, last check time and Check Now. About.

## Develop

```sh
scripts/test.sh Slopapp     # unit + integration tests (real zips, ditto, codesign under /tmp/slopapp-test)
scripts/run.sh Slopapp      # debug build, open it (uses the real feed URL)
scripts/check.sh Slopapp    # the full gate
```

### Testing against a local feed (never your real Applications folder)

```sh
scripts/bundle.sh Awake && scripts/bundle.sh Slopapp
apps/Slopapp/test-feed.sh setup     # /tmp/slopapp-test: Testbed + Sandbox 1.0.0 (installable), Awake (installed elsewhere), served on localhost:8765
apps/Slopapp/test-feed.sh launch    # opens build/Slopapp.app with the overrides below
apps/Slopapp/test-feed.sh bump      # next Testbed + Sandbox (1.1.0, then 1.2.0...): two updates (then ⌘R in the app)
apps/Slopapp/test-feed.sh bad-sha   # next Testbed with a wrong checksum      -> refused
apps/Slopapp/test-feed.sh bad-sig   # next Testbed, modified after signing    -> refused
apps/Slopapp/test-feed.sh corrupt   # next Testbed as a damaged zip           -> refused
apps/Slopapp/test-feed.sh offline   # stop the server (serve starts it again) -> cached catalog + banner
apps/Slopapp/test-feed.sh clean     # stop, unregister the test apps from LaunchServices, delete /tmp/slopapp-test
```

The overrides (testing only; they also allow `file://` and `http://localhost` URLs):

| Variable | Effect |
|---|---|
| `SLOPAPP_FEED_URL` | Feed to use instead of the compiled-in one |
| `SLOPAPP_INSTALL_DIR` | Install here; nothing outside it is ever changed |
| `SLOPAPP_TRASH_DIR` | "Move to Trash" moves here instead |
| `SLOPAPP_LIBRARY_DIR` | Library folder for "Also remove its settings and data" |
| `SLOPAPP_APPEARANCE` | `light` or `dark`, for screenshots |

"Testbed" is a copy of Awake with its own bundle id, so there are two installable apps.
The test feed deliberately leaves out Switchboard and other apps in daily use: a second
copy with the same bundle id could make macOS pick the test copy (for example as the
default browser).

### Code layout

- `Sources/SlopappCore`: the feed model and parser, version compare, trust policy
  (`URLPolicy`, `SignaturePolicy`), inventory (where copies live and what may be changed),
  the catalog join, `Installer` and `Uninstaller`, the 6-hour schedule, the Also Great list.
  `System/` has the real implementations behind protocols: `Network` (URLSession, no
  cookies), `DittoUnarchiver`, `LocalFiles` (Trash, scratch folders, quarantine),
  `LocalAppLocator` and `CodeSignature` (LaunchServices + Security framework), `Checksum`.
- `Sources/Slopapp`: `Store` (state and actions), `Config` (Info.plist + env overrides),
  `RunningApps`, `Icons`, and the views.
- `Tests/SlopappCoreTests`: unit tests with fakes, plus integration tests that build tiny
  real app bundles, sign and zip them, and run the real installer against them.

### Not there yet

- Slopapp doesn't update itself yet: a newer Slopapp shows in its menu bar menu, but you
  download it from the website (self-replace and relaunch is next).
- No automatic installs, no update notifications (the menu bar count is the signal).
- No screenshots or long descriptions on app pages (the feed has no fields for them yet).
- Category filters, "Install all" for a new Mac, beta channel.
