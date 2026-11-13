#!/usr/bin/env bash
# Builds Commit's fixture repositories, deterministically, with a demo identity and no
# global or system git config (so nobody's own config plays a part).
#
#   apps/Commit/Tests/Fixtures/make-fixtures.sh [--big] [--out DIR]
#
# Output (default /tmp/commit-fixtures, never committed):
#   demo       the daily loop: branches, a merge, tags, 2 stashes, a submodule, ahead 1 /
#              behind 1 against remote.git, partly staged + renamed + untracked + CRLF files
#   remote.git demo's bare remote
#   conflict   a merge stopped on a content conflict
#   unborn     no commits yet, one staged file
#   detached   HEAD detached at the first commit
#   bare.git   a bare repository (Commit refuses it)
#   integrate  merge / rebase / cherry-pick / history editing: main with 4 unpushed commits
#              (squash, fixup and reword candidates), feature/login (2 commits), fix/readme
#              (1 commit to cherry-pick), clash (conflicts with main), tags, app.txt renamed
#              from old-app.txt (file history and blame); integrate-remote.git is its remote
#   conflicts  a merge stopped on three conflicts: story.txt (two conflicts in one file),
#              settings.json (deleted by them, changed by us), logo.bin (binary)
#   wide       50,000 tracked files + a 3,000-file untracked node_modules
#   big        (--big) 100,000 commits, ~8,000 merges, ~7,000 branches, plus huge.txt
#              (200,000 lines) with a scattered 28,572-line edit in the working tree
set -euo pipefail
OUT=/tmp/commit-fixtures
BIG=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --big) BIG=1 ;;
    --out) OUT="$2"; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
HERE="$(cd "$(dirname "$0")" && pwd)"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME="Demo Person" GIT_AUTHOR_EMAIL="demo@example.com"
export GIT_COMMITTER_NAME="Demo Person" GIT_COMMITTER_EMAIL="demo@example.com"
CLOCK=1767607200 # 2026-01-05 10:00 UTC
tick() { # tick <minutes>: move the fake clock forward
  CLOCK=$(( CLOCK + $1 * 60 ))
  export GIT_AUTHOR_DATE="@$CLOCK +0000" GIT_COMMITTER_DATE="@$CLOCK +0000"
}
tick 0
g() { git -c init.defaultBranch=main -c user.name="Demo Person" -c user.email=demo@example.com -c protocol.file.allow=always "$@"; }

mkdir -p "$OUT"
rm -rf "$OUT/demo" "$OUT/remote.git" "$OUT/lib" "$OUT/conflict" "$OUT/unborn" "$OUT/detached" "$OUT/bare.git" \
  "$OUT/integrate" "$OUT/integrate-remote.git" "$OUT/conflicts"

# --- lib (submodule source) -------------------------------------------------------------
g init -q "$OUT/lib"
( cd "$OUT/lib" && echo "shared code" > lib.txt && g add . && g commit -qm "Add lib" )

