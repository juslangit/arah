#!/usr/bin/env python3
"""Speed cameras in Malaysia from OpenStreetMap: highway=speed_camera nodes and
type=enforcement relations (enforcement=maxspeed). Output: out/speed_cameras_osm.json"""
import json, sys
import osmium

class H(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.cams = {}
        self.rels = []

    def node(self, n):
        t = n.tags
        if t.get('highway') == 'speed_camera' or t.get('enforcement') == 'maxspeed':
            self.cams[n.id] = {'id': n.id, 'lat': round(n.location.lat, 6), 'lon': round(n.location.lon, 6),
                               'maxspeed': t.get('maxspeed', ''), 'direction': t.get('direction', ''),
                               'name': t.get('name', ''), 'operator': t.get('operator', ''), 'ref': t.get('ref', '')}

    def relation(self, r):
        if r.tags.get('type') == 'enforcement' and r.tags.get('enforcement') in ('maxspeed', 'average_speed'):
            self.rels.append({'id': r.id, 'maxspeed': r.tags.get('maxspeed', ''),
                              'kind': r.tags.get('enforcement'),
                              'members': [(m.type, m.ref, m.role) for m in r.members]})

h = H()
h.apply_file(sys.argv[1])
json.dump({'nodes': list(h.cams.values()), 'relations': h.rels}, open('out/speed_cameras_osm.json', 'w'), indent=1)
lat_ok = [c for c in h.cams.values() if c['lat'] > 0.8 and c['lon'] < 120]
print(f"{len(h.cams)} camera nodes, {len(h.rels)} enforcement relations; "
      f"{sum(1 for c in h.cams.values() if c['maxspeed'])} with maxspeed, "
      f"{sum(1 for c in h.cams.values() if c['direction'])} with direction; "
      f"{sum(1 for c in h.cams.values() if c['lat'] < 1.48)} in Singapore-ish latitudes")
