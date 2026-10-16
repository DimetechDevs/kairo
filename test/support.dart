import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kairo/data/anilist.dart';
import 'package:kairo/data/local_store.dart';
import 'package:kairo/data/providers.dart';
import 'package:kairo/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An AniList `Media` object. No artwork URLs, so tests never touch the network.
Map<String, dynamic> media(int id, String title, {int? episodes = 12, List<String> genres = const ['Action'], int? next}) => {
      'id': id,
      'title': {'english': title, 'romaji': '$title (romaji)', 'native': null},
      'coverImage': {'extraLarge': null, 'color': '#e4a128'},
      'bannerImage': null,
      'format': 'TV',
      'status': next == null ? 'FINISHED' : 'RELEASING',
      'episodes': episodes,
      'duration': 24,
      'season': 'FALL',
      'seasonYear': 2026,
      'averageScore': 85,
      'popularity': 1000,
      'genres': genres,
      'nextAiringEpisode': next == null ? null : {'episode': next, 'airingAt': 1893456000},
    };

final frieren = media(1, 'Frieren', episodes: 28, genres: ['Adventure', 'Fantasy']);
final dandadan = media(2, 'Dandadan', episodes: null, next: 4);
final solo = media(3, 'Solo Leveling');

/// Answers like AniList, and records the variables of each request.
class FakeAniList {
  FakeAniList({List<Map<String, dynamic>>? catalogue}) : catalogue = catalogue ?? [frieren, dandadan, solo];

  final List<Map<String, dynamic>> catalogue;
  final requests = <Map<String, dynamic>>[];
  bool offline = false;

  late final client = MockClient((req) async {
    if (offline) throw http.ClientException('offline');
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    final query = body['query'] as String;
    final vars = body['variables'] as Map<String, dynamic>;
    requests.add(vars);

    Map<String, dynamic> data;
    if (query.contains('trending: Page')) {
      final page = {'media': catalogue};
      data = {'trending': page, 'season': page, 'popular': page, 'topRated': page};
    } else if (query.contains('Media(id')) {
      final m = catalogue.firstWhere((m) => m['id'] == vars['id']);
      data = {
        'Media': {
          ...m,
          'description': 'A <i>long</i> story.<br>Second line &amp; more.',
          'startDate': {'year': 2026},
          'studios': {
            'nodes': [{'name': 'Madhouse'}],
          },
          'externalLinks': [
            {'site': 'Crunchyroll', 'url': 'https://www.crunchyroll.com/series/x', 'type': 'STREAMING', 'color': '#F88C24'},
            {'site': 'Official Site', 'url': 'https://example.jp', 'type': 'INFO'},
          ],
          'streamingEpisodes': [
            {'title': 'Episode 1 - The Journey Ends', 'url': 'https://www.crunchyroll.com/watch/1', 'site': 'Crunchyroll'},
          ],
          'recommendations': {
            'nodes': [{'mediaRecommendation': solo}],
          },
        },
      };
    } else {
      final search = (vars['search'] as String?)?.toLowerCase();
      final all = catalogue;
      final hits = search == null ? all : all.where((m) => (m['title'] as Map)['english'].toLowerCase().contains(search)).toList();
      data = {
        'Page': {'pageInfo': {'hasNextPage': false}, 'media': hits},
      };
    }
    return http.Response(jsonEncode({'data': data}), 200, headers: {'content-type': 'application/json'});
  });
}

Future<(ProviderContainer, FakeAniList)> pumpApp(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  List<Map<String, dynamic>>? catalogue,
  LocalStore? store,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final fake = FakeAniList(catalogue: catalogue);
  final container = ProviderContainer(overrides: [
    prefsProvider.overrideWithValue(sp),
    aniListProvider.overrideWithValue(AniListClient(httpClient: fake.client, prefs: sp)),
    localStoreProvider.overrideWithValue(store ?? MemoryStore()),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const KairoApp()));
  await tester.pumpAndSettle();
  return (container, fake);
}

/// Unmounts the app so its timers (carousel auto-advance) are cancelled before the test ends.
Future<void> unmount(WidgetTester tester) => tester.pumpWidget(const SizedBox());

