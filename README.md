<img src="brand/logo.svg" width="72" height="72" alt="Slopapp logo">

# Slopapp

**Native Mac apps, made with care.**

Slopapp is a growing collection of small, native Mac apps for everyday work: clipboard
history, screenshots, opening links in the right browser, shrinking images. Free and open
source (MIT), written in Swift, with no subscription, no account and no tracking.

## Build order

| | App | What it does | An alternative to | Status |
|---|---|---|---|---|
| 1 | Switchboard | Open every link in the right browser | OpenIn | Planned |
| 2 | Clips | Clipboard history you can search | Paste | Planned |
| 3 | Snapper | Screenshots, annotated and shared in seconds | CleanShot X | Planned |
| 4 | Squish | Smaller images and PDFs | Squash, PDF Squeezer | Planned |
| 5 | Convert | Convert audio, video and images | Permute | Planned |
| 6 | Tidy | Uninstall apps completely, clear out junk | CleanMyMac | Planned |
| — | [Awake](apps/Awake) | Keep your Mac awake from the menu bar | Lungo | Alpha (reference app) |

Next up: Dropper, Ruler, Iconsmith, Specimen, Zones and Crate. The full plan and specs are in
[`catalog/roadmap.json`](catalog/roadmap.json), and the research behind them is in
[`docs/setapp-inventory.md`](docs/setapp-inventory.md). We study how the originals work; we
don't copy their names, icons, copy or assets.

## Build it

Needs macOS 14+ and Xcode 16+ (Swift 6). No Xcode project; everything is SwiftPM.

```sh
scripts/run.sh Awake            # build and open an app
scripts/check.sh                # test, bundle and smoke-test every app (what CI runs)
scripts/new-app.sh switchboard  # start the next app from the roadmap
cd web && pnpm i && pnpm dev    # the website
```

- [`docs/dev-cycle.md`](docs/dev-cycle.md): how each app goes from research to blind test to ship.
- [`docs/design-system.md`](docs/design-system.md): the rules every app follows, so they feel like a set.
- [`docs/pipeline.md`](docs/pipeline.md): the build, test and bundle scripts.
- [`AGENTS.md`](AGENTS.md): conventions for contributors and coding agents.
- [`brand/BRAND.md`](brand/BRAND.md): name, voice, logo, colors.

## Repo

```
apps/        One Swift package per app, plus SlopKit (shared code and components)
brand/       Logo, colors, voice. The product name lives in brand/brand.json
catalog/     Roadmap of planned apps (feeds new-app.sh and the website)
docs/        Inventory, design system, dev cycle, pipeline, per-app research
scripts/     Scaffold, test, bundle, smoke-test, icon generation
templates/   What new-app.sh copies
web/         Next.js landing page (static export)
```

Not affiliated with Setapp or MacPaw.
