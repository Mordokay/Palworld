import { useEffect, useState } from "preact/hooks";
import type { GameData } from "../data/load";
import { loadSpawns } from "../data/load";
import type { SpawnData } from "../data/types";
import { imageURL } from "../data/images";
import { setQueryParams, useRoute } from "../library/router";
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
      <PalSpawnSearch data={data} />
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

/** Search a pal to overlay its spawn points (iOS "Pal spawn areas" section). */
function PalSpawnSearch({ data }: { data: GameData }) {
  const [query, setQuery] = useState("");
  const [spawns, setSpawns] = useState<SpawnData | null>(null);
  const route = useRoute();
  const currentName = route.query.get("spawn");
  const current = currentName ? data.palByLowerName.get(currentName) : undefined;

  useEffect(() => {
    loadSpawns().then(setSpawns);
  }, []);

  const q = query.trim().toLowerCase();
  const matches = q && spawns
    ? data.pals
        .filter((p) => p.name.toLowerCase().includes(q) && spawns[p.name.toLowerCase()])
        .slice(0, 8)
    : [];

  return (
    <>
      <div class="filter-section-title">Pal spawn areas</div>
      {current && (
        <div class="spawn-current">
          <img src={imageURL(current.image, "pals")} width={26} height={26} alt="" />
          <span class="filter-name">{current.name}</span>
          <button
            class="spawn-clear"
            onClick={() => setQueryParams({ spawn: null, side: null })}
          >
            Clear
          </button>
        </div>
      )}
      <input
        class="search-field wide"
        type="search"
        placeholder="Search a pal…"
        value={query}
        onInput={(e) => setQuery((e.target as HTMLInputElement).value)}
      />
      {matches.map((pal) => (
        <button
          key={pal.id}
          class="filter-row"
          onClick={() => {
            setQueryParams({ spawn: pal.name.toLowerCase(), side: null });
            setQuery("");
          }}
        >
          <img src={imageURL(pal.image, "pals")} width={26} height={26} alt="" />
          <span class="filter-name">{pal.name}</span>
        </button>
      ))}
    </>
  );
}
