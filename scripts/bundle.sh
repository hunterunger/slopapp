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
# Stamp the real SDK version into the binary. SwiftPM's driver can tell the linker the SDK
# is the deployment target (14.0), and macOS 26+ then runs the app in its old compatibility
# look: small window buttons, older controls. The deployment target stays as it is.
# Re-stamped after linking with vtool: linker flags don't survive every SwiftPM build
# backend (Xcode 26's universal builds hand them to clang, which rejects them).
MIN_MACOS="$(json_get "$MANIFEST" .minimumMacOS)"; MIN_MACOS="${MIN_MACOS:-14.0}"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
say "Building $NAME ($CONFIG, macOS $MIN_MACOS+, SDK $SDK_VERSION)"
run_logged "$LOG_DIR/$NAME-build.log" swift build --package-path "$DIR" -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_PATH="$(swift build --package-path "$DIR" -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"
stamped_sdk() { otool -arch all -l "$1" | awk '/LC_BUILD_VERSION/{f=1} f && $1=="sdk" {print $2; f=0}' | sort -V | head -1; }

# 2. Assemble the .app.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/$NAME" "$APP/Contents/MacOS/$NAME"
if [[ "$(stamped_sdk "$APP/Contents/MacOS/$NAME")" != "$SDK_VERSION" ]]; then
  vtool -set-build-version macos "$MIN_MACOS" "$SDK_VERSION" -replace -output "$APP/Contents/MacOS/$NAME.stamped" "$APP/Contents/MacOS/$NAME"
  mv "$APP/Contents/MacOS/$NAME.stamped" "$APP/Contents/MacOS/$NAME"
fi
# Fail rather than ship the compatibility look again.
STAMPED_SDK="$(stamped_sdk "$APP/Contents/MacOS/$NAME")"
[[ "${STAMPED_SDK%%.*}" -ge 26 ]] || die "$NAME is stamped with SDK ${STAMPED_SDK:-?} (want 26+): macOS would show it in the old compatibility look"
# SwiftPM resource bundles (from `resources:` in Package.swift), if any.
shopt -s nullglob
for bundle in "$BIN_PATH"/*.bundle "$BIN_PATH"/*.resources; do
  cp -R "$bundle" "$APP/Contents/Resources/"
done
shopt -u nullglob

# 3. Icon: AppIcon.icon (an Icon Composer document: layered Liquid Glass icon on macOS 26+,
#    with a flat .icns fallback for older systems) wins; then AppIcon.svg (finished full-art
#    icon); otherwise Icon.svg (a Lucide glyph on the forest tile).
ICON_NAME=""
if [[ -d "$DIR/AppIcon.icon" ]]; then
  ICON_TMP="$(mktemp -d)"
  run_logged "$LOG_DIR/$NAME-icon.log" xcrun actool --compile "$ICON_TMP" --app-icon AppIcon --platform macosx \
    --minimum-deployment-target "$MIN_MACOS" --output-partial-info-plist "$ICON_TMP/partial.plist" \
    "$DIR/AppIcon.icon"
  cp "$ICON_TMP/AppIcon.icns" "$ICON_TMP/Assets.car" "$APP/Contents/Resources/"
  rm -rf "$ICON_TMP"
  ICON_NAME="AppIcon"
  ICTOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
  if [[ -x "$ICTOOL" ]]; then
    "$ICTOOL" "$DIR/AppIcon.icon" --export-image --output-file "$BUILD_DIR/$NAME-icon.png" \
      --platform macOS --rendition Default --width 512 --height 512 --scale 2 >/dev/null 2>&1 || true
  fi
elif [[ -f "$DIR/AppIcon.svg" ]]; then
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
[[ -n "$ICON_NAME" ]] && set_string CFBundleIconName "$ICON_NAME"
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
