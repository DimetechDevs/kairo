import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';


import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/poster_card.dart';
import '../../widgets/undo_snack.dart';
import '../../playback/open.dart';
import '../../playback/playback_controller.dart';
import '../../playback/player_host.dart';

class DetailsScreen extends ConsumerStatefulWidget {
  const DetailsScreen({super.key, required this.animeId});

  final int animeId;

  @override
  ConsumerState<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends ConsumerState<DetailsScreen> {
  static const _collapsedEpisodes = 12;

  bool _expanded = false;
  bool _allEpisodes = false;

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(animeDetailsProvider(widget.animeId));
    final entry = ref.watch(watchlistProvider)[widget.animeId];

    // Keep the saved copy in the watchlist up to date (new episodes, artwork).
    ref.listen(animeDetailsProvider(widget.animeId), (_, next) {
      if (next.value case final anime?) ref.read(watchlistProvider.notifier).refreshSnapshot(anime);
    });

    final anime = details.value ?? entry?.anime;
    if (anime == null) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: details.hasError
            ? ErrorState(error: details.error!, onRetry: () => ref.invalidate(animeDetailsProvider(widget.animeId)))
            : const _DetailsSkeleton(),
      );
    }

    final watched = entry?.watched ?? 0;
    final episodeCount = anime.episodes ?? anime.airedEpisodes;
    final shownEpisodes = _allEpisodes ? episodeCount : episodeCount.clamp(0, _collapsedEpisodes);
    final accent = anime.accent;

    // What the main button plays: an episode in progress, else the next aired one.
    final progress = ref.watch(progressProvider);
    final resumeEpisode = ref.watch(resumeListProvider).where((p) => p.animeId == anime.id).firstOrNull?.episode;
    bool aired(int ep) => ep >= 1 && (!anime.isAiring || ep <= anime.airedEpisodes) && (episodeCount == 0 || ep <= episodeCount);
    final playEp = resumeEpisode ?? (aired(watched + 1) ? watched + 1 : null);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 230,
            pinned: true,
            backgroundColor: KairoColors.background,
            leading: Padding(
              padding: const EdgeInsets.all(6),
              child: IconButton.filledTonal(
                tooltip: 'Back',
                style: IconButton.styleFrom(backgroundColor: KairoColors.background.withValues(alpha: 0.6)),
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: CoverArt(
                anime: anime,
                banner: true,
                radius: 0,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x66000000), Colors.transparent, KairoColors.background],
                      stops: [0, 0.4, 1],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(KairoSpacing.gutter, 0, KairoSpacing.gutter, 0),
            sliver: SliverList.list(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      width: 104,
                      height: 150,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(KairoRadii.panel),
                        boxShadow: [
                          BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8)),
                        ],
                      ),
                      child: CoverArt(anime: anime, radius: KairoRadii.panel),
                    ),
                    const SizedBox(width: KairoSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            anime.title,
                            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, height: 1.2),
                          ),
                          if (anime.nativeTitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              anime.nativeTitle!,
                              style: const TextStyle(fontSize: 13, color: KairoColors.textSecondary),
                            ),
                          ],
                          if (anime.studios.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              anime.studios.join(', '),
                              style: TextStyle(fontSize: 13, color: accent, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KairoSpacing.lg),
                _InfoStrip(anime: anime),
                if (anime.nextAiring != null) ...[
                  const SizedBox(height: KairoSpacing.md),
                  _Banner(
                    icon: Icons.schedule_rounded,
                    color: KairoColors.success,
                    text: '${anime.nextAiring!.label()} · ${_weekday(anime.nextAiring!.at)}',
                  ),
                ],
                const SizedBox(height: KairoSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: playEp != null
                          ? FilledButton.icon(
                              onPressed: () => playEpisode(context, ref, anime.id, playEp),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(
                                resumeEpisode != null ? 'Resume Ep $playEp' : 'Play Ep $playEp',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          : entry == null
                          ? FilledButton.icon(
                              onPressed: () =>
                                  ref.read(watchlistProvider.notifier).setStatus(anime, ListStatus.planned),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Add to list'),
                            )
                          : FilledButton.icon(
                              onPressed: anime.episodes != null && watched >= anime.episodes!
                                  ? null
                                  : () => ref.read(watchlistProvider.notifier).setWatched(anime, watched + 1),
                              icon: const Icon(Icons.check_rounded),
                              label: Text(
                                anime.episodes != null && watched >= anime.episodes!
                                    ? 'All watched'
                                    : 'Watched Ep ${watched + 1}',
                              ),
                            ),
                    ),
                    const SizedBox(width: KairoSpacing.sm),
                    _StatusButton(
                      status: entry?.status,
                      onSelected: (s) => ref.read(watchlistProvider.notifier).setStatus(anime, s),
                      onRemove: entry == null ? null : () => removeFromListWithUndo(context, ref, anime),
                    ),
                  ],
                ),
                if (entry != null && episodeCount > 0) ...[
                  const SizedBox(height: KairoSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: ProgressLine(value: watched / episodeCount, color: accent),
                      ),
                      const SizedBox(width: KairoSpacing.md),
                      Text(
                        '$watched / ${anime.episodes ?? '?'}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: KairoColors.textSecondary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: KairoSpacing.lg),
                Wrap(
                  spacing: KairoSpacing.sm,
                  runSpacing: KairoSpacing.sm,
                  children: [for (final g in anime.genres) TagChip(g)],
                ),
                const SizedBox(height: KairoSpacing.lg),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.topCenter,
                  child: Text(
                    anime.synopsis,
                    maxLines: _expanded ? null : 4,
                    overflow: _expanded ? null : TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, height: 1.65, color: Color(0xFFD9D6E8)),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    style: TextButton.styleFrom(foregroundColor: KairoColors.info, padding: EdgeInsets.zero),
                    child: Text(_expanded ? 'Show less' : 'Read more'),
                  ),
                ),
                if (episodeCount > 0) ...[
                  const SizedBox(height: KairoSpacing.sm),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Episodes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      ),
                      Flexible(
                        child: Text(
                          anime.isAiring && anime.episodes != null
                              ? '${anime.airedEpisodes} of ${anime.episodes} aired'
                              : '$episodeCount episodes',
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontSize: 13, color: KairoColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: KairoSpacing.sm),
                  for (var ep = 1; ep <= shownEpisodes; ep++)
                    _EpisodeRow(
                      anime: anime,
                      episode: ep,
                      watched: ep <= watched,
                      aired: aired(ep),
                      onToggle: () =>
                          ref.read(watchlistProvider.notifier).setWatched(anime, ep <= watched ? ep - 1 : ep),
                      streaming: anime.streamingEpisode(ep),
                      progress: progress[(anime.id, ep)],
                    ),
                  if (episodeCount > _collapsedEpisodes)
                    Center(
                      child: TextButton(
                        onPressed: () => setState(() => _allEpisodes = !_allEpisodes),
                        style: TextButton.styleFrom(foregroundColor: KairoColors.info),
                        child: Text(_allEpisodes ? 'Show fewer' : 'Show all $episodeCount episodes'),
                      ),
                    ),
                ],
                if (details.isLoading && details.value == null)
                  const Padding(
                    padding: EdgeInsets.all(KairoSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
          if (anime.recommendations.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: KairoSpacing.lg),
                child: PosterRow(title: 'You might also like', items: anime.recommendations),
              ),
            ),
          SliverToBoxAdapter(
            // Room to scroll the last rows clear of the mini player while something plays.
            child: SizedBox(
              height: ref.watch(playbackProvider.select((s) => s != null))
                  ? MediaQuery.paddingOf(context).bottom + PlayerHost.miniPlayerClearance + KairoSpacing.md
                  : KairoSpacing.xxl * 2,
            ),
          ),
        ],
      ),
    );
  }

  static String _weekday(DateTime t) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final local = t.toLocal();
    return '${days[local.weekday - 1]} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

