# Commit research (inspired by Gitfox)

> Written by the research step of [`docs/dev-cycle.md`](../dev-cycle.md). Studied: Gitfox
> 5.4.1 (12610, Setapp build, built 2026-10-30; installed copy at
> /Applications/Setapp/Gitfox.app, read-only) + its website, support center, release notes,
> App Store and Setapp reviews, on 2026-11-03. We study how it works so we don't reinvent the
> wheel. We never copy its name, icons, artwork, wording, sounds or signature visuals.
>
> How it was explored: Gitfox wasn't running. It was launched with window restoration
> suppressed (a launch argument, no setting changed) and pointed only at a throwaway repo
> created under `/tmp` (demo author, demo files). Its Repository Manager and Open Recent list
> are the owner's personal repos: not screenshotted, not transcribed. Only the General
> Settings pane was read before Gitfox was quit by the person at the Mac (it had come to the
> front once for a redraw). It wasn't relaunched; the other Settings panes are described from
> the official docs. Side effect: the `/tmp` demo repo now appears in Gitfox's recents (the
> folder has since been deleted). Screenshots stay in `/tmp/slopdrive`.
>
> Git behaviour was checked separately with `/usr/bin/git` (Apple Git 2.54, Xcode) under a
> Finder-like minimal environment: status, line staging, discard, commit, push, fetch, log.
> The results are in "Engine decision" below.

## The job

Commit is where a developer looks at what they changed, picks exactly which lines belong in
the next commit, writes a decent message, and syncs with the remote, without memorising
`git add -p` or reading raw diffs in a terminal. People reach for it many times a day,
between bursts of editing: "what did I just change?", "commit only the bug fix, not the
debug logging", "pull before I push", "park this work and switch branches". "Done" means the
commit says what it should, contains only what it should, and the branch is pushed, with no
worry that the tool did something surprising to the repo.

The one interaction that matters most: **open the repo window → the changed files and their
diff are already there → click the lines or hunks you want (or press a key) to stage them →
type a subject → ⌘Return.** Everything else (branches, history, push/pull, stash) supports
that loop.

## Who and when

- After a coding session: review every change file by file before committing; catch stray
  debug prints and discard them.
- Splitting one messy working copy into two or three focused commits by staging hunks and
  single lines.
- Switching to a teammate's branch for review: fetch, check out the remote branch, stash or
  carry local work.
- Looking back: "when did this change and why?" in the history, copy a commit hash for a PR
  or issue.
- Start and end of day: pull to get up to date, push what's done.

Frequency: many times a day, from seconds (glance at status, push) to 10+ minutes (careful
staging and message writing). The window often stays open all day next to the editor, so
idle cost and refresh behaviour matter.

## Engine decision: shell out to the user's git (recommended)

Gitfox itself does this: it bundles its own git 2.55 (`Contents/SharedSupport/bin/git`,
`libexec/git-core`), a small `askpass` helper, an `editor` helper, git-lfs, git-flow and a
`gitfox-cli` launcher, and links no git library. Its docs and site promise it "works with
existing repositories, config, credentials, and hooks". That is the bar.

**Recommendation: run the user's `git` executable as a subprocess for every operation. No
libgit2, no bundled git.**

Why not libgit2:

- **Behaviour, not licensing, is the deciding factor.** libgit2 doesn't run hooks, doesn't
  call credential helpers like `osxkeychain` on its own, doesn't run clean/smudge filters
  (git-lfs), and lags on newer git features (SHA-256 repos, reftable, `includeIf`
  variants, fsmonitor, sparse index, `gpg.format=ssh` signing). Every one of those is
  "the GUI did something different from Terminal", which is the worst kind of bug in a git
  client.
- **Licensing:** libgit2 is GPLv2 with a linking exception, which allows linking an
  unmodified copy from an MIT app. It's not on our permissive-only dependency list
  (design system section 9) and adds a C build to the universal binary. Possible, but no
  reason to take it on.
- **Performance is fine.** Measured on a synthetic repo with 20,050 files and 5,001 commits
  (Apple Git, M-series Mac): `status --porcelain=v2 -z` 70–76 ms, first 200 log entries
  51 ms, all 5,001 entries 59 ms, single-file diff 38 ms. A few tens of ms of process
  overhead is invisible next to human input.

Why not bundle git like Gitfox: it adds tens of MB, an update/security burden, and a git
that differs from the one the user's Terminal uses. Use what the user has.

Verified on this Mac (Finder-like env: `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, `HOME`,
`SSH_AUTH_SOCK` only):

| Check | Result |
|---|---|
| `credential.helper` | `osxkeychain`, set by Xcode's system gitconfig (`…/Developer/usr/share/git-core/gitconfig`), so HTTPS pushes reuse Keychain logins from Terminal. |
| `core.hooksPath` from `~/.gitconfig` | Respected; hooks ran on commit. |
| SSH | `SSH_AUTH_SOCK` is provided to GUI apps by launchd (`launchctl getenv`); `~/.ssh/config` (including `IdentityAgent`, e.g. 1Password) is read by `ssh` itself. OpenSSH 10.5 supports `SSH_ASKPASS_REQUIRE=force`. |
| `GIT_TERMINAL_PROMPT=0` | Missing credentials fail fast instead of hanging on an invisible prompt. |
| Line staging | Build a patch containing only the chosen lines, `git apply --cached --recount`; unstage with `-R`; discard from the worktree with `git apply -R`. All worked. |
| Discard with undo | `git stash push -u -m "<msg>" -- <paths>` removed only those paths (staged files untouched); `git stash pop --index` restored them exactly. |
| Unborn repo | `status` reports `branch.oid (initial)`; `git log` fails, so treat "no commits yet" as a state, not an error. |
| `#` lines | `commit -F -` keeps lines starting with `#` (cleanup is `whitespace` when not editing). Good for "#42 Fix…" subjects. |
| GUI PATH | `launchctl getenv PATH` is empty, so apps get `/usr/bin:/bin:/usr/sbin:/sbin`. This Mac's `~/.gitconfig` sets `filter.lfs.required=true` but `git-lfs` isn't on that PATH, and Homebrew/nvm/pnpm tools hooks often need aren't either. The login shell (here fish) resolves the real PATH via `$SHELL -l -c 'printenv PATH'` in about 280 ms. |

Implementation rules for the builder:

1. **Finding git:** Settings override path → else `/usr/bin/git` **only if** `xcode-select -p`
   succeeds (otherwise `/usr/bin/git` is a shim that pops Apple's "install developer tools"
   dialog) → else `/opt/homebrew/bin/git`, `/usr/local/bin/git` → else an empty state with an
   "Install Command Line Tools…" button that runs `xcode-select --install` (Apple shows its
   own dialog).
2. **Environment:** start from the app's env, prepend the login-shell PATH (resolved once,
   off the main actor, with a 3 s timeout and a marker around the output so shell greetings
   don't pollute it), set `GIT_TERMINAL_PROMPT=0`, `GIT_EDITOR=true` (and pass `--no-edit`
   where git would open an editor), `GIT_OPTIONAL_LOCKS=0` / `--no-optional-locks` for
   read-only refreshes so we never fight the user's terminal for `index.lock`.
