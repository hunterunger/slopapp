---
name: build-app
description: Build a Slopapp Mac app end to end with the project's 5-step dev cycle - pick from the roadmap, research the original Setapp app (features and flows), build it Mac-native per the design system, test it rigorously (unit, check, perf, scripted walkthrough, gap and design review), then run fresh blind-tester agents and iterate until a round has no accepted major issues. Use when asked to "build the next app", "build <slug>", "start on <app>", "do the next one in the roadmap", or to re-run research or blind testing for an existing app.
---

# Build a Slopapp app

The full playbook, with commands and exit rules, is [`docs/dev-cycle.md`](../../../docs/dev-cycle.md).
Read it first, plus [`docs/design-system.md`](../../../docs/design-system.md) and
[`AGENTS.md`](../../../AGENTS.md). This skill is the checklist for running it.

## 0. Setup

- Accessibility and Screen Recording must be granted to the terminal running you.
  Check: `scripts/drive apps` works and `scripts/drive shot --screen` writes a PNG.
- `scripts/drive help` once, so you know the tool.

## 1. Pick

- Asked for a slug: use it. Otherwise: the first `catalog/roadmap.json` entry without an
  `apps/<Name>/` directory.
- Note the original (`replaces[0]`) and whether it's installed:
  `ls "/Applications/Setapp/<Original>.app"`.

## 2. Research

Launch the `app-researcher` agent (if that agent type isn't loaded, use a general-purpose
agent and paste the body of `.claude/agents/app-researcher.md` above the task):

> Research <Original> for Slopapp's <Name> (slug `<slug>`). Roadmap entry: <paste JSON>.
> Write docs/research/<slug>.md from docs/research/TEMPLATE.md, following
> docs/dev-cycle.md step 2 and its privacy rules.

Review the doc yourself. Push back on a bloated must-have list. Take open questions that
change scope to the owner before building.

## 3. Build

- `scripts/new-app.sh <slug>`, then build the v1 must-haves per the design system's
  archetype for this app. Core logic + tests first, UI second.
- Keep using it as you go: `scripts/run.sh <Name>`.

## 4. Test

Do all of it, fix, repeat until clean:

- [ ] `scripts/check.sh <Name> --perf` green (tests, bundle, smoke, perf budgets)
- [ ] Scripted walkthrough of every v1 must-have with `scripts/drive` on the release build,
      screenshots reviewed (light and dark if relevant), the real system effect verified
- [ ] `scripts/drive tree <Name>` (and `--menubar`) shows no `[unlabeled]` controls
- [ ] Gap review: each item in the research doc's v1 scope is done or deferred with a reason
- [ ] Design review: each item in docs/design-system.md section 10 passes

## 5. Blind test rounds

For each round, launch a **new** `blind-tester` agent (never reuse one; it must not know
earlier rounds). If the type isn't loaded, use a general-purpose agent and paste the body
of `.claude/agents/blind-tester.md` above the brief. Give it this brief and nothing else:

```
Blind test of a Mac app.

App: <Name>
What it's for: <one-line pitch from app.json tagline>
The app: <absolute path>/build/<Name>.app (a release build; launch it with scripts/drive launch)
Repo root for scripts/drive: <absolute repo path>

Allowed:
- Permissions: <none | e.g. "you may grant Accessibility if asked" — usually none>
- Global shortcuts (`key --global`): <no | yes, the app is built around them>
- Mouse commands (`--allow-mouse`): <no | yes, for <what>>
- Test files: create whatever you need in /tmp/blindtest/
- System changes: none. Don't accept default-app or permission prompts.

Use it like a first-time user and report in the format from your instructions.
```

Don't add hints, feature lists, known issues or "please check X". If a capability truly
needs explaining (say, the app only reacts to links opened from other apps), describe
the *situation* a real user would be in ("you've made it your default browser; links you
click elsewhere come to it"), not the UI.

Then:

1. **Triage** every finding: accept / reject-with-reason / defer, using the rules in
   docs/dev-cycle.md step 5. Two independent rounds raising the same thing = accept.
2. **Log** the round in the research doc's "Blind test log".
3. **Fix** accepted findings, re-run step 4's gates.
4. **Next round** with a new tester.

Stop when a round has no accepted blocker/major findings and accepted minors are fixed or
deferred. After 5 rounds with majors still open, stop and escalate to the owner with the log.

## Ship

docs/dev-cycle.md "Ship": `app.json` status beta + version bump, app README, all-apps
`scripts/check.sh`, `node scripts/catalog.mjs`, and the pipeline's definition of done.
Commit only when the owner asks.

## Report back

Tell the owner, outcome first: what was built, how many blind test rounds and what they
caught, what was deferred and why, perf numbers, and anything that needs their call.
