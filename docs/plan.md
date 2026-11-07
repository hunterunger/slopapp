# Slopapp build plan

The plan for building out the suite, from today to the full catalog. The order follows
the owner's favourite Setapp apps (ranked by real use), then groups apps that share
capabilities, so each app makes the next one cheaper. Every app goes through the 5-step
cycle in [`dev-cycle.md`](dev-cycle.md). Status as of 2026-11-03.

## Phase 0: Foundation (done)

- [x] Inventory of Setapp's top apps and the owner's favourites ([`setapp-inventory.md`](setapp-inventory.md))
- [x] Brand ([`../brand/BRAND.md`](../brand/BRAND.md)), website (`web/`)
- [x] Build pipeline: scaffold, test, bundle, smoke, perf, icons, CI ([`pipeline.md`](pipeline.md))
- [x] Design system + SlopKit shared components ([`design-system.md`](design-system.md))
- [x] Dev-cycle tooling: SlopDrive, researcher and blind-tester agents, `build-app` skill
- [x] Repo on GitHub (public), website + update feed on GitHub Pages, 8 apps released (2026-11-03)
- [ ] CI green on GitHub's runners (macOS 26 / Xcode 26.6). Open: Paper's pending redaction marks
      don't survive save/reopen on macOS 26 (real bug); Convert's tests exceed 45 min on CI
      (no hardware encoder on the VMs).
- [ ] Owner decisions (below)

## Phase 1: Ship Switchboard (OpenIn)

- [x] Research, build, self-test (57 tests, every v1 item)
- [ ] Blind test rounds until clean (needs an unlocked Mac)
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
- Blocked on a Developer ID for frictionless installs. It can be built and tested before then.

## Phase 3: The favourites, priority 1

| # | App | Original | Size | Shares with |
|---|---|---|---|---|
| 1 | Clips | Paste | M | Library window, global hotkey panel |
| 2 | Squish | Squash, PDF Squeezer | S | **File drop queue** (new shared component) |
| 3 | Snapper | CleanShot X | L | **Screen capture + region overlay** (new shared component) |
| 4 | Convert | Permute | M | File drop queue |
| 5 | Tidy | CleanMyMac | L | Library window, file scanning |

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

## Phase 5: Later

- Big favourites: Paper (Nitro PDF Pro), Dual (ForkLift), Commit (Gitfox). Each is a
  product of its own; scope each one carefully before starting.
- Popular Setapp apps outside the favourites: Snip, Tally, Devkit, Focus, Gauge, Tiles,
  Shelf, Margin, Hours, Twins, Glance, Seek, Switches, Quit.
- Awake predates the dev cycle: give it a research pass and blind test when there's time.

## Owner's picks (2026-11-07)

The owner trimmed the later list. In order:

1. **Commit** (Gitfox): the one they're most excited about. v1 with a simple branch graph,
   unified diff only. Research: [`research/commit.md`](research/commit.md).
2. **Dictate**: the owner's own Better Transcriber, moved into Slopapp (old repo archived
   after the switch-over).
3. Eventually: **Gauge** (iStat Menus), **Tuck** (Bartender), **Triggers** (BetterTouchTool).
4. Lower priority: a **disk map in Tidy** (DaisyDisk / GrandPerspective: a visual map of
   what fills the disk, reusing Tidy's scan) and **Shorthand** (TextExpander / Rocket Typist).

Skipped: video downloaders (owner wants no legal risk), Safari extensions and proxies.
The remaining P3 apps (Snip, Tiles, Switches, Quit, Shelf, Margin, Hours, Twins, Glance,
Seek, Dual) are on hold; most can be skipped.

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
| Apple Developer ID ($99/yr) | Without it macOS warns on every download and the launcher can't install cleanly | Get it before phase 2 ships |
| GitHub repo and domain | Bundle IDs (`app.slopapp.*`), the update feed and download links are hard to change after the first release | Settle before the first release |
| Launcher before or after Clips | Launcher makes the suite feel real; Clips is another daily-use app | Launcher first, it's what makes this a suite |
| Mac App Store | Sandboxing rules out several apps (Tidy, Snapper features, Switchboard's handoffs) | Skip; ship direct |
