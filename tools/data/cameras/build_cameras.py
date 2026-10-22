#!/usr/bin/env python3
"""Build cameras.json: Malaysia's fixed JPJ AwAS cameras (speed + red light).

The list of sites is JPJ's official one (LOKASI PENGUATKUASAAN KAMERA AwAS TERKINI,
15.07.2024). Each site is placed either on the OSM camera node that matches it (checked
against the KM marker by measuring along the OSM carriageway, see NOTES.md) or on the
carriageway at the KM marker (scripts/kmplace.py -> kmplaced.json).
Sites that cannot be placed honestly go into "unplaced" with no coordinates.

Run from this folder:  ../.venv/bin/python build_cameras.py
"""
import json, os, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
OSM = json.load(open(os.path.join(HERE, '..', 'out', 'speed_cameras_osm.json')))
NODES = {n['id']: n for n in OSM['nodes']}
KM = json.load(open(os.path.join(HERE, 'kmplaced.json')))

JPJ = 'https://www.jpj.gov.my/wp-content/uploads/2025/04/LOKASI-PENGUATKUASAAN-KAMERA-AwAS-TERKINI-15.07.2024-1-1.pdf'

# (id, kind, where, maxspeed, heading, road, state, confidence, note)
#   where = ('osm', node_id) | ('km', key in kmplaced.json) | ('xy', lat, lon) for a derived point
S, R = 'speed', 'red_light'
SITES = [
    # ---- Speed, expressways (JPJ list items 1-28) ----
    ('my-e2-km151.4-nb', S, ('osm', 12383713955), 110, 302, 'E2 NSE KM 151.4 northbound (Pagoh)', 'Johor', 'high', 'OSM "AWAS Pagoh - Northbound"; OSM carriageway chainage 151.43'),
    ('my-e2-km146.8-sb', S, ('osm', 12389362167), 110, 116, 'E2 NSE KM 146.8 southbound (Pagoh)', 'Johor', 'high', 'OSM "AWAS Pagoh - Southbound" (chainage 146.92); a second OSM node 36360549 "KM 146.8 (SB)" sits 250 m away, same site'),
    ('my-e2-km1-nb', S, ('osm', 10738516098), 110, 297, 'E2 NSE KM 1 northbound (Johor Bahru)', 'Johor', 'medium', 'unnamed OSM camera node; chainage 1.0 km from the E2 KM 0 milestone'),
    ('my-e2-km1-sb', S, ('osm', 12109692963), 110, 118, 'E2 NSE KM 1 southbound (Johor Bahru)', 'Johor', 'medium', 'unnamed OSM camera node; chainage 1.0 km from the E2 KM 0 milestone'),
    ('my-e2-km214.4-sb', S, ('osm', 6120175280), 110, 143, 'E2 NSE KM 214.4 southbound (Alor Gajah)', 'Melaka', 'high', 'OSM node named for this site'),
    ('my-e2-km214.4-nb', S, ('osm', 6120175279), 110, 322, 'E2 NSE KM 214.4 northbound (Alor Gajah)', 'Melaka', 'high', 'OSM node named for this site'),
    ('my-e2-km184.2-nb', S, ('osm', 36363022), 110, 272, 'E2 NSE KM 184.2 northbound (Jasin)', 'Melaka', 'high', 'OSM node named for this site'),
    ('my-e2-km185-sb', S, ('osm', 6110021790), 110, 92, 'E2 NSE KM 185 southbound (Bemban/Jasin)', 'Melaka', 'high', 'OSM node named for this site'),
    ('my-e35-km18-nb', S, ('osm', 12389474320), 110, 62, 'E35 Guthrie Corridor Expressway KM 18 northbound', 'Selangor', 'high', 'OSM "AES GCE - Northbound" (duplicate node 6804709747 at same spot)'),
    ('my-e35-km18-sb', S, ('osm', 12389474319), 110, 242, 'E35 Guthrie Corridor Expressway KM 18 southbound', 'Selangor', 'high', 'OSM "AES GCE - Southbound"'),
    ('my-e6-km28.4-nb', S, ('osm', 33504292), 110, 327, 'E6 ELITE KM 28.4 northbound', 'Selangor', 'high', 'OSM "AWAS ELITE - Northbound"; 11.45 km along road from the KM 17 node (expected 11.4)'),
    ('my-e6-km17-sb', S, ('osm', 12252412840), 110, 146, 'E6 ELITE KM 17 southbound', 'Selangor', 'high', 'OSM "AWAS ELITE Highway - Southbound"'),
    ('my-e1-km431.55-sb', S, ('osm', 13110085647), 110, 143, 'E1 NSE KM 431.55 southbound (Rawang - Bukit Beruntung)', 'Selangor', 'high', 'OSM "AES Bukit Beruntung - Southbound"; chainage ~432.0'),
    ('my-e1-km96.3-sb', S, ('osm', 3096723692), 110, 197, 'E1 NSE KM 96.3 southbound (Kuala Muda)', 'Kedah', 'medium', 'unnamed OSM camera node; chainage 96.3 (calibrated)'),
    ('my-e1-km97.2-nb', S, ('osm', 5487831322), 110, 17, 'E1 NSE KM 97.2 northbound (Kuala Muda)', 'Kedah', 'medium', 'unnamed OSM camera node; chainage 97.1 (calibrated)'),
    ('my-e1-km174-nb', S, ('osm', 10694135234), 110, 275, 'E1 NSE KM 174 northbound (Bandar Baharu)', 'Kedah', 'high', 'OSM "AES Bandar Baharu - Northbound"; chainage 174.1'),
    ('my-e1-km166-sb', S, ('osm', 13110063586), 110, 158, 'E1 NSE KM 166 southbound (Seberang Perai Selatan / Nibong Tebal)', 'Pulau Pinang', 'high', 'OSM "AES Nibong Tebal - Southbound"; chainage 166.2'),
    ('my-e1-km375.9-nb', S, ('osm', 12383760728), 110, 323, 'E1 NSE KM 375.9 northbound (Slim River)', 'Perak', 'high', 'OSM "AES Slim River - Northbound"; chainage 376.2'),
    ('my-e1-km204.6-nb', S, ('osm', 9626165816), 110, 12, 'E1 NSE KM 204.6 northbound (Taiping)', 'Perak', 'high', 'OSM "AES Taiping - Northbound"; chainage 204.5'),
    ('my-e1-km299.9-nb', S, ('osm', 6274234495), 110, 304, 'E1 NSE KM 299.9 northbound (Kampar / Gua Tempurung)', 'Perak', 'high', 'OSM "AES PLUS Gua Tempurung - Northbound"; chainage 300.3'),
    ('my-e1-km382.8-sb', S, ('osm', 1754781964), 110, 137, 'E1 NSE KM 382.8 southbound (Behrang)', 'Perak', 'medium', 'JPJ 2024 list gives no direction; JPJ 2022 list says Arah Selatan. OSM node on SB carriageway; duplicate node 9667604207 50 m away'),
    ('my-e1-km258.25-nb', S, ('km', 'e1_258.25_NB'), 80, 256, 'E1 NSE KM 258.25 northbound (Menora Tunnel, Ipoh)', 'Perak', 'medium', 'no OSM node; placed by KM along OSM carriageway, calibrated on the Taiping and Kampar cameras (+/- ~300 m). Calibration tests reported Sept 2025 (paultan.org)'),
    ('my-e1-km262.5-sb', S, ('km', 'e1_262.5_SB'), 80, 86, 'E1 NSE KM 262.5 southbound (Menora Tunnel)', 'Perak', 'medium', 'no OSM node; placed by KM along OSM carriageway, calibrated on the Taiping and Kampar cameras (+/- ~300 m)'),
    ('my-e21-km21-sb', S, ('osm', 12389516612), 110, 127, 'E21 LEKAS KM 21 southbound (Mantin)', 'Negeri Sembilan', 'high', 'OSM "AES Mantin - Southbound"; chainage ~22 from OSM north end'),
    ('my-e21-km21-nb', S, ('osm', 12389516613), 110, 307, 'E21 LEKAS KM 21 northbound (Mantin)', 'Negeri Sembilan', 'high', 'OSM "AES Mantin - Northbound"'),
    ('my-e2-km265.3-sb', S, ('km', 'e2_265.3_sb'), 110, 126, 'E2 NSE KM 265.3 southbound (Nilai - Seremban)', 'Negeri Sembilan', 'medium', 'no OSM node; placed by KM along OSM carriageway (E2 chainage matches JPJ KMs within ~0.2 km at 5 checked cameras)'),
    ('my-e8-km256.1-kl', S, ('osm', 12389499112), 110, 215, 'E8 LPT2 KM 256.1 towards Kuala Lumpur (Perasing)', 'Terengganu', 'high', 'OSM "AES JPJ Perasing"; 32.75 km along road from the KM 288.6 node (expected 32.5)'),
    ('my-e8-km288.6-kt', S, ('osm', 2913745536), 110, 331, 'E8 LPT2 KM 288.6 towards Kuala Terengganu (Chukai)', 'Terengganu', 'high', 'OSM "AES Exit Chukai Eastbound"'),
    # ---- Speed, federal roads (items 29-30) ----
    ('my-ft1-km85.5-sungkai', S, ('osm', 2539785533), 90, 154, 'FT1 Jalan Ipoh - Kuala Lumpur KM 85.5 (Sungkai)', 'Perak', 'medium', 'OSM "AES KM 85.5 Jalan Ipoh-Kuala Lumpur". JPJ gives no direction; node is on the southbound carriageway and motorist.my says southbound'),
    ('my-ft8-km17-guamusang', S, ('osm', 7558328324), 90, 85, 'FT8 Gua Musang - Kuala Krai KM 17 towards Kota Bharu', 'Kelantan', 'medium', 'OSM "AES Gua Musang"; heading = direction away from Gua Musang along the road'),
    # ---- Red light (items 31-46) ----
    ('my-rl-ft175-km1-sik', R, ('osm', 5339362996), None, 90, 'FT175 Jalan Gurun - Sik KM 1 towards Sik (Kuala Muda)', 'Kedah', 'medium', 'unnamed OSM camera node at signalised junction 1.2 km east of FT1 in Gurun'),
    ('my-rl-ft175-km1-gurun', R, ('xy', 5.818223, 100.488198), None, 271, 'FT175 Jalan Gurun - Sik KM 1 towards Gurun (Kuala Muda)', 'Kedah', 'medium', 'opposite carriageway of node 5339362996 (no OSM node of its own)'),
    ('my-rl-ft1-km54', R, ('osm', 5339350341), None, None, 'FT1 Jalan Alor Setar - Butterworth KM 54 (Sungai Petani, FT1/FT257 junction)', 'Kedah', 'low', 'unnamed OSM camera node at a signalised FT1 junction in Sungai Petani; it is 18.8 km along FT1 from Gurun, matching the 18 km gap between JPJ KM 36 and KM 54, but the match is inferred'),
    ('my-rl-pasir-putih-ipoh', R, ('osm', 4924613763), None, 161, 'Jalan Pasir Puteh, Ipoh towards Pasir Pinji', 'Perak', 'high', 'OSM "AES Jalan Pasir Putih" at signal'),
    ('my-rl-ft1-km26-sgsiput', R, ('osm', 2539785532), None, None, 'FT1 Jalan Ipoh - Kuala Kangsar KM 26, Sungai Siput (towards Kuala Kangsar)', 'Perak', 'high', 'OSM "AES KM 26 Jalan Ipoh-Kuala Kangsar", 5 m from signal; heading left null (carriageway not resolvable from OSM)'),
    ('my-rl-ft1-km116-kl', R, ('osm', 13016777226), None, 161, 'FT1 Ipoh - Kuala Lumpur KM 116 (Batang Padang - Slim River) towards Kuala Lumpur', 'Perak', 'medium', 'unnamed OSM camera node at signal; ~30 km along FT1 south of the KM 85.5 camera, as expected'),
    ('my-rl-ft1-km116-ipoh', R, ('osm', 13016777227), None, 343, 'FT1 Ipoh - Kuala Lumpur KM 116 (Batang Padang - Slim River) towards Ipoh', 'Perak', 'medium', 'unnamed OSM camera node at signal'),
    ('my-rl-ft58-km8-telukintan', R, ('osm', 2539785535), None, None, 'FT58 Teluk Intan - Hutan Melintang KM 8 (Jalan Maharaja Lela)', 'Perak', 'low', 'OSM "AES KM 7 Jalan Maharajalela-Teluk Intan"; JPJ says KM 8; nearest mapped signal 730 m away'),
    ('my-rl-klang-lama', R, ('osm', 4924613744), None, 207, 'Jalan Klang Lama, Kuala Lumpur towards Puchong', 'W.P. Kuala Lumpur', 'medium', 'OSM "AES Jalan Klang Lama" on the Puchong-bound carriageway, 55 m from signal (node direction tag 30 conflicts with JPJ "arah Puchong"; JPJ wins). Camera replaced Feb 2025 near Pearl Point'),
    ('my-rl-jalan-ipoh-kl', R, ('osm', 2539785544), None, 310, 'Jalan Ipoh (Jalan Sultan Azlan Shah), Kuala Lumpur towards Sentul', 'W.P. Kuala Lumpur', 'medium', 'OSM "AES Jalan Ipoh" on the Sentul-bound carriageway, 31 m from signal'),
]

