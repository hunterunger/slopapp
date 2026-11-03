#!/usr/bin/env bash
# Launch test: the bundled app must start and stay running.
#
#   scripts/smoke.sh <Name> [--no-bundle] [--seconds N]
#
# Bundles (unless --no-bundle), runs build/<Name>.app's binary, checks it's still
# alive after N seconds (default 3), then quits it. Fails on crash or early exit.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

NAME="${1:-}"; [[ -n "$NAME" ]] || die "usage: scripts/smoke.sh <Name> [--no-bundle] [--seconds N]"
shift
BUNDLE=1; SECONDS_ALIVE=3
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-bundle) BUNDLE=0 ;;
    --seconds) SECONDS_ALIVE="$2"; shift ;;
    *) die "unknown option $1" ;;
  esac
  shift
done

app_dir "$NAME" >/dev/null
[[ $BUNDLE -eq 1 ]] && "$ROOT/scripts/bundle.sh" "$NAME" --debug
BINARY="$BUILD_DIR/$NAME.app/Contents/MacOS/$NAME"
[[ -x "$BINARY" ]] || die "$BINARY not found; run scripts/bundle.sh $NAME first"

LOG="$LOG_DIR/$NAME-smoke.log"
mkdir -p "$LOG_DIR"
SLOPAPP_SMOKE_TEST=1 "$BINARY" >"$LOG" 2>&1 &
PID=$!
sleep "$SECONDS_ALIVE"

if kill -0 "$PID" 2>/dev/null; then
  kill "$PID"
  wait "$PID" 2>/dev/null || true
  ok "$NAME launched and stayed up for ${SECONDS_ALIVE}s"
else
  status=0; wait "$PID" || status=$?
  echo "${RED}$NAME exited after launch (status $status). Log:${RESET}" >&2
  tail -n 40 "$LOG" >&2
  exit 1
fi
