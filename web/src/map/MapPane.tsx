import { render } from "preact";
import { useEffect, useRef, useState } from "preact/hooks";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import type { GameData } from "../data/load";
import { loadSpawns } from "../data/load";
import { imageURL } from "../data/images";
import { navigate, setQueryParams, useRoute } from "../library/router";
import { ElementChip } from "../library/entity/shared";
import { createMap, type PalMap } from "./setup";
import { LayerManager, type MarkerHit } from "./layers";
import { SpawnOverlay } from "./spawns";
import { getLayers, getVisited, getVisitedFilter, useMapStore } from "./visited";
import { Callout } from "./Callout";
import { FilterPanel } from "./FilterPanel";

/**
 * Left pane: the Leaflet map. Leaflet owns its DOM, so this component mounts
 * it exactly once and drives layers/spawns/popups imperatively through refs;
 * only the floating UI (filter panel, spawn legend) is regular Preact.
 */
export function MapPane({ data }: { data: GameData }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const palMapRef = useRef<PalMap | null>(null);
  const layerMgrRef = useRef<LayerManager | null>(null);
  const spawnOverlayRef = useRef<SpawnOverlay | null>(null);
  const lastFlownRef = useRef<string | null>(null);
  const [filterOpen, setFilterOpen] = useState(false);
  const storeVersion = useMapStore();
  const route = useRoute();

  // spawn state rides in the URL: ?spawn=<lowercased name>&side=day|night
  const spawnName = route.query.get("spawn");
  const requestedSide = route.query.get("side") ?? "day";
  const [spawnSides, setSpawnSides] = useState<Record<string, [number, number][]> | null>(null);
  const spawnPal = spawnName ? data.palByLowerName.get(spawnName) : undefined;

  useEffect(() => {
    if (!containerRef.current || palMapRef.current) return;
    const palMap = createMap(containerRef.current);
    palMapRef.current = palMap;
    spawnOverlayRef.current = new SpawnOverlay(palMap);

    layerMgrRef.current = new LayerManager(palMap, data, (hit: MarkerHit) => {
      const container = document.createElement("div");
      render(
        <Callout
          data={data}
          hit={hit}
          onJump={() => palMap.map.flyTo(hit.latlng, Math.max(palMap.map.getZoom(), 5))}
        />,
        container,
      );
      L.popup({ closeButton: true, className: "pal-popup", offset: [0, -14] })
        .setLatLng(hit.latlng)
        .setContent(container)
        .openOn(palMap.map);
    });

    if (import.meta.env.DEV) {
      (window as unknown as Record<string, unknown>).__palmap = palMap;
    }
    return () => {
      palMap.map.remove();
      palMapRef.current = null;
      layerMgrRef.current = null;
      spawnOverlayRef.current = null;
    };
  }, []);

  // push store changes (enabled layers / visited / filter) into Leaflet
  useEffect(() => {
    layerMgrRef.current?.apply(getLayers(), getVisited(), getVisitedFilter());
  }, [storeVersion]);

  // load the requested pal's spawn points (map_spawns.json is lazy, 1.7MB)
  useEffect(() => {
    if (!spawnName) {
      spawnOverlayRef.current?.clear();
      setSpawnSides(null);
      lastFlownRef.current = null;
      return;
    }
    let cancelled = false;
    loadSpawns().then((all) => {
      if (!cancelled) setSpawnSides(all[spawnName] ?? {});
    });
    return () => {
      cancelled = true;
    };
  }, [spawnName]);

  // draw the dots; fly only when a NEW pal is requested, not on side toggles
  useEffect(() => {
    if (!spawnName || !spawnSides) return;
    const side = spawnSides[requestedSide]?.length
      ? requestedSide
      : requestedSide === "day" ? "night" : "day";
    const points = spawnSides[side] ?? [];
    const fly = lastFlownRef.current !== spawnName;
    lastFlownRef.current = spawnName;
    spawnOverlayRef.current?.show(points, side, fly);
  }, [spawnName, spawnSides, requestedSide]);

  const hasDay = !!spawnSides?.day?.length;
  const hasNight = !!spawnSides?.night?.length;
  const activeSide = spawnSides?.[requestedSide]?.length
    ? requestedSide
    : requestedSide === "day" ? "night" : "day";

  return (
    <div class="map-wrap">
      <div ref={containerRef} class="map-container" />
      <button class="filter-toggle" onClick={() => setFilterOpen((open) => !open)}>
        {filterOpen ? "✕ Close" : "☰ Layers"}
      </button>
      {filterOpen && <FilterPanel data={data} />}
      {spawnPal && spawnSides && (
        <div class="spawn-legend">
          <img class="spawn-legend-pal" src={imageURL(spawnPal.image, "pals")} alt="" />
          <div class="spawn-legend-text">
            <div class="callout-title">{spawnPal.name}</div>
            {hasDay || hasNight ? (
              <div class="chips-row left">
                {spawnPal.elements.map((element) => (
                  <ElementChip key={element} element={element} small />
                ))}
              </div>
            ) : (
              <div class="callout-subtitle">No wild spawn points — breeding or dungeons only.</div>
            )}
          </div>
          {hasDay && hasNight && (
            <>
              <button
                class={`side-button ${activeSide === "day" ? "active-day" : ""}`}
                title="Day spawns"
                onClick={() => setQueryParams({ side: "day" })}
              >
                ☀️
              </button>
              <button
                class={`side-button ${activeSide === "night" ? "active-night" : ""}`}
                title="Night spawns"
                onClick={() => setQueryParams({ side: "night" })}
              >
                🌙
              </button>
            </>
          )}
          <button
            class="callout-button"
            title="Open in Library"
            onClick={() => navigate(["entity", spawnPal.id])}
          >
            📖
          </button>
          <button
            class="callout-button"
            title="Hide spawn points"
            onClick={() => setQueryParams({ spawn: null, side: null })}
          >
            ✕
          </button>
        </div>
      )}
    </div>
  );
}
