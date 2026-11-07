# Commit

A calm Git client.

Part of [Slopapp](../../README.md), a free, open-source collection of Mac apps.
An open alternative to Gitfox.

**Status:** alpha

## What it does

The daily loop, without memorising `git add -p`:

- **Changes**: Staged and Changes lists that refresh on their own (file events, window
  activation, ⌘R). Tick a file or press Space to stage it. Stage All / Unstage All.
- **Diff**: unified, with old and new line numbers, hunk headers and "N unchanged lines"
  between hunks. ⌘↓ / ⌘↑ jump between changes; ⌘= / ⌘− change the context. Binary files show
  their sizes; huge diffs ask before showing everything; a slow `diff.algorithm` is stopped
  after 2 s and redone with Myers.
- **Hunks and lines**: click a changed line to select it (shift-click, ⌘-click or drag for
  more), then Space, or the hunk's **Stage 2 Lines** button. Works on CRLF files, files without
  a final newline and non-UTF-8 text: patches are built from git's exact bytes.
- **Discard with undo**: lines, hunks, files or everything. ⌘Z puts it back. File discards
  are also kept in Stashes.
- **Commit composer**, docked under the file list, never modal: subject counter (guide at
  50, warning past 72), a 72-column guide in the body, a draft saved per repository, ⌘Return
  to commit, ⌥⌘Return to commit and push, Amend (message-only too, with a warning when the
  commit is already pushed), Undo Commit while it's unpushed. Hooks and signing run because
  git runs them; failures show git's output.
- **History** with a branch graph, ref labels, an "Uncommitted Changes" row, commit details
  with files and diff, Copy Hash (⌘C).
- **Branches**: list with the current one marked and ↑↓ counts, filter, switch (Return or
  double-click) with **Stash and Switch** when local changes are in the way, check out remote
  branches as tracking branches, create from HEAD or any commit, delete (undoable).
- **Fetch, Pull, Push** for the current branch with progress and Cancel. The first push sets
  up tracking. Divergent pulls ask Merge or Rebase. Rejected pushes and sign-in problems are
  explained in a sentence.
- **Stash** with a message and untracked files; apply, apply and remove, drop (undoable).
- **Merge, rebase, cherry-pick and revert in progress**: a banner with Continue / Abort,
  conflicted files in their own section, Mark Resolved.
- **Passwords and passphrases**: when git or ssh needs to ask (an HTTPS token, an SSH key
  passphrase, an unknown host key), Commit asks in a sheet on the repository's window. Nothing
  typed is stored by Commit; git's credential helper or ssh-agent keeps what it keeps.

## How it works

Commit runs **your own `git`** (Settings › Advanced; automatically `/usr/bin/git` when
Apple's command line tools are installed, else Homebrew's), so your config, hooks, credential
helper, SSH setup and signing behave exactly as in Terminal. It reads your login shell's PATH
once at launch so hooks, git-lfs and gpg find their tools (can be turned off). Reads never
take `index.lock` (`GIT_OPTIONAL_LOCKS=0`) and git never waits on a terminal prompt
(`GIT_TERMINAL_PROMPT=0`; prompts go to the askpass sheet instead).

It isn't sandboxed (hooks, signing and helpers need the real environment) and needs no
special permissions. macOS may ask once before it can read repositories in Documents,
Desktop or iCloud Drive; that's the system's own prompt.

**Network:** Commit itself makes no network connections. Git talks to your remotes only when
you fetch, pull or push, or if you turn on **Fetch automatically** in Settings (off by default).

## Keyboard

| Action | Shortcut |
|---|---|
| Open repository | ⌘O |
| Changes / History / Stashes | ⌘1 / ⌘2 / ⌘3 |
| Stage or unstage the selection | Space (in the file list or diff), ⇧⌘Space |
| Stage All / Unstage All | ⌥⌘A / ⌥⇧⌘A |
| Discard selection / Discard all | ⌘⌫ / ⌥⇧⌘⌫ |
| Next / previous change | ⌘↓ / ⌘↑ |
| More / less context | ⌘= / ⌘− |
| Focus the commit message | ⌘L |
| Commit / Commit and Push | ⌘Return / ⌥⌘Return |
| Amend last commit | ⇧⌘A |
| New branch / switch branch | ⇧⌘N / ⇧⌘B |
| Fetch / Pull / Push | ⌥⌘F / ⌥⌘P / ⌥⌘U |
| Stash changes | ⌥⌘S |
| Refresh | ⌘R |
| Undo | ⌘Z |

## Not there yet

Side-by-side diff, clone, interactive rebase, a conflict-resolution editor, blame, file
history, reflog, tags beyond the list, remote management, command palette, image diffs,
syntax colouring, hosting accounts. See `docs/research/commit.md` for what's planned and why.

## Develop

```sh
scripts/test.sh Commit     # unit and integration tests (real git in /tmp/commit-test)
scripts/run.sh Commit      # build a debug .app and open it
scripts/check.sh Commit    # the full gate: tests, release bundle, launch smoke test
apps/Commit/Tests/Fixtures/make-fixtures.sh --big   # demo, conflict, wide, big… in /tmp/commit-fixtures
swift test --package-path apps/Commit -c release -Xswiftc -enable-testing --filter PerformanceTests
```

Test hooks (environment variables): `COMMIT_OPEN=/path/repo` opens a repository at launch,
`COMMIT_LOG=/path/file.log` logs timings, `COMMIT_NO_SHELL_PATH=1` skips the login shell,
`COMMIT_RESET_RECENTS=1` starts with no recents. Use git's own `GIT_CONFIG_GLOBAL=/tmp/…` to
keep a test run away from your real global config.

Layout:

- `Sources/CommitCore`: the engine. `GitRunner` (posix_spawn in its own process group,
  concurrent pipes, cancel, timeout) behind a protocol; porcelain v2 status, diff, log, refs
  and stash parsers; `PatchBuilder` (line and hunk patches from raw bytes); `GraphLayout`
  (lanes, flat storage); `RefreshScheduler` + `FileWatcher` (FSEvents, coalesced);
  `Repository` (every git operation); askpass client and server; error explanations.
- `Sources/Commit`: SwiftUI app. `RepoModel` per window; the diff and history are
  `NSTableView`s for virtualised rows and native selection. `main.swift` doubles as the
  askpass helper when git runs it.

Design follows [`docs/design-system.md`](../../docs/design-system.md). Shared pieces
(Settings, About, DropZone, HUD, Hairline, readable colours) come from SlopKit.
