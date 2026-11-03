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
  downloadUrl?: string;
};

export type Brand = {
  name: string;
  tagline: string;
  description: string;
  bundleIdPrefix: string;
  repoUrl: string;
  license: string;
  colors: Record<"forest" | "leaf" | "mint" | "cream" | "ember" | "ink", string>;
};

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
