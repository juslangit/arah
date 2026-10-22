#!/usr/bin/env python3
"""cameras/cameras.json (sources, notes) → assets/cameras.json (what the app reads).
Until the researched list exists, falls back to OSM's Malaysian cameras."""
import json, os, re
here = os.path.dirname(__file__)
src = os.path.join(here, 'cameras.json')
if os.path.exists(src):
    cams = json.load(open(src))
else:
    osm = json.load(open(os.path.join(here, '..', 'out', 'speed_cameras_osm.json')))
    def heading(d):
        return float(d) if re.fullmatch(r'\d+(\.\d+)?', d or '') else None
    def kmh(v):
        m = re.match(r'\d+', v or '')
        return int(m.group()) if m else None
    # Malaysia only: Singapore sits south of ~1.47 between 103.6 and 104.1 E; Brunei 114–115.4 E north of 4 N.
    def malaysia(c):
        sg = c['lat'] < 1.475 and 103.55 < c['lon'] < 104.1
        bn = 4.0 < c['lat'] < 5.1 and 114.05 < c['lon'] < 115.4 and not (c['lon'] > 115.0 and c['lat'] > 4.9)
        return not sg and not bn
    cams = {'updated': 'osm', 'cameras': [
        {'id': f"osm{c['id']}", 'kind': 'speed', 'lat': c['lat'], 'lon': c['lon'], 'maxspeed': kmh(c['maxspeed']),
         'heading_deg': heading(c['direction']), 'road': c['name'] or c['ref']}
        for c in osm['nodes'] if malaysia(c)]}
keep = ('id', 'kind', 'lat', 'lon', 'maxspeed', 'heading_deg', 'road')
out = {'updated': cams.get('updated', ''), 'cameras': [{k: c.get(k) for k in keep} for c in cams['cameras']]}
# OSM-only cameras that are not on JPJ's list (build_unverified.py): shown as unverified.
unv = os.path.join(here, 'unverified.json')
if os.path.exists(src) and os.path.exists(unv):
    out['cameras'] += [{**{k: c.get(k) for k in keep}, 'verified': False} for c in json.load(open(unv))['cameras']]
path = os.path.join(here, '..', '..', '..', 'assets', 'cameras.json')
json.dump(out, open(path, 'w'), separators=(',', ':'), ensure_ascii=False)
print(f"{len(out['cameras'])} cameras ({sum(c.get('verified') is False for c in out['cameras'])} unverified) → assets/cameras.json")
