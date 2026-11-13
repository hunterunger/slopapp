#!/usr/bin/env bash
# A local, throwaway feed for testing the Slopapp launcher without touching real
# Applications folders, the real Trash or the internet. Everything lives in /tmp/slopapp-test.
#
#   apps/Slopapp/test-feed.sh setup      # fresh feed (Testbed 1.0.0, Sandbox 1.0.0, Awake 0.1.0, planned apps) on localhost
#   apps/Slopapp/test-feed.sh launch     # open build/Slopapp.app against it (prints the env it uses)
#   apps/Slopapp/test-feed.sh bump       # publish the next version of Testbed and Sandbox (1.1.0, then 1.2.0...): two updates
#   apps/Slopapp/test-feed.sh bad-sha    # publish the next Testbed with a wrong sha256 in the feed
#   apps/Slopapp/test-feed.sh bad-sig    # publish the next Testbed, modified after signing
#   apps/Slopapp/test-feed.sh corrupt    # publish the next Testbed as a damaged zip (checksum matches the damage)
#   apps/Slopapp/test-feed.sh offline    # stop the server (the feed and downloads become unreachable)
#   apps/Slopapp/test-feed.sh serve      # start it again
#   apps/Slopapp/test-feed.sh env        # print the environment variables
#   apps/Slopapp/test-feed.sh clean      # stop the server, unregister test apps, delete /tmp/slopapp-test
#
# "Testbed" and "Sandbox" are copies of Awake with their own bundle ids (app.slopapp.testbed,
# app.slopapp.sandbox): every install, update and failure scenario uses them. Awake itself stays
# at the version in build/ (0.1.0), so the launcher shows build/Awake.app as "installed
# elsewhere". Never publish a newer Awake, Switchboard, Clips... here: a newer test copy with a
# real app's bundle id makes macOS open the test copy instead of the real one. `clean`
# unregisters every test copy from LaunchServices.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
T=/tmp/slopapp-test
FEED="$T/feed"
WORK="$T/work"
PORT="${SLOPAPP_TEST_PORT:-8765}"
URL="http://localhost:$PORT/feed.json"
PIDFILE="$T/server.pid"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

die() { echo "test-feed: $*" >&2; exit 1; }

env_lines() {
  cat <<EOF
SLOPAPP_FEED_URL=$URL
SLOPAPP_INSTALL_DIR=$T/Applications
SLOPAPP_TRASH_DIR=$T/Trash
SLOPAPP_LIBRARY_DIR=$T/Library
EOF
}

serve() {
  stop_server
  mkdir -p "$FEED"
  # Bind to loopback only.
  nohup python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$FEED" >"$T/server.log" 2>&1 &
  echo $! >"$PIDFILE"
  for _ in $(seq 1 30); do
    curl -fsS "$URL" >/dev/null 2>&1 && { echo "serving $URL"; return 0; }
    sleep 0.1
  done
  die "server didn't start (see $T/server.log)"
}

stop_server() {
  if [[ -f "$PIDFILE" ]]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
  fi
}

# make_variant <src.app> <name> <bundle id> <version> <build> <out dir>: re-versioned, re-signed (ad-hoc) copy, zipped.
make_variant() {
  local src="$1" name="$2" id="$3" version="$4" build="$5" out="$6"
  local stage="$WORK/$name-$version"
  rm -rf "$stage" && mkdir -p "$stage" "$out"
  ditto "$src" "$stage/$name.app"
  local plist="$stage/$name.app/Contents/Info.plist"
  plutil -replace CFBundleIdentifier -string "$id" "$plist"
  plutil -replace CFBundleName -string "$name" "$plist"
  plutil -replace CFBundleDisplayName -string "$name" "$plist"
  plutil -replace CFBundleShortVersionString -string "$version" "$plist"
  plutil -replace CFBundleVersion -string "$build" "$plist"
  codesign --force --options runtime --sign - "$stage/$name.app" >/dev/null 2>&1
  rm -f "$out/$name.zip"
  ditto -c -k --keepParent "$stage/$name.app" "$out/$name.zip"
  echo "$stage/$name.app"
}

