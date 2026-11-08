#!/usr/bin/env bash
# Synthetic content for the launcher's store screenshots (docs/screenshots.md, showcase.json).
# scripts/shots.sh runs it once per run and copies <out> into every scene's {data}:
#
#   apps/Slopapp/showcase-fixtures.sh <out>
#
#   <out>/feed/          a self-contained feed of this repo's apps (scripts/feed.mjs --local):
#                        feed.json, icons and screenshot sets, relative URLs. No zips: the scenes
#                        never install anything.
#   <out>/Applications/  older copies (0.1.0) of a few apps, re-signed ad hoc, so the Updates
#                        page has updates waiting. The launcher's install folder in the scenes.
#
# Uses build/*.zip and build/<Name>.app (scripts/bundle.sh). Nothing outside <out> is changed,
# and nothing here is ever opened: the scenes only read the copies' Info.plist and icon. The
# copies are older than the real apps, have no URL schemes or document types, and shots.sh
# unregisters them from LaunchServices afterwards, so macOS never picks one over a real app.
set -euo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

OUT="${1:-}"
[[ -n "$OUT" ]] || die "usage: $0 <out dir>"
# Apps shown with an update waiting, and the version their "installed" copy claims.
UPDATES=(Dropper Tidy Zones)
OLD_VERSION=0.1.0
OLD_BUILD=1

rm -rf "$OUT"
mkdir -p "$OUT/feed" "$OUT/Applications"

node "$ROOT/scripts/feed.mjs" --local "$OUT/feed"
rm -f "$OUT/feed"/*.zip

for name in "${UPDATES[@]}"; do
  src="$BUILD_DIR/$name.app"
  [[ -d "$src" ]] || die "build/$name.app not found; run scripts/bundle.sh $name"
  app="$OUT/Applications/$name.app"
  ditto "$src" "$app"
  plist="$app/Contents/Info.plist"
  plutil -replace CFBundleShortVersionString -string "$OLD_VERSION" "$plist"
  plutil -replace CFBundleVersion -string "$OLD_BUILD" "$plist"
  # Like the showcase copy of the launcher: never offered links or files.
  plutil -remove CFBundleURLTypes "$plist" 2>/dev/null || true
  plutil -remove CFBundleDocumentTypes "$plist" 2>/dev/null || true
  codesign --force --sign - --preserve-metadata=entitlements,flags,runtime "$app" >/dev/null 2>&1 \
    || die "couldn't re-sign the old copy of $name"
done
echo "fixtures: feed ($(ls "$OUT/feed" | wc -l | tr -d ' ') files), ${UPDATES[*]} at $OLD_VERSION in $OUT/Applications"
