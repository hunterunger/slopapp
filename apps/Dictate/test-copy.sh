#!/bin/bash
# Makes a test copy of the release build with its own bundle id, so a test run can never share
# anything with an installed Dictate: settings, keyboard shortcuts, the menu bar icon setting,
# window positions, the status item's place in the menu bar, login items, privacy grants.
#
#   apps/Dictate/test-copy.sh [destination.app]     (default: /tmp/dictate-test/Dictate Test.app)
#   scripts/drive launch "/tmp/dictate-test/Dictate Test.app" --direct --env DICTATE_DATA_DIR=... ...
#
# The copy keeps the name Dictate (so the UI reads the same); target it by pid with scripts/drive.
# Build first with scripts/bundle.sh Dictate.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
source_app="$root/build/Dictate.app"
dest="${1:-/tmp/dictate-test/Dictate Test.app}"
bundle_id="app.slopapp.dictate.test"

[[ -d "$source_app" ]] || { echo "No $source_app. Run scripts/bundle.sh Dictate first." >&2; exit 1; }
case "$dest" in
    /tmp/*|/private/tmp/*) ;;
    *) echo "Refusing to write outside /tmp: $dest" >&2; exit 1 ;;
esac

rm -rf "$dest"
mkdir -p "$(dirname "$dest")"
ditto "$source_app" "$dest"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$dest/Contents/Info.plist"
codesign --force --sign - --options runtime --entitlements "$root/apps/Dictate/Dictate.entitlements" "$dest" >/dev/null 2>&1
codesign --verify "$dest"
echo "$dest ($bundle_id)"
