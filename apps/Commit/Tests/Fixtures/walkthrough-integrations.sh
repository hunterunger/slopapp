#!/usr/bin/env bash
# Scripted walkthrough of the clone / conflicts / integrations / blame / remotes / tags round,
# on the release build, with scripts/drive. Works only on copies under /tmp/commit-test/walk3
# with a throwaway GIT_CONFIG_GLOBAL. Launches its own copy with --direct and quits it by pid,
# so a copy of Commit someone is using is never touched. Waits for the owner to be away
# (HID idle >= 60 s) and the screen to be unlocked before every step; no mouse, no global keys.
#
#   apps/Commit/Tests/Fixtures/make-fixtures.sh            # or --out DIR, then COMMIT_FIXTURES=DIR
#   apps/Commit/Tests/Fixtures/walkthrough-integrations.sh [step...]   # default: all steps
#
# Screenshots: /tmp/commit-test/walk3/shots/*.png. Results: /tmp/commit-test/walk3/results.txt
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
DRIVE="$ROOT/scripts/drive"
APP="$ROOT/build/Commit.app"
FIX=${COMMIT_FIXTURES:-/tmp/commit-fixtures}  # where make-fixtures.sh put them (--out)
W=/tmp/commit-test/walk3
SHOTS=$W/shots
CONFIG=$W/gitconfig
RESULTS=$W/results.txt
PID=""

g() { GIT_CONFIG_GLOBAL=$CONFIG GIT_CONFIG_NOSYSTEM=1 git -C "$1" "${@:2}"; }
pass() { echo "PASS $*" | tee -a "$RESULTS"; }
fail() { echo "FAIL $*" | tee -a "$RESULTS"; }
check() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$what"; else fail "$what"; fi; }

gate() { # owner away and screen unlocked
  local waited=0 t
  while :; do
    t=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')
    if [[ "$t" -ge 60 ]] && ! "$DRIVE" windows Finder 2>&1 | grep -q "screen is locked"; then return 0; fi
    [[ $waited -ge 600 ]] && { echo "SKIP owner active or screen locked ($1)" | tee -a "$RESULTS"; return 1; }
    sleep 5; waited=$((waited + 5))
  done
}

fixtures() { # fixtures <name...>: fresh copies
  mkdir -p "$W" "$SHOTS"
  for name in "$@"; do rm -rf "${W:?}/$name"; cp -R "$FIX/$name" "$W/"; done
  printf '[user]\n\tname = Walk Tester\n\temail = walk@example.com\n[init]\n\tdefaultBranch = main\n[protocol "file"]\n\tallow = always\n' > "$CONFIG"
  # A stand-in merge tool: takes their side, as a real tool would after the person saves.
  printf '[mergetool "standin"]\n\tcmd = cp \\"$REMOTE\\" \\"$MERGED\\"\n\ttrustExitCode = true\n[mergetool]\n\tkeepBackup = false\n' >> "$CONFIG"
  [[ -d "$W/integrate" ]] && g "$W/integrate" remote set-url origin "$W/integrate-remote.git"
  return 0
}

launch() { # launch [env...]: our own copy, activated so menus act on its key window
  quit_ours
  local out
  out=$("$DRIVE" launch "$APP" --direct --activate --env GIT_CONFIG_GLOBAL=$CONFIG --env COMMIT_NO_RECENTS=1 \
        --env COMMIT_NO_SHELL_PATH=1 --env COMMIT_LOG=$W/app.log "$@" 2>&1)
  PID=$(echo "$out" | awk '/pid/ {for (i=1;i<=NF;i++) if ($i=="pid") print $(i+1)}' | head -1)
  sleep 3
}
quit_ours() { [[ -n "$PID" ]] && { "$DRIVE" quit "$PID" >/dev/null 2>&1; sleep 1; PID=""; }; return 0; }
shot() { "$DRIVE" shot "$PID" ${2:+--window "$2"} -o "$SHOTS/$1.png" >/dev/null && echo "shot $SHOTS/$1.png"; }
unlabeled() { local n; n=$("$DRIVE" tree "$PID" 2>&1 | grep -c '\[unlabeled\]'); [[ "$n" == 0 ]] && pass "no unlabeled ($1)" || fail "$n unlabeled ($1)"; }
menu() { "$DRIVE" menu "$PID" "$1" >/dev/null; sleep "${2:-1.5}"; }
click() { "$DRIVE" click "$PID" "$@" >/dev/null; sleep 1.5; }

