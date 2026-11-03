#!/usr/bin/env bash
# Runs unit tests (Swift Testing) for SlopKit and apps.
#
#   scripts/test.sh            # SlopKit + every app
#   scripts/test.sh Awake Tally
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [[ $# -gt 0 ]]; then
  TARGETS=("$@")
else
  TARGETS=(SlopKit)
  while IFS= read -r app; do TARGETS+=("$app"); done < <(all_apps)
fi

failed=()
for name in "${TARGETS[@]}"; do
  dir="$APPS_DIR/$name"
  [[ -f "$dir/Package.swift" ]] || die "no package at apps/$name"
  if run_logged "$LOG_DIR/$name-test.log" swift test --package-path "$dir"; then
    summary="$(grep -Eo 'Test run with [0-9]+ tests?( in [0-9]+ suites?)? passed' "$LOG_DIR/$name-test.log" | tail -1 || true)"
    ok "$name tests ${DIM}${summary:-passed}${RESET}"
  else
    failed+=("$name")
  fi
done

[[ ${#failed[@]} -eq 0 ]] || die "tests failed: ${failed[*]}"
