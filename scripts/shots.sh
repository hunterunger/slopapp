#!/usr/bin/env bash
# Store screenshots for one app (docs/screenshots.md).
#
#   scripts/shots.sh <Name> [--force] [--only id,id] [--appearance light|dark] [--no-bundle] [--compose-only]
#
# Reads apps/<Name>/showcase.json, and for each shot, in light and then dark:
#   1. shows a full-screen backdrop window of our own on the primary screen (category colour),
#   2. launches a private copy of build/<Name>.app (bundle id <id>.showcase, so it never meets
#      the owner's installed copy, its settings or its links) with SLOP_SHOWCASE=<scene>,
#      SLOP_APPEARANCE and the app's test-data environment from showcase.json,
#   3. waits for the app's ready file, captures each listed window alone (screencapture -l, no
#      shadow: the composer draws one), and quits the app.
# Then it composes every shot on the backdrop (tools/Shots), and writes
# web/public/shots/<slug>/<id>-{light,dark}.webp (2880 × 1800), <id>-{light,dark}@1x.webp
# (1440 × 900) and manifest.json.
#
# Refuses apps below beta unless --force. Needs an awake, unlocked Retina display and the owner
# away: no keyboard or mouse input for 60 s (it waits up to 10 minutes, and stops if they come
# back). Never captures the screen, the wallpaper or another app's window. Needs cwebp
# (brew install webp). Raw captures and logs stay in /tmp/<slug>-showcase for review.
#
#   --only hero,rules     just these shots (the rest of the set is kept as it is)
#   --appearance dark     just one appearance (for trying a scene; the manifest needs both)
#   --compose-only        re-compose from the last captures (after a composer change)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
NAME="${1:-}"; [[ -n "$NAME" && "$NAME" != -* ]] || usage
shift
FORCE=0; ONLY=""; APPEARANCES="light dark"; BUNDLE=1; CAPTURE=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1 ;;
    --only) ONLY="$2"; shift ;;
    --appearance) [[ "$2" == light || "$2" == dark ]] || die "--appearance is light or dark"; APPEARANCES="$2"; shift ;;
    --no-bundle) BUNDLE=0 ;;
    --compose-only) CAPTURE=0; BUNDLE=0 ;;
    -h|--help) usage ;;
    *) die "unknown option $1" ;;
  esac
  shift
done

DIR="$(app_dir "$NAME")"
MANIFEST="$DIR/app.json"
SHOWCASE="$DIR/showcase.json"
SLUG="$(json_get "$MANIFEST" .slug)"
STATUS="$(json_get "$MANIFEST" .status)"
VERSION="$(json_get "$MANIFEST" .version)"
CATEGORY="$(json_get "$MANIFEST" .category)"
BUNDLE_ID="$(json_get "$MANIFEST" .bundleId)"
MENU_BAR="$(json_get "$MANIFEST" .menuBarOnly)"; [[ "$MENU_BAR" == true ]] || MENU_BAR=false
[[ -f "$SHOWCASE" ]] || die "$NAME has no showcase.json (see docs/screenshots.md)"

case "$STATUS" in
  beta|stable) ;;
  *) [[ $FORCE -eq 1 ]] || die "$NAME is $STATUS. Shots are for beta and later (docs/screenshots.md); --force to try a scene anyway." ;;
esac

# --- The Swift half ----------------------------------------------------------------------
TOOL_PKG="$ROOT/tools/Shots"
SHOTS="$TOOL_PKG/.build/release/shots"
STAMP="$TOOL_PKG/.build/shots.stamp"
if [[ ! -x "$SHOTS" || ! -f "$STAMP" ]] || [[ -n "$(find "$TOOL_PKG/Sources" "$TOOL_PKG/Package.swift" -newer "$STAMP" 2>/dev/null | head -1)" ]]; then
  say "Building tools/Shots"
  run_logged "$LOG_DIR/shots-tool-build.log" swift build -c release --package-path "$TOOL_PKG"
  touch "$STAMP"
fi
export SLOPAPP_ROOT="$ROOT"

PLAN="$("$SHOTS" plan "$SHOWCASE")" || die "showcase.json is invalid"
COUNT="$(printf '%s\n' "$PLAN" | wc -l | tr -d ' ')"
[[ $COUNT -ge 3 ]] || echo "${DIM}note: $COUNT shots; a set is 3 to 5${RESET}"
wanted() { [[ -z "$ONLY" ]] || [[ ",$ONLY," == *",$1,"* ]]; }

WORK="/tmp/$SLUG-showcase"
OUT="$ROOT/web/public/shots/$SLUG"
command -v cwebp >/dev/null 2>&1 || die "cwebp not found. Install it with: brew install webp"

