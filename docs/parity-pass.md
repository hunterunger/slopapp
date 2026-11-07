# Parity pass (2026-11-03)

The owner's direction after trying the first apps: **each app should look and work much more
like the original it replaces, and shouldn't be missing features.** This supersedes the
"inspiration only, plain native chrome" stance where the two conflict.

## What changes

- **Match the original's layout, structure and flows closely.** Window shape, where things
  sit, panel placement (e.g. a strip along the bottom edge), sidebar sections, how a card or
  row is laid out, the order of steps, keyboard model, settings panes. Users switching from the
  original should feel at home immediately.
- **Feature parity is the goal.** Work through the original's full feature list. Build every
  feature that fits a single focused session, everyday features first. For anything left,
  record it in the app's research doc with a size estimate and why it's deferred.
- **The design system still applies** (native controls, SF Symbols in UI, system type, perf
  budgets, accessibility, privacy, no network) **except where matching the original requires
  otherwise** (e.g. colour-coded cards, a custom panel shape, a sound effect). Record each
  deviation and why in the research doc.

## What doesn't change: no copying of protected material

Layout, structure, flows and features aren't protectable. These are, and are never copied:

- Icons, logos, illustrations, screenshots, or any artwork from the original.
- Sound files. Use macOS system sounds (`NSSound(named:)`, e.g. "Pop", "Tink", "Morse") or a
  sound we synthesize ourselves.
- Marketing copy, help text, UI strings beyond short generic labels ("Copy", "Pin").
- Product names and signature trade dress: an original's distinctive colour palette, logo-like
  shapes or branded styling. Our version uses our own colours/materials while keeping the
  layout.

## How to study the original

- **Installed originals** (`/Applications/Setapp/…`, `/Applications/Setapp.app`): read-only, with
  `scripts/drive`. Menus, settings, empty states and layout only.
- **Never capture the owner's personal content**: clipboard history (Paste), screenshot history
  (CleanShot), account/profile/billing screens (Setapp), scan results (CleanMyMac), the owner's
  files, folders, servers or repos. For those views, use the official website, help center and
  App Store / product-page screenshots instead: download images to `/tmp/<slug>-parity/` with
  `curl` and look at them with Read. Never commit them.
- Don't change the originals' settings, licence or account state; don't run their destructive
  actions; quit only what you launched.

## Rules while working

- Follow `.claude/agents/app-builder.md` (owner-presence gate for mouse/global keys, no real
  clipboard writes, no full-screen screenshots, test data in `/tmp` only).
- Other agents work in parallel on other apps. **Don't edit `apps/SlopKit`**; build what you
  need inside your app and note it for later extraction. Only touch your app, its research doc,
  and (for the launcher) its own roadmap entry.
- `build/Switchboard.app` is the owner's live default browser: only the Switchboard agent may
  rebuild it, and it must leave it working, running, and set as default.
- All gates must pass at the end (`scripts/check.sh <Name> --perf`, scripted walkthrough with
  screenshots you look at, no `[unlabeled]` controls). Append a "Parity pass" section to the
  research doc: gap table (feature/design item → done / deferred + why), deviations from the
  design system, and screenshots paths.
- Don't bump versions or release; don't commit.
