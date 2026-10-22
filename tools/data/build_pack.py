#!/usr/bin/env python3
"""Build Arah's offline data for one region from an OpenStreetMap extract.

Writes two files:
  <region>.roads   the road network the phone routes on (format below)
  <region>.search  an SQLite place index with full-text search

Usage:
  .venv/bin/python build_pack.py raw/malaysia-singapore-brunei-latest.osm.pbf semenanjung out/
  .venv/bin/python build_pack.py raw/malaysia-singapore-brunei-latest.osm.pbf sabah-sarawak out/

ROADS FORMAT (little-endian; every section starts on a 4-byte boundary)
  header: 'ARAHRD01' then u32 version, nodeCount N, edgeCount E, geomCount G,
          nameCount M, nameBytes B, gridRows R, gridCols C, gridEdgeCount K,
          f32 gridMinLat, gridMinLon, gridCellDeg
  i32 nodeLat[N], i32 nodeLon[N]            (degrees * 1e6)
  u8  nodeFlags[N]                          (bit0 = in a big connected network)
  u32 firstEdge[N+1]                        (CSR: edges of node i are firstEdge[i]..firstEdge[i+1])
  u32 edgeTarget[E], u32 edgeLenDm[E], u32 edgeGeom[E]
  u16 edgeGeomCount[E], u32 edgeName[E], u16 edgeFlags[E]
  u8  edgeMaxspeed[E] (km/h, 0 unknown), u8 edgeSpeed[E] (estimated km/h)
  i32 geomLat[G], i32 geomLon[G]            (shape points between the two end nodes)
  u32 nameOffset[M+1], u8 nameBlob[B]       (utf-8 "name\\x1fref\\x1fdestination"; 0 is empty)
  u32 gridStart[R*C+1], u32 gridEdges[K]    (edges by 0.01-degree cell, for snapping)

edgeFlags: bits 0-3 road class (CLASSES below), 4 toll, 5 roundabout, 6 cars allowed,
           7 motorcycles allowed, 8 geometry stored reversed, 9 tunnel, 10 motorway-like.
"""
import array
import math
import os
import re
import sqlite3
import struct
import sys
import time
from collections import defaultdict

import osmium

REGIONS = {
    # Peninsular Malaysia + Singapore (connected by the causeway and second link).
    'semenanjung': (99.0, 0.8, 105.5, 7.5),
    # Sabah, Sarawak, Labuan + Brunei.
    'sabah-sarawak': (109.0, 0.5, 120.0, 7.6),
}

CLASSES = ['motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'unclassified', 'residential',
           'service', 'living_street', 'track', 'motorway_link', 'trunk_link', 'primary_link',
           'secondary_link', 'tertiary_link', 'ferry']
CLASS_ID = {c: i for i, c in enumerate(CLASSES)}
ROAD_ALIASES = {'road': 'unclassified'}
# Typical car speeds on Malaysian roads, km/h, used when no maxspeed is tagged.
SPEED = {'motorway': 100, 'trunk': 75, 'primary': 60, 'secondary': 50, 'tertiary': 40,
         'unclassified': 30, 'residential': 25, 'service': 15, 'living_street': 10, 'track': 12,
         'motorway_link': 55, 'trunk_link': 45, 'primary_link': 40, 'secondary_link': 35,
         'tertiary_link': 30, 'ferry': 15}
NO = {'no', 'private'}

GRID_CELL = 0.01


def parse_speed(v):
    if not v:
        return 0
    m = re.match(r'^\s*(\d+)\s*(mph)?', v)
    if not m:
        return 0
    s = int(m.group(1))
    if m.group(2):
        s = round(s * 1.609)
    return s if 5 <= s <= 150 else 0


def access_ok(tags, *keys):
    """Most specific tag wins: motorcar > motor_vehicle > vehicle > access."""
    for k in keys:
        v = tags.get(k)
        if v is not None:
            return v not in NO
    return True


# Search categories: OSM tag → kind shown in the app.
POI_KEYS = ['amenity', 'shop', 'tourism', 'leisure', 'office', 'healthcare', 'railway',
            'public_transport', 'aeroway', 'historic', 'craft', 'building', 'man_made', 'landuse']
