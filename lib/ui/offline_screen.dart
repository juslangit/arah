// Offline maps manager (app study §S8, after Magic Earth): downloaded packs
// with size and data date, available packs, progress with pause/resume.
import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../offline/packs.dart';

String _mb(int bytes) => '${(bytes / 1e6).round()} MB';

class OfflineScreen extends StatelessWidget {
  const OfflineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final packs = app.packs;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Peta luar talian', 'Offline maps'))),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            context.tr(
              'Setiap pek ada peta, carian dan rangkaian jalan — navigasi berfungsi walaupun tiada isyarat.',
              'Each pack has the map, search and road network — navigation works with no signal.',
            ),
          ),
        ),
        SwitchListTile(
          title: Text(context.tr('Muat turun melalui Wi-Fi sahaja', 'Download on Wi-Fi only')),
          value: app.settings.wifiOnlyDownloads,
          onChanged: (v) => app.settings.wifiOnlyDownloads = v,
        ),
        const Divider(),
        for (final p in packs.catalog) _PackTile(pack: p),
        if (packs.catalog.every((p) => p.files.isEmpty))
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(context.tr(
              'Senarai pek belum dapat dimuat. Sambung ke internet dan buka semula skrin ini.',
              'The pack list has not loaded yet. Connect to the internet and reopen this screen.',
            )),
          ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Data © OpenStreetMap contributors (ODbL) · Map tiles: Protomaps', style: TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }
}

class _PackTile extends StatelessWidget {
  final PackInfo pack;
  const _PackTile({required this.pack});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final packs = app.packs;
    final installed = packs.installed[pack.id];
    final prog = packs.progress[pack.id];
    final running = prog?.state == DownloadState.running;
    final name = app.tr(pack.nameMs, pack.nameEn);

    String subtitle;
    if (running) {
      subtitle = '${_mb(prog!.done)} / ${_mb(prog.total)}';
    } else if (prog?.state == DownloadState.failed) {
      subtitle = app.tr('Gagal — cuba lagi', 'Failed — try again');
    } else if (prog?.state == DownloadState.paused) {
      subtitle = '${app.tr('Dijeda', 'Paused')} · ${_mb(prog!.done)} / ${_mb(prog.total)}';
    } else if (installed != null) {
      subtitle = '${_mb(packs.diskBytes(pack.id))} · ${app.tr('Data', 'Data')}: ${installed.dataDate}'
          '${packs.hasUpdate(pack.id) ? ' · ${app.tr('Kemas kini ada', 'Update available')}' : ''}';
    } else {
      subtitle = pack.bytes > 0 ? _mb(pack.bytes) : '';
    }

    Future<void> start() async {
      if (app.settings.wifiOnlyDownloads && !app.onWifi) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(app.tr('Sambung ke Wi-Fi, atau matikan "Wi-Fi sahaja"', 'Connect to Wi-Fi, or turn off "Wi-Fi only"')),
        ));
        return;
      }
      await packs.download(pack);
    }

    return Column(children: [
      ListTile(
        leading: Icon(installed != null ? Icons.offline_pin : Icons.map_outlined,
            color: installed != null ? Theme.of(context).colorScheme.primary : null, size: 32),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: running
            ? IconButton(tooltip: app.tr('Jeda', 'Pause'), icon: const Icon(Icons.pause), onPressed: () => packs.pause(pack.id))
            : installed != null && !packs.hasUpdate(pack.id)
                ? IconButton(
                    tooltip: app.tr('Padam', 'Delete'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(app.tr('Padam $name?', 'Delete $name?')),
                          content: Text(app.tr('Hanya data luar talian dipadam.', 'Only the offline data is removed.')),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(app.tr('Batal', 'Cancel'))),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(app.tr('Padam', 'Delete'))),
                          ],
                        ),
                      );
                      if (ok == true) await packs.delete(pack.id);
                    },
                  )
                : FilledButton.tonal(
                    onPressed: pack.files.isEmpty ? null : start,
                    child: Text(installed != null
                        ? app.tr('Kemas kini', 'Update')
                        : prog?.state == DownloadState.paused || prog?.state == DownloadState.failed
                            ? app.tr('Sambung', 'Resume')
                            : app.tr('Muat turun', 'Download')),
                  ),
      ),
      if (running) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: LinearProgressIndicator(value: prog!.fraction)),
    ]);
  }
}
