# Toll dataset notes (tolls.json)

Gathered 2026-10-22. Class 1 (private car) and motorcycle only. Currency MYR.

## How the file is meant to be used

- **`plazas`**: open-system plazas with a fixed charge. Charge `car` each time the route passes one.
  - If `both_directions` is false, charge only when the travel bearing is within about ±60° of `charged_heading_deg`.
  - `penang-second-bridge` has `skip_if_closed_exit: ["plus-bcs"]`. Do not charge it when the trip's PLUS exit gate is Bandar Cassia, because that PLUS fare already includes the RM5.74 bridge toll.
- **`closed`**: closed (entry/exit) systems.
  - The first gate of a system that the route passes is the entry. The next gate of the same system is the exit. Look up `pairs` with `from` = entry and `to` = exit.
  - Pairs are **not always symmetric**: half interchanges and bridge legs differ by direction.
  - A pair with `from == to` is the charge for passing a lone barrier gate with no other gate of that system on the trip, for example Penang Bridge, Tanjung Kupang or Jitra. The PLUS list of these is in `self_pairs_note`.
  - If a pair is missing, use `car_per_km` × the road km between the two gates, never less than `min_car`. Show that price as an estimate.
- **`abolished`**: plazas that no longer charge. Some of them are still in OSM.
- **`ignore_osm`**: OSM "toll" nodes that are not Malaysian road tolls, or that I could not identify. Do not charge at these.
- **Motorcycles are 0 everywhere.**
  - The last motorcycle tolls ended on 2019-01-01: Penang Bridge (was RM1.40), Second Penang Bridge (was RM1.70) and Second Link (was RM1.10). Source: MOF media release of 2018-12-27.
  - Motorcycles are banned from the SMART tunnel.
- **Sabah and Sarawak have no road tolls.**

## Sources and confidence per highway

| Highway | Source | Confidence |
|---|---|---|
| PLUS: NSE E1/E2, NKVE, ELITE E6, Second Link E3, BKE E15, Penang Bridge E36, Seremban–PD E29, BSI | Official PLUS calculator API: `plusapp-api-prod1.azurewebsites.net/api/tolls/GetTollFare/{from}/{to}/1`, used by plus.com.my. All 95×95 pairs were queried. 7,877 valid pairs. | **High** (official, complete) |
| LPT1 + LPT2 E8 (Karak–Kuala Terengganu) | AFA PRIME (formerly ANIH) calculator `afaprime.com/wp-content/toll_rate/lpt.php`. All 342 pairs. | **High** |
| KL–Karak E8 (Gombak RM6.00, Bentong RM3.50) | `afaprime.com/wp-content/toll_rate/klk.php` | High |
| LDP E11 (RM2.10), SPRINT E23 | litrak.com.my toll-fare pages. ALR-owned, rates frozen. | High |
| KESAS E5 (RM2.00) | kesas.com.my | High |
| SMART E38 (RM3.00) | Derived from ALR's Aug 2025 pass offer (44 trips = RM132) | Medium |
| AKLEH, SUKE, SILK, GCE, LKSA, DASH | prolintas.com.my per-highway pages | High; DASH RRIM is medium |
| MEX E20 | mex.com.my | High |
| DUKE E33 (RM2.50) | duke.com.my toll-fare pages (2017 table) | Medium; directions uncertain |
| SPE E39 (RM3.50) | paultan.org 2023-12-08; Wangsa Maju from forum reports only | High / **low** (Ampang location, Wangsa Maju) |
| BESRAYA E9 (RM1.85), NPE E10 | ijmtolldiv.com | High; direction at Mines, PJS2 and PJS5 is medium (taken from OSM geometry) |
| Grand Saga E7 (RM1.30) | grandsaga.com.my | High |
| EKVE E27 (closed) | ekve.com.my. Tolled since 2025-10-25. | High for fares; the two middle gate positions are low |
| LEKAS E21 | Wikipedia (2023-01-01 restructure): RM0.1666/km, Kajang Selatan↔Setul capped at RM5.50, Ampangan RM2.30 open | **Medium**; ramp-gate pairs not verified |
| LATAR E25 | latar.com.my, including the new Eco Grandeur plaza (RM1.15 since 2026-08-07) | High; Kuang direction is medium |
| NNKSB E30 | grandsepadu.com.my | High (mainline); Kapar ramps medium |
| WCE E32 + SKVE E26 (closed) | wce.com.my/toll-rates (official fare data) | High; SKVE-only pairs are **medium** (paultan 2015 table, no later change found, skve site down) |
| Senai–Desaru E22 (closed) | sde22.com/toll-fare (official image) | High |
| Second Penang Bridge E28 (RM5.74, westbound) | jambatankedua.com.my | High |
| Butterworth Outer Ring Road E17 | llb.com.my/tambang-tol | High for rates; direction assumed both |
| Genting Highlands road (RM5 per entry, uphill only) | FMT 2026-05-25. Private road, charging since 2026-05-28. | High (Sempah); Gohtong direction medium |