# --- Capture ---------------------------------------------------------------------------
APP_PID=""; BACKDROP_PID=""; BACKDROP_WID=""; COPY=""
cleanup() {
  [[ -n "$APP_PID" ]] && kill "$APP_PID" 2>/dev/null && wait "$APP_PID" 2>/dev/null || true
  [[ -n "$BACKDROP_PID" ]] && kill "$BACKDROP_PID" 2>/dev/null && wait "$BACKDROP_PID" 2>/dev/null || true
  APP_PID=""; BACKDROP_PID=""
  if [[ -n "$COPY" && -d "$COPY" ]]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$COPY" >/dev/null 2>&1 || true
    rm -rf "$COPY"
    forget_copy_data
  fi
}

# The copy's own settings and support files (its bundle id is <id>.showcase): removed before
# and after each run, so every run starts the same and nothing is left behind.
forget_copy_data() {
  local id="$BUNDLE_ID.showcase"
  defaults delete "$id" >/dev/null 2>&1 || true
  rm -f "$HOME/Library/Preferences/$id.plist"
  rm -rf "$HOME/Library/Application Support/$id" "$HOME/Library/Caches/$id" \
    "$HOME/Library/Saved Application State/$id.savedState" "$HOME/Library/HTTPStorages/$id"
}
trap cleanup EXIT
trap 'echo; die "interrupted"' INT TERM

# Seconds since the last keyboard or mouse input. (awk reads to the end: an early exit
# would SIGPIPE ioreg and fail the pipeline under pipefail.)
idle_seconds() { ioreg -c IOHIDSystem | awk '/HIDIdleTime/ && !found { v = int($NF / 1000000000); found = 1 } END { print v + 0 }'; }

# Waits (up to 10 minutes) until nobody has touched the keyboard or mouse for 60 s.
wait_for_owner_away() {
  local waited=0 idle
  while :; do
    idle="$(idle_seconds)"
    [[ "${idle:-0}" -ge 60 ]] && return 0
    [[ $waited -ge 600 ]] && die "the Mac has been in use for 10 minutes (idle ${idle}s). Shots need 60 s without keyboard or mouse input; try again later."
    [[ $waited -eq 0 ]] && echo "${DIM}waiting for 60 s without keyboard or mouse input (idle ${idle}s)…${RESET}"
    sleep 5; waited=$((waited + 5))
  done
}

# Between scenes: if anyone has touched the keyboard or mouse since the run started, stop
# (the backdrop covers their screen). Launching our own apps doesn't count as input.
check_owner_still_away() {
  local idle; idle="$(idle_seconds)"
  local last_input=$(( $(date +%s) - ${idle:-0} ))
  if [[ $last_input -gt $((LAST_INPUT + 2)) ]]; then
    die "someone used the Mac during the run (last input ${idle}s ago). Stopped; the set wasn't changed."
  fi
}

prepare_copy() {
  [[ -d "$BUILD_DIR/$NAME.app" ]] || die "build/$NAME.app not found; run scripts/bundle.sh $NAME"
  COPY="$WORK/$NAME.app"
  rm -rf "$COPY"
  forget_copy_data
  ditto "$BUILD_DIR/$NAME.app" "$COPY"
  plutil -replace CFBundleIdentifier -string "$BUNDLE_ID.showcase" "$COPY/Contents/Info.plist"
  # No URL schemes or document types: the copy must never be offered links or files.
  plutil -remove CFBundleURLTypes "$COPY/Contents/Info.plist" 2>/dev/null || true
  plutil -remove CFBundleDocumentTypes "$COPY/Contents/Info.plist" 2>/dev/null || true
  codesign --force --sign - --preserve-metadata=entitlements,flags,runtime "$COPY" >/dev/null 2>&1 \
    || die "couldn't re-sign the showcase copy of $NAME"
}

start_backdrop() {
  local appearance="$1" ready="$WORK/backdrop-$1.ready"
  rm -f "$ready"
  "$SHOTS" backdrop --showcase "$SHOWCASE" --category "$CATEGORY" --appearance "$appearance" --ready "$ready" >"$WORK/logs/backdrop.log" 2>&1 &
  BACKDROP_PID=$!
  for _ in $(seq 1 50); do
    if [[ -s "$ready" ]]; then BACKDROP_WID="$(tr -dc '0-9' <"$ready")"; return 0; fi
    sleep 0.1
  done
  die "the backdrop didn't appear (see $WORK/logs/backdrop.log)"
}

stop_backdrop() {
  [[ -n "$BACKDROP_PID" ]] && kill "$BACKDROP_PID" 2>/dev/null && wait "$BACKDROP_PID" 2>/dev/null || true
  BACKDROP_PID=""
}

