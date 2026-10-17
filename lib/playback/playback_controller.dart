import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/settings.dart';
import '../data/watch_links.dart';

enum PlaybackKind {
  /// Kairo's own player (media_kit): imported files and direct streams.
  native,

  /// A streaming site's page in the built-in browser.
  web,
}

/// What's playing now. The player lives above every screen, so it keeps playing while the user
/// browses (mini player) and only stops when they close it.
class PlaybackSession {
  const PlaybackSession({
    required this.kind,
    required this.uri,
    required this.title,
    required this.subtitle,
    this.anime,
    this.episode,
    this.expanded = true,
    this.error,
  });

  final PlaybackKind kind;
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
        kind: kind,
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
  WebViewController? _web;
  final _subscriptions = <StreamSubscription<Object?>>[];
  Timer? _saveTimer;
  bool _countedWatched = false;

  /// Whether the web page's video is playing, as reported by the page (best effort).
  final webPlaying = ValueNotifier<bool>(false);

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
  WebViewController? get web => _web;

  // ---- Opening ----

  /// Plays an imported file or stream for an episode. Returns false if there's nothing to play.
  Future<bool> playEpisode(int animeId, int episode) async {
    final file = ref.read(libraryProvider.notifier).fileFor(animeId, episode);
    if (file == null) return false;
    await _end();
    final anime = ref.read(animeProvider(animeId)) ?? file.anime;
    state = PlaybackSession(
      kind: PlaybackKind.native,
      uri: file.uri,
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
    await player.open(Media(file.uri, start: resumeAt));
    return true;
  }

  /// Opens a streaming site's page in the built-in browser.
  Future<void> openWeb(String url, {int? animeId, int? episode}) async {
    await _end();
    final anime = animeId == null ? null : ref.read(animeProvider(animeId));
    final ep = episode == 0 ? null : episode;
    state = PlaybackSession(
      kind: PlaybackKind.web,
      uri: url,
      title: anime?.shortTitle ?? linkLabel(url),
      subtitle: [linkLabel(url), if (ep != null) 'Episode $ep'].join(' · '),
      anime: anime,
      episode: ep,
    );
    _enterFullscreenMode();
    _web = _createWebView(url);
  }

  WebViewController _createWebView(String url) {
    final web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(KairoColors.background)
      ..addJavaScriptChannel('KairoMedia', onMessageReceived: (m) => webPlaying.value = m.message == 'playing')
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) async {
          // Report play/pause of the page's videos, so the notification shows the right button.
          await _web?.runJavaScript(_hookVideosJs);
          final title = await _web?.getTitle();
          if (title != null && title.isNotEmpty && state?.anime == null) state = state?.copyWith(title: title);
        },
        onNavigationRequest: (r) {
          final uri = Uri.tryParse(r.url);
          if (uri != null && !{'http', 'https', 'about', 'blob', 'data'}.contains(uri.scheme)) {
            launchUrl(uri, mode: LaunchMode.externalApplication).ignore();
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ));
    if (web.platform case final AndroidWebViewController android) {
      android.setMediaPlaybackRequiresUserGesture(false);
      // Allow DRM-protected video (Crunchyroll and others); nothing else (no camera or microphone).
      android.setOnPlatformPermissionRequest((request) {
        final onlyDrm = request.types.every((t) => t == AndroidWebViewPermissionResourceType.protectedMediaId);
        onlyDrm ? request.grant() : request.deny();
      });
      final cookies = WebViewCookieManager();
      if (cookies.platform case final AndroidWebViewCookieManager androidCookies) {
        androidCookies.setAcceptThirdPartyCookies(android, true);
      }
    }
    web.loadRequest(Uri.parse(url));
    return web;
  }

  static const _hookVideosJs = '''
    (function () {
      if (window.__kairoHooked) return;
      window.__kairoHooked = true;
      function hook(v) {
        if (v.__kairo) return;
        v.__kairo = true;
        v.addEventListener('play', function () { KairoMedia.postMessage('playing'); });
        v.addEventListener('pause', function () { KairoMedia.postMessage('paused'); });
        if (!v.paused) KairoMedia.postMessage('playing');
      }
      setInterval(function () { document.querySelectorAll('video').forEach(hook); }, 1000);
    })();
  ''';

  // ---- Controls (also used by the notification) ----

  Future<void> playPause() async {
    switch (state?.kind) {
      case PlaybackKind.native:
        await player.playOrPause();
      case PlaybackKind.web:
        await _web?.runJavaScript(
          "document.querySelectorAll('video').forEach(function (v) { v.paused ? v.play() : v.pause(); });",
        );
      case null:
        break;
    }
  }

  Future<void> pause() async {
    if (state?.kind == PlaybackKind.native) {
      await player.pause();
    } else {
      await _web?.runJavaScript("document.querySelectorAll('video').forEach(function (v) { v.pause(); });");
    }
  }

  Future<void> play() async {
    if (state?.kind == PlaybackKind.native) {
      await player.play();
    } else {
      await _web?.runJavaScript("document.querySelectorAll('video').forEach(function (v) { v.play(); });");
    }
  }

  Future<void> seekBy(Duration offset) async {
    if (state?.kind == PlaybackKind.native) {
      final duration = player.state.duration;
      var next = player.state.position + offset;
      if (next < Duration.zero) next = Duration.zero;
      if (duration > Duration.zero && next > duration) next = duration;
      await player.seek(next);
    } else {
      await _web?.runJavaScript(
        "document.querySelectorAll('video').forEach(function (v) { v.currentTime += ${offset.inSeconds}; });",
      );
    }
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

  LibraryFile? get nextFile {
    final s = state;
    if (s == null || s.kind != PlaybackKind.native || s.anime == null || s.episode == null) return null;
    return ref.read(libraryProvider.notifier).fileFor(s.anime!.id, s.episode! + 1);
  }

  Future<void> playNext() async {
    final s = state;
    if (s?.anime == null || nextFile == null) return;
    final expanded = s!.expanded;
    await playEpisode(s.anime!.id, s.episode! + 1);
    if (!expanded) minimize();
  }

  /// Marks the current episode watched (the ✓ button on web pages).
  void markWatched() {
    final s = state;
    if (s?.anime == null || s?.episode == null) return;
    ref.read(watchlistProvider.notifier).setWatched(s!.anime!, s.episode!);
  }

  // ---- Internals ----

  Future<void> _end() async {
    _saveProgress();
    _saveTimer?.cancel();
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    if (state?.kind == PlaybackKind.native) await _player?.stop();
    if (_web != null) {
      // A WebView keeps playing after its widget is gone, so stop the page explicitly.
      await _web!.runJavaScript("document.querySelectorAll('video,audio').forEach(function (m) { m.pause(); });").catchError((_) {});
      await _web!.loadRequest(Uri.parse('about:blank')).catchError((_) {});
      _web = null;
    }
    webPlaying.value = false;
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
    if (s == null || s.kind != PlaybackKind.native || s.anime == null || s.episode == null || _player == null) return;
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
    if (ref.read(settingsProvider).autoNext && nextFile != null) playNext();
  }
}

final playbackProvider = NotifierProvider<PlaybackController, PlaybackSession?>(PlaybackController.new);
