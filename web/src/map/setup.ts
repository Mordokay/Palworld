import L from "leaflet";
import { mapTileURLTemplate } from "../data/images";

// The world is a 16384px square raster (tile pyramid z0–6 at 256px/tile,
// shared with the iOS app). Marker coordinates are normalized 0–1 with the
// origin at the top-left (west, north) — the same convention as the JSON.

export const WORLD_SIZE = 16384;
export const MAX_NATIVE_ZOOM = 6;

export interface PalMap {
  map: L.Map;
  /** normalized (0–1, y-down) → LatLng. Use this everywhere; never hand-build LatLngs. */
  toLatLng: (x: number, y: number) => L.LatLng;
  bounds: L.LatLngBounds;
}

export function createMap(el: HTMLElement): PalMap {
  const map = L.map(el, {
    crs: L.CRS.Simple,
    minZoom: 1,
    maxZoom: 8, // 2 levels of CSS overzoom past the native tiles
    zoomSnap: 0.5,
    zoomControl: true,
    attributionControl: false,
  });

  const toLatLng = (x: number, y: number): L.LatLng =>
    map.unproject([x * WORLD_SIZE, y * WORLD_SIZE], MAX_NATIVE_ZOOM);

  const bounds = L.latLngBounds(toLatLng(0, 0), toLatLng(1, 1));
  map.setMaxBounds(bounds.pad(0.02));

  L.tileLayer(mapTileURLTemplate(), {
    tileSize: 256,
    minZoom: 1,
    maxNativeZoom: MAX_NATIVE_ZOOM,
    maxZoom: 8,
    noWrap: true,
    bounds,
  }).addTo(map);

  map.fitBounds(bounds);

  return { map, toLatLng, bounds };
}