/// Score, episodes, format and season in one row.
class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.anime});

  final Anime anime;

  @override
  Widget build(BuildContext context) {
    final season = anime.season == null ? null : '${anime.season![0]}${anime.season!.substring(1).toLowerCase()}';
    final cells = <(Widget, String)>[
      (
        anime.score == null
            ? const Text('–', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))
            : ScoreLabel(score: anime.score!, size: 15),
        'Score',
      ),
      (
        Text(anime.episodes?.toString() ?? '?', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        'Episodes',
      ),
      (Text(anime.formatLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)), anime.statusLabel),
      (
        Text(anime.year?.toString() ?? '–', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        season ?? 'Year',
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: KairoSpacing.md),
      decoration: BoxDecoration(color: KairoColors.surface, borderRadius: BorderRadius.circular(KairoRadii.panel)),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) Container(width: 1, height: 28, color: KairoColors.outline),
            Expanded(
              child: Column(
                children: [
                  FittedBox(fit: BoxFit.scaleDown, child: cells[i].$1),
                  const SizedBox(height: 2),
                  Text(cells[i].$2, style: const TextStyle(fontSize: 11, color: KairoColors.textSecondary)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(KairoRadii.card),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({required this.status, required this.onSelected, this.onRemove});

  final ListStatus? status;
  final ValueChanged<ListStatus> onSelected;
  final VoidCallback? onRemove;

  Color get _color => switch (status) {
    ListStatus.watching => KairoColors.primarySoft,
    ListStatus.completed => KairoColors.success,
    ListStatus.paused => KairoColors.info,
    ListStatus.dropped => KairoColors.accent,
    ListStatus.planned || null => KairoColors.textSecondary,
  };

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final s in ListStatus.values)
          MenuItemButton(
            onPressed: () => onSelected(s),
            leadingIcon: Icon(
              s == status ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 18,
            ),
            child: Text(s.label),
          ),
        if (onRemove != null) ...[
          const Divider(height: 1),
          MenuItemButton(
            onPressed: onRemove,
            leadingIcon: const Icon(Icons.delete_outline_rounded, size: 18, color: KairoColors.accent),
            child: const Text('Remove from list', style: TextStyle(color: KairoColors.accent)),
          ),
        ],
      ],
      builder: (context, controller, _) => OutlinedButton.icon(
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        style: OutlinedButton.styleFrom(
          foregroundColor: _color,
          side: BorderSide(color: _color),
          minimumSize: const Size(0, 48),
        ),
        icon: Icon(status == null ? Icons.bookmark_add_outlined : Icons.bookmark_rounded, size: 18),
        label: Text(status?.label ?? 'Status'),
      ),
    );
  }
}

