// Arah — Google-free navigation for Malaysia.
import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app_state.dart';
import 'app/theme.dart';
import 'ui/home_screen.dart';
import 'ui/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.create();
  runApp(AppScope(state: state, child: const ArahApp()));
}

class ArahApp extends StatefulWidget {
  const ArahApp({super.key});
  @override
  State<ArahApp> createState() => _ArahAppState();
}

class _ArahAppState extends State<ArahApp> {
  // Auto theme turns dark at 7 pm and light at 7 am: look again every minute.
  late final Timer _clock = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    _clock;
    return MaterialApp(
      title: 'Arah',
      debugShowCheckedModeBanner: false,
      theme: arahTheme(Brightness.light),
      darkTheme: arahTheme(Brightness.dark),
      // The buttons follow Arah's own theme (same rule as the map), not the phone's dark mode.
      themeMode: app.settings.darkNow ? ThemeMode.dark : ThemeMode.light,
      home: app.settings.onboarded ? const HomeScreen() : OnboardingScreen(onDone: () => setState(() {})),
    );
  }
}
