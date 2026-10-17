import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';
import 'providers.dart';
import 'settings.dart';

/// One notification to show when an episode airs.
class AiringAlert {
  const AiringAlert({required this.animeId, required this.episode, required this.at, required this.title});

  final int animeId;
  final int episode;
  final DateTime at;
  final String title;

  /// Stable per episode, so re-scheduling replaces rather than duplicates.
  int get id => animeId * 1000 + episode % 1000;
  String get route => '/anime/$animeId';
}

/// Shows scheduled notifications. Replaced by a fake in tests.
abstract class AlertScheduler {
  Future<bool> requestPermission();
  Future<void> replaceAll(List<AiringAlert> alerts);
}

class NoopScheduler implements AlertScheduler {
  final scheduled = <AiringAlert>[];

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> replaceAll(List<AiringAlert> alerts) async => scheduled
    ..clear()
    ..addAll(alerts);
}

class LocalNotificationsScheduler implements AlertScheduler {
  LocalNotificationsScheduler._(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const _channel = AndroidNotificationDetails(
    'new_episodes',
    'New episodes',
    channelDescription: 'When a new episode of a show on your list airs',
    importance: Importance.defaultImportance,
  );

  /// [onOpen] gets the route to open when a notification is tapped. Returns the scheduler and,
  /// if the app was launched by tapping a notification, that route.
  static Future<(LocalNotificationsScheduler, String?)> init(void Function(String route) onOpen) async {
    tz_data.initializeTimeZones();
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload case final route?) onOpen(route);
      },
    );
    final launch = await plugin.getNotificationAppLaunchDetails();
    final route = launch?.didNotificationLaunchApp == true ? launch?.notificationResponse?.payload : null;
    return (LocalNotificationsScheduler._(plugin), route);
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> requestPermission() async => await _android?.requestNotificationsPermission() ?? true;

  @override
  Future<void> replaceAll(List<AiringAlert> alerts) async {
    await _plugin.cancelAllPendingNotifications();
    for (final a in alerts) {
      await _plugin.zonedSchedule(
        id: a.id,
        scheduledDate: tz.TZDateTime.from(a.at, tz.UTC),
        notificationDetails: const NotificationDetails(android: _channel),
        // Inexact is fine for "it's out" and needs no exact-alarm permission.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: a.title,
        body: 'Episode ${a.episode} just aired. Tap to see where to watch it.',
        payload: a.route,
      );
    }
  }
}

final alertSchedulerProvider = Provider<AlertScheduler>((ref) => NoopScheduler()); // Real one set in main().

/// Keeps scheduled notifications in step with the list and the settings.
class AiringAlerts {
  AiringAlerts(this._ref);

  final Ref _ref;
  Timer? _debounce;
  static const _askedKey = 'alerts.permissionAsked';

  /// Re-syncs shortly after the list changes (several quick edits make one request).
  void scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () => sync().ignore());
  }

  Future<void> sync() async {
    final scheduler = _ref.read(alertSchedulerProvider);
    final entries = _ref
        .read(watchlistProvider)
        .values
        .where((e) => e.status == ListStatus.watching || e.status == ListStatus.planned)
        .toList();
    if (!_ref.read(settingsProvider).airingAlerts || entries.isEmpty) {
      await scheduler.replaceAll(const []);
      return;
    }

    // Ask for notification permission once, the first time there's something to notify about.
    final prefs = _ref.read(prefsProvider);
    if (!(prefs.getBool(_askedKey) ?? false)) {
      await prefs.setBool(_askedKey, true);
      scheduler.requestPermission().ignore(); // Don't wait: alerts are scheduled either way.
    }

    try {
      final titles = {for (final e in entries) e.animeId: e.anime.title};
      final upcoming = await _ref.read(aniListProvider).upcomingEpisodes(titles.keys.toList());
      await scheduler.replaceAll([
        for (final u in upcoming)
          if (u.at.isAfter(DateTime.now()))
            AiringAlert(animeId: u.animeId, episode: u.episode, at: u.at, title: titles[u.animeId] ?? 'New episode'),
      ]);
    } catch (e) {
      // Offline: keep whatever was scheduled last time.
      debugPrint('Airing alerts not refreshed: $e');
    }
  }
}

final airingAlertsProvider = Provider<AiringAlerts>((ref) {
  final alerts = AiringAlerts(ref);
  ref.listen(watchlistProvider, (_, _) => alerts.scheduleSync());
  ref.listen(settingsProvider.select((s) => s.airingAlerts), (_, _) => alerts.scheduleSync());
  ref.onDispose(() => alerts._debounce?.cancel());
  return alerts;
});
