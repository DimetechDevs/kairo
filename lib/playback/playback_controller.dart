import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../data/models.dart';
import '../data/providers.dart';
import '../data/settings.dart';
import '../data/stream_api.dart';

/// What's playing now. The player lives above every screen, so it keeps playing while the user
/// browses (mini player) and only stops when they close it.
class PlaybackSession {
  const PlaybackSession({
    required this.uri,
    required this.title,
    required this.subtitle,
    this.anime,
    this.episode,
    this.expanded = true,
    this.error,
  });

  /// The stream being played, as the Kairo API gave it.
  final String uri;
  final String title;
  final String subtitle;
  final Anime? anime;

  /// The episode being watched; null for a show's main page.
  final int? episode;

  /// Full screen, or shrunk to the mini player.
  final bool expanded;
  final String? error;

  PlaybackSession copyWith({bool? expanded, String? error, String? title}) => PlaybackSession(
        uri: uri,
        title: title ?? this.title,
        subtitle: subtitle,
        anime: anime,
        episode: episode,
        expanded: expanded ?? this.expanded,
        error: error ?? this.error,
      );
}

class PlaybackController extends Notifier<PlaybackSession?> {
  static const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  Player? _player;
  VideoController? _video;
  final _subscriptions = <StreamSubscription<Object?>>[];
  Timer? _saveTimer;
  bool _countedWatched = false;

  /// Set when the user locks the orientation with the rotate button; null = follow the phone.
  final lockedOrientation = ValueNotifier<Orientation?>(null);

  @override
  PlaybackSession? build() {
    ref.onDispose(() {
      _saveTimer?.cancel();
      for (final s in _subscriptions) {
        s.cancel();
      }
      _player?.dispose();
    });
    return null;
  }

  Player get player => _player ??= Player();
  VideoController get video => _video ??= VideoController(player);

  // ---- Opening ----

  /// Plays an episode from the Kairo API. Returns why it couldn't, or null once it's playing.
  Future<String?> playEpisode(int animeId, int episode) async {
    final StreamApiClient? api;
    final EpisodeStreams? streams;
    try {
      api = await ref.read(streamApiProvider.future);
      if (api == null) return 'Set up your Kairo API in Profile to play episodes.';
      streams = await api.episode(animeId, episode);
    } on StreamApiException catch (e) {
      return e.message;
    }
    if (streams == null) return "Episode $episode isn't available yet.";

    await _end();
    final anime = ref.read(animeProvider(animeId));
    final source = streams.best;
    state = PlaybackSession(
      uri: source.url,
      title: anime?.shortTitle ?? 'Episode $episode',
      subtitle: 'Episode $episode',
      anime: anime,
      episode: episode,
    );
    _countedWatched = false;
    _enterFullscreenMode();

    _subscriptions.addAll([
      player.stream.playing.listen((p) {
        if (!p) _saveProgress();
      }),
      player.stream.completed.listen((done) {
        if (done) _onCompleted();
      }),
      player.stream.error.listen((e) => state = state?.copyWith(error: e)),
    ]);
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());

