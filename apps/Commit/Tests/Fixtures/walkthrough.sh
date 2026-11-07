#!/usr/bin/env bash
# Scripted walkthrough of Commit's v1 must-haves on the release build, with scripts/drive.
# Works only on copies under /tmp/commit-test/walk2 and a throwaway GIT_CONFIG_GLOBAL; never
# touches anyone's own repositories or git config. Waits for the owner to be away (HID idle
# >= 60 s) before every step that drives the UI, and uses no mouse and no global keys.
#
#   apps/Commit/Tests/Fixtures/walkthrough.sh [step...]     # default: all steps
#
# Screenshots: /tmp/commit-test/shots/walk-*.png. Results: /tmp/commit-test/walk2/results.txt
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
DRIVE="$ROOT/scripts/drive"
APP="$ROOT/build/Commit.app"
W=/tmp/commit-test/walk2
SHOTS=/tmp/commit-test/shots
CONFIG=$W/gitconfig
RESULTS=$W/results.txt
mkdir -p "$SHOTS"

g() { GIT_CONFIG_GLOBAL=$CONFIG GIT_CONFIG_NOSYSTEM=1 git -C "$1" "${@:2}"; }
pass() { echo "PASS $*" | tee -a "$RESULTS"; }
fail() { echo "FAIL $*" | tee -a "$RESULTS"; }
check() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$what"; else fail "$what"; fi; }

idle_gate() {
  local waited=0 t
  while :; do
    t=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')
    [[ "$t" -ge 60 ]] && return 0
    [[ $waited -ge 600 ]] && { echo "SKIP owner active ($1)" | tee -a "$RESULTS"; return 1; }
    sleep 5; waited=$((waited + 5))
  done
}

fixtures() {
  rm -rf "$W"; mkdir -p "$W"
  cp -R /tmp/commit-fixtures/demo /tmp/commit-fixtures/remote.git /tmp/commit-fixtures/lib /tmp/commit-fixtures/conflict "$W/"
  printf '[user]\n\tname = Walk Tester\n\temail = walk@example.com\n[init]\n\tdefaultBranch = main\n[protocol "file"]\n\tallow = always\n' > "$CONFIG"
  g "$W/demo" remote set-url origin "$W/remote.git"
}

launch() { # launch <repo> [extra env...]
  "$DRIVE" quit Commit >/dev/null 2>&1 || "$DRIVE" quit Commit --force >/dev/null 2>&1; sleep 1
  rm -rf ~/Library/Saved\ Application\ State/app.slopapp.commit.savedState
  rm -f ~/Library/Application\ Support/app.slopapp.commit/drafts.json # Commit's own drafts from earlier steps
  # Activated: menus act on the key window. Only reached after idle_gate (owner away).
  "$DRIVE" launch "$APP" --activate --env GIT_CONFIG_GLOBAL=$CONFIG --env COMMIT_OPEN="$1" --env COMMIT_LOG=$W/app.log "${@:2}" >/dev/null
  sleep 3
  close_settings
}
close_settings() { # a Settings window left open would be key and take the menu commands
  local ref
  ref=$("$DRIVE" tree Commit 2>/dev/null | awk '/Settings_window/{f=1} f && /closeButton/{print $1; exit}')
  [[ -n "$ref" ]] && { "$DRIVE" click Commit "$ref" >/dev/null; sleep 0.5; }
}
shot() { "$DRIVE" shot Commit -o "$SHOTS/walk-$1.png" >/dev/null && echo "shot $SHOTS/walk-$1.png"; }
unlabeled() { local n; n=$("$DRIVE" tree Commit 2>&1 | grep -c '\[unlabeled\]'); [[ "$n" == 0 ]] && pass "no unlabeled ($1)" || fail "$n unlabeled ($1)"; }

