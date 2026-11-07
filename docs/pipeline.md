# The app pipeline

How an Slopapp app goes from an idea in the roadmap to a zip on GitHub Releases.
Everything is plain text and shell scripts: no `.xcodeproj`, no project generators.
Each app is a Swift package, and the scripts turn it into a real `.app`.

```
catalog/roadmap.json ──new-app.sh──▶ apps/<Name>/ ──test.sh──▶ tested core
                                        │
                                   bundle.sh ──▶ build/<Name>.app + .zip ──smoke.sh──▶ launches
                                        │
                        git tag <slug>-v<version> ──release.yml──▶ GitHub Release
                                        │
                                  catalog.mjs ──▶ web/src/generated/catalog.json (website)
```

## Requirements

macOS 14+, Xcode 16+ (Swift 6), `python3` and `perl` (ship with the Xcode command line
tools), `node` for the catalog. `jq` is used when present (macOS 15+ ships it).

## Layout of an app

```
apps/Awake/
  app.json            manifest: name, tagline, icon, version, bundle id... (source of truth)
  Icon.svg            Lucide glyph, vendored. Becomes the app icon.
  Package.swift       depends on ../SlopKit
  Sources/AwakeCore/  pure logic. No views. System calls behind protocols.
  Sources/Awake/      SwiftUI app: @main, MenuBarExtra or WindowGroup
  Tests/AwakeCoreTests/  Swift Testing tests for the core
  README.md
  Awake.entitlements  (optional) passed to codesign
```

`apps/SlopKit` is shared by every app: brand colors, `AppInfo`, `LaunchAtLogin`,
the standard menu footer (Launch at Login / About / Quit), and the About window.

## Scripts

| Command | What it does |
|---|---|
| `scripts/new-app.sh <slug>` | Scaffolds `apps/<Name>` from its roadmap entry, vendors the icon, runs its tests. |
| `scripts/test.sh [Name...]` | `swift test` for SlopKit and each app. Quiet on success; prints the log tail on failure. |
| `scripts/bundle.sh <Name> [--debug]` | Builds and assembles `build/<Name>.app`, signs it, zips it. |
| `scripts/smoke.sh <Name> [--no-bundle]` | Launches the bundled app; fails if it crashes or exits within 3s. |
| `scripts/run.sh <Name>` | Debug bundle, quit any running copy, open it. |
| `scripts/check.sh [Name...]` | The full gate: tests + release bundle + smoke for every app, then catalog. CI runs this. |
| `node scripts/catalog.mjs` | Merges roadmap + every `app.json` into the website catalog. |
| `swift scripts/icongen.swift <svg> <icns> [--png <png>]` | Renders the app icon. `bundle.sh` calls it. |

Logs go to `build/logs/<Name>-{build,test,sign,smoke}.log`.

### What `bundle.sh` produces

- **Release** (default): universal binary (arm64 + x86_64). Takes a few seconds per app.
  Xcode 27 prints a warning that x86_64 is deprecated; it's harmless, and the binary still
  targets macOS 14.
- **Debug** (`--debug`): host architecture only, faster. Used by `run.sh` and `smoke.sh`.
- `Info.plist` is generated from `app.json`. Menu bar apps (`menuBarOnly: true`) get
  `LSUIElement` so they have no Dock icon. Extra keys (usage descriptions like
  `NSAppleEventsUsageDescription`) go in an optional `"infoPlist": { ... }` object in
  `app.json`; this needs `jq`.
- SwiftPM resource bundles are copied to `Contents/Resources`, where `Bundle.module` finds
  them in both debug and release builds.
- Signed ad-hoc with the hardened runtime. Set `SLOPAPP_SIGN_IDENTITY` to a Developer ID
  identity to sign for real.

## Testing

- **Unit tests** cover the `<Name>Core` target. Anything with logic (parsing, timing,
  layout math, formatting) belongs there, behind protocols so tests can fake the system.
  Awake is the pattern: `PowerAssertion` and `Scheduler` protocols, a fake assertion and a
  manual clock in the tests.
- **Smoke test** proves the real `.app` launches and stays up, which catches bundle,
  Info.plist, signing, and startup crashes the unit tests can't see.
- **Manual check**: `scripts/run.sh <Name>` and use it. For system effects, verify with the
  system's own tools (Awake: `pmset -g assertions`).

