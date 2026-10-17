import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/router.dart';
import 'core/theme.dart';
import 'data/airing_alerts.dart';
import 'data/anilist_sync.dart';
import 'data/local_store.dart';
import 'data/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final router = createRouter();
  final (prefs, store, (scheduler, launchRoute)) = await (
    SharedPreferences.getInstance(),
    SqliteStore.open(),
    LocalNotificationsScheduler.init(router.push),
  ).wait;
  final container = ProviderContainer(overrides: [
    prefsProvider.overrideWithValue(prefs),
    localStoreProvider.overrideWithValue(store),
    alertSchedulerProvider.overrideWithValue(scheduler),
  ]);

  // Notice files that were moved or deleted while the app was closed, and refresh episode alerts.
  container.read(libraryProvider.notifier).checkMissing().ignore();
  container.read(airingAlertsProvider).sync().ignore();
  container.read(aniListSyncProvider.notifier).syncNow().ignore(); // No-op unless signed in.

  runApp(UncontrolledProviderScope(container: container, child: KairoApp(router: router)));
  if (launchRoute != null) WidgetsBinding.instance.addPostFrameCallback((_) => router.push(launchRoute));
}

class KairoApp extends StatefulWidget {
  const KairoApp({super.key, this.router});

  /// Created here when not given (tests).
  final GoRouter? router;

  @override
  State<KairoApp> createState() => _KairoAppState();
}

class _KairoAppState extends State<KairoApp> {
  late final GoRouter _router = widget.router ?? createRouter();

  @override
  void dispose() {
    if (widget.router == null) _router.dispose();
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