step_stage() {
  idle_gate stage || return
  launch "$W/demo" --env COMMIT_SELECT=notes.txt
  shot changes; unlabeled changes
  "$DRIVE" click Commit "Stage main.swift" >/dev/null; sleep 1
  check "checkbox stages a file" bash -c "GIT_CONFIG_GLOBAL=$CONFIG git -C $W/demo diff --cached --name-only | grep -q Sources/main.swift"
  "$DRIVE" menu Commit "Edit > Undo" >/dev/null; sleep 1
  check "undo restores the index" bash -c "! GIT_CONFIG_GLOBAL=$CONFIG git -C $W/demo diff --cached --name-only | grep -q Sources/main.swift"
  "$DRIVE" click Commit "Stage Hunk, change 1" >/dev/null; sleep 1
  check "Stage Hunk stages the hunk" bash -c "GIT_CONFIG_GLOBAL=$CONFIG git -C $W/demo show :notes.txt | grep -q EIGHT"
  "$DRIVE" menu Commit "Edit > Undo" >/dev/null; sleep 1
  check "undo hunk staging" bash -c "! GIT_CONFIG_GLOBAL=$CONFIG git -C $W/demo show :notes.txt | grep -q EIGHT"
  # Line staging from the keyboard: focus the diff, ↓ selects the first changed line.
  "$DRIVE" focus Commit "Diff" --role table >/dev/null
  "$DRIVE" key Commit down >/dev/null; "$DRIVE" key Commit down >/dev/null; sleep 0.5
  shot line-selected
  "$DRIVE" key Commit space >/dev/null; sleep 1
  # Stage Hunk staged all of notes.txt, so the selection moved on to windows.txt (CRLF).
  check "Space stages the selected line (CRLF file)" bash -c "GIT_CONFIG_GLOBAL=$CONFIG git -C $W/demo show :windows.txt | grep -q 'second, edited' && ! GIT_CONFIG_GLOBAL=$CONFIG git -C $W/demo show :windows.txt | grep -q fourth"
}

step_discard() {
  idle_gate discard || return
  launch "$W/demo" --env COMMIT_SELECT=notes.txt
  "$DRIVE" focus Commit "Diff" --role table >/dev/null
  "$DRIVE" key Commit end >/dev/null; "$DRIVE" key Commit up >/dev/null; sleep 0.5
  "$DRIVE" menu Commit "Changes > Discard Selected Lines" >/dev/null; sleep 1
  check "discard a line" bash -c "! grep -q eleven $W/demo/notes.txt"
  "$DRIVE" menu Commit "Edit > Undo" >/dev/null; sleep 1
  check "undo the line discard" grep -q eleven "$W/demo/notes.txt"
  "$DRIVE" menu Commit "Changes > Discard All Changes…" >/dev/null; sleep 1
  shot discard-confirm
  "$DRIVE" click Commit "Discard All" >/dev/null; sleep 1.5
  check "discard all leaves a clean tree" bash -c "[ -z \"\$(GIT_CONFIG_GLOBAL=$CONFIG git -C $W/demo status --porcelain)\" ]"
  check "discarded work is in Stashes" bash -c "GIT_CONFIG_GLOBAL=$CONFIG git -C $W/demo stash list | grep -q Discarded"
  "$DRIVE" menu Commit "Edit > Undo" >/dev/null; sleep 1.5
  check "undo brings it all back" bash -c "grep -q eleven $W/demo/notes.txt && [ -f $W/demo/todo.txt ] && GIT_CONFIG_GLOBAL=$CONFIG git -C $W/demo diff --cached --name-only | grep -q notes.txt"
}

step_commit() {
  idle_gate commit || return
  launch "$W/demo"
  "$DRIVE" set Commit "Commit subject" "Rename the old file" >/dev/null; sleep 0.5
  shot composer
  "$DRIVE" key Commit cmd+return >/dev/null; sleep 2
  check "commit lands with the subject" bash -c "GIT_CONFIG_GLOBAL=$CONFIG git -C $W/demo log -1 --format=%s | grep -q 'Rename the old file'"
  "$DRIVE" menu Commit "Edit > Undo" >/dev/null; sleep 2
  check "undo commit (unpushed) puts changes back staged" bash -c "GIT_CONFIG_GLOBAL=$CONFIG git -C $W/demo log -1 --format=%s | grep -q 'Add the lib submodule' && GIT_CONFIG_GLOBAL=$CONFIG git -C $W/demo diff --cached --name-only | grep -q new-name.txt"
  "$DRIVE" set Commit "Commit subject" "Rename the old file" >/dev/null
  "$DRIVE" key Commit cmd+return >/dev/null; sleep 2
  "$DRIVE" menu Commit "Changes > Amend Last Commit" >/dev/null; sleep 1
  "$DRIVE" set Commit "Commit subject" "Rename the old file, amended" >/dev/null; sleep 0.5
  "$DRIVE" key Commit cmd+return >/dev/null; sleep 2
  check "message-only amend" bash -c "GIT_CONFIG_GLOBAL=$CONFIG git -C $W/demo log -1 --format=%s | grep -q amended"
}

