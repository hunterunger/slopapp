# Slopapp brand

**Slopapp** is a free, open-source collection of small, native Mac apps for everyday work.
Each app does one job well, follows the same design system, and keeps your data on your Mac.
The brand is calm and well made: Nordic colour, botanical prints, plain words.

Everything reads the name from [`brand.json`](brand.json).

## Voice

- **Calm, plain and precise.** Professional, never cute. Don't joke about the name. Let the
  work and the details speak.
- One line says what the app does. No hype words ("revolutionary", "supercharge",
  "unleash"), no exclamation marks.
- Lead with the promise: free, open source, no account, no tracking.
- Don't mention Setapp or MacPaw in public copy (website, app UI, store text, release notes).
  Never use their logos, app names, icons or screenshots. Say what an app replaces only in
  docs and `replaces` fields ("An open alternative to Paste").

**Tagline:** Native Mac apps, made with care.
**One-liner:** A growing collection of small, native Mac apps for everyday work. Free and open
source, with no subscription, no account and no tracking.
**Long:** Slopapp is a growing collection of small, native Mac apps for the things you do every
day: clipboard history, screenshots, opening links in the right browser, shrinking images.
Every app is free, open source (MIT) and written in Swift. No subscription, no account, no
tracking.

**Spelling:** "Slopapp" in prose (one word, capital S). `slopapp` in code, URLs, bundle IDs.
Never "SlopApp" or "Slop App".

## Logo

| File | Use |
|---|---|
| [`apps/Slopapp/AppIcon.icon`](../apps/Slopapp/AppIcon.icon) | The source: the launcher's Icon Composer document. Two stacked rounded diamonds (stacked layers, the collection) in white glass on a strawberry `#F0407A` → tangerine `#F28A0C` gradient, top to bottom. Render sizes and the Dark/Clear/Tinted looks with `ictool`. |
| [`logo.svg`](logo.svg) | Full-color tile for the web: favicon, site header, social. A flat SVG take on the icon: the same gradient, the top layer white, the lower layer white at 80%. |
| [`mark-mono.svg`](mark-mono.svg) | One-color mark (`currentColor`): just the glyph, both layers. The website uses it in charcoal (birch in dark mode) as its logo. |
| [`logo-legacy.svg`](logo-legacy.svg) | Retired. The old forest tile with slop poured over a grid. Keep for history; don't use. |

Keep the glyph as drawn: two layers, no third, no outline, no tilt. On the tile, the glyph spans
about three quarters of the width and sits centered.

## Color

Two palettes, each with its own job.

### Nordic (app icons and the website)

Matte, muted natural colour on warm birch, with botanical prints from *Köhler's
Medizinal-Pflanzen* (public domain, via the Biodiversity Heritage Library) clipped into crisp
panels. The full icon palette and rules are in [`ICONS.md`](ICONS.md); `brand.json` has the
website's subset under `nordic`.

| Token | Hex | Use |
|---|---|---|
| birch | `#F5F0E8` | Page background, light surfaces |
| oat | `#E4D9C6` | Quiet fills, empty specimen slots |
| charcoal | `#2F2D2A` | Text and the logo |
| night | `#24231F` | Dark mode base |
| pine | `#3F5E4E` | Primary buttons and links |
| sage, clay, ochre, fjord, heather, rosewood | | Print panels; each is also an app's tile colour |

- **Prints only inside panels.** A print fills one shape (a panel, a circle) in a tone 30%
  darker than the panel; everything placed on a print gets a clear margin. No textures
  elsewhere.
- **Text:** charcoal on birch (12.1:1), white on pine (7.2:1). Muted text is `#6B655C` (5.1:1).

### Candy (the launcher)

Translucent sugar-candy colour over frosted ice, after the coloured-plastic computers of the
late nineties, done the 2026 way: system glass, colour and a little gloss. No pinstripes, no
gel buttons, no textures. In `brand.json` under `candy`, and in SlopKit as `Brand.Candy`.

| Token | Hex | Use |
|---|---|---|
| strawberry | `#F0407A` | The primary: top of the icon gradient. Launcher selection, sidebar symbols, the hero banner. Hub category |
| tangerine | `#F28A0C` | Bottom of the icon gradient. Waiting-updates capsule and count. Productivity |
| lime | `#6CCB2F` | Developer |
| lagoon | `#0A9DBF` | Media |
| blueberry | `#2F6FE4` | Utilities |
| grape | `#8A4BD1` | Design |
| ice | `#F3F6F9` | Frosted white surfaces (website page background) |
| graphite | `#1C1F24` | Dark text on candy; dark surfaces |

- **Icon gradient:** strawberry → tangerine, top to bottom.
- **One primary, the rest for categories.** Strawberry (with the gradient) is the brand
  colour; the other flavours only tell categories apart. The mapping is the same on the
  website and in the launcher (above).
- **Text on candy:** graphite on tangerine (6.8:1), lime (8.2:1) and lagoon (5.3:1); white on
  blueberry (4.7:1) and grape (5.3:1). White on strawberry or tangerine needs the deepened
  gradient `#C8265C` → `#B9430A` (the website's primary button; the launcher computes the
  same darkening). Never put white text on the plain candy colours.
- **Dark mode** is deeper and jewel-like over graphite, not neon: the launcher's shell turns
  strawberry → grape, banners deepen until white text clears 5:1.
- **Where it's used:** the launcher's icon and frame (sidebar shell, selection, category dots,
  the featured banners, the updates capsule). Not on the website, not in the apps, and not in
  the launcher's content: cards, app pages and text keep system colours and the user's accent.

### Forest (retired)

The palette of the first app icons (Lucide glyphs on a forest-green tile). Retired: app icons are
Nordic herbarium now, see [`ICONS.md`](ICONS.md). Its tokens (forest, leaf, mint, cream, ember, ink)
stay in `brand.json` and SlopKit's `Brand` for older code; don't use them for anything new.

## Type

- Web headlines: **Newsreader** (an editorial serif; italic for botanical names). Web body
  and labels: **Inter**.
- Inside the apps: the system font only. The apps should look like macOS, not like the
  website. See [`docs/design-system.md`](../docs/design-system.md).

## App icons

See [`ICONS.md`](ICONS.md): the Nordic herbarium spec, how each app's `Icon.py` becomes its icon, and
how to draw a new one. App icons never use SF Symbols (Apple's license doesn't allow them in app
icons or on websites); they're fine inside app UI.
