# Palworld Trainer — Web Companion

A dual-pane web version of the iOS app's Map and Library tabs: interactive
Palpagos Islands map on the left, wiki-mirrored Library on the right.
Clicking an alpha/predator marker opens that pal's page; a pal page's
"Show spawn points on the Map" overlays its day/night spawn dots.

Everything reads the repo's shared `../data/` directory (JSON + images +
map tiles) — nothing is copied or duplicated, and pipeline refreshes are
picked up on browser reload in dev mode.

## Run (dev — the normal way)

```sh
cd web
npm install   # first time only
npm run dev   # → http://localhost:5173
```

## Run without node (after a build)

```sh
cd web && npm run build     # writes web/dist/, bakes image-manifest.json
cd .. && python3 -m http.server 8000
# open http://localhost:8000/web/dist/
```

A server is always required (`file://` can't fetch the data files).
Rebuild after a pipeline refresh if you use this mode — dev mode always
reads fresh data.

## Notes

- Visited-POI tracking lives in localStorage under the **same keys and
  formats** the iOS app uses in AppStorage (`mapVisited` as `|`-joined
  `cat:x:y`, `mapLayers`, `mapVisitedFilter`) — no sync between devices,
  but an export/import later needs no translation.
- Map/library state is in the URL hash (`#/entity/anubis?spawn=anubis&side=night`),
  so a copied URL reproduces both panes.
- Personal project: the map/wiki data stances from the main README apply —
  ask Pocketpair / credit the wiki before ever sharing this.
