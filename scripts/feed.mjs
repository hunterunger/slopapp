#!/usr/bin/env node
// Generates the update feed (feed.json) that the Slopapp launcher reads: every built app
// with a zip (version, checksum, size, download URL...) plus the planned apps from the
// roadmap, shown as "coming soon". See docs/pipeline.md, "Releases and the feed".
//
//   node scripts/feed.mjs                    # build/*.zip -> build/feed.json + web/public/feed.json
//   node scripts/feed.mjs --strict           # fail if a zip's version doesn't match its app.json (CI)
//   node scripts/feed.mjs --zips <dir>       # read <Name>.zip files from <dir> instead of build/
//   node scripts/feed.mjs --only Awake,Clips # only these built apps are installable; other built apps are left out
//   node scripts/feed.mjs --no-planned       # leave out roadmap apps that aren't built
//   node scripts/feed.mjs --local <dir>      # a self-contained test feed: copies the zips and icons
//                                            # into <dir> and writes <dir>/feed.json with relative URLs
//   node scripts/feed.mjs --stdout           # print instead of writing
//
// Versions, build numbers and bundle ids come from each zip's own Info.plist (the truth of
// what users download); app.json is the cross-check. Download URLs point at the GitHub
// Release for that exact version: <repoUrl>/releases/download/<slug>-v<version>/<Name>.zip.
// Needs macOS (unzip + plutil), like the rest of the pipeline.
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { copyShotSet, shotSet } from "./shots-feed.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const readJSON = (p) => JSON.parse(readFileSync(p, "utf8"));
const rel = (p) => p.replace(root + "/", "");

// --- Arguments -------------------------------------------------------------------------
const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const option = (name) => {
  const i = args.indexOf(name);
  if (i === -1) return undefined;
  if (i + 1 >= args.length) die(`${name} needs a value`);
  return args[i + 1];
};
function die(message) {
  console.error(`feed: ${message}`);
  process.exit(1);
}
const warnings = [];
const warn = (message) => warnings.push(message);

const strict = flag("--strict");
const zipsDir = resolve(option("--zips") ?? join(root, "build"));
const localDir = option("--local") && resolve(option("--local"));
const only = option("--only")?.split(",").map((s) => s.trim()).filter(Boolean);
const includePlanned = !flag("--no-planned");

// --- Inputs ----------------------------------------------------------------------------
const brand = readJSON(join(root, "brand/brand.json"));
const roadmap = readJSON(join(root, "catalog/roadmap.json")).apps;
const feedUrl = brand.feedUrl || defaultFeedUrl(brand.repoUrl);
const teamId = brand.teamId || null;

/** https://github.com/<owner>/<repo> -> https://<owner>.github.io/<repo>/feed.json */
function defaultFeedUrl(repoUrl) {
  const match = /^https:\/\/github\.com\/([^/]+)\/([^/]+?)\/?$/.exec(repoUrl ?? "");
  if (!match) die(`brand.json has no feedUrl and repoUrl isn't a GitHub repo: ${repoUrl}`);
  return `https://${match[1].toLowerCase()}.github.io/${match[2]}/feed.json`;
}

const manifests = new Map(); // slug -> { app, dir }
for (const entry of readdirSync(join(root, "apps"), { withFileTypes: true })) {
  const manifest = join(root, "apps", entry.name, "app.json");
  if (entry.isDirectory() && existsSync(manifest)) {
    manifests.set(readJSON(manifest).slug, { app: readJSON(manifest), dir: join(root, "apps", entry.name) });
  }
}

// The launcher compiles its feed URL and team ID in (Info.plist), so they can't drift from brand.json.
const launcher = [...manifests.values()].find(({ app }) => app.slug === "slopapp");
if (launcher) {
  const plist = launcher.app.infoPlist ?? {};
  if (plist.SlopappFeedURL !== feedUrl) {
    die(`apps/Slopapp/app.json infoPlist.SlopappFeedURL (${plist.SlopappFeedURL}) must equal brand.json feedUrl (${feedUrl})`);
  }
  if ((plist.SlopappTeamID || null) !== teamId) {
    die(`apps/Slopapp/app.json infoPlist.SlopappTeamID (${plist.SlopappTeamID ?? "unset"}) must equal brand.json teamId (${teamId ?? "null"})`);
  }
}

// --- Zip inspection ----------------------------------------------------------------------
function infoPlistFromZip(zip, name) {
  let xml;
  try {
    xml = execFileSync("unzip", ["-p", zip, `${name}.app/Contents/Info.plist`], { maxBuffer: 1 << 20 });
  } catch {
    return null;
  }
  if (!xml.length) return null;
  try {
    return JSON.parse(execFileSync("plutil", ["-convert", "json", "-o", "-", "-"], { input: xml }).toString());
  } catch {
    return null;
  }
}

/** Uncompressed size: the last line of `unzip -l` is "<bytes>  <n> files". */
function installedSize(zip) {
  try {
    const lines = execFileSync("unzip", ["-l", zip], { maxBuffer: 16 << 20 }).toString().trim().split("\n");
    const total = Number.parseInt(lines.at(-1).trim().split(/\s+/)[0], 10);
    return Number.isFinite(total) ? total : undefined;
  } catch {
    return undefined;
  }
}

