#!/usr/bin/env python3
"""Mirror the palworld.gg interactive map: tiles + all marker coordinates.

Produces:
  data/map/tiles/{z}/{x}/{y}.png   zoom 0-6 tile pyramid (16k effective px)
  data/map/icons/*.png             marker icons
  data/map_markers.json            fixed markers (fast travel, towers, camps,
                                   dungeons, sealed realms, alphas, predators,
                                   eggs, chests, effigies, notes, skill fruits)
  data/map_spawns.json             per-pal day/night wild spawn points

Coordinates are normalized 0..1 (x = west->east, y = north->south) using the
site's own linear world transform:
    nx = (worldX + 1_006_000) / 1_458_000      (north component)
    ny = (worldY +   745_000) / 1_458_000      (east component)
    x, y = ny, 1 - nx

The marker data is embedded in the site's JS chunks with minified variable
names that change on redeploy, so every extraction is verified against
expected counts and loudly reported — eyeball the summary after a refresh.
"""

import json
import re
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

BASE = "https://palworld.gg"
DATA = Path(__file__).resolve().parent.parent / "data"
MAPDIR = DATA / "map"
UA = {"User-Agent": "Mozilla/5.0 (personal Palworld study app; single mirror run)"}

WORLD_MIN_X, WORLD_MIN_Y, WORLD_SPAN = -1_006_000, -745_000, 1_458_000
MAX_ZOOM = 6


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


def norm(world_x: float, world_y: float) -> tuple[float, float]:
    nx = (world_x - WORLD_MIN_X) / WORLD_SPAN
    ny = (world_y - WORLD_MIN_Y) / WORLD_SPAN
    return round(ny, 4), round(1 - nx, 4)


# ---------------------------------------------------------------- chunks

def discover_chunks() -> dict:
    html = fetch(f"{BASE}/map").decode()
    entry = re.search(r'/_nuxt/(entry\.[\w-]+\.js)', html).group(1)
    entry_src = fetch(f"{BASE}/_nuxt/{entry}").decode()
    map_chunk = re.search(r'(map\.[\w-]+\.js)', entry_src).group(1)
    map_src = fetch(f"{BASE}/_nuxt/{map_chunk}").decode()
    imports = set(re.findall(r'import\("\./([\w.-]+\.js)"\)', map_src))
    return {"map": map_src,
            "eagles": sorted(i for i in imports if i.startswith("map-spawn-eagle")),
            "pals": sorted(i for i in imports if i.startswith("pals-very-lite"))}


def parse_balanced(s: str, start: int) -> tuple[str, int]:
    depth, i = 0, start
    while True:
        if s[i] == "[":
            depth += 1
        elif s[i] == "]":
            depth -= 1
            if depth == 0:
                return s[start:i + 1], i
        i += 1


def pair_arrays(src: str) -> list[list[tuple[float, float]]]:
    """All [[x,y],...] literals (however wrapped), largest count first."""
    out, seen = [], set()
    for m in re.finditer(r'[=(]\s*\[\s*\[\s*-?[\d.]', src):
        br = src.index("[", m.start())
        if br in seen:
            continue
        seen.add(br)
        body, _ = parse_balanced(src, br)
        pts = [(float(a), float(b))
               for a, b in re.findall(r'\[(-?[\d.eE]+),(-?[\d.eE]+)\]', body)]
        if len(pts) >= 5:
            out.append(pts)
    return out


def spawn_var_literals(src: str) -> dict:
    """var -> {'day': [(x,y)...], 'night': [...]} for every spawn object."""
    out = {}
    for m in re.finditer(r'(\w+)=\{dayTimeLocations:\{locations:', src):
        var = m.group(1)
        day_start = src.index("[", m.end() - 1)
        day_body, end = parse_balanced(src, day_start)
        night_key = src.index("nightTimeLocations", end)
        night_start = src.index("[", night_key)
        night_body, _ = parse_balanced(src, night_start)
        def pts(body):
            return [(float(x), float(y)) for x, y, _ in
                    re.findall(r'\{X:(-?[\d.eE]+),Y:(-?[\d.eE]+),Z:(-?[\d.eE]+)\}', body)]
        out[var] = {"day": pts(day_body), "night": pts(night_body)}
    return out


