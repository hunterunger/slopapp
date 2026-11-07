#!/usr/bin/env bash
# The full gate. CI runs this; run it before calling an app done.
#
#   scripts/check.sh            # SlopKit + every app
#   scripts/check.sh Awake      # just these apps (plus SlopKit tests)
#   scripts/check.sh --perf     # also run scripts/perf.sh (needs Accessibility; not in CI)
#
# Per app: source lint (design-system detail rules), icon style check (apps with an Icon.py,
# brand/ICONS.md), unit tests, release bundle (universal, signed, zipped, real SDK stamp),
# launch smoke test.
# Then regenerates the website catalog. Exits non-zero if anything failed.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

PERF=0
ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--perf" ]]; then PERF=1; else ARGS+=("$arg"); fi
done

if [[ ${#ARGS[@]} -gt 0 ]]; then
  APPS=("${ARGS[@]}")
else
  APPS=()
  while IFS= read -r app; do APPS+=("$app"); done < <(all_apps)
fi

results=()
failures=0
record() { # record <label> <command...>
  local label="$1"; shift
  if "$@"; then
    results+=("${GREEN}PASS${RESET}  $label")
  else
    results+=("${RED}FAIL${RESET}  $label")
    failures=$((failures + 1))
  fi
}

say "SlopKit"
record "SlopKit  test" "$ROOT/scripts/test.sh" SlopKit

for app in "${APPS[@]}"; do
  say "$app"
  record "$app  lint"   "$ROOT/scripts/lint.sh" "$app"
  if [[ -f "$APPS_DIR/$app/Icon.py" ]]; then
    record "$app  icon"   python3 "$ROOT/scripts/icons/herbarium.py" check "$app"
  fi
  record "$app  test"   "$ROOT/scripts/test.sh" "$app"
  record "$app  bundle" "$ROOT/scripts/bundle.sh" "$app"
  if [[ -x "$BUILD_DIR/$app.app/Contents/MacOS/$app" ]]; then
    record "$app  smoke" "$ROOT/scripts/smoke.sh" "$app" --no-bundle
    if [[ $PERF -eq 1 ]]; then
      record "$app  perf" "$ROOT/scripts/perf.sh" "$app" --no-bundle
    fi
  else
    results+=("${RED}SKIP${RESET}  $app  smoke (no bundle)")
  fi
done

say "Catalog"
if command -v node >/dev/null 2>&1; then
  record "catalog" node "$ROOT/scripts/catalog.mjs"
else
  results+=("${DIM}SKIP  catalog (node not installed)${RESET}")
fi

echo
echo "${BOLD}Summary${RESET}"
printf '  %s\n' "${results[@]}"
if [[ $failures -gt 0 ]]; then
  die "$failures check(s) failed"
fi
ok "all checks passed"
