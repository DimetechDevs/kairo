import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';

/// Player controls and gestures. Real video playback is wired in the playback step;
/// this screen simulates the clock so the controls can be tried now.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.animeId, required this.episode});

  final int animeId;
  final int episode;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  static const _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
  static const _duration = Duration(minutes: 23, seconds: 40);

  late Duration _position;
  bool _playing = true;
  bool _controls = true;
  bool _subtitles = true;
  bool _introSkipped = false;
  int _speed = 1;
  String? _seekToast;
  Timer? _clock;
  Timer? _hideControls;
  Timer? _hideToast;

  @override
  void initState() {
    super.initState();
    final saved = ref.read(progressProvider).where((p) => p.animeId == widget.animeId && p.episode == widget.episode);
    _position = saved.isEmpty ? Duration.zero : saved.first.position;
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _scheduleHide();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _hideControls?.cancel();
    _hideToast?.cancel();
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _tick() {
    if (!_playing || !mounted) return;
    setState(() {
      final next = _position + Duration(milliseconds: (1000 * _speeds[_speed]).round());
      _position = next > _duration ? _duration : next;
      if (_position == _duration) _playing = false;
    });
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

  void _seek(int seconds) {
    setState(() {
      final next = _position + Duration(seconds: seconds);
      _position = next < Duration.zero ? Duration.zero : (next > _duration ? _duration : next);
      _seekToast = seconds > 0 ? '+${seconds}s' : '−${-seconds}s';
    });
    _hideToast?.cancel();
    _hideToast = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekToast = null);
    });
    if (_controls) _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final anime = ref.watch(animeProvider(widget.animeId));
    if (anime == null) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));
    }
    final fraction = _position.inMilliseconds / _duration.inMilliseconds;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Stand-in for the video surface.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [const Color(0xFF1D2A44), anime.palette.first.withValues(alpha: 0.6), const Color(0xFF3A2450)],
              ),
            ),
          ),
          // Gesture layer: tap toggles controls, double-tap a side seeks 10s.
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  onDoubleTap: () => _seek(-10),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  onDoubleTap: () => _seek(10),
                ),
              ),
            ],
          ),
          if (_subtitles)
            Positioned(
              left: 0,
              right: 0,
              bottom: _controls ? 96 : 28,
              child: const IgnorePointer(
                child: Text(
                  '[Subtitle line appears here]',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 4)]),
                ),
              ),
            ),
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
          if (_controls) ...[
            const IgnorePointer(child: ColoredBox(color: Color(0x73050510))),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          onPressed: () => context.pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${anime.shortTitle} · Episode ${widget.episode}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _PillButton(
                          label: 'CC',
                          active: _subtitles,
                          tooltip: 'Subtitles',
                          onPressed: () => setState(() => _subtitles = !_subtitles),
                        ),
                        const SizedBox(width: 6),
                        _PillButton(
                          label: 'Japanese',
                          tooltip: 'Audio track',
                          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Audio tracks are listed once real playback is connected.')),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _PillButton(
                          label: '${_speeds[_speed]}×',
                          tooltip: 'Playback speed',
                          onPressed: () => setState(() => _speed = (_speed + 1) % _speeds.length),
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
                          onPressed: () => _seek(-10),
                          icon: const Icon(Icons.replay_10_rounded),
                        ),
                        const SizedBox(width: 48),
                        IconButton.filled(
                          tooltip: _playing ? 'Pause' : 'Play',
                          iconSize: 40,
                          style: IconButton.styleFrom(backgroundColor: KairoColors.text, foregroundColor: KairoColors.background),
                          onPressed: () {
                            setState(() => _playing = !_playing);
                            _scheduleHide();
                          },
                          icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        ),
                        const SizedBox(width: 48),
                        IconButton.filledTonal(
                          tooltip: 'Forward 10 seconds',
                          iconSize: 28,
                          onPressed: () => _seek(10),
                          icon: const Icon(Icons.forward_10_rounded),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Text(
                          '${formatDuration(_position)} / ${formatDuration(_duration)}',
                          style: const TextStyle(fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]),
                        ),
                        const Spacer(),
                        if (!_introSkipped)
                          FilledButton(
                            onPressed: () {
                              setState(() => _introSkipped = true);
                              _seek(85);
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: KairoColors.text,
                              foregroundColor: KairoColors.background,
                              minimumSize: const Size(0, 40),
                            ),
                            child: const Text('Skip intro'),
                          ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: (anime.episodes ?? anime.airedEpisodes) > widget.episode
                              ? () => context.pushReplacement('/player/${anime.id}/${widget.episode + 1}')
                              : null,
                          icon: const Icon(Icons.skip_next_rounded),
                          label: const Text('Next episode'),
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
                        onChanged: (v) => setState(
                          () => _position = Duration(milliseconds: (v * _duration.inMilliseconds).round()),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onPressed, required this.tooltip, this.active = false});

  final String label;
  final VoidCallback onPressed;
  final String tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(52, 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          backgroundColor: active ? KairoColors.primary.withValues(alpha: 0.85) : Colors.transparent,
          side: const BorderSide(color: Colors.white38),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
