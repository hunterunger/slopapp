#!/usr/bin/env bash
# Performance gate: launch time, idle CPU and memory against Slopapp's budgets.
#
#   scripts/perf.sh <Name> [--no-bundle] [--runs N] [--windows N] [--seconds N] [--keep] [--direct]
#
# Bundles a release build (unless --no-bundle), launches it N times (default 3) and takes
# the median launch time, then leaves the last instance idle and measures CPU over several
# idle windows (default 3 windows of 5 s) and peak memory. Exits non-zero if any budget is missed.
#
# Budgets (see docs/design-system.md):
#   launch             < 300 ms   open -> app finished launching
#   first surface      < 600 ms   open -> first window or menu bar icon
#   idle CPU           < 0.2 %    lowest idle window (the median is printed too)
#   memory (footprint) < 50 MB menu-bar apps, < 120 MB window apps
# Idle CPU gates on the lowest window: an app's own idle work is steady, and a busy machine
# (other agents building and testing) only ever inflates a window, never deflates it.
# The 1-minute load average is printed; above 4 the result is labelled "(busy machine)".
# Memory is the physical footprint (Activity Monitor's "Memory" column). RSS is shown for
# reference only: it counts shared system frameworks, so even an empty SwiftUI app is ~80 MB.
#
# If another copy with the same bundle id is running (e.g. the installed one), a normal launch
# would hand back that copy and measure it, so the script stops instead. --direct measures a
# separate copy of this build beside it; that copy uses the same settings and data as the
# running one unless the app isolates itself, so only use it for apps where that's harmless.
#
# Drives the app with scripts/drive (needs Accessibility permission for the terminal).
# Works with macOS's bash 3.2.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

USAGE="usage: scripts/perf.sh <Name> [--no-bundle] [--runs N] [--windows N] [--seconds N] [--keep] [--direct]"
NAME="${1:-}"; [[ -n "$NAME" ]] || die "$USAGE"
shift
BUNDLE=1; RUNS=3; WINDOWS=3; IDLE=5; KEEP=0; DIRECT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-bundle) BUNDLE=0 ;;
    --runs) RUNS="$2"; shift ;;
    --windows) WINDOWS="$2"; shift ;;
    --seconds) IDLE="$2"; shift ;;
    --keep) KEEP=1 ;;
    --direct) DIRECT=1 ;;
    *) die "unknown option $1. $USAGE" ;;
  esac
  shift
done
[[ "$RUNS" -ge 1 && "$WINDOWS" -ge 1 && "$IDLE" -ge 1 ]] || die "--runs, --windows and --seconds must be at least 1"

DIR="$(app_dir "$NAME")"
MENU_BAR_ONLY="$(json_get "$DIR/app.json" .menuBarOnly)"
if [[ "$MENU_BAR_ONLY" == "true" ]]; then MEM_BUDGET=50; KIND="menu-bar app"; else MEM_BUDGET=120; KIND="window app"; fi
LAUNCH_BUDGET=300; SURFACE_BUDGET=600; CPU_BUDGET=0.2; BUSY_LOAD=4

DRIVE="$ROOT/scripts/drive"
APP="$BUILD_DIR/$NAME.app"
[[ $BUNDLE -eq 1 ]] && "$ROOT/scripts/bundle.sh" "$NAME" >/dev/null
[[ -d "$APP" ]] || die "$APP not found; run scripts/bundle.sh $NAME"

# Is this bundle still a live process, or still listed by LaunchServices (`drive apps`)?
# NSRunningApplication can list an app for a moment after its process exits; launching then
# latches onto the dying instance ("already running", then "no running app matches").
has_process() { pgrep -f "$APP/Contents/MacOS/" >/dev/null 2>&1; }
listed() {
  "$DRIVE" apps --paths 2>/dev/null | awk -v p="  $APP" \
    'length($0) >= length(p) && substr($0, length($0) - length(p) + 1) == p { found = 1 } END { exit !found }'
}

quit_app() {
  "$DRIVE" quit "$APP" >/dev/null 2>&1 || true
  local w
  for ((w = 0; w < 100; w++)); do          # up to ~10 s, plus `drive apps` time
    if ! has_process && ! listed; then return 0; fi
    if [[ $w -eq 50 ]] && has_process; then pkill -9 -f "$APP/Contents/MacOS/" 2>/dev/null || true; fi
    sleep 0.1
  done
  die "$NAME didn't go away after quitting (still in pgrep or \`drive apps\`)"
}

# Another copy with this bundle id running elsewhere (e.g. the installed one in /Applications)?
# Then a normal launch would hand back that copy and measure it, so start this build directly.
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
LAUNCH_FLAGS=()
if [[ $DIRECT -eq 1 ]]; then
  LAUNCH_FLAGS=(--direct)
elif other="$("$DRIVE" apps --paths 2>/dev/null | grep -F "  $BUNDLE_ID  " | grep -vF "  $APP")"; then
  die "another $NAME is running (${other##*  }); its numbers would be measured instead of this build. Quit it, or pass --direct to measure a separate copy beside it"
fi