class _EpisodeRow extends ConsumerWidget {
  const _EpisodeRow({
    required this.anime,
    required this.episode,
    required this.watched,
    required this.aired,
    required this.onToggle,
    this.streaming,
    this.progress,
  });

  final Anime anime;
  final int episode;
  final bool watched;
  final bool aired;
  final StreamingEpisode? streaming;
  final PlaybackProgress? progress;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = progress;
    final (label, color) = switch ((watched, aired)) {
      _ when p != null && !p.finished => (
        '${(p.remaining.inSeconds / 60).ceil()} min left',
        KairoColors.info,
      ),
      (true, _) => ('Watched', KairoColors.success),
      (false, true) => (anime.duration != null ? '${anime.duration} min' : 'Aired', KairoColors.textSecondary),
      (false, false) => ('Not aired yet', KairoColors.textMuted),
    };
    final thumbnail = streaming?.thumbnail;
    final fraction = p != null ? (p.finished ? 1.0 : p.fraction) : (watched ? 1.0 : 0.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: KairoSpacing.sm),
      child: Material(
        color: KairoColors.surface,
        borderRadius: BorderRadius.circular(KairoRadii.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: aired ? () => playEpisode(context, ref, anime.id, episode) : null,
          child: Padding(
            padding: const EdgeInsets.all(KairoSpacing.sm),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  height: 56,
                  child: Opacity(
                    opacity: aired ? 1 : 0.4,
                    child: ClipRSuperellipse(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (thumbnail != null)
                            CachedNetworkImage(
                              imageUrl: thumbnail,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) => CoverArt(anime: anime, banner: true, radius: 0),
                            )
                          else
                            CoverArt(anime: anime, banner: true, radius: 0),
                          ColoredBox(color: Colors.black.withValues(alpha: thumbnail != null ? 0.15 : 0.35)),
                          Center(
                            child: aired
                                ? const Icon(Icons.play_circle_fill_rounded, size: 28)
                                : Text('$episode', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          ),
                          if (fraction > 0)
                            Align(
                              alignment: Alignment.bottomLeft,
                              child: FractionallySizedBox(
                                widthFactor: fraction.clamp(0, 1),
                                child: const SizedBox(height: 3, child: ColoredBox(color: KairoColors.accent)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: KairoSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Episode $episode', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      if (streaming?.name case final name?)
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Color(0xFFD9D6E8)),
                        ),
                      const SizedBox(height: 2),
                      Text(label, style: TextStyle(fontSize: 12, color: color)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: watched ? 'Mark episode $episode unwatched' : 'Mark watched up to episode $episode',
                  onPressed: aired ? onToggle : null,
                  icon: Icon(
                    watched ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: watched ? KairoColors.success : KairoColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailsSkeleton extends StatelessWidget {
  const _DetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(KairoSpacing.gutter),
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Skeleton(width: 104, height: 150, radius: KairoRadii.panel),
            SizedBox(width: KairoSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Skeleton(height: 20), SizedBox(height: 8), Skeleton(width: 120, height: 14)],
              ),
            ),
          ],
        ),
        SizedBox(height: KairoSpacing.lg),
        Skeleton(height: 64, radius: KairoRadii.panel),
        SizedBox(height: KairoSpacing.lg),
        Skeleton(height: 48, radius: KairoRadii.pill),
        SizedBox(height: KairoSpacing.lg),
        Skeleton(height: 14),
        SizedBox(height: 8),
        Skeleton(height: 14),
        SizedBox(height: 8),
        Skeleton(width: 200, height: 14),
      ],
    );
  }
}
