import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairo/data/mock_data.dart';
import 'package:kairo/data/models.dart';
import 'package:kairo/data/providers.dart';
import 'package:kairo/main.dart';

Widget _app() => const ProviderScope(child: KairoApp(useGoogleFonts: false));

void main() {
  testWidgets('shows the five tabs and switches between them', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Continue watching'), findsOneWidget);
    for (final tab in ['Home', 'Discover', 'My Anime', 'Library', 'Profile']) {
      expect(find.widgetWithText(NavigationDestination, tab), findsOneWidget);
    }

    await tester.tap(find.widgetWithText(NavigationDestination, 'Library'));
    await tester.pumpAndSettle();
    expect(find.text('Needs matching · 1'), findsOneWidget);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Guest'), findsOneWidget);
  });

  testWidgets('Discover filters by genre and search text', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, 'Discover'));
    await tester.pumpAndSettle();

    expect(find.text('${mockCatalogue.length} titles'), findsOneWidget);
    await tester.tap(find.text('Sports'));
    await tester.pumpAndSettle();
    expect(find.text('2 titles'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.enterText(find.byType(TextField), 'frieren');
    await tester.pumpAndSettle();
    expect(find.text('1 titles'), findsOneWidget);
  });

  testWidgets('opening a title shows its details and resume button', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Resume Ep 4'), findsOneWidget);
    expect(find.text('4 of 28 episodes are in your library'), findsOneWidget);
  });

  test('marking the last episode completes the title', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(watchlistProvider.notifier);
    final solo = animeById(151807);

    notifier.markNextWatched(solo);
    notifier.markNextWatched(solo);

    final entry = container.read(watchlistProvider)[solo.id]!;
    expect(entry.watched, 12);
    expect(entry.status, ListStatus.completed);
  });

  test('confirming a suggested match moves the file into its anime', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(libraryProvider.notifier).confirmSuggestedMatch('f6');

    final file = container.read(libraryProvider).firstWhere((f) => f.id == 'f6');
    expect(file.state, FileState.matched);
    expect(file.animeId, 171018);
    expect(file.episode, 8);
  });
}