# launch_once: prints the `drive launch --timing` line; retries a fresh start a few times.
launch_once() {
  local attempt line
  for ((attempt = 1; attempt <= 3; attempt++)); do
    line="$("$DRIVE" launch "$APP" --timing ${LAUNCH_FLAGS[@]+"${LAUNCH_FLAGS[@]}"} 2>&1)" || true
    if [[ "$line" == *launch_ms=* ]]; then echo "$line"; return 0; fi
    echo "${DIM}launch attempt $attempt: ${line}${RESET}" >&2
    quit_app
    sleep 0.5
  done
  die "couldn't launch $NAME: $line"
}

quit_app

# Launch N times; keep the last one running for the idle measurement.
launches=(); surfaces=(); surface_kind="-"; PID=""
for ((i = 1; i <= RUNS; i++)); do
  line="$(launch_once)"
  launches+=("$(sed -E 's/.*launch_ms=([0-9-]+).*/\1/' <<<"$line")")
  surfaces+=("$(sed -E 's/.*first_surface_ms=([0-9-]+).*/\1/' <<<"$line")")
  surface_kind="$(sed -E 's/.*first_surface=([a-z-]+).*/\1/' <<<"$line")"
  PID="$(sed -E 's/.*pid=([0-9]+).*/\1/' <<<"$line")"
  [[ $i -lt $RUNS ]] && quit_app
done
median() { printf '%s\n' "$@" | sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}'; }
minimum() { printf '%s\n' "$@" | sort -n | head -n 1; }
LAUNCH_MS="$(median "${launches[@]}")"
SURFACE_MS="$(median "${surfaces[@]}")"

# Let launch work settle, then measure the idle windows. Stats by pid, so a stale
# LaunchServices entry for an earlier instance can't be picked up.
sleep 2
stat() { "$DRIVE" stats "$PID" 2>/dev/null; }
field() { sed -E "s/.*$1=([0-9.]+).*/\1/" <<<"$2"; }
cpus=(); peak_fp=0; peak_rss=0
for ((w = 0; w < WINDOWS; w++)); do
  start="$(stat)" || die "$NAME quit or crashed while idle"
  for ((s = 0; s < IDLE; s++)); do
    sleep 1
    now="$(stat)" || die "$NAME quit or crashed while idle"
    peak_fp="$(awk -v a="$peak_fp" -v b="$(field footprint_mb "$now")" 'BEGIN {print (b > a) ? b : a}')"
    peak_rss="$(awk -v a="$peak_rss" -v b="$(field rss_mb "$now")" 'BEGIN {print (b > a) ? b : a}')"
  done
  # CPU time over wall-clock time for this window.
  cpus+=("$(awk -v a="$(field cpu_ms "$start")" -v b="$(field cpu_ms "$now")" \
    -v t0="$(field time_s "$start")" -v t1="$(field time_s "$now")" \
    'BEGIN {printf "%.3f", (b - a) / ((t1 - t0) * 1000) * 100}')")
done
CPU_MIN="$(minimum "${cpus[@]}")"
CPU_MEDIAN="$(median "${cpus[@]}")"

LOAD1="$(sysctl -n vm.loadavg | awk '{print $2}')"
BUSY=""
[[ "$(awk -v l="$LOAD1" -v b="$BUSY_LOAD" 'BEGIN {print (l > b) ? 1 : 0}')" == 1 ]] && BUSY=" (busy machine)"

[[ $KEEP -eq 1 ]] || quit_app

failures=0
row() { # row <metric> <value> <budget> <pass?>
  local status
  if [[ "$4" == 1 ]]; then status="${GREEN}PASS${RESET}"; else status="${RED}FAIL${RESET}"; failures=$((failures + 1)); fi
  printf '  %-22s %-12s %-12s %s\n' "$1" "$2" "$3" "$status"
}
lt() { awk -v a="$1" -v b="$2" 'BEGIN {print (a >= 0 && a < b) ? 1 : 0}'; }

echo "${BOLD}$NAME performance${RESET}${BUSY} ${DIM}($KIND, median of $RUNS launches, idle CPU over $WINDOWS x ${IDLE}s, load $LOAD1)${RESET}"
printf '  %-22s %-12s %-12s %s\n' "metric" "value" "budget" ""
row "launch" "${LAUNCH_MS} ms" "< ${LAUNCH_BUDGET} ms" "$(lt "$LAUNCH_MS" $LAUNCH_BUDGET)"
row "first $surface_kind" "${SURFACE_MS} ms" "< ${SURFACE_BUDGET} ms" "$(lt "$SURFACE_MS" $SURFACE_BUDGET)"
row "idle CPU (lowest)" "${CPU_MIN} %" "< ${CPU_BUDGET} %" "$(lt "$CPU_MIN" $CPU_BUDGET)"
printf '  %-22s %-12s %s\n' "idle CPU (median)" "${CPU_MEDIAN} %" "${DIM}not a budget; windows: ${cpus[*]}${RESET}"
row "memory (footprint)" "${peak_fp} MB" "< ${MEM_BUDGET} MB" "$(lt "$peak_fp" $MEM_BUDGET)"
printf '  %-22s %-12s %s\n' "rss (reference)" "${peak_rss} MB" "${DIM}not a budget${RESET}"
printf '  %-22s %-12s %s\n' "load average (1 min)" "${LOAD1}" "${DIM}busy above ${BUSY_LOAD}${RESET}${BUSY}"

[[ $failures -eq 0 ]] || die "$failures performance budget(s) missed${BUSY}"
ok "$NAME is within budget${BUSY}"
