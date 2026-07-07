import { render } from "preact";
import { useEffect, useRef, useState } from "preact/hooks";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import type { GameData } from "../data/load";
import { createMap, type PalMap } from "./setup";
import { LayerManager, type MarkerHit } from "./layers";
import { getLayers, getVisited, getVisitedFilter, useMapStore } from "./visited";
import { Callout } from "./Callout";
import { FilterPanel } from "./FilterPanel";

/**
 * Left pane: the Leaflet map. Leaflet owns its DOM, so this component mounts
 * it exactly once and drives layers/popups imperatively through refs; only
 * the floating UI (filter panel) is regular Preact.
 */
export function MapPane({ data }: { data: GameData }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const palMapRef = useRef<PalMap | null>(null);
  const layerMgrRef = useRef<LayerManager | null>(null);
  const [filterOpen, setFilterOpen] = useState(false);
  const storeVersion = useMapStore();

  useEffect(() => {
    if (!containerRef.current || palMapRef.current) return;
    const palMap = createMap(containerRef.current);
    palMapRef.current = palMap;

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
    };
  }, []);

  // push store changes (enabled layers / visited / filter) into Leaflet
  useEffect(() => {
    layerMgrRef.current?.apply(getLayers(), getVisited(), getVisitedFilter());
  }, [storeVersion]);

  return (
    <div class="map-wrap">
      <div ref={containerRef} class="map-container" />
      <button class="filter-toggle" onClick={() => setFilterOpen((open) => !open)}>
        {filterOpen ? "✕ Close" : "☰ Layers"}
      </button>
      {filterOpen && <FilterPanel data={data} />}
    </div>
  );
}
