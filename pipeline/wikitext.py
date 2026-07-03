"""Minimal MediaWiki wikitext parsing helpers: template extraction + markup cleanup."""
import re


def find_templates(text: str) -> list[tuple[str, str]]:
    """Return [(template_name, inner_text)] for every top-level {{...}} in text."""
    out = []
    i, n = 0, len(text)
    while i < n - 1:
        if text[i:i + 2] == "{{":
            depth, j = 1, i + 2
            while j < n - 1 and depth:
                if text[j:j + 2] == "{{":
                    depth += 1
                    j += 2
                elif text[j:j + 2] == "}}":
                    depth -= 1
                    j += 2
                else:
                    j += 1
            inner = text[i + 2:j - 2]
            name = re.split(r"[|\n]", inner, 1)[0].strip()
            out.append((name, inner))
            i = j
        else:
            i += 1
    return out


def template_params(inner: str) -> dict[str, str]:
    """Split template inner text into params at nesting depth 0."""
    parts, depth, cur = [], 0, []
    i, n = 0, len(inner)
    while i < n:
        two = inner[i:i + 2]
        if two in ("{{", "[["):
            depth += 1
            cur.append(two)
            i += 2
        elif two in ("}}", "]]"):
            depth -= 1
            cur.append(two)
            i += 2
        elif inner[i] == "|" and depth == 0:
            parts.append("".join(cur))
            cur = []
            i += 1
        else:
            cur.append(inner[i])
            i += 1
    parts.append("".join(cur))

    params, anon = {}, 0
    for part in parts[1:]:  # parts[0] is the template name
        if "=" in part:
            k, v = part.split("=", 1)
            # positional params may still contain '=' inside links; heuristics:
            key = k.strip()
            if re.fullmatch(r"[\w\- ]+", key):
                params[key.lower()] = v.strip()
                continue
        anon += 1
        params[str(anon)] = part.strip()
    return params


_GALLERY = re.compile(r"<(gallery|dpl)[^>]*>.*?</\1>", re.S | re.I)
_TABBER_TAG = re.compile(r"</?tabber[^>]*>", re.I)
_TABBER_TITLE = re.compile(r"^(?:\|-\|)?\s*([A-Z][\w/]*(?:[ ][\w/]+)*)\s*=\s*$", re.M)
_COLLAPSIBLE_DIV = re.compile(r"<div[^>]*>|</div>", re.S)
_REF = re.compile(r"<ref[^>]*>.*?</ref>|<ref[^/>]*/>", re.S)
_COMMENT = re.compile(r"<!--.*?-->", re.S)


def clean(value: str) -> str:
    """Wikitext fragment -> plain text. Keeps <br> as newline separators."""
    s = _COMMENT.sub("", value)
    s = _GALLERY.sub("", s)
    # tabber tabs -> "Title:" separators with their content kept
    if "tabber" in s:
        s = _TABBER_TAG.sub("", s)
        s = _TABBER_TITLE.sub(r"\1:", s)
        s = re.sub(r"^\|-\|", "", s, flags=re.M)
    s = _REF.sub("", s)
    s = re.sub(r"<br\s*/?>", "\n", s, flags=re.I)
    s = _COLLAPSIBLE_DIV.sub("", s)
    # inline templates: {{i|X}}, {{p|X}}, {{PalListEntry+|X}} etc -> X ; {{PW}} -> Palworld
    for _ in range(3):  # nested
        s = re.sub(r"\{\{(?:i|p|il|l|e|PalListEntry\+?|PalMenu)\|([^{}|]*)(?:\|[^{}]*)?\}\}",
                   r"\1", s, flags=re.I)
    s = re.sub(r"\{\{PW\}\}", "Palworld", s, flags=re.I)
    # {{Cols|N|content}} is layout-only — keep the content (e.g. location pal lists)
    s = re.sub(r"\{\{Cols\|\d+\|([^{}]*)\}\}", r"\1", s, flags=re.I)
    for _ in range(3):  # nested leftovers like {{Cols|2|{{X}}}}
        s = re.sub(r"\{\{[^{}]*\}\}", "", s)
    s = re.sub(r"\[\[Category:[^\]]*\]\]", "", s, flags=re.I)
    # interlanguage links ([[de:Kelpsea]]...) — the app is English-only
    s = re.sub(r"\[\[[a-z]{2,3}(?:-[a-z]+)?:[^\]]*\]\]", "", s)
    # image links render nothing in plain text (galleries/files are extracted
    # separately into structured section images / table cells)
    s = re.sub(r"\[\[File:[^\[\]]*(\[\[[^\]]*\]\][^\[\]]*)*\]\]", "", s, flags=re.I)
    s = re.sub(r"\[\[(?:[^\]|]*\|)?([^\]|]*)\]\]", r"\1", s)  # [[A|B]] -> B
    s = re.sub(r"\[https?://\S+ ([^\]]*)\]", r"\1", s)  # ext links -> label
    s = s.replace("'''", "").replace("''", "")
    s = re.sub(r"<[^>]+>", "", s)  # any leftover html
    # orphaned wikitable markers (tables split across section boundaries)
    s = re.sub(r"^\s*(\{\||\|\}|\|-|[!|]).*$", "", s, flags=re.M)
    # wiki list markup -> readable bullets ("**" nested -> indented)
    s = re.sub(r"^\s*[*#]{2,}\s*", " ◦ ", s, flags=re.M)  # em-space survives collapsing
    s = re.sub(r"^\s*[*#]\s*", "• ", s, flags=re.M)
    s = re.sub(r"[ \t]+", " ", s)
    s = re.sub(r"\n\s*\n+", "\n", s)
    return s.strip()


def clean_list(value: str) -> list[str]:
    """Fragment holding a <br>/newline/bullet separated list -> list of plain strings."""
    return [x.strip("* ").strip() for x in clean(value).split("\n") if x.strip("* ").strip()]
