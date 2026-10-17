import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairo/data/models.dart';

import 'support.dart';

/// Long titles, many genres and every list status, to stress the layouts.
final _long = [
  {
    ...media(10, 'The Apothecary Diaries Season 3: The Pharmacist of the Rear Palace', episodes: 24, next: 5,
        genres: ['Drama', 'Mystery', 'Romance', 'Slice of Life', 'Psychological']),
    'title': {
      'english': 'The Apothecary Diaries Season 3: The Pharmacist of the Rear Palace',
      'romaji': 'Kusuriya no Hitorigoto 3rd Season',
      'native': '薬屋のひとりごと 第3期 後宮の薬師と長い長い副題',
    },
  },
  media(11, 'JoJo no Kimyou na Bouken: Steel Ball Run - 2nd & 3rd STAGE', episodes: null, next: 120),
  media(12, 'Frieren', episodes: 1000),
  media(13, 'Movie', episodes: 1),
  media(14, 'A Sign of Affection: Extremely Long Season Title for Testing Wrapping', episodes: 13),
];

final _entries = [
  for (final (i, status) in ListStatus.values.indexed)
    WatchEntry(
      anime: Anime.fromAniList(_long[i % _long.length]),
      status: status,
      watched: 3,
      updatedAt: DateTime(2026, 1, i + 1),
    ),
];

/// (width, height, text scale): a small phone, the user's S24+ at 1.15, and large text.
const _configs = [(320.0, 640.0, 1.0), (412.0, 915.0, 1.15), (360.0, 740.0, 1.3), (360.0, 780.0, 2.0)];

void main() {
  // Real fonts, not the test font: overflows depend on the font's actual line heights.
  setUpAll(() async {
    for (final (family, files) in [
      ('Zen Kaku Gothic New', ['Regular', 'Medium', 'Bold'].map((w) => 'assets/fonts/ZenKakuGothicNew-$w.ttf')),
      ('Dela Gothic One', ['assets/fonts/DelaGothicOne-Regular.ttf']),
    ]) {
      final loader = FontLoader(family);
      for (final path in files) {
        loader.addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
      }
      await loader.load();
    }
  });

  for (final (width, height, scale) in _configs) {
    testWidgets('no overflow at ${width.toInt()}x${height.toInt()}, text ×$scale', (tester) async {
      tester.view.physicalSize = Size(width * 3, height * 3);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpApp(
        tester,
        catalogue: _long,
        prefs: {'watchlist.v1': jsonEncode([for (final e in _entries) e.toJson()])},
      );

      Future<void> scrollThrough(Finder scrollable) async {
        for (var i = 0; i < 6; i++) {
          await tester.drag(scrollable.first, const Offset(0, -500), warnIfMissed: false);
          await tester.pumpAndSettle();
        }
      }

      Future<void> tab(String name) async {
        await tester.tap(find.widgetWithText(NavigationDestination, name));
        await tester.pumpAndSettle();
      }

      // Home, including the horizontal rows.
      await scrollThrough(find.byType(Scrollable));

      await tab('Discover');
      await scrollThrough(find.byType(CustomScrollView));
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tab('My Anime');
      for (final s in ListStatus.values) {
        await tester.ensureVisible(find.text(s.label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(s.label));
        await tester.pumpAndSettle();
      }

      await tab('Library');
      await tab('Profile');
      await scrollThrough(find.byType(ListView));

      await tab('My Anime');
      await tester.ensureVisible(find.text(ListStatus.watching.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ListStatus.watching.label));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('The Apothecary Diaries').first);
      await tester.pumpAndSettle();
      await scrollThrough(find.byType(CustomScrollView));

      await unmount(tester);
    });
  }
}
