import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'anilist.dart';
import 'models.dart';
import 'providers.dart';

/// The AniList API client registered for Kairo (anilist.co/settings/developer, redirect `kairo://auth`).
/// Public by design: the implicit grant used here has no client secret.
const aniListClientId = String.fromEnvironment('ANILIST_CLIENT_ID', defaultValue: '');

const _statusToAniList = {
  ListStatus.watching: 'CURRENT',
  ListStatus.planned: 'PLANNING',
  ListStatus.completed: 'COMPLETED',
  ListStatus.paused: 'PAUSED',
  ListStatus.dropped: 'DROPPED',
};

ListStatus listStatusFromAniList(String s) => switch (s) {
      'CURRENT' || 'REPEATING' => ListStatus.watching,
      'PLANNING' => ListStatus.planned,
      'COMPLETED' => ListStatus.completed,
      'PAUSED' => ListStatus.paused,
      _ => ListStatus.dropped,
    };

/// Where the sign-in token lives. The real one is the Android keystore.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String? token);
}

class SecureTokenStore implements TokenStore {
  static const _key = 'anilist.token';
  final _storage = const FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String? token) => token == null ? _storage.delete(key: _key) : _storage.write(key: _key, value: token);
}

class MemoryTokenStore implements TokenStore {
  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String? token) async => this.token = token;
}

/// Opens the AniList sign-in page and returns the URL it redirected back to.
typedef AuthLauncher = Future<String> Function(String url);

Future<String> _webAuth(String url) => FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: 'kairo');

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());
final authLauncherProvider = Provider<AuthLauncher>((ref) => _webAuth);

class SyncState {
  const SyncState({this.user, this.syncing = false, this.lastSync, this.error});

  final AniListUser? user;
  final bool syncing;
  final DateTime? lastSync;
  final String? error;

  bool get signedIn => user != null;

