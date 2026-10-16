import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'anilist.dart';
import 'models.dart';

/// Opened in `main()` before the app starts and passed in as an override.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('Override prefsProvider in main()'));

final aniListProvider = Provider<AniListClient>((ref) => AniListClient(prefs: ref.watch(prefsProvider)));

/// Trending, this season, popular and top rated, for the Home tab.
final homeFeedProvider = FutureProvider<HomeFeed>((ref) => ref.watch(aniListProvider).home());

/// Full details for one title. Kept in memory once loaded.
final animeDetailsProvider = FutureProvider.family<Anime, int>((ref, id) => ref.watch(aniListProvider).details(id));

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

  void remove(int animeId) => _save({...state}..remove(animeId));

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

/// Imported videos. Empty until the file import step lands.
class LibraryNotifier extends Notifier<List<LibraryFile>> {
  @override
  List<LibraryFile> build() => const [];

  void confirmSuggestedMatch(String fileId) {
    state = [
      for (final f in state)
        if (f.id == fileId && f.suggestedAnimeId != null && f.suggestedEpisode != null)
          f.matchTo(f.suggestedAnimeId!, f.suggestedEpisode!)
        else
          f,
    ];
  }
}

final libraryProvider = NotifierProvider<LibraryNotifier, List<LibraryFile>>(LibraryNotifier.new);

/// Where playback stopped per episode. Empty until real playback lands.
final progressProvider = Provider<List<PlaybackProgress>>((ref) => const []);
