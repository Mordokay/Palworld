# Palworld wiki data pipeline

Extracts the entire palworld.fandom.com wiki into structured local data for the iOS app.
Uses the MediaWiki API (`api.php`) — no HTML scraping, so it's robust against skin/layout changes.

## Usage — "Update All"

```sh
pipeline/refresh.sh   # runs all three steps below in order
```

Run this after every game update (e.g. the 1.0 release) — new pals/items/skills flow
straight into the app's quizzes and library on the next build, since questions are
generated from these files at runtime. Individual steps:

```sh
python3 pipeline/fetch_pages.py    # 1. mirror all article wikitext -> pipeline/cache/pages.json
python3 pipeline/parse.py          # 2. parse infoboxes/templates   -> data/*.json
python3 pipeline/fetch_images.py   # 3. download referenced images  -> data/images/<kind>/
```

Steps are idempotent.
`pipeline/cache/` is a raw mirror and should stay out of the app bundle.

## Outputs (`data/`)

| File | Contents |
|---|---|
| `pals.json` | Every pal: paldeck number, elements, base + lv50 stats, work suitability levels, partner skill, active-skill learnset, drops, breed power, food, saddle tech, paldeck lore |
| `items.json` | Items (materials, food, medicine, spheres, armor, furniture...): type, rarity, craft materials, tech tier, weight, buy/sell gold, nutrition/sanity |
| `weapons.json` | Weapons: same fields as items plus damage, durability, magazine size |
| `skills.json` | Active skills: element, power, cooldown, learnset (pal + level), skill fruit |
| `locations.json` | Named locations |
| `articles.json` | Every wiki page as cleaned plain-text sections — powers the in-app knowledge library and the per-question "info" page |

Entries carry their wiki `categories`, which encode things like Legendary Pals,
subspecies, alpha pals, work-type groupings — useful for quiz category filters.

`image` fields hold the original wiki filename; the corresponding file lives at
`data/images/<kind>/<filename>` after step 3.

## Notes

- Wiki text content is CC BY-SA (attribution required if the app is ever distributed);
  game images are Pocketpair assets — fine for personal use.
- ~1,425 pages, ~1,200 images. Full refresh takes a few minutes and is politely rate-limited.
