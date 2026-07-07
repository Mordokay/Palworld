// In dev, vite middleware serves the repo's data/ at /data. A production
// build lives in web/dist/, so the shared directory sits at ../../data when
// the repo root is served statically (python3 -m http.server).
export const DATA_BASE = import.meta.env.DEV ? "/data" : "../../data";

export const MANIFEST_URL = import.meta.env.DEV
  ? "/image-manifest.json"
  : "./image-manifest.json";