# capture_scene <id> <scene> <size> <appearance>
capture_scene() {
  local id="$1" scene="$2" size="$3" appearance="$4"
  local key="$id-$appearance"
  local data="$WORK/data/$key" ready="$WORK/ready/$key.json" raw="$WORK/raw/$key" log="$WORK/logs/$key.log"
  rm -rf "$data" "$raw" "$ready"
  mkdir -p "$data" "$raw" "$(dirname "$ready")"
  [[ -d "$DIR/showcase" ]] && ditto "$DIR/showcase" "$data"
  local env_args=(
    "SLOP_SHOWCASE=$scene" "SLOP_SHOWCASE_READY=$ready" "SLOP_SHOWCASE_DATA=$data" "SLOP_APPEARANCE=$appearance"
  )
  [[ "$size" != "-" ]] && env_args+=("SLOP_SHOWCASE_SIZE=$size")
  while IFS= read -r line; do [[ -n "$line" ]] && env_args+=("$line"); done < <("$SHOTS" env "$SHOWCASE" "$data")

  env "${env_args[@]}" "$COPY/Contents/MacOS/$NAME" >"$log" 2>&1 &
  APP_PID=$!
  local waited=0
  until [[ -f "$ready" ]]; do
    kill -0 "$APP_PID" 2>/dev/null || { tail -n 20 "$log" >&2; die "$NAME quit before scene $scene was ready (log: $log)"; }
    [[ $waited -ge 300 ]] && die "scene $scene wasn't ready after 30 s (log: $log)"
    sleep 0.1; waited=$((waited + 1))
  done
  local ids
  ids="$("$SHOTS" ids "$ready")" || die "scene $scene failed (see above)"
  [[ -n "$ids" ]] || die "scene $scene listed no windows"
  while read -r wid kind image; do
    if [[ "$kind" == statusItem ]]; then
      # macOS draws menu bar icons itself; the app drew its icon for the composer.
      [[ -n "$image" && -f "$image" ]] && cp "$image" "$raw/$wid.png"
      continue
    fi
    # The window alone, for its shape (glass comes out grey here; see tools/Shots Capture.swift).
    screencapture -x -o -l"$wid" "$raw/$wid-mask.png" 2>>"$log" || die "couldn't capture window $wid of scene $scene"
    [[ -s "$raw/$wid-mask.png" ]] || die "empty capture of window $wid ($kind). Does this terminal have Screen Recording permission?"
  done <<<"$ids"
  # Then composited over our backdrop, from our own windows only.
  "$SHOTS" capture --ready "$ready" --backdrop "$BACKDROP_WID" --dir "$raw" 2>>"$log" \
    || { tail -n 5 "$log" >&2; die "couldn't capture scene $scene over the backdrop"; }
  kill "$APP_PID" 2>/dev/null || true
  wait "$APP_PID" 2>/dev/null || true
  APP_PID=""
  echo "  $key: $(echo "$ids" | wc -l | tr -d ' ') window(s)"
}

if [[ $CAPTURE -eq 1 ]]; then
  [[ $BUNDLE -eq 1 ]] && "$ROOT/scripts/bundle.sh" "$NAME"
  GATE="$("$SHOTS" gate)" || die "can't take shots now: $GATE"
  mkdir -p "$WORK/logs"
  prepare_copy
  wait_for_owner_away
  LAST_INPUT=$(( $(date +%s) - $(idle_seconds) ))
  for appearance in $APPEARANCES; do
    say "Capturing $NAME ($appearance)"
    start_backdrop "$appearance"
    while IFS=$'\t' read -r id scene size; do
      wanted "$id" || continue
      check_owner_still_away
      capture_scene "$id" "$scene" "$size" "$appearance"
    done <<<"$PLAN"
    stop_backdrop
  done
  cleanup
fi

# --- Compose ---------------------------------------------------------------------------
say "Composing"
mkdir -p "$OUT" "$WORK/out"
while IFS=$'\t' read -r id scene size; do
  wanted "$id" || continue
  for appearance in $APPEARANCES; do
    key="$id-$appearance"
    [[ -f "$WORK/ready/$key.json" ]] || die "no capture for $key; run without --compose-only"
    "$SHOTS" compose --showcase "$SHOWCASE" --shot "$id" --ready "$WORK/ready/$key.json" --captures "$WORK/raw/$key" \
      --category "$CATEGORY" --appearance "$appearance" --menubar "$MENU_BAR" --out "$WORK/out/$key.png" >/dev/null
    sips -z 900 1440 "$WORK/out/$key.png" --out "$WORK/out/$key@1x.png" >/dev/null
    cwebp -quiet -q 90 -m 6 -sharp_yuv -mt "$WORK/out/$key.png" -o "$OUT/$key.webp"
    cwebp -quiet -q 90 -m 6 -sharp_yuv -mt "$WORK/out/$key@1x.png" -o "$OUT/$key@1x.webp"
    echo "  $key  $(du -k "$OUT/$key.webp" | cut -f1) KB, @1x $(du -k "$OUT/$key@1x.webp" | cut -f1) KB"
  done
done <<<"$PLAN"

if [[ "$APPEARANCES" == "light dark" ]] || [[ -f "$OUT/manifest.json" ]]; then
  if "$SHOTS" manifest --slug "$SLUG" --app-version "$VERSION" --showcase "$SHOWCASE" --dir "$OUT" >/dev/null 2>"$WORK/logs/manifest.log"; then
    ok "$NAME: $COUNT shots -> ${OUT#$ROOT/} (manifest.json, app $VERSION)"
  else
    echo "${DIM}manifest not written: $(cat "$WORK/logs/manifest.log")${RESET}"
  fi
fi
echo "${DIM}raw captures and logs: $WORK${RESET}"
