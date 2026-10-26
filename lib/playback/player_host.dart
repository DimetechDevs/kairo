import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/theme.dart';
import '../data/settings.dart';
import '../widgets/common.dart';
import 'playback_controller.dart';

/// Shows the player above every screen: full screen, or as a mini player above the tab bar
/// while the user keeps browsing. Wraps the app's router in `MaterialApp.builder`.
class PlayerHost extends ConsumerStatefulWidget {
  const PlayerHost({super.key, required this.child});

  /// Space the mini player takes above the tab bar; tab screens end above it.
  static const miniPlayerReserve = _PlayerFrame._miniHeight + 8;

  /// How far the mini player's top sits above the bottom inset on any screen.
  static const miniPlayerClearance = 68 + 8 + _PlayerFrame._miniHeight;

  final Widget child;

  @override
  ConsumerState<PlayerHost> createState() => _PlayerHostState();
}

class _PlayerHostState extends ConsumerState<PlayerHost> with WidgetsBindingObserver {
  /// The player's own navigator, so its sheets and menus open above the video.
  final _playerNavigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back in the full-screen player: close a sheet, else shrink to the mini player.
  @override
  Future<bool> didPopRoute() async {
    final session = ref.read(playbackProvider);
    if (session == null || !session.expanded) return false;
    final nav = _playerNavigator.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
      return true;
    }
    ref.read(playbackProvider.notifier).minimize();
    return true;
  }

  /// Whether the app's router has a screen to go back to, as it last reported.
  bool _routerCanPop = false;

  /// Tells Android whether Kairo handles the back gesture. With predictive back the system
  /// only sends back to Kairo when it says so, and the full-screen player always wants it.
  void _reportBack() {
    final expanded = ref.read(playbackProvider)?.expanded ?? false;
    NavigationNotification(canHandlePop: _routerCanPop || expanded).dispatch(context);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(playbackProvider);
    ref.listen(playbackProvider.select((s) => s?.expanded ?? false), (_, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reportBack();
      });
    });
    return Stack(
      children: [
        NotificationListener<NavigationNotification>(
          onNotification: (n) {
            _routerCanPop = n.canHandlePop;
            _reportBack();
            return true;
          },
          child: widget.child,
        ),
        if (session != null)
          // The player's own sheets don't decide back handling; [_reportBack] does.
          NotificationListener<NavigationNotification>(
            onNotification: (_) => true,
            child: _PlayerFrame(session: session, navigatorKey: _playerNavigator),
          ),
      ],
    );
  }
}

class _PlayerFrame extends ConsumerWidget {
  const _PlayerFrame({required this.session, required this.navigatorKey});

  final PlaybackSession session;
  final GlobalKey<NavigatorState> navigatorKey;

  static const _miniHeight = 64.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final expanded = session.expanded;
    // Above the tab bar (68) on tab screens; on other screens it just sits at the bottom.
    final mini = Rect.fromLTWH(8, size.height - media.padding.bottom - 68 - 8 - _miniHeight, size.width - 16, _miniHeight);
    final frame = expanded ? Offset.zero & size : mini;
    // Implicit animations retarget from wherever they are, so a quick tap back reverses smoothly.
    // With the phone's animations off, the player jumps straight to its new size.
    final move = media.disableAnimations ? Duration.zero : const Duration(milliseconds: 260);

    // The video is always laid out at its full-screen size and scaled into the mini player,
    // so switching modes never reloads it.
    final surfaceSize = size;
    final surfaceRect = expanded ? Offset.zero & size : const Rect.fromLTWH(0, 0, _miniHeight * 16 / 9, _miniHeight);

