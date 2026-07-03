#!/usr/bin/env python3
"""Flag pal images that have no usable transparency.

"Who's that Pal?" renders the pal artwork as a solid black silhouette, which
only works when the PNG has a transparent background. Some wiki uploads are
plain screenshots (opaque squares) — this script scans data/images/pals/ and
writes the offenders to data/image_meta.json so the app can keep them out of
silhouette questions. Run after fetch_images.py (refresh.sh does).
"""

import json
from pathlib import Path

from PIL import Image

DATA = Path(__file__).resolve().parent.parent / "data"
PALS = DATA / "images" / "pals"
OUT = DATA / "image_meta.json"

# an image counts as transparent when at least this fraction of its pixels
# is fully see-through (real cutouts are ~40-70%; screenshots are 0%)
MIN_TRANSPARENT_FRACTION = 0.02


def is_opaque(path: Path) -> bool:
    with Image.open(path) as img:
        if img.mode not in ("RGBA", "LA", "PA"):
            img = img.convert("RGBA")
        alpha = img.getchannel("A")
        histogram = alpha.histogram()
        transparent = sum(histogram[:16])  # alpha < 16 ≈ fully see-through
        total = img.width * img.height
    return transparent / total < MIN_TRANSPARENT_FRACTION


def main() -> None:
    opaque = sorted(p.name for p in sorted(PALS.glob("*.png")) if is_opaque(p))
    OUT.write_text(json.dumps({"opaquePalImages": opaque}, indent=1))
    print(f"{len(opaque)}/{len(list(PALS.glob('*.png')))} pal images are opaque squares:")
    for name in opaque:
        print(f"  {name}")


if __name__ == "__main__":
    main()
