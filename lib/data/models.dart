import 'package:flutter/material.dart';

/// A catalogue entry from AniList.
///
/// [Anime.fromAniList] reads the AniList `Media` shape and [toJson] writes the same shape back,
/// so a saved copy (for example in the watchlist) can be read again offline.
class Anime {
  const Anime({
    required this.id,
    required this.title,
    required this.genres,
    required this.synopsis,
    this.romajiTitle,
    this.nativeTitle,
    this.coverUrl,
    this.bannerUrl,
    this.color,
    this.format,
    this.status,
    this.episodes,
    this.duration,
    this.year,
    this.season,
    this.score,
    this.popularity,
    this.studios = const [],
    this.nextAiring,
    this.recommendations = const [],
    this.externalLinks = const [],
    this.streamingEpisodes = const [],
  });

  final int id;

  /// English title when AniList has one, otherwise the romaji title.
  final String title;
  final String? romajiTitle;
  final String? nativeTitle;
  final String? coverUrl;
  final String? bannerUrl;

  /// AniList's dominant cover colour, used for placeholders and accents.
  final Color? color;

  /// AniList enum values, e.g. `TV`, `MOVIE`; see [formatLabel].
  final String? format;

  /// AniList enum values, e.g. `RELEASING`; see [statusLabel].
  final String? status;

  /// Total episodes; null while a show is airing and the count isn't announced.
  final int? episodes;

  /// Minutes per episode.
  final int? duration;
  final int? year;
  final String? season;

  /// Average score out of 100.
  final int? score;
  final int? popularity;
  final List<String> genres;
  final List<String> studios;
  final String synopsis;
  final NextAiring? nextAiring;

  /// Only filled in by the details query.
  final List<Anime> recommendations;

  /// Official places to watch or read about it (details query only).
  final List<ExternalLink> externalLinks;

  /// Per-episode links on official streaming services (details query only).
  final List<StreamingEpisode> streamingEpisodes;

  List<ExternalLink> get streamingLinks => [for (final l in externalLinks) if (l.type == 'STREAMING') l];

  /// The official stream for an episode, matched by the number in its title (falls back to list order).
  StreamingEpisode? streamingEpisode(int episode) {
    for (final e in streamingEpisodes) {
      if (e.number == episode) return e;
    }
    final numbered = streamingEpisodes.any((e) => e.number != null);
    return !numbered && episode <= streamingEpisodes.length ? streamingEpisodes[episode - 1] : null;
  }

  String get shortTitle => title;

  bool get isAiring => status == 'RELEASING';

  /// Episodes that have aired so far (or the total once it's finished).
  int get airedEpisodes => nextAiring != null ? nextAiring!.episode - 1 : (episodes ?? 0);

  String get formatLabel => switch (format) {
        'TV' => 'TV',
        'TV_SHORT' => 'TV Short',
        'MOVIE' => 'Movie',
        'SPECIAL' => 'Special',
        'OVA' => 'OVA',
        'ONA' => 'ONA',
        'MUSIC' => 'Music',
        _ => 'Anime',
      };

  String get statusLabel => switch (status) {
        'FINISHED' => 'Finished',
        'RELEASING' => 'Airing',
        'NOT_YET_RELEASED' => 'Upcoming',
        'CANCELLED' => 'Cancelled',
        'HIATUS' => 'On hiatus',
        _ => '',
      };

  String get episodesLabel {
    if (format == 'MOVIE' && (episodes ?? 1) == 1) return duration != null ? '$duration min' : 'Movie';
    if (episodes != null) return '$episodes eps';
    if (isAiring && airedEpisodes > 0) return '$airedEpisodes eps so far';
    return '? eps';
  }

  /// Two colours for gradients and the placeholder shown while artwork loads.
  List<Color> get palette {
    final base = color ?? const Color(0xFF5B3FD1);
    final hsl = HSLColor.fromColor(base);
    return [
      hsl.withLightness((hsl.lightness * 0.85).clamp(0.25, 0.55)).toColor(),
      hsl.withLightness(0.12).withSaturation((hsl.saturation * 0.6).clamp(0, 1)).toColor(),
    ];
  }

  /// A colour from the artwork that reads well as an accent on the dark background.
  Color get accent {
    if (color == null) return const Color(0xFFA78BFA);
    final hsl = HSLColor.fromColor(color!);
    return hsl.withLightness(hsl.lightness.clamp(0.55, 0.75)).toColor();
  }