    return AnimatedPositioned.fromRect(
      rect: frame,
      duration: move,
      curve: Curves.easeOutCubic,
      child: Material(
        color: expanded ? Colors.black : KairoColors.surfaceRaised,
        elevation: expanded ? 0 : 8,
        borderRadius: BorderRadius.circular(expanded ? 0 : KairoRadii.panel),
        clipBehavior: Clip.antiAlias,
        child: Navigator(
          key: navigatorKey,
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => ScaffoldMessenger(
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: Consumer(
                  builder: (context, ref, _) {
                    final s = ref.watch(playbackProvider);
                    if (s == null) return const SizedBox.shrink();
                    return Stack(
                      children: [
                        AnimatedPositioned.fromRect(
                          rect: surfaceRect,
                          duration: move,
                          curve: Curves.easeOutCubic,
                          child: ClipRect(
                            child: FittedBox(
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                              child: SizedBox.fromSize(size: surfaceSize, child: _Surface(session: s)),
                            ),
                          ),
                        ),
                        if (s.expanded) const Positioned.fill(child: _NativeControls()),
                        if (!s.expanded)
                          Positioned(
                            left: _miniHeight * 16 / 9,
                            right: 0,
                            top: 0,
                            bottom: 0,
                            child: _MiniBar(session: s),
                          ),
                        if (!s.expanded)
                          // Tapping the video part of the mini player expands it too.
                          Positioned.fromRect(
                            rect: const Rect.fromLTWH(0, 0, _miniHeight * 16 / 9, _miniHeight),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: ref.read(playbackProvider.notifier).expand,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The video itself.
class _Surface extends ConsumerWidget {
  const _Surface({required this.session});

  final PlaybackSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Video(controller: ref.read(playbackProvider.notifier).video, controls: NoVideoControls, fill: Colors.black);
}

/// The mini player's title and buttons.
class _MiniBar extends ConsumerWidget {
  const _MiniBar({required this.session});

  final PlaybackSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playbackProvider.notifier);
    final playing = StreamBuilder(
      stream: controller.player.stream.playing,
      initialData: controller.player.state.playing,
      builder: (_, snap) => _playPause(controller, snap.data ?? false),
    );

    return InkWell(
      onTap: controller.expand,
      child: Row(
        children: [
          const SizedBox(width: KairoSpacing.md),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                Text(
                  session.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: KairoColors.textSecondary),
                ),
              ],
            ),
          ),
          playing,
          IconButton(tooltip: 'Close player', onPressed: controller.close, icon: const Icon(Icons.close_rounded)),
        ],
      ),
    );
  }

  Widget _playPause(PlaybackController controller, bool playing) => IconButton(
        tooltip: playing ? 'Pause' : 'Play',
        onPressed: controller.playPause,
        icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
      );
}

/// Kairo's own player controls: tap to show, double-tap a side to seek, tracks, speed, rotate.
class _NativeControls extends ConsumerStatefulWidget {
  const _NativeControls();

  @override
  ConsumerState<_NativeControls> createState() => _NativeControlsState();
}

class _NativeControlsState extends ConsumerState<_NativeControls> {
  final _subscriptions = <StreamSubscription<Object?>>[];
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  bool _controls = true;
  double? _dragging;
  String? _toast;
  Timer? _hideControls;
  Timer? _hideToast;

  PlaybackController get _controller => ref.read(playbackProvider.notifier);
  Player get _player => _controller.player;

  @override
  void initState() {
    super.initState();
    final s = _player.state;
    _position = s.position;
    _duration = s.duration;
    _playing = s.playing;
    _buffering = s.buffering;
    _subscriptions.addAll([
      _player.stream.position.listen((p) => setState(() => _position = p)),
      _player.stream.duration.listen((d) => setState(() => _duration = d)),
      _player.stream.playing.listen((p) => setState(() => _playing = p)),
      _player.stream.buffering.listen((b) => setState(() => _buffering = b)),
    ]);
    _scheduleHide();
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _hideControls?.cancel();
    _hideToast?.cancel();
    super.dispose();
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

  void _showToast(String text) {
    setState(() => _toast = text);
    _hideToast?.cancel();
    _hideToast = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _seekBy(int seconds) {
    _controller.seekBy(Duration(seconds: seconds));
    _showToast(seconds > 0 ? '+${seconds}s' : '−${-seconds}s');
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
        ],
      ),
    );
    if (choice is SubtitleTrack) await _player.setSubtitleTrack(choice);
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
    final session = ref.watch(playbackProvider)!;
    final settings = ref.watch(settingsProvider);
    final position = _dragging != null ? _duration * _dragging! : _position;
    final fraction = _duration.inMilliseconds == 0 ? 0.0 : position.inMilliseconds / _duration.inMilliseconds;
    final hasNext = _controller.hasNext;
    final rate = _player.state.rate;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Gesture layer: tap toggles controls, double-tap a side seeks 10s.
        Row(
          children: [
            for (final seconds in const [-10, 10])
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  onDoubleTap: () => _seekBy(seconds),
                ),
              ),
          ],
        ),
        if (_buffering && session.error == null) const Center(child: IgnorePointer(child: CircularProgressIndicator())),
        if (_toast != null)
          Center(
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: KairoColors.background.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(KairoRadii.pill),
                ),
                child: Text(_toast!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        if (session.error != null)
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
                    Text(session.error!, textAlign: TextAlign.center),
                    const SizedBox(height: KairoSpacing.md),
                    OutlinedButton(onPressed: _controller.close, child: const Text('Close')),
                  ],
                ),
              ),
            ),
          ),
        if (_controls && session.error == null) ...[
          const IgnorePointer(child: ColoredBox(color: Color(0x73050510))),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Minimize',
                        onPressed: _controller.minimize,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
                      ),
                      Expanded(
                        child: Text(
                          '${session.title} · ${session.subtitle}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Rotate',
                        onPressed: () => _controller.rotate(MediaQuery.orientationOf(context)),
                        icon: const Icon(Icons.screen_rotation_rounded),
                      ),
                      IconButton(tooltip: 'Close player', onPressed: _controller.close, icon: const Icon(Icons.close_rounded)),
                    ],
                  ),
                  // Tracks and speed get their own row, so they fit in portrait too.
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 6,
                      children: [
                        _PillButton(label: 'CC', tooltip: 'Subtitles', onPressed: _chooseSubtitles),
                        _PillButton(label: 'Audio', tooltip: 'Audio track', onPressed: _chooseAudio),
                        _PillButton(
                          label: '$rate×',
                          tooltip: 'Playback speed',
                          onPressed: () {
                            final speeds = PlaybackController.speeds;
                            final i = speeds.indexOf(rate);
                            _player.setRate(speeds[(i + 1) % speeds.length]);
                            setState(() {});
                          },
                        ),
                      ],
                    ),
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
                      const SizedBox(width: 40),
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
                      const SizedBox(width: 40),
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
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '${formatDuration(position)} / ${formatDuration(_duration)}',
                          style: const TextStyle(fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]),
                        ),
                      ),
                      const Spacer(),
                      // Openings are usually about 1:30, somewhere in the first few minutes.
                      if (settings.skipIntro && _position < const Duration(minutes: 5) && _duration > const Duration(minutes: 10))
                        FilledButton(
                          onPressed: () => _seekBy(settings.skipSeconds),
                          style: FilledButton.styleFrom(
                            backgroundColor: KairoColors.text,
                            foregroundColor: KairoColors.background,
                            minimumSize: const Size(0, 40),
                          ),
                          child: Text('Skip ${settings.skipSeconds}s'),
                        ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: hasNext ? _controller.playNext : null,
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
                      semanticFormatterCallback: (_) => formatDuration(position),
                      onChanged: _duration == Duration.zero
                          ? null
                          : (v) {
                              setState(() => _dragging = v);
                              _scheduleHide();
                            },
                      onChangeEnd: (v) {
                        _player.seek(_duration * v);
                        setState(() => _dragging = null);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
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
          minimumSize: const Size(52, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          side: const BorderSide(color: Colors.white38),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
