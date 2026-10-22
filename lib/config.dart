// Every outside server Arah talks to, in one place. Moving from the free
// demo servers to Arah's own servers before a public launch means editing
// this file only. None of these is a Google service.
class ArahConfig {
  static const appVersion = '0.1.0';

  /// Routing. FOSSGIS demo server: development and small beta only.
  static const valhallaUrl = 'https://valhalla1.openstreetmap.de';

  /// Search-as-you-type. Komoot's demo server: reasonable use only.
  static const photonUrl = 'https://photon.komoot.io';

  /// Online map style (OpenStreetMap data, OpenMapTiles schema).
  static const onlineStyleUrl = 'https://tiles.openfreemap.org/styles/liberty';

  /// Offline packs (map + search + roads) are published as GitHub release
  /// assets of the public data repo.
  static const packCatalogUrl = 'https://github.com/juslangit/arah-data/releases/latest/download/catalog.json';

  /// Reports backend. Empty until the Supabase project exists; the app then
  /// keeps reports on the phone only.
  static const supabaseUrl = String.fromEnvironment('ARAH_SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('ARAH_SUPABASE_ANON_KEY');

  /// FOSSGIS asks apps to identify themselves with X-Client-Id.
  static const serverHeaders = {
    'Content-Type': 'application/json',
    'X-Client-Id': 'arah-navigation',
    'User-Agent': 'Arah/$appVersion (github.com/juslangit/arah)',
  };
}
