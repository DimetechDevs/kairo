import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/router.dart';
import 'core/theme.dart';
import 'data/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: const KairoApp(),
  ));
}

class KairoApp extends StatefulWidget {
  const KairoApp({super.key});

  @override
  State<KairoApp> createState() => _KairoAppState();
}

class _KairoAppState extends State<KairoApp> {
  final GoRouter _router = createRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Kairo',
      debugShowCheckedModeBanner: false,
      theme: KairoTheme.dark(),
      routerConfig: _router,
    );
  }
}
