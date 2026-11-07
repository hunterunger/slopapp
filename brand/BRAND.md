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
| [`apps/Slopapp/AppIcon.icon`](../apps/Slopapp/AppIcon.icon) | The source: the launcher's Icon Composer document. Built from `apps/Slopapp/Icon.py` in the herbarium finish ([`ICONS.md`](ICONS.md)): the owner's two stacked rounded diamonds (the collection), a birch sheet over an ochre one, on a moss tile with a linden print. Render sizes and the Dark/Clear/Tinted looks with `ictool`. |
| [`logo.svg`](logo.svg) | Full-color tile for the web: favicon, site header, social. A flat SVG take on the icon: the same gradient, the top layer white, the lower layer white at 80%. |
| [`mark-mono.svg`](mark-mono.svg) | One-color mark (`currentColor`): just the glyph, both layers. The website uses it in charcoal (birch in dark mode) as its logo. |

Keep the glyph as drawn: two layers, no third, no outline, no tilt. On the tile, the glyph spans
about three quarters of the width and sits centered.

## Color

One palette, Nordic, for everything: the app icons (the launcher's too), the website and the
launcher's frame.

### Nordic (app icons, the website and the launcher)

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
- **Categories** each have a colour (`nordic.categories` in `brand.json`, mirrored by SlopKit's
  `Brand.Nordic.category(_:)`): Utilities fjord, Productivity ochre, Media clay, Design heather,
  Developer sage, Hub pine. Categories added later get a stable pick from the six panel colours.
- **Dark mode is derived**, as in the icons: a tile or panel goes 66% toward night, its print
  lifts 16% toward white; pine (too deep on night) becomes sage lifted 30% toward birch.

#### In the launcher

The launcher's frame is Nordic (SlopKit `Brand.Nordic`; the launcher's `Views/Herbarium.swift`):

- **Shell:** the system sidebar material, washed with birch (night in dark mode), so the glass
  setting still applies. The content panel is paper: birch lifted toward white, or night
  deepened a little. Behind other windows the wash thins and every colour below goes grey.
- **Pine** marks the sidebar's symbols and selection, the Updates count, the "2 Updates"
  capsule (paper text, 7:1+) and "Up to Date".
- **Category dots** in the category's colour; "See All" in the same hue, deepened to 4.5:1.
- **Featured banners** are print panels: one of the six panel colours with its Köhler plate
  (the website's pairings: sage hops, ochre peppermint, fjord fern, rosewood coffee, heather
  oak, clay mallow), a paper card holding the text (the headline in the system serif), and the
  app's icon on the print in a clear zone. Matte: a soft neutral shadow, no gloss, no tilt.
- Content (cards, app pages, text) keeps semantic colours, and buttons, chips, focus rings and
  checkmarks keep the user's accent.

## Type

- Web headlines: **Newsreader** (an editorial serif; italic for botanical names). Web body
  and labels: **Inter**.
- Inside the apps: the system font only. The apps should look like macOS, not like the
  website. See [`docs/design-system.md`](../docs/design-system.md).

## App icons

See [`ICONS.md`](ICONS.md): the Nordic herbarium spec, how each app's `Icon.py` becomes its icon, and
how to draw a new one. App icons never use SF Symbols (Apple's license doesn't allow them in app
icons or on websites); they're fine inside app UI.
