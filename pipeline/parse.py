#!/usr/bin/env python3
"""Parse cache/pages.json (raw wikitext) into structured JSON under data/.

Outputs:
  data/pals.json      - all pals: elements, stats, work suitability, skills, drops...
  data/items.json     - items (materials, food, spheres, armor, ...)
  data/weapons.json   - weapons incl. rarity variants table fields
  data/skills.json    - active skills incl. power/element/cooldown + learnset
  data/locations.json - named locations
  data/articles.json  - EVERY page as cleaned readable text (knowledge library)
"""
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from wikitext import find_templates, template_params, clean, clean_list

ROOT = Path(__file__).parent.parent
CACHE = Path(__file__).parent / "cache" / "pages.json"
DATA = ROOT / "data"

WORK_KEYS = {
    "kindling": "kindling", "watering": "watering", "planting": "planting",
    "gen_electric": "generatingElectricity", "handiwork": "handiwork",
    "gathering": "gathering", "lumbering": "lumbering", "mining": "mining",
    "med_prod": "medicineProduction", "cooling": "cooling",
    "transporting": "transporting", "farming": "farming",
}

GALLERY_RE = re.compile(r"<gallery[^>]*>.*?</gallery>", re.S)


def num(v):
    """'1,470' -> 1470; '0.5' -> 0.5; otherwise None."""
    s = clean(v).replace(",", "").strip()
    if re.fullmatch(r"-?\d+", s):
        return int(s)
    if re.fullmatch(r"-?\d*\.\d+", s):
        return float(s)
    return None


