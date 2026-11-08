#!/usr/bin/env bash
# Packs build/<Name>.app into build/<Name>.dmg: the app and an Applications shortcut side by
# side, so people drag one onto the other. Run scripts/bundle.sh <Name> first.
#
#   scripts/dmg.sh <Name>
#
# Signs the image with SLOPAPP_SIGN_IDENTITY when that is a real identity (ad-hoc builds leave
# it unsigned; codesign has nothing to add there). The release workflow builds one for apps
# whose app.json has "dmg": true, next to the zip the launcher installs from.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

NAME="${1:-}"; [[ -n "$NAME" ]] || die "usage: scripts/dmg.sh <Name>"
app_dir "$NAME" >/dev/null
APP="$BUILD_DIR/$NAME.app"
DMG="$BUILD_DIR/$NAME.dmg"
IDENTITY="${SLOPAPP_SIGN_IDENTITY:--}"
[[ -d "$APP" ]] || die "no $APP: run scripts/bundle.sh $NAME first"

# dmgbuild, pinned (scripts/dmg/requirements.txt), in its own venv under build/.
VENV="$BUILD_DIR/tools/dmgbuild"
REQUIREMENTS="$ROOT/scripts/dmg/requirements.txt"
if ! cmp -s "$REQUIREMENTS" "$VENV/requirements.txt" 2>/dev/null; then
  say "Installing dmgbuild"
  rm -rf "$VENV"
  run_logged "$LOG_DIR/dmgbuild-install.log" python3 -m venv "$VENV"
  run_logged "$LOG_DIR/dmgbuild-install.log" "$VENV/bin/pip" install --quiet --disable-pip-version-check -r "$REQUIREMENTS"
  cp "$REQUIREMENTS" "$VENV/requirements.txt"
fi

say "Packing $NAME.dmg"
rm -f "$DMG"
VOLUME_ICON="$APP/Contents/Resources/AppIcon.icns"
[[ -f "$VOLUME_ICON" ]] || VOLUME_ICON=""
run_logged "$LOG_DIR/$NAME-dmg.log" "$VENV/bin/dmgbuild" -s "$ROOT/scripts/dmg/settings.py" \
  -D app="$APP" -D volume_icon="$VOLUME_ICON" "$NAME" "$DMG"

if [[ "$IDENTITY" != "-" ]]; then
  run_logged "$LOG_DIR/$NAME-sign.log" codesign --force --timestamp --sign "$IDENTITY" "$DMG"
fi
hdiutil verify "$DMG" >/dev/null 2>&1 || die "$DMG failed hdiutil verify"
ok "$NAME.dmg ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
