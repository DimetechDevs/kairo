import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'providers.dart';

/// One playable copy of an episode from the stream API.
class StreamSource {
  const StreamSource({required this.url, this.quality, this.headers = const {}});

  final String url;

  /// As the API labels it, e.g. "1080p" or "auto".
  final String? quality;

  /// Sent with every request for the video, e.g. a Referer or a signed token.
  final Map<String, String> headers;

  /// Height in pixels read from [quality]; "auto" and adaptive streams rank highest.
  int get rank {
    final q = quality?.toLowerCase() ?? '';
    if (q.isEmpty || q == 'auto' || q == 'default') return 1 << 20;
    return int.tryParse(RegExp(r'\d+').firstMatch(q)?.group(0) ?? '') ?? 0;
  }
}

class SubtitleSource {
  const SubtitleSource({required this.url, required this.language, this.label});

  final String url;

  /// A language code such as "en".
  final String language;
  final String? label;
}

class EpisodeStreams {
  const EpisodeStreams({required this.sources, this.subtitles = const []});

  final List<StreamSource> sources;
  final List<SubtitleSource> subtitles;

  /// The source to play first: adaptive, else the highest quality.
  StreamSource get best => ([...sources]..sort((a, b) => b.rank.compareTo(a.rank))).first;

  /// Reads the API's answer. This is the one place to change if the API's JSON looks different.
  factory EpisodeStreams.fromJson(Map<String, dynamic> j) {
    Map<String, String> headers(Object? h) =>
        {for (final e in (h as Map? ?? const {}).entries) '${e.key}': '${e.value}'};
    return EpisodeStreams(
      sources: [
        for (final s in j['sources'] as List? ?? const [])
          if (s is Map && s['url'] is String)
            StreamSource(url: s['url'] as String, quality: s['quality'] as String?, headers: headers(s['headers'] ?? j['headers'])),
      ],
      subtitles: [
        for (final s in j['subtitles'] as List? ?? const [])
          if (s is Map && s['url'] is String)
            SubtitleSource(
              url: s['url'] as String,
              language: (s['language'] ?? s['lang'] ?? 'und') as String,
              label: s['label'] as String?,
            ),
      ],
    );
  }
}

class StreamApiException implements Exception {
  const StreamApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The user's own video API. Kairo asks it for an episode by AniList ID:
///
///   GET {baseUrl}/anime/{anilistId}/episodes/{episode}
///   Authorization: Bearer {apiKey}      (only when a key is set)
///
/// and expects `{"sources": [{"url", "quality", "headers"}], "subtitles": [{"url", "language", "label"}]}`.
/// A 404 means the API doesn't have that episode.
class StreamApiClient {
  StreamApiClient({required this.baseUrl, this.apiKey, http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String? apiKey;
  final http.Client _http;

  Uri _episodeUri(int anilistId, int episode) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$base/anime/$anilistId/episodes/$episode');
  }

  /// The streams for one episode, or null when the API doesn't have it.
  Future<EpisodeStreams?> episode(int anilistId, int episode) async {
    final http.Response res;
    try {
      res = await _http.get(_episodeUri(anilistId, episode), headers: {
        'Accept': 'application/json',
        if (apiKey case final key? when key.isNotEmpty) 'Authorization': 'Bearer $key',
      }).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const StreamApiException('Your stream API took too long to answer.');
    } catch (_) {
      throw const StreamApiException("Couldn't reach your stream API. Check the address and your connection.");
    }
    if (res.statusCode == 404) return null;
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const StreamApiException('Your stream API refused the key. Check it in Profile › Stream API.');
    }
    if (res.statusCode != 200) throw StreamApiException('Your stream API answered with an error (HTTP ${res.statusCode}).');
    try {
      final streams = EpisodeStreams.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
      return streams.sources.isEmpty ? null : streams;
    } catch (_) {
      throw const StreamApiException("Your stream API's answer isn't in the format Kairo expects.");
    }
  }
}

/// Where the API is and its key. The address is saved in preferences, the key in the Android keystore.
class StreamApiConfig {
  const StreamApiConfig({this.baseUrl = '', this.apiKey});

  final String baseUrl;
  final String? apiKey;

  bool get isSet => baseUrl.isNotEmpty;
}

abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class SecureSecretStore implements SecretStore {
  final _storage = const FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String? value) =>
      value == null || value.isEmpty ? _storage.delete(key: key) : _storage.write(key: key, value: value);
}

class MemorySecretStore implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async =>
      value == null || value.isEmpty ? values.remove(key) : values[key] = value;
}

final secretStoreProvider = Provider<SecretStore>((ref) => SecureSecretStore());

class StreamApiConfigNotifier extends AsyncNotifier<StreamApiConfig> {
  static const _urlKey = 'streamApi.url';
  static const _secretKey = 'streamApi.key';

  @override
  Future<StreamApiConfig> build() async => StreamApiConfig(
        baseUrl: ref.watch(prefsProvider).getString(_urlKey) ?? '',
        apiKey: await ref.watch(secretStoreProvider).read(_secretKey),
      );

  Future<void> save({required String baseUrl, String? apiKey}) async {
    final url = baseUrl.trim();
    await ref.read(prefsProvider).setString(_urlKey, url);
    await ref.read(secretStoreProvider).write(_secretKey, apiKey?.trim());
    state = AsyncData(StreamApiConfig(baseUrl: url, apiKey: apiKey?.trim()));
  }
}

final streamApiConfigProvider =
    AsyncNotifierProvider<StreamApiConfigNotifier, StreamApiConfig>(StreamApiConfigNotifier.new);

/// Overridden in tests with a fake HTTP client.
final streamApiHttpProvider = Provider<http.Client>((ref) => http.Client());

/// The client for the saved API, or null when none is set up.
final streamApiProvider = FutureProvider<StreamApiClient?>((ref) async {
  final config = await ref.watch(streamApiConfigProvider.future);
  if (!config.isSet) return null;
  return StreamApiClient(baseUrl: config.baseUrl, apiKey: config.apiKey, httpClient: ref.watch(streamApiHttpProvider));
});
