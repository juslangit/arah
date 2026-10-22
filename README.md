# Arah

Google-free turn-by-turn navigation for Malaysia. Android first, built in Flutter.

- **Map**: OpenStreetMap through MapLibre — OpenFreeMap online, Protomaps packs offline
- **Search**: Photon online, an SQLite full-text index of the region offline
- **Routing**: Valhalla online, Arah's own A* router on the phone offline
- **Navigation**: BM/EN voice built on the phone, lanes, speed limits, reroute
- **Reports**: police, crash, jam, hazard, flood, closure — with "Masih ada?" votes

No Google services: GPS comes from Android's LocationManager, not Play Services.

## Build
```bash
source ~/Documents/dev/tools/flutter-env.sh
flutter test
flutter build apk --debug
```
Offline packs: `tools/data/build_all.sh`, then `tools/data/publish.sh`.
The research behind the design is in `research/app-study.md`.

Map data © OpenStreetMap contributors (ODbL).
