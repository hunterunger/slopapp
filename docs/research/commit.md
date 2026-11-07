# Commit research (inspired by Gitfox)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied: Gitfox
> 5.4.2 (Setapp build; installed copy at /Applications/Setapp/Gitfox.app, read-only) + its
> website, support center, release notes, App Store and Setapp reviews, on 2026-11-07
> (revising a first pass made on 2026-11-03 against 5.4.1). We study how it works so we don't
> reinvent the wheel. We never copy its name, icons, artwork, wording, sounds or signature
> visuals.
>
> How it was explored:
> - **Docs first.** The feature inventory, flows and settings come mainly from the support
>   center (38 articles), the 5.x release notes and the main menu read through Accessibility.
> - **The installed app, read-only.** First pass (2026-11-03): Gitfox was launched with window
>   restoration suppressed, pointed only at a throwaway `/tmp` repo, the main menu and the
>   General settings pane were read, then the person at the Mac quit it. This pass: the owner
>   was at the Mac the whole session (HID idle never reached the 60 s gate), so the app was
>   **not** driven again; see "What couldn't be explored". The bundle itself was inspected
>   on disk (Info.plist, entitlements, bundled tools), which touches nothing.
> - **Never shown:** the Repository Manager and Open Recent list (the owner's repos), any of
>   the owner's repositories, git config values or accounts.
> - **Git behaviour and performance** were measured with `/usr/bin/git` (Apple Git 2.54,
>   Xcode; Apple M4 Max, macOS 27.2) on synthetic repos under `/tmp/commit-research/`
>   (demo author, `GIT_CONFIG_GLOBAL=/dev/null` so the owner's config played no part):
>   `demo` (branches, merge, tags, two stashes, a submodule, ahead/behind a local bare
>   remote, partly staged/renamed/untracked/CRLF files), `conflict` (merge conflict in
>   progress), `big` (100,000 commits, 8,096 merges, 7,020 branches, generated with
>   `git fast-import`), `wide` (50,000 files + a 3,000-file untracked `node_modules`),
>   `signtest` (SSH commit signing). Results are in "Engine decision" and "Performance budgets".

## The job

Commit is where a developer looks at what they changed, picks exactly which lines belong in
the next commit, writes a decent message, and syncs with the remote, without memorising
`git add -p` or reading raw diffs in a terminal. People reach for it many times a day,
between bursts of editing: "what did I just change?", "commit only the bug fix, not the
debug logging", "pull before I push", "park this work and switch branches". "Done" means the
commit says what it should, contains only what it should, the branch is pushed, and the tool
did nothing surprising to the repo.

The one interaction that matters most: **switch to the repo window → the changed files and
their diff are already there → click the lines or hunks you want (or press a key) to stage
them → type a subject → ⌘Return.** Everything else (history, branches, sync, stash) supports
that loop.

## Who and when

- After a coding session: review every change file by file before committing; catch stray
  debug prints and discard them.
- Splitting one messy working copy into two or three focused commits by staging hunks and
  single lines.
- Switching to a teammate's branch for review: fetch, check out the remote branch, stash or
  carry local work.
- Looking back: "when did this change and why?" in the history; copy a hash for a PR or issue.
- Start and end of day: pull to get up to date, push what's done.

Frequency: many times a day, from seconds (glance at status, push) to 10+ minutes (careful
staging and message writing). The window often stays open all day next to the editor, so
idle cost, refresh behaviour and memory with a big history loaded matter as much as speed.

## Engine decision: shell out to the user's git (confirmed, with three caveats)

The owner's prior: run the system `git` as a subprocess, parse machine-readable output,
because it respects the user's config, hooks, credential helpers and signing for free.
**Confirmed.** The evidence below supports it on every axis. Three things are *not* free and
must be built on purpose: the PATH that hooks and helpers need, a prompt path for
passwords/passphrases (askpass), and protection against a slow diff algorithm.

### Options compared

| | System `git` CLI (recommended) | Bundle our own git (Gitfox, GitHub Desktop) | libgit2 (SwiftGit2, SwiftGitX) | Pure Swift git |
|---|---|---|---|---|
| Same behaviour as Terminal | Yes, by definition | Mostly; a second git with its own version and system config | No: own implementation of status, merge, checkout, config parsing | No |
| Hooks | git runs them | git runs them | Not run. libgit2's hooks PR explicitly left out pre-commit, prepare-commit-msg, commit-msg and post-commit; GitUp (libgit2-based) re-implements only 4 hooks and documents env differences | Would have to re-implement |
| Credential helpers (`osxkeychain`, GCM, `gh auth git-credential`) | git runs them | git runs them | Not called by libgit2 itself; the app must implement the helper protocol (Lix reverted libgit2 fetching in 2024 because private repos broke) | Re-implement |
| SSH (`~/.ssh/config`, agent, 1Password `IdentityAgent`, `UseKeychain`) | OpenSSH does it | OpenSSH does it | libssh2: ignores much of `~/.ssh/config`, no 1Password agent config, different key formats | Re-implement |
| Signing (GPG, SSH, X.509) | git does it from config | git does it | No built-in signing: build the buffer, sign it yourself, `git_commit_create_with_signature` | Re-implement |
| Filters, LFS, fsmonitor, sparse index, SHA-256, reftable, `includeIf` | Whatever the user's git supports | Whatever we bundle | Lags or missing | Missing |
| License | Nothing linked | GPLv2 binary shipped alongside (fine, but we'd own updates and security fixes) | GPLv2 with linking exception: not on our MIT/BSD/Apache list (design system §9), would need an owner exception | n/a |
| Build | Nothing | Tens of MB per arch, notarisation of extra binaries | C build (cmake, libssh2, OpenSSL/mbedTLS) inside SwiftPM for a universal binary | Huge |
| Maintenance status | Apple ships updates with Xcode/CLT | Ours forever | SwiftGit2: no releases, Carthage/submodule install, Swift 5.3 badge. SwiftGitX: active, SPM, but pins a forked libgit2 1.9.x | No maintained, complete Swift implementation exists |
| Speed | Measured below: fast enough everywhere, with a commit-graph | Same | Faster for tiny repeated reads (no process spawn) | Could be fastest for reads (Sublime Merge reads repos with its own code and uses git only for writes) |

Who does what: Gitfox bundles git 2.55 plus an `askpass` and an `editor` helper, git-lfs,
git-flow and a CLI launcher, and links no git library. Its Mac App Store variant is sandboxed
and, per Gitfox's own docs, **lacks commit signing, custom hook execution and external diff
tools**: proof that the sandbox, not the engine, is what breaks those. GitHub Desktop runs a
bundled git CLI (dugite). Sublime Merge reads with its own code and writes with git. GitUp
uses libgit2 and lives with a hook subset.

**Decision: run the user's git as a subprocess for every operation. No libgit2, no bundled
git, not sandboxed.** Revisit a read-only fast path (Sublime Merge style) only if a measured
budget below fails, and only for reads.

### Measurements (Apple Git 2.54, M4 Max; times include process start)

| Operation | Repo | Time |
|---|---|---|
| Process spawn overhead | any | ~9 ms per `git` invocation (`/usr/bin/true`: 1.4 ms) |
| `status --porcelain=v2 -z --branch --no-optional-locks` | 50,000 files | ~100 ms (71 ms with `-uno`; 3,000 untracked files in one dir: 96 ms) |
| `log -z --format=… --topo-order main`, first byte | 100k commits | **14 ms** (commit-graph present) |
| same, all 99,996 rows streamed (16 MB) | 100k | ~500 ms |
| `log … --topo-order --all`, first byte / done | 100k, 7,020 refs | 140–170 ms / ~600 ms (ref loading dominates) |
| `log … -n 300 --all` without a commit-graph file | 100k | 158 ms first page; full `--all` first byte 390–410 ms |
| `rev-list --parents --topo-order --all` | 100k | 183 ms with commit-graph, 415 ms without |
| `log -n 300 -- <path>` (file history) | 100k | ~250 ms |
| `for-each-ref` with upstream + track | 7,020 refs | ~300 ms (ahead/behind for every branch is the expensive part) |
| `rev-list --count --left-right A...B` | 100k | ~320 ms without commit-graph |
| Lane layout of 100k rows (naive Python, single pass) | 100k | 98 ms, max 13 lanes, 6.5 active on average. Swift will be a fraction of that; layout isn't the bottleneck, drawing is |
| `diff` of a 200k-line file with 28,572 changed lines (8.6 MB patch) | — | Myers 68 ms, patience 81 ms, minimal 76 ms, **histogram 10.2 s** |
| `diff` of a 5,000-line insertion in the same file | — | 39 ms (any algorithm) |

Takeaways for the builder:
- Spawning is cheap enough for every user action, but never spawn per row or per file in a
  loop (9 ms × 2,000 files = 18 s). Batch: one `status`, one `diff` per selected file, one
  `for-each-ref`, and a long-lived `git cat-file --batch` for blob reads (binary sizes, Quick
  Look of old versions).
- Stream `git log` and parse as bytes arrive: rows appear in ~15 ms on the current branch.
  No paging protocol needed; one process per history view, cancelled when the view goes away.
- Ahead/behind for thousands of branches is slow: compute it for the current branch and
  visible sidebar rows only, and lazily.
- A user's `diff.algorithm=histogram` can take 10 s on a pathological file. Run diffs with a
  timeout (2 s) and fall back to `--diff-algorithm=myers` with an inline note.
- Without `.git/objects/info/commit-graph`, history is 2–3× slower to start. Most repos have
  one (`gc`, `fetch.writeCommitGraph`, `git maintenance`). We don't write it ourselves (that
  modifies the repo); a later Settings/Repository action could offer "Optimise repository"
  (`git maintenance run --task=commit-graph`).

### What was verified on this Mac (Finder-like env: `PATH=/usr/bin:/bin:/usr/sbin:/sbin`)

| Check | Result |
|---|---|
| `credential.helper` | `osxkeychain`, from Xcode's system gitconfig, so HTTPS pushes reuse Keychain logins from Terminal. **But** a credential that isn't stored yet makes git prompt on a terminal; with `GIT_TERMINAL_PROMPT=0` it fails fast instead of hanging. Asking the user needs `GIT_ASKPASS` (then git hands the answer to osxkeychain to store). |
| Hooks via `core.hooksPath` | Respected; hooks ran on commit. |
| SSH | launchd gives GUI apps `SSH_AUTH_SOCK`; `ssh` reads `~/.ssh/config` itself (1Password `IdentityAgent`, `UseKeychain`). OpenSSH supports `SSH_ASKPASS_REQUIRE=force`. |
| SSH commit signing | Works headless with a key in the agent or without a passphrase. A passphrase-protected key with no agent fails unless `SSH_ASKPASS` answers (verified: with a failing askpass the commit aborts with "incorrect passphrase"). The same askpass helper covers it. |
| GPG signing | `gpg` lives in `/opt/homebrew/bin` here, **not on the GUI PATH**, so `gpg.program=gpg` fails from a Finder-launched app unless we use the login-shell PATH. A terminal pinentry can't work from a GUI; `pinentry-mac` (configured in gpg-agent) can. We show git's error and the fix. |
| GUI PATH | `launchctl getenv PATH` is empty; apps get `/usr/bin:/bin:/usr/sbin:/sbin`. Homebrew, nvm and pnpm tools (git-lfs, gpg, husky/lint-staged's `node`) aren't on it. `$SHELL -l -c 'printenv PATH'` resolves the real PATH (~280 ms with fish). |
| Line staging | Build a patch with only the chosen lines, `git apply --cached --recount`; unstage with `-R`; discard from the worktree with `git apply -R`. Verified. |
| Discard with undo | `git stash push -u -m "<msg>" -- <paths>` removed only those paths; `git stash pop --index` restored them exactly. |
| Unborn repo | `status` reports `branch.oid (initial)`; `git log` fails: treat "no commits yet" as a state. |
| `#` lines | `commit -F -` keeps lines starting with `#` (cleanup `whitespace` when not editing). |
| Porcelain v2 in the demo repo | Rename (`2 R.` with origin path), partly staged (`1 MM`), untracked (`?`), conflict (`u UU` with stage OIDs), submodule (`S…`), `branch.ab +1 -1`. All parse cleanly with `-z`. |

### Implementation rules

1. **Finding git:** Settings override → `/usr/bin/git` **only if** `xcode-select -p` succeeds
   (otherwise `/usr/bin/git` is a shim that pops Apple's install dialog) → `/opt/homebrew/bin/git`,
   `/usr/local/bin/git` → else an empty state with **Install Command Line Tools…**
   (`xcode-select --install`, Apple shows its own dialog). Require git ≥ 2.35 (everything we
   use is older than that) and say so if it's older.
2. **Environment:** the app's env + the login-shell PATH prepended (resolved once per launch,
   off the main actor, 3 s timeout, output between markers so shell greetings don't leak in);
   `GIT_TERMINAL_PROMPT=0`; `GIT_EDITOR=true` and `--no-edit` wherever git would open an
   editor; `--no-optional-locks` on every read so we never take `index.lock` from under the
   user's terminal and never trigger our own file watcher; `-c core.quotepath=false`;
   `LC_ALL=C` only for commands whose stderr we pattern-match (push, pull, fetch, switch).
3. **Output:** machine formats only: `status --porcelain=v2 -z --branch`, `log -z
   --format=<fields separated by %x1f>`, `for-each-ref --format=…`, `diff --no-color
   --no-ext-diff --no-textconv`. Keep diff text as **bytes**; build staging patches from the raw
   bytes (non-UTF-8, CRLF and "\ No newline at end of file" must round-trip). Decode lossily
   for display only.
4. **Processes:** read stdout and stderr concurrently (a full pipe deadlocks). Mutations go
   through a per-repo serial queue; reads run in parallel and are cancellable (terminate the
   process when the view or selection changes). Network commands show `--progress` (parse the
   `\r` lines from stderr) and can be cancelled.
5. **Prompts:** set `GIT_ASKPASS`, `SSH_ASKPASS` and `SSH_ASKPASS_REQUIRE=force` to a tiny
   helper executable inside the bundle (`Contents/Helpers`). It covers HTTPS username/token,
   SSH key passphrases (fetch, push and SSH signing) and unknown host-key confirmation. Two
   ways to build it: the helper asks the running app over a socket whose path is passed in the
   environment and the app shows a sheet on the right repo window (better), or the helper
   shows its own small panel (simpler). Never store what was typed; git's credential helper
   does that.
6. **Behind a protocol:** a `GitRunner` protocol (args, env, stdin → stdout/stderr bytes,
   exit code, streaming variant) so Core tests can fake git, as Awake fakes `PowerAssertion`.
   Integration tests run the real git against temp repos built in the test.

## Feature inventory

Priority: **must** (v1 isn't worth shipping without it), **should** (v1 if cheap, else
v1.1), **later**, **skip** (with reason). The must list is deliberately the daily loop and
nothing else; see "Our v1 scope" for the cut line and why.

### Repositories and windows

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Open a local repo | File > Open Repository… (⌘O); folders are an `NSDocument` type, so Dock drops and `open -a` work | must | Accept a subfolder, open its top level (`rev-parse --show-toplevel`). Refuse bare repos and folders inside `.git` with a clear message. |
| 2 | One window per repo, tabs | Document window per repo; native window tabs | must | Same repo opened twice focuses the existing window. Restore open repos on relaunch. |
| 3 | Recent repositories | File > Open Recent + Repository Manager | must | Standard Open Recent + recents in the welcome window. |
| 4 | Repository Manager | Start window with folders of local and hosted repos, statuses, README rendering, auto-tracked folders, "Open in Tabs" | later | v1 welcome window: recents, Open…, (Clone…). |
| 5 | Create repo (init) | File > New Repository… | should | Offered when the chosen folder isn't a repo. |
| 6 | Clone | File > Clone Repository…: URL, name, destination, account, submodules | should | URL + destination + progress + cancel. No accounts. |
| 7 | Open in Finder / Terminal / editor | View menu, apps chosen in Settings | should | Finder + Terminal (default app). Editor choice later. |
| 8 | Command-line launcher | Bundled `gitfox-cli` | skip | `open -a Commit .` already works via the folder document type. |
| 9 | Quick Look | File > Quick Look (⌘Y) | should | Space on a file row. |
| 10 | Code stats | Bundles `scc` (a line counter), presumably for repo summaries | skip | Not part of the job. |

### Working copy, diff and staging

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 11 | Changed-files list | Outline with a checkbox per file (= staged), index/worktree status letters, +/− counts (5.4), folders tri-state; List/Tree/Group views; optional separate Staged/Unstaged sections | must | Two sections, **Staged** and **Changes**, flat list, name prominent and folder dimmed. A partly staged file is in both. Status as symbol + accessible label. Tree view later. |
| 12 | Live refresh | FSEvents-driven since 4.1.7; 5.4 refreshes once per burst and stopped redrawing every row. A review says it stopped noticing new commits | must | See "Performance budgets": FSEvents on worktree + `.git` refs/HEAD/index, coalesced, plus refresh on window activation, ⌘R to force. Only changed rows redraw. |
| 13 | Diff view | Unstaged/Staged switch, Fluid / Blocks (side by side) / Unified layouts, collapsible "N unchanged lines", line numbers, word-level highlight, keyword highlighting (5.2), wrap toggle | must | Unified, old/new line numbers, hunk headers, collapsed unchanged runs, system monospaced font. Word-level highlight: should. Syntax colouring: later. |
| 14 | Side-by-side diff | Blocks/Fluid layouts, synced scrolling (5.4) | should | Toggle; unified default. |
| 15 | Stage / unstage file | Checkbox, buttons, Stage Selected / Unstage Selected / Toggle Stage (⌥Space), Stage All | must | Checkbox per row, Space toggles, Stage All / Unstage All. |
| 16 | Stage / unstage hunk | Gutter button per change block; Diff > Stage ⌘→ / Unstage-or-Discard ⌘← | must | Button in each hunk header + keyboard. |
| 17 | Stage / unstage lines | Select lines (a drag in the gutter; a Setapp reviewer wants single-click), then a gutter button or context menu | must | **Click a changed line to select it**, shift-click/drag extends, ⌘-click toggles; the hunk button becomes "Stage 2 Lines". Keyboard line cursor. |
| 18 | Discard (file, hunk, lines, all) | Discard File, Discard Changes ⇧⌘⌫, Discard All ⌥⇧⌘⌫, Discard Hunk/Lines; Settings "Discard Behavior" default Stash | must | Always undoable, no setting: file/all discards go to a stash named "Discarded …"; hunk/line discards keep a reverse patch for ⌘Z. |
| 19 | Undo | Undo for edits made inside the diff (4.0) | must (scoped) | ⌘Z undoes our last stage/unstage/discard/stash drop. We don't edit file contents in the diff. |
| 20 | Context lines | More/Less Context ⌘+ / ⌘−, presets 3–100 and Unlimited | should | ⌘= / ⌘−, default 3. |
| 21 | Next / previous change | ⌘↓ / ⌘↑ | must | Also ↑/↓ moves between files in the list. |
| 22 | Whitespace, algorithm, wrap | Settings: whitespace modes, Patience (default) / Histogram / Myers; wrap | should | "Ignore whitespace" (view only; line staging disabled while on). Respect `diff.algorithm` with the 2 s Myers fallback. Wrap later. |
| 23 | Binary, image, huge files | Image diff modes | must (binary/huge), later (image diff) | Binary: "Binary file, 4.2 MB → 4.3 MB" + Quick Look. Diffs over ~10,000 lines collapse to "Show Full Diff". |
| 24 | Blame | Inline blame column | later | |
| 25 | Find in diff | ⌘F in the diff (4.0), matches scroll into view (5.4.2) | should | System find bar if the diff view supports `NSTextFinder`. |
| 26 | External diff/merge tools | Launchers for FileMerge, Kaleidoscope, Beyond Compare, VS Code… | later | |
| 27 | Open line in editor | Open diff lines in an external editor (5.2) | later | |

### Committing

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 28 | Commit composer | Commit window/sheet with staged count, target branch, message editor with 50/72 column markers; reviews on both stores object that it hides the diff | must | **Never modal.** Docked under the file list: subject with a live counter (hint past 50, warning past 72), body with a faint 72 guide. ⌘Return commits. The button says what it does ("Commit 3 Files"). |
| 29 | Amend | Amend HEAD; amend controls in the composer | must | "Amend last commit" toggle: loads the previous message, allows message-only amends, warns inline if HEAD is already on the upstream (`merge-base --is-ancestor HEAD @{u}`). |
| 30 | Draft, merge message, template | Restores unfinished and merge messages; recent messages | must (draft), should (others) | Draft saved per repo as you type. Prefill from `.git/MERGE_MSG` / `commit.template`: should. Recent messages menu: should. |
| 31 | Commit and Push | Commit button menu; ⌥ changes the button | should | ⌥⌘Return. |
| 32 | Hooks | Run by git; "Disable Commit Hooks" option | must (run), later (bypass) | Failure → output in a sheet with Copy Output; the message stays. Long hooks show progress and can be cancelled. |
| 33 | Identity | Settings > Git edits global name/email; app-level identities | must (missing case) | "Committing as Name <email>" under the composer. Missing → inline fields + "Save to Git Config". Multiple identities later. |
| 34 | Sign-off, reset author | Commit menu options | later | |
| 35 | Commit signing | Identities & Signing pane; commit menu Sign / Don't Sign / Git Default; manages `allowed_signers` | must (works via git config), later (UI) | No signing UI. Signing works because git does it; failures show git's message plus the likely fix (pinentry-mac, key not in agent). Show "Signed" in commit detail: later. |
| 36 | Message autocomplete | Paths, hashes, gitmoji, issues (5.0) | later | |
| 37 | AI commit messages | Generates via the Claude or Codex CLI (non-App Store builds) | skip | Third-party CLI and network; against "quiet, no network". Revisit only if the owner asks. |

### Branches, tags, remotes

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 38 | Branch list | Sidebar Local (HEAD badge, `feature/…` folders), Remotes, pinned, ahead/behind badges (5.4); a "Display Merged Branches" toggle the developer recommends for speed | must | Local branches with current marker and ahead/behind for the current branch (others lazily); Remotes collapsible; filter field. Slash folders: should. Must stay smooth with 7,000 branches (fixture). |
| 39 | Switch branch | Double-click / Quick Action; if local changes would be touched: Stash / Stash and Reapply / Checkout / Cancel | must | Return/double-click. If git refuses: **Stash and Switch** (default) / Cancel. |
| 40 | Check out remote branch | New Branch from… with Track | must | Double-click `origin/x` → `git switch --track` (or switch to existing `x`). |
| 41 | Create branch | Name, start point, track, check out | must | Sheet: name (validated with `check-ref-format`), from HEAD or the selected commit, "Switch to it" on. |
| 42 | Branch switcher | Toolbar breadcrumb "branch › upstream" | should | Toolbar branch button → filterable popover (⇧⌘B). |
| 43 | Rename / delete branch | Move Branch…, Delete… (force, delete on remote) | should | Delete confirms with the name, Cancel default, safe `-d` unless ticked; ⌘Z recreates it from the known tip. |
| 44 | Tags | Sidebar list, create | should (list + create), later (push/delete) | |
| 45 | Remotes management | Add/Edit Remote, accounts | later | |
| 46 | Merge / rebase into HEAD | With options (squash, no-ff, no commit, skip hooks) | later | Brings conflicts; with conflicts UI. |
| 47 | Interactive rebase | Reword/Edit/Squash/Fixup/Drop | later | |
| 48 | Conflict resolution UI | Per-hunk ours/theirs/both/neither (5.0), whole-file ours/theirs, Continue/Abort bar | later (UI), must (state) | v1: conflicted files flagged and not stageable by accident; "Mark Resolved" after fixing them in an editor; banner with Continue / Abort for merge, rebase, cherry-pick, revert. Pull can always produce this state, so v1 must not get stuck in it. |
| 49 | Cherry-pick, revert, reset | History context menu | should (revert), later (others) | Revert makes a new commit, so it's safe. Hard reset later, stash-first. |
| 50 | Git-flow, bisect, worktrees, submodule/LFS commands | Menus and toolbar | later | Submodules show as entries; LFS works when `git-lfs` is on the login PATH. |
| 51 | Hosting accounts, PR links, issue sources | GitHub/GitLab/Bitbucket/Gitea/Jira accounts, Create Pull Request, issue links | later | "Open Pull Request Page" when the remote prints a URL after push: should. No accounts ever in v1. |
| 52 | Compare branches | From the sidebar (5.3.1) | later | |

### Sync

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 53 | Fetch | Fetch, Fetch All Remotes; prunes | must | All remotes, `--prune`, progress, cancel. |
| 54 | Pull | Pull… dialog (rebase, autostash) and Pull HEAD | must | One click. Respect `pull.rebase`/`pull.ff`; on "divergent branches" ask Merge / Rebase / Cancel and offer to remember it in the repo's config. Dirty tree → `--autostash`, said aloud. |
| 55 | Push | Push… dialog and Push HEAD; drag a branch onto a remote (5.3.1); push several branches | must | One click. No upstream → `origin` (ask if several remotes) with `-u`. Rejected → "The remote has commits you don't have" + Pull. |
| 56 | Force push | With lease and plain, confirmed | later | With lease only. |
| 57 | Sync | Sync HEAD (fetch + pull + push) | should | One toolbar button. |
| 58 | Automatic fetch | Default every 10 min; 5.4 also fetches repos that aren't open | should (opt-in) | Off by default; Off / 5 / 15 / 30 min; open windows only; no notifications. |
| 59 | Credentials UI | Accounts & Credentials pane, stored passphrases | skip (accounts), **must (askpass)** | We rely on the user's helper and SSH setup; the askpass helper (Engine rule 5) handles prompts. |
| 60 | SSH host key confirmation | Asks before unknown hosts (5.1) | must (via askpass) | ssh asks through `SSH_ASKPASS`. |

### History

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 61 | Commit list | Avatar initials, author, ref chips ("+2 hidden labels"), time, short hash, subject; the working copy is the top row; compact modes | must | Streamed list: subject, author, relative date, short hash, ref labels. Top row "Uncommitted Changes (3)" jumps to Changes. |
| 62 | Graph | Coloured lanes with curves in the log gutter | must (simple) | Lanes from parent hashes, drawn per row. Scope: current branch + upstream by default; "All Branches" toggle: should. Straight segments and dots are enough. |
| 63 | Commit detail | Header (message, author, date, parents, refs) + files + diff | must | Same diff view, read-only. Copy hash (⌘C), copy subject. |
| 64 | Search history | Filter by message; full-text across history | should | Message/author/hash (`--grep`, `--author`, prefix). `-S` content search later. |
| 65 | Jump to ref | Jump to HEAD, branches, tags, stashes in the log (5.2) | should | ⌘0 / selecting a branch scrolls to its tip. |
| 66 | File history | From a file's context menu | later | `log --follow`. |
| 67 | Reflog | Sidebar section | later | Strong v1.1 safety net. |

### Stash

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 68 | Stash changes | Push Stash…: message, only staged, keep staged, untracked, ignored | must | Message (optional) + "Include untracked files" (on). |
| 69 | Stash list and contents | Sidebar with count; files + diff | must | |
| 70 | Apply / pop / drop | Apply with Restore Index / Pop; Drop | must | Drop is undoable (keep the SHA, `git stash store` on ⌘Z). |
| 71 | Partial stash, snapshots | Selected files; snapshot without touching the tree | later | Snapshot = `stash create` + `store`. |

### App-level

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 72 | Activity indicator | Toolbar "Tasks" area | must | Current operation, progress, Cancel; errors stay until dismissed. |
| 73 | Command palette | Quick Action ⌘P (fuzzy actions, branches, clone URLs) | later | Best v1.1 candidate once actions settle. |
| 74 | Custom shortcuts | Settings > Shortcuts for every command | skip | System Settings > Keyboard already remaps menu items. |
| 75 | Appearance override | System / Light / Dark | skip | Follow the system. |
| 76 | Release notes window | Opens after updates | skip | No "what's new" sheets. |
| 77 | Telemetry, crash reporting, licensing | Sentry, TelemetryDeck, StoreKit | skip | Design system §7. |
| 78 | `x-github-client` links | Opt-in handler | later | |
| 79 | Undo last commit | (not offered; Reset HEAD exists) | should | ⌘Z right after a commit = soft reset, message back in the composer, only while unpushed. Owner call (Open questions). |

## Key flows

### Flow 1: review, stage some lines, commit (the main job)

Gitfox (demo repo, first pass): the window opens on Local Changes: sidebar (Local Changes
with count, Graph, Stashes, Settings; then Local branches with a HEAD badge, Remote,
Submodules, Tags, Reflogs; filter at the bottom) → commit log column with an "N modified files"
row on top and a "branch › upstream" breadcrumb → file outline with checkboxes → diff in
side-by-side layout with "N unchanged lines" separators and an Unstaged/Staged switch. Ticking
a file stages it and flips the diff to the Staged side. Lines are selected by dragging in the
gutter. Commit opens a separate commit window; the button's menu holds Commit and Push,
sign-off, reset author, signing and hook options.

Ours:
1. The window opens on **Changes**: Staged and Changes sections in the content column, diff in
   the detail column, composer docked under the file list. First file selected.
2. ↑/↓ moves through files; the diff follows. Space toggles a file's staged state.
3. Tab moves focus into the diff; ⌘↓/⌘↑ jumps between hunks; each hunk header has **Stage
   Hunk** (or **Unstage Hunk** when looking at staged changes).
4. Click a + or − line to select it; shift-click/drag extends, ⌘-click toggles. Selected lines
   take the selection tint (greyed when the window isn't key); the hunk button reads "Stage 2
   Lines". Keyboard: ↑/↓ line cursor, Space selects, Return stages the selection (or the hunk).
   ⌘⌫ discards the selection (undoable).
5. ⌘L focuses the subject; Tab goes to the body. Counter "42/50"; past 72 it turns orange with
   a short reason.
6. ⌘Return. The composer clears, the commit tops History, a `HUD` says "Committed a1b2c3d".
7. A failing hook or missing identity keeps the message and explains inline what to do.

### Flow 2: first run

Gitfox: a Repository Manager window (repo folders, statuses, README) and, after updates, a
Release Notes window. Its getting-started doc then sends you to Settings to add hosting
accounts, set identity, identities and the git binary. Its own first launch couldn't be seen
(the installed copy isn't on its first launch).

Ours:
1. Launch → a small welcome window: **Open…** (⌘O), **Clone…** (should), recents (empty at
   first), and a drop target (SlopKit `DropZone`) for a folder.
2. Git is checked in the background. None found → the welcome window says Commit needs Apple's
   command line tools, with **Install Command Line Tools…**.
3. Not a repo → "This folder isn't a Git repository." **Create Repository** (should) /
   **Choose Another Folder…**.
4. The repo opens on Changes (History if the tree is clean). No tour, no accounts, no
   permission prompts of ours. Repos in Documents/Desktop/iCloud Drive may trigger macOS's own
   one-time folder prompt (git runs as our child): that's the system's, not ours.
5. Missing `user.name`/`user.email` is caught at the first commit, not up front.

### Flow 3: switch branches with local changes

Gitfox: double-click a branch; if checkout would touch local changes it asks Stash / Stash and
Reapply / Checkout / Cancel, and skips the question when it doesn't matter.

Ours: Return/double-click a branch (or the toolbar popover). `git switch <name>`. If git
refuses: "You have changes that would be overwritten by switching to <name>." **Stash and
Switch** (stash with untracked, switch, pop; if the pop conflicts, keep the stash and say so) /
**Cancel**. Remote branch → local tracking branch automatically.

### Flow 4: pull and push

Ours:
1. Toolbar **Fetch**, **Pull**, **Push** (and **Sync**, should) act on the current branch with no
   dialog. The branch shows ↑ahead ↓behind after every fetch.
2. First push sets the upstream. If the remote prints a pull-request URL, the HUD offers **Open
   Pull Request Page** (should).
3. Errors become one sentence + one action: rejected → Pull; auth → the askpass sheet, or if
   that fails "Git couldn't sign in to origin" + Copy Command; divergent pull → Merge / Rebase /
   Cancel; hook failure → output.
4. Any operation can be cancelled from the toolbar activity area.

### Flow 5: discard and undo

Ours: ⌘⌫ discards the selected file(s), hunk or lines. Lines/hunks: no confirmation. Files and
**Discard All…**: one confirmation (Cancel default) that says "You can undo this". Files go to
a stash "Discarded <paths> (<date>)"; lines/hunks keep a reverse patch. ⌘Z restores. The stash
also shows in Stashes for later recovery.

### Flow 6: stash

Ours: Stash (⌥⌘S): message + "Include untracked files" → stash. Stashes in the sidebar with a
count; select one for files and diff; **Apply**, **Pop**, **Drop** (⌘Z restores a drop).

### Flow 7: history

Ours: sidebar History (⌘2): streamed list with lanes for the current branch and its
upstream, ref labels; select → message, author, date, parents, hash (copy button) + files +
diff. ⌘F filters (should). Right-click: Copy Hash, Copy Subject, New Branch Here…, Revert Commit
(should).

### Flow 8: a pull leaves conflicts

Ours: banner "Merge in progress: 1 conflicted file" with **Abort Merge** and **Continue**
(disabled until nothing is conflicted). Conflicted files sit in their own section with a
warning symbol; their diff shows the conflict markers; Stage is replaced by **Mark Resolved**
(asks first if markers are still in the file); **Open in Editor**. Same banner for rebase,
cherry-pick, revert (detected from `MERGE_HEAD`, `rebase-merge/`, `rebase-apply/`,
`CHERRY_PICK_HEAD`, `REVERT_HEAD`). The `conflict` fixture repo exercises it.

## Settings inventory

Gitfox's General pane (seen in the first pass; installed values):

| Setting | Default | Options | Keep? |
|---|---|---|---|
| Appearance | System | System / Light / Dark | No: follow system. |
| Automatic Fetch | Every 10 minutes | Off and intervals | Yes, as "Fetch automatically": Off (default) / 5 / 15 / 30 min. |
| Discard Behavior | Stash by Default | Stash / permanent | No setting: discards are always undoable. |
| Show Release Notes on Update | On | toggle | No. |
| Default Terminal | System | app picker | Later. |
| Default Editor | None | app picker | Later. |
| Open GitHub Desktop links | Off | toggle | Later. |
| Max Subject Length | 50 | number | Fixed guide (50, warning at 72) in v1. |
| Max Body Length | 72 | number | Fixed guide in v1. |

Other Gitfox panes, from the docs (not opened): **Diff** (layout, algorithm, whitespace
modes, wrap, font with size stepper and reset), **Accounts & Credentials** (hosting accounts,
generic HTTPS credentials, stored SSH passphrases), **Identities & Signing** (identities, key
picker: Automatic / discovered OpenPGP / discovered SSH / manual), **Shortcuts** (rebind any
command), **Git** (global name/email, default branch, git binary, SSH allowed-signers file),
**Integration** (external diff/merge tools, CLI installer; not in the App Store variant).

Ours (`SlopSettings`, design system §3):

| Tab | Setting | Default |
|---|---|---|
| General | Launch at login (comes with `GeneralSettingsTab`) | Off |
| General | Fetch automatically | Off |
| General | Show untracked files | On |
| General | Diff layout | Unified (only if side-by-side ships) |
| Advanced | Git executable | Automatic (shows the resolved path and version) / Choose… |
| Advanced | Use my login shell's PATH for Git and hooks | On |
| About | `AboutSettingsTab` | — |

Git identity is edited where it's needed (the composer) and written to git config; we store
none of it.

## Menus and shortcuts

Gitfox's main menu (structure read through Accessibility in the first pass; several modifier
glyphs weren't readable, so some shortcuts are shown as their letter only):

- **App:** About, Release Notes, Settings… ⌘,, Services, Hide, Quit.
- **File:** New ⌘N, New Tab ⌘T, Open Repository… ⌘O, Open Recent, New Repository… ⌃⌘N, Clone
  Repository… ⌃⌘C, Track Folder…, Quick Look ⌘Y, Close ⌘W, Close All ⌥⌘W, Save… ⌘S.
- **View:** Back ⌘[, Forward ⌘]; Local Changes ⌘1, Graph ⌘2, Stashes ⌘3, Settings ⌘4, HEAD
  Branch ⌘0; Inspect Changes; List / Tree / Group; Separate Staged/Unstaged; Hide Commit Log
  for Local Changes; Compact Commit Log / Header; Untracked Files modes; Submodules &
  Worktrees opening; Show Repository/Selection in Finder ⇧⌘F / ⌥⇧⌘F, Terminal ⇧⌘T / ⌥⇧⌘T,
  Editor ⇧⌘E / ⌥⇧⌘E; Full Screen.
- **Find:** Find… ⌘F, Find Next ⌘G, Find Previous ⇧⌘G.
- **Repository:** Sync HEAD; Fetch, Fetch All Remotes; Pull…, Pull HEAD; Push…, Push HEAD,
  Force Push with Lease… ⌥⌘U, Force Push… ⌃⌥⌘U; Create New Branch, Create New Tag; Rebase HEAD,
  Merge Into HEAD; Interactive Rebase ▸ Reword/Edit/Squash/Fixup/Drop; Bisect…; Apply Patch…
  ⇧⌘A; Git LFS ▸ …; Add Remote…, Add Submodule…, Add Worktree…; Refresh ⌘R; Quick Action ⌘P;
  Open Diff or Mergetool; Link Manager…; Issue Sources….
- **Local Changes:** Commit, Amend HEAD; Stage Selected, Unstage Selected, Toggle Stage ⌥Space;
  Resolve Using Ours / Theirs; Push Stash…, Apply Stash…, Snapshot All Changes…; Discard
  Changes ⇧⌘⌫, Discard All Changes ⌥⇧⌘⌫.
- **Diff:** Previous / Next Change ⌘↑ / ⌘↓; Stage ⌘→, Unstage or Discard ⌘←; Show Unstaged ⌥⌘←,
  Show Staged ⌥⌘→; More / Less Context ⌘+ / ⌘−; Context Lines ▸ Unlimited, 3, 7, 15, 30, 50, 100.
- **Window:** standard + tabs; Repository Manager; Release Notes. **Help:** Help, Send Feedback.

Toolbar (left → right): Back, Tasks status, Quick Action, Sync, Fetch/Pull/Push group, Merge,
Rebase, New Branch, Git Flow, Stash, Refresh.

Ours (proposal; every action in a menu; standard shortcuts mean the standard thing; menu items
are plain text, no icons, per Golden Gate):

| Menu | Item | Shortcut |
|---|---|---|
| File | Open… / Open Recent / Clone… / Close | ⌘O / — / ⇧⌘O / ⌘W |
| File | Show in Finder / Open in Terminal | ⇧⌘R / ⌥⌘T |
| View | Changes / History / Stashes | ⌘1 / ⌘2 / ⌘3 |
| View | Unified / Side by Side; More / Less Context; Ignore Whitespace | ⌥⌘1 / ⌥⌘2; ⌘= / ⌘−; — |
| Changes | Commit / Commit and Push / Amend Last Commit (toggle) | ⌘Return / ⌥⌘Return / ⇧⌘A |
| Changes | Stage or Unstage Selection / Stage All / Unstage All | Space or Return / ⌥⌘A / ⌥⇧⌘A |
| Changes | Discard Selection… / Discard All… | ⌘⌫ / ⌥⇧⌘⌫ |
| Changes | Next / Previous Change | ⌘↓ / ⌘↑ |
| Changes | Focus Commit Message | ⌘L |
| Branch | New Branch… / Switch Branch… | ⇧⌘N / ⇧⌘B |
| Repository | Fetch / Pull / Push / Sync | ⌥⌘F / ⌥⌘P / ⌥⌘U / ⌥⌘Y |
| Repository | Stash Changes… / Refresh | ⌥⌘S / ⌘R |
| Edit | Undo (stage, discard, drop stash, commit) | ⌘Z |
| Find | Filter | ⌘F |

Builder: check for collisions with SwiftUI/AppKit defaults (⌥⌘F is "Find and Replace" in
text views; ⌘= / ⌘− may be claimed by text zoom; ⌘N becomes "New Window" with a
`WindowGroup`) and adjust.

## Permissions and system integration

Gitfox: not sandboxed in the Setapp/direct builds (empty entitlements); minimum macOS 15;
folders are an `NSDocument` type with handler rank **Default**; URL schemes `gitfox:` and
`x-github-client:` (opt-in); links Sentry, TelemetryDeck, StoreKit, WebKit (README rendering),
UserNotifications (background fetch). Its App Store build is sandboxed and so loses signing,
custom hooks and external tools; an App Store review complains it wanted access to the whole
home folder.

Ours:
- **Not sandboxed** (git, hooks, signing, helpers). No Accessibility, Screen Recording or Full
  Disk Access. `PermissionGate` isn't needed.
- Folders as a document type with `LSHandlerRank` **Alternate** (design system §2e): shows up
  in Open With and accepts Dock drops, never claims folders.
- macOS may show its own one-time prompt for repos in Documents, Desktop, Downloads, iCloud
  Drive or removable/network volumes. Don't pre-ask; if git fails with "Operation not
  permitted", explain and link Privacy & Security > Files and Folders.
- Bundles one helper executable (askpass). No URL scheme, notifications, Services or App
  Intents in v1.
- No network of our own: git talks to the user's remotes only on fetch/pull/push/clone or
  opted-in auto-fetch. The README says so.

## Archetype and SlopKit pieces

**Archetype: (c) library window**, one per repository, with document-style plumbing from
(e). The repo window is a `NavigationSplitView`:

- **Sidebar** (system sidebar, edge to edge, coloured symbols): Changes (count), History,
  Stashes (count); Branches (filter field, current marker, ↑↓ for the current one); Remotes
  (collapsed); Tags (should).
- **Content column**: Changes → Staged/Changes lists with the composer docked at the bottom;
  History → commit list with graph; Stashes → stash list.
- **Detail**: the diff (or commit/stash header + diff).
- **Toolbar** (system toolbar, no fake strips): branch popover, Fetch, Pull, Push, Stash, the
  activity area. Search (`.searchable`) filters the current column (⌘F).
- Empty states: `ContentUnavailableView` ("No changes", "No stashes") with one action.

Window plumbing (decide in build, both fine): AppKit `NSDocumentController` with a folder
document class gives Open Recent, tabs and restoration for free (this is what Gitfox does,
and Paper's pattern); SwiftUI `WindowGroup(for: URL.self)` gives restoration and tabs, but
Open Recent and "focus the existing window" are manual. Closing the last repo window must
**not** quit (like Paper's delegate), so `SlopAppDelegate`'s window-app rule doesn't fit as
is; the welcome window comes back on reopen.

Big lists (history with 100k rows, diffs with 200k lines, 7,000 branches): spike SwiftUI
`List` first; if it can't hold the budgets, use `NSTableView` via `NSViewRepresentable`. An
`NSTableView` of diff lines also gives line selection (click, shift, ⌘-click, arrows) and a
VoiceOver row per line for free, which maps exactly onto line staging.

SlopKit pieces that apply:

| Piece | Where |
|---|---|
| `SlopSettings`, `SettingsForm`, `GeneralSettingsTab`, `AboutSettingsTab` | Settings (General, Advanced, About) |
| `AboutView`, `AppInfo.current(fallbackName:)` | App menu About, About tab |
| `HUD` | "Committed a1b2c3d", "Pushed to origin", "Copied hash" |
| `DropZone` | Welcome window: drop a repo folder |
| `Hairline`, `.hairlineBorder`, `Spacing`, `Radius`, `windowConcentric` | Separators between composer and list, hunk headers, ref label shapes |
| `Color.selectionTint/selectionFill/windowAccent` (`WindowState.swift`) | Selected diff lines, graph highlight, sidebar marks that grey when the window isn't key |
| `.textGreen`, `.textRed`, `.textOrange`, `.readable(_:on:)` | +/− line numbers and glyphs, counters, subject-length warning, lane colours (graph lanes must stay 3:1 in both modes) |
| `AppPaths.applicationSupport` | Per-repo drafts, recent repos (if not using NSDocumentController) |
| Not used | `FloatingPanel`, `FileQueue`, `MenuFooter`, `ShortcutRow`/global shortcuts, `PermissionGate`, `Capture/`, `MainWindow` (single-window helper) |

Diff colours: background tints from system green/red at low opacity plus +/− glyphs and line
numbers in `.textGreen`/`.textRed`, never colour alone; check Increase Contrast and both modes.

## Performance budgets

The window-app budgets from design system §8 apply as they are (launch < 300 ms, first window
< 600 ms, idle CPU < 0.2 %, idle footprint < 120 MB, measured by `scripts/perf.sh Commit` on the
welcome window). Commit adds budgets of its own, measured on fixture repos.

### Fixtures

A script the builder adds (e.g. `apps/Commit/Tests/Fixtures/make-fixtures.sh`, output in
`/tmp/commit-fixtures`, never committed) that builds, deterministically and with a demo
identity and `GIT_CONFIG_GLOBAL=/dev/null`:

- `demo`: the daily-loop repo (branches, a merge, tags, 2 stashes, a submodule, ahead 1 /
  behind 1 against a local bare remote, partly staged + renamed + untracked + CRLF files).
- `conflict`: a merge stopped on a content conflict.
- `big`: 100,000 commits, ~8,000 merges, ~7,000 branches, via a `git fast-import` stream from
  a seeded generator (took 54 s here; cache it, run only with `--perf`). Plus a 200,000-line
  file and a scattered 28k-line edit of it.
- `wide`: 50,000 tracked files + a 3,000-file untracked folder.
- `unborn`, `detached`, `bare` (should be refused), `signed` (SSH-signed commits, local key).

The generator used for this research is described above; the builder writes its own.

### Budgets

| What | Budget | Fixture | Measured now (git alone) | How to test |
|---|---|---|---|---|
| Open repo → Changes list shown | < 300 ms | `wide` | status ~100 ms | Signpost from open to first list render; `scripts/drive wait` timing in the walkthrough |
| Open History → first 300 rows with graph | < 300 ms | `big` (current branch) | first byte 14 ms; 300 rows ~125 ms | Signposts; Core test parses a recorded 300-row stream under a threshold |
| Full 100k history streamed, UI responsive | < 1.5 s, no main-thread stall > 50 ms | `big` | 0.5–0.6 s | Instruments Time Profiler / hang detection once per release; Core test streams a synthetic 100k-row log through the parser and lane layout |
| Lane layout | < 50 ms per 100k rows, incremental | synthetic DAG in Swift (no git) | naive Python 98 ms | Swift Testing with `ContinuousClock`, generous threshold in CI (×3) |
| Scrolling history and diff | No dropped frames at 120 Hz in release | `big`, 200k-line diff | — | Manual Instruments (Animation Hitches) pass in the test step |
| Memory with 100k history loaded | < 250 MB footprint, back under 150 MB after leaving History | `big` | 16 MB of raw log | `scripts/drive stats Commit` after opening History; store hashes as bytes (20/32), intern author names, keep subjects only |
| Select file → diff shown | < 100 ms typical; < 500 ms for an 8.6 MB diff (virtualised rows) | `demo`, `big/huge.txt` | 40–70 ms | Signposts; walkthrough |
| Slow diff algorithm | Cancel at 2 s, retry with Myers, say so | `big/huge.txt` with `diff.algorithm=histogram` | histogram 10.2 s | Integration test with `-c diff.algorithm=histogram` asserts the fallback |
| Stage line/hunk → lists and diff updated | < 150 ms | `demo` | apply + status + diff ≈ 3 spawns | Integration test timing; walkthrough |
| Edit on disk → list updated | < 500 ms (250 ms debounce + status) | `demo` | — | Integration test: write a file, wait for the change with timeout |
| Event storm (3,000 files written at once) | ≤ 2 status runs per second, never more than one queued; idle again within 1 s of the storm ending | `wide` | — | Integration test counts `status` calls through a spying `GitRunner` |
| Idle with a repo open | CPU < 0.2 %, no git processes spawned | `wide` and `big` | — | Launch, open the fixture (`open -a build/Commit.app /tmp/commit-fixtures/wide`), `scripts/drive stats Commit` over 3 × 5 s; `ps` shows no `git` |
| Branch sidebar with 7,000 branches | First render < 200 ms; filter keystroke < 50 ms | `big` | `for-each-ref` ~300 ms | Signposts; ahead/behind only for visible rows |

### File watching (FSEvents)

- One `FSEventStream` per open repo on the worktree root with `kFSEventStreamCreateFlagFileEvents`
  off (directory-level is enough), latency ~0.25 s, plus the git dir when it lives elsewhere
  (worktrees, `--separate-git-dir`).
- Classify events: `.git/HEAD`, `.git/refs/**`, `.git/packed-refs`, `.git/reftable/**`,
  `.git/index`, `MERGE_HEAD`/`rebase-*` → refresh status + refs; `.git/objects/**`, `*.lock`,
  `.git/logs/**` → ignore; worktree paths → refresh status. Ignored paths (e.g. `node_modules`
  when ignored) still generate events: coalesce, don't filter per path with git (that's a spawn).
- Our own reads use `--no-optional-locks`, so they don't touch `.git/index` and can't trigger
  a refresh loop. Our own writes suppress the watcher until the write's follow-up refresh.
- At most one status in flight and one queued; a newer event replaces the queued one.
- Also refresh on window activation (cheap insurance against missed events, e.g. network
  volumes where FSEvents is unreliable) and on wake from sleep.
- Respect the user's `core.fsmonitor` / `core.untrackedCache` (git uses them itself); don't
  turn them on for the user.

## UX patterns worth adopting

- **The working copy is the first row of history**, so "what I'm doing" and "what I did" are
  one list.
- **Checkbox = staged**, right in the row; Space toggles it.
- **The diff follows the action**: after staging, show what will be committed.
- **Tracking at a glance**: "branch › upstream" and ↑↓ counts answer "am I in sync?".
- **Collapsed unchanged runs** with adjustable context keep long files readable.
- **Discards are recoverable by default** (stash, not delete).
- **One-click variants** of pull/push with options only where needed.
- **Ask once at the moment of conflict** (stash-and-switch) instead of a preference.
- **Commit is disabled until there's something staged and a message**, and the button says
  what it will do.
- **Push sets up tracking automatically.**
- **Activity lives in the toolbar**, never a blocking progress window.
- **Refresh once per burst of edits** and redraw only rows that changed (Gitfox's 5.4 fix).
- **Keyboard palette** (⌘P): v1.1.

## What we won't copy, and what we'll do better

- Not copying: the name, fox icon, colours and chip styles, bundled fonts, the four-column
  layout as is, wording, Repository Manager, release-notes window, accounts,
  subscription/trial flows, telemetry, AI messages.
- Doing better:
  - **The composer is never modal** (complaint on both stores).
  - **Line staging by single click**, not a gutter drag (Setapp review).
  - **Fast with many branches and commits**: streamed log, lazy ahead/behind, virtualised
    rows (reviews mention freezes; the developer's workaround was hiding merged branches).
    Budgets above, tested on a 100k-commit, 7,000-branch fixture.
  - **Never stale**: FSEvents + activation refresh (a review says it stopped noticing commits).
  - **No 10-second diffs**: timeout and Myers fallback.
  - **Safer destructive actions**: names in confirmations, Cancel default, undo for discard,
    branch delete, stash drop and (if approved) the last commit. A reviewer found the push
    button too easy to misclick and nearly deleted a branch.
  - **Behaves exactly like Terminal git**: the user's git, config, hooks, credential helper,
    SSH agent, signing and PATH.
  - **Plain-language errors** for the failures everyone hits: no upstream, rejected push,
    divergent pull, auth, missing identity, hook failure, `index.lock`, conflicts, detached
    HEAD, missing command line tools, signing (pinentry, key not in agent).
  - **The search field doesn't look like the commit box** (Setapp review): search lives in the
    toolbar, the composer is clearly labelled.
  - **VoiceOver**: Gitfox's file checkboxes and some buttons are unlabeled; ours name every
    control ("Stage notes.txt"), and diff lines read as "Added line 12: …".
  - **Native look, no telemetry, no accounts, no subscription.**

## Edge cases

Repository states
- Unborn HEAD: status works; History empty state; staged diff against the empty tree; first
  commit works.
- Detached HEAD: banner with **New Branch Here…**; commits still work.
- Merge / rebase / cherry-pick / revert in progress: banner with Continue / Abort (Flow 8).
- Worktrees (`.git` is a file), submodules (an entry, no recursion), sparse checkouts,
  shallow clones (graph with missing parents), SHA-256 (64-char hashes), reftable refs.
- Bare repo or a folder inside `.git`: refused with a message.
- Repo moved, renamed or deleted while open: "This repository is no longer at <path>" with
  Locate… / Close.
- `index.lock` held by another process: retry with backoff, then "Another Git process is using
  this repository." Never delete the lock.
- Huge working copies: 50k files, an unignored `node_modules` (collapsed with
  `--untracked-files=normal`), thousands of changed files (virtualised list).

Diffs and staging
- Binary, image, very large files; huge diffs (collapse + Show Full Diff); pathological
  algorithm cost (fallback).
- Renames/copies, mode-only changes, symlinks, deletions, names with spaces/newlines/Unicode
  (always `-z`).
- No trailing newline, CRLF and `core.autocrlf`, non-UTF-8: patches from raw bytes.
- File changed on disk between showing and staging: the patch fails → refresh and "The file
  changed. Try again."
- Ignore-whitespace view: line/hunk staging disabled with an explanation.
- LFS pointer files; `git-lfs` missing when the repo requires it: show git's error + how to
  install.

Committing and syncing
- Missing identity, empty message, nothing staged (amend allows message-only), `#` lines kept,
  very long subject, non-ASCII messages.
- Hooks that fail, hang (cancel), or need shell-PATH tools.
- Signing: GPG with a terminal pinentry, SSH key not in the agent, passphrase key (askpass).
- Amending a pushed commit: warning before, not after.
- No remote; several remotes; upstream gone (`[gone]`); push rejected; protected branch;
  offline; slow network (cancel); sleep mid-fetch (error, retry safe).
- HTTPS without a stored credential, 2FA token, SSH passphrase, unknown host key: never hang.
- Command line tools missing; git override pointing at nothing; git older than 2.35.

App
- Several repos in tabs/windows; same repo opened twice focuses the existing window.
- Relaunch restores open repos and views; drafts survive quit and crash.
- Light/dark, Increase Contrast, Reduce Motion, VoiceOver, full keyboard access, inactive
  window greys selection.
- Long branch names, 7,000 branches, many stashes, 13+ graph lanes (cap the gutter width and
  fade extra lanes rather than growing forever).
- Idle: no polling, no git processes while nothing changes.

## Our v1 scope

**Cut line.** v1 is the daily loop and nothing else: status, staging files/hunks/lines,
discard, commit (with amend), history with a simple graph, branches (list, switch, create),
diff, fetch/pull/push of the current branch, stash. Plus the two things the loop can't live
without: credential prompts (askpass) and not getting stuck when a pull stops on a conflict.
Pushed to later, as the owner suggested: interactive rebase, a conflicts UI, blame,
submodule commands, LFS commands, worktrees, GitHub/GitLab integration. Also pushed back
(each is a feature someone will ask for, none is the loop): merge/rebase commands, tags
beyond a list, remote management, command palette, image diff, syntax colouring, multiple
identities, signing UI, Repository Manager, AI messages, custom shortcuts. Side-by-side
diff, clone and auto-fetch are "should": in only if the musts are solid.

Must-haves (the test step walks this list):

- [ ] **Engine:** finds the user's git (override → `/usr/bin/git` only with CLT → Homebrew
      paths), login-shell PATH, git ≥ 2.35 check, never hangs on a prompt, reads never take
      `index.lock`, every process cancellable. Missing tools → install button.
- [ ] **Askpass helper:** HTTPS username/token, SSH passphrase (fetch/push and signing),
      unknown host key, in a native sheet; nothing stored by us.
- [ ] **Open a repo:** ⌘O, folder drop, Open Recent, `open -a`; subfolder → top level;
      non-repo and bare repo explained; one window per repo; restored on relaunch.
- [ ] **Changes:** Staged and Changes sections with status, live refresh (FSEvents +
      activation + ⌘R), keyboard navigation, Space toggles, Stage All / Unstage All.
- [ ] **Diff:** unified with line numbers, hunk headers, collapsed unchanged runs, next/previous
      change, binary and huge-file handling, 2 s Myers fallback, light and dark.
- [ ] **Hunk and line staging/unstaging:** buttons, click/shift/⌘-click selection, keyboard;
      correct on CRLF, no-trailing-newline and non-UTF-8 files.
- [ ] **Discard with undo:** file, hunk, lines, all; ⌘Z restores; file discards also in Stashes.
- [ ] **Commit composer:** docked, subject counter 50/72, body guide, draft per repo, ⌘Return,
      amend (message-only, pushed warning), hook output on failure, missing identity inline,
      signing works when configured (errors explained).
- [ ] **History:** streamed list with lane graph (current branch + upstream), ref labels,
      "Uncommitted Changes" row, commit detail with files and diff, copy hash.
- [ ] **Branches:** list with current marker, ↑↓ for the current branch, filter; switch with
      Stash and Switch; check out a remote branch as tracking; create from HEAD or a commit.
- [ ] **Fetch / Pull / Push:** current branch, progress, cancel; first push sets upstream;
      divergent pull asks Merge/Rebase; rejected push and auth errors explained; works with
      osxkeychain HTTPS, an SSH agent and a passphrase key.
- [ ] **Stash:** stash (message, untracked), list with count, contents, apply / pop / drop
      (drop undoable).
- [ ] **Repo-state banners:** detached HEAD; merge/rebase/cherry-pick/revert in progress with
      Continue/Abort; conflicted files flagged, Mark Resolved, Open in Editor.
- [ ] **Performance budgets** above, on the `demo`, `wide` and `big` fixtures.
- [ ] **Standard pieces:** Settings (General, Advanced, About), every action in a menu with a
      shortcut, no unlabeled controls, VoiceOver reads diff lines, design checklist §10.

## Open questions

These change scope; the first three most of all.

1. **Engine:** confirm "the user's git, no libgit2, no bundled git, not sandboxed" (no Mac App
   Store build). Recommended.
2. **Askpass in v1 (listed as must).** Without it, a first HTTPS push or a passphrase SSH key
   fails with "run this in Terminal once". It's one extra helper binary plus a sheet. OK to
   keep it in v1?
3. **Graph in v1 (listed as must, simple lanes).** Alternative: flat history in v1, graph in
   v1.1, to put all build time into staging and diff quality.
4. **Side-by-side diff:** v1 (some people won't use a client without it) or v1.1?
5. **Auto-fetch default:** off (our network rule) or every 15 min (what git GUI users expect;
   Gitfox does 10). It only talks to the user's own remotes.
6. **Login-shell PATH on by default?** It makes hooks, git-lfs and gpg behave like Terminal,
   but runs the user's shell startup files once per launch (~280 ms, off the main thread).
7. **"Undo Commit"** (soft reset of the last unpushed commit): handy and small, but it
   rewrites history.
8. **Clone and init in v1?** Cheap, expected by new users; listed as should.
9. **Minimum macOS:** the repo standard is 14+; Gitfox needs 15. Anything in the plan (e.g.
   SwiftUI table performance) that would argue for 15? Default: stay on 14.

### Decisions (build step, 2026-11-07)

Owner calls: **(1) engine** confirmed: the user's git, no libgit2, no bundled git, not
sandboxed, no Mac App Store build. **(3) graph**: a simple coloured-lane graph in v1.
**(4) diff**: unified only in v1; side-by-side stays later. The rest were left to the
research doc's recommendations; what was decided and why:

2. **Askpass in v1: yes.** Without it a first HTTPS push or a passphrase key dead-ends in
   "run this in Terminal". Built without a second binary: `GIT_ASKPASS`/`SSH_ASKPASS` point at
   Commit's own executable, which (when git sets the socket variable and passes a prompt)
   runs as a helper, asks the app over a per-launch Unix socket with a token, and the app
   shows a sheet on that repository's window. `bundle.sh` only copies the main executable,
   so a separate `Contents/Helpers` tool would have needed a pipeline change.
5. **Auto-fetch: off by default** (Off / 5 / 15 / 30 min in Settings). The suite's rule is
   no network unless asked; it only ever talks to the user's own remotes when on.
6. **Login-shell PATH: on by default**, resolved once per launch off the main thread with
   markers and a 3 s timeout (`$SHELL -l -i -c 'printenv PATH'`, interactive too because most
   people set PATH in `.zshrc`). Hooks, git-lfs and gpg then behave as in Terminal. Toggle in
   Advanced.
7. **Undo Commit: yes, as ⌘Z** right after a commit or amend, only while that commit is still
   the branch tip and not on its upstream (soft reset; the message goes back into the
   composer). It rewrites only unpushed local history, which is the case where people want it.
8. **Init: yes, clone: later.** "Create Repository" is one button when a chosen folder isn't
   a repository. Clone (URL, destination, progress, cancel) is deferred: the musts came
   first and clone adds a sheet, network progress and a second open path.
9. **Minimum macOS: 14**, as the repo standard. Nothing needed 15: the big lists are
   `NSTableView` (diff, history), so SwiftUI table performance on 14 doesn't matter.

Builder decisions:

- **Windows**: SwiftUI `WindowGroup(for: URL.self)` (restoration, native tabs, and "same
  value focuses the existing window" for free) plus a `Window` welcome scene. Opening resolves
  the top level first (`rev-parse`), so a subfolder and the root share one window. Recents are
  our own list (File › Open Recent, the welcome window) and also noted with
  `NSDocumentController` for the Dock menu. Folders are an `Alternate` document type, so
  Dock drops and `open -a Commit <folder>` work. Closing the last window doesn't quit; a
  Dock click brings back the welcome window. `SlopAppDelegate` is wrapped (appearance hook)
  rather than used directly, because it quits window apps on last close.
- **Diff and history are `NSTableView`s** (virtualised rows; native click/shift/⌘-click/drag
  line selection with non-change rows filtered out; a row per line for VoiceOver: "Added line
  12: …"). File lists, sidebar and sheets are SwiftUI.
- **Line staging pairs lines within a change block**: in "−b −c +B +c", staging −b/+B gives
  "a B c" (the i-th removal pairs with the i-th addition), not "a c B" as the naive
  "unselected removal becomes context in place" approach does. Found by a test; a seeded
  model test now checks random selections (staging and discarding) against expected file
  contents with real git.
- **Discarding files** stashes first (`stash push -u -- paths`), then puts back anything that
  was staged from the stash's index commit, so "discard" in the Changes list only drops
  unstaged work. ⌘Z restores the worktree from the stash's trees and drops the stash.
  (`stash push --keep-index -u -- paths` looked like the one-liner but loses staged changes
  with untracked paths; verified on git 2.54.)
- **Selection follows the flow**: when a staged/unstaged file leaves its list, the row that
  took its place is selected, so ↓ Space ↓ Space walks through Changes without jumping to
  Staged.
- **Stage or Unstage Selection is ⇧⌘Space in the menu** (Space and Return in the file list
  and the diff). A bare Space or Return menu shortcut would fire while typing a message.
- **⌘⌫ and ⌘↑/⌘↓** are also text-editing keys: when a text field or editor has focus the
  menu items hand the key back to it, so typing in the composer can never discard lines.
- **Big repositories**: the sidebar shows the first 200 branches of each section and says
  how many more the filter can find (7,001 branches in the `big` fixture). Ahead/behind is
  shown for the current branch only (from `status --branch`), never computed for every branch.
- **Processes**: `posix_spawn` in a new process group (cancel and timeout kill git's
  children too: ssh, hooks), one reader thread per child polling both pipes (blocking reads
  on the shared GCD pool starved it under load in tests), timers on a private queue.
- **FSEvents** at directory level, 0.25 s latency, classified (objects/logs/hooks ignored;
  `.git` state refreshes branches and stashes too), into a scheduler with a 250 ms debounce,
  one refresh in flight, one queued, ≥ 500 ms between starts. Paths are compared after
  `realpath` (FSEvents reports `/private/tmp`, not `/tmp`). Also refresh on window activation
  and wake.

## What couldn't be explored

- **Gitfox's UI wasn't driven this pass.** The owner was active at the Mac for the whole
  session (HID idle stayed under 1 s at every check), so the 60 s owner-idle gate never
  opened. Not seen first-hand as a result: the Diff, Accounts & Credentials, Identities &
  Signing, Shortcuts, Git and Integration settings panes; the history graph and commit
  detail; the switch-with-changes dialog; the stash sheet; the conflict UI on the `conflict`
  fixture; exact modifier keys for several Repository/Local Changes menu items. They are
  described from the official docs and the first pass. Worth a short walk in the build step
  if the owner is away: open only `/tmp/commit-research/demo` and `/tmp/commit-research/conflict`.
- Gitfox's first-launch onboarding (the installed copy has launched before).
- libgit2 wasn't benchmarked (not installed; no reason to add it to decide against it).

## Sources

- Gitfox site: <https://www.gitfox.app/>
- Release notes (5.0–5.4.2): <https://www.gitfox.app/release-notes>
- Support center: <https://www.gitfox.app/support>
- Getting started: <https://www.gitfox.app/support/start-here/getting-started>
- App variants (App Store build lacks signing, hooks, external tools): <https://www.gitfox.app/support/start-here/app-variants>
- Staging lines and hunks: <https://www.gitfox.app/support/committing-repository-workflow/staging-lines-and-hunks>
- Creating commits: <https://www.gitfox.app/support/committing-repository-workflow/creating-commits>
- Commit signing: <https://www.gitfox.app/support/committing-repository-workflow/commit-signing>
- Undoing changes: <https://www.gitfox.app/support/committing-repository-workflow/undoing-changes>
- Stashes and snapshots: <https://www.gitfox.app/support/committing-repository-workflow/stashes-and-snapshots>
- Managing branches: <https://www.gitfox.app/support/committing-repository-workflow/managing-branches>
- Integrating changes: <https://www.gitfox.app/support/committing-repository-workflow/integrating-changes>
- Resolving conflicts: <https://www.gitfox.app/support/committing-repository-workflow/resolving-conflicts>
- Clone and synchronize: <https://www.gitfox.app/support/accounts-remotes-authentication/repository-synchronization>
- HTTPS / SSH troubleshooting: <https://www.gitfox.app/support/accounts-remotes-authentication/troubleshooting-https-authentication>, <https://www.gitfox.app/support/accounts-remotes-authentication/troubleshooting-ssh-authentication>
- View modes, Quick Actions, custom shortcuts: <https://www.gitfox.app/support/customization-integrations/view-modes>, <https://www.gitfox.app/support/customization-integrations/quick-actions>, <https://www.gitfox.app/support/customization-integrations/custom-keyboard-shortcuts>
- Mac App Store listing and reviews: <https://apps.apple.com/us/app/gitfox/id1475511261>
- Setapp reviews: <https://setapp.com/apps/gitfox/customer-reviews>
- Product Hunt reviews: <https://www.producthunt.com/products/gitfox/reviews>
- libgit2 hooks work in progress (leaves out commit hooks): <https://github.com/libgit2/libgit2/pull/4620>
- libgit2 signing (bring your own signature): <https://libgit2.org/docs/reference/main/commit/git_commit_create_with_signature.html>
- libgit2 and credential helpers (Lix revert): <https://git.lix.systems/puck/lix/commit/8d422c2fef4309b4b7de8e2f909957775a9ec3ef>
- libgit2 licensing discussion: <https://www.github.com/libgit2/libgit2/discussions/6783>
- SwiftGit2: <https://github.com/SwiftGit2/SwiftGit2>; SwiftGitX: <https://swiftpackageregistry.com/ibrahimcetin/SwiftGitX>
- GitUp hooks subset (libgit2-based client): <https://github.com/git-up/GitUp/wiki>
- GitHub Desktop's git layer (dugite, bundled CLI): <https://github.com/desktop/dugite/issues/99>
- Sublime Merge architecture (own reader, git for writes): <https://www.sublimetext.com/blog/articles/sublime-merge>
- GUI clients and hook PATH problems: <https://github.com/typicode/husky/issues/639>, <https://community.atlassian.com/questions/140339/sourcetree-hook-failing-because-paths-don-t-seem-to-be-set-correctly>
- git docs used for command choices: `git status --porcelain=v2`, `git apply --cached --recount`, `git stash push -- <paths>`, `git log --format`, `git commit-graph`, `git diff --diff-algorithm` (local `man` pages, Apple Git 2.54)

## Build notes (test step)

### Performance (2026-11-07, M4 Max, macOS 27.2, release build unless noted; busy machine, load 5–8)

| Budget | Measured | How |
|---|---|---|
| Launch < 300 ms / first window < 600 ms | 182 ms / 378 ms | `scripts/perf.sh Commit` (welcome window) |
| Idle CPU < 0.2 % | 0.017 % (lowest of 3 × 5 s) | `scripts/perf.sh`; also no git processes while idle |
| Idle footprint < 120 MB | 35.8 MB | `scripts/perf.sh` |
| Open repo → Changes shown < 300 ms (`wide`) | 244 ms (`wide`), 51 ms (`demo`), 29 ms (`big`) | app log `open_to_status_ms` (includes waiting for git discovery) |
| History first 300 rows < 300 ms (`big`) | 239 ms in the app; 117–146 ms in the core test | app log `history_first_page_ms`; `PerformanceTests` |
| Full 100k history < 1.5 s | 1,033 ms in the app; 639–674 ms core | app log `history_all_ms`; `PerformanceTests` |
| Lane layout < 50 ms per 100k rows | 4.7 ms (max 42 lanes) | `laneLayoutOf100kRows` |
| Log parse of 100k rows (15 MB) | 58 ms | `parsingA100kRowLog` |
| Memory with 100k history < 250 MB | 129 MB | `drive stats` with History of `big` open |
| Select file → diff < 100 ms; 8.6 MB diff < 500 ms | 19–25 ms (`demo`); 80 ms for `big/huge.txt` (57,144 changed lines, parse 39 ms) | `PerformanceTests` |
| Slow diff algorithm: stop at 2 s, Myers | fallback verified with real git and a fake runner | `slowDiffFallsBackToMyers`, `fallbackIsTriggeredByATimedOutRun` |
| Stage line/hunk → lists and diff < 150 ms | 28–36 ms (apply + status + diff) | `stagingALineIsQuick` |
| Edit on disk → list updated < 500 ms | 203–472 ms | `anEditOnDiskIsSeenQuickly` (real FSEvents) |
| Event storm: ≤ 2 status runs/s, idle within 1 s | 3,000 files over ~2 s → 5 status runs, then none | `aStormOfWritesCostsAFewStatusRuns` |
| Branch sidebar with 7,000 branches | refs 245–255 ms (loaded after the file list), filter 7 ms | `branchesOfTheBigFixture`; sidebar shows 200 per section + "N more" |

Notes: every launch shows a transient footprint peak of 250–330 MB that drops back within
seconds; the welcome window alone does it and so does another suite app, so it's the
system's launch work, not Commit's data. The scrolling budgets (no dropped frames at 120 Hz)
need an Instruments pass by a person; the diff and history are `NSTableView`s with reused
row views, so only visible rows are drawn.

### Bugs found while testing (fixed)

- Partial line staging reordered lines inside a change block (see Decisions). Caught by
  `noTrailingNewline`, then covered by a seeded model test.
- `stash push --keep-index -u -- <paths>` drops staged changes (git 2.54); replaced.
- FSEvents paths are `/private/tmp/…`; the classifier compared against `/tmp/…` and ignored
  everything. Now compares real paths.
- Under parallel load, process timeouts didn't fire because blocking pipe reads filled the
  shared GCD pool; readers moved to one thread per child.
- `rev-parse` inside `.git` reported "bare"; now "inside a .git folder".
- The same path in Staged and Changes shared SwiftUI identity, so a partly staged file showed
  a ticked checkbox in both lists.
- A two-line banner message with `fixedSize` inflated the whole split view to 1,100 pt in a
  760 pt window (content scrolled under the toolbar). Banners now use a line limit.
- Conflicted files showed "No Changes": git prints `diff --cc` for them. Now diffed against
  "ours" (`git diff -2`), so the markers show; Mark Resolved / Open in Editor in the header.
- The history table's extra columns were off-screen in the middle column; it's now a graph
  plus a two-line commit cell (subject with branch/tag labels, then author · date · hash).

### Scripted walkthrough (release build, 2026-11-07)

Driven with `scripts/drive` on copies of the fixtures in `/tmp/commit-test/walk2` with a
throwaway `GIT_CONFIG_GLOBAL`; script: `apps/Commit/Tests/Fixtures/walkthrough.sh` (gated on
HID idle ≥ 60 s before every step; no mouse, no global keys). Git state checked with git
after every action. Screenshots in `/tmp/commit-test/shots/` (`walk-*.png`, `history-*.png`,
`changes-*.png`, `conflict-dark.png`, `welcome-dark.png`, `big-history.png`).

| Must-have | Walked | Result |
|---|---|---|
| Open a repo | `COMMIT_OPEN` (same path as `open -a`/Dock drop), restored windows on relaunch, recents in File › Open Recent and the welcome window | pass. Not walked: the ⌘O panel and a Finder drag (need a mouse) |
| Changes | checkbox stages a file; ⌘Z (Edit › Undo) restores the index exactly; partly staged file in both lists | pass |
| Diff | unified with numbers, hunk headers, "4 unchanged lines", CRLF marker, conflict markers, light and dark | pass (screenshots) |
| Hunk and line staging | Stage Hunk + ⌘Z; ↓ selects the next changed line, Space stages it, on the CRLF file | pass |
| Discard with undo | discard a line + ⌘Z; Discard All (confirmation, Cancel default) → clean tree, stash "Discarded all changes…", ⌘Z restores staged, unstaged and untracked | pass |
| Commit composer | type subject → counter, ⌘Return commits, ⌘Z undoes the commit (staged again, message back), Amend loads the message and amends; drafts restored per repo | pass |
| History | graph lanes, branch/tag labels, Uncommitted Changes row, light and dark; 100k-commit `big` | pass. Commit detail by keyboard: queued (screen locked) |
| Branches | New Branch sheet (validation, "Starts from main.") → created and switched; branch switcher popover; Stash and Switch when changes are in the way (conflicting pop → files marked conflicted, stash kept, banner says so) | pass |
| Fetch / Pull / Push | first push sets upstream; Pull on a divergent branch asks Merge or Rebase; Merge with autostash keeps local edits; Push lands on the remote | pass |
| Stash | stash sheet (message, untracked) → stash made, tree clean | pass. Stashes view drop / ⌘Z / Apply and Remove: queued (screen locked); covered by `stashListApplyPopDropAndRestore` |
| Repo-state banners | merge in progress banner, conflicted section, markers in the diff, Mark Resolved, Continue → merge commit; detached HEAD banner | pass |
| Askpass | the real app binary in helper mode answers through the socket (stand-in server); git calls askpass for HTTPS credentials and SSH signing passphrases (tests) | pass. The sheet end to end (SSH-signed commit with a passphrase key): queued (screen locked) |
| Standard pieces | no `[unlabeled]` controls in Changes, History, Stashes, conflict, welcome, Settings; window buttons 16×16 | pass. Settings screenshots: queued |

Bugs the walkthrough found (fixed): Undo registered on SwiftUI's environment undo manager
wasn't always the one Edit › Undo used (now the window's); after ⌘Return the focus stayed in
the subject field, so ⌘Z undid typing instead of the commit (the composer now gives up focus
after committing); ↑/↓ couldn't start a line selection in the diff (rows that aren't changes
are skipped now); a disabled Commit button still looked accent-coloured in a key window, and
the title truncated next to a hint; diff line rows weren't exposed to VoiceOver (each line now
has a labelled element: "Added line 12: …").

Not verified here, and why: the screen locked partway through (macOS hides windows from
Accessibility then), so the queued items above didn't run; HID idle stayed at 0 s for long
stretches before that. Scrolling at 120 Hz needs an Instruments pass by a person. The
"Install Command Line Tools…" state needs a Mac without them. `scripts/perf.sh` passed twice
with the screen unlocked (footprint 35.8 MB). With the screen locked it fails: every window
Commit opens starts with ~145 MB of "owned unmapped (graphics)" memory (29 window-sized
regions) that is reclaimed within 2 s when the display is awake but takes 5–20 s while it
sleeps, so perf.sh's samples read 180–255 MB. Tidy measures 47.7 MB under the same locked
conditions, so it's something Commit's windows do; ruled out by A/B builds: the app icon
image, the drop target, the hidden title bar, the login-shell PATH. Open item: find it with
Instruments (VM Tracker) on an unlocked Mac, then re-run `scripts/check.sh Commit --perf`.

Process note: one walkthrough pass used Edit › Copy in History, which put a fixture commit
hash on the real clipboard. That step was removed from the script; Copy Hash is covered by
code review only.

### Gap review (v1 must-haves)

All 15 must-haves are built. Partly deferred inside them, with reasons:
- Askpass: the sheet routes to the repository window and covers username, secret and host-key
  confirmation; there's no HTTPS server fixture, so the HTTPS path is verified at the git level
  (`credential fill` through askpass) rather than through a real push.
- Diff: "collapsed unchanged runs" are the gaps between hunks ("42 unchanged lines"); expanding
  one in place is later, ⌘= / ⌘− change the context for the whole diff.
- History: graph scope is the current branch + upstream (or a branch picked in the sidebar);
  "Show All Branches" is in the View menu. Search filters loaded rows (subject, author, hash).
- Branches: delete (undoable) and the toolbar switcher are in; rename is later.
- Discard of single lines in untracked files isn't offered (whole-file discard is).
Should-haves that made it: init, Commit and Push, Undo Commit, branch switcher popover,
context lines, ignore whitespace, auto-fetch (off), pull-request link after push, revert: no
(later). Clone: later (see Decisions).

### Design review (design-system §10)

| # | Check | Result |
|---|---|---|
| 1 | Main job in one shortcut/click | pass: tick/Space to stage, ⌘Return to commit |
| 2 | Native look, light and dark | pass (system split view, toolbar, lists; semantic colours) |
| 3 | Every action in a menu with a shortcut | pass (File, View, Changes, Branch, Repository) |
| 4 | Esc, ⌘, ⌘Q, standard shortcuts | pass; ⌘⌫ and ⌘↑/↓ hand back to text fields while typing |
| 5 | Settings: General (launch at login) + About | pass (General, Advanced, About) |
| 6 | Copy: HIG case, verbs, plain errors | pass |
| 7 | Empty states with symbol, line, action | pass (No Changes, No Stashes, No Commits Yet, welcome) |
| 8 | Permissions | n/a: none requested |
| 9 | Nothing destructive without undo | pass: discards stash first, drop/delete/commit undoable; Abort confirms |
| 10 | No network | pass: only git, only on fetch/pull/push or opted-in auto-fetch |
| 11 | Performance budgets | pass unlocked; see perf notes |
| 12 | VoiceOver names every control | pass (`drive tree`: 0 unlabeled) |
| 13 | Reduce Motion | pass (only short fades; drop target scale respects it) |
| 14 | Window size/position persist, sensible relaunch | pass (SwiftUI restoration; welcome on Dock click) |
| 15 | lint | pass |
| 16 | Full-size window buttons | pass (16×16) |
| 17–18 | Concentric corners, even insets | pass by construction (`Radius`, `Spacing`, system shapes); not measured with `scripts/measure` |
| 19 | Alignment | pass by eye on screenshots; not measured |
| 20 | Hairlines | pass (`Hairline`, `.hairlineBorder`, 1 px in row views) |
| 21 | Contrast | pass: `.textGreen/.textRed`, lane and label colours through `readable` |
| 22 | States | pass; disabled Commit now visibly disabled |
| 23 | Long/huge content | pass: middle truncation, 7,000 branches capped with a hint, huge diffs collapsed |
| 24 | Nothing jumps | pass after the banner fix; activity appears in the toolbar only while running |
| 25 | Golden Gate fit | pass: edge-to-edge sidebar, coloured sidebar icons, text-only menus, system toolbar, inactive windows grey their selections |
| 26 | Every surface light and dark | pass for the main window, conflict, history, welcome; Settings and sheets dark only so far |

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.

### Round 1 (<date>)
| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
