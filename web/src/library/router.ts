import { useEffect, useState } from "preact/hooks";

// Hash-based routing so the app works from any static file server without
// rewrites: #/section/pals, #/entity/anubis, #/element/fire, #/tech-tree...
// Map state rides in the hash query (?spawn=anubis&side=day) so a copied URL
// reproduces both panes.

export interface Route {
  path: string[]; // e.g. ["entity", "anubis"]
  query: URLSearchParams;
}

export function parseHash(hash: string): Route {
  const raw = hash.replace(/^#\/?/, "");
  const qIndex = raw.indexOf("?");
  const pathPart = qIndex === -1 ? raw : raw.slice(0, qIndex);
  const queryPart = qIndex === -1 ? "" : raw.slice(qIndex + 1);
  return {
    path: pathPart.split("/").filter(Boolean).map(decodeURIComponent),
    query: new URLSearchParams(queryPart),
  };
}

export function buildHash(path: string[], query?: URLSearchParams): string {
  const p = "#/" + path.map(encodeURIComponent).join("/");
  const q = query?.toString();
  return q ? `${p}?${q}` : p;
}

export function currentRoute(): Route {
  return parseHash(window.location.hash);
}

/** Navigate to a new library route, preserving the map's query state. */
export function navigate(path: string[]): void {
  window.location.hash = buildHash(path, currentRoute().query);
}

/** Update only the map's query state, preserving the library path. */
export function setQueryParams(update: Record<string, string | null>): void {
  const route = currentRoute();
  for (const [key, value] of Object.entries(update)) {
    if (value === null) route.query.delete(key);
    else route.query.set(key, value);
  }
  // replace, not push: camera/layer tweaks shouldn't pollute back-history
  history.replaceState(null, "", buildHash(route.path, route.query));
  window.dispatchEvent(new HashChangeEvent("hashchange"));
}

export function useRoute(): Route {
  const [route, setRoute] = useState<Route>(currentRoute);
  useEffect(() => {
    const onChange = () => setRoute(currentRoute());
    window.addEventListener("hashchange", onChange);
    return () => window.removeEventListener("hashchange", onChange);
  }, []);
  return route;
}
