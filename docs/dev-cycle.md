# The Slopapp dev cycle

Every app goes through the same five steps. Each step has a concrete output and an exit
rule; don't start the next step until the current one's exit rule holds.

```
1 Pick ─▶ 2 Research ─▶ 3 Build ─▶ 4 Test ─▶ 5 Blind test ─┬─▶ Ship
                           ▲                                │
                           └──────── fix accepted findings ◀┘
```

| Step | Who | Output | Exit rule |
|---|---|---|---|
| 1 Pick | lead | a slug | It's the next un-built app in `catalog/roadmap.json` (or the owner named one) |
| 2 Research | `app-researcher` agent | `docs/research/<slug>.md` | Feature inventory complete, v1 scope agreed |
| 3 Build | lead (or builder agent) | `apps/<Name>/` | Every v1 must-have works by hand |
| 4 Test | lead | green gates + gap review | `check.sh`, `perf.sh`, walkthrough and checklist all pass |
| 5 Blind test | fresh `blind-tester` agent per round | findings + triage log | A round with no accepted blocker/major issues |

The project skill `.claude/skills/build-app` runs this whole loop ("build the next app",
"build switchboard"). This file is the reference it follows.

Tools used throughout:

- `scripts/drive`: drives any running Mac app through Accessibility: read its UI tree,
  press buttons, pick menus, type, take window screenshots. `scripts/drive help` lists
  everything. Keys and clicks go to the target app's process, not to whatever the person at
  the Mac is using; mouse commands are opt-in (`--allow-mouse`) because they move the real
  cursor, and they refuse to act over any window that isn't the target app's.
- `scripts/perf.sh <Name>`: launch time, idle CPU and memory against the budgets.
- `scripts/check.sh <Name>`: unit tests, universal release bundle, smoke test, catalog.

## 1. Pick

