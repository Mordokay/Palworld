import { defineConfig, type Plugin } from "vite";
import preact from "@preact/preset-vite";
import sirv from "sirv";
import { readdirSync } from "node:fs";
import { resolve } from "node:path";

// The iOS app and this web app share the repo's data/ directory (~230MB of
// JSON + wiki images + map tiles). It is never copied: in dev it is served
// at /data by middleware, and a production build reaches it at ../../data
// relative to web/dist/ (see src/data/paths.ts).
const DATA_DIR = resolve(import.meta.dirname, "../data");

function serveData(): Plugin {
  return {
    name: "serve-data",
    configureServer(server) {
      server.middlewares.use("/data", sirv(DATA_DIR, { dev: true, etag: true }));
    },
    configurePreviewServer(server) {
      server.middlewares.use("/data", sirv(DATA_DIR, { dev: true }));
    },
  };
}

// Browsers can't scan directories, so the iOS app's filename→subfolder image
// index (GameData.imageFolderIndex) becomes a generated manifest. Computed per
// request in dev so pipeline re-runs are picked up on reload; emitted as a
// real file into dist at build time.
function scanImages(): Record<string, string> {
  const root = resolve(DATA_DIR, "images");
  const index: Record<string, string> = {};
  for (const folder of readdirSync(root, { withFileTypes: true })) {
    if (!folder.isDirectory()) continue;
    for (const file of readdirSync(resolve(root, folder.name))) {
      if (!file.startsWith(".")) index[file] = folder.name;
    }
  }
  return index;
}

function imageManifest(): Plugin {
  const handler = (_req: unknown, res: import("node:http").ServerResponse) => {
    res.setHeader("content-type", "application/json");
    res.end(JSON.stringify(scanImages()));
  };
  return {
    name: "image-manifest",
    configureServer(server) {
      server.middlewares.use("/image-manifest.json", handler);
    },
    configurePreviewServer(server) {
      server.middlewares.use("/image-manifest.json", handler);
    },
    buildStart() {
      this.emitFile({
        type: "asset",
        fileName: "image-manifest.json",
        source: JSON.stringify(scanImages()),
      });
    },
  };
}

export default defineConfig({
  plugins: [preact(), serveData(), imageManifest()],
  base: "./",
});
