# Arah: app study and research brief

Date: 2026-10-22
Scope: a Google-free turn-by-turn navigation app in Flutter, Android first, built for Malaysia.
Status: research only. There is no app code here.

How to read this brief:

- **Part A** covers how the open-source engines work, from their source code and official docs. Each item is cited to a file or URL.
- **Part B** covers UX patterns from public help pages and press coverage. No closed app was decompiled.
- **Part C** gives the recommendation: the v1 screen list, the elements on each screen, and the numeric defaults.

Pinned source revisions (the line numbers below refer to these):

- Organic Maps `master` @ `e9bbd6e403be9d329ccd5471bfbeceba5d3449c5` (2026-10-22). Routing code is under `libs/routing/`.
  Permalink base: `https://github.com/organicmaps/organicmaps/blob/e9bbd6e4/libs/routing/`
- OsmAnd `master` @ `99352a2fec1ab7a71b49f3d7be45b7157d69e68c` (2026-10-21).
  Permalink base: `https://github.com/osmandapp/OsmAnd/blob/99352a2f/OsmAnd/src/net/osmand/plus/routing/`
- Valhalla `master` docs: `docs/docs/api/route/api-reference.md`, and the demo-server section of `README.md`.
- flutter-maplibre-gl @ 2026-09-10 (0.27.1). MapLibre Native Android CHANGELOG up to 13.7.1.
- Protomaps daily build `20261021.pmtiles` (basemap tiles v4.15.2), measured with go-pmtiles v1.31.2.

---

## TL;DR: decisions this research supports

1. **Map display:** MapLibre via `maplibre_gl` 0.27.1. It bundles MapLibre Native Android `android-sdk-opengl:13.5.0`, which supports `pmtiles://file://` local files.
   - The offline basemap is a Protomaps extract of Malaysia: **454 MB** for the whole country (bbox, z0–15) or **226 MB** at z0–14. These figures come from real `--dry-run`s, not estimates.
   - Online fallback style: OpenFreeMap `liberty`.
2. **Routing (v1, online):** Valhalla.
   - Use the FOSSGIS demo server only for development, at 1 request per user per second with bursts of 10. Send `X-Client-Id`, and tell the maintainers via GitHub Discussions before publishing.
   - Plan a self-hosted Valhalla with a Malaysia graph before public release.
   - Valhalla has **no Malay (`ms`) narration**, so Arah must build Bahasa Malaysia instructions itself from the maneuver `type`, `street_names` and `roundabout_exit_count`.
3. **Search:** Photon (photon.komoot.io) for autocomplete, with a location bias and `countrycode=MY`. **Never use Nominatim for autocomplete.** The OSMF policy forbids it.
4. **Location:** use Android `LocationManager` (GPS provider), not FusedLocationProvider, which is part of Google Play services. In Flutter, that means `geolocator` with `forceLocationManager: true`.
5. **Navigation core:** port the two proven algorithms rather than invent new ones.
   - Organic Maps' route-following logic: windowed projection, snap within 50 m, and an off-route counter.
   - OsmAnd's speed-scaled voice-prompt timing.
   - Part C §C3 gives the exact numbers.

---

# Part A: Open-source internals

## A1. Organic Maps (OM): offline routing data and the router

### A1.1 How the offline data is structured

OM ships one `.mwm` file per region. Routing data lives in **named sections inside each MWM** (`defines.hpp`):

| Section tag | Contents |
|---|---|
| `routing` (`ROUTING_FILE_TAG`) | The road graph as an **IndexGraph**: per-feature road geometry plus **Joints**. A Joint is the set of `RoadPoint`s (feature id, point index) where roads connect (`libs/routing/joint.hpp`: "Joint represents roads connection"). It is serialized delta-coded (`index_graph_serialization.hpp`). |
| `cross_mwm` | **Cross-MWM connectors**: the "enter" and "exit" transition segments at region borders, with **precomputed weights between them** (`cross_mwm_connector.cpp`, `cross_mwm_connector_serialization.hpp`). This lets the router "leap" across a region without loading it. |
| `restrictions` | Turn restrictions (no-left-turn, only-straight, and so on). |
| `roadaccess` | Access tags (private, destination, conditional). |
| `maxspeeds` | Per-feature speed limits from OSM `maxspeed`. These feed the speed-limit sign and the edge speed. |
| `altitudes` | Elevation, used for bike and foot climb penalties. |
| `city_roads` | Marks roads inside cities, which get a different default speed. |
| `routing_world` | A world-level graph used for long routes. |

Key point for Arah: **routing data is a compact graph plus per-region border shortcuts.** It is not a tile pyramid, and it is separate from the rendering data. If Arah ever does offline routing, it needs a separate routing package beside the PMTiles basemap (for example a Valhalla tile set), not just map tiles.

### A1.2 The search algorithm

- **A\* with bidirectional search.** `libs/routing/base/astar_algorithm.hpp` exposes `FindPath` and `FindPathBidirectional` / `FindPathBidirectionalEx` (lines ~185–190, plus `BidirectionalStepContext` at ~247). `index_router.cpp` calls `FindPathBidirectionalEx` (line 1072) and `FindPathBidirectional` (line 1647).
- **Two graph modes** (`index_router.cpp:2058`): `starter.GetGraph().SetMode(AreMwmsNear(starter) ? WorldGraphMode::Joints : WorldGraphMode::LeapsOnly)`.
  - When start and finish are near each other, it runs plain A* on the joint graph.
  - When they are far apart, it runs **LeapsOnly**. That search moves between region border points using the precomputed `cross_mwm` weights, then refines the result back to joints (`CalculateSubrouteLeapsOnlyMode`, line 1012; `ProcessLeapsJoints`, line 1200).
- **Heuristic** (`edge_estimator.cpp:190`, `CalcHeuristic`): `distanceM / m_maxWeightSpeedMpS`, the straight-line distance divided by the maximum possible speed, so the heuristic stays admissible.
- **Edge weight (car)**, from `CarEstimator::CalcSegmentWeight` (`edge_estimator.cpp` ~430):
  - The base weight is `distanceM / speed`, where speed comes from the vehicle model, using `maxspeeds` and road class.
  - Traffic adds `× trafficFactor`, plus `× 1.8` for any known non-free-flow traffic.
  - Penalties: **U-turn 120 s** (car) or 20 s (bike); **ferry landing 20 min** (car).
  - The fixed start and end edges use a 16 m/s (57.5 km/h) "leap" speed (`ComputeDefaultLeapWeightSpeed`).
- **Arah takeaway:** this is standard time-weighted A*, so Valhalla gives an equivalent result online. The two ideas worth copying are the **border shortcuts** and the **U-turn penalty of about 2 min**.

### A1.3 Turn instruction generation ("turns" logic)

Files: `turns_generator.cpp`, `car_directions.cpp`, `turns_generator_utils.cpp`, `routing_settings.cpp`.

