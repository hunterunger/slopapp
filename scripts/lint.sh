#!/usr/bin/env bash
# Source checks for the detail rules in docs/design-system.md §4 that grep can catch.
#
#   scripts/lint.sh <Name>
#
# Fails on:
#   - corner radii written as numbers (use SlopKit `Radius.*`, `Radius.nested(in:padding:)`,
#     `Radius.iconTile(side:)` or `windowConcentric`)
#   - hardcoded colours (`Color(red:`, `NSColor(red:`, `NSColor(calibratedRed:`, hex helpers)
# Warns on: spacing literals above 2 pt (use `Spacing.*`).
# Opt a line out with a trailing `// lint:allow <reason>` (e.g. a hairline nudge, an icon
# drawn to the brand spec).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

NAME="${1:-}"; [[ -n "$NAME" ]] || die "usage: scripts/lint.sh <Name>"
DIR="$(app_dir "$NAME")/Sources"
failed=0

check() { # check <fail|warn> <message> <regex>
  local level="$1" message="$2" regex="$3" hits
  hits="$(grep -rnE --include='*.swift' "$regex" "$DIR" | grep -v 'lint:allow' || true)"
  [[ -z "$hits" ]] && return 0
  local count; count="$(printf '%s\n' "$hits" | wc -l | tr -d ' ')"
  if [[ "$level" == "fail" ]]; then
    echo "${RED}lint:${RESET} $NAME: $count $message"; failed=1
  else
    echo "${DIM}lint (warning): $NAME: $count $message${RESET}"
  fi
  printf '%s\n' "$hits" | sed "s|^$ROOT/||" | head -20 | sed 's/^/    /'
}

check fail "corner radius literal(s); use Radius.* / Radius.nested / windowConcentric" \
  'cornerRadius: *[1-9][0-9.]*|cornerRadius = *[1-9][0-9.]*|\.cornerRadius\([1-9]'
check fail "hardcoded colour(s); use semantic colours or the brand palette in SlopKit" \
  'Color\(red:|NSColor\((calibrated|device|s)?[rR]ed:|Color\(hex|NSColor\(hex|#colorLiteral'
check warn "spacing literal(s) above 2 pt; use Spacing.*" \
  '\.padding\((\.[a-zA-Z]+, *|\[[^]]*\], *)?([3-9]|[1-9][0-9]+)(\.[0-9]+)?\)|spacing: *([3-9]|[1-9][0-9]+)(\.[0-9]+)?[,)]'

[[ $failed -eq 0 ]] && ok "$NAME lint" && exit 0
exit 1
