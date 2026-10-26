import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kairo/data/anilist.dart';
import 'package:kairo/data/anilist_sync.dart';
import 'package:kairo/data/models.dart';
import 'package:kairo/data/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

/// A user's AniList list, editable through the same queries the app sends.
class FakeAccount {
  /// mediaId → (status, progress, updatedAt seconds).
  final list = <int, (String, int, int)>{};
  final media = {for (final m in [frieren, dandadan, solo]) m['id'] as int: m};
  bool offline = false;
  bool expired = false;

  late final client = MockClient((req) async {
    if (offline) throw http.ClientException('offline');
    if (expired) return http.Response(jsonEncode({'errors': [{'message': 'Invalid token'}]}), 401);
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    final q = body['query'] as String;
    final v = body['variables'] as Map<String, dynamic>;
    Object data;
    if (q.contains('Viewer')) {
      data = {'Viewer': {'id': 7, 'name': 'Dime', 'avatar': {'large': null}}};
    } else if (q.contains('MediaListCollection')) {
      data = {
        'MediaListCollection': {
          'lists': [
            {
              'entries': [
                for (final e in list.entries)
                  {'id': e.key + 1000, 'status': e.value.$1, 'progress': e.value.$2, 'updatedAt': e.value.$3, 'media': media[e.key]},
              ],
            },
          ],
        },
      };
    } else if (q.contains('SaveMediaListEntry')) {
      list[v['mediaId'] as int] = (v['status'] as String, v['progress'] as int, DateTime.now().millisecondsSinceEpoch ~/ 1000);
      data = {'SaveMediaListEntry': {'id': 1}};
    } else if (q.contains('DeleteMediaListEntry')) {
      list.remove((v['id'] as int) - 1000);
      data = {'DeleteMediaListEntry': {'deleted': true}};
    } else if (q.contains('MediaList(')) {
      final id = v['mediaId'] as int;
      if (!list.containsKey(id)) return http.Response(jsonEncode({'errors': [{'message': 'Not Found.'}]}), 404);
      data = {'MediaList': {'id': id + 1000}};
    } else {
      throw StateError('unexpected query');
    }
    return http.Response(jsonEncode({'data': data}), 200);
  });
}

Future<ProviderContainer> _signedIn(FakeAccount account, {List<WatchEntry> local = const []}) async {
  SharedPreferences.setMockInitialValues({
    'anilist.user': jsonEncode({'id': 7, 'name': 'Dime', 'avatarUrl': null}),
    'watchlist.v1': jsonEncode([for (final e in local) e.toJson()]),
  });
  final sp = await SharedPreferences.getInstance();
  final tokens = MemoryTokenStore()..token = 'token';
  final c = ProviderContainer(overrides: [
    prefsProvider.overrideWithValue(sp),
    aniListProvider.overrideWithValue(AniListClient(httpClient: account.client)),
    tokenStoreProvider.overrideWithValue(tokens),
  ]);
  addTearDown(c.dispose);
  c.read(aniListSyncProvider); // Start listening for local changes.
  return c;
}

WatchEntry _entry(Map<String, dynamic> m, ListStatus s, int watched, DateTime at) =>
    WatchEntry(anime: Anime.fromAniList(m), status: s, watched: watched, updatedAt: at);

int _secs(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

void main() {
  test('first sync merges both lists; the newer side wins', () async {
    final account = FakeAccount()
      ..list[1] = ('CURRENT', 10, _secs(DateTime(2026, 10, 10))) // Newer on AniList.
      ..list[3] = ('PLANNING', 0, _secs(DateTime(2026, 1, 1))); // Older on AniList.
    final c = await _signedIn(account, local: [
      _entry(frieren, ListStatus.watching, 4, DateTime(2026, 10, 1)),
      _entry(solo, ListStatus.watching, 2, DateTime(2026, 10, 5)),
      _entry(dandadan, ListStatus.planned, 0, DateTime(2026, 10, 6)), // Only on the phone.
    ]);

    await c.read(aniListSyncProvider.notifier).syncNow();

    final list = c.read(watchlistProvider);
    expect(list[1]!.watched, 10, reason: 'AniList had the newer Frieren progress');
    expect(list[3]!.status, ListStatus.watching, reason: 'the phone had the newer Solo Leveling change');
    expect((account.list[3]!.$1, account.list[3]!.$2), ('CURRENT', 2));
    expect(account.list[2]?.$1, 'PLANNING', reason: 'phone-only titles are uploaded');
    expect(c.read(aniListSyncProvider).lastSync, isNotNull);
  });

  test('local edits after sign-in are pushed, and removals are mirrored', () async {
    final account = FakeAccount()..list[1] = ('CURRENT', 1, _secs(DateTime(2026)));
    final c = await _signedIn(account);
    await c.read(aniListSyncProvider.notifier).syncNow();

    final frierenAnime = c.read(watchlistProvider)[1]!.anime;
    c.read(watchlistProvider.notifier).markNextWatched(frierenAnime);
    await c.read(aniListSyncProvider.notifier).flush();
    expect(account.list[1]!.$2, 2);

    c.read(watchlistProvider.notifier).remove(1);
    await c.read(aniListSyncProvider.notifier).flush();
    expect(account.list.containsKey(1), isFalse);
  });

  test('undoing a removal puts the title back here and on AniList', () async {
    final account = FakeAccount()..list[1] = ('CURRENT', 1, _secs(DateTime(2026)));
    final c = await _signedIn(account);
    await c.read(aniListSyncProvider.notifier).syncNow();

    final removed = c.read(watchlistProvider.notifier).remove(1)!;
    await c.read(aniListSyncProvider.notifier).flush();
    expect(account.list.containsKey(1), isFalse);

    c.read(watchlistProvider.notifier).restore(removed);
    await c.read(aniListSyncProvider.notifier).flush();
    expect(c.read(watchlistProvider)[1]?.watched, 1);
    expect((account.list[1]!.$1, account.list[1]!.$2), ('CURRENT', 1));
  });

  test('edits made offline are queued and sent on the next sync', () async {
    final account = FakeAccount();
    final c = await _signedIn(account);
    await c.read(aniListSyncProvider.notifier).syncNow();

    account.offline = true;
    c.read(watchlistProvider.notifier).setStatus(Anime.fromAniList(solo), ListStatus.planned);
    await c.read(aniListSyncProvider.notifier).flush();
    expect(account.list, isEmpty);

    account.offline = false;
    await c.read(aniListSyncProvider.notifier).syncNow();
    expect(account.list[3]?.$1, 'PLANNING');
    expect(c.read(watchlistProvider)[3]?.status, ListStatus.planned);
  });

  test('a title removed on AniList elsewhere is removed from the phone', () async {
    final account = FakeAccount()..list[2] = ('CURRENT', 3, _secs(DateTime(2026)));
    final c = await _signedIn(account);
    await c.read(aniListSyncProvider.notifier).syncNow();
    expect(c.read(watchlistProvider).containsKey(2), isTrue);

    account.list.remove(2);
    await c.read(aniListSyncProvider.notifier).syncNow();
    expect(c.read(watchlistProvider).containsKey(2), isFalse);
  });

  test('an expired sign-in signs out but keeps the list', () async {
    final account = FakeAccount()..expired = true;
    final c = await _signedIn(account, local: [_entry(frieren, ListStatus.watching, 4, DateTime(2026))]);

    await c.read(aniListSyncProvider.notifier).syncNow();
    final state = c.read(aniListSyncProvider);
    expect(state.signedIn, isFalse);
    expect(state.error, contains('expired'));
    expect(c.read(watchlistProvider)[1]!.watched, 4);
  });
}
