import raw from "@/generated/catalog.json";

// Typed view of src/generated/catalog.json, which `node ../scripts/catalog.mjs`
// builds from brand/brand.json, catalog/roadmap.json and apps/*/app.json.

export type AppStatus = "planned" | "alpha" | "beta" | "stable";

export type CatalogApp = {
  slug: string;
  name: string;
  tagline: string;
  replaces: string[];
  category: string;
  /** Lucide icon name (lucide.dev). */
  icon: string;
  /** 1 = up first (the owner's favourites), 2 = next, 3 = later. */
  priority: 1 | 2 | 3;
  /** One of the owner's favourite Setapp apps. */
  favourite?: boolean;
  size?: "S" | "M" | "L";
  menuBarOnly?: boolean;
  status: AppStatus;
  version?: string;
  /** The release's zip. The launcher installs from it too. */
  downloadUrl?: string;
  /** The release's disk image, for apps that ship one (the launcher). Preferred for downloads. */
  dmgUrl?: string;
  /** Store screenshots (docs/screenshots.md), for beta+ apps that have a set. */
  shots?: Shot[];
  /** "<app version>-<showcase version>": changes whenever the set is retaken. */
  shotsVersion?: string;
};

/** One store screenshot. Paths are relative to the site root (prefix the base path). */
export type Shot = {
  id: string;
  title: string;
  caption: string;
  width: number;
  height: number;
  light: string;
  dark: string;
  light1x: string;
  dark1x: string;
};

export type Brand = {
  name: string;
  tagline: string;
  description: string;
  bundleIdPrefix: string;
  repoUrl: string;
  license: string;
  /** The Nordic herbarium palette (brand.json `nordic`): app icons, the website, the launcher. */
  nordic: Record<NordicColour, string> & {
    /** Each app category's colour, by name (the launcher's sidebar and category pages). */
    categories: Record<string, NordicColour>;
  };
};

export type NordicColour =
  | "birch" | "oat" | "charcoal" | "night" | "pine"
  | "sage" | "clay" | "ochre" | "fjord" | "heather" | "rosewood" | "lingonberry";

export type Catalog = {
  generatedAt: string;
  brand: Brand;
  apps: CatalogApp[];
};

export const catalog = raw as Catalog;
export const brand = catalog.brand;

export const isBuilt = (app: CatalogApp) => app.status !== "planned" && Boolean(app.downloadUrl);

/** By priority, built apps first within each priority, then roadmap (build) order. */
export const apps = [...catalog.apps].sort(
  (a, b) => a.priority - b.priority || Number(isBuilt(b)) - Number(isBuilt(a)),
);

export const priorityGroups = [
  { priority: 1, title: "Up first", note: "The everyday essentials. Building these now." },
  { priority: 2, title: "Next", note: "Smaller tools, coming right after." },
  { priority: 3, title: "Later", note: "On the list. Bigger, or less urgent." },
] as const;