# --- demo + remote ------------------------------------------------------------------------
g init -q "$OUT/demo"
cd "$OUT/demo"
printf '# Demo\n\nA small project for trying Commit.\n' > README.md
mkdir -p Sources
printf 'func greet() {\n    print("Hello")\n}\n\nfunc farewell() {\n    print("Bye")\n}\n' > Sources/main.swift
printf 'one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\n' > notes.txt
printf 'first\r\nsecond\r\nthird\r\n' > windows.txt
printf 'old name\n' > old-name.txt
g add . && g commit -qm "Start the demo project"
tick 30
g tag -a v0.1 -m "First tag"
printf 'func greet() {\n    print("Hello, world")\n}\n\nfunc farewell() {\n    print("Bye")\n}\n' > Sources/main.swift
g commit -qam "Say hello to the world"
tick 30
g switch -q -c feature/search
printf 'func search(_ q: String) -> [String] {\n    []\n}\n' > Sources/search.swift
g add . && g commit -qm "Add a search stub"
tick 20
printf 'func search(_ q: String) -> [String] {\n    [q]\n}\n' > Sources/search.swift
g commit -qam "Return the query for now"
g switch -q main
tick 20
echo "Run it with swift run." >> README.md
g commit -qam "Explain how to run it"
tick 20
g merge -q --no-ff feature/search -m "Merge branch 'feature/search'"
g tag v0.2
g clone -q --bare "$OUT/demo" "$OUT/remote.git"
g remote add origin "$OUT/remote.git"
g fetch -q origin
g branch -q -u origin/main main
g branch -q -u origin/feature/search feature/search
g switch -q -c topic/conflict
tick 5
echo "topic change" >> notes.txt && g commit -qam "Change notes on a topic branch"
g switch -q main
g submodule -q add "$OUT/lib" lib 2>/dev/null
tick 10
g commit -qm "Add the lib submodule"
# behind 1: a commit on the remote that we don't have.
rm -rf "$OUT/.tmpclone"; g clone -q "$OUT/remote.git" "$OUT/.tmpclone"
( cd "$OUT/.tmpclone" && tick 5 && echo "Contributors: Demo" >> README.md && g commit -qam "Credit contributors" && g push -q origin main )
rm -rf "$OUT/.tmpclone"
g fetch -q origin
# Two stashes.
echo "scratch" > scratch.txt && g stash push -q -u -m "WIP: scratch file"
echo "tweak" >> README.md && g stash push -q -m "WIP: readme tweak"
# Working copy: partly staged, renamed, untracked, CRLF.
printf 'one\nTWO\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\n' > notes.txt
g add notes.txt
printf 'one\nTWO\nthree\nfour\nfive\nsix\nseven\nEIGHT\nnine\nten\neleven\n' > notes.txt
g mv old-name.txt new-name.txt
printf 'first\r\nsecond, edited\r\nthird\r\nfourth\r\n' > windows.txt
printf 'func greet() {\n    print("Hello, world")\n    log("greeted")\n}\n\nfunc farewell() {\n    print("Goodbye")\n}\n' > Sources/main.swift
echo "A brand new file" > todo.txt
cd - >/dev/null

# --- conflict -----------------------------------------------------------------------------
g init -q "$OUT/conflict"
cd "$OUT/conflict"
printf 'alpha\nbeta\ngamma\n' > shared.txt && g add . && g commit -qm "Base"
g switch -q -c theirs && printf 'alpha\nBETA from theirs\ngamma\n' > shared.txt && g commit -qam "Theirs"
g switch -q main && printf 'alpha\nbeta from ours\ngamma\n' > shared.txt && g commit -qam "Ours"
g merge -q theirs -m "Merge theirs" >/dev/null 2>&1 || true
cd - >/dev/null

# --- integrate ----------------------------------------------------------------------------
g init -q "$OUT/integrate"
cd "$OUT/integrate"
printf '# Integrate\n\nA project for merging, rebasing and editing history.\n' > README.md
printf 'name = "demo"\nversion = 1\nmode = "plain"\n' > old-app.txt
g add . && g commit -qm "Start the project"
tick 30
g tag -a v0.1 -m "First release"
printf 'name = "demo"\nversion = 2\nmode = "plain"\n' > old-app.txt && g commit -qam "Bump the version"
tick 30
g mv old-app.txt app.txt && g commit -qm "Rename the config to app.txt"
g clone -q --bare "$OUT/integrate" "$OUT/integrate-remote.git"
g remote add origin "$OUT/integrate-remote.git" && g fetch -q origin && g branch -q -u origin/main main
g switch -q -c feature/login
tick 10; printf 'login screen\n' > login.txt && g add . && g commit -qm "Add a login screen"
tick 10; printf 'login screen\nremember me\n' > login.txt && g commit -qam "Remember the last user"
g switch -q main
g switch -q -c fix/readme
tick 10; printf '# Integrate\n\nA small project for merging, rebasing and editing history.\n' > README.md && g commit -qam "Fix the README wording"
g switch -q main
g switch -q -c clash
tick 10; printf 'name = "demo"\nversion = 3\nmode = "clashing"\n' > app.txt && g commit -qam "Clash: version 3"
g switch -q main
tick 20; printf 'name = "demo"\nversion = 2\nmode = "fancy"\n' > app.txt && g commit -qam "Use the fancy mode"
tick 5; printf 'notes\n' > notes.txt && g add . && g commit -qm "Add notes"
tick 5; printf 'notes\nmore notes\n' > notes.txt && g commit -qam "fixup notes"
tick 5; printf 'name = "demo"\nversion = 2\nmode = "fancy"\ncolor = "blue"\n' > app.txt && g commit -qam "Add a colr setting"
g tag v0.2-lightweight
cd - >/dev/null

