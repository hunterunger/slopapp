import raw from "@/generated/herbarium.json";

// Herbarium icons and botanical prints, exported from each app's AppIcon.icon by
// `python3 ../scripts/icons/export_web.py` (see brand/ICONS.md).

export type Specimen = {
  app: string;
  /** Botanical name of the app's plate, e.g. "Coffea arabica". */
  plant: string;
  common: string;
  /** Plate number in Köhler's Medizinal-Pflanzen. */
  plate: string | null;
  /** The icon's tile colour. */
  tile: string;
  icon: string;
  iconDark: string;
  /** White-on-transparent plate, used as a CSS mask. */
  print: string;
  source: string | null;
};

const specimens = raw as Record<string, Specimen>;

export const specimenFor = (slug: string): Specimen | undefined => specimens[slug];

/** Public files need the base path when the site is served from a subpath (GitHub Pages). */
export const asset = (path: string) => `${process.env.NEXT_BASE_PATH ?? ""}${path}`;

export const nordic = {
  sage: "#8ea58b",
  pine: "#3f5e4e",
  clay: "#c4704f",
  ochre: "#d2a04c",
  fjord: "#5d7e9a",
  heather: "#8c7ea0",
  rosewood: "#a9665c",
} as const;
