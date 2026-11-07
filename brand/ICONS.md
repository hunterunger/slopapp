# Slopapp app icons: Nordic herbarium

Every Slopapp app icon follows this spec. It was chosen on 2026-11-07 after six rounds of exploration
(`brand/icon-lab/`). Each app's icon is a small spec file, `apps/<Name>/Icon.py`; the generator
`scripts/icons/herbarium.py` builds and checks it, so a new icon can only differ from the family in
what a spec file is allowed to say.

The launcher (`apps/Slopapp/AppIcon.icon`, strawberry → tangerine glass) is the one exception. It is
the brand mark, not an app.

## The idea in one paragraph

**The tile is the thing.** The square is not a background with a symbol on it: it *is* the object (a
clipboard, a camera front, a sheet of paper, a transit map, a saucer on a table), and its parts run
off the edges. It is drawn in flat, matte, muted Nordic colours on a strict grid. One surface of each
icon carries a **botanical print**, a plate from *Köhler's Medizinal-Pflanzen* (1887–1898, public
domain, via the Biodiversity Heritage Library) printed in one tone and clipped by a crisp vector
mask. Everything else is flat. Printed and plain areas meet on a clean edge.

## Anatomy

| Layer | What | Rules |
|---|---|---|
| Tile | The app's own Nordic colour, a 4% vertical shade | One `TILES` colour per app, never shared |
| Back (depth 2) | The "tile thing": sheet, body, strip, saucer, main line | Bleeds off at least one edge |
| Middle (depth 1) | Secondary parts: cards, lines, rims, the unlit route | |
| Front (depth 0) | The part that acts, usually in the accent | Usually one accent part per icon |
| Print | One botanical plate, on the largest uninterrupted surface | See "The print" |

Three depth groups at most. No glass, no specular, no translucency. Shadows are neutral at 0.18,
and 0.10 on the back group. This is the matte look; don't add gloss.

## Construction

The canvas is 1024 × 1024 and the macOS tile fills it. The tile's corner behaves like r = 256.

| Token | Value | Use |
|---|---|---|
| Grid | 32 (anchors), 64 (layout) | Every coordinate is a multiple of 32. The generator refuses anything else |
| W1 | 128 | Bodies, tracks, handles, tubes |
| W2 | 64 | Text lines, rims, rings |
| H | 32 | Cuts, slits, small corners |
| Gap | 64 | Between neighbouring parts |
| Padding | 96 or 128 | Inside a surface, to its contents |
| Corners | 256 − inset | Near the tile edge, concentric with the mask (inset 128 → r 128) |
| Free corners | pill (r = h/2), or r = 32 on polygons (16 on tiny ones) | |
| Bends | r = 256 | Every curve in a route; transit-map style (straight, 45°, straight) |
| Angles | 0°, 45°, 90° | Rotations too |
| Bleed | −64 / 1088 | Shapes that leave the tile |
| Clear zone | 32 | Unprinted margin around anything sitting on a print |

Check alignment with the construction overlay (`herbarium.py render` writes
`build/icons/<App>-construction.svg`). It shows the 64 grid, the centre axes, the 64 and 128 inset keylines,
and the 256/384 circles.

## Colour

Warm and matte: birch instead of white, charcoal instead of black, muted natural colours.

| Token | Light | Dark | Use |
|---|---|---|---|
| birch | `#F5F0E8` | `#3B3833` (surface), `#E8E1D5` (base) | Sheets and light objects |
| charcoal | `#2F2D2A` | `#171614` | Ink: lens glass, nibs, collars |
| night | `#24231F` | | What dark mode mixes toward |

Each spec names six colours:

| Role | Rule of thumb |
|---|---|
| `tile` | An unclaimed `TILES` colour: `herbarium.py tiles` lists who has which. When none are left, add a muted, natural colour to `TILES` |
| `main` | Usually the tile colour, or a strong colour for the hero part |
| `main2` | Lighter: about `mix(tile, birch, 0.5)` |
| `main3` | Deeper: about `mix(tile, charcoal, 0.3)` |
| `accent` | One of lingonberry `#B9473B`, ochre `#E0B054`, clay `#C4704F`, spruce `#4F7A72`. Pick one that contrasts with the tile |
| `muted` | A quiet tint for secondary parts, at least 1.35:1 against what it sits on |

Dark mode is derived and should not be hand-picked: the tile goes 66% toward night, birch surfaces
become warm dark, main3 stays deep (10%), main2 and muted sink. Override a role only for a reason,
for example Awake's coffee.

**Contrast:** every part that sits on something declares it (`on=`). The check requires at least
1.35:1 in both light and dark mode. This catches the "lines vanish on the clipboard" problem before
anyone sees it.

## The print

1. **One plate per app**, from *Köhler's Medizinal-Pflanzen* only, so every print shares one
   engraving style. The index of all 289 BHL-scanned plates is in
   `brand/plates/commons-koehler-meta.json`. Each must be marked public domain, and its source is
   logged in `brand/plates/sources.json` and `brand/plates/SOURCES.md` (generated). The spec names
   the plant (`Print(plant=(botanical, common))`) for the credits and the website.
2. **Pick a plant with a reason** when one exists: coffee for Awake, flax (linen paper) for Paper,
   hops (a climbing bine that routes) for Switchboard, fern fronds for the broom. Otherwise choose
   for the leaves: big, clear leaf shapes print best. Avoid plates that are mostly roots, dissection
   figures or thin stems.
3. **Crop** a square around the densest leaves. **Erase** family labels and stray figures.
4. **Placement:** print the icon's largest uninterrupted surface. That's the ground (tile) when it
   shows, or the object's big surface when the object covers the tile (Clips' sheet, Paper's sheet,
   Awake's saucer, Tidy's bristles). Never print thin parts.