/** Notes for one version: the "## <version>" section of CHANGELOG.md, else app.json's releaseNotes. */
function releaseNotes(dir, app, version) {
  const changelog = join(dir, "CHANGELOG.md");
  if (existsSync(changelog)) {
    const text = readFileSync(changelog, "utf8");
    const sections = text.split(/^## /m).slice(1);
    const section = sections.find((s) => s.split("\n")[0].replace(/^\[?v?/, "").startsWith(version));
    if (section) return section.split("\n").slice(1).join("\n").trim();
  }
  return typeof app.releaseNotes === "string" ? app.releaseNotes : "";
}

const sha256 = (file) => createHash("sha256").update(readFileSync(file)).digest("hex");

const releaseAsset = (slug, version, file) =>
  `${brand.repoUrl}/releases/download/${slug}-v${version}/${file}`;

/** The app's store screenshots (docs/screenshots.md), copied next to a local test feed. */
function shotsFields(app, dir) {
  const set = shotSet(root, app, dir);
  if (!set) return {};
  if (localDir) copyShotSet(root, app.slug, set, localDir);
  return { shots: set.shots, shotsVersion: set.version };
}

function builtEntry(app, dir) {
  const zip = join(zipsDir, `${app.name}.zip`);
  if (!existsSync(zip)) {
    warn(`${app.name}: no ${rel(zip)}, listed as coming soon`);
    return null;
  }
  const info = infoPlistFromZip(zip, app.name);
  if (!info) die(`${rel(zip)} doesn't contain ${app.name}.app/Contents/Info.plist (damaged or wrong zip?)`);
  const bundleId = info.CFBundleIdentifier;
  const version = info.CFBundleShortVersionString;
  const build = Number.parseInt(info.CFBundleVersion, 10) || 0;
  if (bundleId !== app.bundleId) die(`${rel(zip)}: bundle id ${bundleId} != app.json ${app.bundleId}`);
  if (version !== app.version || String(build) !== String(app.build)) {
    const message = `${app.name}: zip is ${version} (${build}) but app.json says ${app.version} (${app.build})`;
    if (strict) die(message);
    warn(`${message}; the feed lists the zip's version`);
  }

  const iconPng = join(dirname(zip), `${app.name}-icon.png`);
  const hasIcon = existsSync(iconPng);
  let downloadUrl = releaseAsset(app.slug, version, `${app.name}.zip`);
  let iconUrl = hasIcon ? releaseAsset(app.slug, version, `${app.name}-icon.png`) : undefined;
  if (localDir) {
    copyFileSync(zip, join(localDir, `${app.name}.zip`));
    downloadUrl = `${app.name}.zip`;
    if (hasIcon) {
      copyFileSync(iconPng, join(localDir, `${app.name}-icon.png`));
      iconUrl = `${app.name}-icon.png`;
    }
  }

  return {
    slug: app.slug,
    name: app.name,
    tagline: app.tagline,
    category: app.category,
    replaces: app.replaces ?? [],
    icon: app.icon,
    menuBarOnly: Boolean(app.menuBarOnly),
    hub: Boolean(app.hub) || undefined,
    status: app.status,
    version,
    build,
    minimumMacOS: info.LSMinimumSystemVersion ?? app.minimumMacOS,
    bundleId,
    downloadUrl,
    iconUrl,
    sha256: sha256(zip),
    size: statSync(zip).size,
    installedSize: installedSize(zip),
    releaseNotes: releaseNotes(dir, app, version),
    ...shotsFields(app, dir),
  };
}

function plannedEntry(planned, dir) {
  return {
    slug: planned.slug,
    name: planned.name,
    tagline: planned.tagline,
    category: planned.category,
    replaces: planned.replaces ?? [],
    icon: planned.icon,
    menuBarOnly: Boolean(planned.menuBarOnly),
    hub: Boolean(planned.hub) || undefined,
    status: "planned",
    // A built app without a zip here (a local test feed) still has its screenshots.
    ...(dir ? shotsFields(planned, dir) : {}),
  };
}

// --- Assemble --------------------------------------------------------------------------
if (localDir) mkdirSync(localDir, { recursive: true });
const included = (name) => !only || only.includes(name);
const apps = [];
const seen = new Set();
for (const planned of roadmap) {
  seen.add(planned.slug);
  const built = manifests.get(planned.slug);
  if (built) {
    if (!included(built.app.name)) continue;
    const entry = builtEntry({ ...planned, ...built.app }, built.dir);
    if (entry) apps.push(entry);
    else if (includePlanned) apps.push(plannedEntry({ ...planned, ...built.app }, built.dir));
  } else if (includePlanned) {
    apps.push(plannedEntry(planned));
  }
}
for (const { app, dir } of manifests.values()) {
  if (seen.has(app.slug) || !included(app.name)) continue;
  const entry = builtEntry(app, dir);
  if (entry) apps.push(entry);
}

const feed = {
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  name: brand.name,
  feedUrl,
  apps,
};
const json = JSON.stringify(feed, null, 2) + "\n";

for (const message of warnings) console.error(`feed: warning: ${message}`);
if (flag("--stdout")) {
  process.stdout.write(json);
} else {
  const outputs = localDir
    ? [join(localDir, "feed.json")]
    : [join(root, "build/feed.json"), join(root, "web/public/feed.json")];
  for (const out of outputs) {
    mkdirSync(dirname(out), { recursive: true });
    writeFileSync(out, json);
  }
  const installable = apps.filter((a) => a.downloadUrl).length;
  console.log(`feed: ${apps.length} apps (${installable} installable) -> ${outputs.map(rel).join(", ")}`);
}