  factory Anime.fromAniList(Map<String, dynamic> m) {
    final title = m['title'] as Map<String, dynamic>? ?? const {};
    final cover = m['coverImage'] as Map<String, dynamic>? ?? const {};
    final next = m['nextAiringEpisode'] as Map<String, dynamic>?;
    final studios = (m['studios'] as Map<String, dynamic>?)?['nodes'] as List? ?? const [];
    final recs = (m['recommendations'] as Map<String, dynamic>?)?['nodes'] as List? ?? const [];
    final english = title['english'] as String?;
    final romaji = title['romaji'] as String?;

    return Anime(
      id: m['id'] as int,
      title: english ?? romaji ?? title['native'] as String? ?? 'Untitled',
      romajiTitle: romaji,
      nativeTitle: title['native'] as String?,
      coverUrl: (cover['extraLarge'] ?? cover['large']) as String?,
      bannerUrl: m['bannerImage'] as String?,
      color: _parseColor(cover['color'] as String?),
      format: m['format'] as String?,
      status: m['status'] as String?,
      episodes: m['episodes'] as int?,
      duration: m['duration'] as int?,
      year: m['seasonYear'] as int? ?? (m['startDate'] as Map<String, dynamic>?)?['year'] as int?,
      season: m['season'] as String?,
      score: m['averageScore'] as int?,
      popularity: m['popularity'] as int?,
      genres: [for (final g in m['genres'] as List? ?? const []) g as String],
      studios: [for (final s in studios) (s as Map<String, dynamic>)['name'] as String],
      synopsis: cleanDescription(m['description'] as String?),
      nextAiring: next == null
          ? null
          : NextAiring(
              episode: next['episode'] as int,
              at: DateTime.fromMillisecondsSinceEpoch((next['airingAt'] as int) * 1000),
            ),
      recommendations: [
        for (final r in recs)
          if ((r as Map<String, dynamic>)['mediaRecommendation'] case final Map<String, dynamic> media)
            Anime.fromAniList(media),
      ],
      externalLinks: [
        for (final l in m['externalLinks'] as List? ?? const [])
          if (l case {'site': final String site, 'url': final String url})
            ExternalLink(
              site: site,
              url: url,
              type: l['type'] as String?,
              language: l['language'] as String?,
              color: _parseColor(l['color'] as String?),
              icon: l['icon'] as String?,
            ),
      ],
      streamingEpisodes: [
        for (final e in m['streamingEpisodes'] as List? ?? const [])
          if (e case {'title': final String title, 'url': final String url})
            StreamingEpisode(title: title, url: url, site: e['site'] as String?, thumbnail: e['thumbnail'] as String?),
      ],
    );
  }

