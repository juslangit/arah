#!/usr/bin/env bash
# Rebuilds every offline pack from fresh OpenStreetMap + Protomaps data.
# Needs: tools/data/.venv with pyosmium, ~/.local/bin/pmtiles. About 15 minutes.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p raw out
curl -L -o raw/malaysia-singapore-brunei-latest.osm.pbf \
  https://download.geofabrik.de/asia/malaysia-singapore-brunei-latest.osm.pbf
BUILD=$(curl -s https://build-metadata.protomaps.dev/builds.json | python3 -c "import json,sys;print(sorted(b['key'] for b in json.load(sys.stdin))[-1])")
~/.local/bin/pmtiles extract "https://build.protomaps.com/$BUILD" out/semenanjung.pmtiles --bbox=99.6,1.2,104.6,6.8 --maxzoom=15
~/.local/bin/pmtiles extract "https://build.protomaps.com/$BUILD" out/sabah-sarawak.pmtiles --bbox=109.5,0.85,119.3,7.4 --maxzoom=15
# A half-written archive (disk full, dropped connection) must never ship.
for f in out/semenanjung.pmtiles out/sabah-sarawak.pmtiles; do ~/.local/bin/pmtiles verify "$f"; done
for region in semenanjung sabah-sarawak; do
  .venv/bin/python build_pack.py raw/malaysia-singapore-brunei-latest.osm.pbf "$region" out/
done
ls -lh out
