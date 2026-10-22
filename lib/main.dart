// Arah — Google-free navigation for Malaysia.
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
  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return MaterialApp(
      title: 'Arah',
      debugShowCheckedModeBanner: false,
      theme: arahTheme(Brightness.light),
      darkTheme: arahTheme(Brightness.dark),
      home: app.settings.onboarded ? const HomeScreen() : OnboardingScreen(onDone: () => setState(() {})),
    );
  }
}
