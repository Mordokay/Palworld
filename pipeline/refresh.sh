#!/bin/sh
# "Update All": re-mirror the wiki and rebuild data/ + images.
# Run after Palworld game updates (e.g. the 1.0 release). Idempotent; images
# already downloaded are skipped, new/changed pages are re-parsed from scratch.
set -e
cd "$(dirname "$0")"
echo "== 1/3 fetching pages =="
python3 fetch_pages.py
echo "== 2/3 parsing =="
python3 parse.py
echo "== 3/3 fetching images =="
python3 fetch_images.py
echo "Done. Review 'git diff --stat data/' to see what changed, then rebuild the app."
