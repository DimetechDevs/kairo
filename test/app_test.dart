import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairo/data/anilist.dart';
import 'package:kairo/data/models.dart';
import 'package:kairo/data/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

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
    final entry = WatchEntry(anime: Anime.fromAniList(frieren), status: ListStatus.watching, watched: 5, updatedAt: DateTime(2026));
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
      final soloAnime = Anime.fromAniList(solo);
      notifier.setWatched(soloAnime, 11);
      notifier.markNextWatched(soloAnime);
      notifier.markNextWatched(soloAnime);

      final entry = container.read(watchlistProvider)[soloAnime.id]!;
      expect(entry.watched, 12);
      expect(entry.status, ListStatus.completed);
    });

    test('airing shows without an episode total can keep counting', () {
      final notifier = container.read(watchlistProvider.notifier);
      final dandadanAnime = Anime.fromAniList(dandadan);
      notifier.setStatus(dandadanAnime, ListStatus.watching);
      for (var i = 0; i < 3; i++) {
        notifier.markNextWatched(dandadanAnime);
      }
      expect(container.read(watchlistProvider)[2]!.watched, 3);
      expect(container.read(watchlistProvider)[2]!.status, ListStatus.watching);
    });
  });

  test('a saved anime reads back the same', () {
    final a = Anime.fromAniList(dandadan);
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
