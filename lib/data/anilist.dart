import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Fields every poster and card needs.
const _cardFields = '''
  id
  title { english romaji native }
  coverImage { extraLarge color }
  bannerImage
  format
  status
  episodes
  duration
  season
  seasonYear
  averageScore
  popularity
  genres
  nextAiringEpisode { episode airingAt }
''';

/// The genres AniList uses, in the order Discover shows them.
const aniListGenres = [
  'Action', 'Adventure', 'Comedy', 'Drama', 'Fantasy', 'Romance', 'Sci-Fi', 'Slice of Life', //
  'Mystery', 'Supernatural', 'Sports', 'Psychological', 'Horror', 'Mecha', 'Music', 'Thriller',
];

enum BrowseSort {
  trending('TRENDING_DESC', 'Trending'),
  popular('POPULARITY_DESC', 'Popular'),
  topRated('SCORE_DESC', 'Top rated'),
  newest('START_DATE_DESC', 'Newest');

  const BrowseSort(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

/// The anime season (WINTER, SPRING, SUMMER, FALL) and its year for a date.
({String season, int year}) seasonOf(DateTime date) => switch (date.month) {
      12 => (season: 'WINTER', year: date.year + 1),
      1 || 2 => (season: 'WINTER', year: date.year),
      3 || 4 || 5 => (season: 'SPRING', year: date.year),
      6 || 7 || 8 => (season: 'SUMMER', year: date.year),
      _ => (season: 'FALL', year: date.year),
    };

class ResultPage<T> {
  const ResultPage(this.items, {required this.page, required this.hasNext});

  final List<T> items;
  final int page;
  final bool hasNext;
}

class HomeFeed {
  const HomeFeed({required this.trending, required this.season, required this.popular, required this.topRated});

  final List<Anime> trending;
  final List<Anime> season;
  final List<Anime> popular;
  final List<Anime> topRated;
}

/// The sign-in expired or was revoked on AniList.
class AniListAuthException extends AniListException {
  const AniListAuthException() : super('Your AniList sign-in has expired. Sign in again to keep syncing.');
}

class AniListException implements Exception {
  const AniListException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Talks to the public AniList GraphQL API (no account needed).
///
/// Home and details responses are also kept on the phone, so the app still shows
/// the last thing it loaded when there's no connection.
class AniListClient {
  AniListClient({http.Client? httpClient, this.prefs}) : _http = httpClient ?? http.Client();

  static final _endpoint = Uri.parse('https://graphql.anilist.co');
  static const _cachePrefix = 'anilist_cache:';

  final http.Client _http;
  final SharedPreferences? prefs;

  Future<Map<String, dynamic>> _query(
    String query,
    Map<String, dynamic> variables, {
    String? cacheKey,
    String? token,
  }) async {
    try {
      final res = await _http
          .post(
            _endpoint,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'query': query, 'variables': variables}),
          )
          .timeout(const Duration(seconds: 15));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 429) throw const AniListException('AniList is busy right now. Try again in a minute.');
      if (res.statusCode == 401 || res.statusCode == 400 && token != null && '${body['errors']}'.contains('Invalid token')) {
        throw const AniListAuthException();
      }
      if (res.statusCode != 200 || body['errors'] != null) {
        final errors = body['errors'] as List?;
        final msg = errors?.isNotEmpty == true ? (errors!.first as Map)['message'] : 'HTTP ${res.statusCode}';
        throw AniListException('AniList error: $msg');
      }
      final data = body['data'] as Map<String, dynamic>;
      if (cacheKey != null) await prefs?.setString('$_cachePrefix$cacheKey', jsonEncode(data));
      return data;
    } catch (e) {
      final cached = cacheKey == null ? null : prefs?.getString('$_cachePrefix$cacheKey');
      if (cached != null) return jsonDecode(cached) as Map<String, dynamic>;
      if (e is AniListException) rethrow;
      if (e is TimeoutException) throw const AniListException('AniList took too long to answer. Check your connection.');
      throw const AniListException("Couldn't reach AniList. Check your connection and try again.");
    }
  }