Take the first entry in `catalog/roadmap.json` (it's in build order) that has no
`apps/<Name>/` yet, unless the owner named one. Priority 1 and 2 are the owner's favourite
Setapp apps, ranked by real use.

Output: the slug. Exit: nobody else is building it.

## 2. Research: how does the original flow?

Goal: understand the job the original does and every feature it has, so we build on years
of its UX lessons instead of guessing. Inspiration only: we never copy names, icons,
artwork, wording, sounds or signature visuals.

Run the `app-researcher` agent (`.claude/agents/app-researcher.md`) with the slug and the
original's name. It fills in `docs/research/<slug>.md` from
[`docs/research/TEMPLATE.md`](research/TEMPLATE.md) using:

1. **Official sources** (WebFetch/WebSearch): product page, help center, docs, changelog.
   Reviews and forum threads for what people love and what annoys them.
2. **The installed original, read-only**, via `scripts/drive`:
   ```sh
   scripts/drive launch "PDF Squeezer"          # originals live in /Applications/Setapp
   scripts/drive tree "PDF Squeezer" --menu      # full main menu with shortcuts
   scripts/drive menu "PDF Squeezer" "PDF Squeezer > Settings…"
   scripts/drive windows "PDF Squeezer"
   scripts/drive tree "PDF Squeezer" --window Settings
   scripts/drive shot "PDF Squeezer" --window Settings   # PNG in /tmp/slopdrive
   scripts/drive quit "PDF Squeezer"             # only if we launched it
   ```
   For menu bar originals: `scripts/drive menubar <App>` opens the status item menu and
   prints it; `close-menu` closes it.

**Privacy rules (hard):**

- Never screenshot, transcribe or describe the owner's personal content: clipboard
  history (Paste), screenshot history (CleanShot X), files, file names, emails, VPN
  accounts, scan results (CleanMyMac). Explore menus, settings and empty or demo states only.
  If a window shows personal content, describe its *layout* only ("a horizontal strip of
  cards with a type icon and timestamp"), never the content.
- Never change the original's settings, license, login or subscription state. Look, don't
  toggle. Close windows you opened; quit only apps you launched (check `scripts/drive apps`
  first: if it was already running, leave it running).
- Screenshots stay in `/tmp/slopdrive`. Never commit them, never put them in the repo.

**Exit rule:** the research doc has the job, a complete feature inventory with
must/should/later/skip, the key flows, the settings and permissions inventory, edge cases,
and a "v1 scope" checklist. If anything needs a product call (scope, risky features), ask
the owner before building.

## 3. Build

1. `scripts/new-app.sh <slug>` scaffolds `apps/<Name>/` from the roadmap entry. It builds and
   passes tests immediately.
2. Follow [`docs/design-system.md`](design-system.md): pick the archetype (menu bar
   utility, drop-in window, browser window, overlay), use the SlopKit pieces, use system
   controls and the user's accent color, keep copy plain.
3. Core logic in `Sources/<Name>Core` with tests from day one. System calls (pasteboard,
   IOKit, file system, NSWorkspace...) go behind protocols so tests can fake them.
4. Build the v1 must-haves from the research doc in order of the main flow first.
5. `scripts/run.sh <Name>` to use it yourself as you go.

**Exit rule:** every v1 must-have works when used by hand, including the real system
effect (the link really opens in the chosen browser; the file really shrinks).

## 4. Test: find the gaps before anyone else does

Run all of these. Fix what fails, then run them again.

1. **Unit tests** cover the core: happy paths, edge cases from the research doc, failure
   paths. `scripts/test.sh <Name>`.
2. **Gates:** `scripts/check.sh <Name>` (tests, release bundle, smoke) and
   `scripts/perf.sh <Name>` (launch < 300 ms, first window or menu bar icon < 600 ms, idle
   CPU < 0.2%, memory footprint < 50 MB for menu bar apps / < 120 MB for window apps).
   Shortcut: `scripts/check.sh <Name> --perf`.
3. **Scripted walkthrough:** drive the release build through every v1 must-have with
   `scripts/drive`, and look at the screenshots. For example:
   ```sh
   scripts/drive launch Awake
   scripts/drive menubar Awake                 # prints the menu with refs e1, e2...
   scripts/drive click Awake "1 Hour"
   scripts/drive menubar Awake | head -5       # status line should say "1 hr left"
   scripts/drive shot Awake                    # the open menu
   scripts/drive shot Awake --status-item      # the menu bar icon
   scripts/drive close-menu Awake
   pmset -g assertions | grep Awake            # the real system effect
   scripts/drive quit Awake
   ```
   Check light and dark mode, and the empty, busy and error states.
4. **Accessibility pass:** `scripts/drive tree <Name>` marks controls with no accessible
   name as `[unlabeled]`. Our apps must have none.
5. **Gap review:** go down the research doc's feature inventory and v1 checklist. Each
   must-have is built and walked through, or explicitly deferred with a reason in the doc.
6. **Design review:** grade the design system's review checklist
   ([`docs/design-system.md`](design-system.md), section 10) item by item.

**Exit rule:** all gates green, no unlabeled controls, every must-have walked through,
checklist passes.

## 5. Blind test

A fresh agent that has never seen the app, its code or its research uses it like a new
user would, and reports what it hits. We filter the feedback, fix, and repeat with a
**new** tester until a round finds nothing worth fixing.

### Brief: what the tester gets (and doesn't)

Gets only: the app's name, its one-line pitch, the path to the release `.app`, what it may
allow (permissions, test files it may create), and the `scripts/drive` tool.
Doesn't get: source code, the research doc, the feature list, earlier rounds' findings,
or what we think is wrong. The point is to see what an outsider discovers on their own.

Use the template in `.claude/skills/build-app/SKILL.md`. Launch the
`blind-tester` agent type (`.claude/agents/blind-tester.md`); if that type isn't loaded in
the session, use a general-purpose agent and paste that file's body above the brief.

### What comes back

- First impressions in the first minute.
- The tasks it tried and whether it managed (done / struggled / failed).
- Findings, each with severity (**blocker**: can't do the main job, crash, data loss;
  **major**: a common task is confusing, broken or slow; **minor**: works but rough;
  **nit**: polish), steps to reproduce, expected vs actual, screenshot paths.
- "What I expected that wasn't there."
- Would it keep using the app, and why.

### Triage: filter reasonably

For each finding decide:

- **Accept**: anything a typical Mac user would hit, any bug, crash, broken system effect,
  anything that contradicts the design system, unclear copy, missing standard Mac behavior
  (shortcuts, Esc, undo, menus).
- **Reject (with a reason)**: contradicts the design system or the research doc's
  deliberate choices; out of v1 scope; tester error caused by the automation tool (for
  example a drag that `scripts/drive` can't do); a personal taste call with no wider
  pull. A finding raised by two independent rounds is never "taste": accept it.
- **Defer**: valid but belongs in a later version. Add it to the research doc's inventory
  as `later`.

Log every round in the research doc's **Blind test log**: date, each finding, severity,
decision, and the fix or reason. Then fix the accepted ones, re-run step 4's gates, and run
a new round with a **new** tester (no memory of earlier rounds).

### Exit rule

Stop when a fresh tester's round has **no accepted blocker or major findings**, and every
accepted minor is fixed or explicitly deferred. Cap: 5 rounds. If round 5 still has
accepted majors, stop and escalate to the owner with the log.

## Ship

1. `app.json`: `status` from `alpha` to `beta`, bump `version`.
2. `README.md` for the app: what it does, permissions and why, keyboard shortcuts, what's
   deliberately not there yet.
3. `scripts/check.sh` (all apps) green; `node scripts/catalog.mjs` so the website shows it.
4. Commit with the research doc and the blind test log. CI must be green.
5. Release: tag `<slug>-v<version>` (see `docs/pipeline.md`).

Also run through the definition of done in [`docs/pipeline.md`](pipeline.md).

## Driving apps: what works and what doesn't

- **The screen must be unlocked and awake.** While the Mac is locked, macOS hides windows from
  Accessibility (every app reports itself as its only window). `scripts/drive` refuses UI commands
  in that state with a clear error; `launch`, `quit`, `stats` and `perf.sh` still work. If a
  blind test round hits this, pause the cycle and ask the owner to unlock; don't work around it.
- **Mouse commands stay inside the app.** `clickxy <app> x y` and `drag <app> x1 y1 x2 y2`
  (with `--allow-mouse`) take the target app first and refuse unless every point they click
  or pass over (start, end and samples along a drag) is on that app's own window, checked
  against the window server and Accessibility before and during the action. The error names
  the window in the way: `activate` the app, pick another point, or for a deliberate
  cross-app drop add `--allow-over <Owner>` (e.g. `Finder`). Status items need `--menubar`.
  `--check` runs only the check. Windows of system permission and security agents
  (UserNotificationCenter, CoreServicesUIAgent, SecurityAgent, universalAccessAuthWarn,
  System Settings, ...) are never acted on, whatever the flags: leave those for a human.

| Works well | Limits |
|---|---|
| Buttons, menus, status item menus, checkboxes, popups, text fields (`click`, `set`, `menu`, `menubar`) | Drag and drop between apps: `drag <app> ... --allow-mouse --allow-over Finder`, or send files with `open -a <App.app> <file>` |
| Typing and shortcuts posted to the app's process (`type`, `key`) | Global hotkeys only fire with `key --global`, which goes to the frontmost app; use only when that's the point |
| Screenshots of the app's windows, sheets and open menus (`shot`) | The menu bar icon is drawn by the system: use `shot --status-item` |
| Waiting for UI to change (`wait`) | Canvas-style UIs (annotation editors, rulers) expose little to Accessibility: use screenshots and `--allow-mouse` |
| Reading values, states and shortcuts from the tree | Non-native UIs (Electron, games) expose less |

Refs (`e12`) come from the latest `tree` of that app; run `tree` again after the UI
changes. Window numbers follow front-to-back order, so prefer `--window <title>`.