Several highways are under the government's 2026 rate freeze: SDE, LPT2, LLB, Second Penang Bridge, Grand Saga, LATAR, NNKSB, SKVE, DUKE and MEX.

Many OSM `charge` tags are **out of date**, from before the 2022–2023 cuts:

| Highway | OSM tag | Actual |
|---|---|---|
| AKLEH | 2.50 | 2.13 |
| SILK | 1.80 | 1.66 |
| GCE | 1.90 | 1.75 |
| LKSA | 1.70 / 0.90 | 1.56 / 0.83 |
| BESRAYA | 2.00 | 1.85 |
| Kuang Timur | 1.30 | 2.50 |

Do not use OSM charge tags.

## What is approximate

- **`car_per_km` fallbacks.**
  - The method: median of fare / (great-circle km × 1.2 circuity) over official pairs.
  - PLUS comes out at 0.11, which fits Jalan Duta–Juru at RM35.51 over about 320 km. LPT comes out at 0.114 (official LPT1 ≈ RM0.12/km).
  - EKVE (0.52) and SDE/SKVE (about 0.23) are inflated because their gates are close together and their routes curve a lot. Prefer the pairs, which cover every gate combination there.
  - The LEKAS figure (0.1666) is the official tariff basis.
- **Unconfirmed directions.** Directions taken only from OSM booth geometry are marked medium or low. This covers NPE PJS2/PJS5, BESRAYA Mines, DUKE ramps and LATAR Kuang.
- **Tanjung Kupang (Second Link) and BSI.** The PLUS self-pairs carry no direction. I believe both directions pay, but no official page confirms it.
- **Bandar Gamuda Cove (plus-bgc).** It is not named in OSM. I matched it to the unnamed ELITE booth at 2.88293,101.6245 (KM26.7, opened 2019-09-06).

## Abolished / not charging (some still in OSM)

| Toll | Status | In OSM? |
|---|---|---|
| Bukit Kayu Hitam (PLUS) | Abolished 2018-01-01 | No |
| Batu Tiga and Sungai Rasau (Federal Highway) | Abolished 2018-01-01 | No |
| EDL toll at Bangunan Sultan Iskandar | Abolished 2018-01-01. The PLUS RM2.37 at BSI **still applies**. | Yes |
| Grand Saga: Batu 9 KL-bound and Batu 11 Kajang-bound | Only these directions were abolished, on 2012-03-02. **The other direction of each still pays RM1.30.** | Yes |
| Batang Baram / ASEAN Bridge, Miri | Free for Malaysian vehicles since 2015-06-01 | Yes |
| Lanang Bridge (Sibu) and Tun Salahuddin Bridge (Kuching) | Abolished 2015/2016 | — |
| Motorcycle tolls on the Penang bridges and Second Link | Abolished 2019-01-01 | — |

Not road tolls (in `ignore_osm`): the Singapore ERP gantries, Sentosa and Universal Studios, Taman Johor Jaya booth, Wang Kelian, Timpohon Gate, the Butterworth ferry booth and Penyel campsite.

## Gaps and things to check with Luqman

1. **Grand Saga Batu 9 / Batu 11.** Is it right that one direction still pays RM1.30? The operator page and Wikipedia both say only one side of each plaza was abolished in 2012. He may remember it differently.
2. **Penang Bridge model.**
   - The bridge is PLUS gate `plus-jpp`, westbound only. KL→island pairs include the RM5.74.
   - Island→mainland has no JPP pairs. The KL-bound ticket must come from the next PLUS gate the route passes. Check this against a real island→KL trip.
3. **Second Penang Bridge.** NSE through-traffic pays the bridge at Bandar Cassia, not at the bridge plaza. The RM0.60 link-road charge is assumed to be already inside the PLUS fares.
4. **Unpriced booths.**
   - Plaza Tol Jelapang: it is a PLUS plaza but is not in the PLUS calculator.
   - NNKSB Bukit Raja (RM0.60): its location is unverified, so I left it out to avoid charging at the PLUS Bukit Raja plaza.
   - The Kapar ramps: which one is RM1.40 and which is RM1.60 is unknown.
   - Six unnamed OSM booths: three near Melaka town at 2.21,102.24, one at 3.20,101.79, one at 4.06,103.31 and one at 4.30,101.25.
