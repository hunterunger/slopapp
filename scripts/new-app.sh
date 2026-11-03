#!/usr/bin/env bash
# Scaffolds a new app from its catalog/roadmap.json entry.
#
#   scripts/new-app.sh <slug> [--no-verify]
#
# Creates apps/<Name>/ from templates/app, writes app.json from the roadmap entry,
# vendors the Lucide icon, then runs the tests to prove the scaffold builds.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

SLUG="${1:-}"; [[ -n "$SLUG" ]] || die "usage: scripts/new-app.sh <slug> [--no-verify]"
VERIFY=1; [[ "${2:-}" == "--no-verify" ]] && VERIFY=0
LUCIDE_VERSION="1.66.0"

# Pull the roadmap entry out as shell-safe variables.
ENTRY_SH="$(python3 - "$ROOT/catalog/roadmap.json" "$SLUG" <<'PY'
import json, shlex, sys
apps = json.load(open(sys.argv[1]))["apps"]
entry = next((a for a in apps if a["slug"] == sys.argv[2]), None)
if entry is None:
    sys.exit(f"no roadmap entry with slug '{sys.argv[2]}'. Add one to catalog/roadmap.json first.")
replaces = entry.get("replaces", [])
fields = {
    "NAME": entry["name"],
    "TAGLINE": entry["tagline"],
    "ICON": entry["icon"],
    "MENUBAR": "true" if entry.get("menuBarOnly") else "false",
    "REPLACES": " and ".join(", ".join(replaces[:-1]) and [", ".join(replaces[:-1]), replaces[-1]] or replaces) or "nothing yet",
    "SPEC": entry.get("spec", "TODO: write the spec in catalog/roadmap.json."),
}
for key, value in fields.items():
    print(f"export {key}={shlex.quote(value)}")
PY
)" || die "couldn't read roadmap entry for '$SLUG'"
eval "$ENTRY_SH"

[[ "$NAME" =~ ^[A-Z][A-Za-z0-9]*$ ]] || die "app name '$NAME' must be UpperCamelCase letters/digits (it becomes a Swift module)"
DIR="$APPS_DIR/$NAME"
[[ ! -e "$DIR" ]] || die "apps/$NAME already exists"

say "Scaffolding $NAME ($SLUG) -> apps/$NAME"
cp -R "$ROOT/templates/app" "$DIR"
# Rename __NAME__ in paths (deepest first so parents rename after children).
find "$DIR" -depth -name '*__NAME__*' | while IFS= read -r path; do
  mv "$path" "$(dirname "$path")/$(basename "$path" | sed "s/__NAME__/$NAME/g")"
done
# Keep the right app entry point.
if [[ "$MENUBAR" == "true" ]]; then KEEP=menubar; DROP=window; else KEEP=window; DROP=menubar; fi
rm "$DIR/Sources/$NAME/${NAME}App.$DROP.swift"
mv "$DIR/Sources/$NAME/${NAME}App.$KEEP.swift" "$DIR/Sources/$NAME/${NAME}App.swift"
# Fill placeholders. perl reads values from the environment, so any characters are safe.
find "$DIR" -type f \( -name '*.swift' -o -name '*.md' \) -print0 | xargs -0 perl -pi -e '
  s/__NAME__/$ENV{NAME}/g; s/__TAGLINE__/$ENV{TAGLINE}/g;
  s/__REPLACES__/$ENV{REPLACES}/g; s/__SPEC__/$ENV{SPEC}/g;'

# app.json: roadmap fields + build metadata.
python3 - "$ROOT/catalog/roadmap.json" "$ROOT/brand/brand.json" "$SLUG" "$DIR/app.json" <<'PY'
import json, sys
roadmap, brand, slug, out = sys.argv[1:]
entry = next(a for a in json.load(open(roadmap))["apps"] if a["slug"] == slug)
prefix = json.load(open(brand))["bundleIdPrefix"]
manifest = {
    "slug": slug,
    "name": entry["name"],
    "tagline": entry["tagline"],
    "replaces": entry.get("replaces", []),
    "category": entry.get("category", "Utilities"),
    "icon": entry["icon"],
    "menuBarOnly": bool(entry.get("menuBarOnly")),
    "status": "alpha",
    "version": "0.1.0",
    "build": 1,
    "minimumMacOS": "14.0",
    "bundleId": f"{prefix}.{slug}",
}
open(out, "w").write(json.dumps(manifest, indent=2) + "\n")
PY

# Vendor the Lucide glyph (pinned) so builds work offline.
curl -fsSL "https://unpkg.com/lucide-static@$LUCIDE_VERSION/icons/$ICON.svg" -o "$DIR/Icon.svg" \
  || die "couldn't download Lucide icon '$ICON' (check the name at lucide.dev/icons)"

ok "created apps/$NAME"
if [[ $VERIFY -eq 1 ]]; then
  "$ROOT/scripts/test.sh" "$NAME"
fi
echo
echo "Next: build the core in apps/$NAME/Sources/${NAME}Core, test it, then run scripts/check.sh $NAME."
