import type { GameData } from "../data/load";
import type { Article } from "../data/types";

// The seven browse sections — ports enum LibrarySection (LibraryView.swift).

export interface LibrarySection {
  id: string;
  title: string;
  icon: string;
  color: string;
  count: (data: GameData) => number;
}

const isGameVersion = (a: Article): boolean => a.categories.includes("Game Versions");

/** Ints extracted from a title, for natural version ordering ("v0.6.5"). */
function versionKey(title: string): number[] {
  return (title.match(/\d+/g) ?? []).map(Number);
}

export function guidesArticles(data: GameData): Article[] {
  return data.articles
    .filter((a) => a.kind === "article" && !isGameVersion(a))
    .sort((a, b) => a.title.localeCompare(b.title));
}

export function updateArticles(data: GameData): Article[] {
  return data.articles
    .filter(isGameVersion)
    .sort((a, b) => {
      const ka = versionKey(a.title);
      const kb = versionKey(b.title);
      for (let i = 0; i < Math.max(ka.length, kb.length); i++) {
        const d = (kb[i] ?? -1) - (ka[i] ?? -1); // newest first
        if (d !== 0) return d;
      }
      return 0;
    });
}

export const librarySections: LibrarySection[] = [
  { id: "pals", title: "Pals", icon: "🐾", color: "#34c759", count: (d) => d.pals.length },
  { id: "items", title: "Items", icon: "📦", color: "#ff9500", count: (d) => d.items.length },
  { id: "weapons", title: "Weapons", icon: "🛡️", color: "#ff3b30", count: (d) => d.weapons.length },
  { id: "skills", title: "Skills", icon: "✨", color: "#af52de", count: (d) => d.skills.length },
  { id: "locations", title: "Locations", icon: "🗺️", color: "#30b0c7", count: (d) => d.locations.length },
  { id: "guides", title: "Guides & World", icon: "📘", color: "#007aff", count: (d) => guidesArticles(d).length },
  { id: "updates", title: "Update History", icon: "🕘", color: "#8e8e93", count: (d) => updateArticles(d).length },
];