step_conflicts() {
  gate conflicts || return
  fixtures conflicts
  for mode in light dark; do
    launch --env COMMIT_OPEN=$W/conflicts --env COMMIT_SECTION=changes --env COMMIT_SELECT=story.txt --env SLOP_APPEARANCE=$mode
    shot "conflict-resolver-$mode"
  done
  unlabeled resolver
  click "Use ours for conflict 1"
  click "Use theirs for conflict 2"
  shot conflict-chosen
  click "Mark Resolved" --role button
  check "story.txt resolved: ours then theirs, staged" bash -c "GIT_CONFIG_GLOBAL=$CONFIG git -C $W/conflicts show :story.txt | grep -q 'sleepy fox' && GIT_CONFIG_GLOBAL=$CONFIG git -C $W/conflicts show :story.txt | grep -q 'read a book' && ! grep -q '<<<<<<<' $W/conflicts/story.txt"
  menu "Edit > Undo"
  check "undo puts the conflict back (stages 1-3, markers)" bash -c "[[ \$(GIT_CONFIG_GLOBAL=$CONFIG git -C $W/conflicts ls-files -u -- story.txt | wc -l) -eq 3 ]] && grep -q '<<<<<<<' $W/conflicts/story.txt"
  # Whole-file choices on the conflicts without markers.
  launch --env COMMIT_OPEN=$W/conflicts --env COMMIT_SECTION=changes --env COMMIT_SELECT=settings.json
  shot conflict-deleted
  click "Use Ours"
  check "settings.json kept (ours)" bash -c "[[ -z \$(GIT_CONFIG_GLOBAL=$CONFIG git -C $W/conflicts ls-files -u -- settings.json) ]] && grep -q dark $W/conflicts/settings.json"
  launch --env COMMIT_OPEN=$W/conflicts --env COMMIT_SECTION=changes --env COMMIT_SELECT=logo.bin
  click "Use Theirs"
  check "logo.bin takes theirs" bash -c "grep -q theirs $W/conflicts/logo.bin && [[ -z \$(GIT_CONFIG_GLOBAL=$CONFIG git -C $W/conflicts ls-files -u -- logo.bin) ]]"
  # The configured merge tool.
  g "$W/conflicts" config merge.tool standin
  launch --env COMMIT_OPEN=$W/conflicts --env COMMIT_SECTION=changes --env COMMIT_SELECT=story.txt
  click "Open in standin"
  sleep 2
  check "merge tool resolved story.txt" bash -c "[[ -z \$(GIT_CONFIG_GLOBAL=$CONFIG git -C $W/conflicts ls-files -u) ]] && grep -q 'quick brown fox' $W/conflicts/story.txt"
  menu "Repository > Continue Merge" 3
  check "Continue finishes the merge" bash -c "[[ \$(GIT_CONFIG_GLOBAL=$CONFIG git -C $W/conflicts rev-list --parents -n1 HEAD | wc -w) -eq 3 ]]"
  quit_ours
}

step_merge_rebase() {
  gate merge || return
  fixtures integrate integrate-remote.git
  launch --env COMMIT_OPEN=$W/integrate --env COMMIT_SECTION=history --env SLOP_APPEARANCE=light
  local before; before=$(g "$W/integrate" rev-parse HEAD)
  menu "Branch > Merge into main…"
  shot merge-sheet-light; unlabeled merge-sheet
  "$DRIVE" type "$PID" "feature/login" >/dev/null; sleep 1
  "$DRIVE" key "$PID" return >/dev/null; sleep 3
  check "merged feature/login" bash -c "GIT_CONFIG_GLOBAL=$CONFIG git -C $W/integrate log -1 --format=%s | grep -q \"Merge branch 'feature/login'\""
  menu "Edit > Undo" 3
  check "undo merge" bash -c "[[ \$(GIT_CONFIG_GLOBAL=$CONFIG git -C $W/integrate rev-parse HEAD) == $before ]]"
  menu "Branch > Rebase main…"
  "$DRIVE" type "$PID" "fix/readme" >/dev/null; sleep 1
  "$DRIVE" key "$PID" return >/dev/null; sleep 3
  check "rebased main onto fix/readme" bash -c "GIT_CONFIG_GLOBAL=$CONFIG git -C $W/integrate merge-base --is-ancestor fix/readme HEAD"
  menu "Edit > Undo" 3
  check "undo rebase" bash -c "[[ \$(GIT_CONFIG_GLOBAL=$CONFIG git -C $W/integrate rev-parse HEAD) == $before ]]"
  # A merge that conflicts lands in Changes with the resolver.
  menu "Branch > Merge into main…"
  "$DRIVE" type "$PID" "clash" >/dev/null; sleep 1
  "$DRIVE" key "$PID" return >/dev/null; sleep 3
  shot merge-conflict
  check "conflicting merge stops in progress" test -f "$W/integrate/.git/MERGE_HEAD"
  menu "Repository > Abort Merge…" 1
  "$DRIVE" click "$PID" "Abort Merge" --role button >/dev/null; sleep 2
  check "abort" test ! -f "$W/integrate/.git/MERGE_HEAD"
  quit_ours
}

step_cherry_pick() {
  gate cherry || return
  fixtures integrate integrate-remote.git
  launch --env COMMIT_OPEN=$W/integrate --env COMMIT_SECTION=history
  click "fix/readme" # its history; the first row (its tip) is selected
  menu "Branch > Cherry-pick onto main" 3
  check "cherry-picked the README fix onto main" bash -c "GIT_CONFIG_GLOBAL=$CONFIG git -C $W/integrate log -1 --format=%s main | grep -q 'Fix the README wording'"
  menu "Edit > Undo" 3
  check "undo cherry-pick" bash -c "GIT_CONFIG_GLOBAL=$CONFIG git -C $W/integrate log -1 --format=%s main | grep -q 'Add a colr setting'"
  quit_ours
}

