import 'package:flutter/material.dart';

/// A catalogue entry. In step 4 these come from AniList; for now from mock data.
class Anime {
  const Anime({
    required this.id,
    required this.title,
    required this.shortTitle,
    required this.year,
    required this.format,
    required this.episodes,
    required this.status,
    required this.genres,
    required this.synopsis,
    required this.palette,
    this.nativeTitle,
  });

  final int id;
  final String title;
  final String shortTitle;
  final String? nativeTitle;
  final int year;
  final String format;
  final int episodes;
  final String status;
  final List<String> genres;
  final String synopsis;

  /// Two colours for the placeholder cover until real artwork is loaded.
  final List<Color> palette;
}

enum ListStatus {
  watching('Watching'),
  planned('Planned'),
  completed('Completed'),
  paused('Paused'),
  dropped('Dropped');

  const ListStatus(this.label);
  final String label;
}

class WatchEntry {
  const WatchEntry({required this.animeId, required this.status, required this.watched});

  final int animeId;
  final ListStatus status;
  final int watched;

  WatchEntry copyWith({ListStatus? status, int? watched}) =>
      WatchEntry(animeId: animeId, status: status ?? this.status, watched: watched ?? this.watched);
}

enum FileState { matched, unmatched, missing }

/// A video the user imported from their phone.
class LibraryFile {
  const LibraryFile({
    required this.id,
    required this.fileName,
    required this.sizeLabel,
    required this.state,
    this.animeId,
    this.episode,
    this.suggestedAnimeId,
    this.suggestedEpisode,
  });

  final String id;
  final String fileName;
  final String sizeLabel;
  final FileState state;
  final int? animeId;
  final int? episode;
  final int? suggestedAnimeId;
  final int? suggestedEpisode;

  LibraryFile matchTo(int animeId, int episode) => LibraryFile(
        id: id,
        fileName: fileName,
        sizeLabel: sizeLabel,
        state: FileState.matched,
        animeId: animeId,
        episode: episode,
      );
}

/// Where the user stopped in an episode.
class PlaybackProgress {
  const PlaybackProgress({required this.animeId, required this.episode, required this.position, required this.duration});

  final int animeId;
  final int episode;
  final Duration position;
  final Duration duration;

  double get fraction => duration.inMilliseconds == 0 ? 0 : position.inMilliseconds / duration.inMilliseconds;
  Duration get remaining => duration - position;
}