PLACE_RANK = {'city': 90, 'town': 80, 'suburb': 65, 'village': 60, 'quarter': 55,
              'neighbourhood': 50, 'hamlet': 40, 'island': 60, 'locality': 35, 'isolated_dwelling': 20}
KIND_RANK = {'fuel': 45, 'hospital': 50, 'place_of_worship': 40, 'mall': 50, 'station': 50,
             'aerodrome': 70, 'university': 50, 'college': 40, 'school': 30, 'police': 40,
             'services': 50, 'parking': 20, 'restaurant': 25, 'cafe': 20, 'fast_food': 25,
             'supermarket': 30, 'bank': 25, 'atm': 15, 'hotel': 35, 'clinic': 30, 'pharmacy': 25}


class Collector(osmium.SimpleHandler):
    def __init__(self, bbox):
        super().__init__()
        self.w, self.s, self.e, self.n = bbox
        self.ways = []          # (refs array, lat array, lon array, attrs tuple)
        self.places = []        # (name, alt, kind, context, lat, lon, rank)
        self.settlements = []   # (lat, lon, name, rank) for "near ..." context
        self.street_seen = set()

    def inside(self, lat, lon):
        return self.s <= lat <= self.n and self.w <= lon <= self.e

    # ---- search entries -------------------------------------------------
    def add_place(self, tags, lat, lon):
        name = tags.get('name')
        if not name:
            return
        alt = ' '.join(v for k, v in (('name:en', tags.get('name:en')), ('name:ms', tags.get('name:ms')),
                                       ('alt_name', tags.get('alt_name')), ('short_name', tags.get('short_name')),
                                       ('brand', tags.get('brand')), ('official_name', tags.get('official_name')))
                       if v and v != name)
        hw = tags.get('highway')
        if hw in ('services', 'rest_area'):  # R&R and laybys
            self.places.append((name, alt, hw, '', lat, lon, 50 if hw == 'services' else 30))
            return
        place = tags.get('place')
        if place in PLACE_RANK:
            self.places.append((name, alt, place, '', lat, lon, PLACE_RANK[place]))
            if place in ('city', 'town', 'suburb', 'village', 'quarter', 'neighbourhood'):
                self.settlements.append((lat, lon, name, PLACE_RANK[place]))
            return
        for k in POI_KEYS:
            v = tags.get(k)
            if v and v not in ('yes', 'no') or (k == 'building' and v):
                if k in ('building', 'landuse') and not (tags.get('amenity') or tags.get('shop')):
                    # Named buildings/estates are still useful ("Menara KL", "Taman Melawati").
                    kind = 'building' if k == 'building' else 'area'
                else:
                    kind = v
                ctx = ' '.join(x for x in (tags.get('addr:street'), tags.get('addr:postcode'),
                                           tags.get('addr:city')) if x)
                self.places.append((name, alt, kind, ctx, lat, lon, KIND_RANK.get(kind, 20)))
                return
        if tags.get('addr:housenumber') and tags.get('addr:street'):
            self.places.append((name, alt, 'address', tags.get('addr:street', ''), lat, lon, 15))

    def add_address(self, tags, lat, lon):
        hn, st = tags.get('addr:housenumber'), tags.get('addr:street')
        if hn and st and not tags.get('name'):
            ctx = ' '.join(x for x in (tags.get('addr:postcode'), tags.get('addr:city')) if x)
            self.places.append((f'{hn}, {st}', '', 'address', ctx, lat, lon, 10))

    def node(self, n):
        if not n.tags or not n.location.valid():
            return
        lat, lon = n.location.lat, n.location.lon
        if not self.inside(lat, lon):
            return
        t = dict(n.tags)
        self.add_place(t, lat, lon)
        self.add_address(t, lat, lon)

    # ---- roads ----------------------------------------------------------
    def way(self, w):
        t = dict(w.tags)
        hw = t.get('highway')
        is_ferry = t.get('route') == 'ferry'
        try:
            locs = [(nd.ref, nd.location.lat, nd.location.lon) for nd in w.nodes]
        except osmium.InvalidLocationError:
            return
        if len(locs) < 2:
            return
        if not self.inside(locs[0][1], locs[0][2]):
            return

        # Areas with names (malls, campuses, estates, R&Rs) become search entries at their middle.
        if (not hw or hw in ('services', 'rest_area')) and not is_ferry and t.get('name') and w.is_closed():
            lat = sum(l[1] for l in locs) / len(locs)
            lon = sum(l[2] for l in locs) / len(locs)
            self.add_place(t, lat, lon)
            self.add_address(t, lat, lon)
            return
        if not hw and not is_ferry:
            if t.get('addr:housenumber') and w.is_closed():
                self.add_address(t, sum(l[1] for l in locs) / len(locs), sum(l[2] for l in locs) / len(locs))
            return

        cls = 'ferry' if is_ferry else ROAD_ALIASES.get(hw, hw)
        if cls not in CLASS_ID:
            return
        if t.get('area') == 'yes':
            return
        car = access_ok(t, 'motorcar', 'motor_vehicle', 'vehicle', 'access')
        moto = access_ok(t, 'motorcycle', 'motor_vehicle', 'vehicle', 'access')
        if cls == 'track':
            car = car and t.get('tracktype') in (None, 'grade1', 'grade2')
        if is_ferry:
            car = t.get('motorcar') == 'yes' or t.get('motor_vehicle') == 'yes'
            moto = car or t.get('motorcycle') == 'yes'
        if not (car or moto):
            return

        ow = t.get('oneway')
        oneway = 1 if ow in ('yes', '1', 'true') else -1 if ow == '-1' else 0
        roundabout = t.get('junction') in ('roundabout', 'circular')
        if roundabout or cls in ('motorway',) or (cls == 'motorway_link' and ow != 'no'):
            if oneway == 0:
                oneway = 1
        name = t.get('name', '')
        ref = t.get('ref', '').replace(' ', '')
        dest = (t.get('destination') or t.get('destination:ref') or '').replace(';', ' / ')
        attrs = (CLASS_ID[cls], oneway, t.get('toll') == 'yes', roundabout, car, moto,
                 t.get('tunnel') in ('yes', 'building_passage', 'culvert'),
                 parse_speed(t.get('maxspeed')), name, ref, dest)
        self.ways.append((array.array('q', (l[0] for l in locs)),
                          array.array('i', (round(l[1] * 1e6) for l in locs)),
                          array.array('i', (round(l[2] * 1e6) for l in locs)), attrs))

        # One search entry per named street per ~1 km, so "Jalan Ampang" shows once per area.
        if name and not is_ferry:
            mid = locs[len(locs) // 2]
            key = (name, round(mid[1], 2), round(mid[2], 2))
            if key not in self.street_seen:
                self.street_seen.add(key)
                self.places.append((name, ref, 'street', '', mid[1], mid[2], 25))


def haversine(lat1, lon1, lat2, lon2):
    p = math.pi / 180
    a = 0.5 - math.cos((lat2 - lat1) * p) / 2 + math.cos(lat1 * p) * math.cos(lat2 * p) * (1 - math.cos((lon2 - lon1) * p)) / 2
    return 12742000 * math.asin(math.sqrt(a))


def build_graph(ways):
    t0 = time.time()
    use = defaultdict(int)
    for refs, _, _, _ in ways:
        for i, r in enumerate(refs):
            # Ends of every way are always graph nodes; inner nodes only if shared.
            use[r] += 2 if (i == 0 or i == len(refs) - 1) else 1
    node_index = {}
    nlat, nlon = array.array('i'), array.array('i')

    def nid(ref, la, lo):
        i = node_index.get(ref)
        if i is None:
            i = len(nlat)
            node_index[ref] = i
            nlat.append(la)
            nlon.append(lo)
        return i

    names = {'': 0}
    name_list = ['']
    geom_lat, geom_lon = array.array('i'), array.array('i')
    edges = []  # (src, dst, lenDm, geomStart, geomCount, nameId, flags, maxspeed, speed)
    for refs, lats, lons, attrs in ways:
        cls, oneway, toll, rb, car, moto, tunnel, maxspeed, name, ref, dest = attrs
        key = f'{name}\x1f{ref}\x1f{dest}' if (name or ref or dest) else ''
        name_id = names.get(key)
        if name_id is None:
            name_id = len(name_list)
            names[key] = name_id
            name_list.append(key)
        base_flags = cls | (toll << 4) | (rb << 5) | (car << 6) | (moto << 7) | (tunnel << 9) | \
            ((CLASSES[cls] in ('motorway', 'trunk', 'motorway_link', 'trunk_link')) << 10)
        speed = SPEED[CLASSES[cls]]
        if maxspeed:
            speed = max(5, min(round(maxspeed * 0.9), round(speed * 1.3)))
        start = 0
        for i in range(1, len(refs)):
            if i == len(refs) - 1 or use[refs[i]] >= 2:
                a = nid(refs[start], lats[start], lons[start])
                b = nid(refs[i], lats[i], lons[i])
                gs = len(geom_lat)
                length = 0.0
                for j in range(start + 1, i + 1):
                    length += haversine(lats[j - 1] / 1e6, lons[j - 1] / 1e6, lats[j] / 1e6, lons[j] / 1e6)
                for j in range(start + 1, i):
                    geom_lat.append(lats[j])
                    geom_lon.append(lons[j])
                gc = i - start - 1
                ldm = max(1, round(length * 10))
                if a != b or gc > 0:
                    # The last field marks one edge per piece of road for the snapping grid.
                    if oneway >= 0:
                        edges.append((a, b, ldm, gs, gc, name_id, base_flags, maxspeed, speed, True))
                    if oneway <= 0:
                        edges.append((b, a, ldm, gs, gc, name_id, base_flags | (1 << 8), maxspeed, speed,
                                      oneway < 0))
                start = i
    print(f'  graph: {len(nlat):,} nodes, {len(edges):,} edges, {len(geom_lat):,} shape points '
          f'({time.time() - t0:.0f}s)')
    return nlat, nlon, edges, geom_lat, geom_lon, name_list


def components(n, edges):
    """Undirected connected components; flag nodes in networks of 500+ nodes."""
    parent = list(range(n))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for e in edges:
        a, b = find(e[0]), find(e[1])
        if a != b:
            parent[a] = b
    size = defaultdict(int)
    roots = [find(i) for i in range(n)]
    for r in roots:
        size[r] += 1
    flags = array.array('B', (1 if size[r] >= 500 else 0 for r in roots))
    big = sorted(size.values(), reverse=True)[:3]
    print(f'  networks: {len(size):,}; biggest {big}; nodes in big ones: {sum(flags):,}')
    return flags


def pad(f):
    r = f.tell() % 4
    if r:
        f.write(b'\0' * (4 - r))


def write_roads(path, nlat, nlon, flags, edges, geom_lat, geom_lon, name_list):
    n = len(nlat)
    edges.sort(key=lambda e: e[0])
    first = array.array('I', [0] * (n + 1))
    for e in edges:
        first[e[0] + 1] += 1
    for i in range(n):
        first[i + 1] += first[i]
    cols = list(zip(*edges)) if edges else [[]] * 10

    # Snapping grid: every cell an edge's shape passes through lists that edge,
    # so a long expressway stretch is found even 10 km from any junction.
    min_lat = min(nlat) / 1e6
    min_lon = min(nlon) / 1e6
    rows = int((max(nlat) / 1e6 - min_lat) / GRID_CELL) + 1
    ncols = int((max(nlon) / 1e6 - min_lon) / GRID_CELL) + 1
    buckets = defaultdict(list)

    def cell_of(la, lo):
        return int((la / 1e6 - min_lat) / GRID_CELL) * ncols + int((lo / 1e6 - min_lon) / GRID_CELL)

    for ei, e in enumerate(edges):
        if not e[9] or not flags[e[0]]:
            continue
        pts = [(nlat[e[0]], nlon[e[0]])]
        pts += [(geom_lat[e[3] + j], geom_lon[e[3] + j]) for j in range(e[4])]
        pts.append((nlat[e[1]], nlon[e[1]]))
        cells = set()
        for j, (la, lo) in enumerate(pts):
            cells.add(cell_of(la, lo))
            if j:  # long straight segments: add the cells in between too
                pla, plo = pts[j - 1]
                steps = int(max(abs(la - pla), abs(lo - plo)) / (GRID_CELL * 1e6 / 2))
                for k in range(1, steps):
                    cells.add(cell_of(pla + (la - pla) * k // steps, plo + (lo - plo) * k // steps))
        for c in cells:
            buckets[c].append(ei)
    grid_start = array.array('I', [0] * (rows * ncols + 1))
    grid_nodes = array.array('I')
    for cell in range(rows * ncols):
        grid_start[cell] = len(grid_nodes)
        grid_nodes.extend(buckets.get(cell, ()))
    grid_start[rows * ncols] = len(grid_nodes)

    blob = bytearray()
    offsets = array.array('I', [0])
    for s in name_list:
        blob += s.encode('utf-8')
        offsets.append(len(blob))

    with open(path, 'wb') as f:
        f.write(b'ARAHRD01')
        f.write(struct.pack('<9I3f', 1, n, len(edges), len(geom_lat), len(name_list), len(blob),
                            rows, ncols, len(grid_nodes), min_lat, min_lon, GRID_CELL))
        for arr in (nlat, nlon):
            arr.tofile(f)
        flags.tofile(f); pad(f)
        first.tofile(f)
        array.array('I', cols[1]).tofile(f)
        array.array('I', cols[2]).tofile(f)
        array.array('I', cols[3]).tofile(f)
        array.array('H', cols[4]).tofile(f); pad(f)
        array.array('I', cols[5]).tofile(f)
        array.array('H', cols[6]).tofile(f); pad(f)
        array.array('B', (min(255, x) for x in cols[7])).tofile(f); pad(f)
        array.array('B', cols[8]).tofile(f); pad(f)
        geom_lat.tofile(f)
        geom_lon.tofile(f)
        offsets.tofile(f)
        f.write(blob); pad(f)
        grid_start.tofile(f)
        grid_nodes.tofile(f)
    print(f'  wrote {path}: {os.path.getsize(path) / 1e6:.1f} MB')


def write_search(path, places, settlements):
    # "Near ..." context from the closest town/suburb within ~15 km.
    cell = 0.1
    grid = defaultdict(list)
    for s in settlements:
        grid[(int(s[0] / cell), int(s[1] / cell))].append(s)

    def near(lat, lon):
        best, bd = None, 15000
        cy, cx = int(lat / cell), int(lon / cell)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                for s in grid.get((cy + dy, cx + dx), ()):
                    d = haversine(lat, lon, s[0], s[1]) * (1.0 if s[3] >= 60 else 1.6)
                    if d < bd:
                        best, bd = s[2], d
        return best or ''

    if os.path.exists(path):
        os.remove(path)
    db = sqlite3.connect(path)
    db.executescript('''
      PRAGMA page_size=4096;
      CREATE TABLE place(id INTEGER PRIMARY KEY, name TEXT, alt TEXT, kind TEXT, context TEXT,
                         lat REAL, lon REAL, rank INTEGER);
      CREATE VIRTUAL TABLE place_fts USING fts5(name, alt, context, content='place', content_rowid='id',
                         tokenize='unicode61 remove_diacritics 2', prefix='1 2 3');
      CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
      CREATE INDEX place_lat ON place(lat);
    ''')
    rows = []
    for name, alt, kind, ctx, lat, lon, rank in places:
        area = near(lat, lon) if kind not in ('city', 'town') else ''
        context = ', '.join(x for x in (ctx, area) if x and x != name)
        rows.append((name, alt, kind, context, round(lat, 6), round(lon, 6), rank))
    db.executemany('INSERT INTO place(name,alt,kind,context,lat,lon,rank) VALUES (?,?,?,?,?,?,?)', rows)
    db.execute("INSERT INTO place_fts(place_fts) VALUES('rebuild')")
    db.execute("INSERT INTO meta VALUES('built', ?)", (time.strftime('%Y-%m-%d'),))
    db.commit()
    db.execute('VACUUM')
    db.close()
    print(f'  wrote {path}: {len(rows):,} places, {os.path.getsize(path) / 1e6:.1f} MB')


def main():
    pbf, region, out = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(out, exist_ok=True)
    t0 = time.time()
    c = Collector(REGIONS[region])
    c.apply_file(pbf, locations=True, idx='flex_mem')
    print(f'{region}: {len(c.ways):,} road ways, {len(c.places):,} places ({time.time() - t0:.0f}s)')
    nlat, nlon, edges, glat, glon, names = build_graph(c.ways)
    c.ways = None
    flags = components(len(nlat), edges)
    write_roads(os.path.join(out, f'{region}.roads'), nlat, nlon, flags, edges, glat, glon, names)
    write_search(os.path.join(out, f'{region}.search'), c.places, c.settlements)
    print(f'done in {time.time() - t0:.0f}s')


if __name__ == '__main__':
    main()
