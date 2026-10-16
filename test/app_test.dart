import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kairo/data/anilist.dart';
import 'package:kairo/data/models.dart';
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

final _frieren = media(1, 'Frieren', episodes: 28, genres: ['Adventure', 'Fantasy']);
final _dandadan = media(2, 'Dandadan', episodes: null, next: 4);
final _solo = media(3, 'Solo Leveling');

/// Answers like AniList, and records the variables of each request.
class FakeAniList {
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
      final page = {'media': [_frieren, _dandadan, _solo]};
      data = {'trending': page, 'season': page, 'popular': page, 'topRated': page};
    } else if (query.contains('Media(id')) {
      final m = [_frieren, _dandadan, _solo].firstWhere((m) => m['id'] == vars['id']);
      data = {
        'Media': {
          ...m,
          'description': 'A <i>long</i> story.<br>Second line &amp; more.',
          'startDate': {'year': 2026},
          'studios': {
            'nodes': [{'name': 'Madhouse'}],
          },
          'recommendations': {
            'nodes': [{'mediaRecommendation': _solo}],
          },
        },
      };
    } else {
      final search = (vars['search'] as String?)?.toLowerCase();
      final all = [_frieren, _dandadan, _solo];
      final hits = search == null ? all : all.where((m) => (m['title'] as Map)['english'].toLowerCase().contains(search)).toList();
      data = {
        'Page': {'pageInfo': {'hasNextPage': false}, 'media': hits},
      };
    }
    return http.Response(jsonEncode({'data': data}), 200, headers: {'content-type': 'application/json'});
  });
}

Future<(ProviderContainer, FakeAniList)> pumpApp(WidgetTester tester, {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final fake = FakeAniList();
  final container = ProviderContainer(overrides: [
    prefsProvider.overrideWithValue(sp),
    aniListProvider.overrideWithValue(AniListClient(httpClient: fake.client, prefs: sp)),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const KairoApp()));
  await tester.pumpAndSettle();
  return (container, fake);
}

/// Unmounts the app so its timers (carousel auto-advance) are cancelled before the test ends.
Future<void> unmount(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  testWidgets('Home shows AniList titles and the five tabs', (tester) async {
    await pumpApp(tester);

    expect(find.text('Frieren'), findsWidgets);
    expect(find.text('Popular this season'), findsOneWidget);
    for (final tab in ['Home', 'Discover', 'My Anime', 'Library', 'Profile']) {
      expect(find.widgetWithText(NavigationDestination, tab), findsOneWidget);
    }

    await tester.tap(find.widgetWithText(NavigationDestination, 'Library'));
    await tester.pumpAndSettle();
    expect(find.text('No videos yet'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Discover searches AniList and filters by genre', (tester) async {
    final (_, fake) = await pumpApp(tester);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Discover'));
    await tester.pumpAndSettle();
    expect(find.text('Solo Leveling'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'frier');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(fake.requests.last['search'], 'frier');
    expect(find.text('Solo Leveling'), findsNothing);
    expect(find.text('Frieren'), findsOneWidget);

    await tester.tap(find.text('Fantasy'));
    await tester.pumpAndSettle();
    expect(fake.requests.last['genre'], 'Fantasy');
    await unmount(tester);
  });

  testWidgets('adding from the details page saves the title to My Anime', (tester) async {
    final (container, _) = await pumpApp(tester);

    await tester.tap(find.text('Details').first);
    await tester.pumpAndSettle();
    expect(find.text('Madhouse'), findsOneWidget);
    expect(find.text('A long story.\nSecond line & more.'), findsOneWidget);

    await tester.tap(find.text('Add to list'));
    await tester.pumpAndSettle();
    expect(container.read(watchlistProvider)[1]?.status, ListStatus.planned);

    final saved = container.read(prefsProvider).getString('watchlist.v1')!;
    expect(saved, contains('Frieren'));
    await unmount(tester);
  });

  testWidgets('the watchlist is read back from the phone on start', (tester) async {
    final entry = WatchEntry(anime: Anime.fromAniList(_frieren), status: ListStatus.watching, watched: 5, updatedAt: DateTime(2026));
    await pumpApp(tester, prefs: {'watchlist.v1': jsonEncode([entry.toJson()])});

    expect(find.text('Continue watching'), findsOneWidget);
    expect(find.text('Ep 5 / 28'), findsOneWidget);
    await unmount(tester);
  });

  group('WatchlistNotifier', () {
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      container = ProviderContainer(overrides: [prefsProvider.overrideWithValue(sp)]);
    });
    tearDown(() => container.dispose());

    test('marking the last episode completes the title', () {
      final notifier = container.read(watchlistProvider.notifier);
      final solo = Anime.fromAniList(_solo);
      notifier.setWatched(solo, 11);
      notifier.markNextWatched(solo);
      notifier.markNextWatched(solo);

      final entry = container.read(watchlistProvider)[solo.id]!;
      expect(entry.watched, 12);
      expect(entry.status, ListStatus.completed);
    });

    test('airing shows without an episode total can keep counting', () {
      final notifier = container.read(watchlistProvider.notifier);
      final dandadan = Anime.fromAniList(_dandadan);
      notifier.setStatus(dandadan, ListStatus.watching);
      for (var i = 0; i < 3; i++) {
        notifier.markNextWatched(dandadan);
      }
      expect(container.read(watchlistProvider)[2]!.watched, 3);
      expect(container.read(watchlistProvider)[2]!.status, ListStatus.watching);
    });
  });

  test('a saved anime reads back the same', () {
    final a = Anime.fromAniList(_dandadan);
    final b = Anime.fromAniList(a.toJson());
    expect(b.title, 'Dandadan');
    expect(b.color, a.color);
    expect(b.nextAiring!.episode, 4);
    expect(b.airedEpisodes, 3);
    expect(b.episodesLabel, '3 eps so far');
  });

  test('home falls back to the last saved response when offline', () async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final fake = FakeAniList();
    final client = AniListClient(httpClient: fake.client, prefs: sp);

    await client.home();
    fake.offline = true;
    final feed = await client.home();
    expect(feed.trending.map((a) => a.title), contains('Frieren'));

    await expectLater(client.browse(search: 'x'), throwsA(isA<AniListException>()));
  });

  test('seasons roll over in December', () {
    expect(seasonOf(DateTime(2026, 12, 5)), (season: 'WINTER', year: 2027));
    expect(seasonOf(DateTime(2026, 10, 16)), (season: 'FALL', year: 2026));
  });
}
