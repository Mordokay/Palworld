// Mirrors the iOS app's GameData.swift models (data/*.json shapes).

export interface PartnerSkill {
  name: string;
  icon: string;
  description: string;
}

export interface PalStats {
  hp: number | null;
  attack: number | null;
  defense: number | null;
  hpLv50Range: (number | null)[];
  attackLv50Range: (number | null)[];
  defenseLv50Range: (number | null)[];
}

export interface LearnedSkill {
  name: string;
  level: number | null;
}

export interface Pal {
  id: string;
  name: string;
  number: string;
  image: string;
  elements: string[];
  alphaTitle: string;
  partnerSkill: PartnerSkill;
  workSuitability: Record<string, number>;
  foodAmount: number | null;
  breedPower: number | null;
  drops: string[];
  alphaDrops: string[];
  farmingProduce: string[];
  habitatDay: string | null;
  habitatNight: string | null;
  saddleTech: string | null;
  saddleTechLevel: number | null;
  stats: PalStats | null;
  activeSkills: LearnedSkill[];
  paldeckEntry: string;
  categories: string[];
}

/** Shared shape of items.json and weapons.json. */
export interface Item {
  id: string;
  name: string;
  image: string;
  type: string;
  description: string;
  rarity: string;
  source: string[];
  craftMaterials: string[];
  weight: number | null;
  techTier: number | null;
  techPointsCost: number | null;
  workload: number | null;
  goldBuy: number | null;
  goldSell: number | null;
  nutrition: number | null;
  sanity: number | null;
  damage: number | null;
  durability: number | null;
  magazineSize: number | null;
  capturePower: number | null;
  categories: string[];
}

export interface Skill {
  id: string;
  name: string;
  skillType: string; // active | ex_active | passive
  element: string;
  description: string;
  power: number | null;
  cooldown: number | null;
  range: string | null;
  image: string | null;
  skillFruit: { name: string; icon: string } | null;
  exclusiveTo: string[];
  learnset: { pal: string; level: number | null }[];
  categories: string[];
}

export interface Location {
  id: string;
  name: string;
  image: string;
  type: string;
  region: string;
  inhabitants: string[];
  level: string;
  categories: string[];
}

export interface TableCell {
  t: string;
  l?: string | null; // link target (article id)
  img?: string | null; // icon filename
}

export interface ArticleTable {
  headers: string[];
  rows: TableCell[][];
}

export interface SectionImage {
  file: string;
  caption: string;
}

export interface ArticleSection {
  heading: string;
  level: number | null; // 2 = top-level wiki section, 3 = sub-section
  text: string;
  tables?: ArticleTable[] | null;
  images?: SectionImage[] | null;
}

export interface Article {
  id: string;
  title: string;
  kind: string; // pal | item | weapon | skill | location | article
  categories: string[];
  sections: ArticleSection[];
}

export interface TechEntry {
  level: number;
  name: string;
  image: string;
  structure: boolean;
  points: number;
  ancient: boolean;
}

export interface MapMarker {
  x: number; // normalized 0–1, west→east
  y: number; // normalized 0–1, north→south
  name?: string | null;
  pal?: string | null; // lowercased pal name (alpha/predator only)
}

export interface MapMarkerCategory {
  id: string;
  name: string;
  icon: string;
  markers: MapMarker[];
}

/** map_spawns.json: pal name (lowercased) → "day"/"night" → [[x, y], ...] */
export type SpawnData = Record<string, Record<string, [number, number][]>>;

/** All image subfolders under data/images/ — kind is only a lookup fallback. */
export type ImageKind =
  | "pals" | "items" | "weapons" | "skills" | "locations"
  | "ui" | "maps" | "articles" | "misc";
