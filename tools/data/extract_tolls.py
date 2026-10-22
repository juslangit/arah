#!/usr/bin/env python3
"""Lists Malaysia's toll plazas from OpenStreetMap (barrier=toll_booth and
highway=toll_gantry), grouped by name, with the highway ref they sit on.
Output: out/toll_plazas_osm.json — the locations; prices come from tolls.json."""
import json, math, sys
from collections import defaultdict
import osmium

class H(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.booths = []      # (name, lat, lon, node id, tags)
        self.ways = {}        # node id -> refs of roads through it
        self.want = set()

    def node(self, n):
        t = n.tags
        if t.get('barrier') == 'toll_booth' or t.get('highway') == 'toll_gantry':
            self.booths.append((t.get('name', ''), n.location.lat, n.location.lon, n.id,
                                {k: v for k, v in t}))
            self.want.add(n.id)

    def way(self, w):
        if 'highway' not in w.tags:
            return
        ref = w.tags.get('ref', '') or w.tags.get('name', '')
        for nd in w.nodes:
            if nd.ref in self.want:
                self.ways.setdefault(nd.ref, set()).add(ref)

h = H()
h.apply_file(sys.argv[1])
groups = defaultdict(list)
for name, lat, lon, nid, tags in h.booths:
    key = name.strip() or f'(unnamed {round(lat, 2)},{round(lon, 2)})'
    groups[key].append((lat, lon, nid, tags))
out = []
for name, pts in sorted(groups.items()):
    # One plaza name can appear at both ends of a highway: split clusters > 3 km apart.
    clusters = []
    for p in pts:
        for c in clusters:
            if abs(c[0][0] - p[0]) < 0.03 and abs(c[0][1] - p[1]) < 0.03:
                c.append(p); break
        else:
            clusters.append([p])
    for c in clusters:
        roads = sorted({r for p in c for r in h.ways.get(p[2], ())} - {''})
        tags = c[0][3]
        out.append({'name': name, 'lat': round(sum(p[0] for p in c) / len(c), 5),
                    'lon': round(sum(p[1] for p in c) / len(c), 5), 'booths': len(c),
                    'roads': roads, 'operator': tags.get('operator', ''),
                    'fee': tags.get('fee', ''), 'charge': tags.get('charge', '')})
json.dump(out, open('out/toll_plazas_osm.json', 'w'), indent=1, ensure_ascii=False)
named = sum(1 for o in out if not o['name'].startswith('(unnamed'))
print(f'{len(out)} plazas ({named} named), {len(h.booths)} booth nodes; '
      f'{sum(1 for o in out if o["charge"])} have an OSM charge tag')
