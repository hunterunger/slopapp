# Slopapp

A free, open-source collection of native Mac apps (an open alternative to Setapp). The name is a
joke; the apps aren't. Every app goes through the dev cycle in `docs/dev-cycle.md` (skill: `build-app`).
Brand: `brand/` (name lives in `brand/brand.json`). Research: `docs/setapp-inventory.md`.

## Repo map

| Path | What |
|---|---|
| `apps/SlopKit/` | Shared Swift package: settings, panels, HUD, drop zone, permissions, shortcuts. Gallery: `swift run --package-path apps/SlopKit SlopKitGallery` |
| `apps/<Name>/` | One Swift package per app. `app.json` is its manifest, `Icon.py` its icon spec. `Awake` is the reference app. |
| `catalog/roadmap.json` | Every planned app: name, tagline, Lucide icon, spec. `new-app.sh` reads it. |
| `templates/app/` | What `new-app.sh` copies |
| `scripts/` | The pipeline (see below). `scripts/icons/` generates and checks app icons |
| `brand/` | Brand (`BRAND.md`), app icon spec (`ICONS.md`), botanical plates for the icons (`plates/`) |
| `web/` | Next.js landing page. Reads `web/src/generated/catalog.json` |
| `docs/pipeline.md` | Build pipeline docs and the definition of done for an app |
| `docs/design-system.md` | The house style every app follows, with a review checklist |
| `docs/plan.md` | The build plan: phases, order, owner decisions |
| `docs/dev-cycle.md` | The 5-step cycle per app: pick, research, build, test, blind test |
| `docs/research/<slug>.md` | Per-app research: feature inventory, flows, blind test log |
| `tools/SlopDrive/` | Accessibility driver CLI, used via `scripts/drive` |
| `.claude/agents/` | `app-researcher`, `blind-tester` |

## Commands

```sh
scripts/new-app.sh <slug>        # scaffold apps/<Name> from catalog/roadmap.json (builds + tests it)
scripts/test.sh [Name...]        # unit tests (default: SlopKit + all apps)
scripts/run.sh <Name>            # debug .app, open it
scripts/bundle.sh <Name>         # release .app (universal, ad-hoc signed) + zip in build/
scripts/smoke.sh <Name>          # launch the .app, fail if it crashes
scripts/check.sh [Name...] [--perf]  # full gate: lint + test + bundle + smoke + catalog (+ perf). CI runs this.
scripts/lint.sh <Name>           # design-system detail rules grep can catch (radius literals, hex colours)
scripts/measure corners <png>    # pixel checks on a window shot: corners, spacing (line), contrast
scripts/perf.sh <Name>           # launch time, idle CPU, memory footprint vs budgets
scripts/drive help               # drive a running app: tree/click/menubar/type/key/shot
python3 scripts/icons/herbarium.py check|build|render [Name...]  # app icons (brand/ICONS.md)
python3 scripts/icons/export_web.py [Name...]  # the website's app icons and prints
node scripts/catalog.mjs         # regenerate the website catalog
cd web && pnpm dev               # website
```

Logs: `build/logs/<Name>-{build,test,sign,smoke,herbarium,icon}.log`.

## Adding an app

1. Research first (`docs/research/<slug>.md`), then `scripts/new-app.sh <slug>` (slug from `catalog/roadmap.json`).
2. Build the logic in `Sources/<Name>Core` with tests in `Tests/<Name>CoreTests`. Put system
   calls behind protocols and fake them in tests, as Awake does (`PowerAssertion`, `Scheduler`).
3. Build the UI in `Sources/<Name>`. Menu bar apps end their menu with `MenuFooter(info:)`.
4. Draw the icon: `new-app.sh` starts `apps/<Name>/Icon.py` on a free tile colour; follow
   `brand/ICONS.md` ("Drawing a new icon"), fetch its plate, then `herbarium.py check` and `render`.
   Commit `Icon.py`, the generated `AppIcon.icon` and the print in `brand/plates/prints/`.
5. `scripts/run.sh <Name>` and use it. Verify the real system effect.
6. `scripts/check.sh <Name>` must pass. Work through the definition of done in `docs/pipeline.md`.

## Rules

- Follow `docs/design-system.md`, including the §4 detail rules (concentric corners from
  `Radius`, even insets, alignment, hairlines, full-size window buttons). Pick an archetype (menu bar utility, drop-in window, library
  window, overlay) before writing UI, and grade against its review checklist.
- Use SlopKit instead of rolling your own: `SlopSettings` for every Settings window, `MenuFooter`
  in menu bar menus, `FloatingPanel`/`HUD` for overlays, `DropZone`, `PermissionGate`, `ShortcutRow`.
  Every app adds `@NSApplicationDelegateAdaptor(SlopAppDelegate.self)`.
- No hardcoded colors or fonts in apps: the user's accent color and system text styles only.
- Our apps must show no `[unlabeled]` controls in `scripts/drive tree`.
- Inspiration, not imitation: study the originals' flows and features, never copy their names,
  icons, copy, assets or signature visuals. Research originals read-only and never capture the
  owner's personal content from them (clipboard history, files, screenshots).
- New SwiftPM dependencies must be vetted, permissively licensed, pinned exactly, and listed in
  `docs/design-system.md`. Commit `Package.resolved`.

- Swift 6 language mode, strict concurrency, macOS 14+. UI and app state are `@MainActor`.
  Use `@Observable`, not `ObservableObject`.
- Swift Testing (`import Testing`, `@Test`, `#expect`) for all tests, not XCTest.
- No `.xcodeproj`, no project generators. Everything builds with SwiftPM + `scripts/`.
- **Never use SF Symbols in app icons or on the website** (Apple's license forbids it). App
  icons come from `apps/<Name>/Icon.py`, a Nordic herbarium spec (`brand/ICONS.md`) that
  generates `AppIcon.icon`; `check.sh` fails an icon that breaks the style. SF Symbols are fine
  inside app UI.
- No network calls, analytics, telemetry or accounts in apps. Data stays local. If a feature
  truly needs the network (e.g. currency rates), make it opt-in and say so in the README.
- Never call apps by Setapp app names or copy their designs. Mention what an app replaces
  only in `replaces` and READMEs.
- `app.json` is the source of truth for name, version, bundle id. Don't hardcode them in Swift
  (read `AppInfo.current(fallbackName:)`).
- Generated output (`build/`, `.build/`) is not committed.
