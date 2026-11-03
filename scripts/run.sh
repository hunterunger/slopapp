#!/usr/bin/env bash
# Builds a debug bundle and opens it, replacing any running copy.
#
#   scripts/run.sh <Name> [--env KEY=VALUE ...]
set -euo pipefail
source "$(dirname "$0")/lib.sh"

NAME="${1:-}"; [[ -n "$NAME" ]] || die "usage: scripts/run.sh <Name> [--env KEY=VALUE ...]"
shift
"$ROOT/scripts/bundle.sh" "$NAME" --debug
pkill -x "$NAME" 2>/dev/null && sleep 0.5 || true
open "$BUILD_DIR/$NAME.app" "$@"
ok "opened $NAME.app"