def codename_mapping(src: str) -> dict:
    """The big {codename: spawnVar} object (plain + boss_ + predator_ keys)."""
    best = {}
    for m in re.finditer(r'\{(?:\w+:\w+,){30,}', src):
        body = src[m.start() + 1:src.index("}", m.start())]
        entries = dict(re.findall(r'(\w+):(\w+)', body))
        if len(entries) > len(best) and any(k.startswith("boss_") for k in entries):
            best = entries
    return best


def bpclass_names(chunk_src: str) -> dict:
    """BPClass codename -> display name."""
    return {bp: name for name, bp in
            re.findall(r'OverrideNameTextID:"([^"]+)",BPClass:"([^"]+)"', chunk_src)}


def fast_travel_names(eagle_srcs: list[str]) -> dict:
    """FTPointN -> English statue name (pick the chunk that speaks English)."""
    for src in eagle_srcs:
        if "Windswept Hills" not in src:
            continue
        var_text = dict(re.findall(
            r'(\w+)=\{TextData:\{LocalizedString:(`[^`]*`|"[^"]*")\}\}', src))
        aliases = dict(re.findall(r'(\w+) as (FTPoint\d+)', src))
        return {ft: var_text[v].strip('`"').replace("\r\n", " — ")
                for v, ft in aliases.items() if v in var_text}
    return {}


# ---------------------------------------------------------------- extraction

def extract(chunks: dict) -> tuple[dict, dict]:
    src = chunks["map"]
    warnings = []

    arrays = pair_arrays(src)
    by_len = {len(a): a for a in arrays}
    # expected sizes as of 2026-07; on redeploy the closest match wins + warning
    expected = {"egg": 1748, "chest": 1283, "effigy": 605, "dungeon": 140,
                "note": 49, "skillFruit": 28, "camp": 27, "sealedRealm": 16}
    plain_layers = {}
    used = set()
    for cat, want in expected.items():
        candidates = sorted((abs(len(a) - want), i) for i, a in enumerate(arrays)
                            if i not in used)
        if not candidates:
            warnings.append(f"NO ARRAY for {cat}")
            continue
        dist, idx = candidates[0]
        used.add(idx)
        if dist != 0:
            warnings.append(f"{cat}: expected {want}, matched array of {len(arrays[idx])}")
        plain_layers[cat] = arrays[idx]

    # fast travel: [[x, y, "FTPointN"], ...]
    ft = re.search(r'\[\s*\[-?[\d.]+,-?[\d.]+,"FTPoint', src)
    ft_body, _ = parse_balanced(src, src.index("[", ft.start()))
    ft_points = re.findall(r'\[(-?[\d.eE]+),(-?[\d.eE]+),"(FTPoint\d+)"\]', ft_body)

    # syndicate towers: [{x:..,y:..,name:"BOSS_BATTLE_NAME_..",image:".."}]
    towers = re.findall(
        r'\{x:(-?[\d.eE]+),y:(-?[\d.eE]+),name:"(BOSS_BATTLE_NAME_[^"]+)"', src)

    spawn_vars = spawn_var_literals(src)
    mapping = codename_mapping(src)
    names = {}
    for chunk_name in chunks["pals"]:
        names = bpclass_names(fetch(f"{BASE}/_nuxt/{chunk_name}").decode())
        if names.get("sheepball") == "Lamball":
            break
    eagle_srcs = [fetch(f"{BASE}/_nuxt/{c}").decode() for c in chunks["eagles"]]
    ft_names = fast_travel_names(eagle_srcs)

    def display(code: str) -> str:
        return names.get(code, code)

    categories = []
    categories.append({"id": "fastTravel", "name": "Fast Travel", "icon": "fast_travel",
                       "markers": [{"x": norm(float(x), float(y))[0],
                                    "y": norm(float(x), float(y))[1],
                                    "name": ft_names.get(key, "Great Eagle Statue")}
                                   for x, y, key in ft_points]})
    categories.append({"id": "tower", "name": "Syndicate Tower", "icon": "tower",
                       "markers": [{"x": norm(float(x), float(y))[0],
                                    "y": norm(float(x), float(y))[1],
                                    "name": name.replace("BOSS_BATTLE_NAME_", "") + " Tower"}
                                   for x, y, name in towers]})
    labels = {"camp": "Camp", "dungeon": "Dungeon", "sealedRealm": "Sealed Realm",
              "skillFruit": "Skill Fruit", "note": "Note", "egg": "Egg",
              "chest": "Chest", "effigy": "Lifmunk Effigy"}
    icons = {"camp": "camp", "dungeon": "dungeon", "sealedRealm": "sealed_realm",
             "skillFruit": "skill_fruit", "note": "note", "egg": "egg",
             "chest": "chest", "effigy": "effigy"}
    for cat, pts in plain_layers.items():
        categories.append({"id": cat, "name": labels[cat], "icon": icons[cat],
                           "markers": [{"x": norm(x, y)[0], "y": norm(x, y)[1]}
                                       for x, y in pts]})

    # alphas + predators from the codename mapping's boss_/predator_ entries
    for prefix, cat_id, cat_name in [("boss_", "alpha", "Alpha Pals"),
                                     ("predator_", "predator", "Predator Pals")]:
        markers = []
        for code, var in mapping.items():
            if not code.startswith(prefix):
                continue
            base = code[len(prefix):]
            spawn = spawn_vars.get(var)
            if not spawn:
                continue
            points = spawn["day"] or spawn["night"]
            # world-boss alphas have 1-3 fixed spots; big lists are area/
            # fishing pools that would flood the layer
            if prefix == "boss_" and len(points) > 3:
                continue
            for x, y in points:
                px, py = norm(x, y)
                markers.append({"x": px, "y": py, "name": display(base),
                                "pal": display(base).lower()})
        categories.append({"id": cat_id, "name": cat_name, "icon": cat_id,
                           "markers": markers})

    # per-pal wild spawns (plain codenames)
    spawns = {}
    for code, var in mapping.items():
        if code.startswith(("boss_", "predator_")) or code == "rowname":
            continue
        spawn = spawn_vars.get(var)
        if not spawn:
            continue
        name = display(code)
        spawns[name] = {side: [list(norm(x, y)) for x, y in pts]
                        for side, pts in spawn.items() if pts}

    categories.extend(mapgenie_categories())

    markers_json = {"categories": categories, "warnings": warnings}
    return markers_json, spawns


