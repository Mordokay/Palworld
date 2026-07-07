import L from "leaflet";
import type { PalMap } from "./setup";

/**
 * Day/night spawn dots for one pal, on a dedicated canvas renderer (up to
 * ~2k points). Ports the iOS spawn overlay: amber day dots, indigo night.
 */
export class SpawnOverlay {
  private group = L.layerGroup();
  private renderer = L.canvas({ padding: 0.5 });

  constructor(private palMap: PalMap) {}

  show(points: [number, number][], side: string, fly: boolean): void {
    this.group.clearLayers();
    const color = side === "night" ? "#8a86ff" : "#ffb020";
    let bounds: L.LatLngBounds | null = null;
    for (const [x, y] of points) {
      const latlng = this.palMap.toLatLng(x, y);
      bounds = bounds ? bounds.extend(latlng) : L.latLngBounds(latlng, latlng);
      this.group.addLayer(
        L.circleMarker(latlng, {
          renderer: this.renderer,
          radius: 4,
          fillColor: color,
          fillOpacity: 0.9,
          color: "rgba(255,255,255,0.9)",
          weight: 1,
        }),
      );
    }
    this.group.addTo(this.palMap.map);
    if (fly && bounds) {
      this.palMap.map.flyToBounds(bounds.pad(0.2), { maxZoom: 6, duration: 0.8 });
    }
  }

  clear(): void {
    this.group.remove();
    this.group.clearLayers();
  }
}