  SyncState copyWith({AniListUser? user, bool? syncing, DateTime? lastSync, String? error, bool clearError = false}) =>
      SyncState(
        user: user ?? this.user,
        syncing: syncing ?? this.syncing,
        lastSync: lastSync ?? this.lastSync,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Keeps the watchlist and the user's AniList list in step.
///
/// - Signing in merges both lists: for a title on both, the most recently changed side wins.
/// - Afterwards every local change is pushed to AniList. Changes made offline are queued and sent on the next sync.
/// - A title removed on one side is removed on the other.
class AniListSync extends Notifier<SyncState> {
  static const _userKey = 'anilist.user';
  static const _lastSyncKey = 'anilist.lastSync';
  static const _knownKey = 'anilist.knownIds';
  static const _pendingKey = 'anilist.pending';
  static const _pendingDeleteKey = 'anilist.pendingDeletes';

  bool _applyingRemote = false;
  Timer? _flushTimer;

  @override
  SyncState build() {
    final prefs = ref.watch(prefsProvider);
    ref.listen(watchlistProvider, _onLocalChange);
    ref.onDispose(() => _flushTimer?.cancel());
    final user = prefs.getString(_userKey);
    final last = prefs.getInt(_lastSyncKey);
    return SyncState(
      user: user == null ? null : AniListUser.fromJson(jsonDecode(user) as Map<String, dynamic>),
      lastSync: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
    );
  }

  AniListClient get _client => ref.read(aniListProvider);

  Set<int> _ids(String key) => {for (final s in ref.read(prefsProvider).getStringList(key) ?? const <String>[]) int.parse(s)};
  void _setIds(String key, Set<int> ids) => ref.read(prefsProvider).setStringList(key, [for (final i in ids) '$i']);

  Future<void> signIn() async {
    if (aniListClientId.isEmpty) {
      state = state.copyWith(error: "AniList sign-in isn't set up in this build yet.");
      return;
    }
    state = state.copyWith(syncing: true, clearError: true);
    try {
      final callback = await ref.read(authLauncherProvider)(
        'https://anilist.co/api/v2/oauth/authorize?client_id=$aniListClientId&response_type=token',
      );
      // The token comes back in the fragment: kairo://auth#access_token=...&token_type=Bearer&expires_in=...
      final fragment = Uri.splitQueryString(Uri.parse(callback).fragment);
      final token = fragment['access_token'];
      if (token == null || token.isEmpty) throw const AniListException('AniList did not return a sign-in.');
      await ref.read(tokenStoreProvider).write(token);
      final user = await _client.viewer(token);
      await ref.read(prefsProvider).setString(_userKey, jsonEncode(user.toJson()));
      state = SyncState(user: user);
      await syncNow();
    } catch (e) {
      // Closing the sign-in page throws PlatformException(CANCELED): not an error worth showing.
      final cancelled = e is PlatformException && e.code == 'CANCELED';
      state = state.copyWith(syncing: false, error: cancelled ? null : '$e');
    }
  }

  Future<void> signOut() async {
    _flushTimer?.cancel();
    await ref.read(tokenStoreProvider).write(null);
    final prefs = ref.read(prefsProvider);
    for (final k in [_userKey, _lastSyncKey, _knownKey, _pendingKey, _pendingDeleteKey]) {
      await prefs.remove(k);
    }
    // The list stays on the phone; only the link to AniList is removed.
    state = const SyncState();
  }

  /// Pulls the AniList list, merges it with the phone's list, then pushes local changes.
  Future<void> syncNow() async {
    final user = state.user;
    final token = await ref.read(tokenStoreProvider).read();
    if (user == null || token == null) return;
    state = state.copyWith(syncing: true, clearError: true);
    try {
      final remote = {for (final r in await _client.animeList(token, user.id)) r.anime.id: r};
      final local = ref.read(watchlistProvider);
      final known = _ids(_knownKey);
      final pending = _ids(_pendingKey);
      final pendingDeletes = _ids(_pendingDeleteKey);

      final merged = {...local};
      final toPush = {...pending};
      for (final r in remote.values) {
        if (pendingDeletes.contains(r.anime.id)) continue;
        final l = local[r.anime.id];
        final remoteEntry = WatchEntry(
          anime: r.anime,
          status: listStatusFromAniList(r.status),
          watched: r.progress,
          updatedAt: r.updatedAt,
        );
        if (l == null) {
          merged[r.anime.id] = remoteEntry;
        } else if (!pending.contains(r.anime.id) && r.updatedAt.isAfter(l.updatedAt)) {
          merged[r.anime.id] = remoteEntry;
        } else if (_statusToAniList[l.status] != r.status || l.watched != r.progress) {
          toPush.add(r.anime.id);
        }
      }
      for (final id in local.keys.where((id) => !remote.containsKey(id))) {
        if (known.contains(id) && !pending.contains(id)) {
          merged.remove(id); // Removed on AniList since the last sync.
        } else {
          toPush.add(id);
        }
      }

      _applyingRemote = true;
      try {
        ref.read(watchlistProvider.notifier).replaceAll(merged);
      } finally {
        _applyingRemote = false;
      }

      for (final id in toPush) {
        final e = merged[id];
        if (e != null) await _client.saveEntry(token, animeId: id, status: _statusToAniList[e.status]!, progress: e.watched);
      }
      for (final id in pendingDeletes) {
        await _client.deleteEntry(token, userId: user.id, animeId: id);
      }

      _setIds(_knownKey, merged.keys.toSet());
      _setIds(_pendingKey, {});
      _setIds(_pendingDeleteKey, {});
      final now = DateTime.now();
      await ref.read(prefsProvider).setInt(_lastSyncKey, now.millisecondsSinceEpoch);
      state = state.copyWith(syncing: false, lastSync: now);
    } on AniListAuthException catch (e) {
      await signOut();
      state = SyncState(error: e.message);
    } catch (e) {
      state = state.copyWith(syncing: false, error: '$e');
    }
  }

  /// Queues local edits for AniList and sends them shortly after.
  void _onLocalChange(Map<int, WatchEntry>? previous, Map<int, WatchEntry> next) {
    if (_applyingRemote || state.user == null || previous == null) return;
    final pending = _ids(_pendingKey);
    final deletes = _ids(_pendingDeleteKey);
    for (final e in next.values) {
      final before = previous[e.animeId];
      if (before == null || before.status != e.status || before.watched != e.watched) {
        pending.add(e.animeId);
        deletes.remove(e.animeId);
      }
    }
    for (final id in previous.keys.where((id) => !next.containsKey(id))) {
      deletes.add(id);
      pending.remove(id);
    }
    _setIds(_pendingKey, pending);
    _setIds(_pendingDeleteKey, deletes);
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(seconds: 2), () => flush().ignore());
  }

  /// Sends queued edits. On failure they stay queued for the next try.
  Future<void> flush() async {
    final user = state.user;
    final token = await ref.read(tokenStoreProvider).read();
    if (user == null || token == null) return;
    final pending = _ids(_pendingKey);
    final deletes = _ids(_pendingDeleteKey);
    final known = _ids(_knownKey);
    try {
      for (final id in [...pending]) {
        final e = ref.read(watchlistProvider)[id];
        if (e != null) await _client.saveEntry(token, animeId: id, status: _statusToAniList[e.status]!, progress: e.watched);
        pending.remove(id);
        known.add(id);
      }
      for (final id in [...deletes]) {
        await _client.deleteEntry(token, userId: user.id, animeId: id);
        deletes.remove(id);
        known.remove(id);
      }
    } on AniListAuthException catch (e) {
      await signOut();
      state = SyncState(error: e.message);
      return;
    } catch (e) {
      debugPrint('AniList sync deferred: $e');
    } finally {
      if (state.user != null) {
        _setIds(_pendingKey, pending);
        _setIds(_pendingDeleteKey, deletes);
        _setIds(_knownKey, known);
      }
    }
  }
}


final aniListSyncProvider = NotifierProvider<AniListSync, SyncState>(AniListSync.new);
