#!/usr/bin/env node
// Merges catalog/roadmap.json with every apps/<Name>/app.json into one catalog
// for the website. Built apps (those with an app.json) override roadmap entries.
//
//   node scripts/catalog.mjs            -> writes web/src/generated/catalog.json
//   node scripts/catalog.mjs --stdout   -> prints it instead
import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { shotSet } from "./shots-feed.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const readJSON = (p) => JSON.parse(readFileSync(p, "utf8"));

const brand = readJSON(join(root, "brand/brand.json"));
const roadmap = readJSON(join(root, "catalog/roadmap.json")).apps;

const built = new Map();
const appsDir = join(root, "apps");
for (const dir of existsSync(appsDir) ? readdirSync(appsDir, { withFileTypes: true }) : []) {
  const manifest = join(appsDir, dir.name, "app.json");
  if (!dir.isDirectory() || !existsSync(manifest)) continue;
  const app = readJSON(manifest);
  // Store screenshots (docs/screenshots.md), for apps that have a set.
  const set = shotSet(root, app, join(appsDir, dir.name));
  built.set(app.slug, { ...app, dir: `apps/${dir.name}`, ...(set && { shots: set.shots, shotsVersion: set.version }) });
}

// Each app is released under its own tag, <slug>-v<version> (see .github/workflows/release.yml),
// so link to that tag. "releases/latest" would point at whichever app shipped last.
const downloadUrl = (app) =>
  `${brand.repoUrl}/releases/download/${app.slug}-v${app.version}/${app.name}.zip`;
const apps = roadmap.map((planned) => {
  const app = built.get(planned.slug);
  built.delete(planned.slug);
  return app ? { ...planned, ...app, downloadUrl: downloadUrl(app) } : { ...planned, status: "planned" };
});
// Apps built without a roadmap entry still show up.
for (const app of built.values()) {
  apps.push({ priority: 3, ...app, downloadUrl: downloadUrl(app) });
}
for (const app of apps) delete app.spec;

const catalog = { generatedAt: new Date().toISOString().slice(0, 10), brand, apps };
const json = JSON.stringify(catalog, null, 2) + "\n";

if (process.argv.includes("--stdout")) {
  process.stdout.write(json);
} else {
  const out = join(root, "web/src/generated/catalog.json");
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, json);
  console.log(`catalog: ${apps.length} apps (${apps.filter((a) => a.status !== "planned").length} built) -> ${out.replace(root + "/", "")}`);
}