  static List<Anime> _media(Map<String, dynamic>? page) =>
      [for (final m in page?['media'] as List? ?? const []) Anime.fromAniList(m as Map<String, dynamic>)];

  /// Everything the Home tab shows, in one request.
  Future<HomeFeed> home({DateTime? now}) async {
    final s = seasonOf(now ?? DateTime.now());
    final data = await _query(
      '''
      query (\$season: MediaSeason, \$year: Int) {
        trending: Page(perPage: 12) { media(type: ANIME, sort: TRENDING_DESC, isAdult: false) { $_cardFields } }
        season: Page(perPage: 12) {
          media(type: ANIME, season: \$season, seasonYear: \$year, sort: POPULARITY_DESC, isAdult: false) { $_cardFields }
        }
        popular: Page(perPage: 12) { media(type: ANIME, sort: POPULARITY_DESC, isAdult: false) { $_cardFields } }
        topRated: Page(perPage: 12) { media(type: ANIME, sort: SCORE_DESC, isAdult: false) { $_cardFields } }
      }
      ''',
      {'season': s.season, 'year': s.year},
      cacheKey: 'home',
    );
    return HomeFeed(
      trending: _media(data['trending'] as Map<String, dynamic>?),
      season: _media(data['season'] as Map<String, dynamic>?),
      popular: _media(data['popular'] as Map<String, dynamic>?),
      topRated: _media(data['topRated'] as Map<String, dynamic>?),
    );
  }

  /// One page of search or browse results. Null arguments are ignored by AniList.
  Future<ResultPage<Anime>> browse({
    int page = 1,
    int perPage = 24,
    BrowseSort sort = BrowseSort.trending,
    String? search,
    String? genre,
    String? format,
    String? status,
    String? season,
    int? seasonYear,
  }) async {
    final hasSearch = search != null && search.trim().isNotEmpty;
    final data = await _query(
      '''
      query (\$page: Int, \$perPage: Int, \$sort: [MediaSort], \$search: String, \$genre: String,
             \$format: MediaFormat, \$status: MediaStatus, \$season: MediaSeason, \$seasonYear: Int) {
        Page(page: \$page, perPage: \$perPage) {
          pageInfo { hasNextPage }
          media(type: ANIME, isAdult: false, sort: \$sort, search: \$search, genre: \$genre,
                format: \$format, status: \$status, season: \$season, seasonYear: \$seasonYear) { $_cardFields }
        }
      }
      ''',
      {
        'page': page,
        'perPage': perPage,
        'sort': hasSearch ? ['SEARCH_MATCH', sort.apiValue] : [sort.apiValue],
        'search': hasSearch ? search.trim() : null,
        'genre': genre,
        'format': format,
        'status': status,
        'season': season,
        'seasonYear': seasonYear,
      },
    );
    final p = data['Page'] as Map<String, dynamic>;
    return ResultPage(_media(p), page: page, hasNext: (p['pageInfo'] as Map)['hasNextPage'] as bool? ?? false);
  }

  /// Episodes that haven't aired yet for these titles, soonest first (a few weeks ahead).
  Future<List<({int animeId, int episode, DateTime at})>> upcomingEpisodes(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final data = await _query(
      '''
      query (\$ids: [Int]) {
        Page(perPage: 50) {
          airingSchedules(mediaId_in: \$ids, notYetAired: true, sort: TIME) { mediaId episode airingAt }
        }
      }
      ''',
      {'ids': ids},
    );
    return [
      for (final s in (data['Page'] as Map<String, dynamic>)['airingSchedules'] as List? ?? const [])
        (
          animeId: (s as Map<String, dynamic>)['mediaId'] as int,
          episode: s['episode'] as int,
          at: DateTime.fromMillisecondsSinceEpoch((s['airingAt'] as int) * 1000),
        ),
    ];
  }

