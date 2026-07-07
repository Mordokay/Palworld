import type { GameData } from "../data/load";
import type { Article } from "../data/types";

/**
 * Global search over article titles — ports LibraryView.searchResults:
 * contains-filter, prefix matches first, then shorter titles, capped at 60.
 */
export function searchArticles(data: GameData, query: string): Article[] {
  const q = query.toLowerCase();
  return data.articles
    .filter((a) => a.title.toLowerCase().includes(q))
    .sort((a, b) => {
      const ap = a.title.toLowerCase().startsWith(q);
      const bp = b.title.toLowerCase().startsWith(q);
      if (ap !== bp) return ap ? -1 : 1;
      return a.title.length - b.title.length;
    })
    .slice(0, 60);
}
