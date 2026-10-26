import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kairo/data/local_store.dart';
import 'package:kairo/data/models.dart';
import 'package:kairo/data/providers.dart';
import 'package:kairo/data/stream_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

/// Answers like the Kairo API for Frieren (AniList 1) episodes 1–3, and records each request.
class FakeStreamApi {
  final requests = <http.Request>[];
  int status = 200;

  late final client = MockClient((req) async {
    requests.add(req);
    if (status != 200) return http.Response('', status);
    final m = RegExp(r'/anime/(\d+)/episodes/(\d+)$').firstMatch(req.url.path);
    if (m == null || m.group(1) != '1' || int.parse(m.group(2)!) > 3) return http.Response('', 404);
    return http.Response(
      jsonEncode({
        'sources': [
          {'url': 'https://cdn.example/ep${m.group(2)}/720.m3u8', 'quality': '720p'},
          {'url': 'https://cdn.example/ep${m.group(2)}/1080.m3u8', 'quality': '1080p', 'headers': {'Referer': 'https://example'}},
        ],
        'subtitles': [
          {'url': 'https://cdn.example/en.vtt', 'language': 'en', 'label': 'English'},
        ],
      }),
      200,
    );
  });
}

void main() {
  group('stream API', () {
    test('asks for an episode by AniList ID with the key, and reads sources and subtitles', () async {
      final fake = FakeStreamApi();
      final api = StreamApiClient(baseUrl: 'https://api.example/v1/', apiKey: 'secret', httpClient: fake.client);

      final streams = await api.episode(1, 2);
      expect(fake.requests.single.url.toString(), 'https://api.example/v1/anime/1/episodes/2');
      expect(fake.requests.single.headers['Authorization'], 'Bearer secret');
      expect(streams!.best.url, 'https://cdn.example/ep2/1080.m3u8', reason: 'highest quality first');
      expect(streams.best.headers, {'Referer': 'https://example'});
      expect(streams.subtitles.single.language, 'en');
    });

    test('a missing episode is null, and errors say what went wrong', () async {
      final fake = FakeStreamApi();
      final api = StreamApiClient(baseUrl: 'https://api.example', httpClient: fake.client);
      expect(await api.episode(1, 9), isNull);
      expect(fake.requests.single.headers.containsKey('Authorization'), isFalse, reason: 'no key, no header');

      fake.status = 401;
      await expectLater(
        api.episode(1, 1),
        throwsA(isA<StreamApiException>().having((e) => e.message, 'message', contains('key'))),
      );
    });

    test('adaptive streams rank above fixed qualities', () {
      final streams = EpisodeStreams.fromJson({
        'sources': [
          {'url': 'a', 'quality': '1080p'},
          {'url': 'b', 'quality': 'auto'},
        ],
      });
      expect(streams.best.url, 'b');
    });

    test('the address is saved in preferences and the key in secure storage', () async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final secrets = MemorySecretStore();
      final c = ProviderContainer(overrides: [
        prefsProvider.overrideWithValue(sp),
        secretStoreProvider.overrideWithValue(secrets),
      ]);
      addTearDown(c.dispose);

      expect(await c.read(streamApiProvider.future), isNull, reason: 'nothing set up yet');
      await c.read(streamApiConfigProvider.notifier).save(baseUrl: ' https://api.example ', apiKey: 'secret');
      expect(sp.getString('streamApi.url'), 'https://api.example');
      expect(sp.getKeys().any((k) => sp.get(k) == 'secret'), isFalse, reason: 'the key never goes in preferences');
      expect(secrets.values.values, ['secret']);
      expect((await c.read(streamApiProvider.future))!.baseUrl, 'https://api.example');
    });
  });

  test('progress is kept per episode and the resume list shows the latest unfinished one per show', () async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [
      prefsProvider.overrideWithValue(sp),
      localStoreProvider.overrideWithValue(MemoryStore()),
    ]);
    addTearDown(c.dispose);

    final progress = c.read(progressProvider.notifier);
    progress.save(1, 1, const Duration(minutes: 23), const Duration(minutes: 24)); // Finished.
    progress.save(1, 2, const Duration(minutes: 5), const Duration(minutes: 24));
    expect([for (final p in c.read(resumeListProvider)) (p.animeId, p.episode)], [(1, 2)]);
  });

  testWidgets('details offers to resume and plays episodes from the API, not from imports', (tester) async {
    final store = MemoryStore(progress: [
      PlaybackProgress(
        animeId: 1,
        episode: 2,
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 24),
        updatedAt: DateTime(2026),
      ),
    ]);
    final (c, _) = await pumpApp(tester, store: store);
    c.read(watchlistProvider.notifier).setStatus(Anime.fromAniList(frieren), ListStatus.watching);
    await tester.pumpAndSettle();

    expect(find.text('Ep 2 · 19 min left'), findsOneWidget, reason: 'Continue watching shows the resume point');
    await tester.tap(find.text('Details').first);
    await tester.pumpAndSettle();
    expect(find.text('Resume Ep 2'), findsOneWidget);
    expect(find.text('Where to watch'), findsNothing);
    await tester.scrollUntilVisible(find.text('19 min left'), 300, scrollable: find.byType(Scrollable).first);
    await tester.scrollUntilVisible(find.text('Resume Ep 2'), -300, scrollable: find.byType(Scrollable).first);

    // No API set up yet: tapping play says where to set it up.
    await tester.tap(find.text('Resume Ep 2'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Set up your Kairo API in Profile'), findsOneWidget);
    await unmount(tester);
  });
}
