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

  Future<Map<String, dynamic>> _query(String query, Map<String, dynamic> variables, {String? cacheKey}) async {
    try {
      final res = await _http
          .post(
            _endpoint,
            headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({'query': query, 'variables': variables}),
          )
          .timeout(const Duration(seconds: 15));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 429) throw const AniListException('AniList is busy right now. Try again in a minute.');
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
}