step_edit_history() {
  gate history || return
  fixtures integrate integrate-remote.git
  for mode in light dark; do
    launch --env COMMIT_OPEN=$W/integrate --env COMMIT_SECTION=history --env SLOP_APPEARANCE=$mode
    menu "Branch > Edit Unpushed Commits…" 2
    shot "rebase-editor-$mode"
  done
  unlabeled rebase-editor
  # The newest commit is selected: reword it; the one above becomes a fixup.
  "$DRIVE" key "$PID" r >/dev/null; sleep 1
  "$DRIVE" set "$PID" "Commit message" "Add a color setting" >/dev/null; sleep 1
  "$DRIVE" key "$PID" up >/dev/null; "$DRIVE" key "$PID" f >/dev/null; sleep 1
  shot rebase-editor-edited
  click "Rewrite History"
  sleep 3
  check "fixup folded, reword applied" bash -c "[[ \"\$(GIT_CONFIG_GLOBAL=$CONFIG git -C $W/integrate log --format=%s -3 | tr '\n' '|')\" == 'Add a color setting|Add notes|Use the fancy mode|' ]]"
  menu "Edit > Undo" 3
  check "undo history edit" bash -c "GIT_CONFIG_GLOBAL=$CONFIG git -C $W/integrate log -1 --format=%s | grep -q 'Add a colr setting'"
  quit_ours
}

step_tags_remotes() {
  gate tags || return
  fixtures integrate integrate-remote.git
  launch --env COMMIT_OPEN=$W/integrate --env COMMIT_SECTION=history
  menu "Branch > New Tag…"
  shot tag-sheet; unlabeled tag-sheet
  "$DRIVE" type "$PID" "v1.0" >/dev/null
  "$DRIVE" set "$PID" "Tag message" "Release one" >/dev/null; sleep 1
  click "Create Tag"
  check "annotated tag created" bash -c "[[ \$(GIT_CONFIG_GLOBAL=$CONFIG git -C $W/integrate cat-file -t v1.0) == tag ]]"
  menu "Repository > Push Tags" 3
  check "tags pushed" bash -c "GIT_CONFIG_GLOBAL=$CONFIG git -C $W/integrate-remote.git tag -l | grep -q v1.0"
  menu "Repository > Remotes…"
  shot remotes-sheet; unlabeled remotes-sheet
  click "Add…"
  "$DRIVE" set "$PID" "Name" "backup" >/dev/null
  "$DRIVE" set "$PID" "URL" "$W/backup.git" >/dev/null; sleep 1
  click "Add Remote"
  check "remote added" bash -c "GIT_CONFIG_GLOBAL=$CONFIG git -C $W/integrate remote | grep -q backup"
  click "Done"
  quit_ours
}

step_file_history() {
  gate blame || return
  fixtures integrate integrate-remote.git
  for mode in light dark; do
    launch --env COMMIT_OPEN=$W/integrate --env COMMIT_SECTION=history --env SLOP_APPEARANCE=$mode
    menu "File > Show File History" 3
    shot "file-history-$mode" "History of app.txt"
    menu "View > Blame of Version" 2
    shot "blame-$mode" "History of app.txt"
  done
  unlabeled file-history
  menu "View > Older Version" 2
  shot blame-older "History of app.txt"
  pass "file history and blame shown (see shots)"
  quit_ours
}

step_clone() {
  gate clone || return
  fixtures integrate integrate-remote.git
  rm -rf "$W/clones"; mkdir -p "$W/clones"
  launch --env COMMIT_SHOW_CLONE=1 --env COMMIT_CLONE_PARENT=$W/clones --env SLOP_APPEARANCE=light
  "$DRIVE" set "$PID" "Address" "$W/integrate-remote.git" >/dev/null; sleep 1
  shot clone-light "Clone Repository"; unlabeled clone
  click "Clone"; sleep 4
  check "cloned into the chosen folder" test -d "$W/clones/integrate-remote/.git"
  "$DRIVE" set "$PID" "Address" "$W/missing.git" >/dev/null 2>&1
  quit_ours
  launch --env COMMIT_SHOW_CLONE=1 --env COMMIT_CLONE_PARENT=$W/clones --env SLOP_APPEARANCE=dark
  "$DRIVE" set "$PID" "Address" "$W/missing.git" >/dev/null; sleep 1
  click "Clone"; sleep 3
  shot clone-error-dark "Clone Repository"
  check "missing repository explained, nothing left behind" test ! -e "$W/clones/missing"
  quit_ours
}

steps=("$@")
[[ ${#steps[@]} -eq 0 ]] && steps=(conflicts merge_rebase cherry_pick edit_history tags_remotes file_history clone)
mkdir -p "$W" "$SHOTS"
for s in "${steps[@]}"; do "step_$s"; done
quit_ours
echo "results in $RESULTS"
