# Malaysia fixed enforcement cameras — notes

Built 2026-10-22. Malaysia only (Singapore and Brunei left out). Output: `cameras.json`.

## What the dataset is

The list of sites comes from **JPJ's official AwAS location list**, *LOKASI PENGUATKUASAAN
KAMERA AwAS TERKINI 15.07.2024* (re-uploaded to jpj.gov.my on 2025-04-16). As of
2026-10-22 it is still the newest location list in JPJ's media library (checked through the
site's WordPress media search for "awas", "kamera" and "lokasi"). It has **46 active sites**
(28 expressway speed, 2 federal-road speed, 16 red light) plus 3 suspended.

OSM was used only to **place** those sites, never to add sites. OSM camera nodes that are not
on JPJ's list are left out (listed below).

### Counts

| | Speed | Red light | Total |
|---|---|---|---|
| On JPJ list (active) | 30 | 16 | 46 |
| Placed in `cameras.json` | 30 | 10 | 40 |
| In `unplaced` (no coordinates) | 0 | 6 | 6 |
| Average-speed (point-to-point) | 0 | – | 0 |

Placed cameras by state:

| State | Speed | Red light |
|---|---|---|
| Johor | 4 | 0 |
| Melaka | 4 | 0 |
| Selangor | 5 | 0 |
| Negeri Sembilan | 3 | 0 |
| Kedah | 3 | 3 (+1 unplaced) |
| Pulau Pinang | 1 | 0 |
| Perak | 7 | 5 (+5 unplaced) |
| Terengganu | 2 | 0 |
| Kelantan | 1 | 0 |
| W.P. Kuala Lumpur | 0 | 2 |

Placement: 36 `osm_node`, 3 `km_marker`, 1 `approx`. Confidence: 22 high, 16 medium, 2 low.

Extra fields beyond the requested schema: `osm_node` (the OSM node used, or null), `note`
(how the camera was matched), and a top-level `unplaced` array for JPJ sites that could not
be placed honestly.

## How cameras were placed and checked

1. **OSM camera nodes** (`highway=speed_camera`, from `out/speed_cameras_osm.json`) were matched
   to JPJ sites by name, road and direction.
2. **KM checks along the road.** For each expressway I routed the OSM carriageway with
   `scripts/chain.py` and measured each matched node's distance along it. OSM distances
   agree with JPJ's KM markers:
   - E2 (from the KM 0 milestone at Johor Bahru): Pagoh 151.43 for KM 151.4; Jasin 184.27 for 184.2; Bemban 185.03 for 185; Alor Gajah 214.5 for 214.4; Kajang 301.76 for 301.6; JB 1.0 for KM 1.
   - E1 (from Bukit Kayu Hitam, with a steady ~1.6–2.0 km offset taken off): Kuala Muda 96.3 and 97.1 for 96.3 and 97.2; Nibong Tebal 166.2 for 166; Bandar Baharu 174.1 for 174; Taiping 204.5 for 204.6; Gua Tempurung 300.3 for 299.9 (Kampar). From the south: Slim River 376.2 for 375.9; Behrang 383.1 for 382.8; Bukit Beruntung 432.0 for 431.55.
   - Spacing checks: ELITE KM 17 to KM 28.4 nodes are 11.45 km apart (11.4 expected); LPT2 KM 256.1 to KM 288.6 are 32.75 km apart (32.5 expected); LEKAS Mantin is at ~22 km from the OSM north end (KM 21); GCE node at ~18.7 km from the south end (KM 18).
3. **KM placement** (`scripts/kmplace.py`) for the 3 expressway sites with no OSM node:
   E1 KM 258.25 NB and KM 262.5 SB (Menora Tunnel), and E2 KM 265.3 SB (Nilai–Seremban).
   The point is put at the KM along the OSM carriageway, corrected by the nearest checked
   cameras, then snapped to the carriageway for that direction. Expect ±300 m.
4. **heading_deg** is the bearing of the one-way carriageway the camera sits on, i.e. the
   direction of travel that is enforced. Null where the carriageway can't be told (KM 26 Sungai
   Siput, KM 54 Sungai Petani, KM 8 Teluk Intan). OSM `direction` tags were *not* used: several
   point the opposite way (camera facing) or contradict their own names.
5. **maxspeed** is the OSM limit on that stretch (110 on most expressways, 80 at Menora, 90 on
   FT1 Sungkai and FT8 Gua Musang). It is null for all red-light cameras because OSM's limits
   there are contradictory (for example Jalan Klang Lama: 60 on the way, 110 on the relation).

## What's uncertain

- **Red-light cameras are the weak part.** Six of the 16 have no OSM node and their KM numbers
  are local markers whose starting point I could not pin down. Perak FT1 markers checked
  against two known cameras disagree by about 3 km, which is too loose for a junction camera.
  They are in `unplaced`: FT1 KM 36 Alor Setar–Butterworth, Setiawan–Lumut KM 4 (both
  directions), Setiawan–Ipoh KM 11, Ipoh–Pusing KM 14, and Ipoh–Kampar KM 38.
