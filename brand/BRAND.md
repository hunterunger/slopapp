# Slopapp brand

**Slopapp** is a free, open-source collection of Mac apps. The name is the joke: "slop" is
what people call careless, mass-produced software. Slopapp is the opposite: small native
apps, Apple-first, sweated over. The gap between the name and the craft is the brand.

Everything reads the name from [`brand.json`](brand.json).

## Voice

- **Deadpan about the name, serious about the work.** Joke about the name now and then; never
  joke about the apps' quality, privacy, or the user's data.
- Plain and warm. One line says what the app does. No hype words ("revolutionary",
  "supercharge", "unleash"), no exclamation marks.
- Lead with the promise: free, open source, no account, no tracking.
- Setapp only comes up in comparisons ("Like Setapp, minus the subscription"). Never use
  their logos, app names, icons or screenshots. Say what we replace only in docs and
  `replaces` fields ("An open alternative to Paste").

**Tagline:** The name is a joke. The apps aren't.
**One-liner:** Free, open-source Mac apps, built with an unreasonable amount of care.
**Long:** Slopapp is a growing set of small, native Mac apps for the things you do every
day: clipboard history, screenshots, opening links in the right browser, shrinking images.
Every app is free, open source, and written in Swift. No subscription, no account, no tracking.

**Spelling:** "Slopapp" in prose (one word, capital S). `slopapp` in code, URLs, bundle IDs.
Never "SlopApp" or "Slop App".

## Logo

| File | Use |
|---|---|
| [`apps/Slopapp/AppIcon.icon`](../apps/Slopapp/AppIcon.icon) | The source: the launcher's Icon Composer document. Two stacked rounded diamonds (stacked layers, the collection) in white glass on a strawberry `#F0407A` → tangerine `#F28A0C` gradient, top to bottom. Render sizes and the Dark/Clear/Tinted looks with `ictool`. |
| [`logo.svg`](logo.svg) | Full-color tile for the web: favicon, site header, social. A flat SVG take on the icon: the same gradient, the top layer white, the lower layer white at 80%. |
| [`mark-mono.svg`](mark-mono.svg) | One-color mark (`currentColor`): just the glyph, both layers. Footers, small UI, anywhere the gradient would be too loud. |
| [`logo-legacy.svg`](logo-legacy.svg) | Retired. The old forest tile with slop poured over a grid. Keep for history; don't use. |

Keep the glyph as drawn: two layers, no third, no outline, no tilt. On the tile, the glyph spans
about three quarters of the width and sits centered. The website hero uses a render of the real
icon (`web/src/assets/slopapp-icon.webp`, from the Default rendition); re-export it when the
icon changes.

## Color

Two palettes, each with its own job.

### Candy (the launcher and the website)

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
- **Where it's used:** the launcher's frame (sidebar shell, selection, category dots, the
  featured banners, the updates capsule) and the website. Not in the apps, and not in the
  launcher's content: cards, app pages and text keep system colours and the user's accent.

### Forest (app icon tiles, for now)

Every app's icon tile still uses the original palette; it's kept for that until the app
icons are redrawn.

| Token | Hex | Use |
|---|---|---|
| forest | `#0F3D2E` | App icon tiles |
| leaf | `#3DBE74` | Legacy accent (old website, old launcher icon) |
| mint | `#D4F2DF` | Legacy soft fills |
| cream | `#FAF6EC` | Glyphs on the icon tiles |
| ember | `#E5603D` | Legacy second accent |
| ink | `#13201A` | Legacy body text |

## Type

- Web headlines: **Bricolage Grotesque**. Web body: **Inter**.
- Inside the apps: the system font only. The apps should look like macOS, not like the
  website. See [`docs/design-system.md`](../docs/design-system.md).

## App icons

Every Slopapp app icon is a forest rounded-square tile with a cream
[Lucide](https://lucide.dev) glyph, generated by `scripts/icongen.swift` from the `icon`
field in each app's `app.json`. One family look, no design work per app.

Why Lucide and not SF Symbols: Apple's SF Symbols license doesn't allow symbols in app
icons or on websites. SF Symbols are fine *inside* app UI (menu bar items, buttons).
