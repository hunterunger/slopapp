# <Slopapp name> research (inspired by <Original>)

> Copy to `docs/research/<slug>.md`. Written by the research step of
> [`docs/dev-cycle.md`](../dev-cycle.md). Studied: <Original> <version> (installed copy at
> /Applications/Setapp/<Original>.app, read-only) + its website/help center, on <date>.
> We study how it works so we don't reinvent the wheel. We never copy its name, icons,
> artwork, wording, sounds or signature visuals.

## The job

One paragraph: what job a person hires this app for, when they reach for it, and what
"done" feels like. Then the one interaction that matters most (e.g. "press a shortcut,
drag a box, the text is on the clipboard").

## Who and when

- Typical moments of use (3–5 bullets, concrete).
- How often (many times a day? once a week?) and how long each use lasts.

## Feature inventory

Every feature, including small ones in menus and settings. Priority: **must** (v1 isn't
worth shipping without it), **should** (v1 if cheap, else v1.1), **later**, **skip** (say why).

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | | | must | |

## Key flows

Step by step, as a user experiences them. Note every click, shortcut, panel and default.

### Flow 1: <the main job>
1. …

### Flow 2: first run / onboarding
1. …

## Settings inventory

| Setting | Default | Options | Keep? |
|---|---|---|---|

## Menus and shortcuts

Main menu / status item menu structure and default shortcuts (global and in-app).

## Permissions and system integration

Accessibility, Screen Recording, Full Disk Access, default-app handlers, login items,
extensions, URL schemes, Services, Shortcuts/AppIntents. How it asks, and what happens if
you say no.

## UX patterns worth adopting

What it does well, in our words (e.g. "the picker opens under the cursor so the eye
doesn't travel"). These are ideas, not designs to replicate.

## What we won't copy, and what we'll do better

- Not copying: name, icon, artwork, wording, sounds, signature visuals, paid/upsell flows.
- Doing better: (rough edges, missing basics, slow paths, privacy issues, things reviews
  complain about).

## Edge cases

Multiple displays, full-screen spaces, dark/light, huge inputs, empty inputs, permissions
revoked mid-use, sleep/wake, app quit mid-task, non-English text, accessibility.

## Our v1 scope

The must-haves above, as a checklist the test step walks through.

- [ ] …

## Open questions

Anything that needs the owner's call.

## Sources

- <links to the official site, help center, changelog, reviews>

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.

### Round 1 (<date>)
| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