# ------------------------------------------------------- mapgenie extras

# Bounty targets + fishing spots aren't on palworld.gg; mapgenie.io has them.
# Affine calibrated by permutation-matching the 7 syndicate towers between
# both datasets (validated on 152 dungeons, median error ~13 world units):
#   x = 0.003246*lat + 1.514979*lng + 1.682067
#   y = -1.514824*lat - 0.001526*lng + 1.458622
MAPGENIE_API = "https://mapgenie.io/api/v1/maps/580/data"
MAPGENIE_SPRITES = "https://cdn.mapgenie.io/images/games/palworld/markers@2x"
MAPGENIE_CATS = {12211: ("bounty", "Bounty Target", "bounty"),
                 10283: ("fishing", "Fishing Spot", "fishing")}


def mapgenie_xy(lat: float, lng: float) -> tuple[float, float]:
    x = 0.003246 * lat + 1.514979 * lng + 1.682067
    y = -1.514824 * lat - 0.001526 * lng + 1.458622
    return round(x, 4), round(y, 4)


def mapgenie_categories() -> list[dict]:
    try:
        data = json.loads(fetch(MAPGENIE_API))
    except Exception as exc:
        print(f"  WARNING: mapgenie fetch failed ({exc}) — bounty/fishing "
              f"layers kept from previous run", file=sys.stderr)
        return []
    out = []
    for cat_id, (layer_id, layer_name, icon) in MAPGENIE_CATS.items():
        markers = []
        for loc in data.get("locations", []):
            if loc.get("category_id") != cat_id:
                continue
            x, y = mapgenie_xy(float(loc["latitude"]), float(loc["longitude"]))
            title = (loc.get("title") or layer_name).replace(" (Bounty)", "")
            markers.append({"x": x, "y": y, "name": title})
        out.append({"id": layer_id, "name": layer_name, "icon": icon,
                    "markers": markers})
        print(f"  {layer_id:<12} {len(markers)} markers (mapgenie)")
    return out