def slug(title: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")


def page_infobox(text: str):
    """(normalized_name, params) of the page's main infobox, or (None, None)."""
    for name, inner in find_templates(GALLERY_RE.sub("", text)):
        nn = name.replace("_", " ").strip().lower()
        if nn == "pal" or nn.startswith("infobox"):
            return nn, template_params(inner)
    return None, None


TABLE_RE = re.compile(r"^\{\|.*?^\|\}", re.S | re.M)


def _split_cells(line: str, sep: str) -> list[str]:
    """Split a wikitable cell line on !!/|| at nesting depth 0."""
    cells, depth, cur = [], 0, []
    i = 0
    while i < len(line):
        two = line[i:i + 2]
        if two in ("{{", "[["):
            depth += 1
            cur.append(two)
            i += 2
        elif two in ("}}", "]]"):
            depth -= 1
            cur.append(two)
            i += 2
        elif depth == 0 and two == sep * 2:
            cells.append("".join(cur))
            cur = []
            i += 2
        else:
            cur.append(line[i])
            i += 1
    cells.append("".join(cur))
    return cells


def _strip_cell_attrs(cell: str) -> str:
    # strip attribute prefix:  style="..." | value
    if "|" in cell:
        prefix, _, rest = cell.partition("|")
        if "=" in prefix and "[[" not in prefix and "{{" not in prefix:
            cell = rest
    return cell


def _clean_cell(cell: str) -> str:
    return clean(_strip_cell_attrs(cell))


FILE_LINK_RE = re.compile(r"\[\[File:([^|\]]+)((?:\|[^\[\]]*)*)\]\]", re.I)
PAGE_LINK_RE = re.compile(r"\[\[(?!File:)([^|\]#]+)(?:#[^|\]]*)?(?:\|[^\]]*)?\]\]", re.I)


def _cell_rowspan(cell: str) -> int:
    if "|" in cell:
        prefix = cell.partition("|")[0]
        if "=" in prefix and "[[" not in prefix and "{{" not in prefix:
            m = re.search(r"rowspan\s*=\s*\"?(\d+)", prefix)
            if m:
                return int(m.group(1))
    return 1


def _rich_cell(cell: str) -> dict:
    """Table cell -> {t: text, l: link-id, img: filename} (l/img omitted if absent)."""
    cell = _strip_cell_attrs(cell)
    img = link = None
    fm = FILE_LINK_RE.search(cell)
    if fm:
        img = fm.group(1).strip()
        lm = re.search(r"\|link=([^|\]]+)", fm.group(2) or "")
        if lm:
            link = slug(lm.group(1))
    pm = PAGE_LINK_RE.search(cell)
    if pm:
        link = slug(pm.group(1))
    tm = re.search(r"\{\{(?:PalMenu|p)\|([^{}|]+)", cell, re.I)
    if tm and not link:
        link = slug(tm.group(1))
    out = {"t": clean(cell)}
    if link:
        out["l"] = link
    if img:
        out["img"] = img
    return out


def parse_wikitable(tbl: str):
    """One {| ... |} block -> {headers, rows}. Handles rowspan carry-over."""
    lines = tbl.splitlines()[1:-1]  # drop {| and |}
    headers: list[str] = []
    rows: list[list[dict]] = []
    current: list[tuple[dict, int]] = []  # (cell, rowspan)
    carry: dict[int, tuple[dict, int]] = {}  # column -> (cell, remaining rows)

    def flush():
        nonlocal current, carry
        if not current:
            return
        out, next_carry = [], {}
        col, cur_i = 0, 0
        while cur_i < len(current) or col in carry:
            if col in carry:
                cell, remaining = carry[col]
                out.append(cell)
                if remaining > 1:
                    next_carry[col] = (cell, remaining - 1)
            else:
                cell, rowspan = current[cur_i]
                cur_i += 1
                out.append(cell)
                if rowspan > 1:
                    next_carry[col] = (cell, rowspan - 1)
            col += 1
        rows.append(out)
        current = []
        carry = next_carry

    for line in lines:
        line = line.strip()
        if line.startswith("|+") or not line:
            continue
        if line.startswith("|-"):
            flush()
        elif line.startswith("!"):
            cells = [_clean_cell(c) for c in _split_cells(line[1:], "!")]
            if not rows and not current:
                headers += cells
            else:
                current += [({"t": c}, 1) for c in cells]  # header cell inside body row
        elif line.startswith("|"):
            for raw in _split_cells(line[1:], "|"):
                current.append((_rich_cell(raw), _cell_rowspan(raw)))
        elif line.startswith("{{"):
            # row template ({{PalListEntry+|Lamball}}...) — starts a new row
            cleaned = clean(line)
            if cleaned:
                if len(current) >= 2:
                    flush()
                current.append(({"t": cleaned, "l": slug(cleaned)}, 1))
        else:
            # continuation of the previous cell's text
            cleaned = clean(line)
            if cleaned and current:
                cell = current[-1][0]
                cell["t"] = (cell["t"] + "\n" + cleaned).strip()
    flush()
    rows = [r for r in rows if any(c["t"].strip() or c.get("img") for c in r)]
    if not rows and not headers:
        return None
    return {"headers": headers, "rows": rows}


SKIP_HEADINGS = {"update history", "references", "navigation"}

IMAGE_EXT = (".png", ".jpg", ".jpeg", ".gif", ".webp")
FILE_PARAM_NOISE = re.compile(r"^(thumb|frame|frameless|border|left|right|center|none"
                              r"|\d+\s*(x\d+)?px|link=.*|alt=.*|upright.*)$", re.I)


def section_images(body: str) -> list:
    """Display images referenced by a section: gallery entries and full-size
    File links (small inline icons excluded; habitat maps are structured
    separately on pal pages)."""
    images = []

    def add(file, caption):
        file = file.strip().removeprefix("File:").strip()
        if not file.lower().endswith(IMAGE_EXT) or file.endswith("Habitat.png"):
            return
        if not any(i["file"] == file for i in images):
            images.append({"file": file, "caption": clean(caption)})

    for g in re.finditer(r"<gallery[^>]*>(.*?)</gallery>", body, re.S | re.I):
        for line in g.group(1).splitlines():
            line = line.strip()
            if not line:
                continue
            file, _, caption = line.partition("|")
            add(file, caption)
    for fm in FILE_LINK_RE.finditer(body):
        params = [p for p in (fm.group(2) or "").split("|") if p]
        size = re.search(r"(\d+)\s*(?:x\d+)?px", fm.group(2) or "")
        if size and int(size.group(1)) <= 60:
            continue  # inline icon, not display content
        caption = next((p for p in reversed(params) if not FILE_PARAM_NOISE.match(p.strip())), "")
        add(fm.group(1), caption)
    return images


def sections(text: str) -> list[dict]:
    """Split page into [{heading, level, text, tables}] with cleaned plain text.
    heading '' = intro; level 2 = ==H==, level 3 = ===H===."""
    out = []
    parts = re.split(r"^(={2,3})\s*(.*?)\s*\1\s*$", text, flags=re.M)

    PLACEHOLDERS = {"?", "???", "tba", "n/a", "wip", "-", "unknown", "unknown information."}

    def emit(heading: str, level: int, body: str):
        tables = [t for t in (parse_wikitable(m) for m in TABLE_RE.findall(body)) if t]
        body = TABLE_RE.sub("", body)
        images = section_images(body)
        cleaned = clean(body)
        # drop wiki placeholder lines ("?", "TBA"...); sections left empty vanish
        cleaned = "\n".join(
            line for line in cleaned.split("\n")
            if line.strip(" •◦ ").lower() not in PLACEHOLDERS
        ).strip()
        if heading.lower() == "gallery":
            # gallery sections are images-only; the text is editor noise ("WIP")
            if not images:
                return
            cleaned = ""
        if cleaned or tables or images:
            entry = {"heading": heading, "level": level, "text": cleaned}
            if tables:
                entry["tables"] = tables
            if images:
                entry["images"] = images
            out.append(entry)

    intro = re.sub(r"^\{\{[^{}]*\}\}\s*", "", parts[0])
    emit("", 2, intro)
    skipping = False
    for i in range(1, len(parts) - 2, 3):
        level = len(parts[i])
        heading = clean(parts[i + 1])
        if level == 2:
            skipping = heading.lower() in SKIP_HEADINGS
        if skipping or heading.lower() in SKIP_HEADINGS:
            continue
        emit(heading, level, parts[i + 2])
    return out


def parse_utility_extras(text: str):
    """Alpha/boss drops and farming produce from the Utility section's lists —
    the infobox only carries normal drops."""
    m = re.search(r"^==\s*Utility\s*==\s*$(.*?)(?=^==[^=]|\Z)", text, re.S | re.M)
    if not m:
        return [], []
    body = m.group(1)
    alpha, produce = [], []
    am = re.search(r"(?:Possible Alpha drops'*|^\*\s*'*Boss'*\s*$)\s*(.*?)(?='''|\Z)",
                   body, re.S | re.I | re.M)
    if am:
        for line in re.findall(r"^\*+\s*(.+)$", am.group(1), re.M):
            c = clean(line)
            if c and c.lower() not in ("normal", "boss"):
                alpha.append(c)
    fm = re.search(r"Farming Produce.*?$(.*)", body, re.S | re.M | re.I)
    if fm:
        produce = [clean(l) for l in re.findall(r"^\*+\s*(.+)$", fm.group(1), re.M) if clean(l)]
    return alpha, produce


def parse_pal(title: str, text: str, box: dict, categories: list[str]) -> dict:
    templates = find_templates(text)
    alpha_drops, farming_produce = parse_utility_extras(text)
    habitat_day = re.search(r"([^|=\n/]+?Day Habitat\.png)", text)
    habitat_night = re.search(r"([^|=\n/]+?Night Habitat\.png)", text)

    stats = {}
    for n, inner in templates:
        if n.replace("_", " ").strip().lower() == "pal table stats":
            p = template_params(inner)
            stats = {k: num(v) for k, v in p.items()}

    paldeck = next((template_params(inner).get("1", "")
                    for n, inner in templates if n.strip().lower() == "paldeck"), "")

    skills = []
    for m in re.finditer(r"\{\{PalSkillListEntry\+\|([^{}|]+?)(?:\|level=(\d+))?\s*\}\}", text):
        skills.append({"name": m.group(1).strip(),
                       "level": int(m.group(2)) if m.group(2) else None})

    elements = [clean(box[k]) for k in ("ele1", "ele2") if box.get(k) and clean(box[k])]
    work = {}
    for wk, out_key in WORK_KEYS.items():
        v = num(box.get(wk, ""))
        if v:
            work[out_key] = v

    return {
        "id": slug(title),
        "name": clean(box.get("name", "")) or title,
        "number": clean(box.get("no", "")),
        "image": box.get("image", "").strip(),
        "elements": elements,
        "alphaTitle": clean(box.get("alphatitle", "")),
        "partnerSkill": {
            "name": clean(box.get("partnerskill", "")),
            "icon": clean(box.get("psicon", "")),
            "description": clean(box.get("psdesc", "")),
        },
        "workSuitability": work,
        "foodAmount": num(box.get("food", "")),
        "breedPower": num(box.get("breedpower", "")),
        "drops": clean_list(box.get("drops", "")),
        "alphaDrops": alpha_drops,
        "farmingProduce": farming_produce,
        "habitatDay": habitat_day.group(1).strip() if habitat_day else None,
        "habitatNight": habitat_night.group(1).strip() if habitat_night else None,
        "saddleTech": clean(box.get("tech", "")) or None,
        "saddleTechLevel": num(box.get("techlevel", "")),
        "stats": {
            "hp": stats.get("hp"), "attack": stats.get("attack"), "defense": stats.get("defense"),
            "hpLv50Range": [stats.get("min_hp"), stats.get("max_hp")],
            "attackLv50Range": [stats.get("min_attack"), stats.get("max_attack")],
            "defenseLv50Range": [stats.get("min_defense"), stats.get("max_defense")],
        } if stats else None,
        "activeSkills": skills,
        "paldeckEntry": clean(paldeck),
        "categories": categories,
    }


def parse_item(title: str, box: dict, categories: list[str]) -> dict:
    return {
        "id": slug(title),
        "name": clean(box.get("name", "")) or title,
        "image": box.get("image", "").strip(),
        "type": clean(box.get("type", "")),
        "description": clean(box.get("effects", "")),
        "rarity": clean(box.get("rarity", "")),
        "source": clean_list(box.get("source", "")),
        "craftMaterials": clean_list(box.get("materials", "")),
        "weight": num(box.get("weight", "")),
        "techTier": num(box.get("tech_tier", "")),
        "techPointsCost": num(box.get("points_cost", "")),
        "workload": num(box.get("workload", "")),
        "goldBuy": num(box.get("gold_buy", "")),
        "goldSell": num(box.get("gold_sell", "")),
        "nutrition": num(box.get("nutrition", "")),
        "sanity": num(box.get("san", "")),
        "damage": num(box.get("dmg", "")),
        "durability": num(box.get("durability", "")),
        "magazineSize": num(box.get("mag_size", "")),
        "capturePower": num(box.get("capt_pwr", "")),
        "categories": categories,
    }


def parse_skill(title: str, text: str, box: dict, categories: list[str]) -> dict:
    learnset = [{"pal": m.group(1).strip(), "level": int(m.group(2))}
                for m in re.finditer(r"\{\{PalListEntry\+\|([^{}|]+)\}\}\s*\|\s*(\d+)", text)]
    return {
        "id": slug(title),
        "name": clean(box.get("name", "")) or title,
        "skillType": clean(box.get("skill_type", "")),
        "element": clean(box.get("element", "")),
        "description": clean(box.get("skill_desc", "")),
        "power": num(box.get("power", "")),
        "cooldown": num(box.get("ct", "")),
        "range": clean(box.get("range", "")) or None,
        "image": box.get("skill_image", "").strip() or None,
        "skillFruit": {
            "name": clean(box.get("fruit_name", "")),
            "icon": box.get("fruit_icon", "").strip(),
        } if box.get("fruit_name") else None,
        "exclusiveTo": clean_list(box.get("exclusive", "")),
        "learnset": learnset,
        "categories": categories,
    }


# wiki type values drift (singular/plural, synonyms) — canonicalize
TYPE_ALIASES = {
    "key items": "Key Item", "ingredients": "Ingredient", "consumables": "Consumable",
    "sphere modules": "Sphere Module", "other materials": "Material",
    "pal materials": "Pal Material", "": "Other",
}


def normalize_type(raw: str) -> str:
    t = raw.strip()
    return TYPE_ALIASES.get(t.lower(), t)


TECHBOX_RE = re.compile(
    r"\{\{TechBox\|image\s*=\s*([^|{}]*)\|name\s*=\s*([^|{}]*)\|type\s*=\s*(\w*)\s*"
    r"\|points\s*=\s*(\d*)\s*(\|ancient\s*=\s*\w+\s*)?\}\}")


def parse_technology(text: str) -> list[dict]:
    """The Technology page's big table: {{TechBox|...}} entries grouped by
    level rows; ancient techs are flagged with |ancient = y."""
    entries = []
    for row in text.split("|-"):
        m = re.search(r'\|\s*style="text-align: center;"\s*\|\s*(\d+)', row)
        if not m:
            continue
        level = int(m.group(1))
        for box in TECHBOX_RE.finditer(row):
            entries.append({
                "level": level,
                "name": clean(box.group(2)),
                "image": box.group(1).strip(),
                "structure": box.group(3).strip() == "s",
                "points": int(box.group(4) or 0),
                "ancient": bool(box.group(5)),
            })
    return entries


def parse_location(title: str, box: dict, categories: list[str]) -> dict:
    return {
        "id": slug(title),
        "name": clean(box.get("name", "")) or title,
        "image": box.get("image", "").strip(),
        "type": clean(box.get("type", "")),
        "region": clean(box.get("location", "")),
        "inhabitants": clean_list(box.get("inhabitants", "")),
        "level": clean(box.get("level", "")),
        "categories": categories,
    }


def main():
    pages = json.loads(CACHE.read_text())
    DATA.mkdir(exist_ok=True)

    # the wiki has a few duplicate pages differing only in capitalization
    # (e.g. "Meteor Launcher" vs "Meteor launcher"); keep the fuller one per slug
    by_slug = {}
    for title, page in pages.items():
        prev = by_slug.get(slug(title))
        if prev is None or len(page["text"]) > len(prev[1]["text"]):
            by_slug[slug(title)] = (title, page)
    pages = dict(by_slug.values())

    pals, things, skills, locations, articles = [], [], [], [], []
    technology = []
    for title, page in sorted(pages.items()):
        text, cats = page["text"], page["categories"]
        kind, box = page_infobox(text)
        if kind == "pal":
            pals.append(parse_pal(title, text, box, cats))
        elif kind in ("infobox item", "infobox weapon"):
            # classification comes from the `type` field, NOT the infobox
            # template — wiki editors mix the two templates up
            thing = parse_item(title, box, cats)
            thing["type"] = normalize_type(thing["type"])
            things.append(thing)
        elif kind == "infobox skill":
            skills.append(parse_skill(title, text, box, cats))
        elif kind == "infobox location":
            locations.append(parse_location(title, box, cats))
        if title == "Technology":
            technology = parse_technology(text)
        article_kind = "article"
        if kind == "pal":
            article_kind = "pal"
        elif kind in ("infobox item", "infobox weapon"):
            article_kind = "weapon" if normalize_type(box.get("type", "")) == "Weapon" else "item"
        elif kind == "infobox skill":
            article_kind = "skill"
        elif kind == "infobox location":
            article_kind = "location"
        articles.append({
            "id": slug(title),
            "title": title,
            "kind": article_kind,
            "categories": cats,
            "sections": sections(text),
        })

    weapons = [t for t in things if t["type"] == "Weapon"]
    items = [t for t in things if t["type"] != "Weapon"]

    # learnsets derived from pal data are complete and always carry levels;
    # skill pages themselves are often missing or malformed (e.g. Hydro Spin)
    learners = {}
    for pal in pals:
        for learned in pal["activeSkills"]:
            learners.setdefault(learned["name"].lower(), []).append(
                {"pal": pal["name"], "level": learned["level"]})
    for skill in skills:
        merged = {e["pal"]: e for e in learners.get(skill["name"].lower(), [])}
        for entry in skill["learnset"]:
            merged.setdefault(entry["pal"], entry)
        skill["learnset"] = sorted(merged.values(),
                                   key=lambda e: (e["level"] is None, e["level"] or 0, e["pal"]))

    for name, data in [("pals", pals), ("items", items), ("weapons", weapons),
                       ("skills", skills), ("locations", locations),
                       ("technology", technology), ("articles", articles)]:
        path = DATA / f"{name}.json"
        path.write_text(json.dumps(data, ensure_ascii=False, indent=1))
        print(f"{path.name}: {len(data)} entries, {path.stat().st_size / 1e6:.2f} MB")


if __name__ == "__main__":
    main()
