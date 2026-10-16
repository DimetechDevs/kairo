import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mock_data.dart';
import 'models.dart';

/// The catalogue. Step 4 replaces this with AniList plus a SQLite cache.
final catalogueProvider = Provider<List<Anime>>((ref) => mockCatalogue);

final animeProvider = Provider.family<Anime, int>(
  (ref, id) => ref.watch(catalogueProvider).firstWhere((a) => a.id == id),
);

class WatchlistNotifier extends Notifier<Map<int, WatchEntry>> {
  @override
  Map<int, WatchEntry> build() => {for (final e in mockWatchlist) e.animeId: e};

  void setStatus(int animeId, ListStatus status) {
    final current = state[animeId] ?? WatchEntry(animeId: animeId, status: status, watched: 0);
    state = {...state, animeId: current.copyWith(status: status)};
  }

  /// Marks the next episode watched; completes the title after the last one.
  void markNextWatched(Anime anime) {
    final current = state[anime.id];
    if (current == null || current.watched >= anime.episodes) return;
    final watched = current.watched + 1;
    state = {
      ...state,
      anime.id: current.copyWith(
        watched: watched,
        status: watched == anime.episodes ? ListStatus.completed : current.status,
      ),
    };
  }
}

final watchlistProvider = NotifierProvider<WatchlistNotifier, Map<int, WatchEntry>>(WatchlistNotifier.new);

class LibraryNotifier extends Notifier<List<LibraryFile>> {
  @override
  List<LibraryFile> build() => mockLibrary;

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

final progressProvider = Provider<List<PlaybackProgress>>((ref) => mockProgress);