    final saved = ref.read(progressProvider)[(animeId, episode)];
    final resumeAt = saved != null && !saved.finished && saved.position > const Duration(seconds: 30) ? saved.position : null;
    await _applySettings();
    await player.open(Media(source.url, httpHeaders: source.headers, start: resumeAt));
    await _addSubtitles(streams.subtitles);
    return null;
  }

  /// Adds the API's subtitle files; the one in the preferred language is switched on.
  Future<void> _addSubtitles(List<SubtitleSource> subtitles) async {
    if (subtitles.isEmpty || player.platform is! NativePlayer) return;
    final native = player.platform! as NativePlayer;
    final want = ref.read(settingsProvider).subtitleLanguage;
    var chosen = false;
    for (final sub in subtitles) {
      final pick = !chosen && want != 'off' && sub.language.toLowerCase().startsWith(want);
      chosen |= pick;
      await native.command(['sub-add', sub.url, pick ? 'select' : 'auto', sub.label ?? sub.language, sub.language]);
    }
  }

  // ---- Controls (also used by the notification) ----

  Future<void> playPause() async {
    if (state != null) await player.playOrPause();
  }

  Future<void> pause() async {
    if (state != null) await player.pause();
  }

  Future<void> play() async {
    if (state != null) await player.play();
  }

  Future<void> seekBy(Duration offset) async {
    if (state == null) return;
    final duration = player.state.duration;
    var next = player.state.position + offset;
    if (next < Duration.zero) next = Duration.zero;
    if (duration > Duration.zero && next > duration) next = duration;
    await player.seek(next);
  }

  void minimize() {
    if (state == null || !state!.expanded) return;
    state = state!.copyWith(expanded: false);
    _leaveFullscreenMode();
  }

  void expand() {
    if (state == null || state!.expanded) return;
    state = state!.copyWith(expanded: true);
    _enterFullscreenMode();
  }

  /// Stops playback completely and removes the player.
  Future<void> close() async {
    await _end();
    state = null;
    _leaveFullscreenMode();
  }

  /// Turns the screen between portrait and landscape (and locks it there until the player closes).
  void rotate(Orientation current) {
    final next = current == Orientation.portrait ? Orientation.landscape : Orientation.portrait;
    lockedOrientation.value = next;
    SystemChrome.setPreferredOrientations(next == Orientation.landscape
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : [DeviceOrientation.portraitUp]);
  }

  /// Whether there's a later episode to go to (one that has aired, when AniList knows).
  bool get hasNext {
    final s = state;
    if (s?.anime == null || s?.episode == null) return false;
    final aired = s!.anime!.airedEpisodes;
    return aired == 0 || s.episode! < aired;
  }

  Future<void> playNext() async {
    final s = state;
    if (s?.anime == null || !hasNext) return;
    final expanded = s!.expanded;
    final error = await playEpisode(s.anime!.id, s.episode! + 1);
    if (error != null) {
      state = state?.copyWith(error: error);
    } else if (!expanded) {
      minimize();
    }
  }

  // ---- Internals ----

  Future<void> _end() async {
    _saveProgress();
    _saveTimer?.cancel();
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    await _player?.stop();
    lockedOrientation.value = null;
  }

  void _enterFullscreenMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Follow the phone's rotation unless the user locked it with the rotate button.
    SystemChrome.setPreferredOrientations(switch (lockedOrientation.value) {
      Orientation.landscape => [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
      Orientation.portrait => [DeviceOrientation.portraitUp],
      null => [],
    });
  }

  void _leaveFullscreenMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    // Give the rest of the app its normal orientation back once rotated upright.
    Future.delayed(const Duration(milliseconds: 600), () {
      if (state == null || !state!.expanded) SystemChrome.setPreferredOrientations([]);
    });
  }

  Future<void> _applySettings() async {
    final s = ref.read(settingsProvider);
    await player.setRate(speeds.contains(s.speed) ? s.speed : 1.0);
    if (player.platform case final NativePlayer native) {
      // mpv picks the first matching track; both 2- and 3-letter codes appear in files.
      const threeLetter = {'en': 'eng', 'es': 'spa', 'pt': 'por', 'fr': 'fre,fra', 'de': 'ger,deu', 'ja': 'jpn'};
      if (s.subtitleLanguage == 'off') {
        await native.setProperty('sid', 'no');
      } else {
        await native.setProperty('sid', 'auto');
        await native.setProperty('slang', '${s.subtitleLanguage},${threeLetter[s.subtitleLanguage]}');
      }
      if (s.audioLanguage != 'auto') {
        await native.setProperty('alang', '${s.audioLanguage},${threeLetter[s.audioLanguage]}');
      }
    }
  }

  void _saveProgress() {
    final s = state;
    if (s == null || s.anime == null || s.episode == null || _player == null) return;
    final position = player.state.position;
    final duration = player.state.duration;
    if (duration <= Duration.zero) return;
    ref.read(progressProvider.notifier).save(s.anime!.id, s.episode!, position, duration);

    // Count the episode as watched once, at the "count as watched" point from Settings.
    if (!_countedWatched && position.inMilliseconds >= duration.inMilliseconds * ref.read(settingsProvider).watchedAt) {
      _countedWatched = true;
      final watched = ref.read(watchlistProvider)[s.anime!.id]?.watched ?? 0;
      if (s.episode! > watched) ref.read(watchlistProvider.notifier).setWatched(s.anime!, s.episode!);
    }
  }

  void _onCompleted() {
    _saveProgress();
    if (ref.read(settingsProvider).autoNext && hasNext) playNext();
  }
}

final playbackProvider = NotifierProvider<PlaybackController, PlaybackSession?>(PlaybackController.new);
