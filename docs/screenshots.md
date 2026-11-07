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
  soft backdrop in the app's category colour from `Brand.Candy`, so the store feels like
  one family. Menu bar apps get a synthetic menu bar strip with their panel dropping from
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
- `scripts/catalog.mjs` adds each app's shots (paths, titles, captions) to the catalog
  feed. The website deploy publishes the images next to the feed.

## In the launcher

On the app page, right under the header: a large paging gallery (one 16:10 image at a
time, a peek of the next), title and caption under it, arrows and page dots, ←/→ keys,
click for a full-size viewer. It shows the light or dark set to match the system. Images
load lazily from the feed and are cached in `~/Library/Caches`; a quiet placeholder shows
while loading, and nothing at all when an app has no set.
