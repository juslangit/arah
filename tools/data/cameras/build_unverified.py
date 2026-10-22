#!/usr/bin/env python3
"""Build unverified.json: Malaysian OSM camera nodes that are NOT on JPJ's AwAS list.

These are kept apart from cameras.json (the JPJ set). The app shows them as
"unverified" cameras. Left out on purpose: nodes already used for a JPJ site, their
duplicates, the sites JPJ suspended, old AES sites JPJ no longer lists, and nodes
outside Malaysia (Singapore, Brunei). See NOTES.md.

  kind:        red_light if a mapped traffic signal is within 60 m, else speed
  heading_deg: bearing of the one-way road the node sits on (null if two-way or unclear)
  maxspeed:    the node's tag, else the road's

Run from this folder after build_cameras.py:  ../.venv/bin/python build_unverified.py
"""
import json, os, re, sys, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'scripts'))
from lib import D, hav, nearest_ways  # noqa: E402

OSM = json.load(open(os.path.join(HERE, '..', 'out', 'speed_cameras_osm.json')))
JPJ = json.load(open(os.path.join(HERE, 'cameras.json')))

used = {c['osm_node'] for c in JPJ['cameras'] if c.get('osm_node')}
SKIP = {
    36360549, 6804709747, 9667604207,          # duplicates of JPJ sites
    12389480233, 3665238029, 2539785543,       # suspended by JPJ
    2539785534, 2539785541, 2539785542,        # old AES, not on JPJ's 2022 or 2024 list
    5089448814, 5089469737, 11594141332,       # Brunei / its border
}


def malaysia(lat, lon):
    sg = lat < 1.475 and 103.55 < lon < 104.1
    bn = 4.0 < lat < 5.1 and 114.05 < lon < 115.4 and not (lon > 115.0 and lat > 4.9)
    return not sg and not bn


def num(v):
    m = re.match(r'\d+', v or '')
    return int(m.group()) if m else None


ROADS = ('motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'unclassified', 'residential',
         'motorway_link', 'trunk_link', 'primary_link', 'secondary_link')
sig = D['sig']
out = []
for n in OSM['nodes']:
    if n['id'] in used or n['id'] in SKIP or not malaysia(n['lat'], n['lon']):
        continue
    la, lo = n['lat'], n['lon']
    near_sig = min((hav(la, lo, a, b) for _, a, b in sig if abs(a - la) < 0.01 and abs(b - lo) < 0.01), default=1e9)
    ways = nearest_ways(la, lo, filt=lambda w: w[1] in ROADS, n=1)
    heading, road, way_max = None, '', None
    if ways and ways[0][0] <= 15:
        w = ways[0]
        road = ' '.join(x for x in (w[3], w[4]) if x).strip()
        if w[5] == 'yes':
            heading = w[6]
        way_max = num(D['extra'][w[1]][0])
    kind = 'red_light' if near_sig <= 60 else 'speed'
    out.append({'id': f"osm{n['id']}", 'kind': kind, 'lat': round(la, 6), 'lon': round(lo, 6),
                'maxspeed': None if kind == 'red_light' else (num(n['maxspeed']) or way_max),
                'heading_deg': heading, 'road': n['name'] or road or n['ref'],
                'osm_node': n['id'], 'signal_m': None if near_sig > 1e8 else round(near_sig)})

# Two nodes for one camera (same kind, same direction, < 150 m apart): keep the one nearer a signal.
out.sort(key=lambda c: c['signal_m'] if c['signal_m'] is not None else 1e9)
kept = []
for c in out:
    dup = next((k for k in kept if k['kind'] == c['kind'] and hav(k['lat'], k['lon'], c['lat'], c['lon']) < 150
                and k['heading_deg'] is not None and c['heading_deg'] is not None
                and abs((k['heading_deg'] - c['heading_deg'] + 180) % 360 - 180) < 30), None)
    if dup:
        dup.setdefault('duplicates', []).append(c['osm_node'])
    else:
        kept.append(c)
out = sorted(kept, key=lambda c: (-c['lat'], c['lon']))
json.dump({'updated': datetime.date.today().isoformat(),
           'source': 'OpenStreetMap highway=speed_camera, not on JPJ list (ODbL)',
           'cameras': out}, open(os.path.join(HERE, 'unverified.json'), 'w'), indent=1, ensure_ascii=False)
print(len(out), 'unverified:', sum(c['kind'] == 'speed' for c in out), 'speed,',
      sum(c['kind'] == 'red_light' for c in out), 'red light,',
      sum(c['heading_deg'] is not None for c in out), 'with direction')
for c in out:
    print(f"  {c['id']:>14} {c['kind']:9} {str(c['heading_deg']):>4} {str(c['maxspeed']):>4} sig={c['signal_m']} {c['road']}")