- **KM 54 Alor Setar–Butterworth** (confidence low): an unnamed OSM camera at the FT1/FT257
  signalised junction in Sungai Petani. It lies 18.8 km along FT1 from Gurun, which fits the
  18 km gap between JPJ's KM 36 and KM 54, but the match is inferred.
- **KM 8 Teluk Intan–Hutan Melintang** (low): the OSM node is labelled "AES KM 7", and the
  nearest mapped traffic signal is 730 m away.
- **Gurun–Sik KM 1 towards Gurun** is placed on the opposite carriageway of the mapped
  towards-Sik camera (`approx`).
- **Directions JPJ does not give:** KM 382.8 Behrang (taken as southbound from JPJ's 2022 list)
  and KM 85.5 Sungkai (taken as southbound from the OSM node's carriageway and motorist.my).
- **Some red-light sites may also enforce speed.** OSM mappers tagged several of them with
  `enforcement=maxspeed`, but JPJ lists them as red-light (*lampu isyarat*) only.
- **No count of a 2024–2026 expansion was found.** I found no official list of new AwAS sites
  for 2025 or 2026. What JPJ did publish:
  - the 2024 list adds 4 sites to the 2022 list (KM 431.55 Rawang–Bukit Beruntung, Menora KM 258.25 and 262.5, KM 265.3 Nilai–Seremban);
  - on 2024-08-08 JPJ said the old Redflex units are being replaced in stages with ANPR cameras at the same gazetted sites;
  - PLUS ran calibration tests at Menora on 2025-09-23 to 25;
  - the Jalan Klang Lama camera was replaced near Pearl Point in February 2025.

  Third-party "2026" lists (motorist.my, carlist.my, ecentral.my, newswav) repeat the JPJ 2024
  list. motorist.my's "highway by highway" list (2026-06-25) adds KESAS KM 33.4, MEX KM 11.6,
  SKVE KM 10.2, red lights at Jalan Skudai and Jalan Biru (Johor), and cameras near Kuching,
  Miri and Kota Kinabalu. It cites no source, contradicts JPJ, and was **not used**.
- **Average speed (point-to-point):** the Transport Minister announced this on 2025-01-07, for
  KL–Karak (Genting Sempah tunnel to Gombak R&R) and the NSE (Senawang toll to Simpang Ampat
  toll). It was due to start in June 2025. On 2025-06-02 the ministry said no start date was set
  (FMT, AutoBuzz). I found no confirmation that it has started, so it has **no entries**. OSM has
  no `enforcement=average_speed` relations in Malaysia.

## Suspended or decommissioned

Suspended by JPJ "for location review" (on both the 2022 and 2024 lists, not in `cameras.json`):
- KM 6.6 SKVE, Jalan Kajang–Puchong (OSM 12389480233 "AES SKVE")
- KM 301.6 NSE Kajang northbound (OSM 3665238029 "AES Kajang - Northbound")
- KM 1.6 Lebuh Sentosa, Kajang to PICC, Putrajaya (OSM 2539785543)

Old AES sites still mapped in OSM but missing from both JPJ lists, so presumed removed:
- AES KM 91 Jalan Ipoh–Butterworth (2539785534)
- AES KM D7.9 Sungai Besi, E37 (2539785541)
- AES Persiaran Timur, Putrajaya (2539785542)

## OSM camera nodes in Malaysia that were left out (not on JPJ's list)

- Sarawak: Miri (12203282701, 12203289401, 12203289501, 12293760591, 12298684951, 12298688533,
  12298692901) and Sibu–Bintulu road (11789095438, 11789095441). JPJ denied a viral claim of
  AwAS cameras in Sarawak on 2023-09-26 (Malay Mail), so these are probably not JPJ cameras.
- Sabah: "Sipitang-Beaufort Speed Camera" (3245903334).
- Penang island: Jalan Ayer Itam, Jalan Scotland, Jalan Kelawai, Jalan Masjid Kapitan Keling,
  Tanjung Bungah (12262831423-5, 12786267647-8, 13858003537). These are probably council
  traffic-light cameras.
- Melaka city (6110034962, 6122463885, 6154342291-2, 11077958600, 12560483103-4), Ipoh's
  Jalan Kuala Kangsar (8104184449, 8104196984, 8104536813), Petaling Jaya (8119172792,
  12485928521-2), and Johor Bahru's Jalan Tebrau (13313055822).
- Duplicates of included sites: 36360549 (Pagoh SB), 6804709747 (GCE NB), 9667604207 (Behrang).
- Near the Brunei border: 5089448814, 5089469737 (Bandar Seri Begawan) and 11594141332.

Since 2026-10-22 the app warns about these too, as a separate **unverified** layer
(`build_unverified.py` → `unverified.json`; `slim.py` adds them to the app asset with
`"verified": false`). They are never mixed into `cameras.json` (the JPJ set). After removing
duplicates there are 27: 11 speed, 16 red light; 26 have a direction.
- kind: red_light if a mapped traffic signal is within 60 m, else speed.
- heading_deg: the bearing of the one-way road the node sits on; null on two-way roads.
- Duplicates (same kind and direction, under 150 m apart) are merged, keeping the node nearer a
  signal: 8104184449 into 8104196984 (Ipoh), 12560483104 into 11077958600 and 6122463885 into
  6154342292 (Melaka).
- The app greys out their map icons, adds "Unverified" to the warning card, and says
  "Possible speed camera ahead". Settings → "Include unverified cameras" turns them off.

## Sources

- JPJ, AwAS location list 15.07.2024 (primary): https://www.jpj.gov.my/wp-content/uploads/2025/04/LOKASI-PENGUATKUASAAN-KAMERA-AwAS-TERKINI-15.07.2024-1-1.pdf
- JPJ, AwAS location list 2022 (45 sites; source of the Behrang direction): https://www.jpj.gov.my/wp-content/uploads/2022/11/LOKASI-PENGUATKUASAAN-KAMERA-AwAS.pdf
- JPJ media statement 2024-08-08, AwAS camera replacement: https://www.jpj.gov.my/wp-content/uploads/2024/08/PR-PENGGANTIAN-KAMERA-AwAS.pdf
- paultan.org 2025-09-23, Menora calibration: https://paultan.org/2025/09/23/ujian-kalibrasi-kamera-awas-di-terowong-menora-meru-pada-23-25-sept-11-malam-3-pagi-plus/
- FMT 2025-06-02, point-to-point not started: https://www.freemalaysiatoday.com/category/nation/2025/06/02/point-to-point-speed-detection-hasnt-started-yet-says-ministry
- AutoBuzz 2025-01-07, P2P announcement: https://autobuzz.my/2025/01/07/new-awas-speed-cameras-to-monitor-vehicle-average-speed-anthony-loke/
- Malay Mail 2023-09-26, Sarawak denial: https://www.malaymail.com/news/malaysia/2023/09/26/jpj-denies-viral-message-claiming-awas-cameras-installed-at-several-locations-in-sarawak/93004
- World of Buzz 2025-02-17, Klang Lama replacement: https://worldofbuzz.com/settle-double-parking-problem-first-lah-msians-react-to-jpj-installing-new-awas-camera-on-old-klang-road/
- motorist.my (secondary, only for the Sungkai direction): https://www.motorist.my/article/4645/latest-aes-awas-camera-locations-across-malaysia-2026
- OpenStreetMap, Geofabrik extract `raw/malaysia-singapore-brunei-latest.osm.pbf` (ODbL; give attribution in the app).

## How to refresh

1. Check JPJ for a newer list. jpj.gov.my resets plain requests, so use `curl --http1.1` and retry:
   `curl -sSL --http1.1 -A "Mozilla/5.0" "https://www.jpj.gov.my/wp-json/wp/v2/media?search=awas&per_page=100"`
   and look for a `LOKASI-PENGUATKUASAAN-KAMERA-AwAS` file newer than 15.07.2024.
   Also search news for "kamera AwAS lokasi baharu" and "point-to-point AwAS".
2. Refresh OSM: `../.venv/bin/python ../extract_cameras.py raw/...pbf` (from `tools/data`), then
   `mkdir -p .work && cd .work && ../../.venv/bin/python ../scripts/extract.py ../../raw/malaysia-singapore-brunei-latest.osm.pbf osm.pkl` (takes a few minutes; about 40 MB).
3. Check matches: `../../.venv/bin/python ../scripts/verify.py` lists every Malaysian OSM camera
   with its road, carriageway bearing and nearest signal.
4. KM placements: build the routes, then place.
   - `../../.venv/bin/python ../scripts/chain.py E2 1.52385,103.7618 3.04608,101.7054 e2nb.json`
   - `../../.venv/bin/python ../scripts/chain.py E1,1,FT1 3.1837,101.59595 6.4967,100.4166 e1nb.json`
   - `../../.venv/bin/python ../scripts/kmplace.py`, which writes `kmplaced.json`.

   For a new KM site, add it to `kmplace.py` and recheck the offset against nearby known cameras.
5. Edit the `SITES` / `UNPLACED` table in `build_cameras.py`, then run
   `../.venv/bin/python build_cameras.py`, `../.venv/bin/python build_unverified.py` and
   `python3 slim.py` from `cameras/`.
6. If an OSM node id disappears, `build_cameras.py` fails with a KeyError. Find the new node with
   `verify.py`, or switch that site to a `km` placement.
