# Store screenshots

How every app gets the screenshots shown on its page in the launcher and on the website.
Decided 2026-11-07.

## When

Only once an app reaches **v1**: `app.json` status `beta` or later, with its blind test
rounds done. Alpha apps show no gallery. After that, shots are retaken only on purpose
(`scripts/shots.sh <Name>`), when a release visibly changes the UI, never on every build
or in CI. Each set records the app version it was taken from.

## What a set looks like

Modelled on Setapp's app pages (a gallery of about five images right under the hero),
but cleaner:

- **3 to 5 shots per app**, 16:10, mastered at 2880 × 1800, light and dark versions of each.
  1. **Hero**: the app doing its main job, at its best, with realistic synthetic content.
  2. to 5. One key feature each (the things people choose the app for).
- **No text baked into the images.** Each shot has a title and a one-line caption in
  `showcase.json`; the launcher and website draw them as real text. That keeps them crisp,
  readable in both appearances, accessible (VoiceOver, alt text), translatable, and
  editable without retaking anything. (Setapp's images bake captions in; we don't.)
- **Composition**: the real app window (real glass, real controls, real window shadow) on a
  soft, matte backdrop in the app's own icon tile colour (Nordic, `apps/<Name>/Icon.py`) over
  birch, or night in dark mode, so each set matches its icon and the store feels like one
  family. Windows fill about three quarters of the frame width, as far as the height allows. Menu bar apps get a synthetic menu bar strip with their panel dropping from
  it. A shot may add one **zoom callout** (a magnified crop) to show a detail that's too
  small at gallery size.
- **Content is always synthetic**: fixtures through each app's test-data hooks. Never the
  owner's files, clipboard, screen, wallpaper or accounts. While capturing, a full-screen
  backdrop window of our own sits behind the app so translucent materials sample it, not
  the desktop.

## How it's made

- `apps/<Name>/showcase.json`: the shot list (id, title, caption, scene, window size,
  optional callout rect) and a `version` that's bumped when the set should be retaken.
- The app implements the scenes: launched with `SLOP_SHOWCASE=<scene>`, it loads fixtures,
  opens the right window/panel at the given size, and signals ready. SlopKit provides the
  shared part (`Showcase`: environment parsing, window sizing and placement, ready file).
- `scripts/shots.sh <Name>`: refuses below beta (unless `--force`), checks the owner-idle
  gate and an awake display, captures each scene's window with `screencapture -l`
  (window only) in light and dark, composes the final images, and writes
  `web/public/shots/<slug>/<id>-{light,dark}.webp` (plus `@1x` 1440 × 900) and a
  `manifest.json` (app version, date, showcase version). These are committed: small,
  hand-reviewed assets, not build output.
- `scripts/catalog.mjs` (website) and `scripts/feed.mjs` (launcher) add each app's shots
  (paths, titles, captions) through `scripts/shots-feed.mjs`. The website deploy publishes the
  images next to the feed.

## In the launcher

On the app page, right under the header: a large paging gallery (one 16:10 image at a
time, a peek of the next), title and caption under it, arrows and page dots, ←/→ keys,
click for a full-size viewer. It shows the light or dark set to match the system. Images
load lazily from the feed and are cached in `~/Library/Caches`; a quiet placeholder shows
while loading, and nothing at all when an app has no set.

## Running it

```sh
scripts/shots.sh Switchboard              # the whole set, light and dark
scripts/shots.sh Snapper --only hero      # retake one shot (the rest of the set stays)
scripts/shots.sh Snapper --compose-only   # re-compose the last captures (composer changes)
```

- **Adding a set to an app**: write `apps/<Name>/showcase.json` (`version`, `env` with the
  app's test-data variables, `{data}` = the scene's scratch folder; `shots` with `id`, `title`,
  `caption`, `scene`, optional `size` "1160x720", `zoom`, `menuBar`, `callout`), put any fixture
  files in `apps/<Name>/showcase/` (copied into `{data}`), or, for fixtures built from the repo
  (the launcher's local feed and older app copies), an executable `apps/<Name>/showcase-fixtures.sh
  <dir>` that the script runs once per run and copies into every `{data}`; handle `Showcase.scene` at launch:
  load synthetic data, open the window, call `Showcase.ready { [window] }` (SlopKit). The
  composer scales every shot's windows to about three quarters of the frame width, or as tall as
  the frame allows when that comes first, and never magnifies past 2× (the captures are 2×). A
  shot's `zoom` is a floor for small panels whose text needs it.
- **What the script does**: bundles the app, waits for 60 s without keyboard or mouse input,
  copies `build/<Name>.app` to `/tmp/<slug>-showcase` with the bundle id `<id>.showcase` (no URL
  schemes, no document types: it can never receive the owner's links or files, and has its own
  settings), shows our backdrop window (`tools/Shots backdrop`), launches each scene with
  `SLOP_SHOWCASE`, `SLOP_APPEARANCE` and the `env`, captures the windows the ready file lists
  with `screencapture -l<id> -o`, then composes with `tools/Shots compose` and encodes with
  `cwebp`. If anyone touches the Mac mid-run, it stops without writing anything.
- **Composition** (tools/Shots, `ShotsCore`): the app's icon tile colour (its `Icon.py`; the
  category's Nordic colour for apps without one) as a soft wash (light: over birch; dark: sunk
  toward night), no gloss and no print (prints only live inside panels), the windows centred with a rendered two-layer shadow
  (the same for every window, so the set matches), a frosted menu bar strip with the app's own
  status item (tinted for the strip) for menu bar apps, and an optional magnified callout.
- **Review** every image in `web/public/shots/<slug>/` light and dark before committing; raw
  captures and logs stay in `/tmp/<slug>-showcase`.
