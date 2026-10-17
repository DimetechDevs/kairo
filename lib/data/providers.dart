import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'anilist.dart';
import 'documents.dart';
import 'filename_parser.dart';
import 'local_store.dart';
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

  /// Replaces the whole list as-is (timestamps kept). Used when merging with AniList.
  void replaceAll(Map<int, WatchEntry> entries) => _save(entries);

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

final documentsProvider = Provider<Documents>((ref) => const Documents());

/// Videos the user imported from the phone, plus stream URLs they added.
class LibraryNotifier extends Notifier<List<LibraryFile>> {
  @override
  List<LibraryFile> build() => [...ref.watch(localStoreProvider).files]..sort((a, b) => a.addedAt.compareTo(b.addedAt));

  LocalStore get _store => ref.read(localStoreProvider);

  void _put(LibraryFile file) {
    state = [for (final f in state) if (f.id != file.id) f, file];
    _store.putFile(file);
  }

  LibraryFile? fileFor(int animeId, int episode) =>
      state.where((f) => f.playable && f.animeId == animeId && f.episode == episode).firstOrNull;

  /// Adds picked videos, then guesses which show and episode each one is.
  Future<void> importPicked(List<PickedDocument> picked) async {
    final now = DateTime.now();
    final known = {for (final f in state) f.uri};
    final added = <LibraryFile>[];
    for (final (i, doc) in picked.indexed) {
      if (known.contains(doc.uri)) continue;
      final file = LibraryFile(
        id: doc.uri,
        uri: doc.uri,
        fileName: doc.name,
        sizeBytes: doc.size,
        state: FileState.unmatched,
        addedAt: now.add(Duration(milliseconds: i)),
      );
      added.add(file);
      _put(file);
    }
    await _suggestMatches(added);
  }

  /// One AniList search per distinct title guess (a season folder is usually one show).
  Future<void> _suggestMatches(List<LibraryFile> files) async {
    final client = ref.read(aniListProvider);
    final byTitle = <String, Anime?>{};
    for (final file in files) {
      final guess = parseVideoName(file.fileName);
      if (guess.title.isEmpty) continue;
      if (!byTitle.containsKey(guess.title)) {
        try {
          byTitle[guess.title] = (await client.browse(search: guess.title, perPage: 1)).items.firstOrNull;
        } catch (_) {
          byTitle[guess.title] = null; // Offline or no match: the user can choose by hand.
        }
      }
      final anime = byTitle[guess.title];
      final current = state.where((f) => f.id == file.id).firstOrNull;
      if (anime == null || current == null || current.state != FileState.unmatched) continue;
      _put(current.copyWith(suggestedAnime: anime, suggestedEpisode: guess.episode ?? 1));
    }
  }

  void confirmSuggestedMatch(String fileId) {
    final file = state.where((f) => f.id == fileId).firstOrNull;
    if (file?.suggestedAnime == null) return;
    _put(file!.matchTo(file.suggestedAnime!, file.suggestedEpisode ?? 1));
  }

  void matchTo(String fileId, Anime anime, int episode) {
    final file = state.where((f) => f.id == fileId).firstOrNull;
    if (file == null) return;
    _put(file.matchTo(anime, episode));
  }

  /// Adds a picked file straight to a known episode (from the details page).
  void addFileFor(PickedDocument doc, Anime anime, int episode) {
    final existing = state.where((f) => f.uri == doc.uri).firstOrNull;
    _put((existing ??
            LibraryFile(
              id: doc.uri,
              uri: doc.uri,
              fileName: doc.name,
              sizeBytes: doc.size,
              state: FileState.matched,
              addedAt: DateTime.now(),
            ))
        .matchTo(anime, episode));
  }

  /// Adds a stream URL the user supplied (their own server, a direct HLS/MP4 link) for one episode.
  void addStream({required Anime anime, required int episode, required String url, String? label}) {
    final now = DateTime.now();
    _put(LibraryFile(
      id: 'stream:${anime.id}:$episode:${now.microsecondsSinceEpoch}',
      uri: url.trim(),
      fileName: label?.trim().isNotEmpty == true ? label!.trim() : 'Stream · Episode $episode',
      state: FileState.matched,
      addedAt: now,
      anime: anime,
      episode: episode,
    ));
  }

  /// Points a missing entry at a new copy of the file.
  void relink(String fileId, PickedDocument doc) {
    final file = state.where((f) => f.id == fileId).firstOrNull;
    if (file == null) return;
    ref.read(documentsProvider).release(file.uri).ignore();
    _put(file.copyWith(uri: doc.uri, fileName: doc.name, sizeBytes: doc.size, state: file.anime != null ? FileState.matched : FileState.unmatched));
  }

  void remove(String fileId) {
    final file = state.where((f) => f.id == fileId).firstOrNull;
    if (file == null) return;
    state = [for (final f in state) if (f.id != fileId) f];
    _store.deleteFile(fileId);
    if (!file.isStream) ref.read(documentsProvider).release(file.uri).ignore();
  }

  /// Marks files that were moved or deleted outside Kairo (and un-marks ones that came back).
  Future<void> checkMissing() async {
    final docs = ref.read(documentsProvider);
    for (final file in [...state]) {
      if (file.isStream) continue;
      final exists = await docs.exists(file.uri);
      if (!exists && file.state != FileState.missing) {
        _put(file.copyWith(state: FileState.missing));
      } else if (exists && file.state == FileState.missing) {
        _put(file.copyWith(state: file.anime != null ? FileState.matched : FileState.unmatched));
      }
    }
  }
}

final libraryProvider = NotifierProvider<LibraryNotifier, List<LibraryFile>>(LibraryNotifier.new);

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

/// Episodes started but not finished that can still be played, most recent first, one per title.
final resumeListProvider = Provider<List<(PlaybackProgress, LibraryFile)>>((ref) {
  final files = ref.watch(libraryProvider);
  final seen = <int>{};
  final result = <(PlaybackProgress, LibraryFile)>[];
  final progress = ref.watch(progressProvider).values.where((p) => !p.finished && p.position > const Duration(seconds: 30)).toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  for (final p in progress) {
    if (!seen.add(p.animeId)) continue;
    final file = files.where((f) => f.playable && f.animeId == p.animeId && f.episode == p.episode).firstOrNull;
    if (file != null) result.add((p, file));
  }
  return result;
});