3. **Output:** always machine formats: `status --porcelain=v2 -z --branch`,
   `log -z --format=<fields separated by %x1f>`, `for-each-ref --format=…`, `diff
   --no-color --no-ext-diff`, `-c core.quotepath=false`. Keep diff text as **bytes**; build
   staging patches from the raw bytes (non-UTF-8 files, CRLF and "\ No newline at end of file"
   markers must survive the round trip).
4. **Processes:** read stdout and stderr concurrently (a full pipe buffer deadlocks if you wait
   for exit first). Mutating commands run on a per-repo serial queue; reads can run in
   parallel. Network commands are cancellable (terminate the process) and show progress
   (`--progress`, parse the `\r` lines from stderr).
5. **Prompts (should):** set `GIT_ASKPASS` and `SSH_ASKPASS` (+ `SSH_ASKPASS_REQUIRE=force`)
   to a tiny helper inside the app bundle that asks the running app for a password/passphrase
   or host-key confirmation and shows a native sheet. Until then, failures say exactly what to
   run in Terminal.

## Feature inventory

Priority: **must** (v1 isn't worth shipping without it), **should** (v1 if cheap, else v1.1),
**later**, **skip** (with reason).

### Repositories and windows

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 1 | Open a local repo | File > Open Repository… (⌘O); folders are a document type (drag on Dock icon, `open -a`) | must | Accept a subfolder and open its top level (`rev-parse --show-toplevel`). Refuse bare repos with a clear message. |
| 2 | One window per repo, tabs | Each repo is a document window; native window tabs (New Tab, Merge All Windows) | must | `WindowGroup(for: URL.self)`; native tabbing for free. Restore open repos on relaunch. |
| 3 | Recent repositories | File > Open Recent; plus a Repository Manager window | must | Standard Open Recent menu + an empty-state list of recents in a "no repo open" window. |
| 4 | Repository Manager | Separate start window organising local and hosted repos into folders, with status and README rendering; "Track Folder…" auto-adds repos under a folder | later | v1's welcome window is just: recents list, Open…, Clone… |
| 5 | Create repo (init) | File > New Repository… (⌃⌘N) | should | When the chosen folder isn't a repo: "This folder isn't a Git repository. Create One" → `git init`. |
| 6 | Clone | File > Clone Repository… (⌃⌘C): URL, local name, destination, account, submodule options; existing destination is moved to Trash first | should | URL + destination + progress + cancel. No accounts. |
| 7 | Open in Finder / Terminal / editor | View menu: repo or selection in Finder (⇧⌘F), Terminal (⇧⌘T), editor (⇧⌘E); Terminal and editor app chosen in Settings | should | Finder and Terminal (system default app) in v1; editor choice later. |
| 8 | Command-line launcher | Bundled `gitfox-cli [path]`, installable | later | `open -a Commit .` already works through the folder document type. |
| 9 | Quick Look | File > Quick Look (⌘Y) on a selected file | should | Space on a file row = Quick Look (design system). |

### Working copy, diff and staging

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 10 | Changed-files list | "Local Changes" view: outline of files with a checkbox (= staged), status letters for index and worktree, +/− counts; folders get tri-state checkboxes; List / Tree / Group views; optional separate Staged/Unstaged sections; untracked display modes | must | Two sections, **Staged** and **Changes**, each a flat list with path dimmed and name prominent (tree view later). A partly staged file appears in both. Status as SF Symbol + label (Modified, Added, Deleted, Renamed, Untracked, Conflicted). |
| 11 | Live refresh | Filesystem-event-driven status since 4.1.7, batched; plus Refresh (⌘R). Reviews complain of stale status and missed new commits | must | FSEvents on the worktree and `.git` (HEAD, index, refs, packed-refs), 250 ms debounce, ignore `.git/objects` and lock files; also refresh on window activation. ⌘R forces it. |
| 12 | Diff view | Side panel: Unstaged/Staged switch, "INDEX vs WORKTREE" headers, three layouts (Fluid, Blocks = side by side, Unified), collapsed "N unchanged lines" separators, line numbers both sides, word-level highlight, whitespace markers | must | Unified view with old/new line numbers, hunk headers, word-level highlight on paired lines (should), collapsible unchanged runs. SF Mono via system monospaced design. |
| 13 | Side-by-side diff | Blocks/Fluid layouts | should | Toggle in the diff toolbar; unified is the default. |
| 14 | Stage / unstage whole file | Checkbox, Stage File / Unstage File buttons, Stage Selected / Unstage Selected / Toggle Stage (⌥Space) menu items, Stage All | must | Checkbox per row + Space toggles + "Stage All" / "Unstage All". |
| 15 | Stage / unstage a hunk | Gutter button beside each change block, or context menu; Diff > Stage (⌘→) / Unstage-or-Discard (⌘←) | must | A button in each hunk header ("Stage Hunk" / "Unstage Hunk") + keyboard. |
| 16 | Stage / unstage selected lines | Select lines (reviewers say it needs a click-and-drag in the gutter, hard to discover), then gutter button or context menu | must | **Click a changed line to select it**, shift-click to extend, ⌘-click to add; the hunk header button becomes "Stage 2 Lines". Keyboard line cursor too. See Flow 1. |
| 17 | Discard (file, hunk, lines, all) | Discard File button; Discard Changes (⇧⌘⌫), Discard All Changes (⌥⇧⌘⌫); context menu Discard Hunk / Lines; Settings "Discard Behavior: Stash by Default" | must | Every discard is undoable: file/all discards go into a stash named "Discarded …" (verified); hunk/line discards keep a reverse patch for ⌘Z. Untracked files: same stash (`-u`). |
| 18 | Undo in the diff | 4.0 added "change undo" for edits made in the diff | must (scoped) | ⌘Z undoes our last stage/unstage/discard (UndoManager per window). We don't edit file contents in the diff. |
| 19 | Context lines | Diff > More/Less Context (⌘+ / ⌘−), presets 3/7/15/30/50/100/Unlimited | should | ⌘+ / ⌘− and a small menu; default 3. |
| 20 | Next / previous change | Diff > Next Change (⌘↓) / Previous Change (⌘↑) | must | Same idea; also ↑/↓ moves between files in the list. |
| 21 | Whitespace options, diff algorithm | Settings: whitespace modes matching `git diff`, Patience (default since 4.3) / Histogram / Myers, line wrap toggle | should | "Ignore whitespace" toggle (`-w`, view only: staging is disabled while it's on, since the patch wouldn't apply). Algorithm: respect `diff.algorithm` from git config. Wrap: later. |
| 22 | Binary, image, large files | Image diff split/side-by-side; many image formats | should | v1: binary files show "Binary file, 4.2 MB → 4.3 MB" + Quick Look. Image diff later. Diffs over ~5,000 lines show a "Show Full Diff" button. |
| 23 | Blame | Inline blame column, jump to commit | later | |
| 24 | Find in diff | Find (⌘F) inside the diff since 4.0 | should | ⌘F in the diff pane uses the system find bar (NSTextFinder) if the diff is text-view based. |
| 25 | External diff/merge tools | Hand off to FileMerge, Kaleidoscope, Beyond Compare, VS Code, etc. (bundled launcher scripts) | later | |

### Committing

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 26 | Commit composer | Local Changes > Commit opens a commit window/sheet: staged count, target branch, one message editor with column markers from Settings (subject 50, body 72); button disabled until there's text and something staged. App Store reviewers object that it's modal and hides the diff | must | **Never modal.** Always visible under the changed-files list: a subject field with a live character count (soft hint past 50, warning past 72) and a body editor with a faint guide at 72 and a "Wrap at 72" command. ⌘Return commits. Commit button says what it will do ("Commit 3 Files to main"). |
| 27 | Amend | Local Changes > Amend HEAD; "amend controls" in the composer | must | "Amend last commit" checkbox in the composer: loads the previous message, allows a message-only amend with nothing staged, warns inline if the commit is already on the remote (`merge-base --is-ancestor HEAD @{u}`). |
| 28 | Draft and recent messages | Restores unfinished messages and merge messages; picks from recent messages | should | Draft saved per repo as you type (must, it's cheap and losing a message hurts). Prefill from `.git/MERGE_MSG` / `commit.template` (should). Recent-messages menu (should). |
| 29 | Commit and Push | Option in the commit button's menu; holding ⌥ changes the button | should | ⌥ on the commit button = "Commit and Push" (⌥⌘Return). |
| 30 | Hooks | Run by git; "Disable Commit Hooks" option | must (run) / later (disable) | Hooks run because git runs them. On failure show the hook's output in a sheet with "Copy Output". Bypass option later. |
| 31 | Identity | Settings > Git edits global `user.name` / `user.email`; app-level identities to switch between | must (missing-identity case) | Show "Committing as Name <email>" under the composer (from `git config`). If missing, inline fields + "Save to Git Config" (global) button. Multiple identities later. |
| 32 | Sign-off, reset author | Commit menu options | later | |
| 33 | Commit signing | SSH/OpenPGP signing settings and status (4.5) | later (works implicitly) | If `commit.gpgsign` is set, git signs. `pinentry-mac` works; terminal pinentry fails: show the error. No signing UI in v1. |
| 34 | Message autocomplete | `/` to insert paths, hashes, Gitmoji, issues (5.0) | later | |
| 35 | AI commit messages | Generates messages through the Claude or Codex CLI (non-App Store builds) | skip | Network/third-party CLI; against "quiet, no network" defaults. Revisit only if the owner wants it. |

### Branches, tags, remotes

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 36 | Branch list | Sidebar sections Local (HEAD badge, branch folders for `feature/…`), Remote (per remote, collapsible), pinned branches, ahead/behind badges (5.4) | must | Sidebar: Local branches with ahead/behind ("↑2 ↓1") and current-branch marker; Remotes collapsible. Slash-folders: should. Pinning: later. |
| 37 | Switch branch | Double-click / Quick Action; when local changes would be touched, asks: Stash, Stash and Reapply, Checkout anyway, Cancel | must | Return/double-click switches. If git refuses because of local changes: sheet with "Stash and Switch" (default; reapplies on the target), "Switch Anyway" only when git allows it, "Cancel". |
| 38 | Check out a remote branch | Via Quick Action / New Branch from… with "Track Starting Point" | must | Double-click `origin/x` → creates local `x` tracking it and switches (`git switch --track`). If `x` exists, switch to it. |
| 39 | Create branch | New Branch (toolbar, Repository > Create New Branch): name, starting point (branch/tag/commit), Track Starting Point, Check Out | must | Sheet: name (validated with `check-ref-format`), from (current branch or the selected commit), "Switch to new branch" on by default. |
| 40 | Branch switcher popover | Toolbar shows a breadcrumb "branch › upstream" | should | Toolbar branch button opens a filterable list (type to filter, Return to switch; ⇧⌘B). |
| 41 | Rename / delete branch | Move Branch… (rename), Delete… with Force and Delete on Remote; a reviewer nearly deleted a branch by mis-click | should | Delete: confirm sheet names the branch, Cancel is default; safe `-d` unless the user ticks "Delete even if not merged". Undo: we know the tip SHA, so ⌘Z recreates it. Remote delete later. |
| 42 | Tags | Sidebar Tags list; Create New Tag | should | List (read-only) + create lightweight/annotated tag on a commit. Push tags with "Push tags too" option later. |
| 43 | Remotes management | Add Remote…, Edit Remote (account), per-remote options | later | v1 reads remotes from config; editing in Terminal. |
| 44 | Merge / rebase into HEAD | Merge Into HEAD, Rebase HEAD with options (squash, no-ff, no auto commit, skip hooks) | later | |
| 45 | Interactive rebase | Reword/Edit/Squash/Fixup/Drop from the history | later | |
| 46 | Conflict resolution UI | Conflicted files in Unstaged; per-hunk Choose Ours/Theirs, Use Ours/Use Theirs for the whole file, save = stage; Continue/Abort in a status bar | later (UI) / must (state) | v1: show conflicted files clearly, block staging them with an explanation, "Mark Resolved" (= stage) after the user fixes them in their editor, and a banner with Continue / Abort for merge, rebase, cherry-pick, revert. |
| 47 | Cherry-pick, revert, reset | History context menu with options | revert: should; others later | Revert creates a new commit, so it's safe. Reset (hard) is destructive: later with a stash-first default. |
| 48 | Git-flow, bisect, worktrees, submodules, LFS commands | Toolbar/menus for each | later | Submodules show as entries in status; LFS works implicitly when `git-lfs` is on the login PATH. |
| 49 | Hosting accounts, PR links, issue sources, link manager | GitHub/GitLab/Bitbucket/Gitea/Jira accounts, "Create Pull Request" after push opens the web page, clickable issue keys | later | "Create pull request" link after push: should (parse the URL git's remote prints in stderr and offer "Open Pull Request Page"). No accounts. |

### Sync

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 50 | Fetch | Repository > Fetch…, Fetch All Remotes; always prunes; toolbar button | must | Toolbar + menu; fetches all remotes with `--prune`. Progress in the toolbar, cancellable. |
| 51 | Pull | Pull… dialog (remote, branch, rebase instead of merge, autostash); Pull HEAD (no dialog) | must | One-click Pull of the current branch's upstream. Respect `pull.rebase`/`pull.ff`; if git stops with "divergent branches", ask Merge / Rebase / Cancel and offer to remember the choice in this repo's config. `--autostash` when the tree is dirty (say so). |
| 52 | Push | Push… dialog (branch, remote/destination, Track Remote Branch on when there's no upstream, force, force with lease, push all tags, check submodules, open PR page); Push HEAD; drag a branch onto a remote | must | One-click Push of the current branch. No upstream → push to `origin` (or ask which remote if several) with `-u`. Rejected (non-fast-forward) → "The remote has commits you don't have. Pull first." with a Pull button. |
| 53 | Force push (with lease) | Separate menu items with confirmations | later | Only with lease, behind a confirm. |
| 54 | Sync (fetch + pull + push) | "Sync HEAD" (4.3) does all three | should | One "Sync" toolbar button is a nice default for the common case. |
| 55 | Automatic fetch | Settings: Automatic Fetch, default every 10 minutes; 5.4 even fetches repos that aren't open; notifications about new commits | should (off by default) | Opt-in in Settings (Off / 5 / 15 / 30 min), only for open windows, no notifications: the ahead/behind badge is the signal. |
| 56 | Credentials UI | Accounts & Credentials pane: service accounts, generic HTTPS username/password, stored SSH key passphrases; asks which account to use on failure | skip (accounts) / should (askpass) | We rely on the user's credential helper and SSH setup. An askpass sheet covers one-off prompts (see Engine decision, rule 5). |
| 57 | SSH host key confirmation | Asks before the first connection to an unknown host (5.1) | should | Comes with the askpass helper (ssh asks through `SSH_ASKPASS`). Without it, explain and offer "Copy Command". |

### History

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 58 | Commit list | Middle column: avatar initials, author, ref labels (branch/tag chips, "+2 hidden labels"), relative/short time, short hash, subject; the working copy shows as a "N modified files" row on top; compact modes | must | Paged list (load 300 at a time) of subject, author, relative date, short hash, ref labels. A top "Uncommitted Changes" row is a good idea (see patterns). |
| 59 | Graph | Colored lanes with merge curves in the list's left gutter | must (simple) | Lane graph computed from parent hashes (standard lane-assignment, drawn per row with `Canvas`). Default scope: current branch + its upstream; "All Branches" toggle (should). Straight lines and dots are enough; no curves needed. |
| 60 | Commit detail | Selecting a commit shows a header (message, author, date, parents, refs) + changed files + diff | must | Same diff view, read-only. Copy hash (⌘C), copy subject. |
| 61 | Search history | Filter field under the log ("Commit Message"); full-text search through file contents across history | should | Filter by message/author/hash (`--grep`, `--author`, prefix match). Content search (`-S`) later. |
| 62 | File history | From a file's context menu | later | `log --follow -- path`. |
| 63 | Compare branches/commits | Compare any two revisions | later | |
| 64 | Reflog | Sidebar Reflogs section | later | Our own undo covers the common "oops"; a reflog view is a strong v1.1 safety net. |

### Stash

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 65 | Stash changes | Local Changes > Push Stash…: message, only staged, keep staged, include untracked, include ignored | must | Sheet: message (optional), "Include untracked files" (on). Others later. |
| 66 | Stash list and contents | Sidebar Stashes with count badge; selecting shows files + diff | must | Sidebar item with count → list → selecting shows files and diff (read-only). |
| 67 | Apply / pop / drop | Apply Stash… with Restore Index and Pop options; Drop n Stashes | must | Apply, Pop (apply + drop), Drop. Drop is undoable: keep the dropped SHA and `git stash store` it back on ⌘Z. |
| 68 | Stash selected files; apply single files from a stash; snapshots (stash without touching the tree) | Context menus, drag to sidebar | later | Snapshot = `git stash create` + `store`: cheap, nice later. |

### App-level

| # | Feature | How the original does it | Priority | Notes for us |
|---|---|---|---|---|
| 69 | Activity / tasks indicator | Toolbar "Tasks" status ("No Active Tasks") with running operations | must | Toolbar activity area: current operation + progress + Cancel; errors stay until dismissed. |
| 70 | Command palette | Quick Action (⌘P): fuzzy actions and targets (branches, repos, clone URLs), two-step "merge release" | later | Strong pattern; worth it in v1.1 once the action set is stable. |
| 71 | Custom shortcuts | Settings > Shortcuts table for every menu command | skip | macOS already lets users remap menu shortcuts in System Settings > Keyboard. |
| 72 | Appearance | System / Light / Dark | skip | Follow the system. |
| 73 | Release notes on update | Separate window opens after updates (on by default) | skip | Design principle: no "what's new" sheets. |
| 74 | Analytics, crash reporting | Sentry + TelemetryDeck bundled; license checks | skip | No telemetry (design system section 7). |
| 75 | `x-github-client` handler | Optional "Open GitHub Desktop links" | later | |
| 76 | Reflog/undo for commits | — | should | ⌘Z after a commit offers "Undo Commit" (soft reset to the previous HEAD, message goes back into the composer), only until the next push. |

## Key flows

### Flow 1: review, stage some lines, commit (the main job)

How Gitfox does it (demo repo):
1. The repo window opens on Local Changes: sidebar (Repository: Local Changes with count,
   Graph, Stashes with count, Settings; then Local branches with a HEAD badge, Remote, Submodules,
   Tags, Reflogs; filter field at the bottom) → commit log column with a "3 modified files" row
   on top and a breadcrumb "main › origin/main" → file outline with checkboxes → diff.
2. Selecting a file shows its unstaged diff in side-by-side "Blocks" layout with
   "N unchanged lines" separators; the Unstaged/Staged switch is above it.
3. "Stage File" (or ticking the checkbox) stages it; the diff flips to the Staged side
   (HEAD vs INDEX) and the folder checkbox shows a mixed state.
4. Line staging: select lines in the gutter (drag), then the gutter button or the context menu.
5. Local Changes > Commit (or the Commit button above the file list, disabled until something
   is staged) opens the commit window; type the message; choose Commit or an option from the
   button's menu (Commit and Push, sign-off, reset author, disable hooks).

Ours:
1. Window opens on **Changes**: file list on the left (Staged section above Changes
   section), diff on the right, composer docked under the file list. First file selected.
2. ↑/↓ moves through files; the diff follows. Space toggles the file's staged state.
3. In the diff, Tab moves focus into it; ⌘↓/⌘↑ jumps between hunks; each hunk header has
   **Stage Hunk** (or **Unstage Hunk** in the Staged section's diff).
4. Click a changed line (+ or −) to select it; shift-click/drag extends, ⌘-click toggles.
   Selected lines get the accent tint; the hunk header button reads "Stage 2 Lines".
   Keyboard: in the diff, ↑/↓ moves a line cursor, Space selects, Return stages the
   selection (or the hunk if nothing is selected). ⌘⌫ discards the selection (undoable).
5. Type a subject in the composer (⌘L focuses it from anywhere, Tab goes to the body). The
   counter shows "42/50"; past 72 it turns orange and says "Long subjects get cut off in
   many tools".
6. ⌘Return. The composer clears, the commit appears at the top of History, a small HUD says
   "Committed a1b2c3d". ⌘Z right after offers "Undo Commit".
7. If a hook fails or identity is missing, the composer keeps the message and shows the
   reason inline with what to do.

### Flow 2: first run

Gitfox: opens a Repository Manager window (repo folders, statuses, README) and, after
updates, a Release Notes window. Its docs then send you to Settings to add hosting accounts,
set your git identity and identities, and choose the git binary. (First-launch onboarding
couldn't be seen: the installed copy isn't on its first launch.)

Ours:
1. Launch → a small welcome window: "Open a Git repository" with **Open…** (⌘O), **Clone…**,
   and recent repositories (empty at first). Dropping a folder on it or on the Dock icon opens it.
2. Git check happens silently in the background. If no git is found: the welcome window says
   Commit needs Apple's command line tools and offers **Install Command Line Tools…**.
3. Opening a folder that isn't a repo: "This folder isn't a Git repository." **Create
   Repository** / **Choose Another Folder…**.
4. Repo opens on Changes (or History if the tree is clean). No tour, no accounts, no
   permission prompts. If the repo lives in Documents/Desktop/iCloud Drive, macOS may ask once
   to allow access to that folder (because git runs on our behalf): that's the system's
   prompt, not ours.
5. Missing `user.name`/`user.email` is caught at the first commit (inline fields), not up front.

### Flow 3: switch branches with local changes

Gitfox: double-click a branch (or Quick Action). If the checkout would touch the working
tree: Stash / Stash and Reapply / Checkout / Cancel. It skips the question when the tree is
clean or the target tree equals HEAD.

Ours: Return/double-click a branch (or the toolbar branch popover, type to filter, Return).
Run `git switch <name>`. If git refuses because of local changes, sheet: "You have changes
that would be overwritten by switching to <name>." **Stash and Switch** (default: stashes
with untracked, switches, pops; if the pop conflicts, the stash is kept and we say so) /
**Cancel**. Remote branch → local tracking branch automatically.

### Flow 4: pull and push

Gitfox: toolbar group with Fetch, Pull, Push, Sync HEAD; Pull…/Push… dialogs with options;
"HEAD" variants skip the dialog. Tasks indicator in the toolbar.

Ours:
1. Toolbar: **Fetch**, **Pull**, **Push** (and **Sync**, should), each acting on the current
   branch without a dialog. The branch row shows ↑ahead ↓behind after every fetch.
2. Push with no upstream: pushes to `origin` with `-u` (asks which remote only if there are
   several). If the remote prints a "create a pull request" URL, the success HUD offers
   **Open Pull Request Page**.
3. Errors map to plain sentences + one action: rejected → "Pull first" (Pull button);
   auth → "Git couldn't sign in to origin. Check your credentials in Terminal with
   `git push`." (Copy Command); divergent pull → Merge / Rebase / Cancel; hook failure → output.
4. Any operation can be cancelled from the toolbar activity area.

### Flow 5: discard and undo

Gitfox: Discard File / Discard Changes (⇧⌘⌫) / Discard All (⌥⇧⌘⌫) / Discard Hunk/Lines;
Settings "Discard Behavior" defaults to "Stash by Default", so discarded work lands in
Stashes.

Ours: ⌘⌫ discards the selected file(s), hunk or lines, no confirmation for single
lines/hunks; files and "Discard All…" confirm once (Cancel default) and say "You can undo
this". Files go into a stash "Discarded <paths> (date)", lines/hunks keep a reverse patch.
⌘Z (Edit > Undo Discard) restores. The stash also shows in Stashes for later recovery.

### Flow 6: stash

Ours: toolbar Stash button (⌥⌘S): message + "Include untracked files" → stash. Stashes in the
sidebar with a count; select one to see files and diff; **Apply**, **Pop**, **Drop** (⌘Z
restores a dropped stash).

### Flow 7: history

Ours: ⌘2 (or sidebar History): paged list with graph lanes for the current branch and its
upstream; ref labels; select → detail (message, author, date, parents, hash with copy button)
+ files + diff. ⌘F filters by message/author/hash. Right-click: Copy Hash, Copy Subject,
Create Branch Here…, Revert Commit (should).

## Settings inventory

Gitfox's General pane (seen, values are the installed defaults on this Mac):

| Setting | Default | Options | Keep? |
|---|---|---|---|
| Appearance | System | System / Light / Dark | No: follow system. |
| Automatic Fetch | Every 10 minutes | Off and intervals | Yes, as **Fetch automatically**: Off (default) / 5 / 15 / 30 min. |
| Discard Behavior | Stash by Default | Stash / discard permanently (inferred) | No setting: we always make discards undoable. |
| Show Release Notes on Update | On | toggle | No. |
| Default Terminal | System | app picker | Later (use the default app for `.command`/Terminal). |
| Default Editor | None | app picker | Later. |
| Open GitHub Desktop links | Off | toggle | Later. |
| Max Subject Length | 50 characters (reset button) | number | Yes, as the composer's subject guide (50, warning at 72). Fixed in v1; setting later. |
| Max Body Length | 72 characters | number | Yes, body guide at 72. Fixed in v1. |

Other Gitfox panes (from docs; not opened): **Diff** (layout, algorithm, whitespace modes, line
wrap, monospace font from several bundled fonts), **Accounts & Credentials** (hosting
accounts, generic HTTPS credentials, stored SSH key passphrases), **Identities & Signing**
(committer identities, SSH/OpenPGP signing), **Shortcuts** (rebind any menu command, conflict
detection, reset), **Git** (global `user.name`/`user.email`, default branch, which git binary),
**Integration** (external diff/merge tools, command-line tool). Persisted view choices also
include diff layout, merge defaults (no-ff, squash, skip hooks) and clone destinations.

Ours (SlopSettings, design system section 3):

| Tab | Setting | Default |
|---|---|---|
| General | Fetch automatically | Off |
| General | Show untracked files | On |
| General | Default diff layout | Unified |
| Advanced | Git executable | Automatic (shows the resolved path and version) / Choose… |
| Advanced | Use my login shell's PATH for Git and hooks | On |
| About | AboutView | — |

No "Launch at login" (a repo window app doesn't need it). Git identity is edited where it's
needed (composer) and written to git config, not stored by us.

## Menus and shortcuts

Gitfox's main menu (structure, from the Accessibility tree; some modifier glyphs weren't
readable through Accessibility, so letters are given as shown):

- **App:** About, Release Notes, Settings… ⌘,, Services, Hide, Quit.
- **File:** New ⌘N, New Tab ⌘T, Open Repository… ⌘O, Open Recent, New Repository… ⌃⌘N,
  Clone Repository… ⌃⌘C, Track Folder…, Quick Look ⌘Y, Close ⌘W, Close All ⌥⌘W, Save… ⌘S
  (for edits in the diff).
- **Edit:** standard.
- **View:** Back ⌘[, Forward ⌘]; Show Local Changes ⌘1, Show Graph ⌘2, Show Stashes ⌘3,
  Show Settings ⌘4, Show HEAD Branch ⌘0; Inspect Changes (Q); List / Tree / Group View;
  Separate Staged / Unstaged; Hide Commit Log for Local Changes; Compact Commit Log; Compact
  Commit Header; Untracked Files (git default / files and folders / all files / hide);
  Submodules & Worktrees (open in push/new window/new tab); Show Repository/Selection in
  Finder ⇧⌘F / ⌥⇧⌘F, in Terminal ⇧⌘T / ⌥⇧⌘T, in Editor ⇧⌘E / ⌥⇧⌘E; Full Screen.
- **Find:** Find… ⌘F, Find Next ⌘G, Find Previous ⇧⌘G.
- **Repository:** Sync HEAD (Y); Fetch (F), Fetch All Remotes (⌥F); Pull… (P), Pull HEAD
  (⌥P); Push… (U), Push HEAD (⌥U), Force Push with Lease… ⌥⌘U, Force Push… ⌃⌥⌘U; Create New
  Branch (B), Create New Tag (T); Rebase HEAD (R), Merge Into HEAD (M); Interactive Rebase ▸
  Reword/Edit/Squash/Fixup/Drop; Bisect…; Apply Patch… ⇧⌘A; Git LFS ▸ Install/Uninstall/
  Fetch/Pull/Push HEAD; Add Remote…, Add Submodule…, Add Worktree… (W); Refresh ⌘R; Quick
  Action ⌘P; Open Diff or Mergetool (D) / for Selection (⌥D); Open Link Manager… (L);
  Configure Issue Sources… (I).
- **Local Changes:** Commit (C), Amend HEAD (A); Stage Selected (.), Unstage Selected (,),
  Toggle Stage ⌥Space; Resolve Using Ours / Theirs; Push Stash… (S), Apply Stash… (⌥S),
  Snapshot All Changes… (⌃S); Discard Changes ⇧⌘⌫, Discard All Changes ⌥⇧⌘⌫.
- **Diff:** Previous Change ⌘↑, Next Change ⌘↓; Stage ⌘→, Unstage / Discard ⌘←; Show
  Unstaged ⌥⌘←, Show Staged ⌥⌘→; More Context ⌘+, Less Context ⌘−; Context Lines ▸ Unlimited,
  3 (default), 7, 15, 30, 50, 100.
- **Window:** standard + tab commands; Repository Manager; Release Notes.
- **Help:** Help, Send Feedback, social links.

Toolbar (left → right): Back, activity/Tasks status, Quick Action, Sync HEAD, Fetch / Pull /
Push segmented group, Merge, Rebase, New Branch, Git Flow menu, Stash menu, Refresh.

Ours (proposal; every action also in a menu, standard shortcuts mean the standard thing):

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

(Builder: check these don't collide with SwiftUI or system defaults (document apps reserve ⇧⌘S
for Save As), and adjust if any are taken.)

## Permissions and system integration

Gitfox:
- Not sandboxed (empty entitlements), so it can run git anywhere. No Accessibility, Screen
  Recording or Full Disk Access requests.
- Declares folders as an Editor document type (open folders from Finder/Dock/`open -a`).
- URL schemes: its own `gitfox:` and `x-github-client:` (only claimed when the user opts in).
- Links UserNotifications (background fetch notifications), WebKit (README rendering),
  StoreKit (subscription), Sentry (crash reports) and TelemetryDeck (usage analytics).
- An older App Store review complains that the sandboxed build needed access to the whole home
  folder; the direct/Setapp builds avoid that.

Ours:
- **Not sandboxed** (needs to run git and the user's hooks). No special permissions.
- Folders as a document type (Viewer/Editor) so "Open With", Dock drops and `open -a Commit .` work.
- macOS may show its own one-time prompt for repos in Documents, Desktop, Downloads, iCloud
  Drive or removable/network volumes, attributed to Commit because git runs as our child.
  Don't pre-ask; if git fails with "Operation not permitted", explain and link Privacy &
  Security > Files and Folders.
- No URL scheme, notifications, Services or App Intents in v1. Later: "Open in Commit"
  Finder Service / App Intent.
- No network of our own. Git talks to the user's remotes only when the user fetches, pulls,
  pushes or clones (or opted into auto-fetch). README says so.

## UX patterns worth adopting

- **The working copy is the first row of history.** Gitfox puts an "N modified files" row
  above the newest commit, so "what I'm doing now" and "what I did" are one list. For us: the
  History list starts with "Uncommitted Changes (3)"; selecting it jumps to Changes.
- **Checkbox = staged.** A file's staged state is a checkbox right in the row, folders show a
  mixed state. Instantly readable, and Space toggles it.
- **The diff follows the action.** After staging, the diff switches to the staged side so you
  see what will be committed.
- **Tracking at a glance.** A "branch › upstream" breadcrumb over the history and ↑↓ badges
  on branches answer "am I in sync?" without fetching a dialog.
- **Collapsed unchanged runs** ("N unchanged lines", click to expand) keep long files
  readable without losing orientation; context lines are adjustable with ⌘+/⌘−.
- **Discards are recoverable by default** (stash instead of delete).
- **One-click "HEAD" variants** of pull/push skip the dialog; options live in the
  "…" versions. We ship only the one-click versions in v1.
- **Ask once at the moment of conflict** (stash-and-switch choice) instead of a preference.
- **Commit is disabled until there's something staged and a message**, and the button says
  what it will do.
- **Push sets up tracking automatically** when the branch has none.
- **Activity in the toolbar**, never a blocking progress window.
- **Keyboard-first palette** (⌘P) for everything: a v1.1 candidate.

## What we won't copy, and what we'll do better

- Not copying: the name, fox icon, colors and chip styles, bundled monospace fonts, the
  four-column layout as-is, wording, the Repository Manager, release-notes window, accounts,
  subscription/trial flows, telemetry.
- Doing better:
  - **The composer is never modal.** Reviewers on both App Store and Setapp complain the
    commit window hides the diff; ours is docked next to it.
  - **Line staging by single click**, not a gutter drag (Setapp review: "hard to discover").
  - **Fast with many branches and commits:** paged log, lazy graph, background parsing, only
    changed rows redraw (several reviews mention freezes and slowness; the developer's
    workaround was hiding merged branches).
  - **Never stale:** FSEvents on refs + activation refresh (a review says it stopped noticing
    new commits).
  - **Safer destructive actions:** names in confirmations, Cancel as default, and undo for
    branch delete, stash drop, discard and the last commit (a review mentions nearly deleting
    a branch by mis-click).
  - **Behaves exactly like Terminal git:** the user's own git, config, hooks, credential
    helper, SSH agent and PATH (common GUI-client failure: hooks can't find `node`/`npx`
    because GUI apps don't get the shell PATH).
  - **Plain-language errors** for the ten failures everyone hits (no upstream, rejected push,
    divergent pull, auth, missing identity, hook failure, `index.lock`, conflicts, detached
    HEAD, missing command line tools).
  - **VoiceOver:** Gitfox's file checkboxes and some buttons are unlabeled in the
    Accessibility tree; ours name every control ("Stage notes.txt").
  - **Native look:** system fonts (SF Mono for code), accent color, standard controls.
  - **No telemetry, no accounts, no subscription.**

## Edge cases

Repository states
- No commits yet (unborn HEAD): status works; History shows an empty state; diff staged
  changes against the empty tree; first commit works.
- Detached HEAD: banner "You're not on a branch" with **Create Branch Here…**; commits still
  work.
- Merge / rebase / cherry-pick / revert in progress (`.git/MERGE_HEAD`, `rebase-merge/`,
  `rebase-apply/`, `CHERRY_PICK_HEAD`, `REVERT_HEAD`): banner with Continue / Abort; conflicted
  files flagged; staging a file with conflict markers asks first.
- Worktrees (`.git` is a file), submodules (shown as an entry, `S…` in porcelain v2, no
  recursion), sparse checkouts, shallow clones (graph with missing parents), SHA-256 repos
  (hash length 64), reftable.
- Bare repo or a folder inside `.git`: refuse with a message.
- Repo moved, renamed or deleted while open: show "This repository is no longer at <path>"
  with Locate… / Close.
- `index.lock` held by the user's terminal or an editor: retry a few times with backoff, then
  "Another Git process is using this repository. Try again in a moment." Never delete the lock
  ourselves.
- Huge working copies: 20k+ files, an unignored `node_modules` (untracked dirs shown
  collapsed with `--untracked-files=normal`), thousands of changed files (list virtualised).

Diffs and staging
- Binary files, images, very large files and huge diffs (cap + "Show Full Diff").
- Renames and copies (porcelain `2` entries with the original path), mode-only changes,
  symlinks, deleted files, files with spaces/newlines/Unicode in names (always `-z`).
- "No newline at end of file", CRLF files and `core.autocrlf`, mixed encodings / non-UTF-8:
  patches built from raw bytes; display decodes lossily.
- File changes on disk between showing the diff and staging lines: the patch fails to apply →
  refresh and say "The file changed. Try again."
- Ignore-whitespace view: line/hunk staging disabled with an explanation.
- git-lfs files: pointer files show as text; if `git-lfs` is missing and the repo needs it,
  git's error is shown with "Install git-lfs (e.g. with Homebrew), then try again."

Committing and syncing
- Missing identity, empty message, nothing staged (Commit disabled; amend allows
  message-only), message with `#` lines (kept), very long subject, non-ASCII messages.
- Hooks that fail, hang (cancel button), or need tools only on the shell PATH.
- Signing configured with a terminal-only pinentry: show git's error.
- Amending a pushed commit: inline warning before, not after.
- No remote; several remotes; upstream gone (`[gone]` in `upstream:track`); remote branch
  deleted; push rejected; protected branch; network offline; slow network (cancel); the
  Mac sleeps mid-fetch (process ends with an error: show it, retry is safe).
- HTTPS without a stored credential, 2FA (token needed), SSH key with passphrase, unknown host
  key: never hang (`GIT_TERMINAL_PROMPT=0`, askpass or a clear message).
- Command line tools missing / git path override pointing at nothing.

App
- Several repos open in tabs/windows; the same repo opened twice (focus the existing window).
- Relaunch restores open repos and the selected view; drafts survive quit and crash.
- Light/dark, Increase Contrast (diff colors must still read: use system green/red with
  sufficient contrast plus +/− glyphs, never color alone), Reduce Motion, VoiceOver reading
  diff lines ("Added line 12: …"), full keyboard access.
- Long branch names, many branches (1,000+: filter field), many stashes.
- Idle: no polling; FSEvents only; idle CPU < 0.2% with a repo open.

## Our v1 scope

The test step walks this list. Must-haves only; "should" items ship if time allows.

- [ ] **Git engine:** finds the user's git (override → `/usr/bin/git` only if command line
      tools exist → Homebrew paths), uses the login-shell PATH, never hangs on a prompt,
      read-only refreshes don't take `index.lock`. Missing tools → install button.
- [ ] **Open a repo:** ⌘O, drop a folder, Open Recent, `open -a`; subfolder opens its top level;
      non-repo and bare repo explained; one window per repo, restored on relaunch.
- [ ] **Changes view:** Staged and Changes sections with status, live refresh (FSEvents +
      activation, ⌘R), keyboard navigation, Space toggles staging, Stage All / Unstage All.
- [ ] **Diff view:** unified with line numbers, hunk headers, collapsed unchanged runs,
      next/previous change, binary and huge-file handling, light and dark.
- [ ] **Hunk and line staging:** Stage/Unstage Hunk buttons; click/shift/⌘-click line
      selection + keyboard; works on CRLF, no-trailing-newline and non-UTF-8 files.
- [ ] **Discard with undo:** file, hunk, lines, all; ⌘Z restores; file discards recoverable
      from Stashes.
- [ ] **Commit composer:** docked (non-modal), subject counter (50/72), body guide, draft saved
      per repo, ⌘Return, amend (incl. message-only, warning if pushed), hook failures shown
      with output, missing identity fixed inline.
- [ ] **Branches:** sidebar list with current marker and ahead/behind; switch (with
      Stash and Switch when needed); check out a remote branch as a tracking branch; create
      from HEAD or a selected commit.
- [ ] **History:** paged list with simple lane graph (current branch + upstream), ref labels,
      commit detail with files and diff, copy hash; "Uncommitted Changes" top row.
- [ ] **Fetch / Pull / Push:** one-click on the current branch with progress and cancel;
      first push sets upstream; divergent pull asks Merge/Rebase; rejected push and auth
      failures explained; works with osxkeychain HTTPS and an SSH agent.
- [ ] **Stash:** stash (message, include untracked), list with count, view contents,
      apply / pop / drop (drop undoable).
- [ ] **Repo state banners:** detached HEAD, merge/rebase/cherry-pick in progress with
      Continue/Abort, conflicted files flagged and "Mark Resolved".
- [ ] Standard pieces: Settings (General, Advanced, About), every action in a menu with a
      shortcut, no unlabeled controls, perf budgets for a window app (< 120 MB idle with a
      20k-file repo open, idle CPU < 0.2%).

## Open questions

1. **Engine:** confirm "shell out to the user's git, no libgit2, no bundled git". (Strongly
   recommended; see Engine decision.)
2. **Graph in v1:** a simple lane graph is listed as must (current branch + upstream). OK, or
   ship a flat list in v1 and the graph in v1.1 to protect the staging/diff quality?
3. **Auto-fetch default:** off (our network rule) vs on every 15 min (what git GUI users expect,
   and what Gitfox does). It only talks to the user's own remotes.
4. **Askpass helper in v1?** Without it, a missing HTTPS credential or SSH passphrase means
   "run this in Terminal once". It's the most likely blind-test failure on a fresh Mac.
5. **Clone in v1?** Cheap and expected by new users; listed as should.
6. **Login-shell PATH on by default?** It's what makes hooks (husky, lint-staged) and git-lfs
   work like Terminal, but it runs the user's shell startup files once per launch.
7. **"Undo Commit"** (soft reset of the last unpushed commit) in v1? Very handy, small,
   but it rewrites history: needs the owner's comfort.
8. **Side-by-side diff** in v1 (should) or v1.1? Some users won't use a client without it.

## Sources

- Gitfox site: <https://www.gitfox.app/>
- Release notes: <https://www.gitfox.app/release-notes>
- Support center index: <https://www.gitfox.app/support>
- Getting started: <https://www.gitfox.app/support/start-here/getting-started>
- Staging lines and hunks: <https://www.gitfox.app/support/committing-repository-workflow/staging-lines-and-hunks>
- Creating commits: <https://www.gitfox.app/support/committing-repository-workflow/creating-commits>
- Stashes and snapshots: <https://www.gitfox.app/support/committing-repository-workflow/stashes-and-snapshots>
- Managing branches: <https://www.gitfox.app/support/committing-repository-workflow/managing-branches>
- Integrating changes: <https://www.gitfox.app/support/committing-repository-workflow/integrating-changes>
- Resolving conflicts: <https://www.gitfox.app/support/committing-repository-workflow/resolving-conflicts>
- Undoing changes: <https://www.gitfox.app/support/committing-repository-workflow/undoing-changes>
- Clone and synchronize: <https://www.gitfox.app/support/accounts-remotes-authentication/repository-synchronization>
- HTTPS / SSH troubleshooting: <https://www.gitfox.app/support/accounts-remotes-authentication/troubleshooting-https-authentication>, <https://www.gitfox.app/support/accounts-remotes-authentication/troubleshooting-ssh-authentication>
- View modes, Quick Actions, custom shortcuts: <https://www.gitfox.app/support/customization-integrations/view-modes>, <https://www.gitfox.app/support/customization-integrations/quick-actions>, <https://www.gitfox.app/support/customization-integrations/custom-keyboard-shortcuts>
- Mac App Store listing and reviews: <https://apps.apple.com/us/app/gitfox/id1475511261>
- Setapp reviews: <https://setapp.com/apps/gitfox/customer-reviews>
- Product Hunt reviews: <https://www.producthunt.com/products/gitfox/reviews>
- GUI clients and hook PATH problems: <https://github.com/typicode/husky/issues/639>, <https://community.atlassian.com/questions/140339/sourcetree-hook-failing-because-paths-don-t-seem-to-be-set-correctly>
- libgit2 licensing discussion: <https://www.github.com/libgit2/libgit2/discussions/6783>
- git docs used for command choices: `git status --porcelain=v2`, `git apply --cached --recount`, `git stash push -- <paths>`, `git commit --cleanup` (local `man` pages, Apple Git 2.54)

## Blind test log

One section per round, newest last. See docs/dev-cycle.md step 5.

### Round 1 (<date>)
| Finding | Severity | Decision | Why / fix |
|---|---|---|---|