# set_entry <slug> <name> <bundle id> <version> <build> <zip file name> [sha override]
set_entry() {
  local slug="$1" name="$2" id="$3" version="$4" build="$5" zip="$6" sha="${7:-}"
  [[ -n "$sha" ]] || sha="$(shasum -a 256 "$FEED/$zip" | cut -d' ' -f1)"
  local size; size="$(stat -f%z "$FEED/$zip")"
  node - "$FEED/feed.json" "$slug" "$name" "$id" "$version" "$build" "$zip" "$sha" "$size" <<'JS'
const fs = require("fs");
const [file, slug, name, id, version, build, zip, sha, size] = process.argv.slice(2);
const feed = JSON.parse(fs.readFileSync(file, "utf8"));
let entry = feed.apps.find((a) => a.slug === slug);
if (!entry) {
  entry = { slug, name, tagline: `A copy of Awake for testing (${name}).`, category: "Utilities",
            replaces: ["Nothing"], menuBarOnly: true, status: "alpha", minimumMacOS: "14.0" };
  feed.apps.splice(1, 0, entry);
}
Object.assign(entry, { version, build: Number(build), bundleId: id, downloadUrl: zip, sha256: sha,
                       size: Number(size), releaseNotes: `Test release ${version}.\n- Changed: the version number.` });
  if (name !== "Awake") entry.iconUrl = "Awake-icon.png";
feed.generatedAt = new Date().toISOString();
fs.writeFileSync(file, JSON.stringify(feed, null, 2) + "\n");
JS
  echo "feed: $name $version ($zip, sha256 ${sha:0:12}…)"
}

setup() {
  [[ -f "$ROOT/build/Awake.zip" && -d "$ROOT/build/Awake.app" ]] || die "build Awake first: scripts/bundle.sh Awake"
  stop_server
  rm -rf "$FEED" "$WORK" "$T/Applications" "$T/Trash" "$T/Library"
  mkdir -p "$FEED" "$WORK" "$T/Applications" "$T/Trash"
  # Real feed generator, limited to Awake (+ every planned app as "coming soon").
  node "$ROOT/scripts/feed.mjs" --only Awake --local "$FEED"
  # Awake is listed (so build/Awake.app shows as installed elsewhere) but not downloadable:
  # a second registered copy of a real app confuses LaunchServices.
  node -e 'const f=process.argv[1],fs=require("fs"),j=JSON.parse(fs.readFileSync(f));
    for (const a of j.apps) if (a.slug==="awake") { delete a.downloadUrl; delete a.sha256; }
    fs.writeFileSync(f, JSON.stringify(j,null,2)+"\n")' "$FEED/feed.json"
  make_variant "$ROOT/build/Awake.app" Sandbox app.slopapp.sandbox 1.0.0 1 "$FEED" >/dev/null
  set_entry sandbox Sandbox app.slopapp.sandbox 1.0.0 1 Sandbox.zip
  make_variant "$ROOT/build/Awake.app" Testbed app.slopapp.testbed 1.0.0 1 "$FEED" >/dev/null
  set_entry testbed Testbed app.slopapp.testbed 1.0.0 1 Testbed.zip
  # Testbed and Sandbox are menu bar apps; keep their icons out of a crowded menu bar
  # (macOS hides status items that don't fit, including Slopapp's own).
  for id in app.slopapp.sandbox app.slopapp.testbed; do
    defaults write "$id" showMenuBarIcon -bool false
  done
  # Settings + data for "Also remove its settings and data".
  for id in app.slopapp.sandbox app.slopapp.testbed; do
    mkdir -p "$T/Library/Application Support/$id" "$T/Library/Preferences" "$T/Library/Caches/$id"
    echo '{"test": true}' >"$T/Library/Application Support/$id/data.json"
    plutil -create xml1 "$T/Library/Preferences/$id.plist"
  done
  serve
}