5. **Tone:** on a coloured surface the print is that colour 30% toward charcoal (dark mode: 16%
   toward white). On birch, it's printed in the app's tile colour at 50%.
6. **Clear zones:** anything sitting on the print gets a 32-unit unprinted margin (`clear=[...]`).
7. Nothing else is textured. No grain, no patterns, no second plate.

## Drawing a new icon

1. **Find the object.** What would this app be if it were a physical thing you could put on a
   desk? The tile becomes that thing, seen straight on or from above. Prefer the object over a
   symbol (a clipboard, not a clipboard icon).
2. **Block it in on the grid.** Use the weights and gap above. Bleed the main surface off one or
   more edges. Keep it to 3–9 parts.
3. **Choose the part that acts** (the clip, the pen, the switch, the bulb) and give it the accent.
4. **Assign depth:** back = the tile thing, front = the actor.
5. **Pick a tile colour** nobody uses (`new` already did), then the other roles.
6. **Pick and fetch the plate**, set the crop, choose where it prints and which parts get clear
   zones.
7. `herbarium.py check`, then `herbarium.py render`, then review.

```sh
python3 scripts/icons/herbarium.py new <App>        # apps/<App>/Icon.py from the template (new-app.sh does this)
python3 scripts/icons/herbarium.py tiles            # which tile colours are taken
python3 scripts/icons/herbarium.py plates farn      # search the plate index (German/Latin names)
python3 scripts/icons/herbarium.py fetch <App> "File:Köhler's Medizinal-Pflanzen … (Plate 81) (….jpg"
python3 scripts/icons/herbarium.py check <App>
python3 scripts/icons/herbarium.py render <App>     # apps/<App>/AppIcon.icon, then build/icons/: 6 looks, 16/32 pt, construction
python3 scripts/icons/export_web.py <App>           # the website's icon and print (web/public/icons, prints)
```

## Review checklist

- [ ] `check` passes: grid, weights, roles, depth ≤ 3, unique tile colour, contrast, plate licence.
- [ ] The tile is the object; the main surface bleeds off an edge; no symbol floats in the middle.
- [ ] Recognisable at 32 pt; distinct from its neighbours at 16 pt (Finder list), light and dark.
- [ ] One part clearly acts, and it's the accent (or has a reason not to be, like Awake's coffee).
- [ ] Construction overlay: edges sit on keylines; corners near the edge are concentric; spacing is the gap.
- [ ] The print sits on one surface with crisp edges; clear zones around everything on it; labels erased.
- [ ] Dark, Clear and Tinted renditions hold up (nothing vanishes, nothing glows).
- [ ] It looks like it belongs next to the existing icons: put it in the review sheet with them.

## How it's built

| Path | What |
|---|---|
| `apps/<Name>/Icon.py` | The app's spec: drawing, colours, plate, crop. The only per-app input |
| `apps/<Name>/AppIcon.icon` | The generated Icon Composer document. Committed, so CI never needs the plate pipeline; Icon Composer can open it |
| `scripts/icons/herbarium.py` | The generator and style check (`build`, `check`, `render`, `new`, `tiles`, `plates`, `fetch`) |
| `scripts/icons/_template.py` | What `new` copies |
| `scripts/icons/export_web.py` | The website's icons (`web/public/icons/`), prints (`web/public/prints/`) and `web/src/generated/herbarium.json` |
| `brand/plates/prints/<Name>.png` | The processed one-colour print (committed), with a `.key` recording the crop/erase it was made with |
| `brand/plates/` | The Köhler index, `sources.json`, `SOURCES.md`. `raw/` holds the downloaded plates and isn't committed |
| `brand/icon-lab/` | The exploration history. Not the spec |

1. **Build:** `scripts/bundle.sh <Name>` runs `herbarium.py build <Name>` when `Icon.py` exists,
   which rewrites `AppIcon.icon` only if the spec changed (a no-op otherwise, ~0.1 s), then
   compiles it with `actool` and writes the preview `build/<Name>-icon.png` with `ictool`. If the
   spec fails the style check, the build goes on with the committed `AppIcon.icon` and the gate
   fails.
2. **Gate:** `scripts/check.sh` runs `herbarium.py check <Name>` for apps with an `Icon.py`; a
   non-conforming icon fails it the same way a lint error does. It also warns when the committed
   `AppIcon.icon` is out of date.
3. **Prints:** changing a spec's crop or erase makes its print stale. `build` re-processes it
   from `brand/plates/raw/<Name>.jpg` (re-download with `fetch` on a fresh clone); commit the new
   `prints/<Name>.png` and `.key` with the spec.
4. **Scaffold:** `scripts/new-app.sh` runs `herbarium.py new <Name>`: the template on the first
   unclaimed `TILES` colour. The app builds without an icon until the spec is drawn and its plate
   fetched.
5. **Website and launcher:** `export_web.py` renders each app's committed `AppIcon.icon` (Default
   and Dark), so the website shows the icon the app ships with. The launcher shows installed apps'
   own icons, and the release's `<Name>-icon.png` (the `bundle.sh` preview) for the rest.

The launcher (`apps/Slopapp/AppIcon.icon`) has no `Icon.py`: it's the brand mark, edited in Icon
Composer. Dictate's earlier hand-made microphone icon is kept at `brand/legacy/dictate-AppIcon.icon`.

Requirements: Xcode 26+ (`ictool`, `actool`) and Python 3 (the macOS one is fine). ImageMagick
only to re-process a print or export the website's WebP files.
