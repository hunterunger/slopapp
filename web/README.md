# Slopapp website

The landing page: Next.js 16 (App Router), Tailwind v4, static export.

```sh
pnpm install
pnpm dev      # http://localhost:3000
pnpm build    # static site in out/
pnpm lint
```

## Where the content comes from

- **Brand** (name, tagline, colors): `../brand/brand.json`. The site uses its `candy` palette
  as Tailwind tokens in `src/app/globals.css` (`bg-strawberry`, `text-grape-ink`, ...), plus
  forest/cream for the app icon tiles. Keep the two in sync. The candy glass (header, hero,
  section accents) is for the frame only; the app collection stays quiet ice and white.
- **Apps**: `src/generated/catalog.json`, built by `node ../scripts/catalog.mjs` from
  `../catalog/roadmap.json` and every `../apps/*/app.json`. `pnpm dev` and `pnpm build`
  regenerate it first. It's checked in so the site still builds on its own.
- **Icons**: each app's `icon` is a [Lucide](https://lucide.dev) name. A new name needs
  one line in `src/components/AppIcon.tsx` (unknown names fall back to a grid icon).

Built apps (those with an `app.json`) get a Download button pointing at
`<repoUrl>/releases/latest/download/<Name>.zip`. Planned apps show "Coming soon".

## Deploy

`out/` is plain HTML/CSS/JS, so any static host works.

- **Vercel / Netlify / Cloudflare Pages**: root directory `web`, build `pnpm build`,
  output `out`.
- **GitHub Pages** (project site): build with `NEXT_BASE_PATH=/<repo-name> pnpm build`
  and publish `out/`. CI (`.github/workflows/web.yml`) already uploads `out/` as an
  artifact.
