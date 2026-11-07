# Slopapp website

The landing page: Next.js 16 (App Router), Tailwind v4, static export.

```sh
pnpm install
pnpm dev      # http://localhost:3000
pnpm build    # static site in out/
pnpm lint
```

## Where the content comes from

- **Brand** (name, tagline, colors): `../brand/brand.json`. The site uses the `nordic` palette
  (`../brand/BRAND.md`): birch paper, charcoal type, pine actions, Newsreader headlines and Inter
  body, defined as Tailwind tokens in `src/app/globals.css`. Botanical prints appear only inside a
  `PrintPanel` (`src/components/Print.tsx`): one crisp shape, the plate as a CSS mask, tinted 30%
  darker than the panel. Nothing else is textured.
- **Apps**: `src/generated/catalog.json`, built by `node ../scripts/catalog.mjs` from
  `../catalog/roadmap.json` and every `../apps/*/app.json`. `pnpm dev` and `pnpm build`
  regenerate it first. It's checked in so the site still builds on its own.
- **Icons and prints**: the herbarium app icons and plates (`../brand/ICONS.md`) are exported by
  `python3 ../scripts/icons/export_web.py` into `public/icons/`, `public/prints/` and
  `src/generated/herbarium.json` (plant names, plate numbers). It renders each app's committed
  `AppIcon.icon`, so the site shows the icon the app ships with; re-run it after changing an
  app's `Icon.py`. Apps without a herbarium icon yet show an empty specimen slot with
  their Lucide glyph; a new Lucide name needs one line in `src/components/AppIcon.tsx`.

Built apps (those with an `app.json`) get a Download button pointing at
`<repoUrl>/releases/latest/download/<Name>.zip`. Planned apps show "Coming soon".

## Deploy

`out/` is plain HTML/CSS/JS, so any static host works.

- **Vercel / Netlify / Cloudflare Pages**: root directory `web`, build `pnpm build`,
  output `out`.
- **GitHub Pages** (project site): build with `NEXT_BASE_PATH=/<repo-name> pnpm build`
  and publish `out/`. CI (`.github/workflows/web.yml`) already uploads `out/` as an
  artifact.