  /// The AniList shape again, without recommendations, for saving on the phone.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': {'english': title, 'romaji': romajiTitle, 'native': nativeTitle},
        'coverImage': {'extraLarge': coverUrl, 'color': color == null ? null : _colorHex(color!)},
        'bannerImage': bannerUrl,
        'format': format,
        'status': status,
        'episodes': episodes,
        'duration': duration,
        'seasonYear': year,
        'season': season,
        'averageScore': score,
        'popularity': popularity,
        'genres': genres,
        'studios': {
          'nodes': [for (final s in studios) {'name': s}],
        },
        'description': synopsis,
        'nextAiringEpisode':
            nextAiring == null ? null : {'episode': nextAiring!.episode, 'airingAt': nextAiring!.at.millisecondsSinceEpoch ~/ 1000},
      };

  static Color? _parseColor(String? hex) {
    if (hex == null || hex.length != 7) return null;
    final v = int.tryParse(hex.substring(1), radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  static String _colorHex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

/// AniList descriptions are light HTML; this turns them into plain text.
String cleanDescription(String? html) {
  if (html == null || html.trim().isEmpty) return 'No synopsis yet.';
  return html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&mdash;', '—')
      .replaceAll('&ndash;', '–')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

class NextAiring {
  const NextAiring({required this.episode, required this.at});

  final int episode;
  final DateTime at;

  /// e.g. "Ep 5 in 2d 4h".
  String label([DateTime? now]) {
    final left = at.difference(now ?? DateTime.now());
    if (left.isNegative) return 'Ep $episode out now';
    final d = left.inDays;
    final h = left.inHours % 24;
    final m = left.inMinutes % 60;
    final when = d > 0 ? '${d}d ${h}h' : (h > 0 ? '${h}h ${m}m' : '${m}m');
    return 'Ep $episode in $when';
  }
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

/// A title on the user's list. Keeps a copy of the anime so the list works offline.
class WatchEntry {
  const WatchEntry({required this.anime, required this.status, required this.watched, required this.updatedAt});

  final Anime anime;
  final ListStatus status;
  final int watched;
  final DateTime updatedAt;

  int get animeId => anime.id;

  WatchEntry copyWith({Anime? anime, ListStatus? status, int? watched}) => WatchEntry(
        anime: anime ?? this.anime,
        status: status ?? this.status,
        watched: watched ?? this.watched,
        updatedAt: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'anime': anime.toJson(),
        'status': status.name,
        'watched': watched,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory WatchEntry.fromJson(Map<String, dynamic> j) => WatchEntry(
        anime: Anime.fromAniList(j['anime'] as Map<String, dynamic>),
        status: ListStatus.values.byName(j['status'] as String),
        watched: j['watched'] as int,
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

/// An official link from AniList, e.g. Crunchyroll or Netflix.
class ExternalLink {
  const ExternalLink({required this.site, required this.url, this.type, this.language, this.color, this.icon});

  final String site;
  final String url;

  /// `STREAMING`, `INFO` or `SOCIAL`.
  final String? type;
  final String? language;
  final Color? color;
  final String? icon;
}

/// An episode on an official streaming service, as listed by AniList.
class StreamingEpisode {
  const StreamingEpisode({required this.title, required this.url, this.site, this.thumbnail});

  /// Usually "Episode 3 - Title".
  final String title;
  final String url;
  final String? site;
  final String? thumbnail;

  static final _number = RegExp(r'^(?:Episode|Ep\.?)\s*(\d+)', caseSensitive: false);

  int? get number => int.tryParse(_number.firstMatch(title)?.group(1) ?? '');

  /// The title without the "Episode 3 - " prefix, if there is one.
  String? get name {
    final m = RegExp(r'^(?:Episode|Ep\.?)\s*\d+\s*[-–:]\s*(.+)$', caseSensitive: false).firstMatch(title);
    return m?.group(1)?.trim();
  }
}

enum FileState { matched, unmatched, missing }

/// A video the user added: a file on the phone (`content://`) or a stream URL they entered.
class LibraryFile {
  const LibraryFile({
    required this.id,
    required this.uri,
    required this.fileName,
    required this.state,
    required this.addedAt,
    this.sizeBytes,
    this.anime,
    this.episode,
    this.suggestedAnime,
    this.suggestedEpisode,
  });

  final String id;

  /// `content://` for files picked on the phone, `http(s)://` for streams.
  final String uri;
  final String fileName;
  final int? sizeBytes;
  final FileState state;
  final DateTime addedAt;

  /// The title it is matched to (a saved copy, so the Library works offline).
  final Anime? anime;
  final int? episode;
  final Anime? suggestedAnime;
  final int? suggestedEpisode;

  int? get animeId => anime?.id;
  bool get isStream => uri.startsWith('http://') || uri.startsWith('https://');

  /// A page on a streaming site (Crunchyroll, Bilibili, …) watched in the in-app browser,
  /// rather than a video Kairo plays itself. Episode 0 means the show's main page.
  bool get isWebLink => id.startsWith('web:');
  bool get playable => state == FileState.matched && anime != null && episode != null && !isWebLink;

  String get sizeLabel {
    if (isStream) return Uri.tryParse(uri)?.host ?? 'Stream';
    final b = sizeBytes;
    if (b == null) return '';
    if (b >= 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(1)} GB';
    if (b >= 1 << 20) return '${(b / (1 << 20)).round()} MB';
    return '${(b / 1024).round()} KB';
  }

  LibraryFile copyWith({
    String? uri,
    String? fileName,
    int? sizeBytes,
    FileState? state,
    Anime? anime,
    int? episode,
    Anime? suggestedAnime,
    int? suggestedEpisode,
    bool clearSuggestion = false,
  }) =>
      LibraryFile(
        id: id,
        uri: uri ?? this.uri,
        fileName: fileName ?? this.fileName,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        state: state ?? this.state,
        addedAt: addedAt,
        anime: anime ?? this.anime,
        episode: episode ?? this.episode,
        suggestedAnime: clearSuggestion ? null : (suggestedAnime ?? this.suggestedAnime),
        suggestedEpisode: clearSuggestion ? null : (suggestedEpisode ?? this.suggestedEpisode),
      );

  LibraryFile matchTo(Anime anime, int episode) =>
      copyWith(anime: anime, episode: episode, state: FileState.matched, clearSuggestion: true);
}

/// Where playback stopped in an episode.
class PlaybackProgress {
  const PlaybackProgress({
    required this.animeId,
    required this.episode,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });

  final int animeId;
  final int episode;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;

  double get fraction => duration.inMilliseconds == 0 ? 0 : position.inMilliseconds / duration.inMilliseconds;
  Duration get remaining => duration - position;

  /// Counted as watched from 90% on (credits are usually the last 10%).
  bool get finished => fraction >= 0.9;
}