## Releasing

1. Bump `version` (and `build`) in `apps/<Name>/app.json`.
2. `scripts/check.sh <Name>`
3. `git tag <slug>-v<version> && git push origin <slug>-v<version>`

`.github/workflows/release.yml` checks the tag matches `app.json`, tests, bundles, smoke
tests, optionally signs and notarizes, and attaches `<Name>.zip` to a GitHub Release. The
website links to `releases/download/<slug>-v<version>/<Name>.zip`. Signing secrets are
listed at the top of the workflow. Without them, releases are ad-hoc signed and users must
right-click > Open on first launch.

## Definition of done for a new app

An app moves from `alpha` to `beta` in `app.json` when all of these hold:

- [ ] Everything in the roadmap `spec` works, or the README says what's missing.
- [ ] Logic lives in `<Name>Core` with real tests (happy path, edge cases, failure paths).
      System access is behind protocols and faked in tests.
- [ ] `scripts/check.sh <Name>` passes: tests, universal release bundle, smoke test.
- [ ] Used for real via `scripts/run.sh <Name>`, including the system effect it promises.
- [ ] Menu bar apps use `MenuFooter`; window apps put About in the app menu.
- [ ] Any permission it needs (Accessibility, Screen Recording...) has a first-run screen
      explaining why, and the app behaves sensibly if it's denied.
- [ ] No network calls, analytics or telemetry. Data stays on the Mac.
- [ ] `Icon.svg` is a Lucide icon (never an SF Symbol) and the generated icon looks right
      (`build/<Name>-icon.png`).
- [ ] `README.md` explains what it does, how to develop it, and the code layout.
- [ ] `version` and `status` in `app.json` are current.

## Gotchas

- App names become Swift module names, so they must be UpperCamelCase letters and digits.
  Names that match SwiftUI types (e.g. `Gauge`) still build, but inside that module the
  bare name refers to the module first; qualify as `SwiftUI.Gauge` if you need the view.
- The scripts run under macOS's bash 3.2. Empty arrays under `set -u` need the
  `${arr[@]+"${arr[@]}"}` form.
- `smoke.sh` runs the binary directly, so window apps briefly show a window.
- Timers don't count time the Mac spends asleep. Re-check the clock on
  `NSWorkspace.didWakeNotification` (see `AwakeApp`).

## Releases and the feed

The Slopapp launcher (`apps/Slopapp`) installs and updates apps from one JSON file, the
**feed**. `scripts/feed.mjs` generates it; the release workflow publishes it.

```
apps/*/app.json + build/<Name>.zip ──feed.mjs──▶ build/feed.json, web/public/feed.json
                                                   │
                     release.yml (every tag) ──▶ gh-pages:/feed.json ──▶ brand.json feedUrl
```

### `brand.json` keys

| Key | What | Default |
|---|---|---|
| `feedUrl` | Where the launcher fetches the feed. Must be HTTPS. | `https://<owner>.github.io/<repo>/feed.json`, derived from `repoUrl` when missing |
| `teamId` | Optional Apple Developer team ID (10 characters). When set, the launcher only installs apps signed by that team with an Apple-issued certificate. When `null`, it accepts ad-hoc signatures and labels those copies "Unsigned development build". | `null` |

The launcher compiles both in (`apps/Slopapp/app.json` → `infoPlist.SlopappFeedURL` and
`infoPlist.SlopappTeamID`), so a compromised feed can't change where it looks or whom it
trusts. `feed.mjs` fails if those two values drift from `brand.json`; change both together.
When you get a Developer ID, set `teamId` in both places and sign every app with
`SLOPAPP_SIGN_IDENTITY` from the same team, or the launcher will refuse them.