def fetch_mapgenie_icons():
    """Actual in-game icons for the mapgenie layers (via paldb's asset CDN):
    the purple hooded bounty compass icon + the fishing rod."""
    icons = MAPDIR / "icons"
    icons.mkdir(parents=True, exist_ok=True)
    from io import BytesIO
    from PIL import Image
    game_icons = {
        "bounty": "https://cdn.paldb.cc/image/Pal/Texture/UI/InGame/"
                  "T_icon_compass_Bounty.webp",
        "fishing": "https://cdn.paldb.cc/image/Others/InventoryItemIcon/Texture/"
                   "T_itemicon_Weapon_FishingRod_1.webp",
    }
    for name, url in game_icons.items():
        Image.open(BytesIO(fetch(url))).convert("RGBA").save(icons / f"{name}.png")
    print(f"  game icons: {len(game_icons)}")


# ---------------------------------------------------------------- assets

ICON_SOURCES = {
    "fast_travel": "images/T_icon_compass_FTtower.png",
    "tower": "images/T_icon_compass_tower.png",
    "dungeon": "images/T_icon_compass_dungeon.png",
    "sealed_realm": "images/T_icon_compass_dungeon.png",
    "camp": "images/camp-loc.png",
    "egg": "images/egg-loc.png",
    "chest": "images/chest-loc.png",
    "effigy": "images/lifmunk_effigy.png",
    "note": "images/note-loc.png",
    "skill_fruit": "images/fruit-loc.png",
}


def fetch_icons():
    icons = MAPDIR / "icons"
    icons.mkdir(parents=True, exist_ok=True)
    for name, path in ICON_SOURCES.items():
        target = icons / f"{name}.png"
        if not target.exists():
            target.write_bytes(fetch(f"{BASE}/{path}"))
    print(f"icons: {len(ICON_SOURCES)}")


def fetch_tiles():
    jobs = []
    for z in range(MAX_ZOOM + 1):
        for x in range(2 ** z):
            for y in range(2 ** z):
                target = MAPDIR / "tiles" / str(z) / str(x) / f"{y}.png"
                if not target.exists():
                    jobs.append((z, x, y, target))
    print(f"tiles: {sum((2 ** z) ** 2 for z in range(MAX_ZOOM + 1))} total, "
          f"{len(jobs)} to fetch")

    def grab(job):
        z, x, y, target = job
        try:
            data = fetch(f"{BASE}/images/tiles/{z}/{x}/{y}.png")
        except Exception:
            return 0
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        return len(data)

    with ThreadPoolExecutor(max_workers=6) as pool:
        total = sum(pool.map(grab, jobs))
    print(f"downloaded {total / 1e6:.1f} MB of tiles")


def main():
    chunks = discover_chunks()
    print(f"map chunk: {len(chunks['map']) / 1e6:.1f} MB, "
          f"{len(chunks['eagles'])} locale chunks, {len(chunks['pals'])} pal chunks")
    markers, spawns = extract(chunks)
    for cat in markers["categories"]:
        print(f"  {cat['id']:<12} {len(cat['markers'])} markers")
    for w in markers["warnings"]:
        print(f"  WARNING: {w}", file=sys.stderr)
    DATA.joinpath("map_markers.json").write_text(
        json.dumps(markers, separators=(",", ":")))
    DATA.joinpath("map_spawns.json").write_text(
        json.dumps(spawns, separators=(",", ":")))
    print(f"spawns: {len(spawns)} pals, "
          f"{sum(len(v) for s in spawns.values() for v in s.values())} points")
    fetch_icons()
    fetch_mapgenie_icons()
    fetch_tiles()
    print("Done.")


if __name__ == "__main__":
    main()
