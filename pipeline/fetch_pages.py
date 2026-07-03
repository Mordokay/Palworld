#!/usr/bin/env python3
"""Mirror all article wikitext + categories from palworld.fandom.com into cache/pages.json.

Uses the MediaWiki API (no HTML scraping). Batches 50 titles per request,
sleeps between requests to be polite. Safe to re-run; overwrites the cache.
"""
import json
import time
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://palworld.fandom.com/api.php"
CACHE = Path(__file__).parent / "cache"
UA = "PalworldQuizAppDataPipeline/1.0 (personal learning project)"


def api_get(params: dict) -> dict:
    params = {**params, "format": "json"}
    url = API + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)


def all_titles() -> list[str]:
    """Every content page (namespace 0), skipping redirects."""
    titles, cont = [], {}
    while True:
        d = api_get({
            "action": "query", "list": "allpages", "apnamespace": 0,
            "apfilterredir": "nonredirects", "aplimit": 500, **cont,
        })
        titles += [p["title"] for p in d["query"]["allpages"]]
        if "continue" not in d:
            return titles
        cont = d["continue"]
        time.sleep(0.3)


def fetch_batch(titles: list[str]) -> dict:
    """title -> {text, categories} for up to 50 titles."""
    out = {}
    cont = {}
    while True:
        d = api_get({
            "action": "query", "prop": "revisions|categories",
            "rvprop": "content", "rvslots": "main",
            "cllimit": "max", "clshow": "!hidden",
            "titles": "|".join(titles), **cont,
        })
        for p in d["query"]["pages"].values():
            t = p["title"]
            e = out.setdefault(t, {"text": "", "categories": []})
            revs = p.get("revisions")
            if revs:
                e["text"] = revs[0]["slots"]["main"]["*"]
            e["categories"] += [
                c["title"].removeprefix("Category:") for c in p.get("categories", [])
            ]
        if "continue" not in d:
            return out
        cont = d["continue"]
        time.sleep(0.3)


def main():
    CACHE.mkdir(exist_ok=True)
    titles = all_titles()
    print(f"{len(titles)} article pages")
    pages = {}
    for i in range(0, len(titles), 50):
        batch = titles[i:i + 50]
        pages.update(fetch_batch(batch))
        print(f"  fetched {min(i + 50, len(titles))}/{len(titles)}")
        time.sleep(0.4)
    out = CACHE / "pages.json"
    out.write_text(json.dumps(pages, ensure_ascii=False))
    print(f"wrote {out} ({out.stat().st_size / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