  /// Full details for one title, including studios, synopsis and recommendations.
  Future<Anime> details(int id) async {
    final data = await _query(
      '''
      query (\$id: Int) {
        Media(id: \$id, type: ANIME) {
          $_cardFields
          description(asHtml: false)
          startDate { year }
          studios(isMain: true) { nodes { name } }
          externalLinks { site url type language color icon }
          streamingEpisodes { title thumbnail url site }
          recommendations(perPage: 12, sort: RATING_DESC) {
            nodes { mediaRecommendation { $_cardFields } }
          }
        }
      }
      ''',
      {'id': id},
      cacheKey: 'media:$id',
    );
    final media = data['Media'] as Map<String, dynamic>?;
    if (media == null) throw const AniListException('This title is no longer on AniList.');
    return Anime.fromAniList(media);
  }

  // ---- Signed-in requests (the user's own AniList list). ----

  /// The signed-in user.
  Future<AniListUser> viewer(String token) async {
    final data = await _query('query { Viewer { id name avatar { large } } }', const {}, token: token);
    final v = data['Viewer'] as Map<String, dynamic>;
    return AniListUser(id: v['id'] as int, name: v['name'] as String, avatarUrl: (v['avatar'] as Map?)?['large'] as String?);
  }

  /// Every anime on the user's AniList list.
  Future<List<RemoteListEntry>> animeList(String token, int userId) async {
    final data = await _query(
      '''
      query (\$userId: Int) {
        MediaListCollection(userId: \$userId, type: ANIME) {
          lists { entries { id status progress updatedAt media { $_cardFields } } }
        }
      }
      ''',
      {'userId': userId},
      token: token,
    );
    final lists = (data['MediaListCollection'] as Map<String, dynamic>?)?['lists'] as List? ?? const [];
    final byMedia = <int, RemoteListEntry>{};
    for (final l in lists) {
      for (final e in (l as Map<String, dynamic>)['entries'] as List? ?? const []) {
        final m = e as Map<String, dynamic>;
        final entry = RemoteListEntry(
          entryId: m['id'] as int,
          anime: Anime.fromAniList(m['media'] as Map<String, dynamic>),
          status: m['status'] as String,
          progress: m['progress'] as int? ?? 0,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(((m['updatedAt'] as int?) ?? 0) * 1000),
        );
        // A title can appear in a custom list too; keep one.
        byMedia[entry.anime.id] = entry;
      }
    }
    return byMedia.values.toList();
  }

  /// Creates or updates the user's entry for a title.
  Future<void> saveEntry(String token, {required int animeId, required String status, required int progress}) => _query(
        r'''
        mutation ($mediaId: Int, $status: MediaListStatus, $progress: Int) {
          SaveMediaListEntry(mediaId: $mediaId, status: $status, progress: $progress) { id }
        }
        ''',
        {'mediaId': animeId, 'status': status, 'progress': progress},
        token: token,
      );

  /// Removes a title from the user's list (no-op if it isn't there).
  Future<void> deleteEntry(String token, {required int userId, required int animeId}) async {
    final Map<String, dynamic> found;
    try {
      found = await _query(
        r'query ($userId: Int, $mediaId: Int) { MediaList(userId: $userId, mediaId: $mediaId) { id } }',
        {'userId': userId, 'mediaId': animeId},
        token: token,
      );
    } on AniListAuthException {
      rethrow;
    } on AniListException {
      return; // "Not Found": already gone.
    }
    final id = (found['MediaList'] as Map<String, dynamic>?)?['id'] as int?;
    if (id == null) return;
    await _query(r'mutation ($id: Int) { DeleteMediaListEntry(id: $id) { deleted } }', {'id': id}, token: token);
  }
}

class AniListUser {
  const AniListUser({required this.id, required this.name, this.avatarUrl});

  final int id;
  final String name;
  final String? avatarUrl;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'avatarUrl': avatarUrl};

  factory AniListUser.fromJson(Map<String, dynamic> j) =>
      AniListUser(id: j['id'] as int, name: j['name'] as String, avatarUrl: j['avatarUrl'] as String?);
}

class RemoteListEntry {
  const RemoteListEntry({
    required this.entryId,
    required this.anime,
    required this.status,
    required this.progress,
    required this.updatedAt,
  });

  final int entryId;
  final Anime anime;

  /// AniList `MediaListStatus`, e.g. `CURRENT`.
  final String status;
  final int progress;
  final DateTime updatedAt;
}