**1. Measuring the turn angle.** The angle comes from points sampled *some distance away* from the junction, not from the immediately adjacent vertices, so curvy geometry doesn't produce false turns.
- Car settings (`routing_settings.cpp`): `m_minIngoingDistMeters = 100`, `m_minOutgoingDistMeters = 120`, `m_maxIngoingPointsCount = 2`, `m_maxOutgoingPointsCount = 9`.
- The sampling also stops after **3 s of estimated travel** (`turns_generator.cpp:78`, `kMaxTimeSeconds = 3.0`) and interpolates on the edge that overshoots (issue #13152).

**2. Mapping the angle to a direction.** `IntermediateDirection` (`turns_generator_utils.cpp:80`) uses these lower bounds. Positive angles are right turns.

| Angle (deg) | Direction |
|---|---|
| ≥ 145 | TurnSharpRight |
| 50 … 145 | TurnRight |
| 10 … 50 | TurnSlightRight |
| −10 … 10 | GoStraight |
| −50 … −10 | TurnSlightLeft |
| −145 … −50 | TurnLeft |
| < −145 | TurnSharpLeft |

**3. Corrections based on the other exits at the junction ("turn candidates").** The candidates are sorted from leftmost to rightmost.
- If the route takes the **rightmost** candidate, `RightmostDirection` applies, and that table never yields a left turn. The same holds for the leftmost (`car_directions.cpp` ~400–450). Candidates sharper than **90°** are ignored when deciding what counts as leftmost or rightmost.
- `CorrectGoStraight`: if the route goes "straight" but another exit is close in angle, the instruction becomes **TurnSlightLeft/Right ("keep left/right")**.
- **Suppressing turns** (`CanDiscardTurnByHighwayClassOrAngles`, `car_directions.cpp:282–330`): no instruction is given when the route stays on the main road and the other exits are smaller roads or differ enough in angle.
  - `kMinAbsAngleDiffForStraightRoute = 25°`
  - `kMinAbsAngleDiffForBigStraightRoute = 5°`
  - `kMinAbsAngleDiffForSameOrSmallerRoad = 35°`
  - `kMinAbsAngleDiffForGoLink = 70°`
- **Highway exits** (`TryToGetExitDirection`): when the route goes from a highway onto a link road and exactly one highway continuation exists, the instruction is `ExitHighwayToRight` if that continuation lies to the left, and the reverse otherwise. Because it uses geometry, this **works for left-hand traffic** such as Malaysia.

**4. Roundabouts** (`car_directions.cpp:178–230`).
- Entering a roundabout way gives `EnterRoundAbout`, leaving gives `LeaveRoundAbout`, and staying on it at a multi-exit node gives `StayOnRoundAbout`.
- **Exit number:** `FixupCarTurns` counts the `StayOnRoundAbout` nodes between entering and leaving, then calls `SetTurnExits(exitNum + 1)` (lines 30–82).
- On roundabouts of class Tertiary or above, **service roads (driveways, parking aisles) are not counted as exits** (`KeepRoundaboutTurnByHighwayClass`). This matters in Malaysian taman roundabouts that have petrol-station accesses.

**5. Post-processing** (`FixupCarTurns`):
- Merge a "stay on road" with a turn closer than 15 m (`kMergeStayOnRoadAndTurnDistM`).
- Merge the two halves of a turn across a divided road closer than 20 m (`kMergeSegregatedTurnsDistM`). These are very common on Malaysian dual carriageways.
- U-turn detection looks ahead 3 segments with a heading sensitivity of π/10.

**Arah takeaway:** with Valhalla, Arah gets maneuver `type` codes directly (§A3). These OM thresholds are worth reusing only if Arah builds its own maneuver post-processing, for example to suppress the "slight left" chatter Valhalla emits on Malaysian slip roads. In that case, use **±10° straight, 50° normal, 145° sharp** and the **20 m segregated-turn merge**.

### A1.4 Snapping the GPS fix to the route

- `Route::MoveIterator` (`route.cpp:601`) builds a search rectangle around the fix with half-size **`max(m_matchingThresholdM, horizontalAccuracy)`**. The threshold is **car 50 m**, bike 30 m, walk 20 m and transit 40 m (`routing_settings.cpp`). It then calls `FollowedPolyline::UpdateMatchingProjection`.
- `FollowedPolyline::GetBestMatchingProjection` (`base/followed_polyline.cpp` ~133) first looks for the closest projection only within the **current segment and the next 2** (`m_current.m_ind + 3`). Only if that fails does it search the rest of the current sub-route, up to the next checkpoint.
  - This **windowed search** stops the cursor jumping to a parallel or overlapping part of the route, such as a flyover above the road you are on, or the other carriageway.
- `Route::MatchLocationToRoute` (`route.cpp:631`): when the fix is within the threshold and the segment is not a fake start or end segment, the displayed position is **replaced by the projected point**. The **bearing is set to the route segment's bearing** (`m_matchRoute = true` for car). That is the familiar "car arrow glued to the road".
- Lane-info rule: lanes are shown only when the turn is **< 500 m away or < 60 s away** (`routing_session.cpp:17,455`).
- Finish tolerance is **20 m** for car (`m_finishToleranceM`), and **10 m** between intermediate stops (`route.cpp:23`, `kOnEndToleranceM`).

### A1.5 Off-route detection and rerouting

`RoutingSession::OnLocationPositionChanged` (`routing_session.cpp:251–330`):

```
if MoveIterator(fix) succeeds  -> on route; m_moveAwayCounter = 0
else:
   dist = distance(last good projected point, fix)
   if |dist - lastDist| < 0.01 m -> ignore (duplicate fix)
   counter += (speed known && speed >= 3 km/h) ? 2 : 1      // m_minSpeedForRouteRebuildMpS = 3 km/h (car)
   if counter > 10 (kOnRouteMissedCount) -> state = RouteNeedRebuild
```

- In practice, a car moving faster than 3 km/h is declared off-route after **6 consecutive fixes** that fall outside the 50 m-or-accuracy window. At 1 Hz GPS, that is about **6 s**. When stationary or without speed, it takes 11 fixes.
- There is **no explicit distance threshold** apart from the matching window. "Off-route" means "cannot be projected within max(50 m, accuracy) of the current, next and next-but-one segments, or further along the sub-route".
- One good match resets the counter to zero.
- The rebuild re-routes from the current position (`RebuildRoute(... adjustToPrevRoute)`), and the "Recalculating" TTS plays once per rebuild (`m_routingRebuildAnnounceCount`, line 508).

### A1.6 OM voice-prompt timing (for comparison with OsmAnd)

From `turns_notification_manager.cpp` and `turns_sound_settings.cpp`:

- **First prompt** ("In X m, turn left"). It is due when `distToTurn < clamp(30 s × v, 200 m, 2000 m) + clamp(8 s × v, 35 m, 150 m)`.
  - The spoken distance is rounded *up* to one of {200, 300, 400, 500, 600, 700, 800, 900, 1000, 1500, 2000} m.
  - It is skipped if the turn is ≤ 170 m away when it becomes the next turn (`m_minDistToSayNotificationMeters = 170`).
- **Second prompt** ("Turn left" now): `distToTurn < clamp(8 s × v, 35 m, 150 m)`.
- **"Then …" chaining:** if the next turn follows within **400 m**, the second turn is appended with "Then". If the gap is **< 50 m**, its distance is not spoken. Roundabout entry followed by exit is always chained.
- **Worked numbers:**

| Speed | First prompt starts at | Spoken as | "Now" prompt at |
|---|---|---|---|
| 20 km/h | 244 m | "In 200 m" | 44 m |
| 50 km/h | 528 m | "In 500 m" | 111 m |
| 80 km/h | 817 m | "In 700 m" | 150 m |
| 110 km/h | 1067 m | "In 1 km" | 150 m |

---

## A2. OsmAnd: voice-prompt timing and off-route thresholds

### A2.1 Voice prompt timing (`routing/data/AnnounceTimeDistances.java`)

- Everything is computed from the profile's **default speed `V0`**: **car 12.5 m/s (45 km/h)**, bike 2.77 m/s and pedestrian 1.11 m/s. These come from `OsmandSettings.java` lines 1313–1320, and the car value is floored at 8 m/s.
- Constants (seconds × V0):

| Stage | Formula | Car value (V0 = 12.5) | Spoken example |
|---|---|---|---|
| LONG_PREPARE | 300 s × V0 (ends 250 s) | 3750 m | Only for V0 ≥ 30 m/s (>108 km/h); otherwise disabled |
| PREPARE | 115 s × V0 (ends 90 s) | **1438 m** (ends 1136 m) | "In 1.4 km, turn left" |
| TURN_IN | 22 s × V0 (ends 15 s) | **275 m** (ends 189 m) | "In 250 m, turn left" |
| TURN_NOW | V0 × min(√(V0×3.6), 8) s, floor 12 m | **83 m** | "Turn left" |
| ARRIVAL | 5 s × V0, floor 12 m | 63 m | "You have arrived" |
| OFF_ROUTE (voice) | 20 s × V0 | 250 m | — |
| Alarm, short / long | 7 s / 12 s × V0 | 88 / 150 m | speed camera and similar |

- **Speed scaling** (`isDistanceLess`): `trigger if dist <= max(lead, v/V0 × lead) + v × promptDelay`. Lead distances **only grow** with speed above V0. TURN_IN and TURN_NOW are passed the real speed. PREPARE and LONG_PREPARE are passed speed 0, so they are not scaled.
- **Low speed, TURN_NOW** (issue #17376): when `v < V0`, the trigger is `dist <= max(12, v/V0 × 83) + v × delay`.
- **Positioning tolerance** of 12 m: "Pre-pone close announcements … to allow for … positioning error".
- **Prompt delay:** `VOICE_PROMPT_DELAY` is **1500 ms when audio goes to the voice-call/Bluetooth SCO stream**, otherwise 0. The trigger distance grows by `v × 1.5 s` to cover Bluetooth link setup. This is directly relevant to car head units.
- **Skip rules** (`VoiceRouter.java` ~438–530):
  - TURN_IN is skipped if fewer than 15 s remain.
  - PREPARE is skipped if fewer than 150 m remain or V0 < 8 km/h.
  - A combined "turn left then turn right" plays when the next-next turn falls inside TURN_IN.
- OsmAnd's own docs give the same table: <https://osmand.net/docs/technical/algorithms/voice-prompt-triggering>. Its "Announcement time" setting multiplies these values by 1.5 (Early), 1.0, 0.5 (Late) or 0.25 (Very late).

**Worked car numbers with speed scaling:**

| Speed | PREPARE | TURN_IN | TURN_NOW |
|---|---|---|---|
| 20 km/h | 1438 m (rarely spoken; city turns are closer) | 275 m | max(12, 0.44 × 83) = **37 m** |
| 50 km/h | 1438 m | 275 × 1.11 = **306 m** | 83 × 1.11 = **92 m** |
| 110 km/h | 1438 m | 275 × 2.44 = **672 m** | 83 × 2.44 = **203 m** |

### A2.2 Off-route thresholds (`RoutingHelper.java`, `RoutingHelperUtils.java`, `RouteRecalculationHelper.java`)

- `POS_TOLERANCE = 60 m`. With a GPS accuracy figure, `posTolerance = 30 m + accuracy` (`getPosTolerance`, line 753).
- **Allowed deviation** = `posTolerance × 2` (`POS_TOLERANCE_DEVIATION_MULTIPLIER`), which is **120 m** with no accuracy and **80 m with 10 m accuracy**. The user can override it with `ROUTE_RECALCULATION_DISTANCE`.
  - The check uses the **orthogonal distance** from the fix to the current route segment (lines 463–475). If it is greater than the allowed deviation, the user is deviated and a recalculation starts **immediately**, with no time debounce.
- **Wrong direction** (`checkWrongMovementDirection`): the GPS bearing differs by **> 90°** from the route bearing (taken from 15 m behind to the next route point), *and* the distance to the route point exceeds the allowed deviation. Either condition triggers a recalculation. A comment notes a debounce was considered but left out, because "late detection is worse than false positive".
- **U-turn advice** (`identifyUTurnIsNeeded`): the bearing differs by **> 135°** from the bearing to the next route point, the distance exceeds `posTolerance`, and this holds **continuously for 10 s**. Then the app says "make a U-turn when possible".
- **Tunnels:** recalculation is suppressed while the location is simulated inside a tunnel (step 4.5).
- **Recalculation throttle** (`evalWaitInterval`): it starts at 3 s and grows ×1.5 for each recalculation up to **120 s**. It resets to 3 s if the new route points against the direction of travel.
  - After 3 recalculations within 2 min, the next one is a **full** recalculation that does not reuse the previous route (`RECALCULATE_THRESHOLD_COUNT_CAUSING_FULL_RECALCULATE = 3`, `..._INTERVAL = 2 min`).

### A2.3 OM and OsmAnd compared

| | Organic Maps | OsmAnd |
|---|---|---|
| Off-route rule | No projection within max(50 m, accuracy) for about 6 moving fixes | Perpendicular distance > 2 × (30 m + accuracy), immediate; or heading wrong by > 90° |
| Debounce | Counter (about 6 s) | None for distance; 10 s for the U-turn prompt |
| First voice prompt (car, 50 km/h) | about 500 m | 1.4 km "prepare" + about 300 m "in" |
| "Now" prompt (car, 50 km/h) | about 110 m | about 90 m |
| Bluetooth lead | None | +1.5 s × v on the SCO stream |

---

## A3. Valhalla maneuvers, and the policies of the public services

### A3.1 Valhalla route response (`docs/docs/api/route/api-reference.md`)

- **Request essentials for Arah:**
  - `costing`: `auto`, or **`motorcycle`**, which matters because Malaysia has many motorcyclists.
  - `units: "kilometers"`.
  - `alternates: 2`. This is not supported with more than 2 locations or with time-dependent routes.
  - `turn_lanes: true` for lane arrays.
  - Costing options `use_tolls` (< 0.5 avoids tolls), `use_highways` and `use_ferry`.
  - `language`.
  - Optional `"format":"osrm"` with `banner_instructions` / `voice_instructions` for an OSRM/Mapbox-style step format.
- **Supported narration languages:** bg, ca, cs, da, de, el, en-GB, en-US, es, et, fi, fr, he, hi, hu, it, ja, nb, nl, pl, pt-BR, pt-PT, ro, ru, sk, sl, sv, tr, uk. **There is no `ms` or `id`.** Request `en-GB`, and generate Malay text on the device from structured fields.
- **Leg:** `shape` is an **encoded polyline with 6-digit precision**. Maneuvers index into it with `begin_shape_index` / `end_shape_index`.
- **Maneuver fields:**

| Field | Meaning |
|---|---|
| `type` | Maneuver type code (list below) |
| `instruction` | Written instruction |
| `verbal_transition_alert_instruction` | Early "prepare" phrasing, e.g. "Turn right onto North Prince Street" |
| `verbal_pre_transition_instruction` | Phrasing just before the maneuver |
| `verbal_post_transition_instruction` | Phrasing after it, e.g. "Continue on … for 3.9 miles" |
| `verbal_multi_cue` | true if the pre-transition text already has the next maneuver appended ("then …") |
| `street_names`, `begin_street_names` | Street names |
| `length`, `time` | Length in request units; time in s |
| `toll`, `highway`, `rough`, `gate`, `ferry` | Flags |
| `sign` | `exit_number_elements`, `exit_branch_elements`, `exit_toward_elements`, `exit_name_elements`; good for "Exit 225 – Toward Seremban" on the PLUS highway |
| `roundabout_exit_count` | Exit number |
| `bearing_before`, `bearing_after` | Clockwise from north |
| `lanes[]` | Lane data, below |

- **Maneuver type codes:**

| Code | Type | Code | Type |
|---|---|---|---|
| 0 | None | 22 | StayStraight |
| 1 | Start | 23 | StayRight |
| 2 | StartRight | 24 | StayLeft |
| 3 | StartLeft | 25 | Merge |
| 4 | Destination | 26 | RoundaboutEnter |
| 5 | DestinationRight | 27 | RoundaboutExit |
| 6 | DestinationLeft | 28 | FerryEnter |
| 7 | Becomes | 29 | FerryExit |
| 8 | Continue | 30–36 | Transit types |
| 9 | SlightRight | 37 | MergeRight |
| 10 | Right | 38 | MergeLeft |
| 11 | SharpRight | 39 | ElevatorEnter |
| 12 | UturnRight | 40 | StepsEnter |
| 13 | UturnLeft | 41 | EscalatorEnter |
| 14 | SharpLeft | 42 | BuildingEnter |
| 15 | Left | 43 | BuildingExit |
| 16 | SlightLeft | | |
| 17 | RampStraight | | |
| 18 | RampRight | | |
| 19 | RampLeft | | |
| 20 | ExitRight | | |
| 21 | ExitLeft | | |

- **Lanes:** `directions` is a bitmask of all directions the lane allows. `valid` means the lane is usable for the maneuver, and `active` means it is the best lane.
  - Bits: 1 None, 2 Through, 4 SharpLeft, 8 Left, 16 SlightLeft, 32 SlightRight, 64 Right, 128 SharpRight, 256 Reverse, 512 MergeToLeft, 1024 MergeToRight.
- **Malay template plan:** map each `type` to a BM string, for example 10 → "Belok kanan", 15 → "Belok kiri", 9 → "Ikut kanan", 16 → "Ikut kiri", 20 → "Keluar di kanan", 26 → "Di bulatan, ambil susur keluar ke-{n}", 4 → "Anda telah tiba". Then fill in `{street}` from `street_names[0]` and `{toward}` from `sign.exit_toward_elements`. Keep en-GB `verbal_*` as the English voice.

### A3.2 FOSSGIS public Valhalla (`valhalla1.openstreetmap.de`)

- Valhalla README, "Demo Server": FOSSGIS e.V. hosts it with a full planet graph. "Usage of the demo server follows the usual fair-usage policy as OSRM & Nominatim demo servers (somewhat enforced by rate limits)."
- **Rate limits** (maintainer nilsnolde, <https://github.com/valhalla/valhalla/discussions/3373#discussioncomment-1644713>):
  - **1 call per user per second, and 100 calls per second in total.**
  - A later reply (2026-09-05) says **bursts of 10** are allowed (the 11th rapid call is rejected) and per-service limits are "a lot stricter".
- **Identification:** "In case you publish apps to end users … we'd ask you to let us know via Github Discussions and to include an identifying **`X-Client-Id`** request header, e.g. `X-Client-Id: newroutingapp.io`." Also send a descriptive `User-Agent` (`Arah/0.1 (+contact)`) as good practice. The README requires only `X-Client-Id`.
- **Implications for Arah:**
  - Usable for development and a small beta. There is no SLA, and a public app with reroutes every few seconds per user is exactly what fair-use forbids.
  - **Self-host Valhalla with a Malaysia/Singapore/Brunei graph** (Geofabrik extract) before launch. Keep the server URL configurable.
  - Never fire requests on every GPS tick. Reroute only through the off-route logic in §C3.

### A3.3 Komoot Photon (`photon.komoot.io`)

- README "Demo server": "You are welcome to use the API for your project as long as the number of requests stay in a reasonable limit. **Extensive usage will be throttled or completely banned.** We do not give guarantees for availability…". Larger volumes should use a private instance.
- Photon is **built for search-as-you-type**, so it is the right engine for autocomplete. Useful parameters (`docs/api-v1.md`):
  - `q`, `lat`/`lon` with `zoom` and `location_bias_scale` (location bias)
  - `bbox`, `countrycode=MY`, `limit`, `lang`
  - `osm_tag=key:value` or `!key:value`, `layer=city|street|house…`, `dedupe`
  - Reverse geocoding through `/reverse?lon&lat&radius`
- **Arah usage:**
  - Debounce at 300 ms with a minimum of 3 characters, `limit=8`, `countrycode=MY` (or MY,SG,BN), and a bias toward the map centre.
  - Cache results.
  - Plan a self-hosted Photon with a Malaysia index for production.

### A3.4 OpenFreeMap (`tiles.openfreemap.org`)

- Home page and ToS (<https://openfreemap.org>, <https://openfreemap.org/tos/>):
  - "No limits on the number of map views or requests". No API keys. Commercial use allowed.
  - **Attribution required** (OpenFreeMap, OpenMapTiles, OpenStreetMap; MapLibre shows it automatically).
- **Offline downloads** are allowed only if each download is **at most 3,000 tiles or 50 MB**, uses **at most 4 parallel requests**, and is "sent with a **unique User-Agent identifying your app**". Larger downloads need permission (info@openfreemap.org).
  - So OpenFreeMap cannot be the source of a 450 MB country download. Use it for the online style, and Protomaps for offline.
- No SLA: "may discontinue it at any time without notice".
- **Styles** (quick start): `https://tiles.openfreemap.org/styles/liberty`, `…/bright`, `…/positron` (plus dark, fiord and 3D). They work with MapLibre Native. A customized style must be self-hosted.
- The OpenFreeMap styles use the **OpenMapTiles schema**, so they do **not** work with Protomaps tiles, which use their own schema. Pick one style per tile source.

### A3.5 Nominatim: why not for autocomplete

The OSMF Nominatim usage policy (<https://operations.osmfoundation.org/policies/nominatim/>) says:

- "an **absolute maximum of 1 request per second**"
- Apps must identify themselves; "stock User-Agents as set by http libraries will not do".
- Results must be cached.
- **Autocomplete:** "This is not yet supported by Nominatim and **you must not implement such a service on the client side using the API**."
- Periodic or bulk app requests are "strongly discouraged".

Use Nominatim, if at all, only for a single explicit "search" button press or for reverse geocoding a long-press. Photon covers both anyway.

---

## A4. Protomaps PMTiles for an offline Malaysia basemap

### A4.1 Source and CLI

- **Daily planet builds:** `https://build.protomaps.com/YYYYMMDD.pmtiles`. The build list is the JSON at `https://build-metadata.protomaps.dev/builds.json`. The latest at the time of writing was `20261021.pmtiles`: 139 GB, tiles v4.15.2, MVT, z0–15, clustered.
  - Retention: builds from the last week, plus the latest build of each patch version.
  - The docs warn "**hotlinking to these downloads are discouraged**". Extract once and host the result yourself (a CDN or object storage bucket). Licence: ODbL produced work, OpenStreetMap attribution required.
- **CLI** (go-pmtiles, <https://docs.protomaps.com/pmtiles/cli>):

```bash
pmtiles extract https://build.protomaps.com/20261021.pmtiles malaysia.pmtiles \
  --bbox=99.6,0.85,119.3,7.4 --maxzoom=15        # whole Malaysia (incl. bits of TH/ID/SG/BN)
# or a precise outline:
pmtiles extract https://build.protomaps.com/20261021.pmtiles malaysia.pmtiles --region=malaysia.geojson
# --dry-run prints the size without downloading; --download-threads=N speeds it up
```

### A4.2 Measured sizes

These come from `pmtiles extract … --dry-run` on 2026-10-22 against `20261021.pmtiles`:

| Region | bbox | maxzoom | Archive size |
|---|---|---|---|
| Whole Malaysia (one bbox) | 99.6,0.85,119.3,7.4 | 15 | **454 MB** (464,478 tiles) |
| Whole Malaysia | same | 14 | **226 MB** |
| Peninsular Malaysia | 99.6,1.2,104.6,6.8 | 15 | **264 MB** |
| Sabah + Sarawak (+Brunei) | 109.5,0.85,119.3,7.4 | 15 | **147 MB** |
| Klang Valley | 101.3,2.7,102.0,3.4 | 15 | **53 MB** |

Recommendations:

- Offer **three packs**: Semenanjung (264 MB), Sabah & Sarawak (147 MB), and Lembah Klang (53 MB) as a quick starter.
- z14 halves the size. MapLibre can overzoom z14 vector tiles, but street labels and buildings are thinner at high zoom. Keep z15 for Klang Valley at least.
- A `--region` GeoJSON of the country outline would trim the parts of Thailand and Indonesia inside the bbox.

### A4.3 MapLibre Native Android and Flutter support

- **MapLibre Native Android:**
  - PMTiles support arrived in **11.7.0/11.8.0**. The CHANGELOG lists "Add PMTiles support (#2882)" under 11.8.0, and the docs say "Starting MapLibre Android 11.7.0".
  - Later fixes include an ambient cache (13.3.0) and better compression handling (13.0.2).
  - **13.7.1** adds `pmtiles://asset://` for files bundled in the APK.
- Official doc `platform/android/docs/data/PMTiles.md`:
  - `pmtiles://https://…` streams a remote file.
  - **`pmtiles://file://<absolute path>`** reads a file from device storage (use `filesDir` or `getExternalFilesDir`).
  - The URL inside must be fully specified; relative paths are not resolved.
  - "PMTiles sources do not support offline pack downloads or caching". So download the `.pmtiles` file yourself and point the style at it, rather than using MapLibre offline regions.
- **Flutter `maplibre_gl` 0.27.1** (latest, published 2026-09-10):
  - The README feature table lists "GeoJSON, vector, raster & PMTiles sources ✅ ✅ ✅" for Android, iOS and Web.
  - The Android plugin depends on **`org.maplibre.gl:android-sdk-opengl:13.5.0`** (`maplibre_gl/android/build.gradle:68`), so `pmtiles://file://` works. `pmtiles://asset://` (13.7.1) does not yet, so copy any bundled pack to `filesDir` on first run.
  - An example exists: `maplibre_gl_example/lib/examples/advanced/pmtiles.dart`.
  - Changelog note: a style loaded from Flutter assets cannot point `sprite` or `glyphs` at `asset://`. Copy them to disk and use `file://`. Arah needs this for fully offline fonts and sprites.
  - The Android build targets Java 21, and JDK 17 fails.
  - An alternative package exists, `maplibre` 0.3.6 (a newer API). `maplibre_gl` is the mature choice.

### A4.4 Styles that match Protomaps tiles

- Use **`@protomaps/basemaps`** (npm, latest 5.7.2). Flavours: `light`, `dark`, `white`, `grayscale`, `black`.
  - Generate static JSON with `layers("protomaps", namedFlavor("light"), {lang: "en"})`, or with "Get style JSON" at maps.protomaps.com.
  - The source must be `{"type":"vector","url":"pmtiles://file:///data/user/0/<pkg>/files/malaysia.pmtiles"}`.
- Glyphs: `https://protomaps.github.io/basemaps-assets/fonts/{fontstack}/{range}.pbf`. Sprites: `https://protomaps.github.io/basemaps-assets/sprites/v4/light`.
  - **For offline use, download both into the app and rewrite them to `file://`.**
- Style v5 is meant for tiles v4. Pin both and test them together.
- `lang`: set `ms` for Malay names where OSM has `name:ms`. It falls back to `name`.
- **OpenFreeMap liberty, bright and positron are for OpenMapTiles-schema tiles only.** Use them for the *online* mode, or skip them and use Protomaps everywhere. One style family keeps the look consistent.

---

# Part B: UX patterns to borrow

The sources are public help pages and press coverage. Where a detail is observed behaviour rather than documented, it is marked *(observed)*.

## B5. Waze

**Navigation screen layout** *(observed; partly confirmed by help pages and press)*

- **Top:** a turn banner showing the next-maneuver arrow, the distance and the street name. The following turn appears small under it when it is close.
- **Bottom-left:** the **speedometer**. A **speed-limit sign** sits beside it, and the speedometer turns red when you are speeding.
  - Settings → Speedometer: show speedometer, when to show the limit, the speeding threshold, and "Alert when speeding". Source: Waze Help, "Get speed limit alerts", <https://support.google.com/waze/answer/6386895>.
  - At launch the threshold choices were at the limit or 5, 10 or 15 % over (9to5Google, 2016).
- **Bottom bar:** **ETA (arrival time), time remaining and distance remaining**. Tap it for route options such as stops and stopping navigation.
- **Right edge:** the **report button** (a hazard icon) and a sound/mute button. Recenter appears after you pan.
- Report markers on the map along the route, with an alert card ("Police reported ahead") as you approach.

**Report categories** (2024 redesign; 9to5Google, <https://9to5google.com/2024/02/08/waze-reporting-android-ios-update/>):

| Category | Sub-options |
|---|---|
| Traffic | Heavy, Standstill |
| Police | Hidden, Other side |
| Crash | Pile-up, Other side |
| Hazard | Construction, Car on shoulder, Broken traffic light, Pothole, Object |
| Bad weather | Slippery road, Flood, Unplowed road, Fog, Icy road |
| Blocked lane | Left, Center, Right |

- Other top-level items: Map issue, Closure, Gas prices, Roadside help, Map chat, Place.
- Patterns worth copying:
  - **One tap opens the grid, and the second tap picks a sub-option.**
  - The report is **sent automatically after a few seconds with no extra input**, so there is no confirm step while driving.

**Expiry and confirmation** (Waze wiki user manual, "Reporting Live Issues", via forum archives; community answers):

- Live reports show for **about 60 min** by default.
- Another driver tapping **"Not there"** when prompted removes the report early. A **"Thumbs up" or "Still there"** response **resets or extends the timer**.
- The prompt appears only to drivers **travelling in the same direction** as the report, because alerts are directional.
- A Waze staff answer about UK tuning gave per-type timers: **car on shoulder 30 min, object on road 1 h, pothole 7 days**.
- Several "Not there" votes make a report disappear quickly.
- Police reports are manual only. The wiki advises against reporting moving police.

## B6. Google Maps

**Search → place card → directions → navigation.** Google Maps Help, "Get directions & show routes", <https://support.google.com/maps/answer/3273406>:

1. Search, or tap a place, and a **place card** appears in a bottom sheet with Directions, Start, Save and Share.
2. Tap **Directions**, choose the travel mode, and tap **Start**.

**Route alternatives:**
- "If other routes are available, they'll show **in gray** on the map". Tap a grey line to switch.
- *(Observed)* Each alternative has a callout bubble with its duration and a tag such as "Fastest", "Avoids tolls" or "+5 min". The selected route is blue, and the bottom sheet shows the ETA, distance and a toll warning.

**Lane guidance:**
- Shown on the banner, and voice says which lane to use. "Navigation and info about which lane to use aren't available in all countries, regions, and languages."
- *(Observed)* Lane arrows appear under the turn banner as a row: the usable lanes are white and highlighted, the others grey.

**Navigation screen:**
- The **bottom information card** shows ETA, time and distance. Swipe it up for Share trip progress, Search along route, the Directions step list, traffic, satellite and Settings.
- A **Report** button sits on the right. **Close** (stop) is at the bottom left.
- **Sound** (bottom right) has three states: **Mute / Alerts only** (traffic and crash warnings but no turn-by-turn) **/ Unmute**.

**Recenter** *(observed)*: panning the map leaves follow mode and shows a **"Re-centre" button** at the bottom. Tapping it returns to the heading-up 3D follow view. The overview icon shows the whole route.

## B7. Magic Earth

From the Magic Earth FAQ (<https://www.magicearth.com/faq/en>):

- **Offline-first:** "navigation itself keeps working even without a connection". There is no account or login needed for offline maps or navigation.
  - Offline does not include live traffic, transit updates or temporary closures.
- **Map download screen:** Account → Settings → **Offline Maps**. Pick a region and tap Download.
  - **Multiple regions can be queued.** A **Retry** button sits beside a failed region.
  - "Use Wi-Fi for large downloads"; "Map files can be several hundred megabytes"; avoid switching apps or locking the screen during downloads.
  - Maps are **updated from the same screen**. **Delete** is a long-press on Android and a swipe on iOS, and "only removes offline data".
- **Privacy positioning:** "does not track your movements or store a history of your trips"; "Activities are currently stored only locally". This framing fits Arah's Google-free identity.

---

# Part C: Recommendation for Arah v1

## C1. Architecture choices (summary)

| Concern | v1 choice | Why / source |
|---|---|---|
| Map renderer | `maplibre_gl` 0.27.1 | PMTiles `file://` support through MapLibre Android 13.5.0 (§A4.3) |
| Offline basemap | Protomaps extract, self-hosted; packs of 264 / 147 / 53 MB | Measured (§A4.2); hotlinking discouraged |
| Online basemap | The same Protomaps style over a self-hosted remote PMTiles, or OpenFreeMap liberty | OpenFreeMap has no request limits but bans bulk downloads over 50 MB (§A3.4) |
| Routing | Valhalla HTTP. FOSSGIS demo for development (X-Client-Id, 1 req/s), self-hosted for launch | §A3.2 |
| Search | Photon (komoot demo for development, self-hosted later) | §A3.3; Nominatim forbids autocomplete (§A3.5) |
| Location | `geolocator` with `forceLocationManager: true`, GPS at 1 Hz | Avoids Google Play services |
| TTS | `flutter_tts` with the system engine. Ask for an `ms-MY` voice and fall back to `en-GB` | Valhalla has no ms narration (§A3.1) |
| Voice text | Templates on the device built from maneuver `type`, `street_names`, `sign` and `roundabout_exit_count` | §A3.1 |
| Reports | A small backend of Arah's own (e.g. Supabase or PocketBase) with TTL and votes | §B5 |

Note on TTS: on many Android phones the default engine *is* Google's TTS. Arah stays free of Google APIs either way. To avoid Google entirely, offer an open engine such as RHVoice or eSpeak NG on the settings screen.

## C2. Screen list and elements per screen

### S0. First run (3 short steps)

1. **Language**: Bahasa Malaysia or English. This sets both the UI and the voice.
2. **Location permission**: a rationale card, then the system dialog. Ask for "Allow all the time" only when the first navigation starts, for the background foreground-service case. Also ask for the notification permission (Android 13+), which the navigation foreground notification needs.
3. **Offline map offer**: "Muat turun peta Semenanjung (264 MB)?" with buttons Wi-Fi only (default on), Later, and Choose region. This links to S8.

### S1. Map (home / browse)

- Full-screen map, follow-me off, north-up by default.
- **Search bar** pinned at the top ("Cari tempat"), with an avatar or menu icon on the right that opens Settings.
- **Shortcut chips** under the search bar: Rumah, Kerja, Stesen minyak, R&R, Surau/Masjid, Parking. Each chip runs a category search through a Photon `osm_tag` (for example `amenity:fuel`, `highway:services`, `amenity:place_of_worship`).
- **Right-edge FABs**: My-location (tapping again toggles heading-up), Layers (style light/dark, traffic later), Report (works without a route).
- Live **report markers** on the map, filtered to ones that have not expired.
- An **offline badge** when there is no network ("Luar talian – peta tersimpan digunakan").
- **Long-press**: drops a pin and opens S3 with a reverse-geocoded address.
- **Attribution** "© OpenStreetMap, Protomaps" (required).

### S2. Search

- A text field with auto focus, debounced to 300 ms with at least 3 characters, sent to Photon with `countrycode=MY`, `lat/lon` set to the map centre and `limit=8`.
- **Sections** when the field is empty: Saved (Home, Work, Favourites), Recent (the last 20, kept locally), and Categories.
- **Result row**: an icon by type, the name, a secondary line (street, city, state), and the distance from the user. A tap opens S3.
- An **offline fallback** that searches downloaded saved and recent places only, with a notice. Offline full-text search is v2.

### S3. Place card (bottom sheet, three snap heights)

- **Peek**: the name, category and distance, plus the **primary "Arah" (Directions)** button and a secondary "Mula" (Start) button that skips the preview.
- **Half**: the address, coordinates, Save (star), Share (a `geo:` URI or text), and "Set as Home/Work".
- **Full**: the OSM details if present (opening hours, phone, website) and a "Report a map issue" link to OSM notes.

### S4. Route preview (directions)

- The **origin and destination fields** at the top, with a swap button and **+ Add stop** (max 3 stops in v1).
- **Travel mode**: Kereta or Motosikal (Valhalla `auto` or `motorcycle`).
- **Up to 3 routes** on the map. The selected route is in the primary colour and alternatives are grey, following Google Maps.
  - Each route has a **callout bubble** showing its duration and a tag: "Terpantas" (fastest), "Tanpa tol" (no toll), "+6 min".
  - Tap a bubble or a line to select it.
- **Bottom sheet**:
  - The ETA clock time, duration and distance.
  - A **toll icon** if any maneuver has `toll`, and a **ferry icon**.
  - A count of reports on the route (e.g. "2 laporan polis, 1 kemalangan").
  - A big **Mula (Start)** button and a "Langkah" (steps) link to S6.
- **Options** (gear): Elak tol (`use_tolls: 0`), Elak lebuh raya (`use_highways: 0`), Elak feri.
- **Error state**: "Tiada laluan" with Retry. If rate-limited, show "Pelayan sibuk, cuba lagi" with automatic retry after 2 s.

### S5. Turn-by-turn navigation (the core screen)

Layout (portrait). This is a Waze and Google Maps hybrid.

- **Top banner (next maneuver)**, large:
  - The maneuver arrow icon, mapped from Valhalla `type`. For roundabouts it shows the exit number from `roundabout_exit_count`.
  - The **distance to the maneuver**. Above 1 km it shows "1.2 km" in 0.1 km steps. From 100 m to 1 km it rounds to 50 m. Below 100 m it rounds to 10 m.
  - The **target street name**, or the exit sign ("Keluar 225 · Seremban") from `sign.exit_number_elements` / `exit_toward_elements`.
  - A **"Kemudian" (Then) strip** under the banner when the following maneuver is ≤ 400 m after this one (the OM rule).
  - A **lane row** under the banner when `lanes` is present and the maneuver is ≤ 500 m away or ≤ 60 s away (OM `kShowLanesMinDistInMeters`). Active lanes are white, valid lanes outlined, and others grey.
- **Map**: follow mode, heading-up, tilt about 45°, zoom tied to speed (z17 below 30 km/h, z16 at 30–70, z15 above 70). The position arrow is snapped to the route (§C3.1). The route line shows the passed part in grey.
- **Bottom-left**:
  - The **speedometer** (current km/h).
  - The **speed-limit sign** (red ring, from OSM `maxspeed`, shown only when known). It turns red when speed exceeds the limit + 5 km/h.
- **Right edge, top to bottom**:
  - **Mute** (3 states, like Google Maps: Bunyi / Amaran sahaja / Senyap)
  - **Report** (big, thumb-reachable)
  - **Overview** (shows the whole route)
- **Bottom bar**: the **ETA clock time** (biggest), the remaining time and the remaining km.
  - Tap or swipe up to open: Add stop (fuel, R&R along the route), Steps list, Share ETA (text only), Route options, and **Tamat (End)**, which needs a confirm tap.
- **Re-centre pill**: appears when the user pans. It follows Google Maps behaviour and **auto re-centres after 10 s without touch**.
- **Alert cards** (top, below the banner): an approaching report such as "Polis dilaporkan · 400 m". When passing it, the card turns into **"Masih ada?" with Ya / Tiada** buttons (§C3.4), and it auto-dismisses after 8 s.
- **Status overlays**:
  - "Mengira semula laluan…" while rerouting.
  - "Isyarat GPS lemah" after 10 s with no fix (OsmAnd uses 20 s for the voice).
  - The offline badge.
- The screen stays on, with a foreground notification showing the next maneuver and the ETA.

### S6. Steps list (overlay from S4 or S5)

- One row per maneuver: icon, instruction, distance. Toll and ferry flags appear inline. A tap previews that spot on the map.

### S7. Report sheet

- A **6-tile grid**, the first tap: Polis, Kemalangan, Kesesakan, Bahaya, Banjir, Jalan ditutup.
  - Flood gets its own top-level tile in Malaysia, where Waze puts it under "Bad weather".
- **Sub-options**, the second tap, optional:
  - Polis: Tersorok / Seberang jalan
  - Kemalangan: Kecil / Besar / Seberang jalan
  - Kesesakan: Sederhana / Teruk / Tidak bergerak
  - Bahaya: Objek di jalan / Kenderaan di bahu jalan / Lubang jalan / Lampu isyarat rosak / Kerja jalan
  - Banjir: Boleh lalu / Tidak boleh lalu
  - Jalan ditutup: (end time optional, default 2 h)
- An **auto-send countdown** of 3 s, cancellable, following Waze. Reports are stamped with location, heading and carriageway direction.
- Only reachable with 2 taps while moving. No text field while speed > 10 km/h.

### S8. Offline maps manager

Modelled on Magic Earth.

- **Downloaded** section: the region name, size on disk, data date ("Data: 21 Okt 2026"), and **Update** when a newer pack exists. Delete is a long-press with confirm.
- **Available** section: Semenanjung Malaysia (264 MB), Sabah & Sarawak (147 MB), Lembah Klang (53 MB). Each row shows its size and a Download button.
- **Queue**: a progress bar per region with MB done / total. **Pause, Resume and Retry** use HTTP Range, because PMTiles is one file and can be resumed. The download runs as a foreground service so screen lock doesn't kill it.
- A **Wi-Fi only** toggle, on by default, and a free-storage readout.
- The footer shows the attribution and licence (ODbL).

### S9. Arrival

- "Anda telah tiba" plus the destination name and the side of the road (from `type` 5/6 DestinationRight/Left).
- Buttons: Done, Save place, and "Cari parking berdekatan".

### S10. Settings

- **Voice**: language (BM/EN), TTS engine shortcut, voice volume, **prompt timing** (Awal / Biasa / Lewat, applied as ×1.5 / ×1.0 / ×0.5 on distances, the OsmAnd approach), **Bluetooth delay compensation** (on by default; adds 1.5 s of lead on SCO, the OsmAnd approach), and "Speak street names".
- **Route**: default mode (Car/Motorcycle), avoid tolls, avoid highways, avoid ferries.
- **Map**: theme (light / dark / auto by sunset), 3D tilt, speed-limit display, the speeding threshold (+0 / +5 / +10 km/h).
- **Data and privacy**: clear recents, report history, servers used (routing, search, tiles) with an editable endpoint in a developer menu, and a statement of no tracking.
- **About**: attributions for OpenStreetMap, Protomaps, OpenFreeMap (if used), Valhalla and Photon, plus open-source licences.

## C3. Numeric defaults

### C3.1 Snapping to the route

| Parameter | Value | Basis |
|---|---|---|
| Matching radius | `max(40 m, GPS accuracy)` for car and motorcycle | OM uses 50 m. 40 m is tighter for Malaysia's dense parallel service roads and frontage lanes along expressways |
| Search window | Current segment and the next 2 first, then the rest of the leg | OM `GetBestMatchingProjection` |
| Snap displayed position | Yes, when within the radius and not on a start/end connector | OM `MatchLocationToRoute` |
| Snap bearing to route | Yes for car and motorcycle, above 5 km/h | OM `m_matchRoute` |
| Arrival radius | 20 m (car), 10 m at intermediate stops | OM finish tolerance |
| GPS rate | 1 Hz; ignore fixes with accuracy > 100 m | Common practice |

### C3.2 Off-route and reroute

| Parameter | Value | Basis |
|---|---|---|
| Off-route distance | Perpendicular distance > **max(40 m, 2 × accuracy)**, capped at **100 m** | Between OM (50 m window) and OsmAnd (2 × (30 + acc), about 80 m) |
| Debounce | Must hold for **≥ 3 consecutive fixes and ≥ 4 s** while speed ≥ 3 km/h. When slower or without speed, require 8 fixes | OM counter (about 6 s moving); OsmAnd has no debounce. 4 s is a compromise for Malaysian flyovers and junction slip roads |
| Wrong direction | Heading differs from the route by > **120°** for **≥ 5 s** and distance > 25 m | OsmAnd: 90° for reroute, 135° for 10 s for U-turn |
| Ignore conditions | Accuracy > 50 m; inside a tunnel (e.g. SMART Tunnel, Penchala Link); speed < 1 m/s and stationary | OsmAnd tunnel rule; OM speed rule |
| Reroute throttle | First reroute immediate, then a minimum gap of **3 s**, ×1.5 per reroute, max **60 s**; reset after 2 min on route | OsmAnd `evalWaitInterval` (3 s → 120 s). Shorter cap because Valhalla is fast |
| Server rate guard | At most 1 Valhalla request per second per device (hard client limit) | FOSSGIS policy |
| "Recalculating" voice | Once per reroute, and not again within 10 s | OM announce-once rule |

### C3.3 Voice prompt distances by speed band

Use the **current speed, smoothed over 5 s**, to pick the band, and recompute each fix. Each maneuver gets at most three prompts:

- **Early**: "Dalam 2 km, keluar di kiri ke arah Seremban"
- **Mid**: "Dalam 300 m, belok kiri ke Jalan Ampang"
- **Now**: "Belok kiri" (+ "kemudian belok kanan" if the next maneuver is ≤ 400 m away)

| Speed band | Typical road (MY) | Early | Mid ("In X m") | Now | Notes |
|---|---|---|---|---|---|
| **< 30 km/h** | Taman, town centre, jam | — | **150 m** | **30 m** | OsmAnd TURN_NOW floor of 12 m + 37 m at 20 km/h; OM gives 44 m |
| **30–60 km/h** | Urban arterials (Jalan Tun Razak) | — | **300 m** | **80 m** | OsmAnd at 50 km/h: 306 / 92 m; OM: 500 / 111 m |
| **60–90 km/h** | Federal roads, MRR2, DUKE | **1 km** | **500 m** | **150 m** | OM caps "now" at 150 m; OsmAnd at 80 km/h about 490 / 148 m |
| **> 90 km/h** | PLUS, LPT, expressways | **2 km** | **1 km** | **250 m** | OsmAnd at 110 km/h: 672 / 203 m (+ 1.4 km prepare); add margin for lane changes to exits |

Rules:

1. **Mid formula** (for any speed): `mid = clamp(v × 25 s, 150 m, 1000 m)`, rounded up to {150, 200, 300, 400, 500, 600, 800, 1000} m. **Now formula**: `now = clamp(v × 6 s, 30 m, 250 m)`.
   - **Add `v × 1.5 s`** to both when audio goes over Bluetooth SCO, the OsmAnd `VOICE_PROMPT_DELAY` approach.
   - Add a **12 m positioning tolerance** to the "now" trigger, the OsmAnd approach.
2. **Skip rules:**
   - Skip Early if the maneuver is less than 1.5 × the mid distance away when it becomes next.
   - Skip Mid if fewer than **15 s** remain (OsmAnd TURN_IN_END).
   - Never play two prompts within **4 s**. Drop the older one.
3. **Chaining:** if the next maneuver is ≤ **400 m** after this one, append "kemudian …" to the Now prompt. If the gap is < **50 m**, omit its distance (OM).
4. **Roundabouts:** speak the exit number in Mid and Now ("Di bulatan, ambil susur keluar ketiga"). Speak "Keluar sekarang" on the `RoundaboutExit` maneuver.
5. **Long straight:** after a maneuver, if the next is > 3 km away, say "Teruskan sejauh X km" once (Valhalla `verbal_post_transition_instruction`, the OsmAnd go-ahead).
6. **Arrival:** "Destinasi di sebelah kiri dalam 100 m" at `max(12 m, v × 5 s)` + 50 m, and "Anda telah tiba" at 20 m.
7. **User timing setting:** multiply all distances by 1.5 (Awal), 1.0 (Biasa) or 0.5 (Lewat).

### C3.4 Report expiry and confirmation

| Report type | Base lifetime | "Masih ada" (Ya) | "Tiada" (No) | Notes |
|---|---|---|---|---|
| Polis | **60 min** | +30 min (cap 2 h) | 2 "Tiada" votes remove it | Waze default about 60 min |
| Kemalangan | **60 min** | +30 min (cap 3 h) | 2 votes remove it | |
| Kesesakan | **30 min** | +15 min (cap 2 h) | 1 vote −15 min; 2 remove it | Jams clear fast |
| Bahaya: objek di jalan | **60 min** | +30 min | 2 remove it | Waze UK: object 1 h |
| Bahaya: kenderaan di bahu | **30 min** | +15 min | 1 removes it | Waze UK: shoulder 30 min |
| Bahaya: lubang jalan | **7 days** | +7 days | 3 remove it | Waze UK: pothole 7 days |
| Bahaya: lampu isyarat rosak | **4 h** | +2 h | 2 remove it | |
| Bahaya: kerja jalan | **24 h** | +24 h | 3 remove it | |
| Banjir | **3 h** | +1 h (cap 12 h) | 2 remove it | Malaysian monsoon floods last hours |
| Jalan ditutup | **Reporter's end time, default 2 h** | +1 h | 3 remove it | |

Confirmation rules:

- **Ask "Masih ada?" only** to drivers who pass within **150 m** of the report, travelling in the **same direction** (heading within 45° of the report's heading). Each device is asked **once per report**, borrowing Waze's directional alerts.
- **Show the prompt after passing** the point, not before, and only when speed is < 120 km/h. It auto-dismisses after 8 s, and no answer counts as no vote.
- The **reporter's own "Tiada"** removes the report at once.
- **Weighting:** in v1, one vote per device per report. A report with **2 "Ya" votes** gets a "Disahkan" (confirmed) badge.
- **Map visibility:** reports older than 50 % of their lifetime are drawn faded. **Voice warning** for police and accidents comes at 500 m (> 60 km/h) or 300 m (otherwise), once per report.
- **Anti-abuse:** max **10 reports per device per hour**; a report must be made while within 200 m of the point and at speed > 0 *or* by long-press while stationary.

## C4. Malaysia-specific notes

- **Left-hand traffic.** Make sure arrow icons for `ExitLeft`, `UturnRight` and so on reflect LHT. Valhalla emits `kUturnRight` / `kUturnLeft` by side, and roundabouts circulate **clockwise**, so the icons must be mirrored versus RHT sets.
- **Divided roads and U-turn bays** are everywhere. Expect many `Uturn*` maneuvers. OM's 2-minute U-turn penalty shows routers weigh them heavily, so check that Valhalla's car costing doesn't produce absurd detours. Tune the costing option `u_turn_penalty` if needed (verify the option name in the Valhalla costing docs).
- **Toll roads:** the toll flag is per maneuver. Show a toll icon in route preview, and offer "Elak tol" (`use_tolls` < 0.5). Valhalla v1 does not estimate toll cost, so leave the amount out.
- **Motorcycles:** offer `motorcycle` costing. Malaysian expressway motorcycle lanes are tagged in OSM in places.
- **Speed limits:** OSM `maxspeed` coverage on PLUS is good (110), but patchy on local roads. Show the sign only when the value is known.

## C5. Open questions to resolve during build

1. Does the system TTS on target test phones (Samsung, Xiaomi, Oppo) have an `ms-MY` voice offline? If not, fall back to `id-ID` for BM text (close, but worth testing) or `en-GB`.
2. What does a Valhalla Malaysia graph cost to host? It needs a small VPS. Measure the memory once built.
3. Offline routing in v2: a Valhalla mobile build or another on-device router. That needs a separate routing data pack (see A1.1).
4. A Photon self-hosted index for Malaysia only. Confirm the import time and size.
5. Choose one style family (Protomaps `light`/`dark`, recommended) and bundle its fonts and sprites with `file://` URLs.

---

## Sources

**Organic Maps** (commit `e9bbd6e4`, under `libs/routing/`):

- `routing_session.cpp` (lines 15–26, 251–330, 455)
- `route.cpp` (23, 601–650)
- `base/followed_polyline.cpp` (118–175)
- `routing_settings.cpp`
- `turns_notification_manager.cpp` (20–23, 39–46, 155–230, 237–251)
- `turns_sound_settings.cpp` (ComputeTurnDistanceM, ComputeDistToPronounceDistM, GetSoundedDistMeters line 151)
- `turns_generator.cpp` (60–120)
- `turns_generator_utils.cpp` (30–100)
- `car_directions.cpp` (25–82, 175–330, 400–450)
- `edge_estimator.cpp` (190–215, 395–460)
- `index_router.cpp` (930–1072, 1200, 1647, 2058)
- `base/astar_algorithm.hpp`, `joint.hpp`, `index_graph_serialization.hpp`
- `defines.hpp` (section tags)
- Repo: <https://github.com/organicmaps/organicmaps>

**OsmAnd** (commit `99352a2f`):

- `OsmAnd/src/net/osmand/plus/routing/data/AnnounceTimeDistances.java`
- `VoiceRouter.java` (438–531)
- `RoutingHelper.java` (49–54, 450–500, 753–773)
- `RoutingHelperUtils.java` (175–240)
- `RouteRecalculationHelper.java` (42–44, 160–180, 255–272)
- `settings/backend/OsmandSettings.java` (1304–1320, 2063–2070)
- Docs: <https://osmand.net/docs/technical/algorithms/voice-prompt-triggering>, <https://osmand.net/docs/user/navigation/guidance/voice-navigation/>

**Valhalla:**

- <https://github.com/valhalla/valhalla/blob/master/docs/docs/api/route/api-reference.md>
- README "Demo Server": <https://github.com/valhalla/valhalla#demo-server>
- Rate limits: <https://github.com/valhalla/valhalla/discussions/3373#discussioncomment-1644713>

**Photon:**

- <https://photon.komoot.io>
- <https://github.com/komoot/photon/blob/master/README.md>
- <https://github.com/komoot/photon/blob/master/docs/api-v1.md>

**OpenFreeMap:**

- <https://openfreemap.org>
- <https://openfreemap.org/tos/>
- <https://openfreemap.org/quick_start/>

**Nominatim:** <https://operations.osmfoundation.org/policies/nominatim/>

**Protomaps:**

- <https://docs.protomaps.com/pmtiles/cli>
- <https://docs.protomaps.com/basemaps/downloads>
- <https://docs.protomaps.com/basemaps/maplibre>
- <https://github.com/protomaps/basemaps>
- Build list: <https://build-metadata.protomaps.dev/builds.json>
- go-pmtiles v1.31.2

**MapLibre:**

- <https://github.com/maplibre/maplibre-native/blob/main/platform/android/CHANGELOG.md>
- `platform/android/docs/data/PMTiles.md`
- flutter-maplibre-gl: `maplibre_gl/android/build.gradle`, `CHANGELOG.md`, `maplibre_gl/README.md` (<https://github.com/maplibre/flutter-maplibre-gl>)
- pub.dev `maplibre_gl` 0.27.1

**Waze:**

- <https://support.google.com/waze/answer/6386895>
- <https://9to5google.com/2024/02/08/waze-reporting-android-ios-update/>
- <https://9to5google.com/2016/03/29/waze-speed-limit-alerts/>
- Waze wiki "Reporting Live Issues": <https://wazeopedia.waze.com/wiki/Commons/User:Imper1um/Overhaul/User_Manual/Waze_Client/Waze_Map/Reporting_Live_Issues>
- Forum threads:
  - <https://www.waze.com/discuss/t/newbie-how-long-do-reported-hazards-remain-on-map/64592>
  - <https://www.waze.com/discuss/t/police-not-there-longer-hazards/147018>
  - <https://www.waze.com/discuss/t/duration-of-alert/48297>

**Google Maps:** <https://support.google.com/maps/answer/3273406>

**Magic Earth:** <https://www.magicearth.com/faq/en>