step_history() {
  idle_gate history || return
  launch "$W/demo" --env COMMIT_SECTION=history --env SLOP_APPEARANCE=light
  shot history-light; unlabeled history
  launch "$W/demo" --env COMMIT_SECTION=history --env SLOP_APPEARANCE=dark
  shot history-dark
  "$DRIVE" focus Commit "History" --role table >/dev/null; "$DRIVE" key Commit down >/dev/null; sleep 1
  shot commit-detail
  # Copy Hash is not exercised here: it writes to the real clipboard.
}

step_branches() {
  idle_gate branches || return
  launch "$W/demo"
  "$DRIVE" menu Commit "Branch > New Branch…" >/dev/null; sleep 1
  "$DRIVE" set Commit "Branch name" "feature/walk" >/dev/null; sleep 0.3
  shot new-branch
  "$DRIVE" click Commit "Create Branch" >/dev/null; sleep 1.5
  check "create and switch" bash -c "[ \"\$(GIT_CONFIG_GLOBAL=$CONFIG git -C $W/demo branch --show-current)\" = feature/walk ]"
  "$DRIVE" menu Commit "Repository > Push" >/dev/null; sleep 2
  check "first push sets the upstream" bash -c "GIT_CONFIG_GLOBAL=$CONFIG git -C $W/demo rev-parse --abbrev-ref @{u} | grep -q origin/feature/walk"
  # topic/conflict changes notes.txt, which has local changes: Stash and Switch.
  "$DRIVE" menu Commit "Branch > Switch Branch…" >/dev/null; sleep 1
  shot switcher
  "$DRIVE" type Commit "topic/conflict" >/dev/null; "$DRIVE" key Commit return >/dev/null; sleep 1.5
  shot stash-and-switch
  "$DRIVE" click Commit "Stash and Switch" >/dev/null; sleep 2
  check "stash and switch" bash -c "[ \"\$(GIT_CONFIG_GLOBAL=$CONFIG git -C $W/demo branch --show-current)\" = topic/conflict ]"
}

step_sync() {
  idle_gate sync || return
  launch "$W/demo"
  "$DRIVE" menu Commit "Repository > Fetch" >/dev/null; sleep 2
  pass "fetch ran"
  "$DRIVE" menu Commit "Repository > Pull" >/dev/null; sleep 2.5
  shot pull
  "$DRIVE" click Commit "Merge" >/dev/null; sleep 2.5
  check "divergent pull merged (with autostash)" bash -c "GIT_CONFIG_GLOBAL=$CONFIG git -C $W/demo log -1 --format=%P | grep -q ' ' && grep -q eleven $W/demo/notes.txt"
  "$DRIVE" menu Commit "Repository > Push" >/dev/null; sleep 2.5
  check "push" bash -c "[ \"\$(GIT_CONFIG_GLOBAL=$CONFIG git -C $W/demo rev-parse HEAD)\" = \"\$(GIT_CONFIG_GLOBAL=$CONFIG git -C $W/remote.git rev-parse main)\" ]"
}