# --- conflicts ----------------------------------------------------------------------------
g init -q "$OUT/conflicts"
cd "$OUT/conflicts"
printf 'Once upon a time\nthere was a fox.\nIt lived in a wood\nnear a river.\nEvery morning\nit went for a walk\nand in the evening\nit slept by the fire.\nThe end.\n' > story.txt
printf '{ "theme": "light" }\n' > settings.json
printf 'LOGO\0v1' > logo.bin
g add . && g commit -qm "Base story"
g switch -q -c theirs
printf 'Once upon a time\nthere was a quick brown fox.\nIt lived in a wood\nnear a river.\nEvery morning\nit went for a walk\nand in the evening\nit read a book.\nThe end.\n' > story.txt
g rm -q settings.json
printf 'LOGO\0theirs' > logo.bin
g commit -qam "Their edits"
g switch -q main
printf 'Once upon a time\nthere was a sleepy fox.\nIt lived in a wood\nnear a river.\nEvery morning\nit went for a walk\nand in the evening\nit watched the stars.\nThe end.\n' > story.txt
printf '{ "theme": "dark" }\n' > settings.json
printf 'LOGO\0ours' > logo.bin
g commit -qam "Our edits"
g merge -q theirs -m "Merge theirs" >/dev/null 2>&1 || true
cd - >/dev/null

# --- unborn, detached, bare ---------------------------------------------------------------
g init -q "$OUT/unborn"
( cd "$OUT/unborn" && echo "first file" > first.txt && g add first.txt && echo "not yet" > later.txt )
g init -q "$OUT/detached"
( cd "$OUT/detached" && echo 1 > a.txt && g add . && g commit -qm "One" && echo 2 > a.txt && g commit -qam "Two" && g switch -q --detach HEAD~1 )
g init -q --bare "$OUT/bare.git"

# --- wide ---------------------------------------------------------------------------------
if [[ ! -d "$OUT/wide/.git" ]]; then
  rm -rf "$OUT/wide"
  g init -q "$OUT/wide"
  python3 -I - "$OUT/wide" <<'PY'
import os, sys
root = sys.argv[1]
for d in range(500):
    folder = os.path.join(root, "src", f"module{d:03}")
    os.makedirs(folder, exist_ok=True)
    for f in range(100):
        with open(os.path.join(folder, f"file{f:03}.txt"), "w") as fh:
            fh.write(f"module {d} file {f}\n")
PY
  ( cd "$OUT/wide" && g add -A && g commit -qm "50,000 files" )
  python3 -I - "$OUT/wide" <<'PY'
import os, sys
root = os.path.join(sys.argv[1], "node_modules")
for p in range(30):
    folder = os.path.join(root, f"pkg{p:02}")
    os.makedirs(folder, exist_ok=True)
    for f in range(100):
        with open(os.path.join(folder, f"index{f:03}.js"), "w") as fh:
            fh.write("module.exports = {}\n")
PY
  echo "edited" >> "$OUT/wide/src/module000/file000.txt"
fi

# --- big ----------------------------------------------------------------------------------
if [[ $BIG -eq 1 && ! -f "$OUT/big/.git/objects/info/commit-graph" ]]; then
  rm -rf "$OUT/big"
  g init -q "$OUT/big"
  python3 -I "$HERE/big-history.py" | (cd "$OUT/big" && g fast-import --quiet)
  ( cd "$OUT/big" && g reset -q --hard main && g commit-graph write --reachable --no-progress )
  python3 -I - "$OUT/big/huge.txt" <<'PY'
import sys
path = sys.argv[1]
lines = open(path).read().split("\n")
for i in range(0, len(lines) - 1, 7):
    lines[i] = lines[i] + " (edited)"
open(path, "w").write("\n".join(lines))
PY
fi
echo "fixtures in $OUT"
