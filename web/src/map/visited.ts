import { useEffect, useReducer } from "preact/hooks";

// Map UI state persisted in localStorage under the SAME keys and formats the
// iOS app uses in AppStorage (PalMapView.swift): a future export/import can
// move completion progress between devices without translation.
//   mapVisited        "cat:x:y" keys joined by "|"  (raw doubles — JS and
//                     Swift both print shortest round-trip, so keys match)
//   mapLayers         enabled category ids joined by ","
//   mapVisitedFilter  "all" | "unvisited" | "visited"

const DEFAULT_LAYERS = "fastTravel,tower,alpha";

let visited = new Set<string>(
  (localStorage.getItem("mapVisited") ?? "").split("|").filter(Boolean),
);
let layers = new Set<string>(
  (localStorage.getItem("mapLayers") ?? DEFAULT_LAYERS).split(",").filter(Boolean),
);
let visitedFilter = localStorage.getItem("mapVisitedFilter") ?? "all";

// bumped on every change; effects and hooks key off it
let version = 0;
const listeners = new Set<() => void>();

function changed(): void {
  version++;
  for (const fn of listeners) fn();
}

export function getVisited(): ReadonlySet<string> {
  return visited;
}

export function isVisited(key: string): boolean {
  return visited.has(key);
}

export function toggleVisited(key: string): void {
  if (!visited.delete(key)) visited.add(key);
  localStorage.setItem("mapVisited", [...visited].join("|"));
  changed();
}

export function getLayers(): ReadonlySet<string> {
  return layers;
}

export function toggleLayer(id: string): void {
  if (!layers.delete(id)) layers.add(id);
  localStorage.setItem("mapLayers", [...layers].sort().join(","));
  changed();
}

export function getVisitedFilter(): string {
  return visitedFilter;
}

export function setVisitedFilter(filter: string): void {
  visitedFilter = filter;
  localStorage.setItem("mapVisitedFilter", filter);
  changed();
}

/** Re-renders the component whenever any map state changes. */
export function useMapStore(): number {
  const [, force] = useReducer((c: number) => c + 1, 0);
  useEffect(() => {
    const listener = () => force(undefined);
    listeners.add(listener);
    return () => {
      listeners.delete(listener);
    };
  }, []);
  return version;
}
