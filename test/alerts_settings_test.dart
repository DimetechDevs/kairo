import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairo/data/airing_alerts.dart';
import 'package:kairo/data/anilist.dart';
import 'package:kairo/data/models.dart';
import 'package:kairo/data/providers.dart';
import 'package:kairo/data/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

Future<(ProviderContainer, NoopScheduler)> _container({Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final scheduler = NoopScheduler();
  final container = ProviderContainer(overrides: [
    prefsProvider.overrideWithValue(sp),
    aniListProvider.overrideWithValue(AniListClient(httpClient: FakeAniList().client, prefs: sp)),
    alertSchedulerProvider.overrideWithValue(scheduler),
  ]);
  addTearDown(container.dispose);
  return (container, scheduler);
}

void main() {
  test('settings are saved and read back', () async {
    final (c, _) = await _container();
    c.read(settingsProvider.notifier).update((s) => s.copyWith(speed: 1.5, autoNext: false, subtitleLanguage: 'off'));

    final saved = c.read(prefsProvider).getString('settings.v1')!;
    final (again, _) = await _container(prefs: {'settings.v1': saved});
    final s = again.read(settingsProvider);
    expect(s.speed, 1.5);
    expect(s.autoNext, isFalse);
    expect(s.subtitleLanguage, 'off');
    expect(s.skipSeconds, 85, reason: 'untouched settings keep their defaults');
  });

  test('a corrupt or unknown save falls back to defaults', () async {
    final (c, _) = await _container(prefs: {'settings.v1': '{"speed": "fast", "subtitleLanguage": "klingon"'});
    expect(c.read(settingsProvider).speed, 1.0);
  });

  test('alerts are scheduled for airing shows on the list, and cleared when turned off', () async {
    final (c, scheduler) = await _container();
    final alerts = c.read(airingAlertsProvider);

    c.read(watchlistProvider.notifier).setStatus(Anime.fromAniList(dandadan), ListStatus.watching);
    c.read(watchlistProvider.notifier).setStatus(Anime.fromAniList(frieren), ListStatus.watching); // Finished: no alerts.
    await alerts.sync();
    expect(scheduler.scheduled.map((a) => (a.animeId, a.episode, a.title)), [(2, 4, 'Dandadan')]);
    expect(scheduler.scheduled.single.route, '/anime/2');

    c.read(settingsProvider.notifier).update((s) => s.copyWith(airingAlerts: false));
    await alerts.sync();
    expect(scheduler.scheduled, isEmpty);
  });

  test('dropped and completed shows get no alerts', () async {
    final (c, scheduler) = await _container();
    c.read(watchlistProvider.notifier).setStatus(Anime.fromAniList(dandadan), ListStatus.dropped);
    await c.read(airingAlertsProvider).sync();
    expect(scheduler.scheduled, isEmpty);
  });
}
