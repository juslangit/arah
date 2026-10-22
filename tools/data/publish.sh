#!/usr/bin/env bash
# Publishes the offline packs as a GitHub release of juslangit/arah-data and
# writes catalog.json, which the app downloads to know what packs exist.
#
#   ./tools/data/publish.sh            (run from the repo root, after build_all.sh)
#
# Each pack = <id>.pmtiles (map) + <id>.search (places) + <id>.roads (road network).
set -euo pipefail
cd "$(dirname "$0")"
REPO=juslangit/arah-data
DATE=$(date +%Y-%m-%d)
TAG="packs-$DATE"
OUT=out

python3 - "$REPO" "$TAG" "$DATE" "$OUT" > "$OUT/catalog.json" <<'EOF'
import json, os, sys
repo, tag, date, out = sys.argv[1:]
packs = [
  ('semenanjung', 'Semenanjung Malaysia', 'Peninsular Malaysia', [99.6, 1.2, 104.6, 6.8]),
  ('sabah-sarawak', 'Sabah & Sarawak', 'Sabah & Sarawak', [109.5, 0.85, 119.3, 7.4]),
]
cat = {'packs': []}
for pid, ms, en, bbox in packs:
    files = []
    for ext in ('pmtiles', 'search', 'roads'):
        name = f'{pid}.{ext}'
        files.append({'name': name, 'bytes': os.path.getsize(os.path.join(out, name)),
                      'url': f'https://github.com/{repo}/releases/download/{tag}/{name}'})
    cat['packs'].append({'id': pid, 'name_ms': ms, 'name_en': en, 'bbox': bbox, 'date': date, 'files': files})
print(json.dumps(cat, indent=1))
EOF

gh repo view "$REPO" >/dev/null 2>&1 || gh repo create "$REPO" --public \
  --description "Offline map, search and road packs for the Arah navigation app (OpenStreetMap data, ODbL)"
gh release create "$TAG" --repo "$REPO" --title "Packs $DATE" \
  --notes "Map data © OpenStreetMap contributors, ODbL. Map tiles extracted from the Protomaps daily build." \
  "$OUT"/semenanjung.{pmtiles,search,roads} "$OUT"/sabah-sarawak.{pmtiles,search,roads} "$OUT/catalog.json"
# The app always reads releases/latest/download/catalog.json.
echo "published $TAG"
