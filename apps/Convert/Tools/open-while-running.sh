#!/usr/bin/env bash
# Regression check (blind test round 2, F1): files opened while Convert is running
# (`open -a`, as Finder's Open With and Dock drops do) must join the one window.
# The app must keep exactly one process and one main window, and never ask to quit.
#
#   apps/Convert/Tools/open-while-running.sh [times]     # default 10; uses /tmp/convert-test
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
APP="$ROOT/build/Convert.app"
TIMES="${1:-10}"
DIR=/tmp/convert-test/open-check
DRIVE="$ROOT/scripts/drive"
FIXTURES=/tmp/convert-test/fixtures
[[ -d "$FIXTURES" ]] || swift run --package-path "$ROOT/apps/Convert" ConvertFixturesTool "$FIXTURES" --quick >/dev/null
rm -rf "$DIR" && mkdir -p "$DIR"
files=("Photo.heic" "Interview.wav" "Clip H264.mov" "Logo.png" "Sideways Photo.jpg")
for i in $(seq 1 "$TIMES"); do cp "$FIXTURES/${files[$(( (i - 1) % 5 ))]}" "$DIR/$i-${files[$(( (i - 1) % 5 ))]}"; done

"$DRIVE" quit Convert >/dev/null 2>&1 || true
"$DRIVE" launch "$APP" >/dev/null
sleep 1
fail=0
for i in $(seq 1 "$TIMES"); do
  name="$i-${files[$(( (i - 1) % 5 ))]}"
  open -a "$APP" "$DIR/$name"
  sleep 1.2
  procs=$(pgrep -f "$APP/Contents/MacOS/Convert" | wc -l | tr -d ' ')
  windows=$("$DRIVE" windows Convert 2>&1 || true)
  mains=$(grep -c '#main' <<<"$windows" || true)
  alerts=$(grep -c 'dialog' <<<"$windows" || true)
  rows=$("$DRIVE" tree Convert 2>/dev/null | grep -c "staticText \"[0-9]*-" || true)
  if [[ "$procs" == 1 && "$mains" == 1 && "$alerts" == 0 && "$rows" == "$i" ]]; then
    echo "ok   $i: 1 process, 1 window, $rows rows"
  else
    echo "FAIL $i: processes=$procs main windows=$mains alerts=$alerts rows=$rows"
    fail=1
  fi
done
"$DRIVE" quit Convert >/dev/null 2>&1 || true
exit $fail
