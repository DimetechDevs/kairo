import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/router.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';

/// Plays an imported file or a stream URL with resume, tracks and gestures.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.animeId, required this.episode});

  final int animeId;
  final int episode;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  static const _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  late final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  final _subscriptions = <StreamSubscription<Object?>>[];

  LibraryFile? _file;
  Anime? _anime;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  bool _controls = true;
  bool _countedWatched = false;
  int _speed = 1;
  String? _error;
  String? _seekToast;
  Timer? _hideControls;
  Timer? _hideToast;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _file = ref.read(libraryProvider.notifier).fileFor(widget.animeId, widget.episode);
    _anime = ref.read(animeProvider(widget.animeId)) ?? _file?.anime;
    if (_file == null) {
      _error = "Episode ${widget.episode} isn't in your library. Import the file or add a stream URL first.";
      _buffering = false;
      return;
    }

    _subscriptions.addAll([
      _player.stream.position.listen((p) => setState(() => _position = p)),
      _player.stream.duration.listen((d) => setState(() => _duration = d)),
      _player.stream.playing.listen((p) {
        setState(() => _playing = p);
        if (!p) _saveProgress();
      }),
      _player.stream.buffering.listen((b) => setState(() => _buffering = b)),
      _player.stream.completed.listen((done) {
        if (done) _onCompleted();
      }),
      _player.stream.error.listen((e) => setState(() => _error = e)),
    ]);
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());

    final saved = ref.read(progressProvider)[(widget.animeId, widget.episode)];
    final resumeAt = saved != null && !saved.finished && saved.position > const Duration(seconds: 30) ? saved.position : null;
    _player.open(Media(_file!.uri, start: resumeAt));
    if (resumeAt != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _toast('Resumed at ${formatDuration(resumeAt)}'));
    }
    _scheduleHide();
  }

  @override
  void dispose() {
    _saveProgress();
    for (final s in _subscriptions) {
      s.cancel();
    }
    _hideControls?.cancel();
    _hideToast?.cancel();
    _saveTimer?.cancel();
    _player.dispose();
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _saveProgress() {
    if (_file == null || _duration <= Duration.zero) return;
    ref.read(progressProvider.notifier).save(widget.animeId, widget.episode, _position, _duration);

    // Count the episode as watched once, at 90%.
    final anime = _anime;
    if (!_countedWatched && anime != null && _position.inMilliseconds >= _duration.inMilliseconds * 0.9) {
      _countedWatched = true;
      final watched = ref.read(watchlistProvider)[anime.id]?.watched ?? 0;
      if (widget.episode > watched) ref.read(watchlistProvider.notifier).setWatched(anime, widget.episode);
    }
  }

  LibraryFile? get _nextFile => ref.read(libraryProvider.notifier).fileFor(widget.animeId, widget.episode + 1);

  void _onCompleted() {
    _saveProgress();
    if (_nextFile != null && mounted) {
      context.pushReplacement(Routes.player(widget.animeId, widget.episode + 1));
    } else {
      setState(() => _controls = true);
    }
  }

  void _scheduleHide() {
    _hideControls?.cancel();
    _hideControls = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _toast(String text) {
    setState(() => _seekToast = text);
    _hideToast?.cancel();
    _hideToast = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _seekToast = null);
    });
  }

  void _seekBy(int seconds) {
    var next = _position + Duration(seconds: seconds);
    if (next < Duration.zero) next = Duration.zero;
    if (_duration > Duration.zero && next > _duration) next = _duration;
    _player.seek(next);
    _toast(seconds > 0 ? '+${seconds}s' : '−${-seconds}s');
    if (_controls) _scheduleHide();
  }

  Future<void> _chooseSubtitles() async {
    final tracks = _player.state.tracks.subtitle;
    final current = _player.state.track.subtitle;
    final choice = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TrackSheet(
        title: 'Subtitles',
        options: [
          for (final t in tracks)
            if (t.id != 'auto') (t, t.id == 'no' ? 'Off' : _trackLabel(t.id, t.title, t.language), t == current),
          ('file', 'Load a subtitle file (.srt, .ass, .vtt)…', false),
        ],
      ),
    );
    if (choice is SubtitleTrack) {
      await _player.setSubtitleTrack(choice);
    } else if (choice == 'file') {
      final docs = ref.read(documentsProvider);
      final doc = await docs.pickSubtitle();
      if (doc == null) return;
      final bytes = await docs.readBytes(doc.uri);
      if (bytes == null) return;
      await _player.setSubtitleTrack(SubtitleTrack.data(utf8.decode(bytes, allowMalformed: true), title: doc.name));
    }
  }

  Future<void> _chooseAudio() async {
    final tracks = _player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final current = _player.state.track.audio;
    final choice = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TrackSheet(
        title: 'Audio',
        options: [for (final t in tracks) (t, _trackLabel(t.id, t.title, t.language), t == current)],
      ),
    );
    if (choice is AudioTrack) await _player.setAudioTrack(choice);
  }

  static String _trackLabel(String id, String? title, String? language) {
    final parts = [
      if (title != null && title.isNotEmpty) title,
      if (language != null && language.isNotEmpty) language.toUpperCase(),
    ];
    return parts.isEmpty ? 'Track $id' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final title = '${_anime?.shortTitle ?? 'Episode'} · Episode ${widget.episode}';
    final fraction = _duration.inMilliseconds == 0 ? 0.0 : _position.inMilliseconds / _duration.inMilliseconds;
    final hasNext = _file != null && _nextFile != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_file != null) Video(controller: _video, controls: NoVideoControls, fill: Colors.black),
          // Gesture layer: tap toggles controls, double-tap a side seeks 10s.
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  onDoubleTap: () => _seekBy(-10),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  onDoubleTap: () => _seekBy(10),
                ),
              ),
            ],
          ),
          if (_buffering && _error == null) const Center(child: IgnorePointer(child: CircularProgressIndicator())),
          if (_seekToast != null)
            Center(
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: KairoColors.background.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(KairoRadii.pill),
                  ),
                  child: Text(_seekToast!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          if (_error != null)
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(KairoSpacing.xxl),
                child: Container(
                  padding: const EdgeInsets.all(KairoSpacing.lg),
                  constraints: const BoxConstraints(maxWidth: 460),
                  decoration: BoxDecoration(color: KairoColors.surface, borderRadius: BorderRadius.circular(KairoRadii.panel)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: KairoColors.accent, size: 32),
                      const SizedBox(height: KairoSpacing.sm),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: KairoSpacing.md),
                      OutlinedButton(onPressed: () => context.pop(), child: const Text('Back')),
                    ],
                  ),
                ),
              ),
            ),
          if (_controls && _error == null) ...[
            const IgnorePointer(child: ColoredBox(color: Color(0x73050510))),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(tooltip: 'Back', onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back_rounded)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _PillButton(label: 'CC', tooltip: 'Subtitles', onPressed: _chooseSubtitles),
                        const SizedBox(width: 6),
                        _PillButton(label: 'Audio', tooltip: 'Audio track', onPressed: _chooseAudio),
                        const SizedBox(width: 6),
                        _PillButton(
                          label: '${_speeds[_speed]}×',
                          tooltip: 'Playback speed',
                          onPressed: () {
                            setState(() => _speed = (_speed + 1) % _speeds.length);
                            _player.setRate(_speeds[_speed]);
                          },
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'Back 10 seconds',
                          iconSize: 28,
                          onPressed: () => _seekBy(-10),
                          icon: const Icon(Icons.replay_10_rounded),
                        ),
                        const SizedBox(width: 48),
                        IconButton.filled(
                          tooltip: _playing ? 'Pause' : 'Play',
                          iconSize: 40,
                          style: IconButton.styleFrom(backgroundColor: KairoColors.text, foregroundColor: KairoColors.background),
                          onPressed: () {
                            _player.playOrPause();
                            _scheduleHide();
                          },
                          icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        ),
                        const SizedBox(width: 48),
                        IconButton.filledTonal(
                          tooltip: 'Forward 10 seconds',
                          iconSize: 28,
                          onPressed: () => _seekBy(10),
                          icon: const Icon(Icons.forward_10_rounded),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${formatDuration(_position)} / ${formatDuration(_duration)}',
                            style: const TextStyle(fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]),
                          ),
                        ),
                        const Spacer(),
                        // Openings are usually about 1:30, somewhere in the first few minutes.
                        if (_position < const Duration(minutes: 5) && _duration > const Duration(minutes: 10))
                          FilledButton(
                            onPressed: () => _seekBy(85),
                            style: FilledButton.styleFrom(
                              backgroundColor: KairoColors.text,
                              foregroundColor: KairoColors.background,
                              minimumSize: const Size(0, 40),
                            ),
                            child: const Text('Skip 85s'),
                          ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: hasNext ? () => context.pushReplacement(Routes.player(widget.animeId, widget.episode + 1)) : null,
                          icon: const Icon(Icons.skip_next_rounded),
                          label: const Text('Next'),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: KairoColors.accent,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: KairoColors.text,
                        trackHeight: 4,
                      ),
                      child: Slider(
                        value: fraction.clamp(0, 1),
                        semanticFormatterCallback: (_) => formatDuration(_position),
                        onChanged: _duration == Duration.zero
                            ? null
                            : (v) {
                                setState(() => _position = _duration * v);
                                _scheduleHide();
                              },
                        onChangeEnd: (v) => _player.seek(_duration * v),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_error != null)
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(tooltip: 'Back', onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back_rounded)),
              ),
            ),
        ],
      ),
    );
  }
}

/// A list of tracks to choose from; pops the chosen option's value.
class _TrackSheet extends StatelessWidget {
  const _TrackSheet({required this.title, required this.options});

  final String title;
  final List<(Object, String, bool)> options;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: KairoSpacing.lg),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(KairoSpacing.gutter, 0, KairoSpacing.gutter, KairoSpacing.sm),
            child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          if (options.isEmpty)
            const Padding(
              padding: EdgeInsets.all(KairoSpacing.gutter),
              child: Text('This video has no other tracks.', style: TextStyle(color: KairoColors.textSecondary)),
            ),
          for (final (value, label, selected) in options)
            ListTile(
              leading: Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? KairoColors.primarySoft : KairoColors.textMuted,
              ),
              title: Text(label),
              onTap: () => Navigator.pop(context, value),
            ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onPressed, required this.tooltip});

  final String label;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(52, 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          side: const BorderSide(color: Colors.white38),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
