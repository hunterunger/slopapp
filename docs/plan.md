# Slopapp build plan

The plan for building out the suite, from today to the full catalog. The order follows
the owner's favourite Setapp apps (ranked by real use), then groups apps that share
capabilities, so each app makes the next one cheaper. Every app goes through the 5-step
cycle in [`dev-cycle.md`](dev-cycle.md). Status as of 2026-11-09.

## Phase 0: Foundation (done)

- [x] Inventory of Setapp's top apps and the owner's favourites ([`setapp-inventory.md`](setapp-inventory.md))
- [x] Brand ([`../brand/BRAND.md`](../brand/BRAND.md)), website (`web/`)
- [x] Build pipeline: scaffold, test, bundle, smoke, perf, icons, CI ([`pipeline.md`](pipeline.md))
- [x] Design system + SlopKit shared components ([`design-system.md`](design-system.md))
- [x] Dev-cycle tooling: SlopDrive, researcher and blind-tester agents, `build-app` skill
- [x] Repo on GitHub (public), website + update feed on GitHub Pages, 8 apps released (2026-11-03)
- [x] CI green on GitHub's runners (macOS 26 / Xcode 26.6), all apps, 2026-11-07. The SDK is
      now stamped with vtool after linking; Paper's and Convert's earlier failures are gone.
- [ ] Owner decisions (below)

## Phase 1: Ship Switchboard (OpenIn)

- [x] Research, build, self-test (57 tests, every v1 item)
- [x] Blind test rounds until clean (2 rounds, 2026-11-03); released as beta 0.2.0
- [ ] Owner uses it as the default browser for a week, then beta

Switchboard replaces the owner's most-used app, so a week of daily use is the real test.

## Phase 2: Launcher and releases

The Slopapp app itself: the hub that installs and updates the rest, like Setapp's app.

- Release pipeline: per-app tags, signed and notarized zips on GitHub Releases, a
  published catalog feed (the website's `catalog.json`).
- Launcher v1: browse and search the catalog; install, update, uninstall; "update all";
  menu bar item with installed apps and pending updates; links to recommended open-source
  apps we don't rebuild (Rectangle, Maccy, IINA, Keka, AlDente).
- Apps downloaded outside the launcher update through Sparkle (the standard open-source
  Mac updater), reading the same feed.
- Status: the launcher is built and released (beta 0.2.2, 2026-11-09) as a `.dmg`, signed with
  Developer ID and notarized in CI.

## Phase 3: The favourites, priority 1

| # | App | Original | Size | Shares with |
|---|---|---|---|---|
| 1 | Clips | Paste | M | Library window, global hotkey panel |
| 2 | Squish | Squash, PDF Squeezer | S | **File drop queue** (new shared component) |
| 3 | Snapper | CleanShot X | L | **Screen capture + region overlay** (new shared component) |
| 4 | Convert | Permute | M | File drop queue |
| 5 | Tidy | CleanMyMac | L | Library window, file scanning |

All five are built. Beta: Clips, Snapper, Tidy. Alpha: Squish, Convert.

Squish moves ahead of Snapper: it's small, an early second release, and it builds the
file drop queue that Convert, Iconsmith and Crate reuse. Snapper is split into v1
(capture, quick-access thumbnail, annotate, pin) and v2 (recording, scrolling capture, OCR).

## Phase 4: The favourites, priority 2

Cheaper once phase 3's shared components exist.

| App | Original | Size | Reuses |
|---|---|---|---|
| Dropper | Sip | S | Capture overlay, global hotkey |
| Ruler | PixelSnap | M | Capture overlay |
| Zones | World Clock Pro | S | Menu bar archetype |
| Iconsmith | Image2icon | M | File drop queue, `icongen` |
| Crate | Archiver | M | File drop queue |
| Specimen | Typeface | M | Library window |

All six are built. Beta: Dropper, Zones, Crate. Alpha: Ruler, Iconsmith, Specimen.

## Phase 5: Later

- Big favourites: Paper (Nitro PDF Pro), Commit (Gitfox). Each is a product of its own;
  scope each one carefully before starting.
- Popular apps outside the favourites: Tally, Devkit, Focus, Gauge.
- Awake predates the dev cycle: its research pass is done (2026-11-03); a blind test is still
  owed.

Built (alpha): Paper, Commit, Tally, Devkit, Focus, Gauge.

## Owner's picks (2026-11-07)

Built on 2026-11-07 (alpha, installed on the owner's Mac, Developer ID signed):
**Commit** (Gitfox), **Dictate** (the owner's Better Transcriber, moved in), **Gauge** (iStat Menus,
public APIs only), **Triggers** (BetterTouchTool), **Shorthand** (TextExpander) and a real **disk map
in Tidy** (DaisyDisk). Also: herbarium icons for every app, the Nordic launcher and website, store
screenshots (Snapper, Switchboard).

Still owed for each new app: the on-screen walkthrough (needs an unlocked Mac with the owner away),
the owner's hand tests (listed in each research doc), blind test rounds, then beta and a release.

Skipped: **Tuck** (Bartender; hiding icons on macOS 27 needs private, fragile behaviour), video
downloaders (no legal risk wanted), Safari extensions and proxies. Removed from the roadmap (owner, 2026-11-07): Snip, Tiles,
Switches, Quit, Shelf, Margin, Hours, Twins, Glance, Seek and Dual.

Done since: Developer ID signing and notarization in CI (GitHub secrets; notarized with an App
Store Connect API key, 2026-11-09).

Open owner decisions: archiving Better Transcriber's repo after the switch-over.

## Running alongside every phase

- **Suite review every ~3 apps.** Use the apps side by side, update the design system,
  move repeated code into SlopKit.
- **Website.** A page per app with real screenshots, changelogs, download buttons fed
  by the release pipeline.
- **Open source hygiene.** CONTRIBUTING, issue templates, privacy statement, a license
  check for dependencies.

## Owner decisions

| Decision | Why it matters | Recommendation |
|---|---|---|
| Apple Developer ID ($99/yr) | Without it macOS warns on every download and the launcher can't install cleanly | Done: releases are signed and notarized in CI |
| GitHub repo and domain | Bundle IDs (`app.slopapp.*`), the update feed and download links are hard to change after the first release | Done: `hunterunger/slopapp`, `app.slopapp.*`, feed on GitHub Pages |
| Launcher before or after Clips | Launcher makes the suite feel real; Clips is another daily-use app | Done: both shipped as beta 0.2.0 |
| Mac App Store | Sandboxing rules out several apps (Tidy, Snapper features, Switchboard's handoffs) | Skip; ship direct |
