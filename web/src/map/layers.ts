import L from "leaflet";
import type { GameData } from "../data/load";
import type { MapMarker, MapMarkerCategory } from "../data/types";
import { imageURL, mapIconURL } from "../data/images";
import type { PalMap } from "./setup";

export const visitedKeyFor = (categoryID: string, m: MapMarker): string =>
  `${categoryID}:${m.x}:${m.y}`;

export interface MarkerHit {
  category: MapMarkerCategory;
  marker: MapMarker;
  latlng: L.LatLng;
}

// iOS size hierarchy (MarkerOverlayView): base 34pt, egg/chest/effigy/note
// ×0.7, dungeon/sealedRealm ×0.75. Dense layers collapse to dots when far out.
const BASE_SIDE = 30;
const SMALL_LAYERS = new Set(["egg", "chest", "effigy", "note"]);
const MID_LAYERS = new Set(["dungeon", "sealedRealm"]);
const DENSE_COUNT = 300;
const DOT_MIN_ZOOM = 4; // dense layers draw as dots below this zoom

function iconSide(categoryID: string): number {
  if (SMALL_LAYERS.has(categoryID)) return BASE_SIDE * 0.7;
  if (MID_LAYERS.has(categoryID)) return BASE_SIDE * 0.75;
  return BASE_SIDE;
}

/**
 * Owns one lazily-built Leaflet LayerGroup per marker category and keeps them
 * in sync with the store (enabled layers, visited set, visited filter).
 * Purely imperative — Leaflet markers are not reactive.
 */
export class LayerManager {
  private groups = new Map<string, L.LayerGroup>();
  /** visited key → the marker's Leaflet layer, for single-marker restyles */
  private refs = new Map<string, L.CircleMarker | L.Marker>();
  private canvasRenderer = L.canvas({ padding: 0.5 });
  private enabled = new Set<string>();
  private visited: ReadonlySet<string> = new Set();
  private visitedFilter = "all";
  private dotsMode: boolean;

  constructor(
    private palMap: PalMap,
    private data: GameData,
    private onMarkerClick: (hit: MarkerHit) => void,
  ) {
    this.dotsMode = palMap.map.getZoom() < DOT_MIN_ZOOM;
    palMap.map.on("zoomend", () => {
      const dots = palMap.map.getZoom() < DOT_MIN_ZOOM;
      if (dots === this.dotsMode) return;
      this.dotsMode = dots;
      for (const category of this.data.markerCategories) {
        if (category.markers.length > DENSE_COUNT && this.groups.has(category.id)) {
          this.rebuild(category);
        }
      }
    });
  }

  apply(enabled: ReadonlySet<string>, visited: ReadonlySet<string>, visitedFilter: string): void {
    const filterChanged = visitedFilter !== this.visitedFilter;
    const changedKeys = symmetricDiff(this.visited, visited);
    this.visitedFilter = visitedFilter;
    this.visited = new Set(visited);

    for (const category of this.data.markerCategories) {
      const want = enabled.has(category.id);
      const group = this.groups.get(category.id);
      if (want && !this.enabled.has(category.id)) {
        (group ?? this.build(category)).addTo(this.palMap.map);
      } else if (!want && this.enabled.has(category.id) && group) {
        group.remove();
      }
    }
    this.enabled = new Set(enabled);

    if (filterChanged) {
      // membership changes — rebuild everything that was ever built
      for (const category of this.data.markerCategories) {
        if (this.groups.has(category.id)) this.rebuild(category);
      }
    } else {
      // same filter: restyle just the toggled markers in place
      for (const key of changedKeys) this.restyle(key);
    }
  }

  private build(category: MapMarkerCategory): L.LayerGroup {
    const group = L.layerGroup();
    this.groups.set(category.id, group);
    this.fill(category, group);
    return group;
  }

  private rebuild(category: MapMarkerCategory): void {
    const group = this.groups.get(category.id);
    if (!group) return;
    for (const [key] of this.refs) {
      if (key.startsWith(category.id + ":")) this.refs.delete(key);
    }
    group.clearLayers();
    this.fill(category, group);
  }

  private fill(category: MapMarkerCategory, group: L.LayerGroup): void {
    const dots = this.dotsMode && category.markers.length > DENSE_COUNT;
    for (const marker of category.markers) {
      const key = visitedKeyFor(category.id, marker);
      const seen = this.visited.has(key);
      if (this.visitedFilter === "unvisited" && seen) continue;
      if (this.visitedFilter === "visited" && !seen) continue;
      const latlng = this.palMap.toLatLng(marker.x, marker.y);
      const layer = dots
        ? this.makeDot(latlng, seen)
        : this.makeIconMarker(category, marker, latlng, seen);
      layer.on("click", () => this.onMarkerClick({ category, marker, latlng }));
      this.refs.set(key, layer);
      group.addLayer(layer);
    }
  }

  private makeDot(latlng: L.LatLng, seen: boolean): L.CircleMarker {
    return L.circleMarker(latlng, {
      renderer: this.canvasRenderer,
      radius: 3.5,
      fillColor: seen ? "#34c759" : "#ffd60a",
      fillOpacity: 1,
      color: "rgba(255,255,255,0.85)",
      weight: 1,
    });
  }

  private makeIconMarker(
    category: MapMarkerCategory,
    marker: MapMarker,
    latlng: L.LatLng,
    seen: boolean,
  ): L.Marker {
    return L.marker(latlng, {
      icon: this.icon(category, marker, seen),
      keyboard: false,
    });
  }

  private icon(category: MapMarkerCategory, marker: MapMarker, seen: boolean): L.DivIcon {
    // alpha/predator markers are the pal's own artwork in a ringed circle
    if (marker.pal) {
      const pal = this.data.palByLowerName.get(marker.pal);
      const side = BASE_SIDE + 6;
      const ring = seen ? "visited" : category.id;
      return L.divIcon({
        className: "",
        html: `<div class="pal-marker ring-${ring}">${
          pal ? `<img src="${imageURL(pal.image, "pals")}" alt="">` : ""
        }</div>`,
        iconSize: [side, side],
        iconAnchor: [side / 2, side / 2],
      });
    }
    const side = iconSide(category.id);
    return L.divIcon({
      className: "",
      html: `<img class="poi-icon${seen ? " visited" : ""}" src="${mapIconURL(category.icon)}" alt="">`,
      iconSize: [side, side],
      iconAnchor: [side / 2, side / 2],
    });
  }

  /** Restyle a single marker after its visited state flipped (filter "all"). */
  private restyle(key: string): void {
    const layer = this.refs.get(key);
    if (!layer) return;
    const categoryID = key.split(":", 1)[0]!;
    const category = this.data.markerCategories.find((c) => c.id === categoryID);
    if (!category) return;
    const seen = this.visited.has(key);
    if (layer instanceof L.CircleMarker) {
      layer.setStyle({ fillColor: seen ? "#34c759" : "#ffd60a" });
    } else {
      const [, x, y] = key.split(":");
      const marker = category.markers.find((m) => String(m.x) === x && String(m.y) === y);
      if (marker) layer.setIcon(this.icon(category, marker, seen));
    }
  }
}

function symmetricDiff(a: ReadonlySet<string>, b: ReadonlySet<string>): string[] {
  const out: string[] = [];
  for (const k of a) if (!b.has(k)) out.push(k);
  for (const k of b) if (!a.has(k)) out.push(k);
  return out;
}
