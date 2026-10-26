import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'playback_controller.dart';

/// The media notification (and lock-screen / headset controls) for whatever Kairo is playing.
class KairoMediaHandler extends BaseAudioHandler with SeekHandler {
  KairoMediaHandler(this._container);

  final ProviderContainer _container;
  final _subscriptions = <StreamSubscription<Object?>>[];

  PlaybackController get _controller => _container.read(playbackProvider.notifier);

  /// Follows the player: shows the notification while something plays, removes it on close.
  void attach() {
    _container.listen<PlaybackSession?>(playbackProvider, (previous, next) {
      if (next == null) {
        _clear();
        return;
      }
      if (previous?.uri != next.uri || previous?.title != next.title) _start(next);
    });
  }

  void _start(PlaybackSession session) {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    final cover = session.anime?.coverUrl;
    mediaItem.add(MediaItem(
      id: session.uri,
      title: session.title,
      album: session.subtitle,
      artist: 'Kairo',
      artUri: cover == null ? null : Uri.parse(cover),
    ));

    final player = _controller.player;
    void update() => _publish(
          playing: player.state.playing,
          buffering: player.state.buffering,
          position: player.state.position,
          duration: player.state.duration,
          seekable: true,
        );
    _subscriptions.addAll([
      player.stream.playing.listen((_) => update()),
      player.stream.buffering.listen((_) => update()),
      player.stream.duration.listen((d) {
        final item = mediaItem.value;
        if (item != null && item.duration != d) mediaItem.add(item.copyWith(duration: d));
        update();
      }),
      // Position is extrapolated by Android between updates, so every few seconds is enough.
      Stream.periodic(const Duration(seconds: 5)).listen((_) => update()),
    ]);
    update();
  }

  void _publish({
    required bool playing,
    bool buffering = false,
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
    required bool seekable,
  }) {
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.rewind,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.fastForward,
        MediaControl.stop,
      ],
      systemActions: {if (seekable) MediaAction.seek, MediaAction.playPause},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: buffering ? AudioProcessingState.buffering : AudioProcessingState.ready,
      playing: playing,
      updatePosition: position,
    ));
  }

  void _clear() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    playbackState.add(PlaybackState(processingState: AudioProcessingState.idle, playing: false));
    mediaItem.add(null);
  }

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> rewind() => _controller.seekBy(const Duration(seconds: -10));

  @override
  Future<void> fastForward() => _controller.seekBy(const Duration(seconds: 10));

  @override
  Future<void> seek(Duration position) async {
    if (_container.read(playbackProvider) != null) await _controller.player.seek(position);
  }

  @override
  Future<void> stop() async {
    await _controller.close();
    await super.stop();
  }

  /// Swiping Kairo away from recent apps stops playback too.
  @override
  Future<void> onTaskRemoved() => stop();
}

/// Starts the notification service. Failure (e.g. in tests) just means no notification.
Future<void> initMediaNotification(ProviderContainer container) async {
  try {
    final handler = await AudioService.init(
      builder: () => KairoMediaHandler(container),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.dimetech.kairo.playback',
        androidNotificationChannelName: 'Playback',
        androidNotificationIcon: 'mipmap/ic_launcher',
        androidStopForegroundOnPause: false,
      ),
    );
    handler.attach();
  } catch (_) {
    // No media notification available.
  }
}
