import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairo/data/local_store.dart';
import 'package:kairo/data/models.dart';
import 'package:kairo/data/watch_links.dart';

import 'support.dart';

void main() {
  test('recognises services from their links, including subdomains', () {
    expect(serviceFor('https://www.crunchyroll.com/watch/GX9U/ep-1')?.name, 'Crunchyroll');
    expect(serviceFor('https://m.bilibili.tv/en/play/1')?.name, 'Bilibili');
    expect(serviceFor('https://youtu.be/abc')?.name, 'YouTube');
    expect(serviceFor('https://www.netflix.com/title/1')?.blocksInAppPlayback, isTrue);
    expect(serviceFor('https://example.org/x'), isNull);
    expect(linkLabel('https://www.example.org/x'), 'example.org');
  });

  test('pasted text is cleaned up into a link', () {
    expect(parseWatchLink('Watch it here: https://www.crunchyroll.com/watch/1 !')?.host, 'www.crunchyroll.com');
    expect(parseWatchLink('bilibili.tv/en/play/2')?.toString(), 'https://bilibili.tv/en/play/2');
    expect(parseWatchLink('not a link'), isNull);
    expect(parseWatchLink(''), isNull);
  });

  test('direct video links are told apart from web pages', () {
    expect(isDirectMediaLink('https://nas.local/anime/ep1.mkv'), isTrue);
    expect(isDirectMediaLink('https://cdn.example.com/master.m3u8?token=1'), isTrue);
    expect(isDirectMediaLink('https://www.crunchyroll.com/watch/1'), isFalse);
  });

  testWidgets('a saved show link becomes the main Watch button on the details page', (tester) async {
    final frierenAnime = Anime.fromAniList(frieren);
    final store = MemoryStore(files: [
      LibraryFile(
        id: 'web:1:0:1',
        uri: 'https://www.crunchyroll.com/series/x',
        fileName: 'Crunchyroll',
        state: FileState.matched,
        addedAt: DateTime(2026),
        anime: frierenAnime,
        episode: 0,
      ),
    ]);
    await pumpApp(tester, store: store);

    await tester.tap(find.text('Details').first);
    await tester.pumpAndSettle();
    expect(find.text('Watch Ep 1 on Crunchyroll'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Add a link'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Crunchyroll'), findsWidgets, reason: 'official and saved links are both listed');
    await unmount(tester);
  });
}
