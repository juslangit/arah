// First run (app study §S0): language, location permission, offline map offer.
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../nav/phrases.dart';
import 'offline_screen.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;

  Future<void> _askLocation() async {
    await context.appRead.location.ensurePermission();
    // Android 13+: the navigation notification needs this.
    await Permission.notification.request();
    setState(() => _step = 2);
  }

  void _finish() {
    context.appRead.settings.onboarded = true;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final body = switch (_step) {
      0 => _Page(
          icon: Icons.translate,
          title: 'Pilih bahasa · Choose language',
          text: 'Untuk skrin dan arahan suara.\nFor the screens and the voice.',
          actions: [
            FilledButton(
              onPressed: () async {
                await app.setLang(Lang.ms);
                setState(() => _step = 1);
              },
              child: const Text('Bahasa Malaysia'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                await app.setLang(Lang.en);
                setState(() => _step = 1);
              },
              child: const Text('English'),
            ),
          ],
        ),
      1 => _Page(
          icon: Icons.my_location,
          title: context.tr('Lokasi anda', 'Your location'),
          text: context.tr(
            'Arah guna GPS telefon untuk menunjukkan kedudukan anda dan memandu anda. Lokasi tidak disimpan atau dihantar ke mana-mana.',
            'Arah uses your phone\'s GPS to show where you are and guide you. Your location is not stored or sent anywhere.',
          ),
          actions: [
            FilledButton(onPressed: _askLocation, child: Text(context.tr('Benarkan lokasi', 'Allow location'))),
            const SizedBox(height: 12),
            TextButton(onPressed: () => setState(() => _step = 2), child: Text(context.tr('Nanti', 'Later'))),
          ],
        ),
      _ => _Page(
          icon: Icons.download_for_offline,
          title: context.tr('Peta luar talian', 'Offline map'),
          text: context.tr(
            'Muat turun Semenanjung atau Sabah & Sarawak supaya peta, carian dan navigasi berfungsi tanpa internet — di lebuh raya, di kampung, di pedalaman.',
            'Download Peninsular Malaysia or Sabah & Sarawak so the map, search and navigation work without internet — on highways, in kampungs, in the interior.',
          ),
          actions: [
            FilledButton(
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const OfflineScreen()));
                _finish();
              },
              child: Text(context.tr('Pilih kawasan', 'Choose a region')),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: _finish, child: Text(context.tr('Nanti', 'Later'))),
          ],
        ),
    };
    return Scaffold(body: SafeArea(child: body));
  }
}

class _Page extends StatelessWidget {
  final IconData icon;
  final String title, text;
  final List<Widget> actions;
  const _Page({required this.icon, required this.title, required this.text, required this.actions});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 48, 28, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Arah', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: ArahColors.brand, letterSpacing: -1)),
          const Spacer(),
          Icon(icon, size: 72, color: ArahColors.brand),
          const SizedBox(height: 24),
          Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text(text, style: Theme.of(context).textTheme.bodyLarge),
          const Spacer(flex: 2),
          ...actions,
        ]),
      );
}
