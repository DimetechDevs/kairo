import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/cover_art.dart';

class DetailsScreen extends ConsumerStatefulWidget {
  const DetailsScreen({super.key, required this.animeId});

  final int animeId;

  @override
  ConsumerState<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends ConsumerState<DetailsScreen> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final anime = ref.watch(animeProvider(widget.animeId));
    final entry = ref.watch(watchlistProvider)[anime.id];
    final files = ref.watch(libraryProvider).where((f) => f.animeId == anime.id).toList();
    final progress = ref.watch(progressProvider).where((p) => p.animeId == anime.id).firstOrNull;
    final playable = files.where((f) => f.state == FileState.matched).map((f) => f.episode!).toSet();
    final watched = entry?.watched ?? 0;

    // The main action depends on what can actually be played (plan section 1).
    final resumeEpisode = progress != null && playable.contains(progress.episode) ? progress.episode : null;
    final nextEpisode = resumeEpisode ?? (playable.where((e) => e > watched).toList()..sort()).firstOrNull;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 210,
            pinned: true,
            backgroundColor: KairoColors.background,
            leading: IconButton.filledTonal(
              tooltip: 'Back',
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: CoverArt(anime: anime, radius: 0),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(KairoSpacing.gutter, KairoSpacing.lg, KairoSpacing.gutter, KairoSpacing.xxl),
            sliver: SliverList.list(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(width: 96, height: 140, child: CoverArt(anime: anime, radius: KairoRadii.panel)),
                    const SizedBox(width: KairoSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(anime.title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, height: 1.2)),
                          if (anime.nativeTitle != null)
                            Text(anime.nativeTitle!, style: const TextStyle(fontSize: 13, color: KairoColors.textSecondary)),
                          Text(
                            '${anime.year} · ${anime.format} · ${anime.episodes} eps · ${anime.status}',
                            style: const TextStyle(fontSize: 13, color: KairoColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KairoSpacing.lg),
                _AvailabilityBanner(count: files.length, total: anime.episodes),
                const SizedBox(height: KairoSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: nextEpisode != null
                          ? FilledButton.icon(
                              onPressed: () => context.push(Routes.player(anime.id, nextEpisode)),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(resumeEpisode != null ? 'Resume Ep $nextEpisode' : 'Play Ep $nextEpisode'),
                            )
                          : FilledButton.icon(
                              onPressed: () => context.go(Routes.library),
                              icon: const Icon(Icons.file_upload_outlined),
                              label: const Text('Import episodes'),
                            ),
                    ),
                    const SizedBox(width: KairoSpacing.sm),
                    _StatusButton(
                      status: entry?.status,
                      onSelected: (s) => ref.read(watchlistProvider.notifier).setStatus(anime.id, s),
                    ),
                  ],
                ),
                const SizedBox(height: KairoSpacing.lg),
                Wrap(spacing: KairoSpacing.sm, runSpacing: KairoSpacing.sm, children: [for (final g in anime.genres) TagChip(g)]),
                const SizedBox(height: KairoSpacing.lg),
                Text(
                  anime.synopsis,
                  maxLines: _expanded ? null : 3,
                  overflow: _expanded ? null : TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, height: 1.65, color: Color(0xFFD9D6E8)),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    style: TextButton.styleFrom(foregroundColor: KairoColors.info, padding: EdgeInsets.zero),
                    child: Text(_expanded ? 'Less' : 'More'),
                  ),
                ),
                const SizedBox(height: KairoSpacing.sm),
                Row(
                  children: [
                    const Expanded(child: Text('Episodes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                    Text('$watched watched', style: const TextStyle(fontSize: 13, color: KairoColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: KairoSpacing.sm),
                for (var ep = 1; ep <= anime.episodes.clamp(0, 12); ep++)
                  _EpisodeRow(
                    anime: anime,
                    episode: ep,
                    watched: ep <= watched,
                    file: files.where((f) => f.episode == ep).firstOrNull,
                    progress: progress?.episode == ep ? progress : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityBanner extends StatelessWidget {
  const _AvailabilityBanner({required this.count, required this.total});

  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final has = count > 0;
    final color = has ? KairoColors.success : KairoColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(KairoRadii.card),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              has ? '$count of $total episodes are in your library' : 'No episodes in your library yet',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({required this.status, required this.onSelected});

  final ListStatus? status;
  final ValueChanged<ListStatus> onSelected;

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
        for (final s in ListStatus.values) MenuItemButton(onPressed: () => onSelected(s), child: Text(s.label)),
      ],
      builder: (context, controller, _) => OutlinedButton.icon(
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        style: OutlinedButton.styleFrom(foregroundColor: _color, side: BorderSide(color: _color), minimumSize: const Size(0, 48)),
        icon: Icon(status == null ? Icons.bookmark_add_outlined : Icons.bookmark_rounded, size: 18),
        label: Text(status?.label ?? 'Add to list'),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.anime, required this.episode, required this.watched, this.file, this.progress});

  final Anime anime;
  final int episode;
  final bool watched;
  final LibraryFile? file;
  final PlaybackProgress? progress;

  @override
  Widget build(BuildContext context) {
    final canPlay = file?.state == FileState.matched;
    final (String label, Color color) = switch ((file?.state, watched, progress)) {
      (FileState.missing, _, _) => ('File missing · relink in Library', KairoColors.accent),
      (_, _, final PlaybackProgress p) when canPlay => ('${(p.remaining.inSeconds / 60).ceil()} min left · In library', KairoColors.info),
      (_, true, _) => ('Watched', KairoColors.success),
      (FileState.matched, false, _) => ('In library', KairoColors.textSecondary),
      _ => ('Not in library', KairoColors.textSecondary),
    };
    final fraction = progress?.fraction ?? (watched ? 1.0 : 0.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: KairoSpacing.sm),
      child: Material(
        color: KairoColors.surface,
        borderRadius: BorderRadius.circular(KairoRadii.card),
        child: Padding(
          padding: const EdgeInsets.all(KairoSpacing.sm),
          child: Row(
            children: [
              SizedBox(
                width: 96,
                height: 56,
                child: CoverArt(
                  anime: anime,
                  radius: 8,
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: FractionallySizedBox(
                      widthFactor: fraction,
                      child: Container(height: 3, color: KairoColors.accent),
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
                    const SizedBox(height: 2),
                    Text(label, style: TextStyle(fontSize: 12, color: color)),
                  ],
                ),
              ),
              if (canPlay)
                IconButton.filledTonal(
                  tooltip: 'Play episode $episode',
                  onPressed: () => context.push(Routes.player(anime.id, episode)),
                  icon: const Icon(Icons.play_arrow_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
