import { DATA_BASE } from "./paths";
import { loadImageManifest } from "./images";
import type {
  Article, Item, Location, MapMarkerCategory, Pal, Skill, SpawnData, TechEntry,
} from "./types";

/** All game data, loaded once at startup. Ports GameData.load(). */
export interface GameData {
  pals: Pal[];
  items: Item[];
  weapons: Item[];
  skills: Skill[];
  locations: Location[];
  technology: TechEntry[];
  articles: Article[];
  markerCategories: MapMarkerCategory[];

  palByID: Map<string, Pal>;
  articleByID: Map<string, Article>;
  /** items and weapons share one index (same shape); first-wins like iOS */
  itemByID: Map<string, Item>;
  skillByID: Map<string, Skill>;
  /** lowercased entity/article title → article id, for cross-linking */
  idByName: Map<string, string>;
  palByLowerName: Map<string, Pal>;
}

async function fetchJSON<T>(file: string): Promise<T> {
  const res = await fetch(`${DATA_BASE}/${file}`);
  if (!res.ok) throw new Error(`Failed to load ${file}: ${res.status}`);
  return res.json();
}

export async function loadGameData(): Promise<GameData> {
  const [pals, items, weapons, skills, locations, technology, articles, markerFile] =
    await Promise.all([
      fetchJSON<Pal[]>("pals.json"),
      fetchJSON<Item[]>("items.json"),
      fetchJSON<Item[]>("weapons.json"),
      fetchJSON<Skill[]>("skills.json"),
      fetchJSON<Location[]>("locations.json"),
      fetchJSON<TechEntry[]>("technology.json"),
      fetchJSON<Article[]>("articles.json"),
      fetchJSON<{ categories: MapMarkerCategory[] }>("map_markers.json"),
      loadImageManifest(),
    ]);

  const idByName = new Map<string, string>();
  for (const article of articles) idByName.set(article.title.toLowerCase(), article.id);

  const itemByID = new Map<string, Item>();
  for (const item of [...items, ...weapons]) {
    if (!itemByID.has(item.id)) itemByID.set(item.id, item);
  }

  return {
    pals, items, weapons, skills, locations, technology, articles,
    markerCategories: markerFile.categories,
    palByID: new Map(pals.map((p) => [p.id, p])),
    articleByID: new Map(articles.map((a) => [a.id, a])),
    itemByID,
    skillByID: new Map(skills.map((s) => [s.id, s])),
    idByName,
    palByLowerName: new Map(pals.map((p) => [p.name.toLowerCase(), p])),
  };
}

// map_spawns.json is 1.7MB — loaded lazily the first time spawns are shown.
let spawnsPromise: Promise<SpawnData> | null = null;

export function loadSpawns(): Promise<SpawnData> {
  spawnsPromise ??= fetchJSON<SpawnData>("map_spawns.json");
  return spawnsPromise;
}

/**
 * Resolve a decorated reference like "1-3 Wool (100%)", "40 Refined Ingot"
 * or "Ring of Resistance +1 - 3%" to the linked entity's article id.
 * Ported literally from GameData.resolveEntityName — the regex order matters.
 */
export function resolveEntityName(data: GameData, raw: string): string | null {
  let s = raw.trim();
  s = s.replace(/\s*\([^)]*\)\s*$/, "");
  s = s.replace(/^[\d,.\-–x× ]+/, "");
  const direct = data.idByName.get(s.toLowerCase());
  if (direct) return direct;
  // drop trailing decorations: " - (2-3) 100%", " +1 - 3%", " 100%"
  const cut = s.indexOf(" - ");
  if (cut !== -1) s = s.slice(0, cut);
  s = s.replace(/\s*(\+\d+|\d+%|\(\d[^)]*\))\s*$/, "");
  return data.idByName.get(s.trim().toLowerCase()) ?? null;
}

/** Display name (sans decorations) for a drops/materials line. */
export function strippedName(raw: string): string {
  return raw.trim().replace(/\s*\([^)]*\)\s*$/, "");
}
