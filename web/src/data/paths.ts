// Where the shared data/ directory and image manifest live at runtime.
//
// - Dev: vite middleware serves the repo's data/ at /data.
// - Production default: ../../data, so a build in web/dist/ reaches the
//   repo's data/ when the repo root is served statically
//   (python3 -m http.server from the repo root).
// - Deployed to a subfolder (e.g. mordokay.com/palworld): pass absolute
//   paths at build time so they resolve regardless of trailing slash —
//   VITE_DATA_BASE=/palworld/data VITE_MANIFEST_URL=/palworld/image-manifest.json
export const DATA_BASE = import.meta.env.DEV
  ? "/data"
  : (import.meta.env.VITE_DATA_BASE ?? "../../data");

export const MANIFEST_URL = import.meta.env.DEV
  ? "/image-manifest.json"
  : (import.meta.env.VITE_MANIFEST_URL ?? "./image-manifest.json");
