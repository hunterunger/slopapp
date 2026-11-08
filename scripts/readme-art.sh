#!/bin/bash
# Renders the README artwork (.github/readme/) from the HTML in scripts/readme/, light and dark,
# at 2x with headless Chrome. Needs Google Chrome and network (web fonts). Re-run after icons change.
#
#   scripts/readme-art.sh
set -euo pipefail
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[[ -x "$CHROME" ]] || { echo "needs Google Chrome" >&2; exit 1; }
OUT=.github/readme
mkdir -p "$OUT"
PROFILE=$(mktemp -d)   # a throwaway profile, never the user's
trap 'rm -rf "${PROFILE:?}"' EXIT

render() {  # render <page> <width> <height> <out-name>
  local page=$1 width=$2 height=$3 name=$4
  for theme in light dark; do
    local query=""; [[ $theme == dark ]] && query="?dark"
    "$CHROME" --headless=new --user-data-dir="$PROFILE" --disable-gpu --hide-scrollbars \
      --allow-file-access-from-files --force-device-scale-factor=2 \
      --window-size="$width,$height" --default-background-color=00000000 \
      --virtual-time-budget=8000 --screenshot="$OUT/$name-$theme.png" \
      "file://$PWD/scripts/readme/$page$query" >/dev/null 2>&1
    echo "  $OUT/$name-$theme.png"
  done
}

render hero.html 1280 520 hero
