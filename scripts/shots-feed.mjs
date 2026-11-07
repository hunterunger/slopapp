// Store screenshots in the catalog and the feed (docs/screenshots.md). Shared by
// scripts/catalog.mjs (website) and scripts/feed.mjs (launcher).
//
// An app has a set when it's beta or later, has apps/<Name>/showcase.json, and
// scripts/shots.sh has written web/public/shots/<slug>/manifest.json with every image.
// Titles and captions come from showcase.json (editable without retaking anything); file
// names, sizes and versions from the manifest. Paths are relative to the site root, which
// is also where the feed lives, so they resolve against either.
import { copyFileSync, existsSync, mkdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const readJSON = (p) => JSON.parse(readFileSync(p, "utf8"));
const released = new Set(["beta", "stable"]);

/**
 * @returns {{ version: string, shots: object[] } | undefined}
 *   version: "<app version>-<showcase version>" (changes whenever the set is retaken)
 */
export function shotSet(root, app, appDir) {
  if (!released.has(app.status)) return undefined;
  const showcasePath = join(appDir, "showcase.json");
  const shotsDir = join(root, "web/public/shots", app.slug);
  const manifestPath = join(shotsDir, "manifest.json");
  if (!existsSync(showcasePath) || !existsSync(manifestPath)) return undefined;
  const showcase = readJSON(showcasePath);
  const manifest = readJSON(manifestPath);
  const byId = new Map((manifest.shots ?? []).map((m) => [m.id, m]));
  const shots = [];
  for (const shot of showcase.shots ?? []) {
    const files = byId.get(shot.id);
    if (!files) continue;
    const names = [files.light, files.dark, files.light1x, files.dark1x];
    if (!names.every((name) => name && existsSync(join(shotsDir, name)))) continue;
    const path = (name) => `shots/${app.slug}/${name}`;
    shots.push({
      id: shot.id,
      title: shot.title,
      caption: shot.caption,
      width: files.width,
      height: files.height,
      light: path(files.light),
      dark: path(files.dark),
      light1x: path(files.light1x),
      dark1x: path(files.dark1x),
    });
  }
  if (shots.length === 0) return undefined;
  return { version: `${manifest.appVersion}-${manifest.showcaseVersion}`, shots };
}

/** Copies a set's images into <dir>/shots/<slug>/ (self-contained test feeds). */
export function copyShotSet(root, slug, set, dir) {
  const out = join(dir, "shots", slug);
  mkdirSync(out, { recursive: true });
  for (const shot of set.shots) {
    for (const key of ["light", "dark", "light1x", "dark1x"]) {
      copyFileSync(join(root, "web/public", shot[key]), join(dir, shot[key]));
    }
  }
}