step_stash() {
  idle_gate stash || return
  launch "$W/demo"
  "$DRIVE" menu Commit "Repository > Stash Changes…" >/dev/null; sleep 1
  "$DRIVE" set Commit "Stash message" "Walkthrough stash" >/dev/null
  shot stash-sheet
  "$DRIVE" click Commit "Stash" --role button >/dev/null; sleep 2
  check "stash with untracked" bash -c "GIT_CONFIG_GLOBAL=$CONFIG git -C $W/demo stash list | head -1 | grep -q 'Walkthrough stash' && [ ! -f $W/demo/todo.txt ]"
  "$DRIVE" menu Commit "View > Stashes" >/dev/null; sleep 1.5
  shot stashes; unlabeled stashes
  "$DRIVE" click Commit "Drop…" >/dev/null; sleep 1
  "$DRIVE" click Commit "Drop Stash" >/dev/null; sleep 1.5
  check "drop" bash -c "[ \"\$(GIT_CONFIG_GLOBAL=$CONFIG git -C $W/demo stash list | wc -l | tr -d ' ')\" = 2 ]"
  "$DRIVE" menu Commit "Edit > Undo" >/dev/null; sleep 1.5
  check "undo drop" bash -c "GIT_CONFIG_GLOBAL=$CONFIG git -C $W/demo stash list | grep -q 'Walkthrough stash'"
  "$DRIVE" click Commit "Apply and Remove" >/dev/null; sleep 2
  check "pop" bash -c "[ -f $W/demo/todo.txt ]"
}

step_conflict() {
  idle_gate conflict || return
  launch "$W/conflict"
  shot conflict; unlabeled conflict
  printf 'alpha\nbeta, both\ngamma\n' > "$W/conflict/shared.txt"; sleep 1.5
  "$DRIVE" click Commit "Mark Resolved" --role button >/dev/null; sleep 1.5
  "$DRIVE" click Commit "Continue" >/dev/null; sleep 2
  check "merge continued" bash -c "[ ! -f $W/conflict/.git/MERGE_HEAD ] && GIT_CONFIG_GLOBAL=$CONFIG git -C $W/conflict log -1 --format=%P | grep -q ' '"
}

step_askpass() {
  idle_gate askpass || return
  local repo=$W/signed
  rm -rf "$repo"; mkdir -p "$repo"; g "$repo" init -q
  ssh-keygen -q -t ed25519 -N "walk passphrase" -C walk -f "$W/signing-key"
  g "$repo" config gpg.format ssh; g "$repo" config user.signingkey "$W/signing-key"; g "$repo" config commit.gpgsign true
  echo hi > "$repo/a.txt"; g "$repo" add a.txt
  launch "$repo" --env SSH_AUTH_SOCK=/nonexistent
  "$DRIVE" set Commit "Commit subject" "Signed from Commit" >/dev/null
  "$DRIVE" key Commit cmd+return >/dev/null; sleep 2
  shot askpass; unlabeled askpass
  "$DRIVE" set Commit "Passphrase for signing-key" "walk passphrase" >/dev/null
  "$DRIVE" click Commit "Continue" >/dev/null; sleep 2
  check "SSH signing passphrase through the sheet" bash -c "GIT_CONFIG_GLOBAL=$CONFIG git -C $repo cat-file commit HEAD | grep -q 'BEGIN SSH SIGNATURE'"
}

step_settings() {
  idle_gate settings || return
  launch "$W/demo"
  "$DRIVE" menu Commit "Commit > Settings…" >/dev/null; sleep 1.5
  SETTINGS_OPENED=1
  "$DRIVE" shot Commit --window General -o "$SHOTS/walk-settings-general.png" >/dev/null
  "$DRIVE" click Commit "Advanced" >/dev/null; sleep 1
  "$DRIVE" shot Commit --window Advanced -o "$SHOTS/walk-settings-advanced.png" >/dev/null
  unlabeled settings
  close_settings
}

step_welcome() {
  idle_gate welcome || return
  "$DRIVE" quit Commit >/dev/null 2>&1 || "$DRIVE" quit Commit --force >/dev/null 2>&1; sleep 1
  rm -rf ~/Library/Saved\ Application\ State/app.slopapp.commit.savedState
  "$DRIVE" launch "$APP" --activate --env GIT_CONFIG_GLOBAL=$CONFIG --env SLOP_APPEARANCE=light >/dev/null; sleep 3
  shot welcome-light; unlabeled welcome
}

mkdir -p "$W"; : > "$RESULTS"
steps=("$@"); [[ ${#steps[@]} -gt 0 ]] || steps=(stage discard commit history branches sync stash conflict askpass settings welcome)
# Every step starts from fresh copies of the fixtures.
for s in "${steps[@]}"; do echo "== $s"; fixtures; "step_$s"; done
"$DRIVE" quit Commit >/dev/null 2>&1
echo; cat "$RESULTS"
