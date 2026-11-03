#!/usr/bin/env bash
# Builds a fake Mac for trying Tidy safely: apps, their leftovers (and decoys that must not
# match), leftovers of deleted apps, caches, logs, Xcode junk, and large and old files.
#
#   apps/Tidy/Scripts/make-fixtures.sh            # -> /tmp/tidy-test (replaces an old one)
#   apps/Tidy/Scripts/make-fixtures.sh --remove   # delete it
#
# Then launch Tidy against it (every scan and every move stays inside /tmp/tidy-test):
#
#   scripts/drive launch build/Tidy.app \
#     --env TIDY_HOME=/tmp/tidy-test/home --env TIDY_APPS_DIRS=/tmp/tidy-test/Applications \
#     --env TIDY_TRASH_DIR=/tmp/tidy-test/Trash --env TIDY_SYSTEM_LIBRARY=/tmp/tidy-test/Library \
#     --env TIDY_RUNNING_IDS=com.fixture.Busybee
#
# Optional: --env TIDY_ASSUME_FULL_DISK_ACCESS=1 (pretend Full Disk Access is on),
#           --env TIDY_APPEARANCE=dark|light.
set -euo pipefail
PKG="$(cd "$(dirname "$0")/.." && pwd)"
ROOT=/tmp/tidy-test
swift build --package-path "$PKG" --product tidy-tool >/dev/null
TOOL="$(swift build --package-path "$PKG" --show-bin-path)/tidy-tool"
if [[ "${1:-}" == "--remove" ]]; then
  "$TOOL" remove-fixtures "$ROOT"
  echo "Removed $ROOT"
else
  "$TOOL" fixtures "$ROOT"
fi