UNPLACED = [
    ('my-rl-ft1-km36', R, 'FT1 Jalan Alor Setar - Butterworth KM 36 (Kuala Muda) towards Alor Setar', 'Kedah', 'no OSM node; several signalised junctions on FT1 around Gurun fit, so not placed'),
    ('my-rl-setiawan-lumut-km4-lumut', R, 'Jalan Setiawan - Lumut/Manjung KM 4 towards Lumut', 'Perak', 'no OSM node; KM origin unknown'),
    ('my-rl-setiawan-lumut-km4-setiawan', R, 'Jalan Setiawan - Lumut/Manjung KM 4 towards Setiawan', 'Perak', 'no OSM node; KM origin unknown'),
    ('my-rl-setiawan-ipoh-km11', R, 'Jalan Setiawan - Ipoh KM 11 towards Setiawan', 'Perak', 'no OSM node; KM origin unknown'),
    ('my-rl-ipoh-pusing-km14', R, 'Jalan Ipoh - Pusing KM 14, Ipoh towards Setiawan', 'Perak', 'no OSM node; KM origin unknown'),
    ('my-rl-ipoh-kampar-km38', R, 'FT1 Jalan Ipoh - Kampar KM 38, Kampar towards Ipoh', 'Perak', 'no OSM node; Perak FT1 local KM origins disagree by ~3 km, too loose for a junction camera'),
]

cams = []
for cid, kind, where, ms, hdg, road, state, conf, note in SITES:
    osm_id = None
    if where[0] == 'osm':
        n = NODES[where[1]]; lat, lon, placement, osm_id = n['lat'], n['lon'], 'osm_node', where[1]
    elif where[0] == 'km':
        k = KM[where[1]]; lat, lon, placement = k[0], k[1], 'km_marker'
    else:
        lat, lon, placement = where[1], where[2], 'approx'
    cams.append({'id': cid, 'kind': kind, 'lat': round(lat, 6), 'lon': round(lon, 6), 'maxspeed': ms,
                 'heading_deg': hdg, 'road': road, 'state': state, 'placement': placement,
                 'confidence': conf, 'source': JPJ, 'osm_node': osm_id, 'note': note})

out = {'updated': datetime.date.today().isoformat(),
       'source_list': JPJ,
       'cameras': cams,
       'unplaced': [{'id': c, 'kind': k, 'road': r, 'state': s, 'source': JPJ, 'note': n} for c, k, r, s, n in UNPLACED]}
json.dump(out, open(os.path.join(HERE, 'cameras.json'), 'w'), indent=1, ensure_ascii=False)
print(len(cams), 'placed,', len(UNPLACED), 'unplaced')
