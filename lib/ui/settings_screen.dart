// Settings (app study §S10).
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../config.dart';
import '../core/settings.dart';
import '../nav/phrases.dart';
import '../routing/route_model.dart';
import 'offline_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.settings;
    Widget header(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        t,
        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Tetapan', 'Settings'))),
      body: ListView(
        children: [
          // The web app is online only: no packs to manage or test.
          if (!kIsWeb) ...[
            ListTile(
              leading: const Icon(Icons.download_for_offline),
              title: Text(context.tr('Peta luar talian', 'Offline maps')),
              subtitle: Text(
                app.packs.installed.isEmpty
                    ? context.tr('Tiada dimuat turun', 'None downloaded')
                    : app.packs.installed.values.map((p) => app.tr(p.nameMs, p.nameEn)).join(', '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OfflineScreen())),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.cloud_off),
              title: Text(context.tr('Uji mod luar talian', 'Test offline mode')),
              subtitle: Text(
                context.tr(
                  'Guna peta, carian dan laluan dari telefon sahaja',
                  'Use only the map, search and routes on the phone',
                ),
              ),
              value: s.forceOffline,
              onChanged: (v) => s.forceOffline = v,
            ),
          ],
          header(context.tr('Bahasa & suara', 'Language & voice')),
          ListTile(
            title: Text(context.tr('Bahasa', 'Language')),
            trailing: SegmentedButton<Lang>(
              segments: const [
                ButtonSegment(value: Lang.ms, label: Text('BM')),
                ButtonSegment(value: Lang.en, label: Text('EN')),
              ],
              selected: {s.lang},
              onSelectionChanged: (v) => app.setLang(v.first),
            ),
          ),
          if (app.speech.malayFallback)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(context.tr('Telefon ini tiada suara Bahasa Melayu', 'This phone has no Malay voice')),
              subtitle: Text(
                context.tr(
                  'Arahan dibaca dengan suara ${app.speech.activeLocale ?? '-'}. Pasang suara Melayu dalam tetapan Teks-ke-pertuturan telefon.',
                  'Prompts are read with the ${app.speech.activeLocale ?? '-'} voice. Install a Malay voice in the phone\'s Text-to-speech settings.',
                ),
              ),
            ),
          ListTile(
            title: Text(context.tr('Masa arahan suara', 'Voice prompt timing')),
            trailing: SegmentedButton<double>(
              segments: [
                ButtonSegment(value: 1.5, label: Text(context.tr('Awal', 'Early'))),
                ButtonSegment(value: 1.0, label: Text(context.tr('Biasa', 'Normal'))),
                ButtonSegment(value: 0.5, label: Text(context.tr('Lewat', 'Late'))),
              ],
              selected: {s.voiceTiming},
              onSelectionChanged: (v) => s.voiceTiming = v.first,
            ),
          ),
          SwitchListTile(
            title: Text(context.tr('Pampasan lewat Bluetooth', 'Bluetooth delay compensation')),
            subtitle: Text(
              context.tr('Bercakap 1.5 saat lebih awal untuk audio kereta', 'Speak 1.5 s earlier for car audio'),
            ),
            value: s.bluetoothDelay,
            onChanged: (v) => s.bluetoothDelay = v,
          ),
          ListTile(
            title: Text(context.tr('Kelantangan suara', 'Voice volume')),
            subtitle: Slider(
              value: s.voiceVolume,
              onChanged: (v) {
                s.voiceVolume = v;
                app.speech.setVolume(v);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.record_voice_over),
            title: Text(context.tr('Uji suara', 'Test voice')),
            onTap: () => app.speech.say(
              app.tr('Dalam 300 meter, belok kiri ke Jalan Ampang.', 'In 300 metres, turn left onto Jalan Ampang.'),
            ),
          ),
          header(context.tr('Laluan', 'Route')),
          ListTile(
            title: Text(context.tr('Kenderaan', 'Vehicle')),
            trailing: SegmentedButton<TravelMode>(
              segments: [
                ButtonSegment(
                  value: TravelMode.car,
                  icon: const Icon(Icons.directions_car),
                  label: Text(context.tr('Kereta', 'Car')),
                ),
                ButtonSegment(
                  value: TravelMode.motorcycle,
                  icon: const Icon(Icons.two_wheeler),
                  label: Text(context.tr('Motor', 'Bike')),
                ),
              ],
              selected: {s.mode},
              onSelectionChanged: (v) => s.mode = v.first,
            ),
          ),
          SwitchListTile(
            title: Text(context.tr('Elak tol', 'Avoid tolls')),
            value: s.avoidTolls,
            onChanged: (v) => s.avoidTolls = v,
          ),
          SwitchListTile(
            title: Text(context.tr('Elak lebuh raya', 'Avoid highways')),
            value: s.avoidHighways,
            onChanged: (v) => s.avoidHighways = v,
          ),
          SwitchListTile(
            title: Text(context.tr('Elak feri', 'Avoid ferries')),
            value: s.avoidFerries,
            onChanged: (v) => s.avoidFerries = v,
          ),
          header(context.tr('Peta', 'Map')),
          ListTile(
            title: Text(context.tr('Tema', 'Theme')),
            trailing: SegmentedButton<MapTheme>(
              segments: [
                ButtonSegment(value: MapTheme.auto, label: Text(context.tr('Auto', 'Auto'))),
                ButtonSegment(value: MapTheme.light, label: Text(context.tr('Cerah', 'Light'))),
                ButtonSegment(value: MapTheme.dark, label: Text(context.tr('Gelap', 'Dark'))),
              ],
              selected: {s.theme},
              onSelectionChanged: (v) => s.theme = v.first,
            ),
          ),
          SwitchListTile(
            title: Text(context.tr('Amaran kamera laju', 'Speed camera alerts')),
            subtitle: Text(context.tr('Kamera AWAS / AES di sepanjang laluan', 'AWAS / AES cameras along the route')),
            value: s.cameraAlerts,
            onChanged: (v) => s.cameraAlerts = v,
          ),
          SwitchListTile(
            title: Text(context.tr('Termasuk kamera tidak disahkan', 'Include unverified cameras')),
            subtitle: Text(
              context.tr(
                'Kamera dari OpenStreetMap yang tiada dalam senarai JPJ',
                'Cameras from OpenStreetMap that are not on JPJ\'s list',
              ),
            ),
            value: s.unverifiedCameras,
            onChanged: s.cameraAlerts ? (v) => s.unverifiedCameras = v : null,
          ),
          SwitchListTile(
            title: Text(context.tr('Tunjuk had laju', 'Show speed limit')),
            value: s.showSpeedLimit,
            onChanged: (v) => s.showSpeedLimit = v,
          ),
          ListTile(
            title: Text(context.tr('Amaran laju melebihi had', 'Speeding warning above limit')),
            trailing: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('+0')),
                ButtonSegment(value: 5, label: Text('+5')),
                ButtonSegment(value: 10, label: Text('+10')),
              ],
              selected: {s.speedingMargin},
              onSelectionChanged: (v) => s.speedingMargin = v.first,
            ),
          ),
          header(context.tr('Data & privasi', 'Data & privacy')),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: Text(context.tr('Arah tidak menjejak anda', 'Arah does not track you')),
            subtitle: Text(
              context.tr(
                'Tiada sejarah perjalanan disimpan. Carian dan laluan dihantar ke pelayan di bawah tanpa akaun. Tiada perkhidmatan Google digunakan.',
                'No trip history is kept. Searches and routes go to the servers below with no account. No Google services are used.',
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: Text(context.tr('Padam carian terkini', 'Clear recent searches')),
            onTap: () {
              s.clearRecents();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Dipadam', 'Cleared'))));
            },
          ),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: Text(context.tr('Pelayan', 'Servers')),
            subtitle: Text(
              '${context.tr('Laluan', 'Routing')}: ${ArahConfig.valhallaUrl}\n'
              '${context.tr('Carian', 'Search')}: ${ArahConfig.photonUrl}\n'
              '${context.tr('Peta', 'Map')}: OpenFreeMap / Protomaps\n'
              '${context.tr('Laporan', 'Reports')}: ${app.reports.shared ? 'Supabase' : context.tr('pada telefon ini sahaja', 'this phone only')}',
            ),
            isThreeLine: true,
          ),
          header(context.tr('Tentang', 'About')),
          ListTile(
            title: Text('Arah ${ArahConfig.appVersion}'),
            subtitle: const Text(
              'Map data © OpenStreetMap contributors (ODbL). Tiles: OpenFreeMap © OpenMapTiles, Protomaps. '
              'Traffic © TomTom. Satellite imagery © Esri, Maxar, Earthstar Geographics. '
              'Elevation: Mapzen, AWS Terrain Tiles. '
              'Routing: Valhalla (FOSSGIS). Search: Photon (Komoot). Map engine: MapLibre.',
            ),
            onTap: () =>
                showLicensePage(context: context, applicationName: 'Arah', applicationVersion: ArahConfig.appVersion),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
