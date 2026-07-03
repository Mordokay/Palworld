#!/usr/bin/env python3
"""Download every image referenced by the parsed data files into data/images/<kind>/.

Resolves File: pages to CDN URLs via the MediaWiki API (batches of 50),
then downloads missing files only. Re-run friendly.
"""
import html
import json
import time
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://palworld.fandom.com/api.php"
ROOT = Path(__file__).parent.parent
DATA = ROOT / "data"
IMAGES = DATA / "images"
UA = "PalworldQuizAppDataPipeline/1.0 (personal learning project)"


def api_get(params: dict) -> dict:
    url = API + "?" + urllib.parse.urlencode({**params, "format": "json"})
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)


def canonical(name: str) -> str:
    """Match MediaWiki title normalization: no File: prefix, underscores as spaces."""
    name = html.unescape(name)
    return name.strip().removeprefix("File:").replace("_", " ").strip()


def wanted_images() -> dict[str, str]:
    """filename -> kind subfolder"""
    want = {}

    def add(name, kind):
        name = canonical(name or "")
        if name:
            want.setdefault(name, kind)

    for p in json.loads((DATA / "pals.json").read_text()):
        add(p["image"], "pals")
    for it in json.loads((DATA / "items.json").read_text()):
        add(it["image"], "items")
    for w in json.loads((DATA / "weapons.json").read_text()):
        add(w["image"], "weapons")
    for s in json.loads((DATA / "skills.json").read_text()):
        add(s.get("image"), "skills")
        if s.get("skillFruit"):
            add(s["skillFruit"].get("icon"), "skills")
    for loc in json.loads((DATA / "locations.json").read_text()):
        add(loc["image"], "locations")
    for tech in json.loads((DATA / "technology.json").read_text()):
        add(tech["image"], "misc")  # most already exist as item images
    for p in json.loads((DATA / "pals.json").read_text()):
        add(p.get("habitatDay"), "maps")
        add(p.get("habitatNight"), "maps")
    for work in ["Kindling", "Watering", "Planting", "Generating_Electricity",
                 "Handiwork", "Gathering", "Lumbering", "Mining",
                 "Medicine_Production", "Cooling", "Transporting", "Farming"]:
        add(f"{work}_Icon.png", "ui")
    for element in ["Neutral", "Fire", "Water", "Grass", "Electric",
                    "Ice", "Ground", "Dark", "Dragon"]:
        add(f"{element}_icon.png", "ui")
    add("Food_on_icon.png", "ui")
    add("Food_off_icon.png", "ui")
    for article in json.loads((DATA / "articles.json").read_text()):
        for section in article["sections"]:
            for image in section.get("images", []):
                add(image["file"], "articles")
    return want


def resolve_urls(filenames: list[str]) -> dict[str, tuple[str, int]]:
    """filename -> (CDN url, byte size). Follows normalization/redirects."""
    urls = {}
    for i in range(0, len(filenames), 50):
        batch = filenames[i:i + 50]
        titles = "|".join("File:" + f for f in batch)
        d = api_get({"action": "query", "prop": "imageinfo", "iiprop": "url|size",
                     "titles": titles, "redirects": 1})
        for page in d["query"]["pages"].values():
            info = page.get("imageinfo")
            if not info:
                continue
            urls[canonical(page["title"])] = (info[0]["url"], info[0].get("size", 0))
        time.sleep(0.3)
    return urls


def main():
    want = wanted_images()
    print(f"{len(want)} images referenced by data files")
    urls = resolve_urls(sorted(want))
    missing = sorted(set(want) - set(urls))
    # wiki naming drift: "<X> icon.png" sometimes uploaded as "<X>.png" (and vice versa)
    alts = {}
    for name in missing:
        alt = name.replace(" icon.", ".") if " icon." in name else name.replace(".", " icon.", 1)
        alts[alt] = name
    for alt, resolved in resolve_urls(sorted(alts)).items():
        original = alts[alt]
        urls[original] = resolved
        missing.remove(original)
    if missing:
        print(f"WARNING: {len(missing)} filenames did not resolve, e.g. {missing[:10]}")

    done = skipped = 0
    for name, (url, size) in sorted(urls.items()):
        kind = want.get(name, "misc")
        folder = IMAGES / kind
        folder.mkdir(parents=True, exist_ok=True)
        dest = folder / name.replace("/", "_")
        if dest.exists() and dest.stat().st_size > 0:
            skipped += 1
            continue
        if kind == "maps" or size > 1_500_000:
            # habitat maps and other huge originals: fetch a scaled thumbnail
            width = 1000 if kind == "maps" else 1200
            url = url.replace("/revision/latest?",
                              f"/revision/latest/scale-to-width-down/{width}?")
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        for attempt in range(3):
            try:
                with urllib.request.urlopen(req, timeout=60) as resp:
                    dest.write_bytes(resp.read())
                break
            except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as e:
                if attempt == 2:
                    print(f"  FAILED {name}: {e}")
                else:
                    time.sleep(3 * (attempt + 1))
        done += 1
        if done % 100 == 0:
            print(f"  downloaded {done}...")
        time.sleep(0.15)
    total_mb = sum(f.stat().st_size for f in IMAGES.rglob("*") if f.is_file()) / 1e6
    print(f"downloaded {done}, already had {skipped}, total {total_mb:.0f} MB in {IMAGES}")


if __name__ == "__main__":
    main()