# next_version <slug>: the feed's version for <slug> with the minor number bumped, and build + 1.
next_version() {
  node -e 'const j=JSON.parse(require("fs").readFileSync(process.argv[1]));
    const a=j.apps.find(x=>x.slug===process.argv[2]); const [M,m]=(a.version||"1.0.0").split(".").map(Number);
    console.log(`${M}.${m+1}.0 ${(a.build||1)+1}`)' "$FEED/feed.json" "$1"
}

bump() {
  # Each run publishes the next version (1.1.0, 1.2.0, ...) of both test apps.
  local v b
  for pair in "sandbox Sandbox" "testbed Testbed"; do
    set -- $pair
    read -r v b < <(next_version "$1")
    make_variant "$ROOT/build/Awake.app" "$2" "app.slopapp.$1" "$v" "$b" "$FEED" >/dev/null
    set_entry "$1" "$2" "app.slopapp.$1" "$v" "$b" "$2.zip"
  done
}

bad_sha() {
  local v b; read -r v b < <(next_version testbed)
  make_variant "$ROOT/build/Awake.app" Testbed app.slopapp.testbed "$v" "$b" "$WORK/out" >/dev/null
  cp "$WORK/out/Testbed.zip" "$FEED/Testbed-$v.zip"
  set_entry testbed Testbed app.slopapp.testbed "$v" "$b" "Testbed-$v.zip" "$(printf '0%.0s' $(seq 1 64))"
}

bad_sig() {
  local v b; read -r v b < <(next_version testbed)
  local app; app="$(make_variant "$ROOT/build/Awake.app" Testbed app.slopapp.testbed "$v" "$b" "$WORK/out")"
  # Change a signed file after signing, then re-zip: the checksum matches, the signature doesn't.
  printf 'tampered' >>"$app/Contents/Resources/AppIcon.icns"
  rm -f "$FEED/Testbed-$v.zip"
  ditto -c -k --keepParent "$app" "$FEED/Testbed-$v.zip"
  set_entry testbed Testbed app.slopapp.testbed "$v" "$b" "Testbed-$v.zip"
}

corrupt() {
  local v b; read -r v b < <(next_version testbed)
  head -c 200000 /dev/urandom >"$FEED/Testbed-$v.zip"
  set_entry testbed Testbed app.slopapp.testbed "$v" "$b" "Testbed-$v.zip"
}

clean() {
  stop_server
  if [[ -d "$T" ]]; then
    find "$T" -name '*.app' -maxdepth 4 -type d 2>/dev/null | while IFS= read -r app; do
      "$LSREGISTER" -u "$app" >/dev/null 2>&1 || true
    done
    rm -rf "$T"
  fi
  for id in app.slopapp.sandbox app.slopapp.testbed; do
    defaults delete "$id" >/dev/null 2>&1 || true
  done
  # The launcher's own test-only state (kept apart from the real catalog's).
  defaults delete app.slopapp.slopapp "lastCheck:$URL" >/dev/null 2>&1 || true
  defaults delete app.slopapp.slopapp "recentUpdates:dev" >/dev/null 2>&1 || true
  rm -f "$HOME/Library/Application Support/app.slopapp.slopapp/"feed-cache-dev-*.json
  echo "cleaned $T"
}

case "${1:-}" in
  setup) setup ;;
  bump) bump ;;
  bad-sha) bad_sha ;;
  bad-sig) bad_sig ;;
  corrupt) corrupt ;;
  offline) stop_server; echo "server stopped: $URL is unreachable" ;;
  serve) serve ;;
  env) env_lines ;;
  launch)
    [[ -d "$ROOT/build/Slopapp.app" ]] || die "build it first: scripts/bundle.sh Slopapp"
    args=()
    while IFS= read -r line; do args+=(--env "$line"); done < <(env_lines)
    env_lines
    # --direct: a separate copy, so an installed Slopapp that is running isn't handed the env instead.
    "$ROOT/scripts/drive" launch "$ROOT/build/Slopapp.app" --direct "${args[@]}" "${@:2}"
    ;;
  clean) clean ;;
  *) sed -n '2,20p' "$0"; exit 1 ;;
esac
