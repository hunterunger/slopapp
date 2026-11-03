#!/usr/bin/env bash
# Builds apps/<Name> into build/<Name>.app (and build/<Name>.zip).
#
#   scripts/bundle.sh <Name> [--debug]
#
# Release builds are universal (arm64 + x86_64); --debug builds the host arch only.
# Signing: ad-hoc by default. Set SLOPAPP_SIGN_IDENTITY="Developer ID Application: ..."
# to sign for distribution (the release workflow does this).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

NAME="${1:-}"; [[ -n "$NAME" ]] || die "usage: scripts/bundle.sh <Name> [--debug]"
CONFIG="release"; [[ "${2:-}" == "--debug" ]] && CONFIG="debug"
DIR="$(app_dir "$NAME")"
MANIFEST="$DIR/app.json"
APP="$BUILD_DIR/$NAME.app"
IDENTITY="${SLOPAPP_SIGN_IDENTITY:--}"

# 1. Compile.
ARCH_FLAGS=()
[[ "$CONFIG" == "release" ]] && ARCH_FLAGS=(--arch arm64 --arch x86_64)
say "Building $NAME ($CONFIG)"
run_logged "$LOG_DIR/$NAME-build.log" swift build --package-path "$DIR" -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_PATH="$(swift build --package-path "$DIR" -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

# 2. Assemble the .app.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/$NAME" "$APP/Contents/MacOS/$NAME"
# SwiftPM resource bundles (from `resources:` in Package.swift), if any.
shopt -s nullglob
for bundle in "$BIN_PATH"/*.bundle "$BIN_PATH"/*.resources; do
  cp -R "$bundle" "$APP/Contents/Resources/"
done
shopt -u nullglob

# 3. Icon: AppIcon.svg (finished full-art icon, e.g. the brand logo) wins; otherwise
#    Icon.svg (a Lucide glyph on the forest tile).
if [[ -f "$DIR/AppIcon.svg" ]]; then
  swift "$ROOT/scripts/icongen.swift" "$DIR/AppIcon.svg" "$APP/Contents/Resources/AppIcon.icns" \
    --png "$BUILD_DIR/$NAME-icon.png" --full-art >/dev/null
elif [[ -f "$DIR/Icon.svg" ]]; then
  swift "$ROOT/scripts/icongen.swift" "$DIR/Icon.svg" "$APP/Contents/Resources/AppIcon.icns" \
    --png "$BUILD_DIR/$NAME-icon.png" >/dev/null
fi

# 4. Info.plist, generated from app.json.
case "$(json_get "$MANIFEST" .category)" in
  Developer)    CATEGORY="public.app-category.developer-tools" ;;
  Design)       CATEGORY="public.app-category.graphics-design" ;;
  Media)        CATEGORY="public.app-category.video" ;;
  Productivity) CATEGORY="public.app-category.productivity" ;;
  *)            CATEGORY="public.app-category.utilities" ;;
esac
PLIST="$APP/Contents/Info.plist"
plutil -create xml1 "$PLIST"
set_string() { plutil -insert "$1" -string "$2" "$PLIST"; }
set_bool()   { plutil -insert "$1" -bool "$2" "$PLIST"; }
set_string CFBundleName "$NAME"
set_string CFBundleDisplayName "$NAME"
set_string CFBundleExecutable "$NAME"
set_string CFBundleIdentifier "$(json_get "$MANIFEST" .bundleId)"
set_string CFBundlePackageType APPL
set_string CFBundleShortVersionString "$(json_get "$MANIFEST" .version)"
set_string CFBundleVersion "$(json_get "$MANIFEST" .build)"
set_string CFBundleIconFile AppIcon
set_string LSMinimumSystemVersion "$(json_get "$MANIFEST" .minimumMacOS)"
set_string LSApplicationCategoryType "$CATEGORY"
set_string NSPrincipalClass NSApplication
set_bool   NSHighResolutionCapable YES
set_bool   LSUIElement "$([[ "$(json_get "$MANIFEST" .menuBarOnly)" == "true" ]] && echo YES || echo NO)"
set_string NSHumanReadableCopyright "Part of Slopapp. Free and open source under the MIT license."
set_string SlopappTagline "$(json_get "$MANIFEST" .tagline)"
# Extra keys (usage descriptions etc.) from app.json's optional "infoPlist" object.
if command -v jq >/dev/null 2>&1 && [[ -n "$(jq -r '.infoPlist // empty' "$MANIFEST")" ]]; then
  while IFS= read -r key; do
    plutil -replace "$key" -json "$(jq -c --arg k "$key" '.infoPlist[$k]' "$MANIFEST")" "$PLIST"
  done < <(jq -r '.infoPlist | keys[]' "$MANIFEST")
fi
plutil -lint -s "$PLIST"

# 5. Sign. Entitlements come from apps/<Name>/<Name>.entitlements when present.
SIGN_ARGS=(--force --options runtime --sign "$IDENTITY")
[[ "$IDENTITY" != "-" ]] && SIGN_ARGS+=(--timestamp)
[[ -f "$DIR/$NAME.entitlements" ]] && SIGN_ARGS+=(--entitlements "$DIR/$NAME.entitlements")
run_logged "$LOG_DIR/$NAME-sign.log" codesign "${SIGN_ARGS[@]}" "$APP"

# 6. Zip for distribution.
rm -f "$BUILD_DIR/$NAME.zip"
ditto -c -k --keepParent "$APP" "$BUILD_DIR/$NAME.zip"

ok "$NAME.app built ($CONFIG, $(lipo -archs "$APP/Contents/MacOS/$NAME")) -> ${APP#$ROOT/}"
