import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'anilist.dart';
import 'local_store.dart';
import 'models.dart';

/// Opened in `main()` before the app starts and passed in as an override.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('Override prefsProvider in main()'));

final aniListProvider = Provider<AniListClient>((ref) => AniListClient(prefs: ref.watch(prefsProvider)));

/// Shows the last saved copy at once and swaps in a fresh one when it arrives
/// (stale-while-revalidate). Without a saved copy it loads normally.
abstract class _CachedThenFresh<T> extends AsyncNotifier<T> {
  T? cached();
  Future<T> fetch();

  @override
  Future<T> build() async {
    final saved = cached();
    if (saved == null) return fetch();
    Future.microtask(revalidate);
    return saved;
  }

  /// Fetches a fresh copy in the background. On failure the saved copy stays up.
  Future<void> revalidate() async {
    try {
      final fresh = await fetch();
      if (ref.mounted) state = AsyncData(fresh);
    } catch (e, st) {
      if (ref.mounted && !state.hasValue) state = AsyncError(e, st);
    }
  }
}

/// Trending, this season, popular and top rated, for the Home tab.
/// Also refreshed when the app comes back to the foreground after a while.
class HomeFeedNotifier extends _CachedThenFresh<HomeFeed> {
  static const _staleAfter = Duration(minutes: 5);
  DateTime _fetchedAt = DateTime.now();

  @override
  HomeFeed? cached() => ref.read(aniListProvider).cachedHome();

  @override
  Future<HomeFeed> fetch() async {
    final feed = await ref.read(aniListProvider).home();
    _fetchedAt = DateTime.now();
    return feed;
  }

  @override
  Future<HomeFeed> build() {
    ref.watch(aniListProvider);
    final lifecycle = AppLifecycleListener(onResume: () {
      if (DateTime.now().difference(_fetchedAt) > _staleAfter) revalidate();
    });
    ref.onDispose(lifecycle.dispose);
    return super.build();
  }
}

final homeFeedProvider = AsyncNotifierProvider<HomeFeedNotifier, HomeFeed>(HomeFeedNotifier.new);

/// Full details for one title. Kept in memory once loaded.
class AnimeDetailsNotifier extends _CachedThenFresh<Anime> {
  AnimeDetailsNotifier(this.id);

  final int id;

  @override
  Anime? cached() => ref.read(aniListProvider).cachedDetails(id);

  @override
  Future<Anime> fetch() => ref.read(aniListProvider).details(id);

  @override
  Future<Anime> build() {
    ref.watch(aniListProvider);
    return super.build();
  }
}

final animeDetailsProvider =
    AsyncNotifierProvider.family<AnimeDetailsNotifier, Anime, int>(AnimeDetailsNotifier.new);

/// The best copy of a title available right now: full details once loaded, else the copy saved in the watchlist.
final animeProvider = Provider.family<Anime?, int>((ref, id) {
  return ref.watch(animeDetailsProvider(id)).value ?? ref.watch(watchlistProvider)[id]?.anime;
});

/// The user's list, saved on the phone.
class WatchlistNotifier extends Notifier<Map<int, WatchEntry>> {
  static const _key = 'watchlist.v1';

  @override
  Map<int, WatchEntry> build() {
    final raw = ref.watch(prefsProvider).getString(_key);
    if (raw == null) return {};
    try {
      final entries = [for (final e in jsonDecode(raw) as List) WatchEntry.fromJson(e as Map<String, dynamic>)];
      return {for (final e in entries) e.animeId: e};
    } catch (_) {
      // A corrupt save shouldn't stop the app from opening.
      return {};
    }
  }

  void _save(Map<int, WatchEntry> next) {
    state = next;
    ref.read(prefsProvider).setString(_key, jsonEncode([for (final e in next.values) e.toJson()]));
  }

  void setStatus(Anime anime, ListStatus status) {
    final current = state[anime.id];
    final watched = switch ((status, anime.episodes)) {
      (ListStatus.completed, final int total) => total,
      _ => current?.watched ?? 0,
    };
    _save({
      ...state,
      anime.id: current == null
          ? WatchEntry(anime: anime, status: status, watched: watched, updatedAt: DateTime.now())
          : current.copyWith(anime: anime, status: status, watched: watched),
    });
  }

  /// Removes a title and returns its entry so the caller can offer Undo.
  WatchEntry? remove(int animeId) {
    final entry = state[animeId];
    if (entry != null) _save({...state}..remove(animeId));
    return entry;
  }

  /// Puts back an entry taken out with [remove].
  void restore(WatchEntry entry) => _save({...state, entry.animeId: entry});

  /// Marks the next episode watched; completes the title after the last one.
  void markNextWatched(Anime anime) {
    final current = state[anime.id];
    final total = anime.episodes;
    if (current == null || (total != null && current.watched >= total)) return;
    final watched = current.watched + 1;
    _save({
      ...state,
      anime.id: current.copyWith(
        anime: anime,
        watched: watched,
        status: watched == total ? ListStatus.completed : current.status,
      ),
    });
  }

  /// Sets how many episodes are watched (tapping an episode in the details list).
  /// Adds the title as Watching if it isn't on the list yet; completes it at the last episode.
  void setWatched(Anime anime, int watched) {
    final current = state[anime.id];
    final total = anime.episodes;
    final status = total != null && watched >= total
        ? ListStatus.completed
        : (current == null || current.status == ListStatus.completed || current.status == ListStatus.planned)
            ? ListStatus.watching
            : current.status;
    _save({
      ...state,
      anime.id: current == null
          ? WatchEntry(anime: anime, status: status, watched: watched, updatedAt: DateTime.now())
          : current.copyWith(anime: anime, status: status, watched: watched),
    });
  }

  /// Refreshes the saved copy of a title after its details load (new episodes, artwork, ...).
  void refreshSnapshot(Anime anime) {
    final current = state[anime.id];
    if (current == null) return;
    _save({...state, anime.id: WatchEntry(anime: anime, status: current.status, watched: current.watched, updatedAt: current.updatedAt)});
  }
}

final watchlistProvider = NotifierProvider<WatchlistNotifier, Map<int, WatchEntry>>(WatchlistNotifier.new);

/// Watchlist entries, most recently touched first.
final sortedWatchlistProvider = Provider<List<WatchEntry>>((ref) {
  return ref.watch(watchlistProvider).values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
});

final localStoreProvider = Provider<LocalStore>((ref) => MemoryStore()); // Replaced by SqliteStore in main().

/// Where playback stopped, per (anime, episode).
class ProgressNotifier extends Notifier<Map<(int, int), PlaybackProgress>> {
  @override
  Map<(int, int), PlaybackProgress> build() => {for (final p in ref.watch(localStoreProvider).progress) (p.animeId, p.episode): p};

  void save(int animeId, int episode, Duration position, Duration duration) {
    if (duration <= Duration.zero) return;
    final p = PlaybackProgress(animeId: animeId, episode: episode, position: position, duration: duration, updatedAt: DateTime.now());
    state = {...state, (animeId, episode): p};
    ref.read(localStoreProvider).putProgress(p);
  }
}

final progressProvider = NotifierProvider<ProgressNotifier, Map<(int, int), PlaybackProgress>>(ProgressNotifier.new);

/// Episodes started but not finished, most recent first, one per title.
final resumeListProvider = Provider<List<PlaybackProgress>>((ref) {
  final seen = <int>{};
  final progress = ref.watch(progressProvider).values.where((p) => !p.finished && p.position > const Duration(seconds: 30)).toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return [for (final p in progress) if (seen.add(p.animeId)) p];
});