### Feed format (schema 1)

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-11-03T04:34:38.815Z",
  "name": "Slopapp",
  "feedUrl": "https://hunterunger.github.io/slopapp/feed.json",
  "apps": [
    {
      "slug": "awake", "name": "Awake", "tagline": "Keep your Mac awake, from the menu bar.",
      "category": "Utilities", "replaces": ["Lungo", "Amphetamine"], "icon": "coffee",
      "menuBarOnly": true, "status": "alpha",
      "version": "0.1.0", "build": 1, "minimumMacOS": "14.0", "bundleId": "app.slopapp.awake",
      "downloadUrl": "https://github.com/hunterunger/slopapp/releases/download/awake-v0.1.0/Awake.zip",
      "iconUrl": "https://github.com/hunterunger/slopapp/releases/download/awake-v0.1.0/Awake-icon.png",
      "sha256": "39777bf0…", "size": 989552, "installedSize": 2474537,
      "releaseNotes": "…"
    },
    { "slug": "clips", "name": "Clips", "tagline": "…", "category": "Productivity",
      "replaces": ["Paste"], "icon": "clipboard-list", "menuBarOnly": true, "status": "planned" }
  ]
}
```

- **Built apps** (an `app.json` and a `<Name>.zip`) carry `version`, `build`, `bundleId`,
  `minimumMacOS` (all read from the zip's own `Info.plist`, the truth of what people
  download), `downloadUrl`, `iconUrl`, `sha256` and `size` of the zip, `installedSize`
  (unzipped bytes) and `releaseNotes`.
- **Planned apps** (roadmap only, or built without a zip) have `"status": "planned"` and no
  download fields: the launcher shows them as Coming Soon.
- `hub: true` marks the launcher itself; it doesn't list itself among the apps.
- URLs may be relative to the feed's own URL (test feeds use `"Awake.zip"`).
- Release notes come from the `## <version>` section of `apps/<Name>/CHANGELOG.md` when it
  exists, else from an optional `releaseNotes` string in `app.json`.
- Adding fields is fine; anything that changes the meaning of existing fields bumps
  `schemaVersion`, and older launchers refuse a newer schema instead of misreading it.

### Commands

```sh
node scripts/feed.mjs                  # build/*.zip -> build/feed.json + web/public/feed.json
node scripts/feed.mjs --strict         # also fail when a zip's version != its app.json
node scripts/feed.mjs --only Awake     # only these built apps (others left out)
node scripts/feed.mjs --local <dir>    # self-contained test feed: copies zips + icons into <dir>
node scripts/feed.mjs --stdout         # print it
```

### What a tagged release does

`release.yml` (tag `<slug>-v<version>`): test, bundle, smoke, optional sign + notarize,
create the GitHub Release with `<Name>.zip` and `<Name>-icon.png`, then download the newest
release zip of every other app, run `feed.mjs`, and commit `feed.json` to the `gh-pages`
branch. Releases are serialized (`concurrency: release`) so the feed never races. One-time
setup: Settings > Pages > Deploy from a branch > `gh-pages` / root.

### Testing the launcher against a local feed

Never test installs against real Applications folders. `apps/Slopapp/test-feed.sh` builds
a throwaway feed in `/tmp/slopapp-test` from `build/Awake.zip`, serves it on
`http://localhost:8765`, and launches the launcher with these overrides (honoured only
for testing; production is HTTPS-only):

| Variable | Effect |
|---|---|
| `SLOPAPP_FEED_URL` | Use this feed (https, `file://` or `http://localhost`). Also allows `file://` and loopback download URLs. |
| `SLOPAPP_INSTALL_DIR` | Install here. Nothing outside it is ever modified; copies elsewhere are shown read-only. |
| `SLOPAPP_TRASH_DIR` | "Move to Trash" moves here instead of the real Trash. |
| `SLOPAPP_LIBRARY_DIR` | The Library folder "Also remove its settings and data" cleans. |

See `apps/Slopapp/README.md` for the scenarios (`bump`, `bad-sha`, `bad-sig`, `corrupt`,
`offline`).

### Full-art app icons

An app can ship its own finished icon instead of the Lucide glyph `Icon.svg`, in one of two
forms (`bundle.sh` checks them in this order):

1. **`AppIcon.icon`**, an Icon Composer document (layered; Liquid Glass on macOS 26+, with
   the Dark, Clear and Tinted looks). `bundle.sh` compiles it with `actool` into
   `Assets.car` + a flat `AppIcon.icns` fallback for older systems, sets
   `CFBundleIconName`, and writes a preview to `build/<Name>-icon.png` with `ictool`. The
   launcher (`apps/Slopapp/AppIcon.icon`) uses this.
2. **`AppIcon.svg`**, a finished square SVG (such as `brand/logo.svg`), rendered with
   `icongen.swift --full-art` on Apple's icon grid with the standard shadow.

Every other app keeps the glyph-on-forest family look.
