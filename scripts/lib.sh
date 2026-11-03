# Shared helpers for Slopapp scripts. Source it: `source "$(dirname "$0")/lib.sh"`.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPS_DIR="$ROOT/apps"
BUILD_DIR="$ROOT/build"
LOG_DIR="$BUILD_DIR/logs"

if [[ -t 1 ]]; then
  BOLD=$'\e[1m'; RED=$'\e[31m'; GREEN=$'\e[32m'; DIM=$'\e[2m'; RESET=$'\e[0m'
else
  BOLD=""; RED=""; GREEN=""; DIM=""; RESET=""
fi

say()  { echo "${BOLD}==>${RESET} $*"; }
ok()   { echo "${GREEN}✓${RESET} $*"; }
die()  { echo "${RED}error:${RESET} $*" >&2; exit 1; }

# json_get <file> <jq-path>   e.g. json_get app.json .name
# Uses jq when available, python3 otherwise. Prints "" for null/missing.
json_get() {
  local file="$1" path="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -r "$path // empty" "$file"
  else
    python3 - "$file" "$path" <<'PY'
import json, sys
value = json.load(open(sys.argv[1]))
for key in sys.argv[2].lstrip(".").split("."):
    value = value.get(key) if isinstance(value, dict) else None
if value is None: print("")
elif isinstance(value, bool): print(str(value).lower())
elif isinstance(value, (dict, list)): print(json.dumps(value))
else: print(value)
PY
  fi
}

# All app names (directories under apps/ that have an app.json), sorted.
all_apps() {
  local manifest
  for manifest in "$APPS_DIR"/*/app.json; do
    [[ -f "$manifest" ]] && basename "$(dirname "$manifest")"
  done
}

# app_dir <Name> -> path, or dies with a helpful message.
app_dir() {
  local dir="$APPS_DIR/$1"
  [[ -f "$dir/app.json" ]] || die "no app named '$1' (expected $dir/app.json). Apps: $(all_apps | tr '\n' ' ')"
  echo "$dir"
}

# run_logged <log-file> <command...>: runs quietly, prints the log tail on failure.
run_logged() {
  local log="$1"; shift
  mkdir -p "$(dirname "$log")"
  if "$@" >"$log" 2>&1; then
    return 0
  else
    local status=$?
    echo "${RED}failed:${RESET} $* ${DIM}(full log: ${log#$ROOT/})${RESET}" >&2
    tail -n 40 "$log" >&2
    return $status
  fi
}