5. **LEKAS ramp gates** (Semenyih, Eco Majestic, Pajam, Mantin): no per-pair fares found. They fall back to RM0.1666/km.
6. **SPE.** The Ampang plaza location and the Wangsa Maju charge are low confidence.
7. **WCE Section 4** (NKVE–NNKSB) was reported to open on 2026-03-18, but it has no gate or fare in WCE's table yet. **Section 3** (OSM booth at 3.009,101.487) is under construction.
8. **Genting Highlands RM5 road charge.** It is a private road, not an LLM toll. Decide whether the app should show it as "Tol".
9. **Refresh.** The PLUS and LPT tables were crawled from the official calculators. Re-run that crawl when rates change (see below); the next PLUS change is not scheduled, since Class 1 has been frozen since the 18% cut on 2020-02-01.

## How to refresh

Everything needed to rebuild `tolls.json` is in this folder:

| Path | What it is |
|---|---|
| `scripts/crawl_plus.py` | Crawls the PLUS calculator API for every gate pair. Writes `raw/plus_c1.json`. |
| `scripts/crawl_lpt.py` | Crawls the AFA Prime LPT1+LPT2 calculator for every gate pair. Writes `raw/lpt_c1.json`. |
| `scripts/plus_gates.py` | Maps each PLUS gate code to its official name and its OSM booth names. Edit this when PLUS adds a gate. |
| `scripts/build_plus.py` | Turns `raw/plus_c1.json` into `raw/plus_closed.json` (gates with OSM coordinates, valid pairs, per-km ratio). |
| `scripts/build_final.py` | Merges everything into `tolls.json`. |
| `raw/research_A.json`, `raw/research_B.json`, `raw/research_C.json` | Rates gathered by hand from operator sites and news on 2026-10-22: open plazas, EKVE, SDE, WCE/SKVE, abolished plazas. These are not crawled. Edit them by hand when an operator changes a rate. |

Commands, run from the repo root (`arah/`):

```bash
python3 -I tools/data/tolls/scripts/crawl_plus.py      # ~3 min, 9,025 requests -> raw/plus_c1.json
python3 -I tools/data/tolls/scripts/crawl_lpt.py       # ~1 min, 342 requests  -> raw/lpt_c1.json
python3 -I tools/data/tolls/scripts/build_plus.py      # seconds -> raw/plus_closed.json
python3 -I tools/data/tolls/scripts/build_final.py     # seconds -> tools/data/tolls/tolls.json
```

- `build_final.py` takes an optional output path (`build_final.py /tmp/check.json`), so you can diff before overwriting. With the files as committed it reproduces the current `tolls.json` byte for byte (checked 2026-10-22).
- `crawl_plus.py` takes an optional class (default 1) and output path. Only class 1 (car) is used. The API has no motorcycle class except at the Penang Bridge, where it returns 0.
- After a refresh, change `"updated"` in `build_final.py` to the new date, update the dates in this file and check the printout. It lists any OSM booth no longer matched (`UNMATCHED`), duplicate ids, and pair counts per system.
- The OSM input is `tools/data/out/toll_plazas_osm.json`. If a new OSM extract renames a booth, `build_plus.py` stops with an assertion naming the code. Fix the name in `plus_gates.py`.

Courtesy to the official servers:
- **PLUS API:** at most 8 requests in parallel, each with a 30 s timeout and up to 4 retries with backoff (2, 4, 6, 8 s).
- **AFA Prime calculator:** at most 4 requests in parallel with 3 retries.
- Run the crawls only when a rate change is announced, not on a schedule.
- Neither endpoint needs a key. Both are the public back ends of the operators' own calculator pages:
  - PLUS: `https://plusapp-api-prod1.azurewebsites.net/api/tolls/GetTollFare/{from}/{to}/{class}`
  - AFA Prime: `POST https://www.afaprime.com/wp-content/toll_rate/lpt.php?action=submit` with `from`, `to`, `class`.
- If either URL stops working, find the new one in the HTML of the calculator page (plus.com.my home page, `#toll-fare-calculator`).

`slim.py` (not written by me) reduces `tolls.json` to `assets/tolls.json` for the app. It currently drops `skip_if_closed_exit` (Second Penang Bridge), the gate-level `charged_heading_deg` on `plus-jpp` (Penang Bridge, westbound only) and the `ignore_osm` list. Without those, the app will double-charge the second bridge and charge the Penang Bridge eastbound. Add those keys to its keep-lists.
