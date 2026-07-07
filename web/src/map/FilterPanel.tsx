import type { GameData } from "../data/load";
import { CategoryIcon } from "./Callout";
import {
  getLayers, getVisited, getVisitedFilter, setVisitedFilter, toggleLayer, useMapStore,
} from "./visited";
import { visitedKeyFor } from "./layers";

/**
 * The palworld.gg-style layer list, as a floating panel over the map:
 * 3-way visited filter + per-layer toggles with seen/total counts.
 * (Pal spawn search joins in M6.)
 */
export function FilterPanel({ data }: { data: GameData }) {
  useMapStore();
  const enabled = getLayers();
  const visited = getVisited();
  const filter = getVisitedFilter();

  return (
    <div class="filter-panel">
      <div class="filter-section-title">Visited</div>
      <div class="segmented">
        {(["all", "unvisited", "visited"] as const).map((value) => (
          <button
            key={value}
            class={filter === value ? "segment active" : "segment"}
            onClick={() => setVisitedFilter(value)}
          >
            {value.charAt(0).toUpperCase() + value.slice(1)}
          </button>
        ))}
      </div>
      <div class="filter-hint">
        Mark points as visited from their map callout — collected effigies, opened chests…
      </div>
      <div class="filter-section-title">Layers</div>
      <div class="filter-layers">
        {data.markerCategories.map((category) => {
          const seen = category.markers.filter((m) =>
            visited.has(visitedKeyFor(category.id, m)),
          ).length;
          const total = category.markers.length;
          const complete = seen > 0 && seen === total;
          const on = enabled.has(category.id);
          return (
            <button key={category.id} class="filter-row" onClick={() => toggleLayer(category.id)}>
              <CategoryIcon icon={category.icon} side={24} />
              <span class="filter-name">{category.name}</span>
              <span class={`filter-count ${complete ? "complete" : ""}`}>
                {seen > 0 ? `${seen}/${total}` : total}
              </span>
              <span class={`filter-check ${on ? "on" : ""}`}>{on ? "●" : "○"}</span>
            </button>
          );
        })}
      </div>
    </div>
  );
}
