import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairo/data/anilist.dart';
import 'package:kairo/data/documents.dart';
import 'package:kairo/data/filename_parser.dart';
import 'package:kairo/data/local_store.dart';
import 'package:kairo/data/models.dart';
import 'package:kairo/data/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

class FakeDocuments extends Documents {
  FakeDocuments({this.missing = const {}});

  final Set<String> missing;
  final released = <String>[];

  @override
  Future<bool> exists(String uri) async => !missing.contains(uri);

  @override
  Future<void> release(String uri) async => released.add(uri);
}

Future<ProviderContainer> _container({LocalStore? store, Documents? documents}) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final fake = FakeAniList();
  final container = ProviderContainer(overrides: [
    prefsProvider.overrideWithValue(sp),
    aniListProvider.overrideWithValue(AniListClient(httpClient: fake.client, prefs: sp)),
    localStoreProvider.overrideWithValue(store ?? MemoryStore()),
    documentsProvider.overrideWithValue(documents ?? FakeDocuments()),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('parseVideoName', () {
    test('release-group style names', () {
      final r = parseVideoName('[SubsPlease] Sousou no Frieren - 03 (1080p) [ABCD1234].mkv');
      expect(r.title, 'Sousou no Frieren');
      expect(r.episode, 3);
    });

    test('SxxEyy and Ep styles', () {
      expect(parseVideoName('Solo.Leveling.S01E07.1080p.WEB-DL.mkv'), (title: 'Solo Leveling', episode: 7));
      expect(parseVideoName('dandadan_ep08.mp4'), (title: 'dandadan', episode: 8));
      expect(parseVideoName('Frieren Episode 12.mp4'), (title: 'Frieren', episode: 12));
    });

    test('ignores years and resolutions', () {
      final r = parseVideoName('Your Name (2016) 1080p.mkv');
      expect(r.episode, isNull);
      expect(r.title, 'Your Name');
    });
  });

  test('importing files suggests the show and episode from AniList', () async {
    final c = await _container();
    final library = c.read(libraryProvider.notifier);

    await library.importPicked(const [
      PickedDocument(uri: 'content://a/1', name: '[Group] Frieren - 02 (1080p).mkv', size: 1 << 30),
      PickedDocument(uri: 'content://a/2', name: '[Group] Frieren - 03 (1080p).mkv'),
    ]);

    final files = c.read(libraryProvider);
    expect(files, hasLength(2));
    expect(files.first.state, FileState.unmatched);
    expect(files.first.suggestedAnime?.title, 'Frieren');
    expect(files.first.suggestedEpisode, 2);
    expect(files.first.sizeLabel, '1.0 GB');

    library.confirmSuggestedMatch('content://a/1');
    expect(library.fileFor(1, 2)?.uri, 'content://a/1');
    expect(library.fileFor(1, 3), isNull, reason: 'still waiting for confirmation');
  });

  test('stream URLs play like files and resume where they stopped', () async {
    final store = MemoryStore();
    final c = await _container(store: store);
    final frierenAnime = Anime.fromAniList(frieren);

    c.read(libraryProvider.notifier).addStream(anime: frierenAnime, episode: 4, url: ' https://jellyfin.local/ep4.m3u8 ');
    final file = c.read(libraryProvider.notifier).fileFor(1, 4)!;
    expect(file.isStream, isTrue);
    expect(file.uri, 'https://jellyfin.local/ep4.m3u8');

    c.read(progressProvider.notifier).save(1, 4, const Duration(minutes: 10), const Duration(minutes: 24));
    expect(c.read(resumeListProvider).single.$1.episode, 4);
    expect(store.progress.single.position, const Duration(minutes: 10), reason: 'saved to the store');

    // Watched past 90%: no longer offered for resuming.
    c.read(progressProvider.notifier).save(1, 4, const Duration(minutes: 23), const Duration(minutes: 24));
    expect(c.read(resumeListProvider), isEmpty);
  });

  test('files that disappear are marked missing and can be relinked', () async {
    final frierenAnime = Anime.fromAniList(frieren);
    final store = MemoryStore(files: [
      LibraryFile(
        id: 'content://old',
        uri: 'content://old',
        fileName: 'ep1.mkv',
        state: FileState.matched,
        addedAt: DateTime(2026),
        anime: frierenAnime,
        episode: 1,
      ),
    ]);
    final docs = FakeDocuments(missing: {'content://old'});
    final c = await _container(store: store, documents: docs);
    final library = c.read(libraryProvider.notifier);

    await library.checkMissing();
    expect(c.read(libraryProvider).single.state, FileState.missing);
    expect(library.fileFor(1, 1), isNull);

    library.relink('content://old', const PickedDocument(uri: 'content://new', name: 'ep1-moved.mkv'));
    expect(library.fileFor(1, 1)?.uri, 'content://new');
    expect(docs.released, ['content://old']);
  });

  testWidgets('details lists official places to watch and plays an imported episode', (tester) async {
    final frierenAnime = Anime.fromAniList(frieren);
    SharedPreferences.setMockInitialValues({});
    final store = MemoryStore(
      files: [
        LibraryFile(
          id: 'f',
          uri: 'content://f',
          fileName: 'ep2.mkv',
          state: FileState.matched,
          addedAt: DateTime(2026),
          anime: frierenAnime,
          episode: 2,
        ),
      ],
      progress: [
        PlaybackProgress(
          animeId: 1,
          episode: 2,
          position: const Duration(minutes: 5),
          duration: const Duration(minutes: 24),
          updatedAt: DateTime(2026),
        ),
      ],
    );
    await pumpApp(tester, store: store);

    expect(find.text('Ep 2 · 19 min left'), findsOneWidget, reason: 'Continue watching shows the resume point');

    await tester.tap(find.text('Details').first);
    await tester.pumpAndSettle();
    expect(find.text('Resume Ep 2'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Where to watch'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Crunchyroll'), findsOneWidget);
    expect(find.text('Official Site'), findsNothing, reason: 'only streaming links are listed');
    await unmount(tester);
  });
}
