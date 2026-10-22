#!/usr/bin/env python3
"""tools/data/tolls/tolls.json (with sources and notes) → assets/tolls.json
(only what the app reads). Run after refreshing the rates.
ignore_osm is not needed: the app only charges plazas listed in tolls.json."""
import json, os
here = os.path.dirname(__file__)
d = json.load(open(os.path.join(here, 'tolls.json')))
keep_p = ('id', 'name', 'lat', 'lon', 'car', 'moto', 'both_directions', 'charged_heading_deg', 'skip_if_closed_exit')
keep_c = ('id', 'name', 'car_per_km', 'moto_per_km', 'min_car', 'max_car')
out = {
    'updated': d['updated'],
    'plazas': [{k: p[k] for k in keep_p if k in p} for p in d['plazas']],
    'closed': [dict({k: c[k] for k in keep_c if k in c},
                    gates=[{k: g[k] for k in ('id', 'name', 'lat', 'lon', 'charged_heading_deg') if k in g} for g in c.get('gates', [])],
                    pairs=[{k: q[k] for k in ('from', 'to', 'car', 'moto') if k in q} for q in c.get('pairs', [])])
               for c in d['closed']],
}
path = os.path.join(here, '..', '..', '..', 'assets', 'tolls.json')
json.dump(out, open(path, 'w'), separators=(',', ':'), ensure_ascii=False)
print(f'{os.path.getsize(path) / 1024:.0f} KB → assets/tolls.json')
