import type { GameData } from "../../data/load";
import { librarySections } from "../sections";
import { navigate } from "../router";

/** Library root: the seven browse sections with counts. */
export function BrowseHome({ data }: { data: GameData }) {
  return (
    <div class="browse-home">
      {librarySections.map((section) => (
        <button
          key={section.id}
          class="browse-row"
          onClick={() => navigate(["section", section.id])}
        >
          <span class="browse-icon" style={{ background: section.color + "26", color: section.color }}>
            {section.icon}
          </span>
          <span class="browse-title">{section.title}</span>
          <span class="browse-count">{section.count(data)}</span>
          <span class="browse-chevron">›</span>
        </button>
      ))}
    </div>
  );
}
